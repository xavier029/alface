import AppKit
import ServiceManagement
import SwiftUI

// Janela de ajustes no layout do Alcove: barra lateral com ícones coloridos + cartões agrupados.

enum Tab: String, CaseIterable, Identifiable {
    case general, battery, connectivity, display, sound, nowPlaying, calendar, lockScreen, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "Geral"
        case .battery: "Bateria"
        case .connectivity: "Conectividade"
        case .display: "Tela"
        case .sound: "Som"
        case .nowPlaying: "Tocando agora"
        case .calendar: "Calendário"
        case .lockScreen: "Tela de bloqueio"
        case .about: "Sobre"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .battery: "bolt.fill"
        case .connectivity: "headphones"
        case .display: "sun.max.fill"
        case .sound: "speaker.wave.2.fill"
        case .nowPlaying: "play.fill"
        case .calendar: "calendar"
        case .lockScreen: "lock.fill"
        case .about: "info"
        }
    }
    var colors: [Color] {
        switch self {
        case .general: [Color(white: 0.62), Color(white: 0.48)]
        case .battery: [Color(red: 1, green: 0.62, blue: 0.35), Color(red: 0.98, green: 0.42, blue: 0.24)]
        case .connectivity: [Color(red: 0.42, green: 0.86, blue: 0.62), Color(red: 0.2, green: 0.72, blue: 0.5)]
        case .display: [Color(red: 0.78, green: 0.56, blue: 1), Color(red: 0.6, green: 0.38, blue: 0.95)]
        case .sound: [Color(red: 0.95, green: 0.55, blue: 0.95), Color(red: 0.84, green: 0.36, blue: 0.86)]
        case .nowPlaying: [Color(red: 1, green: 0.42, blue: 0.5), Color(red: 0.93, green: 0.22, blue: 0.33)]
        case .calendar: [.white, Color(white: 0.94)]
        case .lockScreen: [Color(white: 0.38), Color(white: 0.2)]
        case .about: [Color(white: 0.62), Color(white: 0.48)]
        }
    }
}

final class SettingsNav: ObservableObject {
    @Published var tab: Tab = .general
}

struct IconTile: View {
    var tab: Tab
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: tab.colors, startPoint: .top, endPoint: .bottom))
            if tab == .calendar {
                VStack(spacing: 0) {
                    Rectangle().fill(Color(red: 0.98, green: 0.3, blue: 0.3)).frame(height: size * 0.27)
                    Text(Date().formatted(.dateTime.day())).font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(.black.opacity(0.75))
                        .frame(maxHeight: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).stroke(Color.black.opacity(0.1), lineWidth: 0.5))
            } else {
                Image(systemName: tab.symbol).font(.system(size: size * 0.52, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
    }
}

struct SettingsRoot: View {
    @ObservedObject var nav: SettingsNav
    var body: some View {
        HStack(spacing: 0) {
            Sidebar(nav: nav)
                .frame(width: 225)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    IconTile(tab: nav.tab, size: 22)
                    Text(nav.tab.title).font(.system(size: 15, weight: .semibold))
                }
                .padding(.leading, 18).frame(height: 52)
                ScrollView {
                    page.padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .frame(width: 620, height: 687)
    }

    @ViewBuilder var page: some View {
        switch nav.tab {
        case .general: GeneralPage()
        case .battery: BatteryPage()
        case .connectivity: ConnectivityPage()
        case .display: DisplayPage()
        case .sound: SoundPage()
        case .nowPlaying: NowPlayingPage()
        case .calendar: CalendarPage()
        case .lockScreen: LockScreenPage()
        case .about: AboutPage()
        }
    }
}

struct Sidebar: View {
    @ObservedObject var nav: SettingsNav
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer().frame(height: 46)
            row(.general)
            header("Notificações")
            row(.battery); row(.connectivity); row(.display); row(.sound)
            header("Atividades ao vivo")
            row(.nowPlaying); row(.calendar); row(.lockScreen)
            header("Alface")
            row(.about)
            Spacer()
        }
        .padding(.horizontal, 12)
    }
    func header(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 8).padding(.top, 18).padding(.bottom, 4)
    }
    func row(_ t: Tab) -> some View {
        Button { nav.tab = t } label: {
            HStack(spacing: 9) {
                IconTile(tab: t)
                Text(t.title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(nav.tab == t ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Componentes

struct Card<C: View>: View {
    var title: String?
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = title { Text(t).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 8).padding(.top, 12) }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.09), lineWidth: 1))
        }
    }
}

