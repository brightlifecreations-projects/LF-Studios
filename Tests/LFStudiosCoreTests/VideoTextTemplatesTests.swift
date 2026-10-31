import AppKit
import XCTest
@testable import LFStudiosCore

/// Library ▸ Text (1.15.0): templates and styles in macOS fonts only,
/// search, Library drags onto the timeline, one undo step each.
@MainActor
final class VideoTextTemplatesTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-templates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testTemplatesUseShippedFontsAndDraw() {
        let templates = VideoTextTemplate.all
        XCTAssertGreaterThanOrEqual(templates.count, 12)
        XCTAssertEqual(Set(templates.map(\.id)).count, templates.count, "ids are unique")
        for template in templates {
            XCTAssertTrue(VideoTextFonts.families.contains(template.content.font), "\(template.id) uses a macOS font")
            XCTAssertNotNil(template.content.image(pixelHeight: 100), "\(template.id) draws")
            XCTAssertNotNil(VideoTextLookPreview.image(template.content))
        }
        for style in VideoTextStyle.all {
            var content = VideoTextContent(string: "Aa")
            style.apply(&content)
            XCTAssertNotNil(content.image(pixelHeight: 60), style.id)
        }
    }

    func testPayloadsAndSearch() {
        let payload = VideoLibraryPayload(kind: "text", id: "title-pop")
        XCTAssertEqual(VideoLibraryPayload(string: payload.string), payload)
        XCTAssertNil(VideoLibraryPayload(string: "/Users/someone/file.png"))
        XCTAssertNil(VideoLibraryPayload(string: VideoLibraryPayload.prefix + "text/"))
        let tiles = [
            VideoLibraryTile(payload: .init(kind: "text", id: "a"), title: "Pop title", keywords: ["yellow"], section: "Titles"),
            VideoLibraryTile(payload: .init(kind: "text", id: "b"), title: "Name bar", section: "Lower thirds"),
        ]
        XCTAssertEqual(VideoLibraryTile.matching(tiles, search: "", favourites: nil).count, 2)
        XCTAssertEqual(VideoLibraryTile.matching(tiles, search: "YELLOW", favourites: nil).map(\.payload.id), ["a"], "keywords, any case")
        XCTAssertEqual(VideoLibraryTile.matching(tiles, search: "lower bar", favourites: nil).map(\.payload.id), ["b"], "every word, section too")
        XCTAssertEqual(VideoLibraryTile.matching(tiles, search: "", favourites: ["text/b"]).map(\.payload.id), ["b"])
        XCTAssertTrue(VideoLibraryTile.matching(tiles, search: "zebra", favourites: nil).isEmpty)
    }

    func testPlacingTemplatesAndStyles() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 6)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        // Dropped on the timeline at 2 s: one step, there, with its look and animation.
        var depth = model.undoDepth
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "text", id: "lower-bar"), at: 2, target: .layer(.automatic)))
        XCTAssertEqual(model.undoDepth, depth + 1)
        let item = try XCTUnwrap(model.selectedLayerItem)
        let template = try XCTUnwrap(VideoTextTemplate.all.first { $0.id == "lower-bar" })
        XCTAssertEqual(item.at, 2, accuracy: 0.001)
        XCTAssertEqual(item.text, template.content)
        XCTAssertEqual(item.animation, template.animation)
        XCTAssertEqual(item.y, template.y)
        XCTAssertFalse(model.placeLibraryItem(VideoLibraryPayload(kind: "text", id: "no-such"), at: 0))
        // A style on the selected clip: one step, the words stay.
        depth = model.undoDepth
        model.applyTextStyle(try XCTUnwrap(VideoTextStyle.all.first { $0.id == "outline" }))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.selectedLayerItem?.text?.string, template.content.string)
        XCTAssertNotNil(model.selectedLayerItem?.text?.stroke)
        XCTAssertNil(model.selectedLayerItem?.text?.background)
        // Nothing selected: a new text clip with it.
        model.selection = .none
        model.applyTextStyle(try XCTUnwrap(VideoTextStyle.all.first { $0.id == "neon" }))
        XCTAssertEqual(model.project.layerItems.filter { $0.item.isText }.count, 2)
    }
}

/// Favourites are kept in the shared settings (runs on its own: SERIAL).
@MainActor
final class VideoLibraryFavouritesTests: XCTestCase {
    func testStarringKeepsAndClears() async throws {
        let saved = Settings.videoLibraryFavourites
        defer { Settings.videoLibraryFavourites = saved }
        Settings.videoLibraryFavourites = []
        let model = VideoEditorModel(videoURL: URL(fileURLWithPath: "/tmp/none.mp4"))
        let payload = VideoLibraryPayload(kind: "text", id: "title-clean")
        model.toggleFavourite(payload)
        XCTAssertTrue(model.isFavourite(payload))
        XCTAssertEqual(Settings.videoLibraryFavourites, ["text/title-clean"])
        model.toggleFavourite(payload)
        XCTAssertFalse(model.isFavourite(payload))
        XCTAssertEqual(Settings.videoLibraryFavourites, [])
    }
}
