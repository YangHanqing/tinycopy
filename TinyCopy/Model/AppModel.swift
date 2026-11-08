import AppKit
import Observation

/// The history and everything that changes it: capture, de-duplication, eviction, persistence,
/// OCR and translation results. The UI only reads it and calls its methods.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel(store: HistoryStore(root: HistoryStore.defaultRoot), settings: .shared, pasteboard: .general)

    let store: HistoryStore
    let settings: AppSettings
    @ObservationIgnored let pasteboard: NSPasteboard

    /// Newest copy first.
    private(set) var items: [ClipItem] = []
    private(set) var ocrRunning: Set<UUID> = []
    private(set) var translating: Set<UUID> = []
    private(set) var translationErrors: [UUID: String] = [:]

    /// Called after an item's OCR or translation result arrives (the panel finishes a waiting paste).
    @ObservationIgnored var onItemUpdated: ((UUID) -> Void)?

    @ObservationIgnored private var searchIndex: [UUID: SearchEntry] = [:]
    @ObservationIgnored private var lastChangeCount: Int
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var captureChain: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var qrQueue: [UUID] = []
    @ObservationIgnored private var qrTask: Task<Void, Never>?
    @ObservationIgnored private var qrReading: Set<UUID> = []
    @ObservationIgnored private var ocrQueue: [UUID] = []
    @ObservationIgnored private var ocrTask: Task<Void, Never>?
    @ObservationIgnored private let thumbnails = NSCache<NSString, NSImage>()
    @ObservationIgnored private var translationEngineBox: AnyObject?
    @ObservationIgnored private var interactiveRetry: Set<UUID> = []

    init(store: HistoryStore, settings: AppSettings, pasteboard: NSPasteboard) {
        self.store = store
        self.settings = settings
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
        let loaded = store.loadIndex()
        items = loaded.items.sorted { $0.lastCopied > $1.lastCopied }
        items.forEach(reindex)
        // After a partial read the unlisted files may belong to entries in the kept copy of the index.
        if loaded.complete { store.removeOrphans(keeping: Set(items.map(\.id))) }
        if #available(macOS 15.0, *) {
            let engine = TranslationEngine()
            engine.deliver = { [weak self] job, result in self?.deliverTranslation(job, result) }
            translationEngineBox = engine
        }
    }

    // MARK: Monitoring

    /// The pasteboard has no change notification; its change count is cheap to poll.
    func startMonitoring() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if settings.smartDetection {
            items.filter { $0.kind == .image && $0.qrContents == nil }.forEach { requestQRDetection($0.id) }
        }
        if settings.ocrMode == .automatic {
            items.filter { $0.kind == .image && $0.ocrText == nil }.forEach { requestOCR($0.id) }
        }
    }

    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard let clip = PasteboardIO.read(pasteboard, ignoreConcealed: settings.ignoreConcealed) else { return }
        let date = Date()
        let previous = captureChain
        captureChain = Task { [weak self] in
            await previous?.value
            await self?.ingest(clip, at: date)
        }
    }

    /// Waits for captures and OCR in flight. For tests.
    func waitForBackgroundWork() async {
        await captureChain?.value
        while let task = qrTask { await task.value }
        while let task = ocrTask { await task.value }
    }

    private func ingest(_ clip: CapturedClip, at date: Date) async {
        guard let processed = await Task.detached(priority: .userInitiated, operation: { ClipProcessing.process(clip) }).value
        else { return }
        if let index = items.firstIndex(where: { $0.hash == processed.hash && $0.kind == clip.kind }) {
            var item = items.remove(at: index)
            item.lastCopied = date
            item.isRich = clip.isRich
            items.insert(item, at: 0)
            // Keep the newest representations (the same text may arrive with other formatting).
            store.saveContent(processed.content, thumbnail: nil, for: item.id)
            didChange()
            return
        }
        var item = ClipItem(id: UUID(), kind: clip.kind, text: clip.text, hash: processed.hash,
                            created: date, lastCopied: date, isRich: clip.isRich,
                            imageWidth: processed.width, imageHeight: processed.height)
        if clip.kind == .text {
            let text = clip.text
            let analysis = await Task.detached(priority: .utility, operation: { Self.analyze(text) }).value
            item.contentType = analysis.type
            item.derivedText = analysis.derived
            item.language = analysis.language
        }
        store.saveContent(processed.content, thumbnail: processed.thumbnail, for: item.id)
        if let data = processed.thumbnail, let image = NSImage(data: data) {
            thumbnails.setObject(image, forKey: item.id.uuidString as NSString)
        }
        items.insert(item, at: 0)
        reindex(item)
        evictOverLimit()
        didChange()
        if item.kind == .image { requestQRDetection(item.id) }
        if item.kind == .image, settings.ocrMode == .automatic { requestOCR(item.id) }
        if item.kind == .text, settings.translationMode == .automatic { requestTranslation(item.id, interactive: false) }
    }

    nonisolated static func analyze(_ text: String) -> (type: ContentType, derived: String?, language: String?) {
        let detected = ContentDetector.detect(text)
        let language = detected.type == .plain ? LanguageTools.proseLanguage(of: text) : nil
        return (detected.type, detected.derived, language)
    }

    // MARK: Editing

    func item(_ id: UUID) -> ClipItem? { items.first { $0.id == id } }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        evictOverLimit()
        didChange()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        forget([id])
        didChange()
    }

    func clearHistory(keepPinned: Bool) {
        let removed = items.filter { !keepPinned || !$0.pinned }.map(\.id)
        items.removeAll { !keepPinned || !$0.pinned }
        forget(removed)
        didChange()
    }

    /// Pinned items never count toward the limit.
    func evictOverLimit() {
        var unpinned = 0
        var removed: [UUID] = []
        for item in items where !item.pinned {
            unpinned += 1
            if unpinned > settings.historyLimit { removed.append(item.id) }
        }
        guard !removed.isEmpty else { return }
        let set = Set(removed)
        items.removeAll { set.contains($0.id) }
        forget(removed)
        didChange()
    }

    private func forget(_ ids: [UUID]) {
        for id in ids {
            searchIndex[id] = nil
            thumbnails.removeObject(forKey: id.uuidString as NSString)
            translationErrors[id] = nil
        }
        qrQueue.removeAll { ids.contains($0) }
        ocrQueue.removeAll { ids.contains($0) }
        store.delete(ids)
    }

    private func update(_ id: UUID, _ change: (inout ClipItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        reindex(items[index])
        didChange()
        onItemUpdated?(id)
    }

    private func didChange() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.store.saveIndex(self.items)
        }
    }

    /// Writes the index now. Called at quit and by tests.
    func flush() {
        saveTask?.cancel()
        store.saveIndexNow(items)
    }

    // MARK: Pasteboard output

    /// Puts the item (or a conversion of it) on the pasteboard without recording it as a new copy.
    /// Pasting the original moves it to the top of the history.
    func writeToPasteboard(_ id: UUID, text: String? = nil) {
        guard let item = item(id) else { return }
        if let text {
            PasteboardIO.writePlainText(text, to: pasteboard)
        } else if let content = store.content(for: id), !content.items.isEmpty {
            PasteboardIO.write(content, kind: item.kind, to: pasteboard)
        } else if item.kind == .text {
            PasteboardIO.writePlainText(item.text, to: pasteboard)
        } else {
            return
        }
        lastChangeCount = pasteboard.changeCount
        if text == nil, let index = items.firstIndex(where: { $0.id == id }) {
            var moved = items.remove(at: index)
            moved.lastCopied = Date()
            items.insert(moved, at: 0)
            didChange()
        }
    }

    /// Generated images are output only: they never replace the source URL or re-enter history.
    func writeImageToPasteboard(_ png: Data) {
        let content = ClipContent(items: [[TypedData(type: NSPasteboard.PasteboardType.png.rawValue, data: png)]])
        PasteboardIO.write(content, kind: .image, to: pasteboard)
        lastChangeCount = pasteboard.changeCount
    }

    // MARK: Search

    private struct SearchEntry {
        var primary: String
        var secondary: String
    }

    private func reindex(_ item: ClipItem) {
        var primary = String(item.text.prefix(50_000)).lowercased()
        if item.kind == .file { primary = item.fileURLs.map(\.lastPathComponent).joined(separator: "\n").lowercased() + "\n" + primary }
        let secondary = ([item.ocrText, item.derivedText].compactMap { $0 } + (item.qrContents ?? []) + Array(item.translations.values))
            .joined(separator: "\n").prefix(50_000).lowercased()
        searchIndex[item.id] = SearchEntry(primary: primary, secondary: secondary)
    }

    /// Every term must match (case-insensitive). Ranking: text starting with a term, then a match at a
    /// word start, then anywhere, then only in OCR or decoded text; newer first within each rank.
    func search(_ query: String) -> [ClipItem] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return items }
        var scored: [(score: Int, item: ClipItem)] = []
        for item in items {
            guard let entry = searchIndex[item.id] else { continue }
            var score = 0
            var matched = true
            for term in terms {
                if let range = entry.primary.range(of: term) {
                    if range.lowerBound == entry.primary.startIndex {
                        score += 3
                    } else {
                        let before = entry.primary[entry.primary.index(before: range.lowerBound)]
                        score += before.isLetter || before.isNumber ? 1 : 2
                    }
                } else if !entry.secondary.contains(term) {
                    matched = false
                    break
                }
            }
            if matched { scored.append((score, item)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.item.lastCopied > $1.item.lastCopied }.map(\.item)
    }

    // MARK: Thumbnails

    func thumbnail(for item: ClipItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let image = thumbnails.object(forKey: key) { return image }
        var image = NSImage(contentsOf: store.thumbnailURL(item.id))
        if image == nil, item.kind == .file, let url = item.fileURLs.first {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    // MARK: Smart features

    var translationAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    var smartContext: SmartContext {
        SmartContext(smartDetection: settings.smartDetection, ocrMode: settings.ocrMode,
                     translationTarget: translationAvailable && settings.translationMode != .off ? settings.targetLanguage : nil)
    }

    /// QR recognition is separate from OCR, so it works even when text recognition is disabled.
    func requestQRDetection(_ id: UUID) {
        guard settings.smartDetection, let item = item(id), item.kind == .image, item.qrContents == nil,
              !qrQueue.contains(id), !qrReading.contains(id) else { return }
        qrQueue.insert(id, at: 0)
        guard qrTask == nil else { return }
        qrTask = Task { [weak self] in
            while let self, !self.qrQueue.isEmpty {
                let next = self.qrQueue.removeFirst()
                self.qrReading.insert(next)
                let store = self.store
                let contents = await Task.detached(priority: .utility) { () -> [String] in
                    guard let png = store.content(for: next)?.items.first?.first?.data else { return [] }
                    return QRCode.decode(png)
                }.value
                self.qrReading.remove(next)
                self.update(next) { $0.qrContents = contents }
            }
            self?.qrTask = nil
        }
    }

    /// One image at a time, newest request first, off the main thread.
    func requestOCR(_ id: UUID) {
        guard settings.ocrMode != .off, let item = item(id), item.kind == .image, item.ocrText == nil,
              !ocrQueue.contains(id), !ocrRunning.contains(id) else { return }
        ocrQueue.insert(id, at: 0)
        guard ocrTask == nil else { return }
        ocrTask = Task { [weak self] in
            while let self, !self.ocrQueue.isEmpty {
                let next = self.ocrQueue.removeFirst()
                self.ocrRunning.insert(next)
                let store = self.store
                let text = await Task.detached(priority: .utility) { () -> String? in
                    guard let png = store.content(for: next)?.items.first?.first?.data else { return nil }
                    return await TextRecognizer.recognize(imageData: png)
                }.value
                self.ocrRunning.remove(next)
                self.update(next) { $0.ocrText = text ?? "" }
            }
            self?.ocrTask = nil
        }
    }

    /// `interactive` means the user asked for it now: a missing language pack may then prompt a download.
    func requestTranslation(_ id: UUID, interactive: Bool) {
        guard #available(macOS 15.0, *), let engine = translationEngineBox as? TranslationEngine,
              let target = smartContext.translationTarget, let item = item(id), let language = item.language,
              !LanguageTools.sameLanguage(language, target), item.translations[target] == nil else { return }
        guard !translating.contains(id) else {
            // A background attempt is in flight; if it is skipped for a missing language, retry as asked.
            if interactive { interactiveRetry.insert(id) }
            return
        }
        translationErrors[id] = nil
        translating.insert(id)
        engine.enqueue(.init(id: id, text: item.text, source: language, target: target), interactive: interactive)
    }

    @available(macOS 15.0, *)
    var translationEngine: TranslationEngine? { translationEngineBox as? TranslationEngine }

    @available(macOS 15.0, *)
    private func deliverTranslation(_ job: TranslationEngine.Job, _ outcome: TranslationEngine.Outcome) {
        translating.remove(job.id)
        switch outcome {
        case .translated(let text):
            update(job.id) { $0.translations[job.target] = text }
        case .skipped:
            if interactiveRetry.remove(job.id) != nil { requestTranslation(job.id, interactive: true) }
        case .failed(let message):
            translationErrors[job.id] = message
            onItemUpdated?(job.id)
        }
    }
}
