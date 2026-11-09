import AppKit
import XCTest
@testable import TinyCopy

/// End to end through the real model: a private named pasteboard, real files in a temp folder,
/// and a second model loading them again as a relaunch would.
@MainActor
final class HistoryEndToEndTests: XCTestCase {
    private var root: URL!
    private var pasteboard: NSPasteboard!
    private var settings: AppSettings!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("TinyCopyTests-\(UUID().uuidString)")
        pasteboard = NSPasteboard(name: NSPasteboard.Name("cn.hqyang.TinyCopy.tests.\(UUID().uuidString)"))
        let defaults = UserDefaults(suiteName: "cn.hqyang.TinyCopy.tests.\(UUID().uuidString)")!
        settings = AppSettings(defaults: defaults)
        settings.translationMode = .off
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel() -> AppModel {
        AppModel(store: HistoryStore(root: root), settings: settings, pasteboard: pasteboard)
    }

    private func copy(_ model: AppModel, text: String, extraType: String? = nil) async {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if let extraType { pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(extraType)) }
        model.poll()
        await model.waitForBackgroundWork()
    }

    func testHistoryKeepsDeduplicatesEvictsAndSurvivesRelaunch() async throws {
        settings.historyLimit = 3
        let model = makeModel()
        await copy(model, text: "alpha")
        XCTAssertEqual(model.search("a").map(\.text), ["alpha"])
        await copy(model, text: "beta")
        XCTAssertEqual(model.search("a").map(\.text), ["alpha", "beta"])
        await copy(model, text: "alpha")
        XCTAssertEqual(model.search("a").map(\.text), ["alpha", "beta"])
        XCTAssertEqual(model.items.map(\.text), ["alpha", "beta"], "a repeated copy reuses its entry and moves it to the top")

        model.togglePin(try XCTUnwrap(model.items.last).id) // beta
        for word in ["c1", "c2", "c3", "c4"] { await copy(model, text: word) }
        XCTAssertEqual(model.items.filter { !$0.pinned }.map(\.text), ["c4", "c3", "c2"], "the oldest unpinned entries go first")
        XCTAssertTrue(model.items.contains { $0.text == "beta" && $0.pinned }, "pinned entries never count toward the limit")

        await copy(model, text: "secret", extraType: "org.nspasteboard.ConcealedType")
        XCTAssertFalse(model.items.contains { $0.text == "secret" }, "concealed content is not recorded")

        // Pasting an entry puts it back without recording a new copy, and moves it up.
        let beta = try XCTUnwrap(model.items.first { $0.text == "beta" })
        model.writeToPasteboard(beta.id)
        XCTAssertEqual(pasteboard.string(forType: .string), "beta")
        model.poll()
        await model.waitForBackgroundWork()
        XCTAssertEqual(model.items.first?.text, "beta")
        XCTAssertEqual(model.items.count, 4)

        model.flush()
        let relaunched = makeModel()
        XCTAssertEqual(relaunched.items.map(\.text), model.items.map(\.text))
        XCTAssertEqual(relaunched.items.first { $0.pinned }?.text, "beta")
        XCTAssertEqual(relaunched.search("C3").map(\.text), ["c3"], "search ignores case")

        relaunched.writeToPasteboard(try XCTUnwrap(relaunched.items.first { $0.text == "c2" }).id)
        XCTAssertEqual(pasteboard.string(forType: .string), "c2", "content files survive the relaunch")
    }

    func testIndexFromAnotherVersionLoadsWhatItCanAndDeletesNothing() async throws {
        let model = makeModel()
        await copy(model, text: "kept")
        model.flush()
        let kept = try XCTUnwrap(model.items.first)

        // An older entry missing newer fields, and an entry of a kind this version does not know.
        let unknown = UUID()
        let index: [[String: Any]] = [
            ["id": kept.id.uuidString, "kind": "text", "text": "kept", "hash": kept.hash, "created": 1_800_000_000],
            ["id": unknown.uuidString, "kind": "video", "text": "", "hash": "x", "created": 1_800_000_000],
        ]
        try JSONSerialization.data(withJSONObject: index).write(to: root.appendingPathComponent("index.json"))
        let unknownContent = root.appendingPathComponent("Content/\(unknown.uuidString).plist")
        try Data("future".utf8).write(to: unknownContent)

        let relaunched = makeModel()
        XCTAssertEqual(relaunched.items.map(\.text), ["kept"], "missing fields take their defaults")
        _ = relaunched.store.content(for: kept.id) // waits for the store queue
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknownContent.path), "content of unreadable entries is not deleted")
        relaunched.writeToPasteboard(kept.id)
        XCTAssertEqual(pasteboard.string(forType: .string), "kept")

        // Saving writes the unknown entry back, so a later launch does not take its content for an orphan.
        relaunched.flush()
        let again = makeModel()
        _ = again.store.content(for: kept.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknownContent.path), "unknown entries survive repeated saves")
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("index.json"))) as? [[String: Any]])
        XCTAssertTrue(saved.contains { $0["id"] as? String == unknown.uuidString && $0["kind"] as? String == "video" })
    }

    func testCorruptIndexIsBackedUpAndNoContentIsDeletedOnLaterLaunches() async throws {
        let model = makeModel()
        await copy(model, text: "before corruption")
        model.flush()
        let id = try XCTUnwrap(model.items.first).id
        try Data("{not json".utf8).write(to: root.appendingPathComponent("index.json"))

        let first = makeModel()
        XCTAssertTrue(first.items.isEmpty)
        first.flush()
        let second = makeModel()
        XCTAssertNotNil(second.store.content(for: id), "content stays while the unreadable index copy exists")
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("index-unreadable-") })
    }

    func testRichTextKeepsItsFormatsAndCanPastePlain() async throws {
        let model = makeModel()
        let rtf = try NSAttributedString(string: "Bold words", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            .data(from: NSRange(location: 0, length: 10), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pasteboard.clearContents()
        pasteboard.setString("Bold words", forType: .string)
        pasteboard.setData(rtf, forType: .rtf)
        model.poll()
        await model.waitForBackgroundWork()

        let item = try XCTUnwrap(model.items.first)
        XCTAssertTrue(item.isRich)
        pasteboard.clearContents()
        model.writeToPasteboard(item.id)
        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf, "the original formats are pasted back")

        let plain = try XCTUnwrap(SmartActions.actions(for: item, context: model.smartContext).first { $0.kind == .pastePlain })
        model.writeToPasteboard(item.id, text: plain.result)
        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertEqual(pasteboard.string(forType: .string), "Bold words")
    }

    func testJSONAndJWTOfferConversionsAndDecodedTextIsSearchable() async throws {
        let model = makeModel()
        await copy(model, text: #"{"b":1.50,"a":[{},"x\"y"],"c":{"d":null}}"#)
        let json = try XCTUnwrap(model.items.first)
        XCTAssertEqual(json.contentType, .json)
        let format = try XCTUnwrap(SmartActions.actions(for: json, context: model.smartContext).first { $0.kind == .jsonFormat })
        XCTAssertEqual(format.result, """
        {
          "b": 1.50,
          "a": [
            {},
            "x\\"y"
          ],
          "c": {
            "d": null
          }
        }
        """, "key order and number spelling are kept")

        // {"alg":"HS256","typ":"JWT"} . {"sub":"tinycopy-user","exp":4102444000}
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0aW55Y29weS11c2VyIiwiZXhwIjo0MTAyNDQ0MDAwfQ.c2lnbmF0dXJl"
        await copy(model, text: token)
        let jwt = try XCTUnwrap(model.items.first)
        XCTAssertEqual(jwt.contentType, .jwt)
        let decode = try XCTUnwrap(SmartActions.actions(for: jwt, context: model.smartContext).first { $0.kind == .jwtDecode })
        XCTAssertTrue(decode.result?.contains(#""sub": "tinycopy-user""#) == true)
        XCTAssertTrue(decode.result?.contains(#""alg": "HS256""#) == true)
        XCTAssertEqual(model.search("tinycopy-user").first?.id, jwt.id, "decoded claims are searchable")

        await copy(model, text: "hello world")
        XCTAssertEqual(model.items.first?.contentType, .plain)
        XCTAssertFalse(SmartActions.actions(for: try XCTUnwrap(model.items.first), context: model.smartContext)
            .contains { [.base64Decode, .jwtDecode, .jsonFormat].contains($0.kind) }, "ordinary text is not misread")
    }

    func testImageIsKeptWithThumbnailAndItsTextIsRecognizedAndSearchable() async throws {
        settings.ocrMode = .automatic
        let model = makeModel()
        let png = try renderTextImage("TinyCopy Receipt 2026")
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        model.poll()
        await model.waitForBackgroundWork()

        let item = try XCTUnwrap(model.items.first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.imageWidth, 900)
        XCTAssertNotNil(model.thumbnail(for: item))
        XCTAssertTrue(item.ocrText?.lowercased().contains("receipt") == true, "recognized: \(item.ocrText ?? "nil")")
        XCTAssertEqual(model.search("receipt").first?.id, item.id)

        pasteboard.clearContents()
        model.writeToPasteboard(item.id)
        XCTAssertEqual(pasteboard.data(forType: .png), png, "the original image is pasted back")
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
    }

    func testPreviewPreservesClipboardAndOriginalContentUntilExplicitPaste() async throws {
        let model = makeModel()
        let other = #"{"other":2.50}"#
        await copy(model, text: other)
        let original = #"{"preview":true,"count":1.50}"#
        await copy(model, text: original)
        let item = try XCTUnwrap(model.items.first)
        let panel = PanelState(model: model)
        panel.perform = { selected, text, _ in model.writeToPasteboard(selected.id, text: text) }
        panel.prepareForShow()
        XCTAssertFalse(panel.previewVisible)
        panel.activate(paste: true)
        XCTAssertEqual(pasteboard.string(forType: .string), original)

        // Browsing and processing previews never write to the clipboard by themselves.
        panel.move(-1)
        XCTAssertTrue(panel.previewVisible)
        XCTAssertEqual(panel.currentPreview, .original)
        panel.movePreview(1)
        let result = try XCTUnwrap(panel.selectedAction?.result)
        XCTAssertNotEqual(result, original)
        XCTAssertEqual(pasteboard.string(forType: .string), original)
        panel.activate(paste: true)
        XCTAssertEqual(pasteboard.string(forType: .string), result)

        // Up/Down still selects records after processing was chosen, and always resets to source.
        panel.move(1)
        XCTAssertEqual(panel.selected?.text, other)
        XCTAssertEqual(panel.currentPreview, .original)
        panel.activate(paste: true)
        XCTAssertEqual(pasteboard.string(forType: .string), other)
        panel.movePreview(1)
        panel.movePreview(-1)
        panel.activate(paste: true)
        XCTAssertEqual(pasteboard.string(forType: .string), other)
        panel.movePreview(1)
        panel.escape()
        XCTAssertFalse(panel.previewVisible)
        panel.activate(paste: true)
        XCTAssertEqual(pasteboard.string(forType: .string), other)
        panel.prepareForShow()
        XCTAssertEqual(panel.currentPreview, .original)
        XCTAssertFalse(panel.previewVisible)

        // An explicit transformed paste must not overwrite the stored source on disk.
        panel.run(.jsonFormat, on: item.id)
        model.flush()
        let relaunched = makeModel()
        relaunched.writeToPasteboard(item.id)
        XCTAssertEqual(pasteboard.string(forType: .string), original)
    }

    func testChangingRecordCancelsPendingOCRPaste() async throws {
        settings.ocrMode = .onDemand
        let model = makeModel()
        await copy(model, text: "Original record")
        let png = try renderTextImage("TinyCopy Preview 2026")
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        model.poll()
        await model.waitForBackgroundWork()
        let image = try XCTUnwrap(model.items.first)
        let panel = PanelState(model: model)
        var outputCount = 0
        panel.perform = { selected, text, _ in
            outputCount += 1
            model.writeToPasteboard(selected.id, text: text)
        }
        panel.run(.ocr, on: image.id)
        panel.move(1)
        await model.waitForBackgroundWork()
        XCTAssertNotNil(model.item(image.id)?.ocrText)
        XCTAssertEqual(outputCount, 0, "a late result must never paste after the user has moved on")
        XCTAssertEqual(pasteboard.data(forType: .png), png)
        panel.activate(paste: true)
        XCTAssertEqual(pasteboard.string(forType: .string), "Original record")
    }

    func testClearHistoryKeepsPinnedWhenRequestedAndPersistsDeletion() async throws {
        let model = makeModel()
        await copy(model, text: "Keep pinned")
        let pinned = try XCTUnwrap(model.items.first)
        model.togglePin(pinned.id)
        await copy(model, text: "Remove unpinned")
        let removed = try XCTUnwrap(model.items.first)
        XCTAssertEqual(model.search("unpinned").map(\.id), [removed.id])
        model.clearHistory(keepPinned: true)
        XCTAssertTrue(model.search("unpinned").isEmpty, "deleted content must also disappear from cached searches")
        model.flush()
        let relaunched = makeModel()
        XCTAssertEqual(relaunched.items.map(\.id), [pinned.id])
        XCTAssertNil(relaunched.store.content(for: removed.id))
        XCTAssertNotNil(relaunched.store.content(for: pinned.id))
        XCTAssertEqual(pasteboard.string(forType: .string), "Remove unpinned", "clearing stored history must not erase the system clipboard")
        relaunched.clearHistory(keepPinned: false)
        relaunched.flush()
        let empty = makeModel()
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertNil(empty.store.content(for: pinned.id))
    }

    func testQRCodeContentsAreKeptSearchableAndSurviveRelaunchWithoutOCR() async throws {
        settings.ocrMode = .off
        let model = makeModel()
        let payload = "https://example.com/二维码?name=TinyCopy&message=hello%20world"
        let png = try XCTUnwrap(QRCode.encode(payload))
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        model.poll()
        await model.waitForBackgroundWork()
        let image = try XCTUnwrap(model.items.first)
        XCTAssertEqual(image.qrContents, [payload])
        XCTAssertNil(image.ocrText)
        XCTAssertEqual(model.search("二维码").first?.id, image.id)
        let action = try XCTUnwrap(SmartActions.actions(for: image, context: model.smartContext).first { $0.kind == .qrRead })
        model.writeToPasteboard(image.id, text: action.result)
        XCTAssertEqual(pasteboard.string(forType: .string), payload)
        model.flush()
        let relaunched = makeModel()
        XCTAssertEqual(relaunched.item(image.id)?.qrContents, [payload])
        relaunched.writeToPasteboard(image.id)
        XCTAssertEqual(pasteboard.data(forType: .png), png, "extracting a QR payload must preserve the original image")
    }

    func testGeneratedQRCodeDoesNotOverwriteSourceOrRecaptureItself() async throws {
        let model = makeModel()
        let url = "https://example.com/tinycopy?value=hello%20world&count=1.50"
        await copy(model, text: url)
        let source = try XCTUnwrap(model.items.first)
        let panel = PanelState(model: model)
        var outputs = 0
        panel.performImage = { data, _ in
            outputs += 1
            model.writeImageToPasteboard(data)
        }
        panel.run(.qrGenerate, on: source.id)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while outputs == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(outputs, 1)
        let png = try XCTUnwrap(pasteboard.data(forType: .png))
        let decoded = await Task.detached(priority: .utility) { QRCode.decode(png) }.value
        XCTAssertEqual(decoded, [url])
        model.poll()
        await model.waitForBackgroundWork()
        XCTAssertEqual(model.items.count, 1)
        model.flush()
        let relaunched = makeModel()
        relaunched.writeToPasteboard(source.id)
        XCTAssertEqual(pasteboard.string(forType: .string), url)

        // Moving to another record cancels a requested QR paste before generation completes.
        await copy(model, text: "https://example.com/another-record")
        panel.run(.qrGenerate, on: try XCTUnwrap(model.items.first).id)
        panel.move(1)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(outputs, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "https://example.com/another-record")
    }

    private func renderTextImage(_ text: String) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 200, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 200).fill()
        (text as NSString).draw(at: NSPoint(x: 40, y: 70), withAttributes: [.font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
