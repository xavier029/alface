import AppKit
import EventKit
import IOBluetooth
import IOKit.ps

// MARK: - Bateria (IOPS)

final class Battery {
    struct State { var level: Int; var charging: Bool; var ac: Bool }
    var onEvent: ((Peek) -> Void)?
    private var last: State?
    private var warned = false

    func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            Unmanaged<Battery>.fromOpaque(ctx!).takeUnretainedValue().check()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        last = Self.read()
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            guard ProcessInfo.processInfo.isLowPowerModeEnabled, Prefs.bool(K.enableBattery), Prefs.bool(K.notifyLowPowerMode),
                  let s = Self.read() else { return }
            self?.onEvent?(.battery(s.level, .lowPower))
        }
    }

    static func read() -> State? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d["Type"] as? String == "InternalBattery" else { continue }
            let cur = d["Current Capacity"] as? Int ?? 0, max = d["Max Capacity"] as? Int ?? 100
            return State(level: max > 0 ? cur * 100 / max : cur, charging: d["Is Charging"] as? Bool ?? false,
                         ac: d["Power Source State"] as? String == "AC Power")
        }
        return nil
    }

    private func check() {
        guard let s = Self.read() else { return }
        defer { last = s }
        guard Prefs.bool(K.enableBattery) else { return }
        if let l = last, !l.ac && s.ac {
            onEvent?(.battery(s.level, .charging))
            warned = false
            return
        }
        let threshold = Prefs.d.integer(forKey: K.lowBatteryThreshold)
        if s.ac || s.level > threshold { warned = false }
        if !s.ac && s.level <= threshold && !warned && Prefs.bool(K.warnOnLowBattery) {
            warned = true
            onEvent?(.battery(s.level, .low))
            if Prefs.bool(K.playSoundOnLowBattery) { NSSound(named: "Sosumi")?.play() }
        }
    }
}

// MARK: - Bluetooth (fones conectando)

final class Bluetooth: NSObject {
    var onEvent: ((Peek) -> Void)?
    private var note: IOBluetoothUserNotification?
    private var started = Date()

    func start() {
        started = Date()
        note = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    @objc private func connected(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // o registro avisa na hora sobre os aparelhos que já estavam conectados
        guard Date().timeIntervalSince(started) > 3, Prefs.bool(K.enableConnectivity) else { return }
        let name = device.name ?? "Bluetooth"
        let audio = device.deviceClassMajor == kBluetoothDeviceClassMajorAudio
        guard audio || Self.symbol(for: name) != "headphones" else { return }
        // a bateria dos fones chega uns instantes depois da conexão
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let battery = Prefs.bool(K.showConnectivityBattery) ? Self.battery(of: device) : nil
            self?.onEvent?(.bluetooth(name, Self.symbol(for: name), battery))
        }
    }

    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// bateria pelas propriedades privadas do IOBluetoothDevice (0 = desconhecida)
    static func battery(of d: IOBluetoothDevice) -> Int? {
        var vals: [Int] = []
        for k in ["batteryPercentSingle", "batteryPercentLeft", "batteryPercentRight"] where d.responds(to: Selector(k)) {
            if let v = d.value(forKey: k) as? Int, v > 0 { vals.append(v) }
        }
        return vals.min()
    }
}

// MARK: - Calendário (EventKit)

final class Agenda: ObservableObject {
    static let shared = Agenda()
    let store = EKEventStore()
    @Published var events: [EKEvent] = []
    @Published var authorized = false
    private var timer: Timer?

    func start() {
        guard Prefs.bool(K.enableCalendar) else { return }
        store.requestFullAccessToEvents { ok, _ in
            DispatchQueue.main.async {
                self.authorized = ok
                guard ok else { return }
                self.reload()
                NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: self.store, queue: .main) { _ in self.reload() }
                self.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self.reload() }
            }
        }
    }

    func reload() {
        guard authorized else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let pred = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        events = store.events(matching: pred).filter { !$0.isAllDay && $0.endDate > now }.sorted { $0.startDate < $1.startDate }
    }
}

// MARK: - Sistema: bloqueio de tela e tela cheia

final class SystemWatch {
    var onLock: ((Bool) -> Void)?
    var onFullscreen: ((Bool) -> Void)?

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.onLock?(true) }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.onLock?(false) }
        let wc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            wc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                // o Spaces anima a troca; olha de novo depois que assenta
                self?.checkFullscreen()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.checkFullscreen() }
            }
        }
    }

    func checkFullscreen() { onFullscreen?(Self.frontIsFullscreen()) }

    /// uma janela do app da frente do tamanho exato da tela = tela cheia
    /// (janela maximizada fica com a barra de menus de fora)
    static func frontIsFullscreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != "com.apple.finder" else { return false }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let screens = NSScreen.screens.map { $0.frame.size }
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier && (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let size = CGSize(width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if (b["Y"] ?? 1) == 0 && screens.contains(size) { return true }
        }
        return false
    }
}
