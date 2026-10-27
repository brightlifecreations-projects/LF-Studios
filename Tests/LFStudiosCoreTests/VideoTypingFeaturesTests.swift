import XCTest
@testable import LFStudiosCore

/// Typing zooms and Speed up typing: nothing happens until a button is
/// pressed, each press is one ⌘Z step, and old projects stay as they were.
final class VideoTypingFeaturesTests: XCTestCase {
    private func project(duration: Double = 20) -> VideoDemoProject {
        VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/typing.mp4"), duration: duration, sourceSize: CGSize(width: 1600, height: 1000))
    }

    /// A text cursor moving right along a line, one step every 0.15 s.
    private func typing(from start: Double, to end: Double, x: Double = 0.2, y: Double = 0.7) -> [VideoTextCursorSample] {
        stride(from: start, through: end, by: 0.15).enumerated().map { index, time in
            VideoTextCursorSample(time: time, x: x + Double(index) * 0.004, y: y, width: 0.002, height: 0.02)
        }
    }

    // MARK: Off by default, old projects unchanged

    func testNothingIsOnForANewRecording() {
        let fresh = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/a.mp4"))
        XCTAssertTrue(fresh.zoomRegions.isEmpty)
        XCTAssertNil(fresh.loupeStyle)
        XCTAssertEqual(fresh.cursor.style, .classic)
        XCTAssertNil(fresh.cursor.customImage)
        XCTAssertFalse(fresh.timelineClips.contains(where: \.typingSpeedUp))

        // Typing data alone changes nothing: no zooms, no speed-ups.
        var recorded = project()
        recorded.textCursor = typing(from: 2, to: 6)
        recorded.keyPresses = Array(stride(from: 2.0, through: 6.0, by: 0.2))
        XCTAssertTrue(recorded.zoomRegions.isEmpty)
        XCTAssertEqual(recorded.timelineDuration(totalDuration: 20), 20, accuracy: 0.0001)
        XCTAssertTrue(VideoDemoExporter.makePlan(project: recorded, sourceDuration: 20, recording: nil).camera.isStatic)
    }

