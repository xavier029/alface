import AppKit
import EventKit
import SwiftUI

// MARK: - Estado

enum BatteryEvent: Equatable { case charging, low, lowPower }

/// notificação curta que aparece nas "asas" do notch
enum Peek: Equatable {
    case volume(Float, Bool)
    case brightness(Float)
    case battery(Int, BatteryEvent)
    case bluetooth(String, String, Int?)
    case lock(Bool)
    case track
}

struct NotchLayout: Equatable {
    var width: CGFloat      // corpo (sem as orelhas)
    var height: CGFloat
    var ear: CGFloat        // curva côncava que liga o notch à barra de menus
    var bottom: CGFloat     // raio dos cantos de baixo
    var total: CGFloat { width + 2 * ear }
}

final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var peek: Peek?
    @Published var notch = CGSize(width: 185, height: 32)
    @Published var locked = false
    @Published var hidden = false
    @Published var sourceActive = false
    @Published var tick = Date()   // atualiza a atividade do calendário
    private var peekWork: DispatchWorkItem?

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    func show(_ p: Peek, for seconds: Double) {
        withAnimation(Self.spring) { peek = p }
        peekWork?.cancel()
        let w = DispatchWorkItem { [weak self] in withAnimation(Self.spring) { self?.peek = nil } }
        peekWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    var showsCompactMedia: Bool {
        let m = Media.shared
        return Prefs.bool(K.enableNowPlaying) && Prefs.string(K.idleActivity) == "playing"
            && m.hasMedia && m.playing && !(Prefs.bool(K.hideWhileSourceActive) && sourceActive)
    }

    /// próximo evento que vale mostrar no notch (em andamento ou nos próximos 60 min)
    var compactEvent: EKEvent? {
        guard Prefs.bool(K.enableCalendar), Prefs.string(K.idleActivity) == "calendar" else { return nil }
        return Agenda.shared.events.first { $0.startDate.timeIntervalSince(tick) < 3600 }
    }

    func layout() -> NotchLayout {
        let nw = notch.width, nh = notch.height
        if expanded { return .init(width: max(345, nw + 166), height: 176, ear: 14, bottom: 36) }
        func wings(_ w: CGFloat, _ h: CGFloat? = nil) -> NotchLayout { .init(width: nw + 2 * w, height: h ?? nh, ear: 8, bottom: 13) }
        if let p = peek {
            switch p {
            case .volume, .brightness: return wings(58)
            case .battery: return wings(88)
            case .bluetooth: return wings(68)
            case .lock: return wings(36)
            case .track: return .init(width: nw + 2 * 46, height: nh + 30, ear: 10, bottom: 18)
            }
        }
        if locked { return wings(36) }
        if showsCompactMedia { return wings(44) }
        if compactEvent != nil { return wings(74) }
        return .init(width: nw, height: nh, ear: 5, bottom: 10)
    }
}

// MARK: - Formato

