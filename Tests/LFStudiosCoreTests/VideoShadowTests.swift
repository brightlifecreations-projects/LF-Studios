import CoreImage
import XCTest
@testable import LFStudiosCore

/// The fine-tuned frame shadow: off until it's switched on, old projects
/// and presets keep the classic shadow, and each control does what it says.
final class VideoShadowTests: XCTestCase {
    private let output = CGSize(width: 960, height: 540)

    private func project() -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/shadow.mp4"), duration: 4, sourceSize: CGSize(width: 1600, height: 1000))
        project.background = .color(VideoRGBA(1, 1, 1))
        project.outline = false
        project.padding = 0.12
        return project
    }

    /// One frame of a mid-grey recording, as RGBA bytes.
    private func render(_ project: VideoDemoProject) -> (bytes: [UInt8], stage: CGRect) {
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 4, recording: nil)
        let source = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        let image = VideoFrameRenderer().render(source: source, timelineTime: 1, plan: plan, outputSize: output)
        let cg = VideoRenderContext.shared.createCGImage(image, from: CGRect(origin: .zero, size: output), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
        let k = output.width / plan.canvasSize.width
        let stage = CGRect(x: plan.stageRect.minX * k, y: plan.stageRect.minY * k, width: plan.stageRect.width * k, height: plan.stageRect.height * k)
        return (TestImageBytes.rgba(cg), stage)
    }

    /// Brightness 0…1 at a point (top-left origin).
    private func brightness(_ bytes: [UInt8], _ x: CGFloat, _ y: CGFloat) -> Double {
        let i = (Int(y) * Int(output.width) + Int(x)) * 4
        return (Double(bytes[i]) + Double(bytes[i + 1]) + Double(bytes[i + 2])) / 765
    }

    private func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count) / 255
    }

    func testNewAndOldProjectsUseTheClassicShadow() throws {
        XCTAssertNil(VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/a.mp4")).shadowStyle)
        XCTAssertNil(VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/a.mp4")).shadowStyle)
        // A project saved before fine-tuning existed: no key, classic shadow,
        // and saving it again doesn't add one.
        let old = project()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        XCTAssertNil(json["shadowStyle"])
        json["shadow"] = 0.7
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.shadowStyle)
        XCTAssertEqual(decoded.shadow, 0.7)
        XCTAssertNil(VideoDemoExporter.makePlan(project: decoded, sourceDuration: 4, recording: nil).shadowStyle, "drawn by the classic code")
    }

    func testFineTuneStartsWhereTheSliderIs() {
        var project = project()
        project.shadow = 0.55
        let classic = render(project)
        project.setShadowFineTuned(true)
        XCTAssertEqual(project.shadowStyle, .matching(strength: 0.55))
        XCTAssertEqual(project.shadowStyle?.inset, false)
        let tuned = render(project)
        let difference = meanDifference(classic.bytes, tuned.bytes)
        XCTAssertLessThan(difference, 0.002, "switching fine-tune on changes nothing you'd see (\(difference))")
        project.setShadowFineTuned(false)
        XCTAssertNil(project.shadowStyle)

        // No shadow on the slider: fine-tune starts with none too.
        project.shadow = 0
        project.setShadowFineTuned(true)
        XCTAssertEqual(project.shadowStyle?.isVisible, false)
    }

    func testAngleDistanceOpacityAndColor() {
        var project = project()
        project.shadowStyle = VideoShadowStyle(angle: 0, distance: 40, softness: 10, opacity: 1)
        var (bytes, stage) = render(project)
        // Falling to the right: dark just right of the frame, white on its left.
        XCTAssertLessThan(brightness(bytes, stage.maxX + 6, stage.midY), 0.6)
        XCTAssertGreaterThan(brightness(bytes, stage.minX - 6, stage.midY), 0.97)

        project.shadowStyle?.angle = 180
        (bytes, stage) = render(project)
        XCTAssertLessThan(brightness(bytes, stage.minX - 6, stage.midY), 0.6, "180°: to the left")
        XCTAssertGreaterThan(brightness(bytes, stage.maxX + 6, stage.midY), 0.97)

        project.shadowStyle?.opacity = 0
        let none = render(project)
        var flat = project
        flat.shadowStyle = nil
        flat.shadow = 0
        XCTAssertLessThan(meanDifference(none.bytes, render(flat).bytes), 0.0005, "opacity 0: no shadow")

        project.shadowStyle = VideoShadowStyle(angle: 90, distance: 30, softness: 6, opacity: 1, color: VideoRGBA(1, 0, 0))
        (bytes, stage) = render(project)
        let i = (Int(stage.maxY + 8) * Int(output.width) + Int(stage.midX)) * 4
        XCTAssertGreaterThan(Int(bytes[i]), 200, "a red shadow below")
        XCTAssertLessThan(Int(bytes[i + 1]), 90)
    }

    func testInsetIsASoftInnerEdge() {
        var project = project()
        project.cornerRadius = 0
        project.shadowStyle = VideoShadowStyle(angle: 90, distance: 12, softness: 16, opacity: 0.8, inset: true)
        let (bytes, stage) = render(project)
        // Nothing outside the frame…
        XCTAssertGreaterThan(brightness(bytes, stage.midX, stage.maxY + 10), 0.97)
        // …a darker edge just inside its top (the light comes from above)…
        let edge = brightness(bytes, stage.midX, stage.minY + 3)
        let middle = brightness(bytes, stage.midX, stage.midY)
        XCTAssertLessThan(edge, middle - 0.1, "inner edge \(edge) vs middle \(middle)")
        // …and the middle of the recording untouched.
        XCTAssertEqual(middle, 0.5, accuracy: 0.03)
    }

    func testNoShadowOnAFullFrame() {
        var project = project()
        project.padding = 0
        project.shadowStyle = VideoShadowStyle(angle: 90, distance: 30, softness: 10, opacity: 1, inset: true)
        XCTAssertNil(project.effectiveShadowStyle)
    }

    func testPresetsKeepTheShadow() throws {
        var project = project()
        project.shadowStyle = VideoShadowStyle(angle: 135, distance: 22, softness: 48, opacity: 0.4, color: VideoRGBA(0.1, 0.2, 0.6), inset: true)
        let style = project.style
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(VideoStylePreset.self, from: data)
        XCTAssertEqual(decoded.shadowStyle, project.shadowStyle)

        var other = self.project()
        other.apply(style: decoded)
        XCTAssertEqual(other.shadowStyle, project.shadowStyle)

        // A preset saved before fine-tuning: the classic shadow.
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "shadowStyle")
        let old = try JSONDecoder().decode(VideoStylePreset.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.shadowStyle)
        other.apply(style: old)
        XCTAssertNil(other.shadowStyle)

        var library = VideoStylePresetLibrary()
        let preset = library.add(name: "Deep", style: style, includesAspectRatio: false)
        XCTAssertTrue(preset.matches(project))
        project.shadowStyle?.distance = 10
        XCTAssertFalse(preset.matches(project), "a changed shadow no longer matches")
    }

    @MainActor
    func testFineTuneIsOneUndoStep() async throws {
        VideoTestStorage.isolate()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-shadow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: 2, fps: 30)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        model.setStyle { $0.padding = 0.1 }
        model.setStyle { $0.setShadowFineTuned(true) }
        XCTAssertNotNil(model.project.shadowStyle)
        model.setStyle(coalesce: "shadow-angle") { $0.shadowStyle?.angle = 30 }
        model.setStyle(coalesce: "shadow-angle") { $0.shadowStyle?.angle = 40 }
        model.endGesture()
        model.undo()
        XCTAssertEqual(model.project.shadowStyle?.angle, 90, "a slider drag is one step")
        model.undo()
        XCTAssertNil(model.project.shadowStyle)
    }
}
