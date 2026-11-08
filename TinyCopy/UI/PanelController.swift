import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A borderless panel that can take keyboard focus without activating TinyCopy, so the app the
/// user was in stays frontmost and receives the paste.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating panel: showing it centered on the screen in use, keyboard routing, closing on
/// focus loss, and pasting into the previous app. The panel's content is SwiftUI.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let state: PanelState
    private let panel: KeyablePanel
    private let model: AppModel
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var layout = PanelLayout()
    private var applyingLayout = false
    private var saveLayoutTask: Task<Void, Never>?

    private struct PanelLayout: Codable {
        var topLeft: CGPoint?
        var compactWidth: CGFloat = Metrics.panelSize.width
        var expandedWidth: CGFloat = Metrics.expandedWidth
        var height: CGFloat = Metrics.panelSize.height

        var isValid: Bool {
            compactWidth.isFinite && expandedWidth.isFinite && height.isFinite &&
            compactWidth > 0 && expandedWidth > 0 && height > 0 &&
            (topLeft.map { $0.x.isFinite && $0.y.isFinite } ?? true)
        }
    }

    init(model: AppModel) {
        self.model = model
        state = PanelState(model: model)
        panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: Metrics.panelSize),
                             styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        super.init()
        if let data = model.settings.panelLayoutData,
           let saved = try? JSONDecoder().decode(PanelLayout.self, from: data), saved.isValid {
            layout = saved
        }
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let host = NSHostingView(rootView: MainView(state: state))
        host.sizingOptions = []
        panel.contentView = host

        state.onPreviewVisibilityChanged = { [weak self] in self?.resizePreview() }
        state.close = { [weak self] in self?.hide() }
        state.performImage = { [weak self] png, paste in
            guard let self else { return }
            self.model.writeImageToPasteboard(png)
            self.finish(paste: paste)
        }
        state.perform = { [weak self] item, text, paste in self?.finish(item, text: text, paste: paste) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        applyingLayout = true
        state.prepareForShow()
        applyingLayout = false
        position()
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        // SwiftUI focus usually follows focusToken; this covers the first show.
        DispatchQueue.main.async { [weak self] in self?.focusSearchField() }
    }

    func hide() {
        state.cancelPending()
        saveLayout()
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func screenForLayout() -> NSScreen {
        if let point = layout.topLeft,
           let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }) {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func position() {
        let screen = screenForLayout()
        let anchorOnScreen = layout.topLeft.map { point in
            NSScreen.screens.contains { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
        } ?? false
        if !anchorOnScreen {
            let visible = screen.visibleFrame.insetBy(dx: 20, dy: 20)
            let width = min(max(layout.compactWidth, Metrics.minimumPanelSize.width), visible.width)
            let height = min(max(layout.height, Metrics.minimumPanelSize.height), visible.height)
            layout.topLeft = CGPoint(x: visible.midX - width / 2,
                                     y: min(visible.maxY, visible.midY + height / 2 + visible.height * 0.06))
        }
        applyLayout(on: screen)
    }

    /// Preserve the user's list width and height; only shift the frame when a screen edge requires it.
    private func resizePreview() {
        guard panel.isVisible, !applyingLayout else { return }
        applyLayout(on: screenForLayout())
    }

    private func applyLayout(on screen: NSScreen) {
        let visible = screen.visibleFrame.insetBy(dx: 20, dy: 20)
        let minimumWidth: CGFloat = state.previewVisible ? max(Metrics.minimumExpandedSize.width, layout.compactWidth + 340) : Metrics.minimumPanelSize.width
        let desiredWidth = state.previewVisible ? layout.expandedWidth : layout.compactWidth
        let width = min(max(desiredWidth, minimumWidth), visible.width)
        let height = min(max(layout.height, Metrics.minimumPanelSize.height), visible.height)
        let anchor = layout.topLeft ?? CGPoint(x: visible.midX - width / 2, y: visible.midY + height / 2)
        let x = max(visible.minX, min(anchor.x, visible.maxX - width)).rounded()
        let y = max(visible.minY, min(anchor.y - height, visible.maxY - height)).rounded()
        applyingLayout = true
        defer { applyingLayout = false }
        state.historyColumnWidth = layout.compactWidth
        panel.minSize = NSSize(width: min(minimumWidth, visible.width), height: min(Metrics.minimumPanelSize.height, visible.height))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.invalidateShadow()
    }

    func resetWindowGeometry() {
        saveLayoutTask?.cancel()
        layout = PanelLayout()
        model.settings.panelLayoutData = nil
        if panel.isVisible { position() }
    }

    func windowDidMove(_ notification: Notification) { rememberLayout() }
    func windowDidResize(_ notification: Notification) { rememberLayout() }

    private func rememberLayout() {
        guard panel.isVisible, !applyingLayout else { return }
        let frame = panel.frame
        layout.topLeft = CGPoint(x: frame.minX, y: frame.maxY)
        layout.height = frame.height
        if state.previewVisible { layout.expandedWidth = frame.width } else { layout.compactWidth = frame.width }
        saveLayoutTask?.cancel()
        saveLayoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveLayout()
        }
    }

    private func saveLayout() {
        saveLayoutTask?.cancel()
        model.settings.panelLayoutData = try? JSONEncoder().encode(layout)
    }

    private func focusSearchField() {
        guard panel.isVisible, !(panel.firstResponder is NSTextView) else { return }
        if let field = findTextField(in: panel.contentView) { panel.makeFirstResponder(field) }
    }

    private func findTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for sub in view.subviews { if let found = findTextField(in: sub) { return found } }
        return nil
    }

    // MARK: Closing

    func windowDidResignKey(_ notification: Notification) {
        // A sheet (the translation language download) takes key focus without leaving the panel.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow, self.panel.attachedSheet == nil else { return }
            self.hide()
        }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                return self.handle(event)
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the key was handled. Keys go to the input method while it is composing
    /// (pinyin and other marked text), so its candidate list keeps working.
    private func handle(_ event: NSEvent) -> Bool {
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch Int(event.keyCode) {
        case kVK_DownArrow: state.move(1)
        case kVK_UpArrow: state.move(-1)
        case kVK_PageDown: state.move(7)
        case kVK_PageUp: state.move(-7)
        case kVK_Return, kVK_ANSI_KeypadEnter: state.activate(paste: !flags.contains(.command))
        case kVK_Escape: state.escape()
        case kVK_Tab where flags.isEmpty || flags == .shift:
            state.movePreview(flags == .shift ? -1 : 1)
        case kVK_RightArrow where flags.isEmpty && (state.navigationActive || state.query.isEmpty):
            state.movePreview(1)
        case kVK_LeftArrow where flags.isEmpty && (state.navigationActive || state.query.isEmpty):
            state.movePreview(-1)
        case kVK_ANSI_P where flags == .command: state.togglePinSelected()
        case kVK_Delete where flags == .command: state.deleteSelected()
        case kVK_ANSI_W where flags == .command: hide()
        case kVK_ANSI_Comma where flags == .command:
            hide()
            AppDelegate.openSettings()
        default: return false
        }
        return true
    }

    // MARK: Paste

    private func finish(_ item: ClipItem, text: String?, paste: Bool) {
        model.writeToPasteboard(item.id, text: text)
        finish(paste: paste)
    }

    private func finish(paste: Bool) {
        hide()
        guard paste else { return }
        guard Paster.isTrusted else {
            // The content is on the pasteboard already; the user can press ⌘V after granting access.
            Paster.requestTrust()
            return
        }
        let target = previousApp
        if let target, !target.isActive { target.activate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Paster.sendCommandV()
        }
    }
}

/// Invisible drag regions occupy toolbar whitespace without covering text editing or controls.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            window?.performDrag(with: event)
        }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
