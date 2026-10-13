import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--selftest") { selftest(); return }
        let app = NSApplication.shared
        let d = AppDelegate()
        app.delegate = d
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// confere as partes que não pedem permissão: `Alface --selftest`
func selftest() {
    Prefs.register()
    var fails = 0
    func check(_ name: String, _ ok: Bool, _ detail: Any = "") {
        print(ok ? "ok  " : "FALHA", name, detail)
        if !ok { fails += 1 }
    }
    let v = Volume.level
    check("volume lido", v >= 0 && v <= 1, "\(v) mudo=\(Volume.muted) saída=\(Volume.deviceName) ajustável=\(Volume.canSet)")
    check("brilho", !Brightness.available || (0...1).contains(Brightness.level), "disponível=\(Brightness.available) nível=\(Brightness.level)")
    let b = Battery.read()
    check("bateria", b == nil || (0...100).contains(b!.level), b.map { "\($0.level)% carregando=\($0.charging) tomada=\($0.ac)" } ?? "sem bateria")
    check("teclado", !KeyboardLight.available || (0...1).contains(KeyboardLight.level), "disponível=\(KeyboardLight.available) nível=\(KeyboardLight.level)")
    check("símbolo AirPods Pro", Bluetooth.symbol(for: "AirPods Pro de Gui") == "airpodspro")
    check("símbolo AirPods Max", Bluetooth.symbol(for: "AirPods Max") == "airpodsmax")
    check("símbolo genérico", Bluetooth.symbol(for: "JBL Tune") == "headphones")
    check("tela cheia (app da frente)", true, SystemWatch.frontIsFullscreen())
    let now = Date()
    check("relativo agora", relative(now.addingTimeInterval(-30), now: now) == "agora")
    check("relativo minutos", relative(now.addingTimeInterval(12 * 60), now: now) == "em 12 min")
    let m = NotchModel()
    m.notch = CGSize(width: 180, height: 32)
    check("layout fechado = notch", m.layout() == NotchLayout(width: 180, height: 32, ear: 5, bottom: 10))
    m.peek = .volume(0.5, false)
    check("layout HUD", m.layout().width == 180 + 116)
    m.expanded = true
    check("layout expandido 345x176", m.layout().width == 346 && m.layout().height == 176, m.layout())
    print(fails == 0 ? "tudo ok" : "\(fails) falha(s)")
    exit(fails == 0 ? 0 : 1)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let notch = NotchController()
    let battery = Battery()
    let bluetooth = Bluetooth()
    let system = SystemWatch()
    let nav = SettingsNav()
    let volumeWatch = VolumeWatch()
    var keyboardLevel: Float = -1
    var keyboardChangedByUs = Date.distantPast
    var lastKeyboardLevel: Float = 0.5
    var status: NSStatusItem!
    var settingsWindow: NSWindow?
    var axTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        Prefs.register()
        installMenu()
        notch.setup()

        let media = Media.shared
        // modo demonstração: nada que peça permissão (teclas, calendário, Bluetooth, AppleScript)
        let isDemo = ProcessInfo.processInfo.environment["ALFACE_DEMO"] != nil
        media.onTrackChange = { [weak self] in
            guard let self, Prefs.bool(K.showOnMediaChange), Prefs.bool(K.enableNowPlaying), !self.notch.model.expanded else { return }
            self.notch.model.show(.track, for: 3)
        }
        if !isDemo { media.start(); Agenda.shared.start() }

        battery.onEvent = { [weak self] p in self?.notch.model.show(p, for: 3) }
        battery.start()
        bluetooth.onEvent = { [weak self] p in self?.notch.model.show(p, for: 3.5) }
        if !isDemo { bluetooth.start() }

        system.onLock = { [weak self] l in self?.notch.setLocked(l) }
        system.onFullscreen = { [weak self] f in self?.notch.setFullscreen(f) }
        system.start()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            withAnimation(NotchModel.spring) { self?.notch.model.frontApp = app?.bundleIdentifier ?? "" }
        }

        if !isDemo { setupKeys() }

        // HUD também quando o volume muda fora das teclas (Central de Controle, outro app)
        let launched = Date()
        volumeWatch.onChange = { [weak self] in
            guard let self, Prefs.bool(K.enableVolume), Date().timeIntervalSince(launched) > 2 else { return }
            self.notch.model.show(.volume(Volume.level, Volume.muted), for: Prefs.double(K.hudDuration))
        }
        volumeWatch.start()

        // ponytail: brilho do teclado lido 1x/s (o CoreBrightness não tem aviso público); troque por notificação se aparecer
        if KeyboardLight.available {
            keyboardLevel = KeyboardLight.level
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.pollKeyboard() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.notch.applySettings()
            self?.notch.model.objectWillChange.send()
        }

        demo()
    }

    func pollKeyboard() {
        let v = KeyboardLight.level
        guard abs(v - keyboardLevel) > 0.004 else { return }
        keyboardLevel = v
        // mudança feita pelas nossas teclas já mostrou o HUD
        guard Prefs.bool(K.enableKeyboardBrightness), Date().timeIntervalSince(keyboardChangedByUs) > 1 else { return }
        notch.model.show(.keyboard(v), for: Prefs.double(K.hudDuration))
    }

    // MARK: teclas de volume e brilho

    func setupKeys() {
        MediaKeys.shared.handler = { [weak self] key, flags, down in
            guard let self else { return false }
            let fine = flags.contains(.option) && flags.contains(.shift)
            let step: Float = fine ? 1 / 64 : 1 / 16
            let duration = Prefs.double(K.hudDuration)
            switch key {
            case .volUp, .volDown, .mute:
                guard Prefs.bool(K.enableVolume), Volume.canSet else { return false }
                guard down else { return true }
                if key == .mute {
                    Volume.muted.toggle()
                } else {
                    var v = (Volume.level / step).rounded() * step + (key == .volUp ? step : -step)
                    v = max(0, min(1, v))
                    if key == .volUp && Volume.muted { Volume.muted = false }
                    Volume.level = v
                }
                self.notch.model.show(.volume(Volume.level, Volume.muted), for: duration)
                return true
            case .brightUp, .brightDown:
                guard Prefs.bool(K.enableBrightness), Brightness.available else { return false }
                guard down else { return true }
                let v = (Brightness.level / step).rounded() * step + (key == .brightUp ? step : -step)
                Brightness.level = max(0, min(1, v))
                self.notch.model.show(.brightness(Brightness.level), for: duration)
                return true
            case .kbUp, .kbDown, .kbToggle:
                guard Prefs.bool(K.enableKeyboardBrightness), KeyboardLight.available else { return false }
                guard down else { return true }
                let cur = KeyboardLight.level
                var v: Float
                if key == .kbToggle {
                    if cur > 0 { self.lastKeyboardLevel = cur; v = 0 } else { v = self.lastKeyboardLevel }
                } else {
                    v = (cur / step).rounded() * step + (key == .kbUp ? step : -step)
                }
                KeyboardLight.level = max(0, min(1, v))
                self.keyboardChangedByUs = Date()
                self.keyboardLevel = KeyboardLight.level
                self.notch.model.show(.keyboard(KeyboardLight.level), for: duration)
                return true
            }
        }
        if !MediaKeys.shared.start() {
            // pede Acessibilidade uma vez e tenta de novo até ser liberada
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            axTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                if MediaKeys.shared.start() { t.invalidate(); self?.axTimer = nil }
            }
        }
    }

    // MARK: menu e ajustes

    func installMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Alface")
        let m = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let v = NSMenuItem(title: "Versão \(version)", action: nil, keyEquivalent: "")
        v.isEnabled = false
        m.addItem(v)
        m.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Sair do Alface", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = m

        // menu principal (só aparece com a janela de ajustes aberta): ⌘W/⌘Q
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Fechar janela", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Sair do Alface", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 687),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: SettingsRoot(nav: nav))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) {
        if (n.object as? NSWindow) === settingsWindow { NSApp.setActivationPolicy(.accessory) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: demonstração (testes): ALFACE_DEMO=expanded|volume|brightness|charging|low|bt|lock|track|compact
    //                                ALFACE_SETTINGS=<aba>  abre os ajustes nessa aba

    func demo() {
        let env = ProcessInfo.processInfo.environment
        if let t = env["ALFACE_SETTINGS"], let tab = Tab(rawValue: t) {
            nav.tab = tab
            openSettings()
        }
        guard let d = env["ALFACE_DEMO"] else { return }
        let media = Media.shared
        media.source = .spotify
        media.title = env["ALFACE_DEMO_TITLE"] ?? "Montagem Nada Tropica"
        media.artist = "Eternxlkz"
        media.duration = 118
        media.position = 76
        media.playing = env["ALFACE_DEMO_PLAYING"] != nil
        if let path = env["ALFACE_DEMO_ART"], let img = NSImage(contentsOfFile: path) {
            media.artwork = img
            if let c = Media.accent(of: img) { media.tint = c }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            let m = notch.model, forever = 1e6
            switch d {
            case "expanded":
                withAnimation { m.expanded = true }
                notch.updateBlurMask()
                if Prefs.bool(K.progressiveBlur) { notch.blurPanel.alphaValue = 1 }
            case "volume": m.show(.volume(0.56, false), for: forever)
            case "brightness": m.show(.brightness(0.75), for: forever)
            case "charging": m.show(.battery(Battery.read()?.level ?? 80, .charging), for: forever)
            case "low": m.show(.battery(12, .low), for: forever)
            case "bt": m.show(.bluetooth("AirPods Pro", "airpodspro", 84, low: false), for: forever)
            case "btlow": m.show(.bluetooth("AirPods Pro", "airpodspro", 12, low: true), for: forever)
            case "keyboard": m.show(.keyboard(0.5), for: forever)
            case "lock": withAnimation { m.locked = true }
            case "track": m.show(.track, for: forever)
            default: break
            }
        }
    }
}
