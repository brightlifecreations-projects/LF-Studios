import AVFoundation
import XCTest
@testable import LFStudiosCore

/// 1.3.0's checks on real exports, kept in $LFSTUDIOS_TEST_FRAMES/1.3 for
/// a look (and for avmediainfo): each ProRes type, 4444 with transparency,
/// markers as chapters, a looping cursor's first and last frames, the
/// fine-tuned shadow and its inset, and the phone overlay staying out.
@MainActor
final class ReleaseChecks13Tests: XCTestCase {
    private var out: URL!

    override func setUp() async throws {
        VideoTestStorage.isolate()
        let base = ProcessInfo.processInfo.environment["LFSTUDIOS_TEST_FRAMES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-test-frames", isDirectory: true)
        out = base.appendingPathComponent("1.3", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    /// A 6 s recording with a scripted pointer, a camera-less screen, and
    /// sound; markers at 1.5 s and 4 s.
    private func model() async throws -> VideoEditorModel {
        let url = out.appendingPathComponent("recording.mp4")
        try? FileManager.default.removeItem(at: url)
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 1440, height: 900), seconds: 6, fps: 30, audioSeconds: 6)
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 6)
        let metadata = VideoDemoRecordingMetadata(videoURLPath: url.path, createdAt: Date(), duration: 6, sourceWidth: 1440, sourceHeight: 900, fps: 30, nativeCursorVisible: false, cursorSamples: samples, clickEvents: clicks, pointPixelScale: 2, renderCursor: true, markers: [VideoMarker(time: 1.5, name: "Open the settings"), VideoMarker(time: 4, name: "Turn it on")])
        VideoDemoSidecarStore.save(metadata, for: url)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.isReady)
        return model
    }

    private func export(_ model: VideoEditorModel, _ name: String, _ change: (inout VideoExportSettings) -> Void = { _ in }) async throws -> URL {
        var settings = VideoExportSettings()
        settings.resolution = .p1080
        settings.fps = 30
        change(&settings)
        let url = out.appendingPathComponent("\(name).\(settings.fileExtension)")
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

    func testReleaseChecks() async throws {
        let model = try await model()
        model.setStyle { $0.apply(style: .factory) }

        // ProRes, each type; 4444 with a transparent background.
        for format in [VideoExportSettings.Format.proRes422, .proRes422HQ, .proRes4444] {
            _ = try await export(model, "prores-\(format.rawValue)") { $0.format = format }
        }
        let alpha = try await export(model, "prores4444-transparent") {
            $0.format = .proRes4444
            $0.transparentBackground = true
        }
        try save(try await frame(alpha, at: 2), "prores4444-transparent-frame")

        // Markers as MP4 chapters.
        _ = try await export(model, "chapters") { $0.chapters = true }
        print("CHAPTERS TEXT:\n\(VideoChapterText.text(model.chapters, duration: model.timelineDuration))")

        // The looping cursor: first and last frames.
        model.setStyle { $0.cursor.returnToStart = true }
        let loop = try await export(model, "looping-cursor")
        let first = try await frame(loop, at: 0)
        let last = try await frame(loop, at: model.timelineDuration - 1.0 / 30)
        try save(first, "loop-first-frame")
        try save(last, "loop-last-frame")
        let difference = zip(TestImageBytes.rgba(first), TestImageBytes.rgba(last)).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(first.width * first.height * 4) / 255
        print("LOOP first vs last mean difference: \(difference)")
        XCTAssertLessThan(difference, 0.003)
        model.setStyle { $0.cursor.returnToStart = false }

        // The fine-tuned shadow, then its inset.
        model.setStyle {
            $0.background = .color(VideoRGBA(0.93, 0.93, 0.95))
            $0.shadowStyle = VideoShadowStyle(angle: 45, distance: 34, softness: 40, opacity: 0.7, color: VideoRGBA(0.15, 0.1, 0.45))
        }
        try save(try await frame(try await export(model, "shadow"), at: 2), "shadow-fine-tuned")
        model.setStyle { $0.shadowStyle = VideoShadowStyle(angle: 90, distance: 14, softness: 36, opacity: 0.9, color: VideoRGBA(1, 1, 1), inset: true) }
        try save(try await frame(try await export(model, "inset"), at: 2), "shadow-inset")

        // The phone overlay never reaches an export.
        model.setStyle {
            $0.shadowStyle = nil
            $0.apply(aspectPreset: .vertical)
        }
        let plain = try await frame(try await export(model, "vertical-plain"), at: 2)
        model.phoneOverlay = .fullRail
        let overlaid = try await frame(try await export(model, "vertical-with-overlay-on"), at: 2)
        XCTAssertEqual(TestImageBytes.rgba(plain), TestImageBytes.rgba(overlaid))
        try save(overlaid, "vertical-export-with-overlay-on")
        print("RELEASE CHECKS in \(out.path)")
    }
}
