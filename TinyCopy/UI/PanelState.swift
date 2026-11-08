import Foundation
import Observation

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, text, image, file
    var id: Self { self }
    var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }
    var kind: ClipKind? {
        switch self {
        case .all: return nil
        case .text: return .text
        case .image: return .image
        case .file: return .file
        }
    }
}

/// Vertical navigation chooses history; horizontal navigation chooses how to use that item.
@MainActor
@Observable
final class PanelState {
    let model: AppModel

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            selectedID = nil
            previewChoice = .original
            navigationActive = false
        }
    }
    var filter: HistoryFilter = .all {
        didSet {
            guard filter != oldValue else { return }
            selectedID = nil
            previewChoice = .original
            waiting = nil
            navigationActive = false
        }
    }
    var favoritesOnly = false {
        didSet {
            guard favoritesOnly != oldValue else { return }
            selectedID = nil
            previewChoice = .original
            waiting = nil
            navigationActive = false
        }
    }
    /// nil means the first result.
    var selectedID: UUID? {
        didSet {
            if selectedID != oldValue {
                waiting = nil
                cancelQRGeneration()
                previewChoice = .original
            }
        }
    }
    var historyColumnWidth: CGFloat = Metrics.historyWidth
    var previewVisible = false {
        didSet {
            guard previewVisible != oldValue else { return }
            onPreviewVisibilityChanged?()
        }
    }
    @ObservationIgnored var navigationActive = false
    @ObservationIgnored var onPreviewVisibilityChanged: (() -> Void)?
    /// Original content is always the starting point for a newly selected record.
    enum PreviewChoice: Hashable { case original, action(SmartActionKind) }
    var previewChoice: PreviewChoice = .original { didSet { if previewChoice != oldValue { waiting = nil } } }
    /// Bumped on every show so the search field takes focus again.
    var focusToken = 0
    var now = Date()

    /// Called with the item and the converted text (nil for the original); `paste` false means copy only.
    @ObservationIgnored var perform: ((ClipItem, String?, Bool) -> Void)?
    @ObservationIgnored var close: (() -> Void)?
    @ObservationIgnored var performImage: ((Data, Bool) -> Void)?
    @ObservationIgnored private var qrPNG: Data?
    @ObservationIgnored private var qrGenerationTask: Task<Void, Never>?
    private(set) var qrReadyID: UUID?
    private(set) var qrGeneratingID: UUID?
    private(set) var qrFailedID: UUID?

    var qrCodeData: Data? { qrReadyID == selected?.id ? qrPNG : nil }

    private func cancelQRGeneration() {
        qrGenerationTask?.cancel()
        qrGenerationTask = nil
        qrGeneratingID = nil
    }

    private func requestQRCode() {
        guard let item = selected, QRCode.canGenerateURL(item.text), qrCodeData == nil,
              qrGeneratingID != item.id else { return }
        cancelQRGeneration()
        qrGeneratingID = item.id
        qrFailedID = nil
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = item.id
        qrGenerationTask = Task { [weak self] in
            let data = await Task.detached(priority: .userInitiated) { QRCode.encode(text) }.value
            guard !Task.isCancelled, let self, self.selected?.id == id else { return }
            self.qrPNG = data
            self.qrReadyID = data == nil ? nil : id
            self.qrFailedID = data == nil ? id : nil
            self.qrGeneratingID = nil
            self.qrGenerationTask = nil
            self.itemUpdated(id)
        }
    }

    /// An action the user chose before its result existed (OCR or translation still running).
    /// Dropped as soon as the user moves on (other item or action, card or panel closed), so a late
    /// result never pastes into whatever app is in front by then.
    @ObservationIgnored private var waiting: (id: UUID, kind: SmartActionKind, paste: Bool)?
    /// Conversions are costly for large text (~0.1 s for 1 MB of JSON) and every visible row's context
    /// menu asks for them on each redraw, so they are computed once per item version.
    @ObservationIgnored private var cachedActions: [UUID: (item: ClipItem, context: String, actions: [SmartAction])] = [:]

    init(model: AppModel) {
        self.model = model
        model.onItemUpdated = { [weak self] id in self?.itemUpdated(id) }
    }

    var results: [ClipItem] {
        let matches = model.search(query)
        return matches.filter { item in
            (!favoritesOnly || item.pinned) && (filter.kind.map { item.kind == $0 } ?? true)
        }
    }

    var selected: ClipItem? {
        let results = results
        return results.first { $0.id == selectedID } ?? results.first
    }

    var actions: [SmartAction] {
        guard let item = selected else { return [] }
        return actions(for: item)
    }

    func actions(for item: ClipItem) -> [SmartAction] {
        let context = model.smartContext
        let key = "\(context.smartDetection)|\(context.ocrMode.rawValue)|\(context.translationTarget ?? "")"
        if let cached = cachedActions[item.id], cached.context == key, cached.item == item { return cached.actions }
        let list = SmartActions.actions(for: item, context: context)
        cachedActions[item.id] = (item, key, list)
        return list
    }

    var primaryActions: [SmartAction] { actions.filter(\.isPrimary) }
    var moreActions: [SmartAction] { actions.filter { !$0.isPrimary } }
    var previewChoices: [PreviewChoice] { [.original] + primaryActions.map { .action($0.kind) } }

    private var availableChoices: [PreviewChoice] { [.original] + actions.map { .action($0.kind) } }

    var currentPreview: PreviewChoice {
        availableChoices.contains(previewChoice) ? previewChoice : .original
    }

    var selectedAction: SmartAction? {
        guard case .action(let kind) = currentPreview else { return nil }
        return actions.first { $0.kind == kind }
    }

    func choosePreview(_ choice: PreviewChoice) {
        guard let item = selected, availableChoices.contains(choice) else { return }
        // Pin the current record before starting work; new captures must not change its identity.
        selectedID = item.id
        navigationActive = true
        previewVisible = true
        previewChoice = choice
        startPendingWork()
    }

    /// Left/right (and Tab) have one meaning, regardless of which pane was last clicked.
    func movePreview(_ delta: Int) {
        guard selected != nil else { return }
        let choices = previewChoices
        let current = choices.firstIndex(of: currentPreview) ?? 0
        choosePreview(choices[min(max(current + delta, 0), choices.count - 1)])
    }

    func collapsePreview() {
        waiting = nil
        previewChoice = .original
        previewVisible = false
    }

    func editSearch() {
        navigationActive = false
        previewChoice = .original
        waiting = nil
    }

    /// Results are visible alongside the source, so prepare them even while the source is selected.
    /// A missing translation language never opens a download prompt without an explicit click.
    func preparePreview() {
        guard previewVisible else { return }
        if let item = selected, item.kind == .image { model.requestQRDetection(item.id) }
        primaryActions.forEach { requestPreview($0) }
    }

    func requestPreview(_ action: SmartAction, interactive: Bool = false) {
        guard let item = selected, action.result == nil else { return }
        switch action.kind {
        case .qrGenerate: requestQRCode()
        case .ocr: model.requestOCR(item.id)
        case .translate: model.requestTranslation(item.id, interactive: interactive)
        default: break
        }
    }

    func prepareForShow() {
        query = ""
        filter = .all
        favoritesOnly = false
        selectedID = nil
        previewChoice = .original
        navigationActive = false
        previewVisible = false
        waiting = nil
        now = Date()
        focusToken += 1
        let live = Set(model.items.map(\.id))
        cachedActions = cachedActions.filter { live.contains($0.key) }
    }

    /// The panel closed: nothing chosen earlier may paste later.
    func cancelPending() {
        waiting = nil
        cancelQRGeneration()
    }

    // MARK: Keyboard

    func move(_ delta: Int) {
        let results = results
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selected?.id } ?? 0
        select(results[min(max(current + delta, 0), results.count - 1)].id)
    }

    func select(_ id: UUID) {
        selectedID = id
        // Reset even when Up/Down hits the list boundary or the same row is clicked again.
        waiting = nil
        previewChoice = .original
        navigationActive = true
        previewVisible = true
    }

    /// Enter uses exactly the currently selected original or transformation.
    func activate(paste: Bool) {
        guard let item = selected else { return }
        guard let action = selectedAction else {
            perform?(item, nil, paste)
            return
        }
        if action.kind == .qrGenerate {
            if let data = qrCodeData { performImage?(data, paste) }
            else {
                waiting = (item.id, action.kind, paste)
                requestQRCode()
            }
        } else if let result = action.result {
            perform?(item, result, paste)
        } else {
            waiting = (item.id, action.kind, paste)
            startPendingWork(force: true)
        }
    }

    /// Runs one conversion of an item (the context menu): pastes at once when the result exists,
    /// else reveals the preview while OCR or translation produces it, then pastes.
    func run(_ kind: SmartActionKind, on id: UUID) {
        select(id)
        guard actions.contains(where: { $0.kind == kind }) else { return }
        choosePreview(.action(kind))
        activate(paste: true)
    }

    /// Escape first clears processing and folds the preview away, then closes the panel.
    func escape() {
        if previewVisible { collapsePreview() } else { close?() }
    }

    func togglePinSelected() {
        guard let item = selected else { return }
        model.togglePin(item.id)
        if model.item(item.id) == nil || (favoritesOnly && model.item(item.id)?.pinned != true) {
            selectedID = nil
            previewChoice = .original
            waiting = nil
        }
    }

    func deleteSelected() {
        guard let item = selected else { return }
        let results = results
        if let index = results.firstIndex(where: { $0.id == item.id }) {
            selectedID = results.indices.contains(index + 1) ? results[index + 1].id : (index > 0 ? results[index - 1].id : nil)
        }
        waiting = nil
        previewChoice = .original
        model.delete(item.id)
        if selected == nil { collapsePreview() }
    }

    /// Starts OCR or translation for the highlighted action when its result does not exist yet.
    /// Highlighting starts work that needs no prompt; Enter (`force`) may also let the system ask to
    /// download a translation language.
    private func startPendingWork(force: Bool = false) {
        guard let action = selectedAction else { return }
        requestPreview(action, interactive: force)
    }

    private func itemUpdated(_ id: UUID) {
        guard let waiting, waiting.id == id, let item = model.item(id) else { return }
        if waiting.kind == .qrGenerate {
            if let data = qrCodeData {
                self.waiting = nil
                performImage?(data, waiting.paste)
            } else if qrFailedID == id {
                self.waiting = nil
            }
            return
        }
        let action = actions(for: item).first { $0.kind == waiting.kind }
        if let result = action?.result {
            self.waiting = nil
            perform?(item, result, waiting.paste)
        } else if model.translationErrors[id] != nil || (waiting.kind == .ocr && item.ocrText == "") {
            self.waiting = nil
        }
    }
}
