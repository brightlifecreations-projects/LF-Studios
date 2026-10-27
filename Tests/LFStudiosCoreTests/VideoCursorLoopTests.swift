import CoreImage
import XCTest
@testable import LFStudiosCore

/// Cursor ▸ Return to start at the end: off until switched on; on, the last
/// frame's pointer is the first frame's, reached by a smooth glide.
final class VideoCursorLoopTests: XCTestCase {
    private let duration = 6.0
    private let output = CGSize(width: 960, height: 600)

    private func project(loop: Bool, glide: Double = 0.8) -> (VideoDemoProject, VideoDemoRecordingMetadata) {
        let source = CGSize(width: 1440, height: 900)
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/loop.mp4"), duration: duration, sourceSize: source)
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: duration)
        let metadata = VideoDemoRecordingMetadata(videoURLPath: "/tmp/loop.mp4", createdAt: Date(), duration: duration, sourceWidth: source.width, sourceHeight: source.height, fps: 60, nativeCursorVisible: false, cursorSamples: samples, clickEvents: clicks, pointPixelScale: 2, renderCursor: true)
        project.apply(metadata: metadata)
        project.cursor.returnToStart = loop
        project.cursor.returnDuration = glide
        return (project, metadata)
    }

    private func frame(_ project: VideoDemoProject, _ metadata: VideoDemoRecordingMetadata, at time: Double) -> [UInt8] {
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: duration, recording: metadata)
        let source = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7)).cropped(to: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let image = VideoFrameRenderer().render(source: source, timelineTime: time, plan: plan, outputSize: output)
        let cg = VideoRenderContext.shared.createCGImage(image, from: CGRect(origin: .zero, size: output), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
        return TestImageBytes.rgba(cg)
    }

    private func difference(_ a: [UInt8], _ b: [UInt8]) -> Int {
        zip(a, b).reduce(0) { $0 + (abs(Int($1.0) - Int($1.1)) > 24 ? 1 : 0) }
    }

    func testOffByDefaultAndForOldProjects() throws {
        XCTAssertFalse(VideoCursorSettings().returnToStart)
        XCTAssertFalse(VideoCursorSettings.plain.returnToStart)
        XCTAssertFalse(VideoStylePreset.factory.cursor.returnToStart)
        let old = try JSONDecoder().decode(VideoCursorSettings.self, from: Data(#"{"visible":true,"size":1.6,"smoothing":"smooth"}"#.utf8))
        XCTAssertFalse(old.returnToStart)
        XCTAssertEqual(old.returnDuration, 0.8)
        let (project, metadata) = self.project(loop: false)
        XCTAssertNil(VideoDemoExporter.makePlan(project: project, sourceDuration: duration, recording: metadata).cursorLoop)
    }

    func testFirstAndLastFramesMatch() {
        let (looping, metadata) = project(loop: true)
        let plan = VideoDemoExporter.makePlan(project: looping, sourceDuration: duration, recording: metadata)
        XCTAssertNotNil(plan.cursorLoop)
        let first = frame(looping, metadata, at: 0)
        for fps in [24.0, 30, 60] {
            let last = frame(looping, metadata, at: plan.timelineDuration - 1 / fps)
            XCTAssertEqual(difference(first, last), 0, "last frame at \(Int(fps)) fps matches the first")
        }

        // Without it, the pointer ends somewhere else.
        let (plain, _) = project(loop: false)
        let lastPlain = frame(plain, metadata, at: plan.timelineDuration - 1 / 30)
        XCTAssertGreaterThan(difference(first, lastPlain), 50)
    }

    func testTheGlideIsSmoothAndTakesTheChosenTime() throws {
        let (looping, metadata) = project(loop: true, glide: 1.5)
        let plan = VideoDemoExporter.makePlan(project: looping, sourceDuration: duration, recording: metadata)
        let loop = try XCTUnwrap(plan.cursorLoop)
        let track = try XCTUnwrap(plan.cursorTrack)
        XCTAssertEqual(loop.end - loop.start, 1.5, accuracy: 0.001)
        XCTAssertEqual(loop.weight(at: loop.start - 0.1), 0)
        XCTAssertEqual(loop.weight(at: loop.end), 1)

        func position(_ time: Double) -> CGPoint {
            loop.position(track.position(at: plan.sourceTime(forTimelineTime: time)), at: time)
        }
        // Frame to frame at 60 fps the pointer never jumps, and it eases
        // in and out (slow at both ends of the glide).
        var previous = position(loop.start - 1 / 60)
        var largest = 0.0
        var lastWeight = 0.0
        for frame in 0...Int(1.5 * 60) {
            let time = loop.start + Double(frame) / 60
            let point = position(time)
            largest = max(largest, hypot(point.x - previous.x, point.y - previous.y))
            previous = point
            let weight = loop.weight(at: time)
            XCTAssertGreaterThanOrEqual(weight, lastWeight)
            lastWeight = weight
        }
        let total = hypot(loop.firstPosition.x - track.position(at: plan.sourceTime(forTimelineTime: loop.start)).x, loop.firstPosition.y - track.position(at: plan.sourceTime(forTimelineTime: loop.start)).y)
        XCTAssertLessThan(largest, max(total / 20, 0.02), "no jumps: largest step \(largest) of \(total)")
        XCTAssertLessThan(loop.weight(at: loop.start + 0.05), 0.01, "eases in")
        XCTAssertGreaterThan(loop.weight(at: loop.end - 0.05), 0.99, "eases out")

        // The glide never takes more than half a short video.
        var short = looping
        short.cursor.returnDuration = 2
        short.timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 1.5)]
        let shortLoop = try XCTUnwrap(VideoDemoExporter.makePlan(project: short, sourceDuration: duration, recording: metadata).cursorLoop)
        XCTAssertEqual(shortLoop.end - shortLoop.start, 0.75, accuracy: 0.01)
    }

    func testSavedInPresets() throws {
        var (project, _) = self.project(loop: true, glide: 1.2)
        let decoded = try JSONDecoder().decode(VideoStylePreset.self, from: JSONEncoder().encode(project.style))
        XCTAssertTrue(decoded.cursor.returnToStart)
        XCTAssertEqual(decoded.cursor.returnDuration, 1.2)
        project.cursor.returnToStart = false
        project.apply(style: decoded)
        XCTAssertTrue(project.cursor.returnToStart)
    }
}
