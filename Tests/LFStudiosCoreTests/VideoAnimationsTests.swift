import AppKit
import XCTest
@testable import LFStudiosCore

/// In, Out and Combo animations (1.15.0): what each does over time, how
/// they add up, the export's pixels, and the command.
@MainActor
final class VideoAnimationsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    func testPresetsStartAwayAndEndInPlace() {
        for preset in VideoAnimationPreset.allCases {
            let away = preset.change(0)
            let home = preset.change(1)
            XCTAssertEqual(home, VideoAnimationChange(), "\(preset) ends where the item is")
            XCTAssertNotEqual(away, VideoAnimationChange(), "\(preset) starts somewhere else")
            XCTAssertFalse(preset.title.isEmpty)
        }
        for combo in VideoComboPreset.allCases {
            XCTAssertEqual(combo.change(0).opacity, 1, "\(combo) never fades")
            XCTAssertFalse(combo.title.isEmpty)
        }
    }

    func testInOutAndComboOverTheItem() {
        var animation = VideoItemAnimation()
        animation.inPreset = .fade
        animation.inLength = 1
        animation.outPreset = .fade
        animation.outLength = 1
        XCTAssertEqual(animation.change(at: 0, length: 5).opacity, 0, accuracy: 0.001)
        XCTAssertEqual(animation.change(at: 2.5, length: 5).opacity, 1, accuracy: 0.001, "in place between them")
        XCTAssertEqual(animation.change(at: 5, length: 5).opacity, 0, accuracy: 0.001)
        animation.combo = .pulse
        animation.comboLength = 1
        XCTAssertGreaterThan(animation.change(at: 2.5, length: 5).scale, 1.05, "half a cycle in: biggest")
        // On the item: size and place follow.
        var item = VideoLayerItem(kind: .image, path: "/p.png", name: "p", at: 10, length: 5, aspect: 1)
        item.width = 0.5
        item.animation = VideoItemAnimation(inPreset: .slideLeft, inLength: 1)
        let start = item.shown(at: 10).item
        XCTAssertGreaterThan(start.x, item.x, "slides in from the right")
        XCTAssertEqual(item.shown(at: 12).item.x, item.x, accuracy: 0.0001)
        item.animation = VideoItemAnimation(inPreset: .blur, inLength: 1)
        XCTAssertGreaterThan(item.shown(at: 10).blur, 10)
        XCTAssertEqual(item.shown(at: 12).blur, 0)
    }

    func testAFadeInIsInTheExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-anim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("white.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.white, 3)])
        var project = VideoInspection.project(for: source, seconds: 3, size: CGSize(width: 320, height: 180))
        project.padding = 0
        let png = directory.appendingPathComponent("red.png")
        try VideoInspection.writePNG(to: png, size: CGSize(width: 160, height: 90), color: .red)
        var item = VideoLayerItem(kind: .image, path: png.path, name: "red.png", at: 0, length: 3, aspect: 16.0 / 9)
        item.width = 1
        item.animation = VideoItemAnimation(inPreset: .fade, inLength: 2)
        project.layerTracks = [VideoLayerTrack(items: [item])]
        let output = directory.appendingPathComponent("fade.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let early = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 0.1), x: 0.5, y: 0.5)
        let late = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 2.6), x: 0.5, y: 0.5)
        XCTAssertGreaterThan(early.g, 0.7, "barely in yet \(early)")
        XCTAssertLessThan(late.g, 0.2, "fully in \(late)")
    }

    func testTheCommandIsOneStep() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-anim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 3)])
        VideoDemoDraftStore.delete(for: url)
        defer { VideoDemoDraftStore.delete(for: url) }
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let png = directory.appendingPathComponent("a.png")
        try VideoInspection.writePNG(to: png, size: CGSize(width: 100, height: 100), color: .green)
        let added = await model.addLayerItem(from: png, at: 0)
        let id = try XCTUnwrap(added)
        XCTAssertNil(model.project.layerItem(id)?.animation, "starts off")
        let depth = model.undoDepth
        XCTAssertTrue(model.perform(.edit(.setAnimation(VideoItemAnimation(inPreset: .pop)))))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.project.layerItem(id)?.animation?.inPreset, .pop)
        model.endGesture()
        model.perform(.edit(.setAnimation(VideoItemAnimation())))
        XCTAssertNil(model.project.layerItem(id)?.animation, "None takes it off")
    }
}
