import AppKit
import AVFoundation
import XCTest
@testable import LFStudiosCore

/// A new recording through the real export, three ways: as it opens
/// (plain), with Auto-zoom on clicks, and with My Style applied. Frames go
/// to $LFSTUDIOS_TEST_FRAMES/manual-only.
@MainActor
final class ManualOnlyExportTests: XCTestCase {
    override func setUp() async throws {
        VideoTestStorage.isolate()
        VideoStylePresetStore.shared.change { $0 = VideoStylePresetLibrary() }
    }

    override func tearDown() async throws {
        VideoStylePresetStore.shared.change { $0 = VideoStylePresetLibrary() }
    }

    private func frames() throws -> URL {
        let base = ProcessInfo.processInfo.environment["LFSTUDIOS_TEST_FRAMES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-test-frames", isDirectory: true)
        let url = base.appendingPathComponent("manual-only", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func export(_ model: VideoEditorModel, to url: URL) async throws {
        var settings = VideoExportSettings()
        settings.resolution = .p1080
        settings.fps = 30
        settings.endCard = false
        try? FileManager.default.removeItem(at: url)
        try await VideoDemoExporter.export(project: model.project, recording: model.recording, destinationURL: url, settings: settings)
    }

    private func frame(_ url: URL, at time: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    private func save(_ image: CGImage, _ url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// The pixel at a fraction of the frame (top-left origin).
    private func color(_ image: CGImage, x: Double, y: Double) -> (r: Double, g: Double, b: Double) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -Double(image.width) * x, y: -Double(image.height) * (1 - y), width: Double(image.width), height: Double(image.height)))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    func testANewRecordingThenAutoZoomThenMyStyle() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-manual-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("New recording.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 1440, height: 900), seconds: 8, fps: 30)
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 8)
        let metadata = VideoDemoRecordingMetadata(videoURLPath: url.path, createdAt: Date(), duration: 8, sourceWidth: 1440, sourceHeight: 900, fps: 30, nativeCursorVisible: false, cursorSamples: samples, clickEvents: clicks, pointPixelScale: 2, renderCursor: true)
        VideoDemoSidecarStore.save(metadata, for: url)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.isReady)
        let out = try frames()
        let time = 3.4

        // 1. As it opens: the recording itself, its own 1440×900 frame.
        let plain = folder.appendingPathComponent("1-plain.mp4")
        try await export(model, to: plain)
        let plainFrame = try await frame(plain, at: time)
        try save(plainFrame, out.appendingPathComponent("1-plain-as-it-opens.png"))
        XCTAssertEqual(Double(plainFrame.width) / Double(plainFrame.height), 1440.0 / 900, accuracy: 0.01, "the recording's own shape: no 16:9 frame around it")
        let corner = color(plainFrame, x: 0.004, y: 0.004)
        let source = try await frame(url, at: time)
        let sourceCorner = color(source, x: 0.004, y: 0.004)
        XCTAssertEqual(corner.r, sourceCorner.r, accuracy: 0.08, "the corner is the recording, not a background")
        XCTAssertTrue(model.project.zoomRegions.isEmpty)

        // 2. Auto-zoom on clicks: zooms from the clicks.
        model.setAutoZoom(true)
        XCTAssertTrue(model.project.zoomRegions.contains { $0.isAuto })
        let zoomed = folder.appendingPathComponent("2-auto-zoom.mp4")
        try await export(model, to: zoomed)
        let zoomedFrame = try await frame(zoomed, at: time)
        try save(zoomedFrame, out.appendingPathComponent("2-auto-zoom-on.png"))
        let difference = zip(TestImageBytes.rgba(plainFrame), TestImageBytes.rgba(zoomedFrame)).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(plainFrame.width * plainFrame.height * 4) / 255
        print("plain vs auto-zoom mean difference \(difference)")
        XCTAssertGreaterThan(difference, 0.02, "the zoom changes the picture")

        // 3. Apply my style: a framed look with a background.
        var look = VideoStylePreset.factory
        look.background = .color(VideoRGBA(0.95, 0.5, 0.15))
        look.padding = 0.12
        VideoStylePresetStore.shared.change { library in
            let preset = library.add(name: "Brand", style: look, includesAspectRatio: true)
            library.setMyStyle(preset.id)
        }
        model.applyMyStyle()
        let styled = folder.appendingPathComponent("3-my-style.mp4")
        try await export(model, to: styled)
        let styledFrame = try await frame(styled, at: time)
        try save(styledFrame, out.appendingPathComponent("3-apply-my-style.png"))
        XCTAssertEqual(Double(styledFrame.width) / Double(styledFrame.height), 16.0 / 9, accuracy: 0.01, "My Style's 16:9 frame")
        let background = color(styledFrame, x: 0.01, y: 0.01)
        XCTAssertEqual(background.r, 0.95, accuracy: 0.08, "My Style's orange background: \(background)")
        XCTAssertEqual(background.g, 0.5, accuracy: 0.1)
        print("Manual-only frames saved in \(out.path)")
    }
}

/// RGBA bytes of an image, for comparing frames.
enum TestImageBytes {
    static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    /// Two exports of the same edit show the same picture, but they aren't
    /// always the same bytes: while other exports keep the Mac's video
    /// encoder busy (the full test run), H.264 compresses a little
    /// differently: up to about 36 levels in a pixel, 0.05 on average. Any
    /// drawing that matters (an icon, a line, a shade) is far more
    /// (VideoPhoneOverlayTests.testTheComparisonWouldSeeTheOverlay).
    static let encoderNoise = (largest: 64, mean: 0.5)

    /// The largest difference in one channel of one pixel, and the average
    /// over all of them, in levels (0–255).
    static func difference(_ a: CGImage, _ b: CGImage) -> (largest: Int, mean: Double) {
        let first = rgba(a)
        let second = rgba(b)
        guard first.count == second.count, !first.isEmpty else { return (255, 255) }
        var largest = 0
        var total = 0
        for index in first.indices {
            let difference = abs(Int(first[index]) - Int(second[index]))
            largest = max(largest, difference)
            total += difference
        }
        return (largest, Double(total) / Double(first.count))
    }

    /// Two exported frames show the same picture, give or take encoder noise.
    static func assertSamePicture(_ a: CGImage, _ b: CGImage, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let (largest, mean) = difference(a, b)
        XCTAssertLessThanOrEqual(largest, encoderNoise.largest, "\(message): a pixel differs by \(largest)", file: file, line: line)
        XCTAssertLessThan(mean, encoderNoise.mean, "\(message): pixels differ by \(mean) on average", file: file, line: line)
    }
}
