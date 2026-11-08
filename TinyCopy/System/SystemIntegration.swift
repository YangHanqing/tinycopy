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
