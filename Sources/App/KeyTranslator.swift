import Carbon
import Cocoa

/// Turns key-down events into the text the user's keyboard layout would type,
/// tracking dead keys (e.g. ⌥E then E → é) across events.
///
/// While an input method is the selected input source the system doesn't
/// apply the keyboard layout for us, so this asks the layout directly via
/// UCKeyTranslate, using the current ASCII-capable layout (the one macOS pairs
/// with input methods: U.S., Dvorak, British, …).
final class KeyTranslator {
    private var deadKeyState: UInt32 = 0
    /// The accent of a dead key pressed but not yet completed, shown underlined until it is.
    private(set) var pendingDeadKey = ""

    func reset() {
        deadKeyState = 0
        pendingDeadKey = ""
    }

    /// The text for `event`, "" while a dead key is pending, nil if the
    /// keyboard layout can't be read.
    func text(for event: NSEvent) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }

        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var modifiers = 0
        if event.modifierFlags.contains(.shift) { modifiers |= shiftKey }
        if event.modifierFlags.contains(.option) { modifiers |= optionKey }
        if event.modifierFlags.contains(.capsLock) { modifiers |= alphaLock }
        let modifierState = UInt32((modifiers >> 8) & 0xFF)
        let keyboardType = UInt32(LMGetKbdType())

        func translate(_ options: OptionBits, _ state: inout UInt32) -> String? {
            var chars = [UniChar](repeating: 0, count: 16)
            var length = 0
            let status = UCKeyTranslate(layout, event.keyCode, UInt16(kUCKeyActionDown), modifierState,
                                        keyboardType, options, &state, chars.count, &length, &chars)
            return status == noErr ? String(utf16CodeUnits: chars, count: length) : nil
        }

        guard let text = translate(0, &deadKeyState) else { return nil }
        if deadKeyState != 0 {
            // Mid dead-key sequence: work out which accent to show by translating
            // the same key again with dead-key processing off.
            var scratch: UInt32 = 0
            pendingDeadKey = translate(OptionBits(kUCKeyTranslateNoDeadKeysMask), &scratch) ?? ""
        } else {
            pendingDeadKey = ""
        }
        return text
    }
}
