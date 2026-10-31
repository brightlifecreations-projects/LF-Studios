import AppKit
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Blend modes, cutout (chroma key, remove background) and masks on items
/// above the main track (1.15.0): in rendered pixels, through commands.
@MainActor
final class VideoItemLookTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private let size = CGSize(width: 200, height: 100)

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ rect: CGRect? = nil) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: rect ?? CGRect(origin: .zero, size: size))
    }

    private func color(_ image: CIImage, _ x: Double, _ y: Double) -> (r: Double, g: Double, b: Double) {
        VideoInspection.color(of: image.composited(over: solid(0, 0, 0)), size: size, x: x, y: y)
    }

    func testBlendModes() {
        let scene = solid(0.5, 0.5, 0.5)
        let red = solid(1, 0, 0, CGRect(x: 0, y: 0, width: 100, height: 100))
        let multiplied = VideoBlendMode.multiply.composite(red, over: scene)
        let m = color(multiplied, 0.25, 0.5)
        XCTAssertEqual(m.r, 0.5, accuracy: 0.08, "multiply: red × grey")
        XCTAssertLessThan(m.g, 0.08)
        let outside = color(multiplied, 0.75, 0.5)
        XCTAssertEqual(outside.g, 0.5, accuracy: 0.05, "only where it is")
        let screened = color(VideoBlendMode.screen.composite(red, over: scene), 0.25, 0.5)
        XCTAssertGreaterThan(screened.r, 0.9, "screen lightens")
        XCTAssertEqual(screened.g, 0.5, accuracy: 0.08)
        XCTAssertNil(VideoBlendMode.normal.filter)
    }

    func testChromaKeyTakesTheColourOut() {
        // Left half green screen, right half a dark-red subject.
        let picture = solid(0, 0.85, 0.2, CGRect(x: 0, y: 0, width: 100, height: 100)).composited(over: solid(0.6, 0.1, 0.1))
        let keyed = VideoCutout.chroma(picture, key: VideoChromaKey())
        let gone = color(keyed, 0.25, 0.5)
        XCTAssertLessThan(gone.g, 0.05, "the green is see-through (black behind it) \(gone)")
        let kept = color(keyed, 0.75, 0.5)
        XCTAssertGreaterThan(kept.r, 0.5, "the subject stays \(kept)")
    }

    func testMasksKeepTheShape() {
        let white = solid(1, 1, 1)
        var circle = VideoMask(shape: .circle)
        circle.size = 0.4
        circle.feather = 0
        let masked = circle.apply(to: white)
        XCTAssertGreaterThan(color(masked, 0.5, 0.5).r, 0.9, "inside the circle")
        XCTAssertLessThan(color(masked, 0.05, 0.1).r, 0.1, "outside it")
        circle.invert = true
        XCTAssertLessThan(color(circle.apply(to: white), 0.5, 0.5).r, 0.1, "inverted")
        var linear = VideoMask(shape: .linear)
        linear.feather = 0
        let half = linear.apply(to: white)
        XCTAssertGreaterThan(color(half, 0.5, 0.2).r, 0.9, "linear: keeps the top")
        XCTAssertLessThan(color(half, 0.5, 0.8).r, 0.1, "not the bottom")
        var band = VideoMask(shape: .mirror)
        band.size = 0.3
        band.feather = 0
        let mirrored = band.apply(to: white)
        XCTAssertGreaterThan(color(mirrored, 0.5, 0.5).r, 0.9, "mirror: the band")
        XCTAssertLessThan(color(mirrored, 0.5, 0.05).r, 0.1)
        var box = VideoMask(shape: .rectangle)
        box.size = 0.5
        box.feather = 0
        XCTAssertGreaterThan(color(box.apply(to: white), 0.5, 0.5).r, 0.9)
        XCTAssertLessThan(color(box.apply(to: white), 0.05, 0.5).r, 0.1)
    }

    func testRemoveBackgroundRunsAndKeepsTheFrame() {
        // A real person needs a real check; here: it runs and keeps the size.
        let picture = solid(0.4, 0.5, 0.6)
        let cut = VideoCutout.person(picture, key: "test-\(UUID())")
        XCTAssertEqual(cut.extent.width, picture.extent.width, accuracy: 1)
    }

    func testCommandsAreOneStepEachAndRefuseALockedTrack() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-look-\(UUID().uuidString)", isDirectory: true)
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
        for edit in [VideoItemEdit.setBlend(.screen), .setChromaKey(VideoChromaKey()), .setMask(VideoMask(shape: .circle)), .setRemoveBackground(true), .setValue(.opacity, 0.4)] {
            let depth = model.undoDepth
            let before = model.project.layerItem(id)
            XCTAssertTrue(model.perform(.edit(edit)), edit.name)
            model.endGesture()
            XCTAssertEqual(model.undoDepth, depth + 1, edit.name)
            XCTAssertNotEqual(model.project.layerItem(id), before, edit.name)
        }
        let item = try XCTUnwrap(model.project.layerItem(id))
        XCTAssertEqual(item.blend, .screen)
        XCTAssertEqual(item.mask?.shape, .circle)
        XCTAssertTrue(model.project.needsFormat4)
        // Everything starts off.
        let fresh = await model.addLayerItem(from: png, at: 1)
        let plain = try XCTUnwrap(model.project.layerItem(try XCTUnwrap(fresh)))
        XCTAssertNil(plain.blend); XCTAssertNil(plain.mask); XCTAssertNil(plain.chroma); XCTAssertNil(plain.removesBackground)
        // Locked: refused.
        model.selection = .layer(id)
        model.toggleTrackLocked(.layer(model.project.layerTracks[model.project.layerTrackIndex(of: id)!].id))
        let locked = model.project.layerItem(id)
        model.perform(.edit(.setBlend(.multiply)))
        XCTAssertEqual(model.project.layerItem(id), locked)
    }
}
