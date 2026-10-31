import AppKit
import XCTest
@testable import LFStudiosCore

/// 1.14.0's annotations stay over every track until moved; Move to a track
/// makes a text or picture annotation a clip on its own top track (1.15.0).
@MainActor
final class VideoAnnotationToTrackTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-totrack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testTextAndPicturesMoveArrowsDont() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        model.seek(to: 1)
        model.addOverlay(.text)
        let text = try XCTUnwrap(model.project.overlayEffects.last)
        model.updateOverlay(text.id) { $0.text = "Hello" }
        model.endGesture()
        let depth = model.undoDepth
        let id = try XCTUnwrap(model.moveAnnotationToTrack(text.id))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertFalse(model.project.overlayEffects.contains { $0.id == text.id })
        let item = try XCTUnwrap(model.project.layerItem(id))
        XCTAssertEqual(item.text?.string, "Hello")
        XCTAssertEqual(item.at, 1, accuracy: 0.05)
        XCTAssertEqual(model.project.layerTrackIndex(of: id), model.project.layerTracks.count - 1, "on top")
        model.undo()
        XCTAssertTrue(model.project.overlayEffects.contains { $0.id == text.id })
        // Arrows stay annotations.
        model.addOverlay(.arrow)
        let arrow = try XCTUnwrap(model.project.overlayEffects.first { $0.kind == .arrow })
        XCTAssertNil(model.moveAnnotationToTrack(arrow.id))
    }

    func testAPictureLooksTheSameOnATrack() throws {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 4, sourceSize: CGSize(width: 1920, height: 1080))
        var overlay = VideoDemoOverlayEffect(kind: .image, time: 1, duration: 2, x: 0.3, y: 0.6, width: 0.25, height: 0.2, text: "")
        overlay.image = VideoOverlayImage(path: "/tmp/a.png", name: "a.png", aspect: 1.5, opacity: 0.8)
        project.overlayEffects = [overlay]
        let segments = project.timelineSegments(totalDuration: 4)
        let item = try XCTUnwrap(VideoLayerItem.from(overlay, project: project, segments: segments))
        let size = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(item.rect(in: size), overlay.imageRect(in: size), "the same place and size")
        XCTAssertEqual(item.opacity, 0.8)
        XCTAssertEqual(item.at, 1, accuracy: 0.001)
        XCTAssertEqual(item.length, 2, accuracy: 0.001)
    }
}
