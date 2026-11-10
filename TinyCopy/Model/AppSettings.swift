import Foundation
import Carbon.HIToolbox
import Observation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

enum OCRMode: String, CaseIterable, Identifiable {
    case automatic, onDemand, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "自动后台识别"
        case .onDemand: "仅在需要时识别"
        case .off: "关闭"
        }
    }
}

enum TranslationMode: String, CaseIterable, Identifiable {
    case automatic, onDemand, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "自动后台翻译"
        case .onDemand: "按需翻译"
        case .off: "关闭"
        }
    }
}

/// A global shortcut as Carbon wants it, plus the key's label for display.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "V")

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: .standard)
    static let historyLimits = [25, 50, 100, 200, 500]

    @ObservationIgnored private let defaults: UserDefaults

    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) } }
    var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) } }
    var ocrMode: OCRMode { didSet { defaults.set(ocrMode.rawValue, forKey: Keys.ocrMode) } }
    var translationMode: TranslationMode { didSet { defaults.set(translationMode.rawValue, forKey: Keys.translationMode) } }
    /// A `Locale.Language` identifier such as "zh-Hans" or "en".
    var targetLanguage: String { didSet { defaults.set(targetLanguage, forKey: Keys.targetLanguage) } }
    var smartDetection: Bool { didSet { defaults.set(smartDetection, forKey: Keys.smartDetection) } }
    /// Skip content the source app marked concealed, transient or auto-generated.
    var ignoreConcealed: Bool { didSet { defaults.set(ignoreConcealed, forKey: Keys.ignoreConcealed) } }
    /// Ask GitHub for a newer release once every 30 days (`UpdateChecker`).
    var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: Keys.checkForUpdates) } }
    var shortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: Keys.shortcut) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init) ?? .system
        let limit = defaults.integer(forKey: Keys.historyLimit)
        historyLimit = limit > 0 ? limit : 100
        ocrMode = defaults.string(forKey: Keys.ocrMode).flatMap(OCRMode.init) ?? .automatic
        translationMode = defaults.string(forKey: Keys.translationMode).flatMap(TranslationMode.init) ?? .onDemand
        targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? LanguageTools.recommendedTarget()
        smartDetection = defaults.object(forKey: Keys.smartDetection) as? Bool ?? true
        ignoreConcealed = defaults.object(forKey: Keys.ignoreConcealed) as? Bool ?? true
        checkForUpdates = defaults.object(forKey: Keys.checkForUpdates) as? Bool ?? true
        shortcut = defaults.data(forKey: Keys.shortcut).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .standard
    }

    /// Window geometry is UI persistence, not observable application state.
    var panelLayoutData: Data? {
        get { defaults.data(forKey: Keys.panelLayout) }
        set { defaults.set(newValue, forKey: Keys.panelLayout) }
    }

    private enum Keys {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let appearance = "appearance"
        static let panelLayout = "panelLayout"
        static let historyLimit = "historyLimit"
        static let ocrMode = "ocrMode"
        static let translationMode = "translationMode"
        static let targetLanguage = "targetLanguage"
        static let smartDetection = "smartDetection"
        static let ignoreConcealed = "ignoreConcealed"
        static let shortcut = "shortcut"
        static let checkForUpdates = "checkForUpdates"
    }
}