struct NotchShape: Shape {
    var ear: CGFloat
    var bottom: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(ear, bottom) }
        set { ear = newValue.first; bottom = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        let e = ear, b = min(bottom, r.height / 2, (r.width - 2 * ear) / 2), k: CGFloat = 0.42
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + e, y: r.minY + e), control: CGPoint(x: r.minX + e, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + e, y: r.maxY - b))
        p.addCurve(to: CGPoint(x: r.minX + e + b, y: r.maxY),
                   control1: CGPoint(x: r.minX + e, y: r.maxY - b * k), control2: CGPoint(x: r.minX + e + b * k, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e - b, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX - e, y: r.maxY - b),
                   control1: CGPoint(x: r.maxX - e - b * k, y: r.maxY), control2: CGPoint(x: r.maxX - e, y: r.maxY - b * k))
        p.addLine(to: CGPoint(x: r.maxX - e, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - e, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Raiz

struct NotchRoot: View {
    @ObservedObject var m: NotchModel
    @ObservedObject var media = Media.shared
    @ObservedObject var agenda = Agenda.shared
    @AppStorage(K.contrastOutline) var outline = true
    var onTap: () -> Void = {}

    var body: some View {
        let L = m.layout()
        let shape = NotchShape(ear: L.ear, bottom: L.bottom)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            shape.stroke(Color.white.opacity(outline && m.expanded ? 0.13 : 0), lineWidth: 1)
            content(L)
                .frame(width: L.width, height: L.height, alignment: .top)
                .frame(width: L.total, height: L.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: L.total, height: L.height)
        .contentShape(shape)
        .onTapGesture { onTap() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(m.hidden ? 0 : 1)
        .animation(NotchModel.spring, value: L)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder func content(_ L: NotchLayout) -> some View {
        let nw = m.notch.width, nh = m.notch.height
        if m.expanded {
            Group {
                if media.hasMedia && Prefs.bool(K.enableNowPlaying) { ExpandedMedia() }
                else if Prefs.bool(K.enableCalendar) && agenda.authorized { ExpandedCalendar() }
                else { ExpandedEmpty() }
            }
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(NotchModel.spring.delay(0.05)),
                                    removal: .opacity.animation(.easeOut(duration: 0.12))))
        } else if let p = m.peek {
            PeekView(peek: p, notchWidth: nw, notchHeight: nh)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .id(peekID(p))
        } else if m.locked {
            Wings(notchWidth: nw, height: nh) {
                Image(systemName: "lock.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            } right: { EmptyView() }
            .transition(.opacity)
        } else if m.showsCompactMedia {
            Wings(notchWidth: nw, height: nh) {
                Artwork(image: media.artwork, size: 22, radius: 6)
            } right: {
                if !Prefs.bool(K.disableCompactWaveform) {
                    Waveform(playing: media.playing, color: waveColor, bars: 4, maxHeight: 14)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        } else if let e = m.compactEvent {
            Wings(notchWidth: nw, height: nh) {
                HStack(spacing: 5) {
                    Circle().fill(Color(cgColor: e.calendar.cgColor)).frame(width: 7, height: 7)
                    Text(e.title ?? "").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                }.padding(.leading, 6)
            } right: {
                Text(relative(e.startDate, now: m.tick)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Color(cgColor: e.calendar.cgColor))
            }
            .transition(.opacity)
        }
    }

    var waveColor: Color { Prefs.string(K.colorStyle) == "mono" ? .white.opacity(0.8) : media.tint }

    func peekID(_ p: Peek) -> String {
        switch p {
        case .volume: return "vol"
        case .brightness: return "bri"
        case .battery(_, let e): return "bat\(e)"
        case .bluetooth(let n, _, _): return "bt\(n)"
        case .lock(let l): return "lock\(l)"
        case .track: return "track\(media.title)"
        }
    }
}

func relative(_ d: Date, now: Date) -> String {
    let m = Int((d.timeIntervalSince(now) / 60).rounded(.up))
    if m <= 0 { return "agora" }
    return m < 60 ? "em \(m) min" : "em \(m / 60) h"
}

/// conteúdo dos dois lados do notch físico
struct Wings<L: View, R: View>: View {
    var notchWidth: CGFloat
    var height: CGFloat
    @ViewBuilder var left: L
    @ViewBuilder var right: R
    var body: some View {
        HStack(spacing: 0) {
            left.frame(maxWidth: .infinity)
            Color.clear.frame(width: notchWidth)
            right.frame(maxWidth: .infinity)
        }
        .frame(height: height)
    }
}

// MARK: - Peças

struct Artwork: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var body: some View {
        ZStack {
            if let i = image {
                Image(nsImage: i).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: radius).fill(Color.white.opacity(0.12))
                Image(systemName: "music.note").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// barrinhas animadas; pausado vira uma fila de pontinhos (como no Alcove)
struct Waveform: View {
    var playing: Bool
    var color: Color
    var bars: Int
    var maxHeight: CGFloat
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { t in
            let time = t.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule().fill(color)
                        .frame(width: 3, height: playing ? height(i, time) : 3)
                }
            }
            .frame(height: maxHeight)
            .animation(.easeOut(duration: 0.25), value: playing)
        }
    }
    func height(_ i: Int, _ t: Double) -> CGFloat {
        let d = Double(i)
        let v = 0.5 + 0.3 * sin(t * (5.1 + d * 1.3) + d * 1.7) + 0.2 * sin(t * (8.3 - d * 0.9) + d * 0.6)
        return 3 + (maxHeight - 3) * CGFloat(max(0, min(1, v)))
    }
}

struct Bar: View {
    var value: Double
    var color: Color = .white
    var track: Color = .white.opacity(0.22)
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(g.size.height, g.size.width * CGFloat(max(0, min(1, value)))))
                    .opacity(value <= 0 ? 0 : 1)
            }
        }
    }
}

struct BatteryGlyph: View {
    var level: Int
    var color: Color
    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color)
                    .frame(width: max(2, 20 * CGFloat(level) / 100)).padding(2)
            }
            .frame(width: 25, height: 12)
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.35)).frame(width: 1.5, height: 4)
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IconButton: View {
    var symbol: String
    var size: CGFloat
    var color: Color = .white
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(color)
                .frame(width: 44, height: 36)
                .background(Circle().fill(Color.white.opacity(hover ? 0.1 : 0)).frame(width: 40, height: 40))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
    }
}

