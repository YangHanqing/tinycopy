import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "通用", history = "历史记录", smart = "智能功能"
    var id: Self { self }
}

struct SettingsView: View {
    @Bindable private var settings: AppSettings
    private let model: AppModel
    @State private var page: SettingsPage
    @State private var loginStatus = LoginItem.status
    @State private var trusted = Paster.isTrusted
    @State private var pasteboardRestricted = PasteboardAccess.isRestricted
    @State private var explainingAccessibility = false
    @State private var pendingLimit: Int?
    @State private var targets: [String] = []
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init() { self.init(settings: .shared, model: .shared) }

    init(settings: AppSettings, model: AppModel, initialPage: SettingsPage = .general) {
        self.settings = settings
        self.model = model
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置分类", selection: $page) {
                ForEach(SettingsPage.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 4)
            Form {
                switch page {
                case .general: generalSection
                case .history: historySection
                case .smart: smartSection
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text("历史记录仅保存在这台 Mac 上")
                Spacer()
                Text("版本 " + version)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(minWidth: Metrics.minimumSettingsSize.width, minHeight: Metrics.minimumSettingsSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(settings.appearance.colorScheme)
        .onChange(of: settings.appearance) { NSApp.appearance = settings.appearance.nsAppearance }
        .onReceive(refresh) { _ in
            trusted = Paster.isTrusted
            pasteboardRestricted = PasteboardAccess.isRestricted
            loginStatus = LoginItem.status
        }
        .onChange(of: settings.historyLimit) { model.evictOverLimit() }
        .onChange(of: settings.smartDetection) {
            if settings.smartDetection {
                model.items.filter { $0.kind == .image && $0.qrContents == nil }.forEach { model.requestQRDetection($0.id) }
            }
        }
        .onChange(of: settings.ocrMode) {
            if settings.ocrMode == .automatic {
                model.items.filter { $0.kind == .image && $0.ocrText == nil }.forEach { model.requestOCR($0.id) }
            }
        }
        .task { await loadTargets() }
    }

    private var generalSection: some View {
        Section("通用") {
            Picker("外观", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }
            Toggle("显示菜单栏图标", isOn: $settings.showMenuBarIcon)
            if !settings.showMenuBarIcon {
                note("从应用启动器、Spotlight 或“应用程序”打开 TinyCopy 即可进入设置，重新显示图标。剪贴板快捷键仍然可用。")
            }
            Toggle("登录时启动", isOn: Binding(
                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                set: { LoginItem.set($0); loginStatus = LoginItem.status }
            ))
            if loginStatus == .requiresApproval {
                note("需要在“系统设置 ▸ 通用 ▸ 登录项”中允许 TinyCopy。")
            }
            HStack {
                Text("打开 TinyCopy")
                Spacer()
                ShortcutRecorder(shortcut: $settings.shortcut)
            }
            HStack {
                Text("辅助功能权限")
                Button { explainingAccessibility.toggle() } label: {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("为什么需要辅助功能权限")
                .popover(isPresented: $explainingAccessibility) {
                    Text("TinyCopy 需要模拟一次 ⌘V，才能将选中的内容直接粘贴回之前的应用。\n\n可以在“系统设置 ▸ 隐私与安全性 ▸ 辅助功能”中管理此授权。未授权时仍可保存历史和复制内容，再自行按 ⌘V。")
                        .font(.system(size: 13))
                        .padding(16)
                        .frame(width: 320)
                }
                Spacer()
                if trusted {
                    Label("已授权", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("前往授权") {
                        Paster.requestTrust()
                        Paster.openAccessibilitySettings()
                    }
                }
            }
            note("用于模拟 ⌘V，把选中的内容粘贴回之前的应用。未授权时仍可保存历史和复制内容，再自行按 ⌘V。")
            if pasteboardRestricted {
                LabeledContent("读取剪贴板") {
                    Button("前往设置") { PasteboardAccess.openPrivacySettings() }
                }
                note("系统目前会询问或拒绝 TinyCopy 读取剪贴板。请在“系统设置 ▸ 隐私与安全性”的剪贴板（粘贴）访问设置里把 TinyCopy 改为“始终允许”。")
                    .foregroundStyle(.red)
            }
        }
    }

    private var historySection: some View {
        Section("历史记录") {
            Picker("最多保存", selection: Binding(
                get: { settings.historyLimit },
                set: { new in
                    // Lowering the limit deletes the oldest records at once; ask first.
                    if new < unpinnedCount { pendingLimit = new } else { settings.historyLimit = new }
                }
            )) {
                ForEach(AppSettings.historyLimits, id: \.self) { Text("\($0) 条").tag($0) }
            }
            .confirmationDialog("只保留最近 \(pendingLimit ?? 0) 条？", isPresented: Binding(
                get: { pendingLimit != nil },
                set: { if !$0 { pendingLimit = nil } }
            )) {
                Button("删除较早的 \(unpinnedCount - (pendingLimit ?? 0)) 条记录", role: .destructive) {
                    if let limit = pendingLimit { settings.historyLimit = limit }
                    pendingLimit = nil
                }
                Button("取消", role: .cancel) { pendingLimit = nil }
            } message: {
                Text("超出上限的未收藏记录会立即删除，无法撤销。收藏的记录不受影响。")
            }
            Toggle("忽略标记为保密或临时的内容", isOn: $settings.ignoreConcealed)
            note("密码管理器等应用会把复制的密码标记为保密，这类内容默认不记录。收藏的记录不计入条数上限。")
        }
    }


    private var smartSection: some View {
        Section("智能功能") {
            Toggle("识别内容类型", isOn: $settings.smartDetection)
            note("识别 JSON、JWT、链接、Base64、时间戳和图片中的二维码，并提供相应转换。")
            Picker("图片文字识别", selection: $settings.ocrMode) {
                ForEach(OCRMode.allCases) { Text($0.title).tag($0) }
            }
            if model.translationAvailable {
                Picker("翻译", selection: $settings.translationMode) {
                    ForEach(TranslationMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("翻译为", selection: $settings.targetLanguage) {
                    ForEach(targetChoices, id: \.self) { Text(LanguageTools.displayName($0)).tag($0) }
                }
                .disabled(settings.translationMode == .off)
                note("文字识别和翻译都在本机完成；翻译使用系统翻译，首次使用某种语言时可能需要下载语言包。")
            }
        }

    }


    private var unpinnedCount: Int { model.items.filter { !$0.pinned }.count }

    /// The supported languages, plus the current choice while the list loads.
    private var targetChoices: [String] {
        targets.contains(settings.targetLanguage) ? targets : [settings.targetLanguage] + targets
    }

    private func loadTargets() async {
        guard #available(macOS 15.0, *) else { return }
        let list = await TranslationEngine.supportedTargets()
        targets = list
        // Use the list's spelling of the stored language so the picker shows it selected.
        if !list.contains(settings.targetLanguage),
           let match = list.first(where: { LanguageTools.sameLanguage($0, settings.targetLanguage) }) {
            settings.targetLanguage = match
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Click, then press the new combination. It needs ⌘, ⌥ or ⌃ (or is a function key); Escape cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    recording ? stop() : start()
                } label: {
                    Text(recording ? "请按下快捷键…" : shortcut.display)
                        .frame(minWidth: 76)
                }
                if shortcut != .standard, !recording {
                    Button("恢复默认") { apply(.standard) }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if let conflict = HotKeyCenter.shared.conflict, conflict == shortcut, !recording {
                Text("\(conflict.display) 已被其他应用（例如其他剪贴板工具）占用。请换一个快捷键，或退出那个应用。")
                    .font(.caption).foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 260, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onDisappear { stop() }
    }

    private func start() {
        error = nil
        recording = true
        // Free the current combination so pressing it again is recorded instead of opening the panel.
        HotKeyCenter.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            MainActor.assumeIsolated {
                if Int(keyCode) == kVK_Escape {
                    stop()
                } else if flags.intersection([.command, .option, .control]).isEmpty && !KeyNames.isFunctionKey(keyCode) {
                    NSSound.beep()
                } else {
                    let new = Shortcut(keyCode: UInt32(keyCode), modifiers: KeyNames.carbonModifiers(flags),
                                       keyLabel: KeyNames.label(for: keyCode))
                    if KeyNames.isReservedByEveryApp(keyCode: keyCode, modifiers: new.modifiers) {
                        error = "\(new.display) 是所有应用都在用的快捷键，请换一个"
                        stop()
                    } else {
                        apply(new)
                    }
                }
            }
            return nil
        }
    }

    private func apply(_ new: Shortcut) {
        if HotKeyCenter.shared.register(new) {
            shortcut = new
            error = nil
        } else {
            error = "\(new.display) 已被系统或其他应用占用，请换一个"
        }
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { HotKeyCenter.shared.registerKeepingRetry(shortcut) }
        recording = false
    }
}
