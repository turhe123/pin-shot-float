import AppKit
import Carbon.HIToolbox

/// A key code + Carbon modifier combination, encodable as a single Int for UserDefaults.
struct HotKey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultCapture = HotKey(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(controlKey | shiftKey))
    static let defaultClipboard = HotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(controlKey | shiftKey))

    var encoded: Int { Int(modifiers) << 16 | Int(keyCode) }
    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(encoded: Int) { keyCode = UInt32(encoded & 0xFFFF); modifiers = UInt32((encoded >> 16) & 0xFFFF) }

    /// Builds a hotkey from a key event; requires at least one of ⌘ ⌃ ⌥.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        guard mods & UInt32(cmdKey | controlKey | optionKey) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    private static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_F1: "F1", kVK_F2: "F2",
                                      kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6"]
        if let name = special[Int(code)] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Registers the global capture / pin-clipboard hotkeys via the Carbon hot key API.
final class HotKeyManager {
    static let shared = HotKeyManager()
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false
    private static let signature: OSType = 0x5053_4654 // 'PSFT'

    func registerFromDefaults() {
        installHandlerIfNeeded()
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        let d = UserDefaults.standard
        register(HotKey(encoded: d.integer(forKey: Prefs.captureKey)), id: 1)
        register(HotKey(encoded: d.integer(forKey: Prefs.clipboardKey)), id: 2)
    }

    private func register(_ key: HotKey, id: UInt32) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(key.keyCode, key.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref) }
        else { NSLog("PinShotFloat: could not register hotkey \(key.displayString) (status \(status))") }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard err == noErr else { return err }
            DispatchQueue.main.async {
                switch hkID.id {
                case 1: CaptureCoordinator.shared.beginCapture()
                case 2: PinManager.shared.pinClipboard()
                default: break
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = status == noErr
    }
}
