import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

/// Sends ⌘V to the frontmost app. Needs the Accessibility permission, which macOS remembers by the
/// app's code signature (an ad hoc build loses it on every rebuild).
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to System Settings ▸ Privacy & Security ▸ Accessibility.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// File managers treat ⌘V outside a text field as "paste items here": with text on the
    /// pasteboard, Finder makes a new file ("已粘贴 …") in the folder or on the desktop. TinyCopy
    /// only means to paste into an input, so in these apps it pastes only when a text field (rename,
    /// search, Go to Folder) has focus; elsewhere it leaves the content on the pasteboard.
    private static let fileManagers: Set<String> = [
        "com.apple.finder",
        "com.cocoatech.PathFinder",
        "com.binarynights.ForkLift",
        "com.binarynights.ForkLift-3",
        "com.binarynights.forklift4",
        "com.mac.QSpace",
        "com.mac.QSpace.pro",
        "com.marta.Marta",
        "com.commander-one",
        "com.eltima.cmd1",
    ]

    /// Whether ⌘V in `app` would land in an input rather than create files.
    static func acceptsPaste(_ app: NSRunningApplication?) -> Bool {
        guard let app, let id = app.bundleIdentifier, fileManagers.contains(id) else { return true }
        return focusedElementIsEditable(pid: app.processIdentifier)
    }

    private static func focusedElementIsEditable(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        // A busy app must not stall the paste; no answer counts as "not a text field".
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let role = role as? String,
           [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"].contains(role) {
            return true
        }
        var settable: DarwinBoolean = false
        var range: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success
            && AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Keep the user's own keys from mixing into the synthetic press.
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                           state: .eventSuppressionStateSuppressionInterval)
        // The key that types "v" with ⌘ in the current layout (Dvorak and others move it); the
        // ANSI position otherwise, which is also what non-Latin layouts use for shortcuts.
        let v = CGKeyCode(KeyNames.keyCode(typing: "v", modifiers: UInt32(cmdKey)) ?? UInt16(kVK_ANSI_V))
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

/// macOS 15.4+ can ask the user, or refuse, each time an app reads the pasteboard on its own.
/// A clipboard history needs "always allow"; otherwise nothing (or not everything) is recorded.
enum PasteboardAccess {
    static var isRestricted: Bool {
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .ask, .alwaysDeny: return true
            default: return false
            }
        }
        return false
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("TinyCopy: login item change failed: \(error.localizedDescription)")
        }
    }

    /// Login at startup is on by default: turned on once, at the first launch from /Applications,
    /// so a build-folder copy never registers itself.
    static func applyDefaultOnce() {
        let key = "didApplyDefaultLoginItem"
        guard !UserDefaults.standard.bool(forKey: key), Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        UserDefaults.standard.set(true, forKey: key)
        if status != .enabled { set(true) }
    }
}
