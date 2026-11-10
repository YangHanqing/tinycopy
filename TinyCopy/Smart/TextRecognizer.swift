import Foundation
import ImageIO
import Vision

/// On-device OCR with Vision. Large images are scaled down first; the result is the recognized
/// lines joined with newlines, or "" when no real text was found.
enum TextRecognizer {
    private static let maxPixels = 2600

    static func recognize(_ source: CGImageSource) async -> String {
        guard let image = downscaled(source) else { return "" }
        let languages = preferredLanguages()
        var lines: [String] = []
        if #available(macOS 15.0, *) {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
            if let observations = try? await request.perform(on: image) {
                lines = observations.compactMap { $0.topCandidates(1).first?.string }
            }
        } else {
            lines = legacyRecognize(image, languages: languages)
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // A stray mark or a single character is noise, not text worth offering.
        let meaningful = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        return meaningful >= 2 ? text : ""
    }

    private static func legacyRecognize(_ image: CGImage, languages: [String]) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = languages
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// The user's preferred languages that Vision can read, in order, plus English.
    private static func preferredLanguages() -> [String] {
        let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
        var result: [String] = []
        for preferred in Locale.preferredLanguages {
            let normalized = LanguageTools.normalized(preferred)
            if let match = supported.first(where: { LanguageTools.sameLanguage($0, normalized) }), !result.contains(match) {
                result.append(match)
            }
        }
        if !result.contains(where: { $0.hasPrefix("en") }) { result.append("en-US") }
        return result
    }

    private static func downscaled(_ source: CGImageSource) -> CGImage? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        if max(width, height) <= maxPixels {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
