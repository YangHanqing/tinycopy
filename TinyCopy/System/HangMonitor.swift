import AppKit

/// Records main-thread stalls (the spinning beachball) to `~/Library/Logs/TinyCopy`, so a user can
/// send the files afterwards. A watchdog thread pings the main queue; when a ping goes unanswered
/// for `threshold`, it starts `/usr/bin/sample` on this process and, once the main thread is back,
/// logs how long it was stuck and what the app was doing. Nothing here may contain clipboard text:
/// breadcrumbs carry only kinds, sizes and action names.
final class HangMonitor: @unchecked Sendable {
    static let shared = HangMonitor()

    static var logDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/TinyCopy", isDirectory: true)
    }

    private let threshold: TimeInterval = 0.5
    private let sampleSeconds = 3
    private let minimumSampleGap: TimeInterval = 60
    private let maxSampleFiles = 10
    private let maxLogBytes = 1_000_000

    private let lock = NSLock()
    private var lastPong = Date()
    private var breadcrumb = "启动"
    private var started = false

    private let fileQueue = DispatchQueue(label: "cn.hqyang.TinyCopy.diagnostics")
    private lazy var logURL = Self.logDirectory.appendingPathComponent("diagnostics.log")
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// What the app is doing right now; shown next to any stall that follows. No clipboard content.
    static func note(_ text: String) {
        shared.lock.withLock { shared.breadcrumb = text }
    }

    func start() {
        let first = lock.withLock { () -> Bool in
            defer { started = true }
            return !started
        }
        guard first else { return }
        try? FileManager.default.createDirectory(at: Self.logDirectory, withIntermediateDirectories: true)
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        log("启动 TinyCopy \(version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(String(cString: model))")
        let thread = Thread { [self] in watch() }
        thread.name = "TinyCopy.HangMonitor"
        thread.qualityOfService = .utility
        thread.start()
    }

    private func watch() {
        var stalledSince: Date?
        var stalledCrumb = ""
        var lastSample = Date.distantPast
        while true {
            DispatchQueue.main.async { [self] in lock.withLock { lastPong = Date() } }
            Thread.sleep(forTimeInterval: 0.1)
            let (pong, crumb) = lock.withLock { (lastPong, breadcrumb) }
            let now = Date()
            if now.timeIntervalSince(pong) > threshold {
                if stalledSince == nil {
                    stalledSince = pong
                    stalledCrumb = crumb
                    if now.timeIntervalSince(lastSample) > minimumSampleGap {
                        lastSample = now
                        startSample()
                    }
                }
            } else if let since = stalledSince {
                stalledSince = nil
                let ms = Int(pong.timeIntervalSince(since) * 1000)
                log("主线程卡住约 \(ms) ms · 当时：\(stalledCrumb)")
            }
        }
    }

    private func startSample() {
        let name = "hang-\(fileStamp()).txt"
        let output = Self.logDirectory.appendingPathComponent(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "\(sampleSeconds)", "-mayDie", "-file", output.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            log("开始采样主线程 → \(name)")
        } catch {
            log("无法启动采样：\(error.localizedDescription)")
        }
        pruneSamples()
    }

    private func fileStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private func pruneSamples() {
        fileQueue.async { [self] in
            let fm = FileManager.default
            let files = ((try? fm.contentsOfDirectory(at: Self.logDirectory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("hang-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            files.dropFirst(maxSampleFiles).forEach { try? fm.removeItem(at: $0) }
        }
    }

    func log(_ message: String) {
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        fileQueue.async { [self] in
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: logURL.path))?[.size] as? Int, size > maxLogBytes {
                let old = logURL.deletingPathExtension().appendingPathExtension("old.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: logURL, to: old)
            }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: logURL)
            }
        }
    }

    /// A content-free description of an item for breadcrumbs.
    static func describe(_ item: ClipItem) -> String {
        var parts = [item.kind.rawValue]
        if item.isRich { parts.append("rich") }
        if item.contentType != .plain { parts.append(item.contentType.rawValue) }
        if item.kind == .text {
            let bytes = item.text.utf8.count
            parts.append("\(bytes) 字节")
            if bytes < 2_000_000 { parts.append("\(item.text.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }) 行") }
            if let language = item.language { parts.append(language) }
        }
        if let w = item.imageWidth, let h = item.imageHeight { parts.append("\(w)×\(h)") }
        return parts.joined(separator: " ")
    }
}
