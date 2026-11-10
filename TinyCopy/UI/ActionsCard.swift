import SwiftUI
import ImageIO

/// Source and detected results stay visible together. Selection changes what Enter uses, not what is shown.
struct ActionsCard: View {
    let state: PanelState
    let item: ClipItem
    @State private var image: NSImage?
    @State private var imageLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        contentCard("原始内容", symbol: item.kind == .image ? "photo" : "doc", choice: .original) {
                            originalContent
                        }
                        ForEach(state.primaryActions) { action in
                            resultCard(action)
                        }
                        if let action = state.selectedAction, !action.isPrimary {
                            resultCard(action)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: state.currentPreview) { _, choice in
                    proxy.scrollTo(choice, anchor: .center)
                }
            }
            Divider()
            footer
        }
        .background(Palette.raised)
        .task(id: item.id) {
            state.preparePreview()
            await loadImage()
        }
    }

    /// One compact row, with contextual choices first and occasional tools at the far right.
    private var toolbar: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        choice("原始内容", value: .original)
                        ForEach(state.primaryActions) { action in
                            choice(action.previewTitle, value: .action(action.kind))
                        }
                    }
                    .padding(.leading, 12)
                }
                .scrollIndicators(.hidden)
                .onChange(of: state.currentPreview, initial: true) { _, value in
                    proxy.scrollTo(value, anchor: .center)
                }
            }
            if !state.moreActions.isEmpty {
                Menu {
                    ForEach(state.moreActions) { action in
                        Button(action.previewTitle) { state.choosePreview(.action(action.kind)) }
                    }
                } label: {
                    Text(state.selectedAction.flatMap { !$0.isPrimary ? $0.previewTitle : nil } ?? "更多")
                        .font(.system(size: 12))
                        .foregroundStyle(state.selectedAction?.isPrimary == false ? Color.accentColor : .secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Button { state.collapsePreview() } label: {
                Image(systemName: "sidebar.right")
                    .accessibilityLabel("收起预览")
                    .frame(width: 24, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.trailing, 10)
        .frame(height: Metrics.searchArea)
    }

    private func choice(_ title: String, value: PanelState.PreviewChoice) -> some View {
        Button { state.choosePreview(value) } label: {
            Text(title)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(state.currentPreview == value ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .id(value)
    }

    private func contentCard<Content: View>(_ title: String, symbol: String,
                                           choice: PanelState.PreviewChoice,
                                           @ViewBuilder content: () -> Content) -> some View {
        let selected = state.currentPreview == choice
        return VStack(alignment: .leading, spacing: 0) {
            Button { state.choosePreview(choice) } label: {
                HStack(spacing: 6) {
                    Label(title, systemImage: symbol)
                    Spacer()
                    if selected { Label("回车使用", systemImage: "checkmark.circle.fill") }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            content()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.04) : Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .id(choice)
    }

    private func resultCard(_ action: SmartAction) -> some View {
        contentCard(action.previewTitle, symbol: action.symbol, choice: .action(action.kind)) {
            VStack(alignment: .leading, spacing: 10) {
                if action.kind == .qrGenerate {
                    if let data = state.qrCodeData, let qrImage = NSImage(data: data) {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 220, height: 220)
                            .padding(8)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if state.qrFailedID == item.id {
                        Text("无法生成二维码，请尝试缩短链接。")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    } else {
                        ProgressView("正在生成二维码…")
                            .frame(maxWidth: .infinity).padding(12)
                    }
                } else if let result = action.result {
                    textBlock(result, monospaced: monospaced(action))
                } else {
                    Text(status(for: action))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if action.kind == .translate {
                        Button("开始翻译") { state.requestPreview(action, interactive: true) }
                            .buttonStyle(.bordered)
                            .disabled(state.model.translating.contains(item.id))
                    } else if action.kind == .ocr && !state.model.ocrRunning.contains(item.id) {
                        Button("识别文字") { state.requestPreview(action) }
                            .buttonStyle(.bordered)
                    }
                }
                if let note = action.note {
                    Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func monospaced(_ action: SmartAction) -> Bool {
        switch action.kind {
        case .translate, .ocr: return false
        case .fileText:
            let ext = item.fileURLs.first?.pathExtension.lowercased() ?? ""
            return !["txt", "text", "md", "markdown"].contains(ext)
        default: return true
        }
    }

    @ViewBuilder private var originalContent: some View {
        if item.kind == .file {
            // The other file cards are short, so the picture can take the room.
            FileOriginalView(item: item, preview: state.filePreview(for: item), imageHeight: 330)
        } else if item.kind == .image {
            VStack(spacing: 8) {
                if let image {
                    Image(nsImage: image)
                        .interpolation((item.qrContents ?? []).isEmpty ? .high : .none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: state.primaryActions.isEmpty ? 330 : 230)
                } else if !imageLoaded {
                    ProgressView().frame(maxWidth: .infinity).frame(height: 140)
                } else {
                    Text("图片无法读取").foregroundStyle(.secondary)
                }
                if let width = item.imageWidth, let height = item.imageHeight {
                    Text("\(width) × \(height)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            textBlock(item.text, monospaced: item.contentType != .plain, compact: !state.primaryActions.isEmpty)
        }
    }

    private func textBlock(_ text: String, monospaced: Bool, compact: Bool = false) -> some View {
        // Bound every traversal to the preview, including the truncation check.
        let end = text.index(text.startIndex, offsetBy: 100_000, limitedBy: text.endIndex) ?? text.endIndex
        let excerpt = String(text[..<end])
        let long = excerpt.count > (compact ? 400 : 700) || excerpt.lazy.filter { $0 == "\n" }.prefix(compact ? 7 : 13).count > (compact ? 6 : 12)
        return Group {
            if long {
                // SwiftUI's selectable `Text` lays out the whole string on the main thread; on
                // macOS 15 a 13 KB, 400-line note froze the panel for 14 s. TextKit lays out lazily.
                LongTextView(text: excerpt, monospaced: monospaced)
                    .frame(height: compact ? 120 : 240)
            } else {
                textContent(excerpt, monospaced: monospaced)
            }
            if end != text.endIndex {
                Text("仅预览前 100,000 个字符；复制和粘贴会保留完整内容。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func textContent(_ text: String, monospaced: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, design: monospaced ? .monospaced : .default))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(state.selectedAction == nil ? "↩ 使用原始内容" : "↩ 使用处理结果")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button { state.activate(paste: false) } label: { Text("复制").font(.system(size: 12)) }
                .buttonStyle(.plain)
            Button { state.activate(paste: true) } label: {
                Text(state.selectedAction == nil ? "粘贴原内容" : "粘贴结果")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.footer)
    }

    private func status(for action: SmartAction) -> String {
        let model = state.model
        switch action.kind {
        case .fileText:
            return "正在读取文件…"
        case .fileImage:
            return "作为图片粘贴，在聊天和文档里直接显示，而不是作为附件。"
        case .ocr:
            return model.ocrRunning.contains(item.id) ? "正在识别图片中的文字…" : "暂无识别结果"
        case .translate:
            if let error = model.translationErrors[item.id] { return error }
            return model.translating.contains(item.id) ? "正在翻译…" : "点击开始翻译；需要时系统会询问是否下载语言包。"
        default: return "暂无结果"
        }
    }

    /// Decode from the stored original, off the main thread. Never enlarge the tiny list thumbnail.
    private func loadImage() async {
        guard item.kind == .image else { return }
        let store = state.model.store
        let id = item.id
        let decoded = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let content = store.content(for: id),
                  let original = content.items.flatMap({ $0 }).first(where: { $0.type == NSPasteboard.PasteboardType.png.rawValue }),
                  let source = CGImageSourceCreateWithData(original.data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1800,
                  ] as CFDictionary) else { return nil }
            return cgImage
        }.value
        guard !Task.isCancelled else { return }
        image = decoded.map { NSImage(cgImage: $0, size: .zero) }
        imageLoaded = true
    }
}

/// Read-only, selectable text backed by NSTextView, for content too long for SwiftUI `Text`.
private struct LongTextView: NSViewRepresentable {
    let text: String
    let monospaced: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.drawsBackground = false
            textView.textContainerInset = .zero
            textView.textContainer?.lineFragmentPadding = 0
            textView.textColor = .labelColor
        }
        update(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        update(scrollView)
    }

    private func update(_ scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let font = monospaced ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) : NSFont.systemFont(ofSize: 14)
        guard textView.string != text || textView.font != font else { return }
        textView.string = text
        textView.font = font
        textView.textColor = .labelColor
        textView.scroll(.zero)
    }
}

/// A copied file as it is now: what it looks like, what it is, and whether it still exists.
private struct FileOriginalView: View {
    let item: ClipItem
    let preview: FilePreview?
    let imageHeight: CGFloat

    var body: some View {
        if let preview {
            if let file = preview.single {
                single(file, preview: preview)
            } else {
                list(preview.files)
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).frame(height: 80)
        }
    }

    @ViewBuilder private func single(_ file: FilePreview.File, preview: FilePreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = preview.image {
                Image(nsImage: NSImage(cgImage: image, size: .zero))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: imageHeight)
            }
            HStack(alignment: .top, spacing: 10) {
                if preview.image == nil { icon(file, size: 40) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.url.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text(file.exists ? metadata(file, detail: preview.detail) : "文件已不存在，可能已被移动或删除")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text((file.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            if let text = preview.text, preview.pasteableText == nil {
                Text(text.prefix(4000))
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                Text("文件较大，仅预览开头；粘贴时作为文件。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if file.exists { revealButton([file.url]) }
        }
    }

    private func list(_ files: [FilePreview.File]) -> some View {
        let total = files.compactMap(\.size).reduce(0, +)
        let missing = files.filter { !$0.exists }.count
        var summary = "\(files.count) 个文件"
        if total > 0 { summary += " · 共 " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file) }
        if missing > 0 { summary += " · \(missing) 个已不存在" }
        return VStack(alignment: .leading, spacing: 8) {
            Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(files.prefix(50), id: \.url) { file in
                    HStack(spacing: 8) {
                        icon(file, size: 18)
                        Text(file.url.lastPathComponent)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(file.exists ? .primary : .secondary)
                            .strikethrough(!file.exists)
                        Spacer(minLength: 8)
                        Text(file.exists ? (file.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "文件夹") : "已不存在")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if files.count > 50 {
                    Text("还有 \(files.count - 50) 个文件").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            let existing = files.filter(\.exists).map(\.url)
            if !existing.isEmpty { revealButton(existing) }
        }
    }

    private func icon(_ file: FilePreview.File, size: CGFloat) -> some View {
        Group {
            if file.exists {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable()
            } else {
                Image(systemName: "questionmark.folder").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func metadata(_ file: FilePreview.File, detail: String?) -> String {
        var parts: [String] = []
        if let type = file.typeName { parts.append(type) }
        if let detail { parts.append(detail) }
        if let size = file.size { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if let modified = file.modified { parts.append("修改于 " + modified.formatted(date: .abbreviated, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    private func revealButton(_ urls: [URL]) -> some View {
        Button { NSWorkspace.shared.activateFileViewerSelecting(urls) } label: {
            Label("在 Finder 中显示", systemImage: "folder").font(.system(size: 12))
        }
        .buttonStyle(.link)
    }
}
