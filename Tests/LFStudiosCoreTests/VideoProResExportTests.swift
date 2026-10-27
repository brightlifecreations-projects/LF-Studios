import AVFoundation
import XCTest
@testable import LFStudiosCore

/// ProRes in the normal export: each type writes a .mov with that codec
/// and uncompressed sound, 4444 keeps transparency only when asked, and the
/// size estimate and the space check know ProRes is big.
@MainActor
final class VideoProResExportTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        VideoTestStorage.isolate()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-prores-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func model() async throws -> VideoEditorModel {
        let url = folder.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 960, height: 600), seconds: 2, fps: 30, audioSeconds: 2)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.isReady)
        // A framed look: background, margin, corners, shadow.
        model.setStyle { $0.apply(style: .factory) }
        return model
    }

    private func export(_ model: VideoEditorModel, _ format: VideoExportSettings.Format, transparent: Bool = false) async throws -> URL {
        var settings = VideoExportSettings()
        settings.format = format
        settings.resolution = .p720
        settings.fps = 30
        settings.transparentBackground = transparent
        let url = folder.appendingPathComponent("\(format.rawValue)\(transparent ? "-alpha" : "").\(settings.fileExtension)")
        try await VideoDemoExporter.export(project: model.project, recording: model.recording, destinationURL: url, settings: settings)
        return url
    }

    private func codec(_ url: URL) async throws -> FourCharCode {
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let description = try XCTUnwrap(descriptions.first)
        return CMFormatDescriptionGetMediaSubType(description)
    }

    /// The alpha of a pixel in the frame at 1 s (fractions, top-left origin).
    private func alpha(_ url: URL, x: Double, y: Double) async throws -> UInt8 {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600), duration: CMTime(seconds: 0.5, preferredTimescale: 600))
        XCTAssertTrue(reader.startReading())
        let sample = try XCTUnwrap(output.copyNextSampleBuffer())
        let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let px = min(Int(Double(width) * x), width - 1), py = min(Int(Double(height) * y), height - 1)
        return base[py * row + px * 4 + 3]
    }

    func testDefaultsAreMP4WithoutTransparency() {
        let settings = VideoExportSettings()
        XCTAssertEqual(settings.format, .mp4)
        XCTAssertFalse(settings.transparentBackground)
        XCTAssertFalse(settings.keepsTransparency)
        var other = settings
        other.format = .proRes422HQ
        other.transparentBackground = true
        XCTAssertFalse(other.keepsTransparency, "only 4444 keeps transparency")
        XCTAssertEqual(VideoExportSettings.Format.allCases, [.mp4, .proRes422, .proRes422HQ, .proRes4444, .gif])
        XCTAssertEqual(other.fileExtension, "mov")
    }

    func testEachProResType() async throws {
        let model = try await model()
        let expected: [(VideoExportSettings.Format, FourCharCode)] = [
            (.proRes422, kCMVideoCodecType_AppleProRes422),
            (.proRes422HQ, kCMVideoCodecType_AppleProRes422HQ),
            (.proRes4444, kCMVideoCodecType_AppleProRes4444),
        ]
        var sizes: [Int64] = []
        for (format, fourCC) in expected {
            let url = try await export(model, format)
            XCTAssertEqual(url.pathExtension, "mov")
            let actual = try await codec(url)
            XCTAssertEqual(actual, fourCC, "\(format.title)")
            // Uncompressed sound.
            let audioTracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
            let audio = try XCTUnwrap(audioTracks.first)
            let audioFormats = try await audio.load(.formatDescriptions)
            let audioFormat = try XCTUnwrap(audioFormats.first)
            XCTAssertEqual(CMFormatDescriptionGetMediaSubType(audioFormat), kAudioFormatLinearPCM)
            let bytes = Int64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            sizes.append(bytes)
            var settings = VideoExportSettings()
            settings.format = format
            settings.resolution = .p720
            settings.fps = 30
            let estimate = settings.estimatedBytes(duration: model.timelineDuration, canvas: model.plan.outputCanvasSize, hasAudio: true)
            print("PRORES \(format.title): \(bytes) bytes, estimated \(estimate)")
            XCTAssertLessThan(bytes, estimate * 3 / 2, "the estimate isn't far under")
        }
        // An opaque 4444 is opaque.
        let opaque = try await export(model, .proRes4444)
        let corner = try await alpha(opaque, x: 0.01, y: 0.01)
        XCTAssertEqual(corner, 255)
        XCTAssertLessThan(sizes[0], sizes[1], "422 is smaller than 422 HQ")
    }

    func testProRes4444KeepsTransparency() async throws {
        let model = try await model()
        let url = try await export(model, .proRes4444, transparent: true)
        let corner = try await alpha(url, x: 0.01, y: 0.01)
        let middle = try await alpha(url, x: 0.5, y: 0.5)
        XCTAssertEqual(corner, 0, "no background: transparent around the frame")
        XCTAssertEqual(middle, 255, "the video itself is solid")
        // The shadow is see-through, not solid.
        let stage = model.project.stageRect(in: model.plan.outputCanvasSize)
        let canvas = model.plan.outputCanvasSize
        let below = try await alpha(url, x: Double(stage.midX / canvas.width), y: Double((stage.maxY + 8) / canvas.height))
        XCTAssertGreaterThan(below, 10, "the shadow below the frame")
        XCTAssertLessThan(below, 250)
    }

    func testEstimateAndSpaceWarning() throws {
        var settings = VideoExportSettings()
        settings.resolution = .p1080
        settings.fps = 30
        let canvas = CGSize(width: 1920, height: 1080)
        settings.format = .mp4
        let mp4 = settings.estimatedBytes(duration: 60, canvas: canvas, hasAudio: true)
        settings.format = .proRes422
        let p422 = settings.estimatedBytes(duration: 60, canvas: canvas, hasAudio: true)
        settings.format = .proRes422HQ
        let hq = settings.estimatedBytes(duration: 60, canvas: canvas, hasAudio: true)
        settings.format = .proRes4444
        let p4444 = settings.estimatedBytes(duration: 60, canvas: canvas, hasAudio: true)
        XCTAssertLessThan(mp4, p422)
        XCTAssertLessThan(p422, hq)
        XCTAssertLessThan(hq, p4444)
        // A minute of 1080p30 ProRes 422 HQ: about 1.65 GB.
        let audioBytes: Double = 48_000 * 6 * 60
        let hqVideo: Double = 220_000_000 / 8 * 60 * (30 / 29.97)
        XCTAssertEqual(Double(hq), hqVideo + audioBytes, accuracy: 1_000_000)
        settings.fps = 60
        let doubled = Double(settings.estimatedBytes(duration: 60, canvas: canvas, hasAudio: false))
        let p4444Video = Double(p4444) - audioBytes
        XCTAssertEqual(doubled, p4444Video * 2, accuracy: 1_000_000, "twice the frames, twice the size")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prores.mov")
        XCTAssertThrowsError(try VideoExportFiles.checkSpace(for: url, needed: hq, available: hq / 2)) { error in
            XCTAssertTrue(error.localizedDescription.contains("free space"), error.localizedDescription)
        }
        XCTAssertNoThrow(try VideoExportFiles.checkSpace(for: url, needed: hq, available: hq * 2))
    }
}
