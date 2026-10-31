import AppKit
import AVFoundation
import XCTest
@testable import LFStudiosCore

/// The export window (1.15.0): name and folder, MP4 or MOV, codec, bit
/// rate (lower / recommended / higher / custom), 25 and 50 fps.
@MainActor
final class VideoExportWindowTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-exportwindow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testChoices() {
        var settings = VideoExportSettings()
        XCTAssertEqual(settings.movieFileType, .mp4)
        settings.container = .mov
        XCTAssertEqual(settings.movieFileType, .mov)
        XCTAssertEqual(settings.fileExtension, "mov")
        settings.format = .proRes422
        settings.container = .mp4
        XCTAssertEqual(settings.movieFileType, .mov, "ProRes is always a .mov")
        settings.format = .mp4
        // Bit rate: the three qualities, or your own.
        XCTAssertEqual(settings.bitRate, .recommended)
        settings.bitRate = .higher
        XCTAssertEqual(settings.quality, .studio)
        settings.bitRate = .custom
        XCTAssertNotNil(settings.customBitrate)
        settings.customBitrate = 12_000_000
        XCTAssertEqual(settings.videoBitrate(for: CGSize(width: 3840, height: 2160)), 12_000_000, "your number, whatever the size")
        settings.customBitrate = 900_000_000
        XCTAssertEqual(settings.videoBitrate(for: CGSize(width: 1920, height: 1080)), 200_000_000)
        settings.bitRate = .lower
        XCTAssertNil(settings.customBitrate)
        XCTAssertEqual(settings.quality, .web)
        XCTAssertEqual(VideoExportSettings.frameRates, [24, 25, 30, 50, 60])
        XCTAssertEqual(VideoExportSettings.Resolution.allCases.last?.rawValue, 2160, "up to 4K")
    }

    func testAnHEVCMovAt25fpsWithItsOwnBitRate() async throws {
        let source = directory.appendingPathComponent("tone.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.red, 1), (.blue, 1)], toneSeconds: 2)
        let project = VideoInspection.project(for: source, seconds: 2, size: CGSize(width: 320, height: 180))
        var settings = VideoInspection.mp4Settings(fps: 25)
        settings.codec = .hevc
        settings.container = .mov
        settings.customBitrate = 2_000_000
        let output = directory.appendingPathComponent("out.mov")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: settings)
        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let formats = try await track.load(.formatDescriptions)
        XCTAssertEqual(try XCTUnwrap(formats.first).mediaSubType, .hevc)
        let rate = try await track.load(.nominalFrameRate)
        XCTAssertEqual(Double(rate), 25, accuracy: 0.5)
        let type = try output.resourceValues(forKeys: [.contentTypeKey]).contentType
        XCTAssertEqual(type, .quickTimeMovie)
    }

    func testNameAndFolder() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 1)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let folder = directory.appendingPathComponent("Exports", isDirectory: true)
        model.exportFolderPath = folder.path
        XCTAssertEqual(model.exportName, model.exportBaseName)
        model.exportName = "Launch/teaser"
        XCTAssertEqual(model.exportName, "Launch-teaser", "no folders in a name")
        let settings = VideoExportSettings()
        let first = try XCTUnwrap(model.exportDestination(settings: settings) { _ in XCTFail("nothing there yet"); return .cancel })
        XCTAssertEqual(first, folder.appendingPathComponent("Launch-teaser.mp4"))
        try Data().write(to: first)
        XCTAssertEqual(model.exportDestination(settings: settings) { _ in .alertFirstButtonReturn }, first, "Replace")
        XCTAssertEqual(model.exportDestination(settings: settings) { _ in .alertSecondButtonReturn }, folder.appendingPathComponent("Launch-teaser 2.mp4"), "Keep Both")
        XCTAssertNil(model.exportDestination(settings: settings) { _ in .alertThirdButtonReturn }, "Cancel")
        model.exportName = model.exportBaseName
        XCTAssertNil(model.exportNameEdited)
    }
}
