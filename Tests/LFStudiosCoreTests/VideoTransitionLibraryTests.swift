import AppKit
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Library ▸ Transitions (1.15.0): each new transition starts on the clip
/// before the cut and ends on the one after, the export, placing them and
/// Apply to all (one step each), and the project format.
@MainActor
final class VideoTransitionLibraryTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-transitions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private let rect = CGRect(x: 0, y: 0, width: 160, height: 90)

    private func average(_ image: CIImage) -> (r: Double, g: Double, b: Double) {
        VideoInspection.color(of: image, size: rect.size, x: 0.5, y: 0.5)
    }

    func testEachStartsOnOneClipAndEndsOnTheOther() {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: rect)
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: rect)
        for kind in VideoTransitionKind.allCases where kind.usesBothSides {
            let start = VideoTransitionRenderer.blend(kind, from: red, to: blue, progress: 0, rect: rect)
            let end = VideoTransitionRenderer.blend(kind, from: red, to: blue, progress: 1, rect: rect)
            XCTAssertGreaterThan(average(start).r, 0.85, "\(kind) starts on the clip before")
            XCTAssertGreaterThan(average(end).b, 0.85, "\(kind) ends on the clip after")
            XCTAssertEqual(start.extent, rect, "\(kind) keeps the frame")
            XCTAssertNotNil(VideoTransitionPreview.render(kind, progress: 0.5))
        }
        // Slide halfway: the next clip covers the right half.
        let half = VideoTransitionRenderer.blend(.slide, from: red, to: blue, progress: 0.5, rect: rect)
        XCTAssertGreaterThan(VideoInspection.color(of: half, size: rect.size, x: 0.25, y: 0.5).r, 0.85)
        XCTAssertGreaterThan(VideoInspection.color(of: half, size: rect.size, x: 0.75, y: 0.5).b, 0.85)
    }

    func testNewKindsNeedTheNewFormatOldOnesDont() throws {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 10, sourceSize: CGSize(width: 640, height: 360))
        project.transitions.betweenClips = .dissolve
        XCTAssertFalse(project.needsFormat4)
        project.transitions.betweenClips = .push
        XCTAssertTrue(project.needsFormat4)
        // 1.14.0's files read as they were.
        let old = try JSONDecoder().decode(VideoTransitionSettings.self, from: Data(#"{"betweenClips":"fadeThroughBlack","duration":0.8}"#.utf8))
        XCTAssertEqual(old.betweenClips, .fadeThroughBlack)
    }

    func testASlideInTheExport() async throws {
        let source = directory.appendingPathComponent("two.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.red, 2), (.blue, 2)])
        var project = VideoInspection.project(for: source, seconds: 4, size: CGSize(width: 320, height: 180))
        project.timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 2), VideoDemoTimelineClip(sourceStart: 2, sourceEnd: 4)]
        project.transitions.betweenClips = .slide
        project.transitions.duration = 1
        let output = directory.appendingPathComponent("slide.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let frame = try VideoInspection.frame(of: output, at: 2.0)
        let left = VideoInspection.color(of: frame, x: 0.15, y: 0.5)
        let right = VideoInspection.color(of: frame, x: 0.85, y: 0.5)
        XCTAssertGreaterThan(left.r, 0.6, "the clip before still shows on the left \(left)")
        XCTAssertGreaterThan(right.b, 0.6, "the next one has slid in on the right \(right)")
    }

    func testPlacingAndApplyToAll() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 6)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        // No cut yet: nothing to put it on.
        XCTAssertFalse(model.perform(.clip(.setTransition(.wipe, 0.5))))
        model.seek(to: 2)
        model.perform(.split)
        model.seek(to: 4)
        model.perform(.split)
        XCTAssertEqual(model.segments.count, 3)
        // Dropped near the second cut: on that cut, one step.
        var depth = model.undoDepth
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "transition", id: "spin"), at: 3.8))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.project.transitions.transition(into: model.segments[2].id).kind, .spin)
        XCTAssertEqual(model.project.transitions.transition(into: model.segments[1].id).kind, .none)
        // + with the first clip selected: its cut out.
        model.selection = .clip(model.segments[0].id)
        XCTAssertTrue(model.perform(.clip(.setTransition(.zoom, 0.8))))
        let into = model.project.transitions.transition(into: model.segments[1].id)
        XCTAssertEqual(into.kind, .zoom)
        XCTAssertEqual(into.duration, 0.8, accuracy: 0.001)
        // Apply to all: one step, the per-cut ones go.
        depth = model.undoDepth
        XCTAssertTrue(model.perform(.clip(.transitionEverywhere(.blur, 0.6))))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertTrue(model.project.transitions.overrides.isEmpty)
        XCTAssertEqual(model.project.transitions.betweenClips, .blur)
        XCTAssertEqual(model.plan.transitions.count, 2)
        // Locked: refused.
        model.toggleTrackLocked(.clips)
        XCTAssertFalse(model.perform(.clip(.transitionEverywhere(.push, 0.5))))
        XCTAssertEqual(model.project.transitions.betweenClips, .blur)
    }
}
