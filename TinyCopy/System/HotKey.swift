import AppKit
import Carbon.HIToolbox
import Observation

/// The one global shortcut, through Carbon's RegisterEventHotKey: it needs no permission and the
/// key press is not passed on to the frontmost app.
@MainActor
@Observable
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// The shortcut the system refused (another app holds it), retried every few seconds.
    private(set) var conflict: Shortcut?
    @ObservationIgnored var action: (() -> Void)?
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?
    @ObservationIgnored private var retryTimer: Timer?

    /// Returns false when the system refuses the combination (another app holds it).
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x5443_4F50), id: 1) // 'TCOP'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { hotKeyRef = nil }
        return status == noErr
    }

    /// Registers the app's shortcut; on a conflict keeps retrying, so it takes over once the other app quits.
    @discardableResult
    func registerKeepingRetry(_ shortcut: Shortcut) -> Bool {
        retryTimer?.invalidate()
        retryTimer = nil
        if register(shortcut) {
            conflict = nil
            return true
        }
        conflict = shortcut
        let timer = Timer(timeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let center = HotKeyCenter.shared
                guard let pending = center.conflict else { return }
                if center.register(pending) {
                    center.conflict = nil
                    center.retryTimer?.invalidate()
                    center.retryTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
        return false
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// While recording a new shortcut nothing is registered and nothing is retried.
    func pause() {
        retryTimer?.invalidate()
        retryTimer = nil
        unregister()
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.action?() } }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

enum KeyNames {
    private static let special: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        (special[Int(keyCode)] ?? "").hasPrefix("F")
    }

    /// The key's label in the current keyboard layout, without modifiers (so ⇧2 shows "2", not "@").
    static func label(for keyCode: UInt16) -> String {
        if let name = special[Int(keyCode)] { return name }
        guard let layout = currentLayout() else { return "?" }
        return translate(keyCode, modifiers: 0, in: layout)?.uppercased() ?? "?"
    }

    /// The key that types `character` with the given Carbon modifiers in the current layout.
    static func keyCode(typing character: String, modifiers: UInt32) -> UInt16? {
        guard let layout = currentLayout() else { return nil }
        return (0..<128).map(UInt16.init).first { translate($0, modifiers: modifiers, in: layout) == character }
    }

    private static func currentLayout() -> Data? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    private static func translate(_ keyCode: UInt16, modifiers: UInt32, in layoutData: Data) -> String? {
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), (modifiers >> 8) & 0xFF, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    /// ⌘ plus one of these is an editing or window command every app relies on; taking it globally
    /// would break it everywhere (⌘V would even catch TinyCopy's own paste).
    static func isReservedByEveryApp(keyCode: UInt16, modifiers: UInt32) -> Bool {
        guard modifiers == UInt32(cmdKey) else { return false }
        let reserved: Set<Int> = [kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_Q,
                                  kVK_ANSI_W, kVK_ANSI_S, kVK_ANSI_H, kVK_ANSI_M, kVK_Tab, kVK_Space]
        return reserved.contains(Int(keyCode))
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }
}
