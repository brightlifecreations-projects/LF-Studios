import AVFoundation
import XCTest
@testable import LFStudiosCore

/// Proxies (1.15.0): ProRes 422 Proxy at half size, the estimate, the
/// editor plays them while exports read the originals, Clean Up removes
/// them, and a Mac without them plays the originals.
@MainActor
final class VideoProxiesTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-proxies-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testSizesAndTheEstimate() {
        XCTAssertEqual(VideoProxies.halfSize(CGSize(width: 1920, height: 1080)), CGSize(width: 960, height: 540))
        XCTAssertEqual(VideoProxies.halfSize(CGSize(width: 1366, height: 769)), CGSize(width: 684, height: 384), "even numbers")
        let minute = VideoProxies.estimatedBytes(size: CGSize(width: 1920, height: 1080), frameRate: 30, duration: 60)
        XCTAssertEqual(Double(minute), 45e6 / 4 * 60 / 8 * 30 / 29.97, accuracy: 1e6, "a quarter of 45 Mbit/s for a minute")
    }

    func testCreatingAProxy() async throws {
        let original = directory.appendingPathComponent("phone.mp4")
        // Stored sideways, turned upright by players.
        try await VideoInspection.writeSplitVideo(to: original, size: CGSize(width: 320, height: 180), left: .red, right: .blue, seconds: 2, transform: CGAffineTransform(rotationAngle: .pi / 2))
        XCTAssertNil(VideoProxies.existing(for: original))
        let proxy = try await VideoProxies.create(from: original)
        XCTAssertEqual(VideoProxies.existing(for: original), proxy)
        XCTAssertEqual(proxy.deletingLastPathComponent().standardizedFileURL, VideoProxies.folder.standardizedFileURL, "with LF Studios' caches")
        let asset = AVURLAsset(url: proxy)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(videoTracks.first)
        let natural = try await track.load(.naturalSize)
        XCTAssertEqual(natural, CGSize(width: 160, height: 90))
        let formats = try await track.load(.formatDescriptions)
        XCTAssertEqual(try XCTUnwrap(formats.first).mediaSubType, .proRes422Proxy)
        let transform = try await track.load(.preferredTransform)
        XCTAssertEqual(transform.b, 1, accuracy: 0.001, "turned like the original")
        XCTAssertEqual(transform.c, -1, accuracy: 0.001)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty, "picture only")
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.05)
        // A changed original needs a new one.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: original.path)
        XCTAssertNil(VideoProxies.existing(for: original))
    }

    /// The editor plays the proxy (here blue on purpose); the export reads
    /// the original (red).
    func testTheEditorPlaysProxiesExportsUseOriginals() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.red, 2)], toneSeconds: 2)
        let fake = directory.appendingPathComponent("blue.mov")
        try await VideoInspection.writeColorVideo(to: fake, size: CGSize(width: 160, height: 90), colors: [(.blue, 2)])
        try FileManager.default.createDirectory(at: VideoProxies.folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: VideoProxies.url(for: url))
        try FileManager.default.copyItem(at: fake, to: VideoProxies.url(for: url))
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        model.usesProxies = true
        await model.load()
        let playing = try XCTUnwrap(model.playback.source)
        XCTAssertNotNil(model.playback.originalSource, "playing the proxy")
        let playingSize = try await playing.video.load(.naturalSize)
        XCTAssertEqual(playingSize, CGSize(width: 160, height: 90))
        XCTAssertFalse(playing.audio.isEmpty, "the original's sound")
        XCTAssertEqual(model.project.sourceWidth, 320, "the project keeps the original's size")
        // Never in the project (so never in a handoff or Include media).
        let saved = String(decoding: try JSONEncoder().encode(model.project), as: UTF8.self)
        XCTAssertFalse(saved.contains("VideoProxies"))
        XCTAssertFalse(model.project.assetPaths.contains { $0.contains("VideoProxies") })
        // The export: the original.
        let output = directory.appendingPathComponent("out.mp4")
        var project = model.project
        project.padding = 0
        project.aspectPreset = .source
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let middle = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 1), x: 0.5, y: 0.5)
        XCTAssertGreaterThan(middle.r, 0.7, "red: the original \(middle)")
        XCTAssertLessThan(middle.b, 0.3)
        // Off: the original again.
        model.usesProxies = false
        await model.applyProxySetting()
        XCTAssertNil(model.playback.originalSource)
    }

    func testAnotherMacAndCleanUp() async throws {
        let url = directory.appendingPathComponent("plain.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 1)])
        // No proxy here: the original plays.
        let tracks = try await VideoSourceTracks.load(url: url)
        let swapped = await VideoProxies.swapping(tracks)
        XCTAssertTrue(swapped.video === tracks.video)
        // Clean Up lists and removes every proxy, even one made just now.
        let proxy = try await VideoProxies.create(from: url)
        let plan = VideoDataCleanup.plan(finder: .nowhere)
        XCTAssertTrue(plan.proxies.map(\.standardizedFileURL).contains(proxy.standardizedFileURL))
        XCTAssertTrue(plan.summary.contains("1"))
        VideoDataCleanup.perform(plan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: proxy.path))
    }
}
