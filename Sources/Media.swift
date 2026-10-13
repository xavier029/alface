import AppKit
import CoreImage
import SwiftUI

// "Tocando agora" sem APIs privadas: notificações distribuídas que o Spotify e o Music
// publicam a cada mudança + AppleScript para posição, capa e controles.
// (O Alcove lê do MediaRemote por um helper com bundle id com.apple.*; aqui não.)
final class Media: ObservableObject {
    static let shared = Media()

    enum Source: String { case spotify, music
        var bundle: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
        var app: String { self == .spotify ? "Spotify" : "Music" }
    }

    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var duration: Double = 0
    @Published var position: Double = 0      // posição no instante `stamp`
    @Published var stamp = Date()
    @Published var playing = false
    @Published var shuffle = false
    @Published var artwork: NSImage?
    @Published var tint = Color(red: 0.95, green: 0.55, blue: 0.3)
    @Published var source: Source?

    var hasMedia: Bool { source != nil && !title.isEmpty }
    /// chamado quando a faixa muda (para o "mostrar ao trocar de mídia")
    var onTrackChange: (() -> Void)?

    private var trackID = ""
    private let q = DispatchQueue(label: "alface.applescript")

    func elapsed(at d: Date = Date()) -> Double {
        let e = position + (playing ? d.timeIntervalSince(stamp) : 0)
        return max(0, duration > 0 ? min(duration, e) : e)
    }

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(spotifyChanged(_:)), name: .init("com.spotify.client.PlaybackStateChanged"), object: nil)
        dnc.addObserver(self, selector: #selector(musicChanged(_:)), name: .init("com.apple.Music.playerInfo"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let s = self?.source, app?.bundleIdentifier == s.bundle { self?.clear() }
        }
        initialState()
    }

    private func allowed(_ s: Source) -> Bool {
        let pref = Prefs.string(K.musicApp)
        return pref == "auto" || pref == s.rawValue
    }

    static func isRunning(_ s: Source) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: s.bundle).isEmpty
    }

    // MARK: notificações

    @objc private func spotifyChanged(_ n: Notification) {
        guard allowed(.spotify) else { return }
        let u = n.userInfo ?? [:]
        let state = u["Player State"] as? String ?? ""
        if state == "Stopped" { if source == .spotify { clear() }; return }
        // com outra fonte tocando, uma pausa no Spotify não rouba a tela
        if source == .music && playing && state != "Playing" { return }
        apply(.spotify,
              id: u["Track ID"] as? String ?? "",
              title: u["Name"] as? String ?? "",
              artist: u["Artist"] as? String ?? "",
              album: u["Album"] as? String ?? "",
              duration: (u["Duration"] as? Double ?? 0) / 1000,
              position: u["Playback Position"] as? Double,
              playing: state == "Playing")
    }

    @objc private func musicChanged(_ n: Notification) {
        guard allowed(.music) else { return }
        let u = n.userInfo ?? [:]
        let state = u["Player State"] as? String ?? ""
        if state == "Stopped" { if source == .music { clear() }; return }
        if source == .spotify && playing && state != "Playing" { return }
        let pid = (u["PersistentID"] as? NSNumber)?.stringValue ?? (u["Persistent ID"] as? NSNumber)?.stringValue ?? (u["Name"] as? String ?? "")
        apply(.music,
              id: pid,
              title: u["Name"] as? String ?? "",
              artist: u["Artist"] as? String ?? "",
              album: u["Album"] as? String ?? "",
              duration: (u["Total Time"] as? Double ?? 0) / 1000,
              position: nil,
              playing: state == "Playing")
    }

    private func apply(_ s: Source, id: String, title: String, artist: String, album: String,
                       duration: Double, position: Double?, playing: Bool) {
        let changed = id != trackID || s != source
        withAnimation(.easeInOut(duration: 0.25)) {
            self.source = s
            self.title = title
            self.artist = artist
            self.album = album
            if duration > 0 { self.duration = duration }
            if let p = position { self.position = p; self.stamp = Date() }
            else if changed { self.position = 0; self.stamp = Date() }
            else { self.position = elapsed(); self.stamp = Date() }
            self.playing = playing
        }
        if changed {
            trackID = id
            artwork = nil
            fetchExtras()
            if playing { onTrackChange?() }
        } else if position == nil {
            syncPosition()
        }
    }

    func clear() {
        withAnimation(.easeInOut(duration: 0.25)) {
            source = nil; title = ""; artist = ""; album = ""; duration = 0; position = 0
            playing = false; artwork = nil
        }
        trackID = ""
    }

    // MARK: AppleScript

    @discardableResult
    private func script(_ src: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        return NSAppleScript(source: src)?.executeAndReturnError(&err)
    }

    /// estado inicial ao abrir o app (só pergunta a apps já abertos, para não abri-los)
    private func initialState() {
        q.async { [self] in
            for s in [Source.spotify, .music] where Self.isRunning(s) && allowed(s) {
                let src = s == .spotify
                    ? "tell application \"Spotify\" to return {name of current track, artist of current track, album of current track, (duration of current track) / 1000, player position, player state as string, id of current track}"
                    : "tell application \"Music\" to return {name of current track, artist of current track, album of current track, duration of current track, player position, player state as string, (persistent ID of current track) as string}"
                guard let r = script(src), r.numberOfItems >= 7 else { continue }
                let state = r.atIndex(6)?.stringValue ?? ""
                if state == "stopped" { continue }
                let vals = (1...7).map { r.atIndex($0) }
                DispatchQueue.main.async {
                    self.apply(s, id: vals[6]?.stringValue ?? "",
                               title: vals[0]?.stringValue ?? "", artist: vals[1]?.stringValue ?? "",
                               album: vals[2]?.stringValue ?? "",
                               duration: vals[3]?.doubleValue ?? 0, position: vals[4]?.doubleValue ?? 0,
                               playing: state == "playing")
                }
                if state == "playing" { return }
            }
        }
    }

    /// capa, posição e aleatório da faixa atual
    private func fetchExtras() {
        guard let s = source else { return }
        let id = trackID
        q.async { [self] in
            var shuffleOn = false
            var art: NSImage?
            if s == .spotify {
                if let r = script("tell application \"Spotify\" to return {artwork url of current track, player position, shuffling}") {
                    if let u = r.atIndex(1)?.stringValue, let url = URL(string: u), let d = try? Data(contentsOf: url) { art = NSImage(data: d) }
                    if let p = r.atIndex(2)?.doubleValue { DispatchQueue.main.async { self.position = p; self.stamp = Date() } }
                    shuffleOn = r.atIndex(3)?.booleanValue ?? false
                }
            } else {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("alface-art-\(UUID().uuidString)")
                let src = """
                tell application "Music"
                    set p to player position
                    set sh to shuffle enabled
                    try
                        set d to raw data of artwork 1 of current track
                        set f to open for access (POSIX file "\(tmp.path)") with write permission
                        set eof f to 0
                        write d to f
                        close access f
                    end try
                    return {p, sh}
                end tell
                """
                if let r = script(src) {
                    if let p = r.atIndex(1)?.doubleValue { DispatchQueue.main.async { self.position = p; self.stamp = Date() } }
                    shuffleOn = r.atIndex(2)?.booleanValue ?? false
                }
                if let d = try? Data(contentsOf: tmp) { art = NSImage(data: d) }
                try? FileManager.default.removeItem(at: tmp)
            }
            let color = art.flatMap(Self.accent(of:))
            DispatchQueue.main.async {
                guard id == self.trackID else { return }
                self.shuffle = shuffleOn
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.artwork = art
                    if let c = color { self.tint = c }
                }
            }
        }
    }

    /// acerta a posição (chamado ao expandir, a extrapolação acumula erro)
    func syncPosition() {
        guard let s = source else { return }
        q.async { [self] in
            guard let r = script("tell application \"\(s.app)\" to return player position"), let p = Optional(r.doubleValue) else { return }
            DispatchQueue.main.async { self.position = p; self.stamp = Date() }
        }
    }

    // MARK: controles

    func toggle() { send("playpause"); withAnimation { position = elapsed(); stamp = Date(); playing.toggle() } }
    func next() { send("next track") }
    func previous() { send("previous track") }
    func seek(_ t: Double) {
        position = t; stamp = Date()
        send("set player position to \(t)")
    }
    func toggleShuffle() {
        guard let s = source else { return }
        shuffle.toggle()
        send(s == .spotify ? "set shuffling to \(shuffle)" : "set shuffle enabled to \(shuffle)")
    }
    func openSource() {
        guard let s = source, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: s.bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func send(_ cmd: String) {
        guard let s = source, Self.isRunning(s) else { return }
        q.async { [self] in script("tell application \"\(s.app)\" to \(cmd)") }
    }

    // MARK: cor da capa

    static let ci = CIContext(options: [.workingColorSpace: NSNull()])
    /// cor média da capa, clareada para servir de destaque sobre o preto
    static func accent(of img: NSImage) -> Color? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        guard let f = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]),
              let out = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        ci.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let c = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let sat = s < 0.12 ? s : min(1, s * 1.25 + 0.1)
        return Color(nsColor: NSColor(hue: h, saturation: sat, brightness: max(b, 0.82), alpha: 1))
    }
}
