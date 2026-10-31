import AppKit
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Text clips on their own track (1.15.0): only macOS fonts, the look in
/// rendered pixels, the export, the commands and the project format.
@MainActor
final class VideoTextClipsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-text-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testEveryFontComesWithMacOS() {
        for family in VideoTextFonts.families {
            XCTAssertNotNil(NSFontManager.shared.availableMembers(ofFontFamily: family), "\(family) is on every Mac")
        }
        // A font that isn't on the list (installed or not) is never used.
        let font = VideoTextFonts.font("Some Font Someone Installed", size: 20, bold: false, italic: false)
        XCTAssertEqual(font.familyName, VideoTextFonts.defaultFamily)
        XCTAssertTrue(VideoTextFonts.font("Futura", size: 20, bold: true, italic: false).fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testTheLookInPixels() throws {
        var content = VideoTextContent(string: "HELLO")
        content.color = VideoRGBA(1, 0, 0)
        content.background = .init(color: VideoRGBA(0, 0, 1, 1), padding: 30, radius: 0)
        let image = try XCTUnwrap(content.image(pixelHeight: 200))
        let middle = VideoInspection.color(of: image, x: 0.5, y: 0.5, radius: 6)
        XCTAssertTrue(middle.r > 0.6 || middle.b > 0.6, "red letters on blue \(middle)")
        let edge = VideoInspection.color(of: image, x: 0.5, y: 0.2, radius: 1)
        XCTAssertGreaterThan(edge.b, 0.8, "the background behind the words \(edge)")
        // Bigger text: a bigger picture; more letter spacing: wider.
        let small = content.naturalSize()
        content.size = 144
        XCTAssertGreaterThan(content.naturalSize().height, small.height * 1.35, "the padding stays, the words double")
        content.size = 72
        content.letterSpacing = 40
        XCTAssertGreaterThan(content.naturalSize().width, small.width + 60, "40 points between each of the letters")
    }

    func testATextClipInTheExport() async throws {
        let source = directory.appendingPathComponent("black.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 640, height: 360), colors: [(.black, 2)])
        var project = VideoInspection.project(for: source, seconds: 2, size: CGSize(width: 640, height: 360))
        var content = VideoTextContent(string: "■■■")
        content.size = 200
        content.color = VideoRGBA(0, 1, 0)
        let item = VideoLayerItem.text(content, at: 0, canvas: CGSize(width: 640, height: 360))
        project.layerTracks = [VideoLayerTrack(items: [item])]
        XCTAssertTrue(project.needsFormat4)
        let output = directory.appendingPathComponent("text.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let frame = try VideoInspection.frame(of: output, at: 1)
        let middle = VideoInspection.color(of: frame, x: 0.5, y: 0.5, radius: 4)
        XCTAssertGreaterThan(middle.g, 0.6, "green squares in the middle \(middle)")
        let corner = VideoInspection.color(of: frame, x: 0.05, y: 0.05)
        XCTAssertLessThan(corner.g, 0.15, "the rest stays black")
    }

    func testCommandsAndUndo() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        model.seek(to: 1)
        var depth = model.undoDepth
        XCTAssertTrue(model.perform(.addTextClip))
        XCTAssertEqual(model.undoDepth, depth + 1)
        let item = try XCTUnwrap(model.selectedLayerItem)
        XCTAssertTrue(item.isText)
        XCTAssertEqual(item.at, 1, accuracy: 0.001)
        XCTAssertEqual(model.project.layerTracks.count, 1, "on a track of its own")
        // A typing session and a drag are one step each; the size follows.
        var content = try XCTUnwrap(item.text)
        depth = model.undoDepth
        for word in ["H", "He", "Hello there"] {
            content.string = word
            model.perform(.edit(.setText(content)))
        }
        model.endGesture()
        XCTAssertEqual(model.undoDepth, depth + 1)
        let typed = try XCTUnwrap(model.selectedLayerItem)
        XCTAssertEqual(typed.name, "Hello there")
        XCTAssertGreaterThan(typed.width, item.width)
        // A size set by hand keeps its proportion when the look changes.
        model.setLayerItem(typed.id, label: "Clip Change") { $0.width = typed.width / 2 }
        content.bold = true
        model.perform(.edit(.setText(content)))
        model.endGesture()
        let bolded = try XCTUnwrap(model.selectedLayerItem)
        XCTAssertLessThan(bolded.width, typed.width * 0.7)
        // Undo brings the words back.
        model.undo()
        model.undo()
        model.undo()
        XCTAssertEqual(model.selectedLayerItem?.text?.string, L("Your text"))
        // Locked: refused.
        let track = try XCTUnwrap(model.project.layerTracks.first?.id)
        model.toggleTrackLocked(.layer(track))
        let before = model.project.layerTracks
        content.string = "Nope"
        XCTAssertFalse(model.perform(.edit(.setText(content))))
        XCTAssertEqual(model.project.layerTracks, before)
    }

    func testOldFilesStayTheSame() throws {
        // An item without text writes no "text" key (1.14.0's files).
        let picture = VideoLayerItem(kind: .image, path: "/tmp/a.png", name: "a.png", at: 0, length: 5, aspect: 1)
        let json = String(decoding: try JSONEncoder().encode(picture), as: UTF8.self)
        XCTAssertFalse(json.contains("\"text\""))
        XCTAssertFalse(picture.needsFormat4)
        let text = VideoLayerItem.text(VideoTextContent(string: "Hi"), at: 0, canvas: CGSize(width: 1920, height: 1080))
        let decoded = try JSONDecoder().decode(VideoLayerItem.self, from: try JSONEncoder().encode(text))
        XCTAssertEqual(decoded, text)
        XCTAssertTrue(decoded.needsFormat4)
    }
}
