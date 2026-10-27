import AVFoundation
import XCTest
@testable import LFStudiosCore

/// Checks on real exports for typing zooms, loupes, fitting zooms around
/// the camera, cursor styles and Speed up typing, kept in
/// $LFSTUDIOS_TEST_FRAMES/typing for a look. With $LFSTUDIOS_TYPING_RECORDING
/// (a folder with recording.mp4 and metadata.json from a real recording
/// made with both typing options on) they run on that; otherwise on a
/// scripted recording.
@MainActor
final class ReleaseChecksTypingTests: XCTestCase {
    private var out: URL!
    /// This test's own copy of the recording (the checks run in parallel).
    private var recordingURL: URL?

    override func setUp() async throws {
        VideoTestStorage.isolate()
        let base = ProcessInfo.processInfo.environment["LFSTUDIOS_TEST_FRAMES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-test-frames", isDirectory: true)
        out = base.appendingPathComponent("typing", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let recordingURL {
            VideoDemoDraftStore.delete(for: recordingURL)
            try? FileManager.default.removeItem(at: recordingURL)
        }
    }

    private func model() async throws -> VideoEditorModel {
        let url = out.appendingPathComponent("recording-\(UUID().uuidString).mp4")
        recordingURL = url
        var metadata: VideoDemoRecordingMetadata
        if let real = ProcessInfo.processInfo.environment["LFSTUDIOS_TYPING_RECORDING"].map({ URL(fileURLWithPath: $0, isDirectory: true) }) {
            try FileManager.default.copyItem(at: real.appendingPathComponent("recording.mp4"), to: url)
            metadata = try JSONDecoder().decode(VideoDemoRecordingMetadata.self, from: Data(contentsOf: real.appendingPathComponent("metadata.json")))
            metadata.videoURLPath = url.path
        } else {
            try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 1440, height: 900), seconds: 12, fps: 30)
            let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 12)
            metadata = VideoDemoRecordingMetadata(videoURLPath: url.path, createdAt: Date(), duration: 12, sourceWidth: 1440, sourceHeight: 900, fps: 30, nativeCursorVisible: false, cursorSamples: samples, clickEvents: clicks, pointPixelScale: 2, renderCursor: true)
            metadata.textCursor = stride(from: 2.0, through: 8.0, by: 0.15).enumerated().map { VideoTextCursorSample(time: $1, x: 0.04 + Double($0) * 0.004, y: 0.12, width: 0, height: 0.012) }
            metadata.keyPresses = Array(stride(from: 2.0, through: 8.0, by: 0.15))
        }
        VideoDemoSidecarStore.save(metadata, for: url)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.isReady)
        model.setStyle { $0.apply(style: .factory) }
        return model
    }

    private func export(_ model: VideoEditorModel, _ name: String) async throws -> URL {
        var settings = VideoExportSettings()
        settings.resolution = .p1080
        settings.fps = 30
        let url = out.appendingPathComponent("\(name).mp4")
        try? FileManager.default.removeItem(at: url)
        try await VideoDemoExporter.export(project: model.project, recording: model.recording, destinationURL: url, settings: settings)
        return url
    }

    private func frame(_ url: URL, at time: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    private func save(_ image: CGImage, _ name: String) throws {
        let url = out.appendingPathComponent("\(name).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func save(_ image: CIImage, size: CGSize, _ name: String) throws {
        try VideoTestSupport.writePNG(image, size: size, to: out.appendingPathComponent("\(name).png"))
    }

    private func duration(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    /// The recording's own frame at a source moment.
    private func sourceFrame(_ model: VideoEditorModel, at time: Double) async throws -> CIImage {
        CIImage(cgImage: try await frame(model.project.sourceURL, at: time))
    }

    // MARK: Typing zooms, Speed up typing

    func testTypingZoomsAndSpeedUp() async throws {
        let model = try await model()
        let stretches = try XCTUnwrap(model.typingStretches)
        print("TYPING basis \(stretches.basis): \(stretches.stretches.map { String(format: "%.2f–%.2f", $0.start, $0.end) })")

        model.addTypingZooms()
        let zooms = model.project.zoomRegions.filter(\.isTyping)
        XCTAssertFalse(zooms.isEmpty)
        print("TYPING ZOOMS \(zooms.map { String(format: "%.2f–%.2f", $0.start, $0.end) })")

        // While typing, the text cursor is inside the zoomed view.
        let plan = model.plan
        var checked = 0
        for zoom in zooms {
            for time in stride(from: zoom.start + 1.2, through: zoom.end - 1, by: 1.5) {
                guard let caret = plan.typingTrack?.position(at: time), let t = model.timelineTime(forSource: time) else { continue }
                let window = plan.camera.state(at: t).window(in: plan.canvasSize)
                XCTAssertTrue(window.contains(plan.canvasPoint(forVideoPoint: caret)), "at \(time)s the text cursor is in view")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 2)
        let zoomed = try await export(model, "typing-zooms")
        for (index, zoom) in zooms.enumerated() {
            for (name, time) in [("a", zoom.start + 1.5), ("b", (zoom.start + zoom.end) / 2), ("c", zoom.end - 1.2)] {
                try save(try await frame(zoomed, at: model.timelineTime(forSource: time) ?? time), "typing-zoom\(index + 1)-\(name)")
            }
        }

        // Speed up typing: the video gets shorter by what was sped up.
        let before = try await duration(zoomed)
        model.speedUpTyping(4)
        let sped = model.project.timelineClips.filter(\.typingSpeedUp)
        XCTAssertFalse(sped.isEmpty)
        let expected = sped.reduce(0) { $0 + $1.sourceDuration * (1 - 1.0 / 4) }
        let fast = try await export(model, "typing-sped-up-4x")
        let after = try await duration(fast)
        print(String(format: "SPEED UP: %.2f s → %.2f s, %.2f s shorter (expected %.2f s)", before, after, before - after, expected))
        XCTAssertEqual(before - after, expected, accuracy: 0.12)
    }

    // MARK: Loupe

    func testLoupeExport() async throws {
        let model = try await model()
        let stretch = try XCTUnwrap(model.typingStretches?.stretches.first)
        var region = VideoZoomRegion(start: stretch.start, end: stretch.end + 0.6, scale: 2.5, followsCursor: false)
        region.followsTyping = true
        var style = VideoLoupeStyle()
        style.size = 0.4
        style.shape = .circle
        region.loupe = style
        model.mutate(label: "Add Loupe") { $0.zoomRegions = [region] }
        let url = try await export(model, "loupe")
        let mid = (stretch.start + stretch.end) / 2
        for (name, time) in [("opening", stretch.start + 0.12), ("open", mid), ("later", stretch.end - 0.5)] {
            try save(try await frame(url, at: model.timelineTime(forSource: time) ?? time), "loupe-\(name)")
        }

        model.updateLoupe(region.id) { $0.shape = .rounded; $0.borderColor = VideoRGBA(1, 0.6, 0); $0.borderWidth = 0.01; $0.shadow = 1 }
        let rounded = try await export(model, "loupe-rounded")
        try save(try await frame(rounded, at: model.timelineTime(forSource: mid) ?? mid), "loupe-rounded-open")
    }

    // MARK: Fit zooms around camera

    func testFitZoomsAroundCamera() async throws {
        let model = try await model()
        model.addTypingZooms()
        // A big camera bubble in the corner the typing is in.
        var project = model.project
        let caret = model.plan.typingTrack?.samples.first?.center ?? CGPoint(x: 0.2, y: 0.2)
        project.webcam.anchor = caret.x < 0.5 ? (caret.y < 0.5 ? .topLeft : .bottomLeft) : (caret.y < 0.5 ? .topRight : .bottomRight)
        project.webcam.size = 0.5
        project.webcam.shrinkWhenZoomed = false
        let output = CGSize(width: 1920, height: 1080)
        // A stand-in camera picture (the recording has no camera).
        let camera = CIImage(color: CIColor(red: 0.95, green: 0.45, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        func render(_ project: VideoDemoProject, _ name: String, at source: Double) async throws {
            let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: model.sourceDuration, recording: model.recording, hasWebcam: true)
            var options = VideoFrameRenderer.Options()
            options.webcamFrame = camera
            options.frameRate = 30
            let time = project.timelineTime(forSourceTime: source, totalDuration: model.sourceDuration)
            let image = VideoFrameRenderer().render(source: try await sourceFrame(model, at: source), timelineTime: time, plan: plan, outputSize: output, options: options)
            try save(image, size: output, name)
        }
        let zoom = try XCTUnwrap(project.zoomRegions.first(where: \.isTyping))
        let moment = zoom.start + 2.2
        let makePlan = { (candidate: VideoDemoProject) in VideoDemoExporter.makePlan(project: candidate, sourceDuration: model.sourceDuration, recording: model.recording, hasWebcam: true) }
        XCTAssertTrue(VideoZoomCameraFit.isCovered(zoom, plan: makePlan(project)), "the bubble covers the typing")
        try await render(project, "fit-before", at: moment)

        var shifted = project
        let shift = VideoZoomCameraFit.fit(&shifted, mode: .shiftFraming, makePlan: makePlan)
        print("FIT shift: \(VideoEditorModel.fitMessage(shift, mode: .shiftFraming))")
        try await render(shifted, "fit-after-shift", at: moment)

        var moved = project
        let move = VideoZoomCameraFit.fit(&moved, mode: .moveCamera, makePlan: makePlan)
        print("FIT move: \(VideoEditorModel.fitMessage(move, mode: .moveCamera)) → \(moved.zoomRegions.compactMap(\.cameraCorner))")
        try await render(moved, "fit-after-move-camera", at: moment)
        XCTAssertGreaterThan(shift.adjusted + move.adjusted, 0)

        // A loupe over the typing, under the bubble.
        var loupe = project
        if let index = loupe.zoomRegions.firstIndex(where: { $0.id == zoom.id }) {
            loupe.zoomRegions[index].loupe = VideoLoupeStyle()
            loupe.zoomRegions[index].scale = 2.5
        }
        loupe.webcam.size = 0.3
        let loupeZoom = try XCTUnwrap(loupe.zoomRegions.first { $0.id == zoom.id })
        XCTAssertTrue(VideoZoomCameraFit.isCovered(loupeZoom, plan: makePlan(loupe)), "the bubble covers the loupe")
        try await render(loupe, "fit-loupe-before", at: moment)
        let loupeResult = VideoZoomCameraFit.fit(&loupe, mode: .shiftFraming, makePlan: makePlan)
        print("FIT loupe: \(VideoEditorModel.fitMessage(loupeResult, mode: .shiftFraming))")
        XCTAssertEqual(loupeResult.adjusted, 1)
        try await render(loupe, "fit-loupe-after-shift", at: moment)
    }

    // MARK: Cursor styles

    func testCursorStyles() async throws {
        let model = try await model()
        let output = CGSize(width: 1920, height: 1080)
        // Mid-typing: the pointer is over the text, so it's the I-beam.
        let time = try XCTUnwrap(model.typingStretches?.stretches.first).start + 2
        let source = try await sourceFrame(model, at: time)
        let renderer = VideoFrameRenderer()
        for style in VideoCursorStyle.allCases where style != .custom {
            var project = model.project
            project.cursor.style = style
            project.cursor.size = 2.4
            // Still while typing: idle hiding would fade it out.
            project.cursor.hideWhenIdle = false
            let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: model.sourceDuration, recording: model.recording)
            let t = project.timelineTime(forSourceTime: time, totalDuration: model.sourceDuration)
            let image = renderer.render(source: source, timelineTime: t, plan: plan, outputSize: output)
            // A close-up around the pointer.
            let pointer = plan.cursorTrack.map { plan.canvasPoint(forVideoPoint: $0.position(at: time)) } ?? CGPoint(x: plan.canvasSize.width / 2, y: plan.canvasSize.height / 2)
            let k = output.width / plan.canvasSize.width
            let crop = CGRect(x: pointer.x * k - 160, y: output.height - pointer.y * k - 160, width: 320, height: 320)
            let close = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            try save(close, size: crop.size, "cursor-\(style.rawValue)")
        }

        // Every style's arrow, I-beam and hand side by side.
        let cell: CGFloat = 120
        var sheet = CIImage(color: CIColor(red: 0.55, green: 0.6, blue: 0.68)).cropped(to: CGRect(x: 0, y: 0, width: cell * 3, height: cell * 4))
        for (row, style) in [VideoCursorStyle.white, .outlined, .touch, .ring].enumerated() {
            var settings = VideoCursorSettings()
            settings.style = style
            let artwork = try XCTUnwrap(VideoCursorStyleArtwork.make(settings: settings))
            for (column, kind) in [VideoCursorKind.arrow, .text, .hand].enumerated() {
                let shape = artwork.shape(for: kind)
                let image = shape.mips[0]
                let scale = cell * 0.7 / max(image.extent.width, image.extent.height)
                let placed = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let x = CGFloat(column) * cell + (cell - placed.extent.width) / 2
                let y = CGFloat(3 - row) * cell + (cell - placed.extent.height) / 2
                sheet = placed.transformed(by: CGAffineTransform(translationX: x, y: y)).composited(over: sheet)
            }
        }
        try save(sheet, size: CGSize(width: cell * 3, height: cell * 4), "cursor-styles-sheet")
    }
}
