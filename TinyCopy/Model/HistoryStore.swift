import Foundation

/// Files on disk:
///   index.json          the item list (metadata, text, OCR, translations), newest first
///   Content/<id>.plist  the pasteboard representations of one item
///   Thumbs/<id>.jpg     the list thumbnail of an image item
/// All writes go through one serial queue, so they land in the order they were made.
final class HistoryStore: @unchecked Sendable {
    let root: URL
    private let contentDir: URL
    private let thumbDir: URL
    private let indexURL: URL
    private let queue = DispatchQueue(label: "cn.hqyang.TinyCopy.store", qos: .utility)

    init(root: URL) {
        self.root = root
        contentDir = root.appendingPathComponent("Content", isDirectory: true)
        thumbDir = root.appendingPathComponent("Thumbs", isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")
        for dir in [root, contentDir, thumbDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "cn.hqyang.TinyCopy", isDirectory: true)
    }

    // MARK: Index

    /// `complete` is false when the file existed but some or all of it could not be read. Then a
    /// copy of it is kept, and the caller must not treat unlisted content files as orphans.
    func loadIndex() -> (items: [ClipItem], complete: Bool) {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return ([], true) }
        let decoded = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder.store.decode([Lossy].self, from: $0) }
        let items = decoded?.compactMap(\.item) ?? []
        guard let decoded, items.count == decoded.count else {
            // Keep the unreadable file for inspection instead of losing it on the next save.
            let backup = root.appendingPathComponent("index-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: indexURL, to: backup)
            return (items, false)
        }
        return (items, true)
    }

    /// One entry of the index; an entry this version cannot read is skipped, not fatal.
    private struct Lossy: Decodable {
        let item: ClipItem?
        init(from decoder: Decoder) throws { item = try? ClipItem(from: decoder) }
    }

    func saveIndex(_ items: [ClipItem]) {
        queue.async { self.writeIndex(items) }
    }

    /// Waits for every queued write, then writes the index. Used at quit and by tests.
    func saveIndexNow(_ items: [ClipItem]) {
        queue.sync { self.writeIndex(items) }
    }

    private func writeIndex(_ items: [ClipItem]) {
        guard let data = try? JSONEncoder.store.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: Content and thumbnails

    func saveContent(_ content: ClipContent, thumbnail: Data?, for id: UUID) {
        queue.async {
            if let data = try? PropertyListEncoder.binary.encode(content) {
                try? data.write(to: self.contentURL(id), options: .atomic)
            }
            if let thumbnail {
                try? thumbnail.write(to: self.thumbnailURL(id), options: .atomic)
            }
        }
    }

    func content(for id: UUID) -> ClipContent? {
        queue.sync {
            guard let data = try? Data(contentsOf: contentURL(id)) else { return nil }
            return try? PropertyListDecoder().decode(ClipContent.self, from: data)
        }
    }

    func thumbnailURL(_ id: UUID) -> URL { thumbDir.appendingPathComponent("\(id.uuidString).jpg") }
    private func contentURL(_ id: UUID) -> URL { contentDir.appendingPathComponent("\(id.uuidString).plist") }

    func delete(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        queue.async {
            for id in ids {
                try? FileManager.default.removeItem(at: self.contentURL(id))
                try? FileManager.default.removeItem(at: self.thumbnailURL(id))
            }
        }
    }

    /// Removes files that no item refers to (left by a crash between writes).
    func removeOrphans(keeping ids: Set<UUID>) {
        queue.async {
            for dir in [self.contentDir, self.thumbDir] {
                let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                for file in files {
                    let name = file.deletingPathExtension().lastPathComponent
                    if let id = UUID(uuidString: name), ids.contains(id) { continue }
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}

extension JSONEncoder {
    static var store: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    static var store: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

extension PropertyListEncoder {
    static var binary: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }
}