// MARK: - Notificações curtas

struct PeekView: View {
    var peek: Peek
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    @ObservedObject var media = Media.shared
    @AppStorage(K.hudProgressStyle) var progressStyle = "white"
    @AppStorage(K.showVolumePercentage) var volPct = false
    @AppStorage(K.showBrightnessPercentage) var briPct = false
    @AppStorage(K.hideBatteryPercentage) var hideBatPct = false

    var hudColor: Color { progressStyle == "accent" ? .accentColor : .white }
    static let green = Color(red: 0.2, green: 0.84, blue: 0.36)

    var body: some View {
        switch peek {
        case .volume(let v, let muted):
            hud(symbol: muted || v == 0 ? "speaker.slash.fill" : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill",
                value: muted ? 0 : Double(v), percent: volPct)
        case .brightness(let v):
            hud(symbol: v < 0.5 ? "sun.min.fill" : "sun.max.fill", value: Double(v), percent: briPct)
        case .battery(let level, let e):
            let (label, color): (String, Color) = e == .charging ? ("Carregando", Self.green)
                : e == .low ? ("Bateria fraca", Color(red: 1, green: 0.27, blue: 0.23)) : ("Pouca energia", Color(red: 1, green: 0.8, blue: 0.1))
            Wings(notchWidth: notchWidth, height: notchHeight) {
                HStack(spacing: 4) {
                    if e == .charging { Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold)) }
                    Text(label).font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(color)
            } right: {
                HStack(spacing: 6) {
                    if !hideBatPct { Text("\(level)%").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.white) }
                    BatteryGlyph(level: level, color: color)
                }
            }
        case .bluetooth(_, let symbol, let battery):
            Wings(notchWidth: notchWidth, height: notchHeight) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
            } right: {
                if let b = battery {
                    HStack(spacing: 5) {
                        Text("\(b)%").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                        ZStack {
                            Circle().stroke(Self.green.opacity(0.25), lineWidth: 2.5)
                            Circle().trim(from: 0, to: CGFloat(b) / 100).stroke(Self.green, style: .init(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                        }
                        .frame(width: 15, height: 15)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Self.green)
                }
            }
        case .lock(let locked):
            Wings(notchWidth: notchWidth, height: notchHeight) {
                Image(systemName: locked ? "lock.fill" : "lock.open.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            } right: { EmptyView() }
        case .track:
            VStack(spacing: 0) {
                Wings(notchWidth: notchWidth, height: notchHeight) {
                    Artwork(image: media.artwork, size: 22, radius: 6)
                } right: {
                    Waveform(playing: media.playing, color: Prefs.string(K.colorStyle) == "mono" ? .white.opacity(0.8) : media.tint, bars: 4, maxHeight: 14)
                }
                Text(media.artist.isEmpty ? media.title : "\(media.title) — \(media.artist)")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).padding(.horizontal, 18).frame(height: 24)
            }
        }
    }

    func hud(symbol: String, value: Double, percent: Bool) -> some View {
        Wings(notchWidth: notchWidth, height: notchHeight) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace)).frame(width: 24)
        } right: {
            if percent {
                Text("\(Int((value * 100).rounded()))").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
            } else {
                Bar(value: value, color: hudColor).frame(width: 38, height: 5)
                    .animation(.spring(response: 0.25, dampingFraction: 0.9), value: value)
            }
        }
    }
}

