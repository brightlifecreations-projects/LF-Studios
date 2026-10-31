import AppKit
import AVFoundation
import XCTest
@testable import LFStudiosCore

/// Keyframes (1.15.0): easing, the value between keys, editing at the
/// playhead, keys through trims and splits, in the export's pixels and
/// sound, and the project format.
@MainActor
final class VideoKeyframesTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-keys-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testEasingAndValuesBetweenKeys() {
        XCTAssertEqual(VideoEasing.linear.apply(0.25), 0.25, accuracy: 0.0001)
        XCTAssertLessThan(VideoEasing.easeIn.apply(0.25), 0.25, "starts slow")
        XCTAssertGreaterThan(VideoEasing.easeOut.apply(0.25), 0.25, "starts fast")
        XCTAssertEqual(VideoEasing.easeInOut.apply(0.5), 0.5, accuracy: 0.0001)
        for easing in VideoEasing.allCases {
            XCTAssertEqual(easing.apply(0), 0, accuracy: 0.0001)
            XCTAssertEqual(easing.apply(1), 1, accuracy: 0.0001)
        }
        var keys = VideoKeyframes()
        XCTAssertEqual(keys.value(.opacity, at: 1, base: 0.7), 0.7, "no keys: the base")
        keys.set(.opacity, at: 1, value: 0)
        keys.set(.opacity, at: 3, value: 1)
        XCTAssertEqual(keys.value(.opacity, at: 0, base: 0.7), 0, "held before the first")
        XCTAssertEqual(keys.value(.opacity, at: 2, base: 0.7), 0.5, accuracy: 0.0001)
        XCTAssertEqual(keys.value(.opacity, at: 9, base: 0.7), 1, "held after the last")
        keys.setEasing(.easeIn, at: 1)
        XCTAssertLessThan(keys.value(.opacity, at: 2, base: 0.7), 0.5, "eased from the key at 1 s")
        keys.set(.opacity, at: 1.001, value: 0.2)
        XCTAssertEqual(keys.keys(.opacity).count, 2, "within a frame: replaced")
        keys.remove(.opacity, at: 3)
        XCTAssertEqual(keys.keys(.opacity).count, 1)
        XCTAssertEqual(keys.times, [1])
    }

    private func makeModel() async throws -> (VideoEditorModel, UUID) {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let png = directory.appendingPathComponent("logo.png")
        try VideoInspection.writePNG(to: png, size: CGSize(width: 100, height: 100), color: .red)
        let added = await model.addLayerItem(from: png, at: 0)
        return (model, try XCTUnwrap(added))
    }

    func testEditingAtThePlayheadKeysOnlyAnimatedProperties() async throws {
        let (model, id) = try await makeModel()
        // Not animated: a change is for the whole clip.
        model.seek(to: 1)
        model.setLayerAnimated(id) { $0.opacity = 0.5 }
        XCTAssertEqual(model.project.layerItem(id)?.opacity, 0.5)
        XCTAssertNil(model.project.layerItem(id)?.keys)
        // The diamond: a key with the value shown, one ⌘Z step.
        let depth = model.undoDepth
        model.toggleKeyframe(id, .opacity)
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.project.layerItem(id)?.keys?.keys(.opacity).first?.value, 0.5)
        // Elsewhere, a change is a new key; the base stays.
        model.seek(to: 3)
        model.setLayerAnimated(id) { $0.opacity = 1 }
        let item = try XCTUnwrap(model.project.layerItem(id))
        XCTAssertEqual(item.keys?.keys(.opacity).map(\.time), [1, 3])
        XCTAssertEqual(item.opacity, 0.5, "the base")
        XCTAssertEqual(item.value(.opacity, at: 2), 0.75, accuracy: 0.0001)
        // Position keys x and y together.
        model.toggleKeyframe(id, .x)
        XCTAssertTrue(model.project.layerItem(id)?.keys?.hasKey(.y, at: 3) == true)
        // ⌥K keys position, size, rotation and opacity; ◀ ▶ jump between keys.
        model.seek(to: 2)
        model.selection = .layer(id)
        XCTAssertTrue(model.perform(.addKeyframe))
        XCTAssertTrue(model.project.layerItem(id)?.keys?.hasKey(.width, at: 2) == true)
        XCTAssertTrue(model.perform(.nextKeyframe))
        XCTAssertEqual(model.clock.time, 3, accuracy: 0.001)
        XCTAssertTrue(model.perform(.previousKeyframe))
        XCTAssertEqual(model.clock.time, 2, accuracy: 0.001)
        // The diamond again: the key goes.
        model.seek(to: 3)
        model.toggleKeyframe(id, .opacity)
        XCTAssertFalse(model.project.layerItem(id)?.keys?.hasKey(.opacity, at: 3) == true)
    }

    func testKeysFollowTrimsAndSplits() async throws {
        let (model, id) = try await makeModel()
        model.seek(to: 1); model.toggleKeyframe(id, .opacity)
        // Animated: a change at 3 s makes a key there.
        model.seek(to: 3); model.setLayerAnimated(id) { $0.opacity = 0.2 }
        XCTAssertEqual(model.project.layerItem(id)?.keys?.keys(.opacity).map(\.time), [1, 3])
        // Trimming the start by half a second keeps keys on their moments.
        model.trimLayerItem(id, leading: true, to: 0.5, coalesce: false)
        XCTAssertEqual(model.project.layerItem(id)?.keys?.keys(.opacity).map(\.time) ?? [], [0.5, 2.5], accuracy: 0.001)
        // Splitting at 2 s: each half keeps its own.
        let second = try XCTUnwrap(model.splitLayerItem(id, at: 2))
        XCTAssertEqual(model.project.layerItem(id)?.keys?.keys(.opacity).map(\.time) ?? [], [0.5], accuracy: 0.001)
        XCTAssertEqual(model.project.layerItem(second)?.keys?.keys(.opacity).map(\.time) ?? [], [1], accuracy: 0.001)
    }

    func testKeyedOpacityAndVolumeInTheExport() async throws {
        let source = directory.appendingPathComponent("white.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        var project = VideoInspection.project(for: source, seconds: 4, size: CGSize(width: 320, height: 180))
        project.padding = 0
        // A red video over all of it, fading in from 0 to 1 over 0.5 → 3.5 s,
        // its tone getting louder the same way.
        let red = directory.appendingPathComponent("red.mov")
        try await VideoInspection.writeColorVideo(to: red, size: CGSize(width: 320, height: 180), colors: [(.red, 4)], toneSeconds: 4, toneFrequency: 880)
        var item = VideoLayerItem(kind: .video, path: red.path, name: "red.mov", at: 0, length: 4, fileDuration: 4, aspect: 16.0 / 9)
        item.width = 1
        var keys = VideoKeyframes()
        keys.set(.opacity, at: 0.5, value: 0)
        keys.set(.opacity, at: 3.5, value: 1)
        keys.set(.volume, at: 0.5, value: 0)
        keys.set(.volume, at: 3.5, value: 1)
        item.keys = keys
        project.layerTracks = [VideoLayerTrack(items: [item])]
        XCTAssertTrue(project.needsFormat4)
        let output = directory.appendingPathComponent("keys.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let early = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 0.3), x: 0.5, y: 0.5)
        let middle = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 2), x: 0.5, y: 0.5)
        let late = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 3.8), x: 0.5, y: 0.5)
        XCTAssertGreaterThan(early.g, 0.85, "faded out: white shows \(early)")
        XCTAssertGreaterThan(middle.g, 0.3, "half way: pink \(middle)")
        XCTAssertLessThan(middle.g, 0.75, "\(middle)")
        XCTAssertLessThan(late.g, 0.2, "faded in: red \(late)")
        let samples = try VideoInspection.audio(of: output)
        let quiet = VideoInspection.toneLevel(samples, frequency: 880, from: 0.1, to: 0.4)
        let loud = VideoInspection.toneLevel(samples, frequency: 880, from: 3.6, to: 3.9)
        XCTAssertGreaterThan(loud, quiet * 4 + 0.001, "volume keys: louder at the end")
    }

    func testKeyframesAreFormat4AndOthersStayAsTheyWere() throws {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 4, sourceSize: CGSize(width: 640, height: 360))
        var item = VideoLayerItem(kind: .image, path: "/tmp/a.png", name: "a.png", at: 0, length: 2, aspect: 1)
        project.layerTracks = [VideoLayerTrack(items: [item])]
        XCTAssertFalse(project.needsFormat4, "a 1.14 track stays format 3")
        let three = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        for key in ["keys", "mask", "level"] { XCTAssertFalse(three.contains("\"\(key)\""), key) }
        XCTAssertEqual(VideoProjectDocument(mediaMode: .linked, project: project, recording: nil).format, VideoProjectDocument.layersFormat)
        item.keys = VideoKeyframes()
        item.keys?.set(.x, at: 0, value: 0.2)
        project.layerTracks = [VideoLayerTrack(items: [item])]
        let document = VideoProjectDocument(mediaMode: .linked, project: project, recording: nil)
        XCTAssertEqual(document.format, "lfstudios-project-4")
        XCTAssertEqual(document.version, 4)
        let read = try VideoProjectDocument.decode(try document.encoded())
        XCTAssertEqual(read.project.layerTracks.first?.items.first?.keys, item.keys)
        // 1.14.0 read format 4 as "needs a newer version" (any later name does).
        let later = try JSONSerialization.data(withJSONObject: ["format": "lfstudios-project-5", "version": 5])
        XCTAssertThrowsError(try VideoProjectDocument.decode(later)) { XCTAssertEqual($0 as? VideoProjectDocument.ReadError, .needsNewerVersion) }
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, "\(a) vs \(b)", file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
