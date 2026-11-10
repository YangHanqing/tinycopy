import AppKit
import AVFoundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// What a copied file looks like right now. Read live when the item is previewed, never stored:
/// history keeps only the path, so the file may have changed or gone.
struct FilePreview: Sendable {
    struct File: Sendable, Equatable {
        var url: URL
        var exists: Bool
        var isDirectory = false
        var size: Int64?
        var modified: Date?
        var typeName: String?
    }

    var id: UUID
    var files: [File]
    /// The image itself for image files, or a Quick Look thumbnail (PDF, video, documents).
    var image: CGImage?
    /// One extra fact for a single file: pixel size, page count, duration or folder item count.
    var detail: String?
    /// The start of a text file, for the preview.
    var text: String?
    /// The whole text, when the file is small enough to paste as text.
    var pasteableText: String?

    var single: File? { files.count == 1 ? files[0] : nil }
}

enum FilePreviewLoader {
    /// Text files up to this size can be pasted as their contents.
    static let maxPasteableTextBytes = 1_000_000
    private static let excerptBytes = 256 * 1024

    enum Kind { case image, text, pdf, media, other }

    /// From the extension alone, so it costs no file access and works for list rows.
    static func kind(of url: URL) -> Kind {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .other }
        if type.conforms(to: .rtf) || type.conforms(to: .rtfd) || type.conforms(to: .flatRTFD) { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .text) { return .text }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .audiovisualContent) { return .media }
        return .other
    }

    static func load(_ item: ClipItem) async -> FilePreview {
        let files = item.fileURLs.map(info)
        var preview = FilePreview(id: item.id, files: files)
        guard let file = preview.single, file.exists else { return preview }
        let url = file.url
        if file.isDirectory {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.filter { !$0.hasPrefix(".") }.count
            preview.detail = count.map { "\($0) 项" }
            return preview
        }
        switch kind(of: url) {
        case .image:
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 {
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                if let w = props?[kCGImagePropertyPixelWidth] as? Int, let h = props?[kCGImagePropertyPixelHeight] as? Int {
                    preview.detail = "\(w) × \(h)"
                }
                preview.image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1800,
                ] as CFDictionary)
            }
            if preview.image == nil { preview.image = await thumbnail(url) }
        case .text:
            let (text, complete) = readText(url, size: file.size ?? 0)
            preview.text = text
            if complete { preview.pasteableText = text }
        case .pdf:
            if let pages = CGPDFDocument(url as CFURL)?.numberOfPages { preview.detail = "\(pages) 页" }
            preview.image = await thumbnail(url)
        case .media:
            if let duration = try? await AVURLAsset(url: url).load(.duration), duration.isNumeric, duration.seconds > 0 {
                preview.detail = formatDuration(duration.seconds)
            }
            preview.image = await thumbnail(url)
        case .other:
            preview.image = await thumbnail(url)
        }
        return preview
    }

    /// The image file as PNG, for pasting it as an image rather than as a file.
    static func pngData(of url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        if (CGImageSourceGetType(source) as String?) == UTType.png.identifier,
           let data = try? Data(contentsOf: url), data.count <= PasteboardIO.maxBytes {
            return data
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest), out.length <= PasteboardIO.maxBytes else { return nil }
        return out as Data
    }

    private static func info(_ url: URL) -> FilePreview.File {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return .init(url: url, exists: false) }
        let isDirectory = values.isDirectory ?? false
        return .init(url: url, exists: true, isDirectory: isDirectory,
                     size: isDirectory ? nil : values.fileSize.map(Int64.init),
                     modified: values.contentModificationDate, typeName: values.localizedTypeDescription)
    }

    private static func thumbnail(_ url: URL) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 560, height: 320), scale: 2,
                                                   representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }

    /// Reads at most 1 MB. Returns nil for binary content or an encoding it cannot tell.
    private static func readText(_ url: URL, size: Int64) -> (String?, complete: Bool) {
        let complete = size <= maxPasteableTextBytes
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, false) }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: complete ? maxPasteableTextBytes : excerptBytes) else { return (nil, false) }
        if data.isEmpty { return ("", complete) }
        // A NUL byte early on means binary, unless the file is UTF-16 (which has a BOM).
        let hasBOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        if !hasBOM, data.prefix(8192).contains(0) { return (nil, false) }
        if hasBOM { return (String(data: data, encoding: .utf16), complete) }
        if let text = String(data: data, encoding: .utf8) { return (text, complete) }
        if !complete {
            // The excerpt may end inside a multibyte character.
            for cut in 1...3 where data.count > cut {
                if let text = String(data: data.dropLast(cut), encoding: .utf8) { return (text, false) }
            }
        }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gb18030) { return (text, complete) }
        return (nil, false)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
