import AppKit
import AudioToolbox
import CoreAudio

// Volume do dispositivo de saída padrão (CoreAudio, API pública).
enum Volume {
    static func device() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }
    static var volumeAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                       mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    static var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                     mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    /// nil quando o dispositivo não deixa mudar o volume (ex.: HDMI) — aí o sistema cuida da tecla
    static var canSet: Bool {
        var settable: DarwinBoolean = false
        let d = device()
        return AudioObjectHasProperty(d, &volumeAddr) && AudioObjectIsPropertySettable(d, &volumeAddr, &settable) == noErr && settable.boolValue
    }
    static var level: Float {
        get {
            var v = Float32(0); var size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectGetPropertyData(device(), &volumeAddr, 0, nil, &size, &v)
            return v
        }
        set {
            var v = Float32(max(0, min(1, newValue)))
            AudioObjectSetPropertyData(device(), &volumeAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }
    static var muted: Bool {
        get {
            var m = UInt32(0); var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device(), &muteAddr, 0, nil, &size, &m)
            return m != 0
        }
        set {
            var m = UInt32(newValue ? 1 : 0)
            AudioObjectSetPropertyData(device(), &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        }
    }
    /// nome do dispositivo de saída (para escolher o símbolo)
    static var deviceName: String {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(device(), &a, 0, nil, &size, &name)
        return name?.takeRetainedValue() as String? ?? ""
    }
}

// Brilho da tela embutida pelo DisplayServices (framework privado, o mesmo que o Alcove usa).
enum Brightness {
    static let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    static let getFn = dlsym(h, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: (@convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32).self) }
    static let setFn = dlsym(h, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: (@convention(c) (UInt32, Float) -> Int32).self) }

    static var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n = UInt32(0)
        CGGetOnlineDisplayList(16, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }
    static var available: Bool { getFn != nil && setFn != nil && CGDisplayIsBuiltin(display) != 0 }
    static var level: Float {
        get { var v: Float = 0; _ = getFn?(display, &v); return v }
        set { _ = setFn?(display, max(0, min(1, newValue))) }
    }
}

// Intercepta as teclas de volume/brilho (precisa de Acessibilidade) para trocar o HUD do sistema pelo do notch.
final class MediaKeys {
    static let shared = MediaKeys()
    enum Key { case volUp, volDown, mute, brightUp, brightDown, kbUp, kbDown, kbToggle }
    /// devolve true quando tratou a tecla (o evento some e o HUD do sistema não aparece)
    var handler: ((Key, NSEvent.ModifierFlags, _ down: Bool) -> Bool)?
    fileprivate var tap: CFMachPort?

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1 << 14) | CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else { return false }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type.rawValue == 14 {
            guard let e = NSEvent(cgEvent: event), e.subtype.rawValue == 8 else { return false }
            let code = (e.data1 & 0xFFFF0000) >> 16
            let down = ((e.data1 & 0xFF00) >> 8) == 0xA
            let key: Key
            switch code {
            case 0: key = .volUp
            case 1: key = .volDown
            case 7: key = .mute
            case 2: key = .brightUp
            case 3: key = .brightDown
            case 21: key = .kbUp
            case 22: key = .kbDown
            case 23: key = .kbToggle
            default: return false
            }
            return handler?(key, e.modifierFlags, down) ?? false
        }
        // alguns teclados mandam o brilho como tecla comum (códigos 144/145)
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard code == 144 || code == 145 else { return false }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        return handler?(code == 144 ? .brightUp : .brightDown, flags, type == .keyDown) ?? false
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = MediaKeys.shared.tap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    return MediaKeys.shared.handle(type, event) ? nil : Unmanaged.passUnretained(event)
}

// Brilho do teclado pelo CoreBrightness (framework privado, classe KeyboardBrightnessClient).
enum KeyboardLight {
    static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()
    static let id: UInt64? = {
        guard let c = client, c.responds(to: NSSelectorFromString("copyKeyboardBacklightIDs")) else { return nil }
        return (c.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber])?.first?.uint64Value
    }()
    static var available: Bool { id != nil }
    static var level: Float {
        get {
            guard let c = client, let id else { return 0 }
            let sel = NSSelectorFromString("brightnessForKeyboard:")
            guard c.responds(to: sel) else { return 0 }
            return unsafeBitCast(c.method(for: sel), to: (@convention(c) (AnyObject, Selector, UInt64) -> Float).self)(c, sel, id)
        }
        set {
            guard let c = client, let id else { return }
            let sel = NSSelectorFromString("setBrightness:forKeyboard:")
            guard c.responds(to: sel) else { return }
            _ = unsafeBitCast(c.method(for: sel), to: (@convention(c) (AnyObject, Selector, Float, UInt64) -> Bool).self)(c, sel, max(0, min(1, newValue)), id)
        }
    }
}

// Avisa quando o volume ou o mudo mudam por qualquer caminho (Central de Controle, outro app...).
final class VolumeWatch {
    var onChange: (() -> Void)?
    private var device = AudioDeviceID(0)
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onChange?() }

    func start() {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        // trocou a saída (ex.: fones conectaram): passa a ouvir o novo dispositivo
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { [weak self] _, _ in self?.bind() }
        bind()
    }

    private func bind() {
        if device != 0 {
            AudioObjectRemovePropertyListenerBlock(device, &Volume.volumeAddr, .main, listener)
            AudioObjectRemovePropertyListenerBlock(device, &Volume.muteAddr, .main, listener)
        }
        device = Volume.device()
        AudioObjectAddPropertyListenerBlock(device, &Volume.volumeAddr, .main, listener)
        AudioObjectAddPropertyListenerBlock(device, &Volume.muteAddr, .main, listener)
    }
}