struct Row<C: View>: View {
    var label: String
    var info: String? = nil
    var divider = true
    @ViewBuilder var control: C
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 13))
                    if let i = info { Text(i).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Spacer()
                control
            }
            .padding(.horizontal, 12).frame(minHeight: 42)
            if divider { Divider().padding(.leading, 12) }
        }
    }
}

struct ToggleRow: View {
    var label: String
    var key: String
    var info: String? = nil
    var divider = true
    @AppStorage private var on: Bool
    init(_ label: String, _ key: String, info: String? = nil, divider: Bool = true) {
        self.label = label; self.key = key; self.info = info; self.divider = divider
        _on = AppStorage(wrappedValue: false, key)
    }
    var body: some View {
        Row(label: label, info: info, divider: divider) {
            Toggle("", isOn: $on).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}

struct PickerRow: View {
    var label: String
    var options: [(String, String)]
    var divider = true
    @AppStorage private var value: String
    init(_ label: String, _ key: String, _ options: [(String, String)], divider: Bool = true) {
        self.label = label; self.options = options; self.divider = divider
        _value = AppStorage(wrappedValue: options.first?.0 ?? "", key)
    }
    var body: some View {
        Row(label: label, divider: divider) {
            Picker("", selection: $value) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden().fixedSize()
        }
    }
}

struct SliderRow: View {
    var label: String
    var range: ClosedRange<Double>
    var step: Double
    var unit: String
    var divider = true
    @AppStorage private var value: Double
    init(_ label: String, _ key: String, _ range: ClosedRange<Double>, step: Double, unit: String, divider: Bool = true) {
        self.label = label; self.range = range; self.step = step; self.unit = unit; self.divider = divider
        _value = AppStorage(wrappedValue: range.lowerBound, key)
    }
    var body: some View {
        Row(label: label, divider: divider) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: step).frame(width: 150).controlSize(.small)
                Text(unit == "s" ? String(format: "%.2g s", value) : "\(Int(value))\(unit)")
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
            }
        }
    }
}

struct PermissionRow: View {
    var text: String
    var url: String
    var granted: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            if !granted {
                Button("Abrir Ajustes…") { NSWorkspace.shared.open(URL(string: url)!) }.controlSize(.small)
            }
        }
        .padding(12)
    }
}

// MARK: - Páginas

struct GeneralPage: View {
    @AppStorage(K.launchAtLogin) var launchAtLogin = false
    @AppStorage(K.idleActivity) var idle = "playing"
    @State var axTrusted = AXIsProcessTrusted()
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Card {
                ToggleRow("Abrir ao iniciar sessão", K.launchAtLogin)
                ToggleRow("Ocultar em tela cheia", K.hideInFullscreen)
                ToggleRow("Ocultar da captura de tela", K.hideFromCapture)
                ToggleRow("Forçar notch simulado", K.forceSimulatedNotch)
                PickerRow("Exibir em", K.displayOn, [("builtin", "Tela embutida"), ("main", "Tela principal")], divider: false)
            }
            .onChange(of: launchAtLogin) { _, on in
                try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }

            Card(title: "Atividade em repouso") {
                HStack(spacing: 10) {
                    idleOption("none", "Nenhuma") { Image(systemName: "nosign").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary) }
                    idleOption("playing", "Tocando") {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(LinearGradient(colors: Tab.nowPlaying.colors, startPoint: .top, endPoint: .bottom))
                            Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        }.frame(width: 28, height: 28)
                    }
                    idleOption("calendar", "Calendário") { IconTile(tab: .calendar, size: 28) }
                }
                .padding(12)
            }

            Card(title: "Comportamento") {
                ToggleRow("Contorno de contraste", K.contrastOutline)
                ToggleRow("Desfoque progressivo", K.progressiveBlur)
                ToggleRow("Expandir ao passar o mouse", K.expandOnHover)
                SliderRow("Tempo para expandir", K.hoverDuration, 0...1, step: 0.05, unit: "s")
                ToggleRow("Retorno háptico", K.haptics, divider: false)
            }

            Card(title: "Gestos") {
                ToggleRow("Deslizar para pular mídia", K.swipeToSkip, info: "Dois dedos para os lados sobre o notch")
                ToggleRow("Deslizar para abrir e fechar", K.swipeToToggle, info: "Dois dedos para baixo abre, para cima fecha", divider: false)
            }

            Card(title: "Ajuste fino") {
                SliderRow("Largura do notch", K.notchWidthOffset, -20...20, step: 1, unit: " px")
                SliderRow("Altura do notch", K.notchHeightOffset, -10...10, step: 1, unit: " px", divider: false)
            }

            Card(title: "Permissões") {
                PermissionRow(text: "Acessibilidade: necessária para trocar os HUDs de volume e brilho.",
                              url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", granted: axTrusted)
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in axTrusted = AXIsProcessTrusted() }
    }

    func idleOption<V: View>(_ value: String, _ label: String, @ViewBuilder icon: () -> V) -> some View {
        let on = idle == value
        return Button { idle = value } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(on && value == "playing" ? Color(red: 1, green: 0.42, blue: 0.5).opacity(0.15) : Color.primary.opacity(0.05))
                    icon()
                }
                .frame(height: 50)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Color.accentColor : .clear, lineWidth: 2.5).padding(-4))
                Text(label).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