// MARK: - Expandido

struct ExpandedMedia: View {
    @ObservedObject var media = Media.shared
    @State private var scrub: Double?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                Artwork(image: media.artwork, size: 46, radius: 10)
                    .onTapGesture { media.openSource() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(media.title.isEmpty ? "Sem título" : media.title)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Text(media.artist).font(.system(size: 14)).foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                .padding(.leading, 22).padding(.trailing, 40)
                Spacer(minLength: 0)
            }
            .overlay(alignment: .topTrailing) {
                Waveform(playing: media.playing, color: Prefs.string(K.colorStyle) == "mono" ? .white.opacity(0.8) : media.tint, bars: 6, maxHeight: 16)
                    .padding(.top, 15)
            }
            .frame(height: 46)
            .padding(.top, 22)

            TimelineView(.periodic(from: .now, by: 0.5)) { t in
                let now = media.elapsed(at: t.date)
                let shown = scrub.map { $0 * media.duration } ?? now
                HStack(spacing: 9) {
                    Text(fmt(shown)).frame(minWidth: 24, alignment: .leading)
                    GeometryReader { g in
                        Bar(value: media.duration > 0 ? shown / media.duration : 0, color: .white.opacity(0.55), track: .white.opacity(0.2))
                            .frame(height: scrub == nil ? 6 : 8)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { v in scrub = max(0, min(1, v.location.x / g.size.width)) }
                                .onEnded { _ in
                                    if let s = scrub, media.duration > 0 { media.seek(s * media.duration) }
                                    scrub = nil
                                })
                            .animation(.easeOut(duration: 0.15), value: scrub == nil)
                    }
                    .frame(height: 14)
                    Text("-" + fmt(max(0, media.duration - shown))).frame(minWidth: 32, alignment: .trailing)
                }
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 19)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    IconButton(symbol: "shuffle", size: 16, color: .white.opacity(media.shuffle ? 0.9 : 0.4)) { media.toggleShuffle() }
                }
                .overlay(alignment: .bottom) {
                    Circle().fill(Color.white.opacity(0.6)).frame(width: 4, height: 4).offset(y: 6).opacity(media.shuffle ? 1 : 0)
                }
                .frame(width: 66)
                IconButton(symbol: "backward.fill", size: 22) { media.previous() }.frame(width: 66)
                IconButton(symbol: media.playing ? "pause.fill" : "play.fill", size: 30) { media.toggle() }
                    .contentTransition(.symbolEffect(.replace)).frame(width: 66)
                IconButton(symbol: "forward.fill", size: 22) { media.next() }.frame(width: 66)
                IconButton(symbol: outputSymbol(), size: 17, color: .white.opacity(0.4)) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.sound")!)
                }.frame(width: 66)
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
    }

    func fmt(_ s: Double) -> String {
        let t = Int(s.isFinite ? s : 0)
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    func outputSymbol() -> String {
        let n = Volume.deviceName.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") || n.contains("headphone") || n.contains("fone") { return "headphones" }
        if n.contains("macbook") || n.contains("alto-falante") || n.contains("speaker") { return "laptopcomputer" }
        if n.contains("hdmi") || n.contains("display") || n.contains("tv") { return "tv" }
        return "hifispeaker"
    }
}