    func testOldProjectsOpenAndSaveAsBefore() throws {
        var old = project()
        old.zoomRegions = [VideoZoomRegion(start: 1, end: 4, scale: 2, followsCursor: false, focusX: 0.3, focusY: 0.4)]
        let data = try JSONEncoder().encode(old)
        let json = String(data: data, encoding: .utf8)!
        for key in ["followsTyping", "isTyping", "loupe", "offsetX", "offsetY", "cameraCorner", "textCursor", "keyPresses", "typingSpeedUp", "\"style\"", "customImage"] {
            XCTAssertFalse(json.contains(key), "\(key) is only saved once used")
        }
        // A project saved before these existed: the same zooms, cursor, and clips.
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: data)
        XCTAssertEqual(decoded.zoomRegions, old.zoomRegions)
        XCTAssertEqual(decoded.cursor, old.cursor)
        XCTAssertEqual(decoded.timelineClips, old.timelineClips)
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        XCTAssertEqual(try sorted.encode(decoded), try sorted.encode(old), "saved again, byte for byte the same")
    }

    // MARK: Typing zooms

    func testTypingTrackHoldsTheLastPosition() throws {
        let track = try XCTUnwrap(VideoTypingTrack(samples: typing(from: 2, to: 3)))
        XCTAssertNil(track.position(at: 0.5))
        XCTAssertEqual(try XCTUnwrap(track.position(at: 1.5)).x, 0.201, accuracy: 0.0001, "just before: the first position")
        XCTAssertEqual(try XCTUnwrap(track.position(at: 2.16)).x, 0.205, accuracy: 0.0001)
        XCTAssertNotNil(track.position(at: 6))
        XCTAssertNil(track.position(at: 3 + VideoTypingTrack.hold + 0.5), "long after: no longer typing")
    }

    func testTypingStretchesFromTheTextCursor() {
        var samples = typing(from: 2, to: 5)
        samples += typing(from: 9, to: 11, x: 0.6, y: 0.2)
        // A lone jump (a click into another field) isn't typing.
        samples.append(VideoTextCursorSample(time: 14, x: 0.9, y: 0.9, width: 0.002, height: 0.02))
        let stretches = VideoTypingDetector.stretches(textCursor: samples)
        XCTAssertEqual(stretches.count, 2)
        XCTAssertEqual(stretches[0].start, 2, accuracy: 0.001)
        XCTAssertEqual(stretches[1].start, 9, accuracy: 0.001)
    }

    func testAddTypingZoomsFollowsTheTextCursor() throws {
        var project = project()
        project.textCursor = typing(from: 4, to: 8, x: 0.15, y: 0.8)
        // Zooms placed by hand stay.
        let own = VideoZoomRegion(start: 14, end: 17, followsCursor: false)
        project.zoomRegions = [own]
        XCTAssertEqual(project.addTypingZooms(totalDuration: 20), 1)
        let zoom = try XCTUnwrap(project.zoomRegions.first { $0.isTyping })
        XCTAssertTrue(zoom.followsTyping)
        XCTAssertFalse(zoom.followsCursor)
        XCTAssertLessThan(zoom.start, 4)
        XCTAssertGreaterThan(zoom.end, 8)
        XCTAssertTrue(project.zoomRegions.contains(own))

        // The camera is on the text cursor while it types.
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 20, recording: nil)
        let early = plan.camera.state(at: 5)
        let late = plan.camera.state(at: 7.8)
        XCTAssertGreaterThan(early.scale, 1.8)
        let caretEarly = plan.canvasPoint(forVideoPoint: try XCTUnwrap(plan.typingTrack?.position(at: 5)))
        let window = early.window(in: plan.canvasSize)
        XCTAssertTrue(window.contains(caretEarly), "text cursor \(caretEarly) inside the zoomed view \(window)")
        XCTAssertGreaterThan(late.centerX, early.centerX - 0.0001, "the camera moves with the typing (left to right)")

        // Pressing again replaces only its own zooms.
        XCTAssertEqual(project.addTypingZooms(totalDuration: 20), 1)
        XCTAssertEqual(project.zoomRegions.filter(\.isTyping).count, 1)
        XCTAssertEqual(project.zoomRegions.count, 2)
    }

    func testTypingZoomsUseKeyTimingWhenThereIsSome() {
        var project = project()
        project.textCursor = typing(from: 4, to: 12)
        // Two bursts of keys: typing, a pause, typing.
        project.keyPresses = Array(stride(from: 4.0, through: 6.0, by: 0.2)) + Array(stride(from: 10.0, through: 12.0, by: 0.2))
        project.addTypingZooms(totalDuration: 20)
        XCTAssertEqual(project.zoomRegions.count, 2)
    }

    @MainActor
    func testAddTypingZoomsIsOneUndoStepAndEditable() async throws {
        VideoTestStorage.isolate()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-typing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: 6, fps: 30)
        defer {
            VideoDemoDraftStore.delete(for: url)
            try? FileManager.default.removeItem(at: folder)
        }
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertFalse(model.hasTypingPositions)
        model.addTypingZooms()
        XCTAssertTrue(model.project.zoomRegions.isEmpty, "without positions there's nothing to follow")

        model.mutate { $0.textCursor = self.typing(from: 1.5, to: 4) }
        model.addTypingZooms()
        XCTAssertEqual(model.project.zoomRegions.count, 1)
        XCTAssertEqual(model.undoLabel, "Add Typing Zooms")
        let id = try XCTUnwrap(model.project.zoomRegions.first?.id)
        model.setZoomFollow(id, .pointer)
        XCTAssertFalse(model.project.zoomRegions[0].followsTyping)
        XCTAssertFalse(model.project.zoomRegions[0].isTyping, "an edited zoom is the user's: pressing again keeps it")
        model.undo()
        model.undo()
        XCTAssertTrue(model.project.zoomRegions.isEmpty)
        XCTAssertFalse(model.project.textCursor.isEmpty)
    }

    // MARK: Speed up typing

    func testSpeedBlocksFromKeyTiming() throws {
        var project = project()
        project.keyPresses = Array(stride(from: 5.0, through: 9.0, by: 0.2))
        let stretches = VideoTypingDetector.stretches(keyPresses: project.keyPresses)
        XCTAssertEqual(stretches.count, 1)
        let stretch = stretches[0]
        XCTAssertEqual(stretch.start, 5, accuracy: 0.001)
        XCTAssertEqual(stretch.end, 9.12, accuracy: 0.001)

        let result = project.speedUpTyping(stretches, speed: 4, totalDuration: 20)
        XCTAssertEqual(result.stretches, 1)
        let expected = stretch.duration * (1 - 1.0 / 4)
        XCTAssertEqual(result.saved, expected, accuracy: 0.001)
        XCTAssertEqual(project.timelineDuration(totalDuration: 20), 20 - expected, accuracy: 0.001)
        let fast = project.timelineClips.filter(\.typingSpeedUp)
        XCTAssertEqual(fast.count, 1)
        XCTAssertEqual(fast[0].speed, 4)
        XCTAssertEqual(fast[0].sourceStart, 5, accuracy: 0.001)
        XCTAssertEqual(fast[0].sourceEnd, 9.12, accuracy: 0.001)
        XCTAssertTrue(project.timelineClips.filter { !$0.typingSpeedUp }.allSatisfy { $0.speed == 1 })

        // Again at another speed: the same blocks change speed.
        let again = project.speedUpTyping(stretches, speed: 2, totalDuration: 20)
        XCTAssertEqual(again.stretches, 0)
        XCTAssertEqual(project.timelineClips.filter(\.typingSpeedUp).map(\.speed), [2])
        XCTAssertEqual(project.timelineDuration(totalDuration: 20), 20 - stretch.duration / 2, accuracy: 0.001)

        // Saved and opened, the blocks are still speed blocks.
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded.timelineClips, project.timelineClips)
    }

    func testSpeedUpLeavesClipsTheUserSped() {
        var project = project()
        project.keyPresses = Array(stride(from: 5.0, through: 9.0, by: 0.2))
        _ = project.splitClip(atSourceTime: 4, totalDuration: 20)
        _ = project.splitClip(atSourceTime: 10, totalDuration: 20)
        let middle = project.timelineClips[1].id
        _ = project.updateClip(id: middle, totalDuration: 20) { $0.speed = 0.5 }
        let result = project.speedUpTyping(VideoTypingDetector.stretches(keyPresses: project.keyPresses), speed: 4, totalDuration: 20)
        XCTAssertEqual(result.stretches, 0)
        XCTAssertEqual(project.timelineClips.first { $0.id == middle }?.speed, 0.5)
    }

    func testKeycapsStayReadableInsideSpedUpTyping() {
        var project = project()
        project.keyPresses = Array(stride(from: 5.0, through: 9.0, by: 0.2))
        project.keystrokes = [VideoKeystrokeEvent(time: 7, keys: ["⌘", "S"])]
        project.speedUpTyping(VideoTypingDetector.stretches(keyPresses: project.keyPresses), speed: 8, totalDuration: 20)
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 20, recording: nil)
        let keys = plan.keystrokes[0]
        XCTAssertEqual(keys.end - keys.start, VideoRenderPlan.keystrokeHold, accuracy: 0.001, "on screen as long as at normal speed")
    }

    func testOlderRecordingsGetAnEstimate() {
        let still = [VideoDemoCursorSample(time: 0, x: 0.4, y: 0.4), VideoDemoCursorSample(time: 20, x: 0.4, y: 0.4)]
        // The screen changes five times a second from 12 to 15 s.
        let activity = Array(stride(from: 12.0, through: 15.0, by: 0.2))
        let found = VideoTypingDetector.estimatedStretches(screenActivity: activity, cursorSamples: still, clicks: [])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].start, 12, accuracy: 0.001)

        // A moving pointer, or clicks, is something else.
        let moving = stride(from: 0.0, through: 20, by: 0.1).map { VideoDemoCursorSample(time: $0, x: $0 / 20, y: 0.4) }
        XCTAssertTrue(VideoTypingDetector.estimatedStretches(screenActivity: activity, cursorSamples: moving, clicks: []).isEmpty)
        let click = VideoDemoClickEvent(time: 13, x: 0.4, y: 0.4, button: .left)
        XCTAssertTrue(VideoTypingDetector.estimatedStretches(screenActivity: activity, cursorSamples: still, clicks: [click]).isEmpty)

        // A short burst counts over a text field (the I-beam), not elsewhere.
        let short = Array(stride(from: 12.0, through: 13.4, by: 0.2))
        XCTAssertTrue(VideoTypingDetector.estimatedStretches(screenActivity: short, cursorSamples: still, clicks: []).isEmpty)
        XCTAssertEqual(VideoTypingDetector.estimatedStretches(screenActivity: short, cursorSamples: still, clicks: [], isTextPointer: { _ in true }).count, 1)

        // Which data is used, and that it's an estimate.
        var project = project()
        project.cursorSamples = still
        XCTAssertEqual(VideoTypingDetector.stretches(project: project, screenActivity: activity)?.basis, .estimate)
        project.keyPresses = [1, 1.2, 1.4, 1.6, 1.8, 2.0]
        XCTAssertEqual(VideoTypingDetector.stretches(project: project, screenActivity: activity)?.basis, .keyTiming)
        XCTAssertNil(VideoTypingDetector.stretches(project: self.project(), screenActivity: nil))
    }

    @MainActor
    func testSpeedUpTypingIsOneUndoStep() async throws {
        VideoTestStorage.isolate()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-typing-speed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: 8, fps: 30)
        defer {
            VideoDemoDraftStore.delete(for: url)
            try? FileManager.default.removeItem(at: folder)
        }
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let before = model.timelineDuration
        model.mutate { $0.keyPresses = Array(stride(from: 2.0, through: 5.0, by: 0.15)) }
        model.speedUpTyping(3)
        XCTAssertEqual(model.undoLabel, "Speed Up Typing")
        XCTAssertLessThan(model.timelineDuration, before - 1.5)
        model.undo()
        XCTAssertEqual(model.timelineDuration, before, accuracy: 0.001)
        XCTAssertFalse(model.project.timelineClips.contains(where: \.typingSpeedUp))
    }
}
