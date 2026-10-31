import AppKit
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Library ▸ Filters (1.15.0): our looks as LUTs, .cube files, filter
/// clips in the export, filters on a clip, one undo step each.
@MainActor
final class VideoFiltersTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-filters-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private let rect = CGRect(x: 0, y: 0, width: 64, height: 64)

    private func colour(_ image: CIImage) -> (r: Double, g: Double, b: Double) {
        VideoInspection.color(of: image, size: rect.size, x: 0.5, y: 0.5)
    }

    func testLooksChangeColourAndStrengthMixes() {
        let orange = CIImage(color: CIColor(red: 0.9, green: 0.5, blue: 0.2)).cropped(to: rect)
        for look in VideoFilterLook.allCases {
            let out = colour(VideoFilterRenderer.apply(VideoAppliedFilter(look: look, intensity: 1), to: orange))
            let moved = abs(out.r - 0.9) + abs(out.g - 0.5) + abs(out.b - 0.2)
            XCTAssertGreaterThan(moved, 0.03, "\(look) changes the colour \(out)")
        }
        let mono = colour(VideoFilterRenderer.apply(VideoAppliedFilter(look: .mono, intensity: 1), to: orange))
        XCTAssertEqual(mono.r, mono.b, accuracy: 0.03, "Mono is grey")
        let none = colour(VideoFilterRenderer.apply(VideoAppliedFilter(look: .mono, intensity: 0), to: orange))
        XCTAssertEqual(none.r, 0.9, accuracy: 0.03, "strength 0 leaves it")
        let half = colour(VideoFilterRenderer.apply(VideoAppliedFilter(look: .mono, intensity: 0.5), to: orange))
        XCTAssertLessThan(half.r, 0.9 - 0.05)
        XCTAssertGreaterThan(half.r, mono.r + 0.05)
    }

    func testCubeFiles() throws {
        // A 2³ identity LUT, red fastest.
        var lines = ["TITLE \"identity\"", "# a comment", "LUT_3D_SIZE 2"]
        for b in 0..<2 { for g in 0..<2 { for r in 0..<2 { lines.append("\(r).0 \(g).0 \(b).0") } } }
        let identity = try XCTUnwrap(VideoColorCube.parse(lines.joined(separator: "\n")))
        XCTAssertEqual(identity.size, 2)
        let orange = CIImage(color: CIColor(red: 0.9, green: 0.5, blue: 0.2)).cropped(to: rect)
        let kept = colour(identity.apply(to: orange))
        XCTAssertEqual(kept.r, 0.9, accuracy: 0.03)
        XCTAssertEqual(kept.b, 0.2, accuracy: 0.03)
        // Inverting: every colour flipped.
        var invert = ["LUT_3D_SIZE 2"]
        for b in 0..<2 { for g in 0..<2 { for r in 0..<2 { invert.append("\(1 - r) \(1 - g) \(1 - b)") } } }
        let flipped = colour(try XCTUnwrap(VideoColorCube.parse(invert.joined(separator: "\n"))).apply(to: orange))
        XCTAssertEqual(flipped.r, 0.1, accuracy: 0.05)
        // Not LUTs.
        XCTAssertNil(VideoColorCube.parse("LUT_1D_SIZE 4\n0 0 0"))
        XCTAssertNil(VideoColorCube.parse("LUT_3D_SIZE 2\n0 0 0\n1 1 1"), "too few lines")
        XCTAssertNil(VideoColorCube.parse("hello"))
    }

    func testAFilterClipInTheExport() async throws {
        let source = directory.appendingPathComponent("red.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.red, 4)])
        var project = VideoInspection.project(for: source, seconds: 4, size: CGSize(width: 320, height: 180))
        var clip = VideoLayerItem.adjustmentClip(at: 2, length: 2)
        clip.filter = VideoAppliedFilter(look: .mono, intensity: 1)
        project.layerTracks = [VideoLayerTrack(items: [clip])]
        XCTAssertTrue(project.needsFormat4)
        let output = directory.appendingPathComponent("mono.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let before = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 1), x: 0.5, y: 0.5)
        let during = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 3), x: 0.5, y: 0.5)
        XCTAssertGreaterThan(before.r - before.g, 0.5, "red before")
        XCTAssertLessThan(abs(during.r - during.g), 0.08, "grey while the filter clip plays \(during)")
    }

    func testPlacingFiltersAndImportingACube() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 6)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        // Dropped: a filter clip there, one step.
        var depth = model.undoDepth
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "filter", id: "film"), at: 1, target: .layer(.automatic)))
        XCTAssertEqual(model.undoDepth, depth + 1)
        let clip = try XCTUnwrap(model.selectedLayerItem)
        XCTAssertEqual(clip.role, .adjustment)
        XCTAssertEqual(clip.filter?.look, .film)
        // Its strength: one step for a drag.
        depth = model.undoDepth
        var next = try XCTUnwrap(clip.filter)
        for value in [0.5, 0.4, 0.3] {
            next.intensity = value
            model.perform(.edit(.setFilter(next)))
        }
        model.endGesture()
        XCTAssertEqual(model.undoDepth, depth + 1)
        // + with a text clip selected: on it.
        let text = model.addTextClip(VideoTextContent(string: "Hi"), at: 0)
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "filter", id: "sepia"), at: nil))
        XCTAssertEqual(model.project.layerItem(text)?.filter?.look, .sepia)
        // A .cube file: copied into the store, on the selected clip, kept by Clean Up.
        var lines = ["LUT_3D_SIZE 2"]
        for b in 0..<2 { for g in 0..<2 { for r in 0..<2 { lines.append("\(r) \(g) \(b)") } } }
        let cube = directory.appendingPathComponent("My Look.cube")
        try lines.joined(separator: "\n").write(to: cube, atomically: true, encoding: .utf8)
        XCTAssertTrue(model.importCubeLUT(cube, for: text))
        let filter = try XCTUnwrap(model.project.layerItem(text)?.filter)
        XCTAssertEqual(filter.cubeName, "My Look")
        let stored = try XCTUnwrap(filter.cubePath)
        XCTAssertTrue(VideoAssetStore.isStored(stored))
        XCTAssertTrue(model.project.assetPaths.contains(stored))
        // Not a LUT: refused, nothing changes.
        let bad = directory.appendingPathComponent("bad.cube")
        try "hello".write(to: bad, atomically: true, encoding: .utf8)
        let before = model.project.layerTracks
        XCTAssertFalse(model.importCubeLUT(bad, for: text))
        XCTAssertEqual(model.project.layerTracks, before)
    }
}
