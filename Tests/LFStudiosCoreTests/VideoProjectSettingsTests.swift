import AVFoundation
import XCTest
@testable import LFStudiosCore

/// Project settings (1.16.0): resolution, frame rate and colour space, set
/// only by hand; export starts from them; older projects are unchanged.
@MainActor
final class VideoProjectSettingsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-projset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeModel() async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 2)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        return model
    }

    func testNeverOpensByItselfAndOldProjectsKeepTheirExport() async throws {
        let model = try await makeModel()
        XCTAssertFalse(model.isProjectSettingsPresented, "only a click on the name opens it")
        XCTAssertNil(model.project.projectSettings)
        // Without settings, the export window keeps its last choices.
        model.exportSettings.resolution = .p720
        model.exportSettings.fps = 25
        model.isExportPresented = true
        XCTAssertEqual(model.exportSettings.resolution, .p720)
        XCTAssertEqual(model.exportSettings.fps, 25)
        XCTAssertEqual(model.shownProjectSettings, VideoProjectSettings(resolution: .p720, frameRate: 25, colorSpace: .rec709), "the window shows what it exports at now")
        XCTAssertFalse(model.project.needsFormat4)
    }

    func testSettingThemIsOneStepAndExportStartsFromThem() async throws {
        let model = try await makeModel()
        XCTAssertTrue(model.perform(.showProjectSettings))
        XCTAssertTrue(model.isProjectSettingsPresented)
        model.isProjectSettingsPresented = false

        let depth = model.undoDepth
        let chosen = VideoProjectSettings(resolution: .p2160, frameRate: 24, colorSpace: .displayP3)
        XCTAssertTrue(model.perform(.projectSettings(chosen)))
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step")
        XCTAssertEqual(model.project.projectSettings, chosen)
        XCTAssertTrue(model.project.needsFormat4)
        // The export window opens with them, after something else was chosen there.
        model.exportSettings.resolution = .p720
        model.exportSettings.fps = 60
        model.isExportPresented = true
        XCTAssertEqual(model.exportSettings.resolution, .p2160)
        XCTAssertEqual(model.exportSettings.fps, 24)
        XCTAssertEqual(model.exportSettings.colorSpace, .displayP3)
        model.isExportPresented = false

        model.undo()
        XCTAssertNil(model.project.projectSettings)
    }

    func testTheSavedProject() throws {
        var project = VideoInspection.project(for: directory.appendingPathComponent("rec.mp4"), seconds: 2, size: CGSize(width: 320, height: 180))
        let plain = String(decoding: try JSONEncoder().encode(project), as: UTF8.self)
        XCTAssertFalse(plain.contains("projectSettings"), "never set: not in the file")
        project.projectSettings = VideoProjectSettings(resolution: .p1440, frameRate: 50, colorSpace: .rec709)
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: try JSONEncoder().encode(project))
        XCTAssertEqual(decoded.projectSettings, project.projectSettings)
        XCTAssertEqual(VideoProjectSettings(resolution: .p1080, frameRate: 17, colorSpace: .rec709).frameRate, 30, "only the rates the export offers")
    }

    private func primaries(of url: URL) async throws -> String? {
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let description = try XCTUnwrap(descriptions.first)
        return CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String
    }

    func testDisplayP3ExportsAreTaggedSoAndLookTheSame() async throws {
        let source = directory.appendingPathComponent("red.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 640, height: 360), colors: [(.red, 1)])
        let project = VideoInspection.project(for: source, seconds: 1, size: CGSize(width: 640, height: 360))
        var settings = VideoInspection.mp4Settings()
        let standard = directory.appendingPathComponent("709.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: standard, settings: settings)
        settings.colorSpace = .displayP3
        let wide = directory.appendingPathComponent("p3.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: wide, settings: settings)

        let standardPrimaries = try await primaries(of: standard)
        let widePrimaries = try await primaries(of: wide)
        XCTAssertEqual(standardPrimaries, kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String, "as before")
        XCTAssertEqual(widePrimaries, kCMFormatDescriptionColorPrimaries_P3_D65 as String)
        // The same red: in the P3 file it's written as P3 values (the
        // frames come back without conversion, so compare numbers).
        let a = VideoInspection.color(of: try VideoInspection.frame(of: standard, at: 0.5), x: 0.5, y: 0.5, radius: 4)
        let b = VideoInspection.color(of: try VideoInspection.frame(of: wide, at: 0.5), x: 0.5, y: 0.5, radius: 4)
        let red = try XCTUnwrap(CGColor(srgbRed: a.r, green: a.g, blue: a.b, alpha: 1)
            .converted(to: try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)), intent: .relativeColorimetric, options: nil)?.components)
        XCTAssertEqual(red[0], b.r, accuracy: 0.05, "\(a) as P3 is \(red), the file has \(b)")
        XCTAssertEqual(red[1], b.g, accuracy: 0.05)
        XCTAssertEqual(red[2], b.b, accuracy: 0.05)
    }
}
