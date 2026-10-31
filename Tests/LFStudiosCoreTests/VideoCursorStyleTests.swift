import CoreImage
import XCTest
@testable import LFStudiosCore

/// Cursor styles: classic stays the default and draws the recording's own
/// pointer; every other style has its own arrow, I-beam and hand; the
/// choice is saved in projects and presets, a custom picture with
/// "Include media".
final class VideoCursorStyleTests: XCTestCase {
    private let output = CGSize(width: 800, height: 450)

    private func project() -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/cursor.mp4"), duration: 4, sourceSize: CGSize(width: 1600, height: 1000))
        project.background = .color(VideoRGBA(0.2, 0.4, 0.8))
        project.nativeCursorVisible = false
        project.cursor.visible = true
        project.cursor.motionBlur = false
        project.cursor.hideWhenIdle = false
        project.cursorSamples = [VideoDemoCursorSample(time: 0, x: 0.5, y: 0.5), VideoDemoCursorSample(time: 4, x: 0.5, y: 0.5)]
        return project
    }

    private func render(_ project: VideoDemoProject) -> [UInt8] {
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 4, recording: nil)
        let source = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        let image = VideoFrameRenderer().render(source: source, timelineTime: 1, plan: plan, outputSize: output)
        let cg = VideoRenderContext.shared.createCGImage(image, from: CGRect(origin: .zero, size: output), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
        return TestImageBytes.rgba(cg)
    }

    func testClassicIsTheDefault() {
        XCTAssertEqual(VideoCursorSettings().style, .classic)
        XCTAssertNil(VideoCursorStyleArtwork.make(settings: VideoCursorSettings()), "classic draws the recording's own pointer")
        XCTAssertEqual(VideoStylePreset.factory.cursor.style, .classic)
    }

    func testEveryStyleHasAnArrowATextBeamAndAHand() {
        for style in VideoCursorStyle.allCases where style != .classic && style != .custom {
            var settings = VideoCursorSettings()
            settings.style = style
            let artwork = try! XCTUnwrap(VideoCursorStyleArtwork.make(settings: settings))
            var ids = Set<String>()
            for kind in [VideoCursorKind.arrow, .text, .hand] {
                let shape = artwork.shape(for: kind)
                ids.insert(shape.id)
                XCTAssertGreaterThan(shape.size.width, 4)
                XCTAssertGreaterThan(shape.mips[0].extent.width, 100, "drawn large, sharp when zoomed")
                // The hot spot is on the drawing.
                XCTAssertTrue(CGRect(origin: .zero, size: shape.size).contains(shape.hotSpot))
                let cg = VideoRenderContext.shared.createCGImage(shape.mips[0], from: shape.mips[0].extent)!
                XCTAssertTrue(TestImageBytes.rgba(cg).enumerated().contains { $0.offset % 4 == 3 && $0.element > 200 }, "\(style) \(kind) draws something")
            }
            XCTAssertEqual(ids.count, 3, "\(style): three different pointers")
        }
    }

    func testCapturedPointersAreToldApart() {
        // An arrow (tip at the top left), an I-beam (narrow, points from its
        // middle), the pointing hand (fingertip near the top).
        XCTAssertEqual(VideoCursorKind.guess(size: CGSize(width: 17, height: 23), hotSpot: CGPoint(x: 4, y: 4)), .arrow)
        XCTAssertEqual(VideoCursorKind.guess(size: CGSize(width: 9, height: 18), hotSpot: CGPoint(x: 4, y: 9)), .text)
        XCTAssertEqual(VideoCursorKind.guess(size: CGSize(width: 32, height: 32), hotSpot: CGPoint(x: 13, y: 8)), .hand)
        XCTAssertEqual(VideoCursorKind.guess(size: CGSize(width: 24, height: 24), hotSpot: CGPoint(x: 12, y: 12)), .arrow, "a resize pointer uses the style's arrow")
    }

    func testEachStyleLooksDifferentInTheVideo() {
        var frames: [VideoCursorStyle: [UInt8]] = [:]
        for style in VideoCursorStyle.allCases where style != .custom {
            var project = project()
            project.cursor.style = style
            frames[style] = render(project)
        }
        for (a, b) in [(VideoCursorStyle.classic, VideoCursorStyle.white), (.white, .outlined), (.outlined, .touch), (.touch, .ring), (.ring, .classic)] {
            XCTAssertNotEqual(frames[a], frames[b], "\(a) and \(b)")
        }
    }

    func testStylesAreSavedInProjectsAndPresets() throws {
        var project = project()
        project.cursor.style = .ring
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded.cursor.style, .ring)
        let preset = try JSONDecoder().decode(VideoStylePreset.self, from: JSONEncoder().encode(project.style))
        XCTAssertEqual(preset.cursor.style, .ring)
        var other = self.project()
        other.apply(style: preset)
        XCTAssertEqual(other.cursor.style, .ring)

        // Settings saved before styles existed: classic.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(VideoCursorSettings())) as! [String: Any]
        XCTAssertNil(json["style"])
        json["size"] = 2.2
        let old = try JSONDecoder().decode(VideoCursorSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.style, .classic)
        XCTAssertEqual(old.size, 2.2)
    }

    func testCustomImageWithItsHotSpot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-cursor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("star.png")
        let star = CIImage(color: CIColor(red: 1, green: 0.8, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        try VideoTestSupport.writePNG(star, size: CGSize(width: 64, height: 64), to: png)

        var project = project()
        project.cursor.style = .custom
        project.cursor.customImage = VideoCursorImage(path: png.path, name: "star.png", hotSpotX: 0.5, hotSpotY: 0.5, aspect: 1)
        let artwork = try XCTUnwrap(VideoCursorStyleArtwork.make(settings: project.cursor))
        let shape = artwork.shape(for: .text)
        XCTAssertEqual(shape.id, "custom", "one picture for every pointer")
        XCTAssertEqual(shape.hotSpot.x, shape.size.width / 2, accuracy: 0.01)

        // The picture is centered on the pointer's spot.
        let bytes = render(project)
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 4, recording: nil)
        let k = output.width / plan.canvasSize.width
        let i = (Int(plan.stageRect.midY * k) * Int(output.width) + Int(plan.stageRect.midX * k)) * 4
        XCTAssertGreaterThan(Int(bytes[i]), 220)
        XCTAssertGreaterThan(Int(bytes[i + 1]), 170)
        XCTAssertLessThan(Int(bytes[i + 2]), 60)

        // Missing picture: the recording's own pointer, no crash.
        project.cursor.customImage?.path = folder.appendingPathComponent("gone.png").path
        XCTAssertNil(VideoCursorStyleArtwork.make(settings: project.cursor))
    }

    func testCustomImageTravelsWithIncludeMedia() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-cursor-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("rec.mp4")
        try Data([0, 1, 2]).write(to: video)
        let png = folder.appendingPathComponent("hand.png")
        try VideoTestSupport.writePNG(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8)), size: CGSize(width: 8, height: 8), to: png)

        var project = VideoDemoProject.make(sourceURL: video, duration: 1)
        project.cursor.style = .custom
        project.cursor.customImage = VideoCursorImage(path: png.path, name: "hand.png", hotSpotX: 0.2, hotSpotY: 0.1, aspect: 1)
        let contents = VideoProjectContents(project: project, recording: nil, sourceRecordings: [:])
        XCTAssertTrue(contents.paths.contains(png.path))

        let package = folder.appendingPathComponent("Demo.lfs")
        _ = try VideoProjectPackage.save(contents, to: package, mode: .included)
        try FileManager.default.removeItem(at: png)
        let opened = try VideoProjectPackage.open(package)
        let image = try XCTUnwrap(opened.contents.project.cursor.customImage)
        XCTAssertTrue(image.path.hasPrefix(package.path), "the picture is inside the project: \(image.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
        XCTAssertEqual(image.hotSpotX, 0.2)
    }
}
