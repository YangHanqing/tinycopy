import Foundation

enum SmartActionKind: String, Sendable {
    case qrRead, qrGenerate
    case translate, ocr, jsonFormat, jsonMinify, jwtDecode, jwtPayload, base64Decode, urlDecode
    case timestampLocal, timestampISO, pastePlain, trim, filePaths, base64Encode, urlEncode
}

/// One conversion offered for an item. `result` is nil while it is still being produced (OCR, translation).
struct SmartAction: Identifiable, Equatable {
    var kind: SmartActionKind
    var title: String
    var symbol: String
    var result: String?
    var note: String?
    var id: SmartActionKind { kind }

    /// Only content-specific results belong in the arrow-key selection path.
    var isPrimary: Bool {
        switch kind {
        case .qrRead, .qrGenerate, .translate, .ocr, .jsonFormat, .jwtDecode, .base64Decode, .urlDecode, .timestampLocal, .filePaths:
            return true
        case .jsonMinify, .jwtPayload, .timestampISO, .pastePlain, .trim, .base64Encode, .urlEncode:
            return false
        }
    }

    var previewTitle: String {
        switch kind {
        case .qrRead: return "二维码内容"
        case .qrGenerate: return "二维码"
        case .translate: return "译文"
        case .ocr: return "识别文字"
        case .jsonFormat: return "格式化 JSON"
        case .jwtDecode: return "JWT 解码"
        case .timestampLocal: return "本地时间"
        default: return title.replacingOccurrences(of: "粘贴", with: "")
        }
    }
}

struct SmartContext {
    var smartDetection: Bool
    var ocrMode: OCRMode
    /// nil when translation is unavailable (macOS 14) or off.
    var translationTarget: String?
}

enum SmartActions {
    /// Conversions are skipped above this size: they would stall the panel for little use.
    static let maxTransformBytes = 1_000_000

    static func actions(for item: ClipItem, context: SmartContext) -> [SmartAction] {
        var list: [SmartAction] = []
        switch item.kind {
        case .image:
            if context.smartDetection, let contents = item.qrContents, !contents.isEmpty {
                list.append(SmartAction(kind: .qrRead, title: "提取二维码内容", symbol: "qrcode.viewfinder", result: contents.joined(separator: "\n")))
            }
            if context.ocrMode != .off, item.ocrText != "" {
                list.append(SmartAction(kind: .ocr, title: "粘贴识别文字", symbol: "text.viewfinder", result: item.ocrText))
            }
        case .file:
            list.append(SmartAction(kind: .filePaths, title: "粘贴文件路径", symbol: "folder", result: item.text))
        case .text:
            list = textActions(for: item, context: context)
        }
        return list
    }

    static func translationTitle(_ target: String) -> String {
        "翻译为\(LanguageTools.displayName(target))"
    }

