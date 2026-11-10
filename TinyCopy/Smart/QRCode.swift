import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// System-only QR encoding/recognition. No network, downloaded model, or bundled resources.
enum QRCode {
    static func canGenerateURL(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.utf8.count <= 2000 && Transforms.isWebURL(value)
    }

    /// A four-module quiet zone and integer scaling keep the copied PNG easy to scan.
    static func encode(_ text: String) -> Data? {
        guard !text.isEmpty, text.utf8.count <= 2000,
              let filter = CIFilter(name: "CIQRCodeGenerator", parameters: [
                "inputMessage": Data(text.utf8), "inputCorrectionLevel": "M",
              ]), let code = filter.outputImage else { return nil }
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
            .cropped(to: code.extent.insetBy(dx: -4, dy: -4))
        let image = code.composited(over: white).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        guard let rendered = context.createCGImage(image, from: image.extent) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, rendered, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    static func decode(_ data: Data) -> [String] {
        CGImageSourceCreateWithData(data as CFData, nil).map { decode($0) } ?? []
    }

    static func decode(_ source: CGImageSource) -> [String] {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2600,
              ] as CFDictionary) else { return [] }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
        var contents: [String] = []
        for observation in request.results ?? [] {
            guard let value = observation.payloadStringValue, !value.isEmpty, !contents.contains(value) else { continue }
            contents.append(value)
            if contents.count == 16 { break }
        }
        return contents
    }
}
