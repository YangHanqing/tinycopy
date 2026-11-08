import SwiftUI

enum Metrics {
    static let minimumPanelSize = CGSize(width: 560, height: 400)
    static let minimumExpandedSize = CGSize(width: 960, height: 400)
    static let minimumSettingsSize = CGSize(width: 640, height: 460)
    static let panelSize = CGSize(width: 620, height: 520)
    static let expandedWidth: CGFloat = 1180
    static let historyWidth: CGFloat = 620
    static let searchArea: CGFloat = 56
    static let searchField: CGFloat = 36
    static let historyRow: CGFloat = 64
    static let leadingSize: CGFloat = 40
    static let footer: CGFloat = 32
    static let padding: CGFloat = 12
    static let cornerRadius: CGFloat = 13
}

struct MainView: View {
    @Bindable var state: PanelState
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    searchBar
                    filters
                    Divider()
                    HistoryList(state: state)
                        .frame(maxHeight: .infinity)
                    Divider()
                    footer
                }
                .frame(width: state.previewVisible ? min(state.historyColumnWidth, geometry.size.width - 340) : geometry.size.width)
                if state.previewVisible {
                    Divider()
                    if let item = state.selected {
                        ActionsCard(state: state, item: item)
                            .id(item.id)
                    } else {
                        ContentUnavailableView("没有选中的记录", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .background(translationHost)
        .preferredColorScheme(state.model.settings.appearance.colorScheme)
        .onChange(of: state.focusToken, initial: true) { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: $state.query, prompt: Text("搜索剪贴板历史"))
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
                .onTapGesture { state.editSearch() }
            if !state.query.isEmpty {
                Button {
                    state.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Metrics.searchField)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, Metrics.padding)
        .frame(height: Metrics.searchArea)
        .overlay(alignment: .top) { WindowDragArea().frame(height: 10).accessibilityHidden(true) }
        .overlay(alignment: .bottom) { WindowDragArea().frame(height: 10).accessibilityHidden(true) }
    }

    private var filters: some View {
        HStack(spacing: 6) {
            ForEach(HistoryFilter.allCases) { filter in
                HistoryFilterButton(title: filter.title, selected: state.filter == filter) {
                    state.filter = filter
                }
            }
            Button { state.favoritesOnly.toggle() } label: {
                Image(systemName: state.favoritesOnly ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(state.favoritesOnly ? Color.accentColor : .secondary)
                    .frame(width: 36, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(state.favoritesOnly ? Color.accentColor.opacity(0.18) : .clear))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("只看收藏")
            .help("只看收藏，可与分类和搜索同时使用")
            .accessibilityAddTraits(state.favoritesOnly ? [.isSelected] : [])
        }
        .padding(.horizontal, Metrics.padding)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            hint("↑↓", "选记录")
            hint("←→", "选处理")
            hint("↩", "粘贴")
            hint("esc", state.previewVisible ? "收起" : "关闭")
            Spacer(minLength: 0)
            hint("⌘P", "收藏")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.padding + 4)
        .frame(height: Metrics.footer)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).fontWeight(.medium).foregroundStyle(.primary.opacity(0.7))
            Text(label)
        }
    }

    @ViewBuilder private var translationHost: some View {
        if #available(macOS 15.0, *), let engine = state.model.translationEngine {
            TranslationHost(engine: engine)
        }
    }
}

/// Equal-width category buttons use the same soft selection treatment as history rows.
private struct HistoryFilterButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.18) : (hovering ? Color.primary.opacity(0.04) : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .onHover { hovering = $0 }
    }
}

struct HistoryList: View {
    let state: PanelState

