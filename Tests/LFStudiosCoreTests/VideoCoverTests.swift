import AppKit
import AVFoundation
import XCTest
@testable import LFStudiosCore

/// Cover (1.15.0): a frame or a picture as the exported file's artwork,
/// MP4 and MOV, range exports, and the commands.
@MainActor
final class VideoCoverTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-cover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private func colour(_ jpeg: Data) throws -> (r: Double, g: Double, b: Double) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return VideoInspection.color(of: image, x: 0.5, y: 0.5)
    }

    private func redThenBlue() async throws -> VideoDemoProject {
        let source = directory.appendingPathComponent("two.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.red, 1), (.blue, 1)])
        return VideoInspection.project(for: source, seconds: 2, size: CGSize(width: 320, height: 180))
    }

    func testAFrameCoverInMP4AndMOV() async throws {
        var project = try await redThenBlue()
        let plain = directory.appendingPathComponent("plain.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: plain, settings: VideoInspection.mp4Settings())
        let none = await VideoCoverEmbedder.artwork(of: plain)
        XCTAssertNil(none, "no cover unless picked")
        project.cover = VideoCover(time: 1.5)
        XCTAssertTrue(project.needsFormat4)
        for container in VideoExportSettings.Container.allCases {
            var settings = VideoInspection.mp4Settings()
            settings.container = container
            let output = directory.appendingPathComponent("cover.\(settings.fileExtension)")
            let warnings = try await VideoDemoExporter.export(project: project, destinationURL: output, settings: settings)
            XCTAssertTrue(warnings.isEmpty, "\(warnings)")
            let artwork = await VideoCoverEmbedder.artwork(of: output)
            XCTAssertGreaterThan(try colour(try XCTUnwrap(artwork, "\(container)")).b, 0.7, "the blue frame at 1.5 s (\(container))")
            let duration = try await AVURLAsset(url: output).load(.duration).seconds
            XCTAssertEqual(duration, 2, accuracy: 0.1, "the video itself is untouched")
        }
        // A range from 1 s: the cover is still the frame at 1.5 s.
        let part = directory.appendingPathComponent("part.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: part, settings: VideoInspection.mp4Settings(), range: .timeline(0.9...2))
        let partArtwork = await VideoCoverEmbedder.artwork(of: part)
        XCTAssertGreaterThan(try colour(try XCTUnwrap(partArtwork)).b, 0.7)
    }

    func testAPictureCover() async throws {
        var project = try await redThenBlue()
        let picture = directory.appendingPathComponent("green.png")
        try VideoInspection.writePNG(to: picture, size: CGSize(width: 64, height: 64), color: .green)
        project.cover = VideoCover(imagePath: picture.path)
        let output = directory.appendingPathComponent("picture.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let artwork = await VideoCoverEmbedder.artwork(of: output)
        XCTAssertGreaterThan(try colour(try XCTUnwrap(artwork)).g, 0.6)
    }

    func testCommands() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 3)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        model.seek(to: 1.2)
        var depth = model.undoDepth
        model.setCoverFrame()
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.project.cover?.time ?? 0, 1.2, accuracy: 0.05)
        let picture = directory.appendingPathComponent("mine.png")
        try VideoInspection.writePNG(to: picture, size: CGSize(width: 32, height: 32), color: .orange)
        depth = model.undoDepth
        XCTAssertTrue(model.setCoverPicture(picture))
        XCTAssertEqual(model.undoDepth, depth + 1)
        let stored = try XCTUnwrap(model.project.cover?.imagePath)
        XCTAssertTrue(VideoAssetStore.isStored(stored), "LF Studios' own copy")
        XCTAssertTrue(model.project.assetPaths.contains(stored), "Clean Up keeps it")
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: try JSONEncoder().encode(model.project))
        XCTAssertEqual(decoded.cover, model.project.cover)
        model.clearCover()
        XCTAssertNil(model.project.cover)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(model.project), as: UTF8.self).contains("\"cover\""))
    }
}
