import SwiftUI
@preconcurrency import Translation

/// Apple Translation (macOS 15+), on device.
/// - Installed language pair on macOS 26+: translated directly, in the background.
/// - Otherwise a session only exists inside SwiftUI's `.translationTask`, so the panel hosts
///   `TranslationHost` and jobs wait here until it runs them. A missing language pack makes the
///   system ask to download it there, so that route is taken only when the user asked (`interactive`).
@available(macOS 15.0, *)
@MainActor
@Observable
final class TranslationEngine {
    struct Job: Equatable {
        var id: UUID
        var text: String
        var source: String
        var target: String
    }

    var configuration: TranslationSession.Configuration?
    @ObservationIgnored private var jobs: [Job] = []
    @ObservationIgnored private var running = false
    @ObservationIgnored var deliver: ((Job, Outcome) -> Void)?

    enum Outcome {
        case translated(String)
        /// The language pack is not installed and the request was not interactive; nothing was shown.
        case skipped
        case failed(String)
    }

    func enqueue(_ job: Job, interactive: Bool) {
        guard !jobs.contains(where: { $0.id == job.id && $0.target == job.target }) else { return }
        Task {
            let source = Locale.Language(identifier: job.source), target = Locale.Language(identifier: job.target)
            let status = await LanguageAvailability().status(from: source, to: target)
            switch status {
            case .installed:
                if #available(macOS 26.0, *) {
                    await translateDirectly(job)
                    return
                }
            case .supported:
                guard interactive else {
                    deliver?(job, .skipped)
                    return
                }
            default:
                deliver?(job, .failed("系统翻译不支持从\(LanguageTools.displayName(job.source))翻译为\(LanguageTools.displayName(job.target))。"))
                return
            }
            jobs.append(job)
            if !running { start() }
        }
    }

    @available(macOS 26.0, *)
    private func translateDirectly(_ job: Job) async {
        let session = TranslationSession(installedSource: Locale.Language(identifier: job.source),
                                         target: Locale.Language(identifier: job.target))
        do {
            deliver?(job, .translated(try await session.translate(job.text).targetText))
        } catch {
            deliver?(job, .failed(Self.failureMessage))
        }
    }

    static let failureMessage = "系统翻译暂不可用。可在“系统设置 ▸ 通用 ▸ 语言与地区 ▸ 翻译语言”中下载所需语言。"

    private func start() {
        guard let next = jobs.first else { return }
        let source = Locale.Language(identifier: next.source), target = Locale.Language(identifier: next.target)
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    func run(_ session: TranslationSession) async {
        guard !running, let config = configuration else { return }
        running = true
        while let index = jobs.firstIndex(where: {
            Locale.Language(identifier: $0.source) == config.source && Locale.Language(identifier: $0.target) == config.target
        }) {
            let job = jobs[index]
            do {
                let response = try await session.translate(job.text)
                deliver?(job, .translated(response.targetText))
            } catch {
                deliver?(job, .failed(Self.failureMessage))
            }
            jobs.removeAll { $0 == job }
        }
        running = false
        if !jobs.isEmpty { start() }
    }

    nonisolated static func supportedTargets() async -> [String] {
        let languages = await LanguageAvailability().supportedLanguages
        var ids: [String] = []
        for language in languages {
            let id = language.languageCode?.identifier == "zh" ? LanguageTools.normalized(language.maximalIdentifier) : language.minimalIdentifier
            if !ids.contains(id) { ids.append(id) }
        }
        return ids.sorted { LanguageTools.displayName($0).localizedStandardCompare(LanguageTools.displayName($1)) == .orderedAscending }
    }
}

@available(macOS 15.0, *)
struct TranslationHost: View {
    let engine: TranslationEngine

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(engine.configuration) { session in
                await engine.run(session)
            }
    }
}
