import XCTest
@testable import LFStudiosCore

/// Zoom cut (1.16.0): a punch-in on the clip after a cut, made of zoom
/// keyframes on that clip; the command, undo, the lock, splits, the export
/// and the project format.
@MainActor
final class VideoZoomCutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-zoomcut-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testTheKeys() {
        let keys = VideoZoomCut.keys(scale: 1.2, length: 0.6, clipLength: 5)
        XCTAssertEqual(keys.value(.zoom, at: 0, base: 1), 1.2, accuracy: 0.000_1, "in at the cut")
        XCTAssertEqual(keys.value(.zoom, at: 0.3, base: 1), 1.1, accuracy: 0.000_1, "half way back (ease in and out)")
        XCTAssertEqual(keys.value(.zoom, at: 0.6, base: 1), 1, accuracy: 0.000_1, "back out")
        XCTAssertEqual(keys.value(.zoom, at: 3, base: 1), 1, accuracy: 0.000_1)
        // Kept in range, and inside a short clip.
        XCTAssertEqual(VideoZoomCut.keys(scale: 9, length: 0.6, clipLength: 5).keys(.zoom).first?.value, VideoZoomCut.scaleRange.upperBound)
        XCTAssertEqual(VideoZoomCut.keys(scale: 1.2, length: 2, clipLength: 0.5).keys(.zoom).last?.time ?? 0, 0.5, accuracy: 0.000_1)
    }

    func testTheNearestCut() {
        let clips = [
            VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 2),
            VideoDemoTimelineClip(sourceStart: 2, sourceEnd: 5),
            VideoDemoTimelineClip(sourceStart: 5, sourceEnd: 6),
        ]
        var start = 0.0
        let segments = clips.map { clip -> VideoDemoTimelineSegment in
            defer { start += clip.outputDuration }
            return VideoDemoTimelineSegment(clip: clip, timelineStart: start)
        }
        XCTAssertEqual(VideoZoomCut.clip(near: 0.2, in: segments)?.id, clips[1].id, "the first clip has no cut before it")
        XCTAssertEqual(VideoZoomCut.clip(near: 2.4, in: segments)?.id, clips[1].id)
        XCTAssertEqual(VideoZoomCut.clip(near: 4.2, in: segments)?.id, clips[2].id)
        XCTAssertNil(VideoZoomCut.clip(near: 1, in: Array(segments.prefix(1))), "no cut: nothing")
    }

    private func makeModel() async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        return model
    }

    func testTheCommandUndoAndTheLock() async throws {
        let model = try await makeModel()
        // No cut yet: refused, and nothing changes.
        XCTAssertFalse(model.perform(.zoomCut))
        XCTAssertFalse(model.project.timelineClips.contains { $0.hasZoom })

        model.seek(to: 2)
        XCTAssertTrue(model.perform(.split))
        model.seek(to: 1.8)
        let depth = model.undoDepth
        XCTAssertTrue(model.perform(.zoomCut))
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step")
        let second = try XCTUnwrap(model.segments.dropFirst().first)
        XCTAssertTrue(second.clip.hasZoom)
        XCTAssertFalse(try XCTUnwrap(model.segments.first).clip.hasZoom)
        XCTAssertEqual(model.selection, .clip(second.id))
        XCTAssertEqual(model.clock.time, second.timelineStart, accuracy: 0.01, "the playhead goes to the cut")
        XCTAssertTrue(model.project.needsFormat4)

        // The keys are ordinary: change the zoom at the playhead, remove it.
        model.seek(to: second.timelineStart + 0.3)
        XCTAssertTrue(model.perform(.zoom(.setZoom(1.5))))
        model.endGesture()
        XCTAssertEqual(model.segments[1].clip.zoom(at: 0.3), 1.5, accuracy: 0.000_1)
        XCTAssertTrue(model.perform(.zoom(.clear)))
        XCTAssertFalse(model.segments[1].clip.hasZoom)
        model.undo()
        model.undo()
        model.undo()
        XCTAssertFalse(model.segments[1].clip.hasZoom, "undone back to before the zoom cut")
        XCTAssertFalse(model.project.needsFormat4)

        // Locked: refused.
        model.toggleTrackLocked(.clips)
        let before = model.project.timelineClips
        XCTAssertFalse(model.perform(.zoomCut))
        XCTAssertEqual(model.project.timelineClips, before)
    }

    func testASplitKeepsTheZoomWhereItWas() {
        var project = VideoInspection.project(for: directory.appendingPathComponent("rec.mp4"), seconds: 6, size: CGSize(width: 320, height: 180))
        var clip = VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 4)
        clip.keys = VideoZoomCut.keys(scale: 1.8, length: 2, clipLength: 4)
        project.timelineClips = [clip]
        let before = clip.zoom(at: 1)
        XCTAssertNotNil(project.splitClip(atSourceTime: 1, totalDuration: 6))
        let first = project.timelineClips[0], second = project.timelineClips[1]
        XCTAssertEqual(first.zoom(at: 0), 1.8, accuracy: 0.000_1)
        XCTAssertEqual(first.zoom(at: 1), before, accuracy: 0.000_1, "no jump at the split")
        XCTAssertEqual(second.zoom(at: 0), before, accuracy: 0.000_1)
        XCTAssertEqual(second.zoom(at: 1), clip.zoom(at: 2), accuracy: 0.01, "the rest plays on as before")
        XCTAssertEqual(second.zoom(at: 2.5), 1, accuracy: 0.000_1)
    }

    func testTheExportPunchesIn() async throws {
        let source = directory.appendingPathComponent("red.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 640, height: 360), colors: [(.red, 4)])
        var project = VideoInspection.project(for: source, seconds: 4, size: CGSize(width: 640, height: 360))
        project.padding = 0.2
        project.background = .color(VideoRGBA(0, 1, 0))
        var cut = VideoDemoTimelineClip(sourceStart: 2, sourceEnd: 4)
        cut.keys = VideoZoomCut.keys(scale: 2, length: 1, clipLength: 2)
        project.timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 2), cut]
        let output = directory.appendingPathComponent("zoomcut.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())

        func corner(at time: Double) throws -> (r: Double, g: Double, b: Double) {
            let color = VideoInspection.color(of: try VideoInspection.frame(of: output, at: time), x: 0.04, y: 0.06, radius: 2)
            return (color.r, color.g, color.b)
        }
        let before = try corner(at: 1)
        XCTAssertGreaterThan(before.g, 0.6, "before the cut: the green background at the corner \(before)")
        let punched = try corner(at: 2.05)
        XCTAssertGreaterThan(punched.r, 0.6, "at the cut: zoomed in, the red video reaches the corner \(punched)")
        XCTAssertLessThan(punched.g, 0.35)
        let after = try corner(at: 3.5)
        XCTAssertGreaterThan(after.g, 0.6, "eased back out \(after)")
    }

    func testOldFilesStayTheSame() throws {
        let clip = VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 2)
        let json = String(decoding: try JSONEncoder().encode(clip), as: UTF8.self)
        XCTAssertFalse(json.contains("\"keys\""), "no zoom: no new key in the file")
        XCTAssertFalse(clip.needsFormat4)
        var zoomed = clip
        zoomed.keys = VideoZoomCut.keys(scale: 1.2, length: 0.6, clipLength: 2)
        let decoded = try JSONDecoder().decode(VideoDemoTimelineClip.self, from: try JSONEncoder().encode(zoomed))
        XCTAssertEqual(decoded, zoomed)
        XCTAssertTrue(decoded.needsFormat4)
    }
}
