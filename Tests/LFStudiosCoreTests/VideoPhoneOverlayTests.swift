import AVFoundation
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// The phone overlay: off until switched on, only for vertical videos,
/// generic (no app names), and never in an export.
@MainActor
final class VideoPhoneOverlayTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        VideoTestStorage.isolate()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-phone-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testOnlyForVerticalVideos() {
        XCTAssertTrue(VideoPhoneLayout.isAvailable(for: CGSize(width: 1080, height: 1920)))
        XCTAssertFalse(VideoPhoneLayout.isAvailable(for: CGSize(width: 1920, height: 1080)))
        XCTAssertFalse(VideoPhoneLayout.isAvailable(for: CGSize(width: 1080, height: 1080)))
        XCTAssertFalse(VideoPhoneLayout.isAvailable(for: CGSize(width: 1080, height: 1350)), "4:5 isn't a phone screen")
    }

    func testLayoutsAreGenericAndInsideTheFrame() {
        XCTAssertEqual(VideoPhoneLayout.allCases.map(\.title), [L("Side rail"), L("Full rail"), L("Minimal")])
        let brands = ["tiktok", "reels", "shorts", "instagram", "youtube", "snapchat", "facebook"]
        for language in ["en"] + L10n.translations {
            L10n.use(language)
            for layout in VideoPhoneLayout.allCases {
                let text = (layout.title + " " + layout.detail).lowercased()
                XCTAssertFalse(brands.contains { text.contains($0) }, "\(language): \(text)")
            }
        }
        L10n.use(nil)
        let size = CGSize(width: 1080, height: 1920)
        let frame = CGRect(origin: .zero, size: size)
        var seen: [VideoPhoneLayout.Zones] = []
        for layout in VideoPhoneLayout.allCases {
            for rect in layout.unsafeRects(in: size) {
                XCTAssertTrue(frame.contains(rect), "\(layout): \(rect)")
                XCTAssertGreaterThan(rect.height, 0)
            }
            XCTAssertFalse(seen.contains(layout.zones), "each layout has its own zones")
            seen.append(layout.zones)
        }
    }

    func testOffByDefaultAndNeverExported() async throws {
        let url = folder.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 960, height: 600), seconds: 2, fps: 30)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertNil(model.phoneOverlay)
        XCTAssertFalse(model.canShowPhoneOverlay, "a landscape recording")
        model.setStyle { $0.apply(aspectPreset: .vertical) }
        XCTAssertTrue(model.canShowPhoneOverlay)
        model.togglePhoneOverlay()
        XCTAssertEqual(model.phoneOverlay, .sideRail)
        XCTAssertFalse(model.canUndo && model.undoLabel == "Phone Overlay", "showing it isn't an edit")

        var settings = VideoExportSettings()
        settings.resolution = .p720
        settings.fps = 30
        let with = folder.appendingPathComponent("with.mp4")
        try await VideoDemoExporter.export(project: model.project, recording: model.recording, destinationURL: with, settings: settings)
        model.phoneOverlay = nil
        let without = folder.appendingPathComponent("without.mp4")
        try await VideoDemoExporter.export(project: model.project, recording: model.recording, destinationURL: without, settings: settings)
        for time in [0.2, 1.0, 1.8] {
            let a = try await frame(with, at: time)
            let b = try await frame(without, at: time)
            TestImageBytes.assertSamePicture(a, b, "the export is the same with the overlay on (\(time) s)")
        }
        let json = String(data: try JSONEncoder().encode(model.project), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("phoneOverlay") || json.contains("sideRail"), "not saved in the project")
    }

    /// The export check allows for encoder noise, but never for the
    /// overlay: even the lightest layout over a real exported frame is far
    /// outside it.
    func testTheComparisonWouldSeeTheOverlay() async throws {
        let url = folder.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 960, height: 600), seconds: 2, fps: 30)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        model.setStyle { $0.apply(aspectPreset: .vertical) }
        var settings = VideoExportSettings()
        settings.resolution = .p720
        settings.fps = 30
        let exported = folder.appendingPathComponent("plain.mp4")
        try await VideoDemoExporter.export(project: model.project, recording: model.recording, destinationURL: exported, settings: settings)
        let plain = try await frame(exported, at: 1.0)
        let size = CGSize(width: plain.width, height: plain.height)
        for layout in VideoPhoneLayout.allCases {
            let view = ZStack {
                Image(decorative: plain, scale: 1)
                VideoPhoneOverlayView(layout: layout, size: size)
            }
            .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let overlaid = try XCTUnwrap(renderer.cgImage)
            let (largest, mean) = TestImageBytes.difference(plain, overlaid)
            XCTAssertGreaterThan(largest, TestImageBytes.encoderNoise.largest * 2, "\(layout)")
            XCTAssertGreaterThan(mean, TestImageBytes.encoderNoise.mean, "\(layout)")
            print("PHONE OVERLAY CHECK: \(layout) largest \(largest) mean \(mean)")
        }
    }

    /// Pictures of each layout over a grey frame, for a look.
    func testDrawEachLayout() throws {
        let base = ProcessInfo.processInfo.environment["LFSTUDIOS_TEST_FRAMES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-test-frames", isDirectory: true)
        let out = base.appendingPathComponent("phone-overlay", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let size = CGSize(width: 360, height: 640)
        for layout in VideoPhoneLayout.allCases {
            let view = ZStack {
                LinearGradient(colors: [Color(white: 0.45), Color(white: 0.25)], startPoint: .top, endPoint: .bottom)
                VideoPhoneOverlayView(layout: layout, size: size)
            }
            .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            let url = out.appendingPathComponent("\(layout.rawValue).png")
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            print("PHONE OVERLAY: \(url.path)")
        }
    }

    private func frame(_ url: URL, at time: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }
}