    private static func textActions(for item: ClipItem, context: SmartContext) -> [SmartAction] {
        let text = item.text
        var list: [SmartAction] = []
        if let target = context.translationTarget, let language = item.language,
           !LanguageTools.sameLanguage(language, target) {
            list.append(SmartAction(kind: .translate, title: translationTitle(target), symbol: "translate",
                                    result: item.translations[target]))
        }
        let small = text.utf8.count <= maxTransformBytes
        if context.smartDetection, small {
            switch item.contentType {
            case .json:
                if let pretty = Transforms.formatJSON(text), pretty != text {
                    list.append(SmartAction(kind: .jsonFormat, title: "格式化 JSON", symbol: "text.alignleft", result: pretty))
                }
                if let mini = Transforms.minifyJSON(text), mini != text {
                    list.append(SmartAction(kind: .jsonMinify, title: "压缩 JSON", symbol: "arrow.down.right.and.arrow.up.left", result: mini))
                }
            case .jwt:
                if let jwt = Transforms.decodeJWT(text) {
                    var note = "仅解码查看，未验证签名"
                    if let exp = jwt.expires {
                        note += " · 过期时间 \(Transforms.localTime(exp))\(exp < Date() ? "（已过期）" : "")"
                    }
                    let combined = Transforms.formatJSON("{\"header\":\(jwt.header),\"payload\":\(jwt.payload)}")
                    list.append(SmartAction(kind: .jwtDecode, title: "解码 Header + Payload", symbol: "key", result: combined, note: note))
                    list.append(SmartAction(kind: .jwtPayload, title: "仅解码 Payload", symbol: "key", result: jwt.payload, note: note))
                }
            case .base64:
                if let decoded = Transforms.decodeBase64(text) {
                    list.append(SmartAction(kind: .base64Decode, title: "Base64 解码", symbol: "lock.open", result: decoded))
                }
            case .timestamp:
                if let date = Transforms.unixDate(text) {
                    list.append(SmartAction(kind: .timestampLocal, title: "转换为本地时间", symbol: "clock", result: Transforms.localTime(date)))
                    list.append(SmartAction(kind: .timestampISO, title: "转换为 ISO 8601", symbol: "clock", result: Transforms.iso8601(date)))
                }
            case .url:
                if QRCode.canGenerateURL(text) {
                    list.append(SmartAction(kind: .qrGenerate, title: "生成二维码", symbol: "qrcode", result: nil))
                }
            case .plain:
                break
            }
            if let decoded = Transforms.urlDecode(text) {
                list.append(SmartAction(kind: .urlDecode, title: "URL 解码", symbol: "link", result: decoded))
            }
        }
        if item.isRich {
            list.append(SmartAction(kind: .pastePlain, title: "粘贴为纯文本", symbol: "textformat", result: text))
        }
        if let trimmed = Transforms.trimmed(text) {
            list.append(SmartAction(kind: .trim, title: "去除首尾空白", symbol: "scissors", result: trimmed))
        }
        if context.smartDetection, small, item.contentType != .jwt, item.contentType != .timestamp {
            if item.contentType != .base64 {
                list.append(SmartAction(kind: .base64Encode, title: "Base64 编码", symbol: "lock", result: Transforms.encodeBase64(text)))
            }
            if let encoded = Transforms.urlEncode(text) {
                list.append(SmartAction(kind: .urlEncode, title: "URL 编码", symbol: "link", result: encoded))
            }
        }
        return list
    }

    /// Text derived from the item that the list shows on its second line: what OCR read in an
    /// image, or the cached translation of text.
    static func derivedLine(for item: ClipItem, context: SmartContext) -> (label: String, text: String)? {
        switch item.kind {
        case .image:
            if context.smartDetection, let contents = item.qrContents, !contents.isEmpty {
                return ("二维码", contents.joined(separator: " · "))
            }
            if context.ocrMode != .off, let ocr = item.ocrText, !ocr.isEmpty { return ("文字", ocr) }
        case .text:
            if let target = context.translationTarget, let translated = item.translations[target] { return ("译", translated) }
        case .file:
            break
        }
        return nil
    }

    /// The faint tags shown under an item in the list.
    static func hints(for item: ClipItem, context: SmartContext) -> [String] {
        var hints: [String] = []
        switch item.kind {
        case .image:
            if let w = item.imageWidth, let h = item.imageHeight { hints.append("\(w)×\(h)") }
        case .file:
            let count = item.fileURLs.count
            hints.append(count == 1 ? (item.fileURLs.first?.deletingLastPathComponent().path ?? "") : "\(count) 个文件")
        case .text:
            if context.smartDetection {
                switch item.contentType {
                case .json: hints.append("JSON · 可格式化")
                case .jwt: hints.append("JWT · 可解码")
                case .base64: hints.append("Base64 · 可解码")
                case .timestamp:
                    if let date = Transforms.unixDate(item.text) { hints.append("时间戳 · \(Transforms.localTime(date))") }
                case .url: hints.append("链接")
                case .plain: break
                }
            }
            if item.isRich { hints.append("富文本") }
            if let target = context.translationTarget, let language = item.language,
               !LanguageTools.sameLanguage(language, target) {
                if item.translations[target] == nil { hints.append("可翻译") }
            }
            let lines = item.text.utf8.count < 200_000 ? item.text.split(separator: "\n", omittingEmptySubsequences: false).count : 0
            if lines > 1 { hints.append("\(lines) 行") }
        }
        return hints
    }
}
