import AppKit
import SwiftUI

@main
struct TinyCopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var settings = AppSettings.shared

    var body: some Scene {
        @Bindable var settings = settings
        MenuBarExtra("TinyCopy", systemImage: "doc.on.clipboard", isInserted: $settings.showMenuBarIcon) {
            MenuContent()
        }
    }
}

private struct MenuContent: View {
    private let settings = AppSettings.shared
    private var hasHistory: Bool {
        !AppDelegate.isTesting && !AppModel.shared.items.isEmpty
    }

    var body: some View {
        Button("打开 TinyCopy（\(settings.shortcut.display)）") { AppDelegate.shared?.panel?.show() }
        if let conflict = HotKeyCenter.shared.conflict {
            Button("⚠︎ 快捷键 \(conflict.display) 被其他应用占用…") { AppDelegate.openSettings() }
        }
        if PasteboardAccess.isRestricted {
            Button("⚠︎ 系统限制了读取剪贴板，历史可能没有记录…") { AppDelegate.openSettings() }
        }
        Divider()
        Button("重置窗口位置和大小") { AppDelegate.shared?.panel?.resetWindowGeometry() }
        Button("清空剪贴板历史…") { AppDelegate.shared?.confirmClearHistory() }
            .disabled(!hasHistory)
        Divider()
        Button("设置…") { AppDelegate.openSettings() }
            .keyboardShortcut(",")
        if !Paster.isTrusted {
            Button("授予辅助功能权限…") {
                Paster.requestTrust()
                Paster.openAccessibilitySettings()
            }
        }
        Divider()
        Button("退出 TinyCopy") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static weak var shared: AppDelegate?
    private(set) var panel: PanelController?
    private var settingsWindow: NSWindow?

    static var isTesting: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        guard !Self.isTesting else { return }
        NSApp.appearance = AppSettings.shared.appearance.nsAppearance
        let model = AppModel.shared
        model.startMonitoring()
        let panel = PanelController(model: model)
        self.panel = panel
        HotKeyCenter.shared.action = { [weak panel] in panel?.toggle() }
        if !HotKeyCenter.shared.registerKeepingRetry(AppSettings.shared.shortcut) {
            // Without its shortcut the app is unreachable; say so instead of failing silently.
            showSettings()
        }
        if !AppSettings.shared.showMenuBarIcon { showSettings() }
        LoginItem.applyDefaultOnce()
        // `kill` (as scripts/install.sh sends) quits normally, so the index is flushed.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termSource = source
    }

    private var termSource: DispatchSourceSignal?

    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isTesting else { return }
        panel?.hide()
        AppModel.shared.flush()
    }

    /// Opening the app again from Finder or Spotlight shows the settings: there is no other window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.openSettings()
        return false
    }

    static func openSettings() {
        shared?.showSettings()
    }

    func confirmClearHistory() {
        panel?.hide()
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "清空剪贴板历史？"
        alert.informativeText = "删除的历史记录无法恢复。可以保留收藏的记录，也可以全部清空。当前剪贴板中的内容不受影响。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空未收藏记录")
        alert.addButton(withTitle: "全部清空")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: AppModel.shared.clearHistory(keepPinned: true)
        case .alertSecondButtonReturn: AppModel.shared.clearHistory(keepPinned: false)
        default: break
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "TinyCopy 设置"
            let host = NSHostingView(rootView: SettingsView())
            host.sizingOptions = []
            window.contentView = host
            window.contentMinSize = Metrics.minimumSettingsSize
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