struct ExpandedCalendar: View {
    @ObservedObject var agenda = Agenda.shared
    @AppStorage(K.useCalendarColor) var useColor = true
    var body: some View {
        let now = Date()
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: -2) {
                Text(now.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23))
                Text(now.formatted(.dateTime.day())).font(.system(size: 36, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                if agenda.events.isEmpty {
                    Text("Seu dia está livre").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text("Nenhum evento hoje").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                } else {
                    ForEach(agenda.events.prefix(3), id: \.eventIdentifier) { e in
                        HStack(spacing: 8) {
                            Capsule().fill(useColor ? Color(cgColor: e.calendar.cgColor) : .white.opacity(0.6)).frame(width: 3, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.title ?? "").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                Text(e.startDate <= now ? "Agora · até \(e.endDate.formatted(date: .omitted, time: .shortened))"
                                     : "\(e.startDate.formatted(date: .omitted, time: .shortened)) – \(e.endDate.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 42).padding(.horizontal, 26)
    }
}

struct ExpandedEmpty: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
            Text("Nada tocando").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 24)
    }
}

// MARK: - Janelas

/// NSHostingView sem área segura (senão o SwiftUI empurra tudo para baixo do notch) e que aceita o primeiro clique
final class NotchHostingView<C: View>: NSHostingView<C> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchPanel: NSPanel {
    init(rect: NSRect, levelOffset: Int) {
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true   // antes do nível: isFloatingPanel redefine o nível para .floating
        // acima da proteção de tela (CGShieldingWindowLevel), como o Alcove: aparece sobre tudo
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + levelOffset)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        canBecomeVisibleWithoutLogin = true
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // sem isto o macOS empurra a janela para baixo da barra de menus
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// Space privado (SkyLight) com nível absoluto alto: mantém o notch visível na tela de bloqueio.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSpaceCreate") private func CGSSpaceCreate(_ cid: Int32, _ flag: Int32, _ opts: CFDictionary?) -> UInt64
@_silgen_name("CGSSpaceSetAbsoluteLevel") private func CGSSpaceSetAbsoluteLevel(_ cid: Int32, _ sid: UInt64, _ level: Int32)
@_silgen_name("CGSShowSpaces") private func CGSShowSpaces(_ cid: Int32, _ sids: CFArray)
@_silgen_name("CGSAddWindowsToSpaces") private func CGSAddWindowsToSpaces(_ cid: Int32, _ wids: CFArray, _ sids: CFArray)
@_silgen_name("CGSRemoveWindowsFromSpaces") private func CGSRemoveWindowsFromSpaces(_ cid: Int32, _ wids: CFArray, _ sids: CFArray)

enum LockSpace {
    static var space: UInt64 = 0
    static func attach(_ windows: [NSWindow]) {
        let cid = CGSMainConnectionID()
        if space == 0 {
            space = CGSSpaceCreate(cid, 1, nil)
            CGSSpaceSetAbsoluteLevel(cid, space, 400)   // acima da tela de bloqueio (300)
            CGSShowSpaces(cid, [NSNumber(value: space)] as CFArray)
        }
        CGSAddWindowsToSpaces(cid, windows.map { NSNumber(value: $0.windowNumber) } as CFArray, [NSNumber(value: space)] as CFArray)
    }
    static func detach(_ windows: [NSWindow]) {
        guard space != 0 else { return }
        CGSRemoveWindowsFromSpaces(CGSMainConnectionID(), windows.map { NSNumber(value: $0.windowNumber) } as CFArray, [NSNumber(value: space)] as CFArray)
    }
}

// MARK: - Controlador

final class NotchController {
    let model = NotchModel()
    static let size = NSSize(width: 640, height: 300)
    var panel: NotchPanel!
    var blurPanel: NotchPanel!
    var blurView: NSVisualEffectView!
    private var hoverWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var scrollAcc = CGSize.zero
    private var scrollFired = false
    private var fullscreen = false
    private var onLockSpace = false

    func setup() {
        panel = NotchPanel(rect: NSRect(origin: .zero, size: Self.size), levelOffset: 1)
        let host = NotchHostingView(rootView: NotchRoot(m: model, onTap: { [weak self] in self?.tapped() }))
        host.sizingOptions = []
        panel.contentView = host

        // fundo com desfoque progressivo atrás do notch expandido
        blurPanel = NotchPanel(rect: NSRect(origin: .zero, size: Self.size), levelOffset: 0)
        blurView = NSVisualEffectView()
        blurView.material = .fullScreenUI
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurPanel.contentView = blurView
        blurPanel.alphaValue = 0

        reposition()
        blurPanel.orderFrontRegardless()
        panel.orderFrontRegardless()
        applySettings()

        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in self?.mouseMoved() }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .mouseExited]) { [weak self] e in self?.mouseMoved(); return e }
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            if e.window === self?.panel { self?.scroll(e) }
            return e
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.model.tick = Date() }
    }

    var screen: NSScreen {
        let screens = NSScreen.screens
        if Prefs.string(K.displayOn) == "main" { return NSScreen.screens.first ?? NSScreen.main! }
        return screens.first { $0.safeAreaInsets.top > 0 } ?? screens.first ?? NSScreen.main!
    }

    func reposition() {
        let s = screen
        var size: CGSize
        if !Prefs.bool(K.forceSimulatedNotch), s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            size = CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        } else {
            let menuBar = s.frame.maxY - s.visibleFrame.maxY
            size = CGSize(width: 185, height: menuBar > 20 ? menuBar : 32)
        }
        size.width += Prefs.double(K.notchWidthOffset)
        size.height += Prefs.double(K.notchHeightOffset)
        if model.notch != size { model.notch = size }
        let f = NSRect(x: s.frame.midX - Self.size.width / 2, y: s.frame.maxY - Self.size.height, width: Self.size.width, height: Self.size.height)
        panel.setFrame(f, display: true)
        blurPanel.setFrame(f, display: true)
        updateBlurMask()
    }

    func applySettings() {
        reposition()
        let sharing: NSWindow.SharingType = Prefs.bool(K.hideFromCapture) ? .none : .readOnly
        panel.sharingType = sharing
        blurPanel.sharingType = sharing
        let wantLock = Prefs.bool(K.enableLockScreen)
        if wantLock != onLockSpace {
            onLockSpace = wantLock
            // só o notch: dentro do Space privado o NSVisualEffectView não enxerga o que está atrás
            wantLock ? LockSpace.attach([panel]) : LockSpace.detach([panel])
        }
        updateHidden()
    }

    // MARK: rato

    /// área ocupada pelo formato atual, em coordenadas de tela
    func hitRect() -> NSRect {
        let L = model.layout()
        let f = panel.frame
        return NSRect(x: f.midX - L.total / 2, y: f.maxY - L.height, width: L.total, height: L.height + 2)
    }

    func mouseMoved() {
        guard !model.hidden else { panel.ignoresMouseEvents = true; return }
        let p = NSEvent.mouseLocation
        let margin: CGFloat = model.expanded ? 10 : 4
        let inside = hitRect().insetBy(dx: -margin, dy: -margin).contains(p)
        panel.ignoresMouseEvents = !inside
        if inside {
            collapseWork?.cancel(); collapseWork = nil
            if !model.expanded && Prefs.bool(K.expandOnHover) && hoverWork == nil {
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.hoverWork = nil
                    if self.hitRect().insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) { self.expand() }
                }
                hoverWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.02, Prefs.double(K.hoverDuration)), execute: w)
            }
        } else {
            hoverWork?.cancel(); hoverWork = nil
            if model.expanded && collapseWork == nil {
                let w = DispatchWorkItem { [weak self] in self?.collapseWork = nil; self?.collapse() }
                collapseWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
            }
        }
    }

    func tapped() { if !model.expanded { expand() } }

    func expand() {
        guard !model.expanded, !model.hidden else { return }
        haptic()
        withAnimation(NotchModel.spring) { model.expanded = true }
        Media.shared.syncPosition()
        Agenda.shared.reload()
        updateBlurMask()
        if Prefs.bool(K.progressiveBlur) {
            NSAnimationContext.runAnimationGroup { c in c.duration = 0.3; blurPanel.animator().alphaValue = 1 }
        }
    }

    func collapse() {
        guard model.expanded else { return }
        withAnimation(NotchModel.spring) { model.expanded = false }
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.25; blurPanel.animator().alphaValue = 0 }
        panel.ignoresMouseEvents = !hitRect().contains(NSEvent.mouseLocation)
    }

    func haptic() {
        if Prefs.bool(K.haptics) { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
    }

    /// máscara de borda suave: o desfoque some aos poucos em volta do notch expandido
    func updateBlurMask() {
        let s = Self.size
        let L = NotchLayout(width: max(345, model.notch.width + 166), height: 176, ear: 14, bottom: 36)
        let feather: CGFloat = 34
        blurView.maskImage = NSImage(size: s, flipped: true) { _ in
            let steps = 18
            for i in 0..<steps {
                let t = CGFloat(i) / CGFloat(steps - 1)
                let grow = feather * (1 - t)
                let r = NSRect(x: (s.width - L.width) / 2 - grow, y: -40, width: L.width + 2 * grow, height: L.height + 40 + grow)
                NSColor.black.withAlphaComponent(1.0 / CGFloat(steps) * 1.6).setFill()
                NSBezierPath(roundedRect: r, xRadius: L.bottom + grow, yRadius: L.bottom + grow).fill()
            }
            return true
        }
    }

    // MARK: gestos

    func scroll(_ e: NSEvent) {
        if e.phase == .began { scrollAcc = .zero; scrollFired = false }
        if e.phase == .ended || e.phase == .cancelled { scrollAcc = .zero; scrollFired = false; return }
        guard !scrollFired, e.momentumPhase == [] else { return }
        scrollAcc.width += e.scrollingDeltaX
        scrollAcc.height += e.scrollingDeltaY
        let media = Media.shared
        if abs(scrollAcc.width) > 45, abs(scrollAcc.width) > abs(scrollAcc.height), Prefs.bool(K.swipeToSkip), media.hasMedia {
            scrollFired = true
            scrollAcc.width < 0 ? media.next() : media.previous()
            haptic()
        } else if abs(scrollAcc.height) > 30, Prefs.bool(K.swipeToToggle) {
            scrollFired = true
            scrollAcc.height > 0 ? expand() : collapse()
        }
    }

    // MARK: estado do sistema

    func setFullscreen(_ f: Bool) { fullscreen = f; updateHidden() }

    func setLocked(_ l: Bool) {
        withAnimation(NotchModel.spring) { model.locked = l }
        if l {
            collapse()
            if Prefs.bool(K.playSoundOnLock) { NSSound(named: "Tink")?.play() }
        } else {
            model.show(.lock(false), for: 1.4)
            if Prefs.bool(K.playSoundOnUnlock) { NSSound(named: "Pop")?.play() }
        }
        updateHidden()
    }

    func updateHidden() {
        let h = fullscreen && Prefs.bool(K.hideInFullscreen) && !model.locked
        if model.hidden != h {
            withAnimation(.easeInOut(duration: 0.2)) { model.hidden = h }
            if h { collapse() }
        }
    }
}