    var body: some View {
        let results = state.results
        let selectedID = state.selected?.id
        let context = state.model.smartContext
        Group {
            if results.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: state.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 26, weight: .light))
                    Text(state.query.isEmpty ? (state.favoritesOnly ? "没有符合条件的收藏" : (state.filter == .all ? "还没有剪贴板历史" : "还没有\(state.filter.title)记录")) : "没有匹配的结果")
                        .font(.system(size: 13))
                    if state.query.isEmpty && state.filter == .all && !state.favoritesOnly {
                        Text("复制的文本和图片会出现在这里").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(results) { item in
                                HistoryRow(item: item, selected: item.id == selectedID, context: context,
                                           now: state.now, model: state.model)
                                    .id(item.id)
                                    .onTapGesture(count: 2) {
                                        state.selectedID = item.id
                                        state.previewChoice = .original
                                        state.activate(paste: true)
                                    }
                                    .onTapGesture { state.select(item.id) }
                                    .contextMenu { contextMenu(item) }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: selectedID) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                    .onChange(of: state.query) { _, _ in
                        if let first = results.first { proxy.scrollTo(first.id, anchor: .top) }
                    }
                    .onChange(of: state.filter) { _, _ in
                        if let first = results.first { proxy.scrollTo(first.id, anchor: .top) }
                    }
                    .onChange(of: state.favoritesOnly) { _, _ in
                        if let first = results.first { proxy.scrollTo(first.id, anchor: .top) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func contextMenu(_ item: ClipItem) -> some View {
        Button("粘贴") { state.selectedID = item.id; state.previewChoice = .original; state.activate(paste: true) }
        Button("复制") { state.selectedID = item.id; state.previewChoice = .original; state.activate(paste: false) }
        let actions = state.actions(for: item)
        if !actions.isEmpty {
            Divider()
            Section("粘贴转换结果") {
                ForEach(actions) { action in
                    Button(action.title) { state.run(action.kind, on: item.id) }
                }
            }
        }
        Divider()
        Button(item.pinned ? "取消收藏" : "收藏") { state.selectedID = item.id; state.togglePinSelected() }
        Button("删除") { state.selectedID = item.id; state.deleteSelected() }
    }
}

struct HistoryRow: View {
    let item: ClipItem
    let selected: Bool
    let context: SmartContext
    let now: Date
    let model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                subtitle
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if item.pinned {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            TimeText(date: item.lastCopied, now: now)
        }
        .padding(.horizontal, 10)
        .frame(height: Metrics.historyRow)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : (hovering ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    /// Metadata stays secondary, but remains readable at the same size throughout the list.
    @ViewBuilder private var subtitle: some View {
        let hints = SmartActions.hints(for: item, context: context).joined(separator: " · ")
        let derived = SmartActions.derivedLine(for: item, context: context)
        if let derived {
            let lead = Text(derived.label).foregroundStyle(.secondary)
            let body = Text(" " + oneLine(derived.text)).foregroundStyle(.secondary)
            let tail = hints.isEmpty ? Text("") : Text("  ·  " + hints).foregroundStyle(.secondary)
            lead + body + tail
        } else if !hints.isEmpty {
            Text(hints).foregroundStyle(.secondary)
        }
    }

    private func oneLine(_ text: String) -> String {
        text.prefix(300).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private var title: String {
        switch item.kind {
        case .image:
            return "图片"
        case .file:
            let names = item.fileURLs.map(\.lastPathComponent)
            return names.count == 1 ? names[0] : "\(names[0]) 等 \(names.count) 个文件"
        case .text:
            // One line: collapse runs of whitespace so the visible start is the content.
            return oneLine(item.text)
        }
    }

    /// One shared tile keeps mixed content aligned; glyphs retain their natural optical size.
    private var leading: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if item.kind == .image, let image = model.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Metrics.leadingSize, height: Metrics.leadingSize)
            } else if item.kind == .file, let image = model.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Metrics.leadingSize, height: Metrics.leadingSize)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var symbol: String {
        switch item.kind {
        case .image: return "photo"
        case .file: return "doc"
        case .text:
            guard context.smartDetection else { return item.isRich ? "doc.richtext" : "doc.plaintext" }
            switch item.contentType {
            case .json: return "curlybraces"
            case .jwt: return "key"
            case .url: return "link"
            case .base64: return "number"
            case .timestamp: return "clock"
            case .plain: return item.isRich ? "doc.richtext" : "doc.plaintext"
            }
        }
    }
}

/// The copy time, right aligned with even digits; hovering shows the full date with seconds.
struct TimeText: View {
    let date: Date
    let now: Date
    @State private var hovering = false

    var body: some View {
        Text(hovering ? TimeLabel.full(date) : TimeLabel.short(date, now: now))
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .onHover { hovering = $0 }
    }
}

enum TimeLabel {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    private static let time = formatter("HH:mm")
    private static let monthDay = formatter("MM/dd HH:mm")
    private static let fullDay = formatter("yyyy/MM/dd HH:mm")
    private static let seconds = formatter("yyyy/MM/dd HH:mm:ss")

    static func short(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return time.string(from: date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 " + time.string(from: date)
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return monthDay.string(from: date)
        }
        return fullDay.string(from: date)
    }

    static func full(_ date: Date) -> String { seconds.string(from: date) }
}

/// Colors the system palette has no name for.
enum Palette {
    /// The raised surface of the actions card: white in light mode, a step above the window in dark.
    static let raised = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.20, alpha: 1) : .white
    })

}