struct BatteryPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Card {
                ToggleRow("Bateria", K.enableBattery, info: "Avisos de carregamento no notch")
                ToggleRow("Avisar com bateria fraca", K.warnOnLowBattery)
                SliderRow("Limite de bateria fraca", K.lowBatteryThreshold, 5...50, step: 5, unit: "%")
                ToggleRow("Tocar som com bateria fraca", K.playSoundOnLowBattery)
                ToggleRow("Esconder porcentagem", K.hideBatteryPercentage)
                ToggleRow("Avisar no modo de pouca energia", K.notifyLowPowerMode, divider: false)
            }
        }
    }
}

struct ConnectivityPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Card {
                ToggleRow("Conectividade", K.enableConnectivity, info: "Mostra fones Bluetooth ao conectar")
                ToggleRow("Mostrar bateria do aparelho", K.showConnectivityBattery, divider: false)
            }
        }
    }
}

struct DisplayPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Card {
                ToggleRow("HUD de brilho", K.enableBrightness, info: "Troca o aviso do sistema pelo do notch")
                ToggleRow("Mostrar porcentagem", K.showBrightnessPercentage, divider: false)
            }
            Card(title: "HUDs") {
                PickerRow("Estilo da barra", K.hudProgressStyle, [("white", "Branco"), ("accent", "Cor de destaque")])
                SliderRow("Duração", K.hudDuration, 0.8...4, step: 0.2, unit: "s", divider: false)
            }
        }
    }
}

struct SoundPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Card {
                ToggleRow("HUD de volume", K.enableVolume, info: "Troca o aviso do sistema pelo do notch")
                ToggleRow("Mostrar porcentagem", K.showVolumePercentage, divider: false)
            }
            Card(title: "HUDs") {
                PickerRow("Estilo da barra", K.hudProgressStyle, [("white", "Branco"), ("accent", "Cor de destaque")])
                SliderRow("Duração", K.hudDuration, 0.8...4, step: 0.2, unit: "s", divider: false)
            }
        }
    }
}

struct NowPlayingPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Card {
                ToggleRow("Tocando agora", K.enableNowPlaying)
                PickerRow("Fonte", K.musicApp, [("auto", "Automático"), ("spotify", "Spotify"), ("music", "Music")])
                ToggleRow("Mostrar ao trocar de mídia", K.showOnMediaChange)
                ToggleRow("Ocultar com o app de origem ativo", K.hideWhileSourceActive)
                PickerRow("Estilo de cor", K.colorStyle, [("artwork", "Capa"), ("mono", "Monocromático")])
                ToggleRow("Desativar onda compacta", K.disableCompactWaveform, divider: false)
            }
            Card(title: "Permissões") {
                Text("Na primeira vez que você usar os controles, o macOS pede para o Alface controlar o Spotify ou o Music. Escolha “Permitir”.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
            }
        }
    }
}

struct CalendarPage: View {
    @ObservedObject var agenda = Agenda.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Card {
                ToggleRow("Calendário", K.enableCalendar, info: "Eventos de hoje na vista expandida")
                ToggleRow("Usar cor do calendário", K.useCalendarColor, divider: false)
            }
            Card(title: "Permissões") {
                PermissionRow(text: "Calendários: para ver os eventos de hoje.",
                              url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars", granted: agenda.authorized)
            }
        }
    }
}

struct LockScreenPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Card {
                ToggleRow("Tela de bloqueio", K.enableLockScreen, info: "Mantém o notch visível com a tela bloqueada")
                ToggleRow("Tocar som ao bloquear", K.playSoundOnLock)
                ToggleRow("Tocar som ao desbloquear", K.playSoundOnUnlock, divider: false)
            }
        }
    }
}

struct AboutPage: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96).padding(.top, 30)
            Text("Alface").font(.system(size: 22, weight: .bold))
            Text("Versão \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Text("Ilha dinâmica no notch do Mac. Clone pessoal do Alcove, só para uso local.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }
}
