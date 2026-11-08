import Foundation

enum ClipKind: String, Codable, Sendable {
    case text, image, file
}

/// What the text of an item was recognized as. Only certain readings get a type; everything else is `.plain`.
enum ContentType: String, Codable, Sendable {
    case plain, json, jwt, url, base64, timestamp
}

/// One history entry. Its pasteboard representations live in a separate file (`HistoryStore.content`),
/// so the index stays small enough to load and search in memory.
struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: ClipKind
    /// The plain text (text items), the file paths one per line (file items), or empty (images).
    var text: String
    /// Identity for de-duplication: SHA-256 of the text, the paths or the image bytes.
    var hash: String
    var created: Date
    var lastCopied: Date
    var pinned: Bool = false
    /// The item carries RTF, RTFD or HTML besides plain text.
    var isRich: Bool = false
    var imageWidth: Int?
    var imageHeight: Int?
    var contentType: ContentType = .plain
    /// Searchable text derived from the content (decoded JWT payload, Base64 or URL decoding).
    var derivedText: String?
    /// The dominant natural language (NLLanguage raw value) of plain text, when it is clearly prose.
    var language: String?
    /// Recognized text of an image; empty when recognition found nothing, nil when it has not run.
    var ocrText: String?
    /// nil until QR recognition finishes; an empty array means no QR payload was found.
    var qrContents: [String]?
    /// Translations keyed by target language identifier.
    var translations: [String: String] = [:]

    var hasUsefulOCR: Bool { !(ocrText ?? "").isEmpty }

    var fileURLs: [URL] {
        kind == .file ? text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) } : []
    }
}

/// One pasteboard representation, kept in the order the source app offered it.
struct TypedData: Codable, Sendable {
    var type: String
    var data: Data
}

/// Everything needed to put an item back on the pasteboard: one array per pasteboard item.
struct ClipContent: Codable, Sendable {
    var items: [[TypedData]]
}

extension ClipItem {
    /// Tolerant of fields an older or newer version did not write: a missing field takes its default
    /// instead of making the whole history unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ClipKind.self, forKey: .kind)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        hash = try c.decodeIfPresent(String.self, forKey: .hash) ?? ""
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date(timeIntervalSince1970: 0)
        lastCopied = try c.decodeIfPresent(Date.self, forKey: .lastCopied) ?? created
        pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
        isRich = (try? c.decodeIfPresent(Bool.self, forKey: .isRich)) ?? false
        imageWidth = try? c.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try? c.decodeIfPresent(Int.self, forKey: .imageHeight)
        contentType = (try? c.decodeIfPresent(ContentType.self, forKey: .contentType)) ?? .plain
        derivedText = try? c.decodeIfPresent(String.self, forKey: .derivedText)
        language = try? c.decodeIfPresent(String.self, forKey: .language)
        ocrText = try? c.decodeIfPresent(String.self, forKey: .ocrText)
        qrContents = (try? c.decodeIfPresent([String].self, forKey: .qrContents)) ?? nil
        translations = (try? c.decodeIfPresent([String: String].self, forKey: .translations)) ?? [:]
    }
}
