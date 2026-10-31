import AVFoundation
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Budget checks: the preview must render a Retina recording well inside a
/// 60Hz frame, and export must beat real time.
final class VideoPerformanceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    func testPreviewFrameRenderBudget() throws {
        let source = CIImage(cgImage: VideoTestSupport.fakeScreen(size: CGSize(width: 2880, height: 1800), progress: 0.5, typed: "Acme"))
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/perf.mp4"), duration: 10, sourceSize: CGSize(width: 2880, height: 1800))
        project.apply(style: .factory)
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 10)
        project.cursorSamples = samples
        project.clickEvents = clicks
        project.nativeCursorVisible = false
        project.zoomRegions = [VideoZoomRegion(start: 1, end: 9, scale: 2, followsCursor: true)]
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 10, recording: nil)
        let renderer = VideoFrameRenderer()
        let context = VideoRenderContext.makeContext()
        let size = CGSize(width: 2600, height: 1462) // a Retina preview area

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &buffer)
        let target = try XCTUnwrap(buffer)

        // Warm up (shader compiles, caches).
        for i in 0..<10 {
            context.render(renderer.render(source: source, timelineTime: Double(i) * 0.1, plan: plan, outputSize: size), to: target, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        let frames = 120
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<frames {
            let image = renderer.render(source: source, timelineTime: 1.5 + Double(i) / 60, plan: plan, outputSize: size)
            context.render(image, to: target, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        let perFrame = (CFAbsoluteTimeGetCurrent() - start) / Double(frames) * 1000
        print(String(format: "PERF: preview frame %.2f ms (%.0f fps)", perFrame, 1000 / perFrame))
        XCTAssertLessThan(perFrame, 16, "must fit a 60Hz frame with room to spare")
    }

    func testExportBeatsRealTime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("src.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 2880, height: 1800), seconds: 6, fps: 60)
        var project = VideoDemoProject.make(sourceURL: url, duration: 6, sourceSize: CGSize(width: 2880, height: 1800))
        project.apply(style: .factory)
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 6)
        project.cursorSamples = samples
        project.clickEvents = clicks
        project.nativeCursorVisible = false
        project.zoomRegions = [VideoZoomRegion(start: 1, end: 5, scale: 2, followsCursor: true)]
        var settings = VideoExportSettings()
        settings.resolution = .p1080
        settings.fps = 60
        settings.endCard = false
        let start = CFAbsoluteTimeGetCurrent()
        try await VideoDemoExporter.export(project: project, destinationURL: directory.appendingPathComponent("out.mp4"), settings: settings)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print(String(format: "PERF: 6s 1080p60 export in %.2fs (%.1fx real time)", elapsed, 6 / elapsed))
        XCTAssertLessThan(elapsed, 6)
    }
}

/// A 30-minute project with many tracks (1.15.0): opening, planning,
/// editing and drawing stay inside their budgets.
@MainActor
final class VideoLongProjectPerformanceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    /// 30 minutes, 60 clips with dissolves, and four tracks above the main
    /// track: text every 10 s, stickers every 10 s, an effect clip and an
    /// adjustment clip every minute.
    static func longProject(source: URL) -> VideoDemoProject {
        let minutes = 30.0
        var project = VideoDemoProject.make(sourceURL: source, duration: minutes * 60, sourceSize: CGSize(width: 1920, height: 1080))
        project.timelineClips = (0..<60).map { VideoDemoTimelineClip(sourceStart: Double($0) * 30, sourceEnd: Double($0 + 1) * 30) }
        project.transitions.betweenClips = .dissolve
        let canvas = project.canvasSize()
        var texts = VideoLayerTrack(), stickers = VideoLayerTrack(), effects = VideoLayerTrack(), adjustments = VideoLayerTrack()
        for i in 0..<180 {
            var text = VideoLayerItem.text(VideoTextContent(string: "Title \(i)"), at: Double(i) * 10, canvas: canvas)
            text.animation = VideoItemAnimation(inPreset: .pop)
            texts.items.append(text)
            stickers.items.append(VideoLayerItem.sticker(VideoSticker.allCases[i % VideoSticker.allCases.count], at: Double(i) * 10 + 5, canvas: canvas))
        }
        for i in 0..<30 {
            effects.items.append(VideoLayerItem.effectClip(VideoEffectKind.allCases[i % VideoEffectKind.allCases.count], at: Double(i) * 60 + 20, length: 5))
            var adjustment = VideoLayerItem.adjustmentClip(at: Double(i) * 60 + 30, length: 10)
            adjustment.adjust = VideoAdjustSettings(exposure: 0.1, contrast: 0.2)
            adjustment.filter = VideoAppliedFilter(look: VideoFilterLook.allCases[i % VideoFilterLook.allCases.count])
            adjustments.items.append(adjustment)
        }
        project.layerTracks = [texts, stickers, effects, adjustments]
        return project
    }

    func testThirtyMinutesWithManyTracks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-long-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Synthetic media: 30 minutes at 2 frames a second, small.
        let source = directory.appendingPathComponent("long.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.darkGray, 1800)], fps: 2)
        let project = Self.longProject(source: source)
        XCTAssertEqual(project.layerItems.count, 420)

        // Saving and opening the project.
        var start = CFAbsoluteTimeGetCurrent()
        let data = try JSONEncoder().encode(project)
        _ = try JSONDecoder().decode(VideoDemoProject.self, from: data)
        let saveOpen = CFAbsoluteTimeGetCurrent() - start
        // Planning the edit.
        start = CFAbsoluteTimeGetCurrent()
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 1800, recording: nil)
        let planning = CFAbsoluteTimeGetCurrent() - start
        // Drawing frames all over the timeline at preview size.
        let renderer = VideoFrameRenderer()
        let context = VideoRenderContext.makeContext()
        let size = CGSize(width: 1280, height: 720)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &buffer)
        let target = try XCTUnwrap(buffer)
        let frame = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let times = (0..<180).map { Double($0) * 10 + 1.3 }
        for time in times.prefix(20) { context.render(renderer.render(source: frame, timelineTime: time, plan: plan, outputSize: size), to: target, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) }
        // Playing: frames a thirtieth of a second apart, with the
        // background rendering ahead of them.
        VideoRenderWarmup.warm(project, from: 600, seconds: 30, height: size.height)
        VideoRenderWarmup.wait()
        start = CFAbsoluteTimeGetCurrent()
        for i in 0..<240 {
            let time = 600 + Double(i) / 30
            context.render(renderer.render(source: frame, timelineTime: time, plan: plan, outputSize: size), to: target, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        let perFrame = (CFAbsoluteTimeGetCurrent() - start) / 240 * 1000
        // The editor: open it, then make one edit.
        VideoDemoDraftStore.delete(for: source)
        let model = VideoEditorModel(videoURL: source)
        await model.load()
        model.project = project
        start = CFAbsoluteTimeGetCurrent()
        model.seek(to: 905)
        model.perform(.split)
        let edit = CFAbsoluteTimeGetCurrent() - start
        print(String(format: "PERF: 30-min project — save+open %.0f ms, plan %.0f ms, frame %.1f ms, split %.0f ms", saveOpen * 1000, planning * 1000, perFrame, edit * 1000))
        XCTAssertLessThan(saveOpen, 1, "saving and opening")
        XCTAssertLessThan(planning, 1, "planning the edit")
        XCTAssertLessThan(perFrame, 33, "playback at 30 frames a second")
        XCTAssertLessThan(edit, 0.5, "an edit")
        VideoDemoDraftStore.delete(for: source)
    }
}
