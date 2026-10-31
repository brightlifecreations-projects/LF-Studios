import AppKit
import XCTest
@testable import LFStudiosCore

/// The filmstrip and waveform kept on disk, and background rendering of
/// what's coming up (1.15.0).
@MainActor
final class VideoTimelineCacheTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-timelinecache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testKeptAndMadeAgainWhenTheFileChanges() throws {
        let url = directory.appendingPathComponent("a.mp4")
        try Data("x".utf8).write(to: url)
        let image = NSImage(size: NSSize(width: 16, height: 9), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        VideoTimelineCache.save([VideoTimelineThumbnail(time: 0.5, image: image), VideoTimelineThumbnail(time: 1.5, image: image)], for: url, count: 2)
        XCTAssertEqual(VideoTimelineCache.thumbnails(for: url, count: 2)?.map(\.time), [0.5, 1.5])
        XCTAssertNil(VideoTimelineCache.thumbnails(for: url, count: 3), "another count is another filmstrip")
        VideoTimelineCache.save(waveform: [0.1, 0.5, 1], for: url)
        XCTAssertEqual(VideoTimelineCache.waveform(for: url), [0.1, 0.5, 1])
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(120)], ofItemAtPath: url.path)
        XCTAssertNil(VideoTimelineCache.waveform(for: url), "a changed file is read again")
        XCTAssertNil(VideoTimelineCache.thumbnails(for: url, count: 2))
    }

    func testAnEditorOpensWithTheKeptFilmstrip() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 3)], toneSeconds: 3)
        VideoDemoDraftStore.delete(for: url)
        let first = VideoEditorModel(videoURL: url)
        await first.load()
        // The filmstrip and waveform load in the background: wait for them.
        for _ in 0..<100 where first.thumbnails.isEmpty || first.waveform == nil { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(first.thumbnails.isEmpty)
        for _ in 0..<40 where VideoTimelineCache.waveform(for: url) == nil { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNotNil(VideoTimelineCache.waveform(for: url), "kept for next time")
        XCTAssertTrue(VideoTimelineCache.files.contains { $0.pathExtension == "filmstrip" })
        // Clean Up lists them.
        XCTAssertFalse(VideoDataCleanup.plan(finder: .nowhere).timelineCaches.isEmpty)
    }

    func testBackgroundRenderingMakesWhatsComingUp() {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 60, sourceSize: CGSize(width: 1920, height: 1080))
        var text = VideoTextContent(string: "Warm \(UUID().uuidString.prefix(6))")
        text.size = 77
        let soon = VideoLayerItem.text(text, at: 3, canvas: project.canvasSize())
        let later = VideoLayerItem.sticker(.heart, at: 40, canvas: project.canvasSize())
        var adjustment = VideoLayerItem.adjustmentClip(at: 4, length: 2)
        adjustment.adjust = VideoAdjustSettings(exposure: 0.123)
        project.layerTracks = [VideoLayerTrack(items: [soon, later]), VideoLayerTrack(items: [adjustment])]
        let jobs = VideoRenderWarmup.jobs(for: project, from: 0, seconds: 8, height: 1080)
        XCTAssertEqual(jobs.count, 2, "the text and the adjustment within 8 s, not the sticker at 40 s")
        let h = soon.rect(in: CGSize(width: 1920, height: 1080)).height
        XCTAssertFalse(VideoTextClipRenderer.isCached(text, pixelHeight: h))
        XCTAssertFalse(VideoAdjustRenderer.isCached(adjustment.adjust!))
        VideoRenderWarmup.warm(project, from: 0, height: 1080)
        VideoRenderWarmup.wait()
        // Made already, ready for playback.
        XCTAssertTrue(VideoTextClipRenderer.isCached(text, pixelHeight: h))
        XCTAssertTrue(VideoAdjustRenderer.isCached(adjustment.adjust!))
    }
}
