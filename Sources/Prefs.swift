import Foundation

// Chaves do UserDefaults. As views usam @AppStorage(K.x); a lógica lê `Prefs.bool(K.x)`.
enum K {
    // Geral
    static let launchAtLogin = "launchAtLogin"
    static let hideInFullscreen = "hideInFullscreen"
    static let hideFromCapture = "hideFromScreenCapture"
    static let forceSimulatedNotch = "forceSimulatedNotch"
    static let displayOn = "displayOn"              // "builtin" | "main"
    static let idleActivity = "idleActivity"        // "none" | "playing" | "calendar"
    static let contrastOutline = "contrastOutline"
    static let progressiveBlur = "progressiveBlur"
    static let expandOnHover = "expandOnHover"
    static let hoverDuration = "hoverDuration"
    static let haptics = "haptics"
    static let swipeToSkip = "swipeToSkip"
    static let swipeToToggle = "swipeToToggle"
    static let notchWidthOffset = "notchWidthOffset"
    static let notchHeightOffset = "notchHeightOffset"
    // Bateria
    static let enableBattery = "enableBattery"
    static let warnOnLowBattery = "warnOnLowBattery"
    static let lowBatteryThreshold = "lowBatteryThreshold"
    static let playSoundOnLowBattery = "playSoundOnLowBattery"
    static let hideBatteryPercentage = "hideBatteryPercentage"
    static let notifyLowPowerMode = "notifyLowPowerMode"
    // Conectividade
    static let enableConnectivity = "enableConnectivity"
    static let showConnectivityBattery = "showConnectivityBattery"
    static let warnOnLowConnectBattery = "warnOnLowConnectBattery"
    static let playSoundOnLowConnectBattery = "playSoundOnLowConnectBattery"
    static let lowConnectBatteryThreshold = "lowConnectBatteryThreshold"
    // HUDs
    static let enableVolume = "enableVolume"
    static let showVolumePercentage = "showVolumePercentage"
    static let enableBrightness = "enableBrightness"
    static let showBrightnessPercentage = "showBrightnessPercentage"
    static let enableKeyboardBrightness = "enableKeyboardBrightness"
    static let hudProgressStyle = "hudProgressStyle"  // "white" | "accent"
    static let hudDuration = "hudDuration"
    // Tocando agora
    static let enableNowPlaying = "enableNowPlaying"
    static let musicApp = "musicApp"                  // "auto" | "spotify" | "music"
    static let hideWhileSourceActive = "hideWhileSourceActive"
    static let colorStyle = "nowPlayingColorStyle"    // "artwork" | "mono"
    static let disableCompactWaveform = "disableCompactWaveform"
    static let showOnMediaChange = "showOnMediaChange"
    // Calendário
    static let enableCalendar = "enableCalendar"
    static let useCalendarColor = "useCalendarColor"
    // Tela de bloqueio
    static let enableLockScreen = "enableLockScreen"
    static let playSoundOnLock = "playSoundOnLock"
    static let playSoundOnUnlock = "playSoundOnUnlock"
}

enum Prefs {
    static let d = UserDefaults.standard
    static func register() {
        d.register(defaults: [
            K.launchAtLogin: false, K.hideInFullscreen: true, K.hideFromCapture: false,
            K.forceSimulatedNotch: false, K.displayOn: "builtin", K.idleActivity: "playing",
            K.contrastOutline: true, K.progressiveBlur: true, K.expandOnHover: true, K.hoverDuration: 0.15,
            K.haptics: true, K.swipeToSkip: true, K.swipeToToggle: true,
            K.notchWidthOffset: 0.0, K.notchHeightOffset: 0.0,
            K.enableBattery: true, K.warnOnLowBattery: true, K.lowBatteryThreshold: 20,
            K.playSoundOnLowBattery: true, K.hideBatteryPercentage: false, K.notifyLowPowerMode: true,
            K.enableConnectivity: true, K.showConnectivityBattery: true,
            K.warnOnLowConnectBattery: true, K.playSoundOnLowConnectBattery: true, K.lowConnectBatteryThreshold: 20,
            K.enableKeyboardBrightness: true,
            K.enableVolume: true, K.showVolumePercentage: false,
            K.enableBrightness: true, K.showBrightnessPercentage: false,
            K.hudProgressStyle: "white", K.hudDuration: 1.6,
            K.enableNowPlaying: true, K.musicApp: "auto", K.hideWhileSourceActive: false,
            K.colorStyle: "artwork", K.disableCompactWaveform: false, K.showOnMediaChange: true,
            K.enableCalendar: true, K.useCalendarColor: true,
            K.enableLockScreen: true, K.playSoundOnLock: false, K.playSoundOnUnlock: false,
        ])
    }
    static func bool(_ k: String) -> Bool { d.bool(forKey: k) }
    static func double(_ k: String) -> Double { d.double(forKey: k) }
    static func string(_ k: String) -> String { d.string(forKey: k) ?? "" }
}
