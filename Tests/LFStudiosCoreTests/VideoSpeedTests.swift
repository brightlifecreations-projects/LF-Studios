import AppKit
import AVFoundation
import XCTest
@testable import LFStudiosCore

/// Speed (1.15.0): 0.1× to 100×, Keep pitch in the exported sound, speed
/// curves as pieces of one clip, and their commands.
@MainActor
final class VideoSpeedTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-speed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    /// 4 s of white with a 440 Hz tone.
    private func toneProject() async throws -> VideoDemoProject {
        let source = directory.appendingPathComponent("tone.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.white, 4)], toneSeconds: 4, toneFrequency: 440)
        return VideoInspection.project(for: source, seconds: 4, size: CGSize(width: 320, height: 180))
    }

    func testCurvesArePiecesOfOneClip() {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 10, sourceSize: CGSize(width: 640, height: 360))
        let id = project.timelineClips[0].id
        project.applySpeedCurve(to: id, VideoSpeedPreset.hero.curve, totalDuration: 10)
        let pieces = project.timelineClips
        XCTAssertEqual(pieces.count, VideoSpeedCurve.pieces(sourceSeconds: 10))
        XCTAssertEqual(Set(pieces.compactMap { $0.curve?.id }).count, 1, "one group")
        XCTAssertEqual(pieces.first?.id, id, "the first keeps the clip's id")
        XCTAssertEqual(pieces.first?.sourceStart ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(pieces.last?.sourceEnd ?? -1, 10, accuracy: 0.0001)
        let middle = pieces[pieces.count / 2].speed
        XCTAssertLessThan(middle, pieces[0].speed, "Hero slows down in the middle")
        XCTAssertTrue(project.needsFormat4)
        // No transitions inside the curve, even with one on every cut.
        project.transitions.betweenClips = .dissolve
        XCTAssertTrue(VideoTransitionTiming.spans(settings: project.transitions, segments: project.timelineSegments(totalDuration: 10)).isEmpty)
        // A steady speed again: one clip, the whole range.
        project.applySpeedCurve(to: pieces[3].id, nil, speed: 2, totalDuration: 10)
        XCTAssertEqual(project.timelineClips.count, 1)
        XCTAssertEqual(project.timelineClips[0].sourceEnd, 10, accuracy: 0.0001)
        XCTAssertEqual(project.timelineClips[0].speed, 2)
        XCTAssertNil(project.timelineClips[0].curve)
        // Every preset stays inside the speeds allowed.
        for preset in VideoSpeedPreset.allCases {
            for x in stride(from: 0.0, through: 1, by: 0.05) {
                XCTAssertTrue(VideoSpeedCurve.speedRange.contains((preset.curve.speed(at: x) * 1000).rounded() / 1000), "\(preset) at \(x)")
            }
        }
    }

    func testKeepPitchInTheExport() async throws {
        var project = try await toneProject()
        project.timelineClips[0].speed = 2
        let kept = directory.appendingPathComponent("kept.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: kept, settings: VideoInspection.mp4Settings())
        let keptSound = try VideoInspection.audio(of: kept)
        XCTAssertGreaterThan(VideoInspection.toneLevel(keptSound, frequency: 440, from: 0.3, to: 1.7), VideoInspection.toneLevel(keptSound, frequency: 880, from: 0.3, to: 1.7) * 3, "Keep pitch: still 440 Hz")
        project.timelineClips[0].keepsPitch = false
        XCTAssertTrue(project.needsFormat4)
        let raised = directory.appendingPathComponent("raised.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: raised, settings: VideoInspection.mp4Settings())
        let raisedSound = try VideoInspection.audio(of: raised)
        XCTAssertGreaterThan(VideoInspection.toneLevel(raisedSound, frequency: 880, from: 0.3, to: 1.7), VideoInspection.toneLevel(raisedSound, frequency: 440, from: 0.3, to: 1.7) * 3, "Keep pitch off: an octave up at 2×")
    }

    func testTheFastestAndSlowest() async throws {
        var project = try await toneProject()
        project.timelineClips[0].speed = 100
        let fast = directory.appendingPathComponent("fast.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: fast, settings: VideoInspection.mp4Settings())
        let length = try await AVURLAsset(url: fast).load(.duration).seconds
        XCTAssertEqual(length, 0.04, accuracy: 0.05, "4 s at 100×")
        project.timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 0.5, speed: 0.1)]
        let slow = directory.appendingPathComponent("slow.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: slow, settings: VideoInspection.mp4Settings())
        let slowLength = try await AVURLAsset(url: slow).load(.duration).seconds
        XCTAssertEqual(slowLength, 5, accuracy: 0.15, "half a second at 0.1×")
        XCTAssertEqual(VideoDemoTimelineClip.speedRange, 0.1...100)
    }

    func testCommandsAreOneStepEach() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 6)], toneSeconds: 6)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        model.seek(to: 1)
        for edit in [VideoClipEdit.setSpeed(3), .setKeepPitch(false), .setSpeedCurve(VideoSpeedPreset.montage.curve), .setSpeedCurve(nil)] {
            let depth = model.undoDepth
            let before = model.project.timelineClips
            XCTAssertTrue(model.perform(.clip(edit)), edit.name)
            model.endGesture()
            XCTAssertEqual(model.undoDepth, depth + 1, edit.name)
            XCTAssertNotEqual(model.project.timelineClips, before, edit.name)
        }
        XCTAssertEqual(model.project.timelineClips.count, 1, "the curve is gone again")
        // A custom curve drag is one step.
        model.perform(.clip(.setSpeedCurve(VideoSpeedPreset.flashIn.curve)))
        model.endGesture()
        let depth = model.undoDepth
        var custom = VideoSpeedPreset.flashIn.curve
        custom.preset = .custom
        custom.points[1].speed = 3
        model.perform(.clip(.setSpeedCurve(custom)))
        custom.points[1].speed = 4
        model.perform(.clip(.setSpeedCurve(custom)))
        model.endGesture()
        XCTAssertEqual(model.undoDepth, depth + 1)
        // Locked: refused.
        model.toggleTrackLocked(.clips)
        let locked = model.project.timelineClips
        XCTAssertFalse(model.perform(.clip(.setSpeed(2))))
        XCTAssertEqual(model.project.timelineClips, locked)
    }
}
