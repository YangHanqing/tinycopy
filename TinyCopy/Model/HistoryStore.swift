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

    /// `complete` is false when the file existed but could not be read at all. Then a copy of it is
    /// kept, and the caller must not treat unlisted content files as orphans.
    func loadIndex() -> (items: [ClipItem], complete: Bool) {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return ([], true) }
        let data = try? Data(contentsOf: indexURL)
        // Normal indexes need one decode, not a JSON object graph plus a re-encode/decode per item.
        // Keep the tolerant per-entry path below for indexes containing unknown or damaged entries.
        if let data, let items = try? JSONDecoder.store.decode([ClipItem].self, from: data) {
            queue.sync {
                unreadableEntries = []
                unreadableIDs = []
            }
            return (items, true)
        }
        guard let data,
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            // Keep the unreadable file for inspection instead of losing it on the next save.
            let backup = root.appendingPathComponent("\(Self.backupPrefix)\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: indexURL, to: backup)
            return ([], false)
        }
        var items: [ClipItem] = []
        var kept: [Data] = []
        var keptIDs: Set<UUID> = []
        for entry in entries {
            guard let raw = try? JSONSerialization.data(withJSONObject: entry) else { continue }
            if let item = try? JSONDecoder.store.decode(ClipItem.self, from: raw) {
                items.append(item)
            } else {
                // An entry from another version (an unknown kind, say) is written back untouched,
                // so going back to that version finds it again with its content.
                kept.append(raw)
                if let id = (entry as? [String: Any])?["id"] as? String, let uuid = UUID(uuidString: id) { keptIDs.insert(uuid) }
            }
        }
        queue.sync {
            unreadableEntries = kept
            unreadableIDs = keptIDs
        }
        return (items, true)
    }

    private static let backupPrefix = "index-unreadable-"
    /// Index entries this version cannot read, kept verbatim. Touched only on `queue`.
    private var unreadableEntries: [Data] = []
    private var unreadableIDs: Set<UUID> = []

    func saveIndex(_ items: [ClipItem]) {
        queue.async { self.writeIndex(items) }
    }

    /// Waits for every queued write, then writes the index. Used at quit and by tests.
    func saveIndexNow(_ items: [ClipItem]) {
        queue.sync { self.writeIndex(items) }
    }

    private func writeIndex(_ items: [ClipItem]) {
        guard var data = try? JSONEncoder.store.encode(items) else { return }
        if !unreadableEntries.isEmpty {
            guard var entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return }
            entries += unreadableEntries.compactMap { try? JSONSerialization.jsonObject(with: $0) }
            guard let merged = try? JSONSerialization.data(withJSONObject: entries) else { return }
            data = merged
        }
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

    /// Removes files that no item refers to (left by a crash between writes). Skipped while a copy
    /// of an unreadable index exists: its entries may still need these files.
    func removeOrphans(keeping ids: Set<UUID>) {
        queue.async {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: self.root.path)) ?? []
            guard !names.contains(where: { $0.hasPrefix(Self.backupPrefix) }) else { return }
            let ids = ids.union(self.unreadableIDs)
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
