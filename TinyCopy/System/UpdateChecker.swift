import AppKit
import Observation

/// Asks GitHub for the latest release and, when it is newer, offers to open its page. Nothing is downloaded
/// or installed: the user gets the DMG from the page. The automatic check runs at most once every
/// `interval`, at launch and when the panel opens (no timer). A failure (offline, GitHub unreachable,
/// a bad answer) is skipped silently, for manual checks too.
///
/// A menu bar app is rarely active, and an alert would take focus from the app the user is pasting into,
/// so an automatic find never interrupts: it only shows in the panel footer, the menu and Settings.
/// Everything read from the network is optional and validated; a bad answer only means "no update".
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let interval: TimeInterval = 30 * 24 * 60 * 60
    /// Automatic attempts that failed (offline, rate limited) are retried no sooner than this.
    static let retryDelay: TimeInterval = 60 * 60
    nonisolated static let latestReleaseAPI = URL(string: "https://api.github.com/repos/YangHanqing/tinycopy/releases/latest")!
    nonisolated static let releasesPage = URL(string: "https://github.com/YangHanqing/tinycopy/releases/latest")!

    struct Release: Sendable, Equatable {
        let version: [Int]
        let versionString: String
        let page: URL
    }

    /// A newer release found by any check and not skipped. Written only when the answer changes.
    private(set) var available: Release?

    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private var manualRequested = false
    @ObservationIgnored private var lastAttempt: Date?

    private enum Key {
        static let lastCheck = "updates.lastCheck"
        static let skippedVersion = "updates.skippedVersion"
    }

    // MARK: Entry points

    /// Called once at launch: waits for the app to settle, then checks if due.
    func scheduleLaunchCheck() {
        guard Self.automaticChecksAllowed else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            checkIfDue()
        }
    }

    /// Automatic check: only when enabled and due. Cheap when not due (a date comparison).
    func checkIfDue() {
        guard Self.automaticChecksAllowed, AppSettings.shared.checkForUpdates else { return }
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: Key.lastCheck) as? Date,
           now >= last, now.timeIntervalSince(last) < Self.interval { return }
        if let attempt = lastAttempt, now >= attempt, now.timeIntervalSince(attempt) < Self.retryDelay { return }
        start(manual: false)
    }

    /// 检查更新… in the menu and Settings: reports "up to date" or the offer; a failure stays silent.
    func checkNow() {
        start(manual: true)
    }

    /// The footer and menu entry: opens the release page.
    func openAvailable() {
        NSWorkspace.shared.open(available?.page ?? Self.releasesPage)
    }

    // MARK: Check

    private func start(manual: Bool) {
        if manual { manualRequested = true }
        guard !isChecking else { return }
        isChecking = true
        lastAttempt = Date()
        Task { @MainActor in
            let result = await Self.fetchLatest()
            isChecking = false
            let wasManual = manualRequested
            manualRequested = false
            finish(result, manual: wasManual)
        }
    }

    private func finish(_ result: Release?, manual: Bool) {
        // A network or server failure is never reported, not even for a manual check: it is skipped.
        guard let release = result else { return }
        UserDefaults.standard.set(Date(), forKey: Key.lastCheck)
        guard let current = Self.currentVersion, Self.isNewer(release.version, than: current) else {
            if available != nil { available = nil }
            if manual { showUpToDate() }
            return
        }
        let skipped = UserDefaults.standard.string(forKey: Key.skippedVersion) == release.versionString
        let shown = skipped && !manual ? nil : release
        if available != shown { available = shown }
        if manual { present(release) }
    }

    /// `nil` on any failure: transport, status, size, JSON shape, unparsable tag.
    nonisolated private static func fetchLatest() async -> Release? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TinyCopy", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 4 * 1024 * 1024 else { return nil }
        return parseRelease(data)
    }

    private struct ReleaseJSON: Decodable {
        let tag_name: String?
        let html_url: String?
        let draft: Bool?
        let prerelease: Bool?
    }

    nonisolated static func parseRelease(_ data: Data) -> Release? {
        guard let json = try? JSONDecoder().decode(ReleaseJSON.self, from: data),
              json.draft != true, json.prerelease != true,
              let tag = json.tag_name, let version = parseVersion(tag) else { return nil }
        return Release(version: version, versionString: version.map(String.init).joined(separator: "."),
                       page: safePage(json.html_url))
    }

    /// Only a page of this repository on github.com is opened; anything else falls back to the releases page.
    nonisolated private static func safePage(_ string: String?) -> URL {
        guard let string, let url = URL(string: string), url.scheme == "https",
              url.host?.lowercased() == "github.com",
              url.path.lowercased().hasPrefix("/yanghanqing/tinycopy/") else { return releasesPage }
        return url
    }

    /// `v0.5.12` or `0.5.12` → `[0, 5, 12]`; anything else (suffixes, empty parts, huge numbers) → `nil`.
    nonisolated static func parseVersion(_ string: String) -> [Int]? {
        var s = Substring(string.trimmingCharacters(in: .whitespacesAndNewlines))
        if s.first == "v" || s.first == "V" { s = s.dropFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 6, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let n = Int(part) else { return nil }
            numbers.append(n)
        }
        return numbers
    }

    nonisolated static func isNewer(_ a: [Int], than b: [Int]) -> Bool {
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private static var currentVersion: [Int]? { parseVersion(currentVersionString) }

    /// Debug builds and tests never check by themselves; 立即检查 still works there.
    private static var automaticChecksAllowed: Bool {
        #if DEBUG
        return false
        #else
        return !AppDelegate.isTesting
        #endif
    }

    // MARK: Alerts (manual checks only)

    private func present(_ release: Release) {
        AppDelegate.shared?.panel?.hide()
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "TinyCopy \(release.versionString) 已发布"
        alert.informativeText = "当前版本为 \(Self.currentVersionString)。在发布页面下载新版本，拖入“应用程序”文件夹替换即可。"
        alert.addButton(withTitle: "下载")
        alert.addButton(withTitle: "跳过此版本")
        alert.addButton(withTitle: "以后")
        alert.buttons[2].keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.page)
        case .alertSecondButtonReturn:
            UserDefaults.standard.set(release.versionString, forKey: Key.skippedVersion)
            available = nil
        default:
            break
        }
    }

    private func showUpToDate() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "已是最新版本"
        alert.informativeText = "TinyCopy \(Self.currentVersionString) 是目前的最新版本。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
