import AppKit
import XCTest
@testable import LFStudiosCore

/// Compound clips (1.15.0): made and broken apart in one step each, moved,
/// sized, turned and faded as one (in the export too), and Break apart
/// keeps the look.
@MainActor
final class VideoCompoundsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-compounds-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testTheTransform() {
        var item = VideoLayerItem(kind: .image, path: "/tmp/a.png", name: "a", at: 0, length: 2, aspect: 1)
        item.x = 0.75
        item.y = 0.5
        item.width = 0.2
        let canvas = CGSize(width: 1600, height: 900)
        XCTAssertEqual(VideoCompoundClip(name: "c").apply(to: item, canvas: canvas), item, "as made: unchanged")
        var half = VideoCompoundClip(name: "c")
        half.scale = 0.5
        half.opacity = 0.5
        let small = half.apply(to: item, canvas: canvas)
        XCTAssertEqual(small.x, 0.625, accuracy: 0.0001, "closer to the middle")
        XCTAssertEqual(small.width, 0.1, accuracy: 0.0001)
        XCTAssertEqual(small.opacity, 0.5, accuracy: 0.0001)
        var turned = VideoCompoundClip(name: "c")
        turned.rotation = 90
        let quarter = turned.apply(to: item, canvas: canvas)
        XCTAssertEqual(quarter.x, 0.5, accuracy: 0.0001, "a quarter turn about the middle")
        XCTAssertEqual(quarter.y, 0.5 + 0.25 * 1600 / 900, accuracy: 0.0001)
        XCTAssertEqual(quarter.rotation, 90, accuracy: 0.0001)
    }

    func testMakeMoveAndBreakApart() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let a = model.addSticker(.star, at: 0)
        let b = model.addSticker(.heart, at: 1)
        // Nothing selected: refused.
        model.selection = .none
        XCTAssertFalse(model.perform(.makeCompound))
        model.selection = .layer(a)
        model.extraSelection = [.layer(b)]
        var depth = model.undoDepth
        XCTAssertTrue(model.perform(.makeCompound))
        XCTAssertEqual(model.undoDepth, depth + 1)
        let compound = try XCTUnwrap(model.project.compounds?.first)
        XCTAssertEqual(Set(model.project.compoundMembers(compound.id).map(\.item.id)), [a, b])
        XCTAssertTrue(model.project.needsFormat4)
        XCTAssertEqual(VideoCompoundBlock.blocks(model.project).first?.first, a, "one block, standing for the earliest clip")
        XCTAssertEqual(VideoCompoundBlock.blocks(model.project).first?.end ?? 0, 5, accuracy: 0.001)
        // Moved, sized and faded as one: one step for a drag.
        depth = model.undoDepth
        model.setCompound(compound.id) { $0.x = 0.6 }
        model.setCompound(compound.id) { $0.x = 0.7; $0.scale = 0.5 }
        model.endGesture()
        XCTAssertEqual(model.undoDepth, depth + 1)
        let moved = try XCTUnwrap(model.project.compound(compound.id))
        let canvas = model.project.canvasSize()
        let shownBefore = moved.apply(to: try XCTUnwrap(model.project.layerItem(a)), canvas: canvas)
        // Moving the block on the timeline moves both clips.
        model.moveLayerItem(a, to: 0.5, track: try XCTUnwrap(model.project.layerTrackIndex(of: a)))
        XCTAssertEqual(model.project.layerItem(b)?.at ?? 0, 1.5, accuracy: 0.001)
        // Break apart: one step, the clips look as they did.
        model.selection = .layer(a)
        depth = model.undoDepth
        XCTAssertTrue(model.perform(.breakApart))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertNil(model.project.compounds)
        let apart = try XCTUnwrap(model.project.layerItem(a))
        XCTAssertNil(apart.group)
        XCTAssertEqual(apart.x, shownBefore.x, accuracy: 0.0001)
        XCTAssertEqual(apart.width, shownBefore.width, accuracy: 0.0001)
        model.undo()
        XCTAssertNotNil(model.project.compounds)
        // Its clips deleted: the compound goes too.
        var project = model.project
        for t in project.layerTracks.indices { project.layerTracks[t].items.removeAll() }
        project.dropEmptyLayerTracks()
        XCTAssertNil(project.compounds)
    }

    func testInTheExport() async throws {
        let source = directory.appendingPathComponent("black.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.black, 2)])
        var project = VideoInspection.project(for: source, seconds: 2, size: CGSize(width: 320, height: 180))
        let picture = directory.appendingPathComponent("red.png")
        try VideoInspection.writePNG(to: picture, size: CGSize(width: 40, height: 40), color: .red)
        var item = VideoLayerItem(kind: .image, path: picture.path, name: "red.png", at: 0, length: 2, aspect: 1)
        item.width = 0.15
        var compound = VideoCompoundClip(name: "c")
        compound.x = 0.8
        item.group = compound.id
        project.layerTracks = [VideoLayerTrack(items: [item])]
        project.compounds = [compound]
        let output = directory.appendingPathComponent("compound.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let frame = try VideoInspection.frame(of: output, at: 1)
        XCTAssertGreaterThan(VideoInspection.color(of: frame, x: 0.8, y: 0.5).r, 0.7, "moved right with the compound")
        XCTAssertLessThan(VideoInspection.color(of: frame, x: 0.5, y: 0.5).r, 0.2, "not where it was made")
        // Without compounds, nothing new is written.
        project.compounds = nil
        let json = String(decoding: try JSONEncoder().encode(project), as: UTF8.self)
        XCTAssertFalse(json.contains("\"compounds\""))
    }
}
