import AppKit
import XCTest
@testable import LFStudiosCore

/// The editor's panels (1.13.0): the Library, the player and Properties
/// across the top, their borders, the Layout menu, the Library's tabs, the
/// player's handles, and projects from newer versions.
@MainActor
final class VideoEditorPanelsTests: XCTestCase {
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "LFStudiosCoreTests.Panels.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        VideoEditorPanelStore.shared.reload()
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        VideoEditorPanelStore.shared.reload()
    }

    typealias Layout = VideoEditorPanelLayout

    // MARK: Sizes

    /// The editor's smallest window, a 13" MacBook's, and a large one.
    static let widths: [CGFloat] = [1080, 1280, 1440, 1920, 2560]

    func testEveryPanelFitsAtEverySize() {
        for preset in Layout.Preset.allCases {
            for width in Self.widths {
                let fitted = preset.layout.fitted(windowWidth: width)
                XCTAssertGreaterThanOrEqual(fitted.player, Layout.minimumPlayer, "\(preset) \(width): the player keeps room")
                XCTAssertTrue(Layout.libraryRange.contains(fitted.library), "\(preset) \(width)")
                XCTAssertTrue(Layout.propertiesRange.contains(fitted.properties), "\(preset) \(width)")
                XCTAssertEqual(fitted.library + fitted.player + fitted.properties + Layout.borders, width, accuracy: 0.001, "\(preset) \(width): the whole width")
            }
        }
        // As chosen when there's room.
        let wide = Layout.standard.fitted(windowWidth: 1920)
        XCTAssertEqual(wide.library, 300)
        XCTAssertEqual(wide.properties, 318)
        // Player first: a bigger player.
        XCTAssertGreaterThan(Layout.playerFirst.fitted(windowWidth: 1280).player, Layout.standard.fitted(windowWidth: 1280).player)
    }

    func testANarrowWindowShrinksTheLibraryFirst() {
        let wide = Layout(library: 480, properties: 440)
        let fitted = wide.fitted(windowWidth: 1080)
        XCTAssertEqual(fitted.player, Layout.minimumPlayer, accuracy: 0.001)
        XCTAssertEqual(fitted.properties, 440, "Properties keeps its width…")
        XCTAssertEqual(fitted.library, 1080 - Layout.minimumPlayer - Layout.borders - 440, accuracy: 0.001, "…the Library gives way first")
        // Narrower still: the Library at its least, then Properties gives way.
        let narrow = wide.fitted(windowWidth: 950)
        XCTAssertEqual(narrow.library, Layout.libraryRange.lowerBound)
        XCTAssertEqual(narrow.properties, 950 - Layout.minimumPlayer - Layout.borders - Layout.libraryRange.lowerBound, accuracy: 0.001)
        // Out-of-range values (a hand-edited setting) are kept in range.
        let odd = Layout(library: 10, properties: 9000).fitted(windowWidth: 1920)
        XCTAssertEqual(odd.library, Layout.libraryRange.lowerBound)
        XCTAssertEqual(odd.properties, Layout.propertiesRange.upperBound)
    }

    func testTheLayoutMenuIsRememberedAndResets() {
        let store = VideoEditorPanelStore.shared
        XCTAssertEqual(store.layout, .standard)
        XCTAssertNil(Settings.videoEditorPanels)
        store.choose(.playerFirst)
        XCTAssertEqual(Settings.videoEditorPanels, .playerFirst)
        XCTAssertEqual(store.layout.preset, .playerFirst)
        // A drag: shown at once, remembered when it ends.
        store.set(Layout(library: 350, properties: 300), remember: false)
        XCTAssertEqual(Settings.videoEditorPanels, .playerFirst)
        store.set(Layout(library: 350, properties: 300), remember: true)
        XCTAssertEqual(Settings.videoEditorPanels, Layout(library: 350, properties: 300))
        XCTAssertNil(store.layout.preset, "neither layout now")
        // Reset Layout: everything where it starts, the timeline too.
        Settings.videoTimelineFraction = 0.5
        let reset = expectation(forNotification: .lfstudiosEditorLayoutReset, object: nil)
        store.reset()
        wait(for: [reset], timeout: 1)
        XCTAssertEqual(store.layout, .standard)
        XCTAssertNil(Settings.videoEditorPanels)
        XCTAssertNil(Settings.videoTimelineFraction)
    }

    // MARK: The Library and the player

    func testTheLibraryShowsOnlyTabsWithSomethingInThem() {
        // CapCut's order (1.15.0): every tab has its own content.
        XCTAssertEqual(VideoLibraryTab.allCases, [.media, .audio, .text, .stickers, .effects, .transitions, .captions, .filters, .adjustment])
        for tab in VideoLibraryTab.allCases { XCTAssertFalse(tab.title.isEmpty) }
        // Every Library item kind has a handler (drag, + and double-click).
        let kinds = Set(VideoEditorModel.libraryHandlers.map(\.kind))
        XCTAssertEqual(kinds, ["text", "sticker", "effect", "transition", "caption", "filter", "adjustment", "sound"])
    }

    func testThePlayersZoom() {
        XCTAssertEqual(VideoEditorModel.previewZooms, [1, 1.5, 2, 3])
        XCTAssertEqual(VideoEditorModel.previewZoomTitle(1), "Fit")
        XCTAssertEqual(VideoEditorModel.previewZoomTitle(2), "200%")
    }

    func testMovingSnapsToTheMiddleAndEdgesWithGuides() {
        let size = CGSize(width: 800, height: 450)
        let nearMiddle = CGRect(x: 400 - 50 + 4, y: 225 - 25 - 3, width: 100, height: 50)
        let middle = VideoAlignmentGuides.snap(nearMiddle, in: size, threshold: 6)
        XCTAssertEqual(middle.rect.midX, 400)
        XCTAssertEqual(middle.rect.midY, 225)
        XCTAssertEqual(middle.guides, [.init(axis: .vertical, position: 400), .init(axis: .horizontal, position: 225)])
        let nearEdge = CGRect(x: 4, y: 450 - 50 - 2, width: 100, height: 50)
        let edge = VideoAlignmentGuides.snap(nearEdge, in: size, threshold: 6)
        XCTAssertEqual(edge.rect.minX, 0)
        XCTAssertEqual(edge.rect.maxY, 450)
        let free = CGRect(x: 120, y: 80, width: 100, height: 50)
        XCTAssertEqual(VideoAlignmentGuides.snap(free, in: size, threshold: 6).rect, free)
        XCTAssertTrue(VideoAlignmentGuides.snap(free, in: size, threshold: 6).guides.isEmpty)
    }

    func testTheRotateKnob() {
        let center = CGPoint(x: 100, y: 100)
        XCTAssertEqual(VideoAlignmentGuides.rotation(from: center, to: CGPoint(x: 100, y: 40), steps: false), 0, accuracy: 0.001, "straight up: upright")
        XCTAssertEqual(VideoAlignmentGuides.rotation(from: center, to: CGPoint(x: 160, y: 100), steps: false), 90, accuracy: 0.001, "right: a quarter turn clockwise")
        XCTAssertEqual(VideoAlignmentGuides.rotation(from: center, to: CGPoint(x: 160, y: 98), steps: false), 90, accuracy: 0.001, "near a quarter turn: settles there")
        XCTAssertEqual(VideoAlignmentGuides.rotation(from: center, to: CGPoint(x: 140, y: 40), steps: false), 33.69, accuracy: 0.01)
        XCTAssertEqual(VideoAlignmentGuides.rotation(from: center, to: CGPoint(x: 140, y: 40), steps: true), 30, accuracy: 0.001, "⇧: steps of 15°")
        // A drag along a picture turned 90°: its own width grows.
        let along = VideoImageOverlayHandles.unturn(CGSize(width: 0, height: 20), by: 90)
        XCTAssertEqual(along.width, 20, accuracy: 0.001)
        XCTAssertEqual(along.height, 0, accuracy: 0.001)
    }

    func testOlderPicturesAreUpright() throws {
        let json = #"{"path": "/tmp/logo.png", "name": "logo.png", "aspect": 2, "opacity": 1}"#
        let image = try JSONDecoder().decode(VideoOverlayImage.self, from: Data(json.utf8))
        XCTAssertNil(image.rotation)
        XCTAssertEqual(image.keptRotation, 0)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(image), as: UTF8.self).contains("rotation"), "nothing new written")
        var turned = image
        turned.rotation = 270
        XCTAssertEqual(turned.keptRotation, -90)
    }

    func testATurnedPictureIsTurnedInTheVideo() throws {
        // 200 × 50, red on the left half and blue on the right.
        let picture = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 50))
            .composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 50)))
        let rect = CGRect(x: 100, y: 100, width: 200, height: 50)
        let upright = VideoImageOverlayRenderer.placed(picture, in: rect, opacity: 1, rotation: 0)
        XCTAssertEqual(upright.extent.width, 200, accuracy: 0.5)
        let turned = VideoImageOverlayRenderer.placed(picture, in: rect, opacity: 1, rotation: 90)
        XCTAssertEqual(turned.extent.width, 50, accuracy: 0.5, "a quarter turn: tall")
        XCTAssertEqual(turned.extent.height, 200, accuracy: 0.5)
        XCTAssertEqual(turned.extent.midX, rect.midX, accuracy: 0.5, "about its middle")
        // Clockwise on screen: the left (red) half ends up on top (high y).
        let context = CIContext()
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(turned, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: rect.midX, y: rect.midY + 60, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        XCTAssertGreaterThan(pixel[0], 200, "red on top")
        XCTAssertLessThan(pixel[2], 60)
    }

    // MARK: Projects from newer versions

    func testANewerKindOfProjectAsksForANewerVersion() throws {
        func manifest(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
        // A later project format than this one reads.
        XCTAssertThrowsError(try VideoProjectDocument.decode(manifest(["format": "lfstudios-project-5", "version": 5]))) { error in
            XCTAssertEqual(error as? VideoProjectDocument.ReadError, .needsNewerVersion)
        }
        // One that says it needs a later version.
        XCTAssertThrowsError(try VideoProjectDocument.decode(manifest(["format": VideoProjectDocument.format, "version": 3, VideoProjectDocument.requiresKey: VideoProjectDocument.currentVersion + 1]))) { error in
            XCTAssertEqual(error as? VideoProjectDocument.ReadError, .needsNewerVersion)
        }
        // Something else entirely is still "not a project".
        XCTAssertThrowsError(try VideoProjectDocument.decode(manifest(["format": "somebody-elses-file"]))) { error in
            XCTAssertEqual(error as? VideoProjectDocument.ReadError, .notAProject)
        }
        let words = VideoProjectOpener.newerVersionMessage("Demo")
        XCTAssertEqual(words.title, "This project needs a newer version of LF Studios")
        XCTAssertTrue(words.detail.contains("“Demo”"))
    }
}
