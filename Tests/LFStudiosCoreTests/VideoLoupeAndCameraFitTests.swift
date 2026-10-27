import CoreImage
import XCTest
@testable import LFStudiosCore

/// Loupes (a magnifier over one spot, the rest of the frame as it is) and
/// "Fit zooms around camera".
final class VideoLoupeAndCameraFitTests: XCTestCase {
    private let output = CGSize(width: 960, height: 540)

    private func project(duration: Double = 10) -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/loupe.mp4"), duration: duration, sourceSize: CGSize(width: 1600, height: 900))
        project.background = .color(VideoRGBA(1, 1, 1))
        project.outline = false
        project.shadow = 0
        return project
    }

    /// Grey, with a red dot of `radius` source pixels in the middle.
    private func source(radius: CGFloat = 30) -> CIImage {
        let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 900))
        let dot = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 800, y: 450), "inputRadius0": radius - 0.5, "inputRadius1": radius + 0.5,
            "inputColor0": CIColor(red: 1, green: 0, blue: 0), "inputColor1": CIColor.clear,
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 900))
        return dot.composited(over: grey)
    }

    private func render(_ project: VideoDemoProject, at time: Double) -> [UInt8] {
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 10, recording: nil)
        let image = VideoFrameRenderer().render(source: source(), timelineTime: time, plan: plan, outputSize: output)
        let cg = VideoRenderContext.shared.createCGImage(image, from: CGRect(origin: .zero, size: output), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
        return TestImageBytes.rgba(cg)
    }

    private func pixel(_ bytes: [UInt8], _ x: CGFloat, _ y: CGFloat) -> (r: Int, g: Int, b: Int) {
        let i = (Int(y) * Int(output.width) + Int(x)) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    private func loupe(scale: Double = 2, style: VideoLoupeStyle = VideoLoupeStyle()) -> VideoZoomRegion {
        var region = VideoZoomRegion(start: 2, end: 6, scale: scale, followsCursor: false, focusX: 0.5, focusY: 0.5)
        region.loupe = style
        return region
    }

    // MARK: Loupe

    func testALoupeMagnifiesOneSpotAndLeavesTheRest() {
        var plain = project()
        plain.padding = 0.1
        var magnified = plain
        var style = VideoLoupeStyle()
        style.borderWidth = 0
        style.shadow = 0
        magnified.zoomRegions = [loupe(scale: 2, style: style)]

        let before = render(plain, at: 4)
        let after = render(magnified, at: 4)
        let plan = VideoDemoExporter.makePlan(project: plain, sourceDuration: 10, recording: nil)
        let k = output.width / plan.canvasSize.width
        let center = CGPoint(x: plan.stageRect.midX * k, y: plan.stageRect.midY * k)
        let dotRadius = 30 * plan.stageRect.width / 1600 * k

        // 1.5× the dot's radius from the middle: grey without the loupe,
        // red inside it (the dot is twice as big).
        let probe = CGPoint(x: center.x + dotRadius * 1.5, y: center.y)
        XCTAssertLessThan(pixel(before, probe.x, probe.y).r, 160)
        let inside = pixel(after, probe.x, probe.y)
        XCTAssertGreaterThan(inside.r, 200)
        XCTAssertLessThan(inside.g, 60)

        // Away from the loupe, nothing changed — and the camera didn't zoom.
        XCTAssertTrue(VideoDemoExporter.makePlan(project: magnified, sourceDuration: 10, recording: nil).camera.isStatic)
        for corner in [CGPoint(x: 20, y: 20), CGPoint(x: 940, y: 520), CGPoint(x: 120, y: 270)] {
            XCTAssertEqual(pixel(before, corner.x, corner.y).r, pixel(after, corner.x, corner.y).r, "\(corner)")
        }
        // Outside the loupe's time: the plain frame.
        XCTAssertEqual(render(magnified, at: 0.5), render(plain, at: 0.5))
    }

    func testTheLoupeOpensAndClosesSmoothly() {
        var style = VideoLoupeStyle()
        style.animation = 0.4
        let region = loupe(style: style)
        let span = VideoLoupeSpan(region: region, style: style, start: 2, end: 6)
        XCTAssertEqual(span.openness(at: 1.9), 0)
        XCTAssertGreaterThan(span.openness(at: 2.1), 0)
        XCTAssertLessThan(span.openness(at: 2.1), 1)
        XCTAssertEqual(span.openness(at: 4), 1, accuracy: 0.0001)
        XCTAssertLessThan(span.openness(at: 5.9), 1)
        style.animation = 0
        XCTAssertEqual(VideoLoupeSpan(region: region, style: style, start: 2, end: 6).openness(at: 2.01), 1)
    }

    func testLoupeSettingsAreSavedInProjectsAndPresets() throws {
        var style = VideoLoupeStyle()
        style.size = 0.5
        style.shape = .rounded
        style.borderWidth = 0.012
        style.borderColor = VideoRGBA(1, 0.5, 0)
        style.shadow = 0.9
        style.animation = 0.7
        var project = project()
        project.zoomRegions = [loupe(scale: 3, style: VideoLoupeStyle())]
        project.loupeStyle = style

        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded.loupeStyle, style)
        XCTAssertEqual(decoded.zoomRegions[0].loupe, VideoLoupeStyle())

        // A preset keeps the look, and applying it restyles the loupes
        // (each keeps its own magnification).
        let preset = try JSONDecoder().decode(VideoStylePreset.self, from: JSONEncoder().encode(project.style))
        XCTAssertEqual(preset.loupeStyle, style)
        var other = self.project()
        other.zoomRegions = [loupe(scale: 2.5), VideoZoomRegion(start: 7, end: 9)]
        other.apply(style: preset)
        XCTAssertEqual(other.zoomRegions[0].loupe, style)
        XCTAssertEqual(other.zoomRegions[0].scale, 2.5)
        XCTAssertNil(other.zoomRegions[1].loupe, "full zooms stay full")
        XCTAssertEqual(other.loupeStyle, style)

        // A preset from before loupes leaves them alone and still matches.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as! [String: Any]
        json.removeValue(forKey: "loupeStyle")
        let old = try JSONDecoder().decode(VideoStylePreset.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.loupeStyle)
        var kept = other
        kept.apply(style: old)
        XCTAssertEqual(kept.zoomRegions[0].loupe, style)
        var library = VideoStylePresetLibrary()
        XCTAssertTrue(library.add(name: "Old", style: old, includesAspectRatio: false).matches(kept))
    }

    @MainActor
    func testAddLoupeAndItsEditsAreUndoable() async throws {
        VideoTestStorage.isolate()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-loupe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: 6, fps: 30)
        defer {
            VideoDemoDraftStore.delete(for: url)
            try? FileManager.default.removeItem(at: folder)
        }
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        model.seek(to: 1)
        model.addLoupe()
        XCTAssertEqual(model.undoLabel, "Add Loupe")
        let id = try XCTUnwrap(model.project.zoomRegions.first?.id)
        XCTAssertTrue(model.project.zoomRegions[0].isLoupe)
        model.updateLoupe(id, coalesce: "size") { $0.size = 0.4 }
        model.updateLoupe(id, coalesce: "size") { $0.size = 0.45 }
        model.endGesture()
        XCTAssertEqual(model.project.loupeStyle?.size, 0.45, "new loupes take the last look")
        model.setZoomIsLoupe(id, false)
        XCTAssertFalse(model.project.zoomRegions[0].isLoupe)
        model.undo()
        XCTAssertEqual(model.project.zoomRegions[0].loupe?.size, 0.45)
        model.undo()
        XCTAssertEqual(model.project.zoomRegions[0].loupe, VideoLoupeStyle(), "a slider drag is one step")
        model.undo()
        XCTAssertTrue(model.project.zoomRegions.isEmpty, "adding the loupe is one step")
    }

    // MARK: Fit zooms around camera

    /// A full zoom aimed at the bottom right, where a big camera bubble
    /// (that doesn't shrink while zoomed) sits.
    private func coveredProject() -> VideoDemoProject {
        var project = project()
        project.padding = 0.085
        project.webcam.size = 0.4
        project.webcam.shrinkWhenZoomed = false
        project.zoomRegions = [VideoZoomRegion(start: 2, end: 6, scale: 2, followsCursor: false, focusX: 0.93, focusY: 0.9)]
        return project
    }

    /// A loupe over the bottom right corner, under the bubble.
    private func coveredLoupe() -> VideoDemoProject {
        var project = project()
        var region = VideoZoomRegion(start: 2, end: 6, scale: 2, followsCursor: false, focusX: 0.88, focusY: 0.85)
        region.loupe = VideoLoupeStyle()
        project.zoomRegions = [region]
        return project
    }

    private func plan(_ project: VideoDemoProject) -> VideoRenderPlan {
        VideoDemoExporter.makePlan(project: project, sourceDuration: 10, recording: nil, hasWebcam: true)
    }

    func testFindsZoomsUnderTheBubble() {
        let covered = coveredProject()
        XCTAssertTrue(VideoZoomCameraFit.isCovered(covered.zoomRegions[0], plan: plan(covered)))
        var clear = covered
        clear.zoomRegions[0].focusX = 0.3
        clear.zoomRegions[0].focusY = 0.3
        XCTAssertFalse(VideoZoomCameraFit.isCovered(clear.zoomRegions[0], plan: plan(clear)))
        // No camera: nothing to fit around.
        XCTAssertFalse(VideoZoomCameraFit.isCovered(covered.zoomRegions[0], plan: VideoDemoExporter.makePlan(project: covered, sourceDuration: 10, recording: nil)))
    }

    func testShiftingTheFramingClearsTheBubble() {
        var project = coveredLoupe()
        var untouched = project
        untouched.zoomRegions.append(VideoZoomRegion(start: 7, end: 9, scale: 2, followsCursor: false, focusX: 0.3, focusY: 0.3))
        project = untouched
        let result = VideoZoomCameraFit.fit(&project, mode: .shiftFraming, makePlan: plan)
        XCTAssertEqual(result, VideoZoomCameraFit.Result(covered: 1, adjusted: 1, unfixed: 0))
        let zoom = project.zoomRegions[0]
        XCTAssertTrue(zoom.offsetX != 0 || zoom.offsetY != 0)
        XCTAssertNil(zoom.cameraCorner)
        XCTAssertFalse(VideoZoomCameraFit.isCovered(zoom, plan: plan(project)))
        XCTAssertEqual(project.zoomRegions[1], untouched.zoomRegions[1], "a zoom clear of the bubble is left alone")
        XCTAssertEqual(VideoEditorModel.fitMessage(result, mode: .shiftFraming), "Adjusted 1 zoom — ⌘Z to undo.")
    }

    func testAFullZoomAtTheFramesEdgeZoomsDeeperInstead() {
        var project = coveredProject()
        let result = VideoZoomCameraFit.fit(&project, mode: .shiftFraming, makePlan: plan)
        XCTAssertEqual(result.adjusted, 1)
        let zoom = project.zoomRegions[0]
        // Near the corner the framing can't move further out: a deeper zoom
        // pulls the subject in from the corner.
        XCTAssertGreaterThan(zoom.scale, 2)
        XCTAssertLessThanOrEqual(zoom.scale, 3.5)
        XCTAssertFalse(VideoZoomCameraFit.isCovered(zoom, plan: plan(project)))
    }

    func testALoupeMovesOutFromUnderTheBubble() {
        var project = coveredLoupe()
        XCTAssertTrue(VideoZoomCameraFit.isCovered(project.zoomRegions[0], plan: plan(project)))
        let result = VideoZoomCameraFit.fit(&project, mode: .shiftFraming, makePlan: plan)
        XCTAssertEqual(result, VideoZoomCameraFit.Result(covered: 1, adjusted: 1, unfixed: 0))
        let loupe = project.zoomRegions[0]
        XCTAssertTrue(loupe.offsetX < 0 || loupe.offsetY < 0, "moved left or up, away from the bottom right")
        XCTAssertEqual(loupe.scale, 2, "a loupe keeps its magnification")
        XCTAssertFalse(VideoZoomCameraFit.isCovered(loupe, plan: plan(project)))
    }

    func testMovingTheCameraInsteadPicksAFreeCorner() {
        var project = coveredProject()
        let result = VideoZoomCameraFit.fit(&project, mode: .moveCamera, makePlan: plan)
        XCTAssertEqual(result.adjusted, 1)
        XCTAssertEqual(project.zoomRegions[0].cameraCorner, .bottomLeft, "across first")
        XCTAssertEqual(project.zoomRegions[0].offsetX, 0)

        // The bubble slides over while the zoom plays and comes back after.
        let plan = plan(project)
        let home = VideoFrameRenderer.webcamRect(project.webcam, outputSize: output)
        let during = VideoFrameRenderer.movedWebcamRect(project.webcam, plan: plan, time: 4, outputSize: output, cameraScale: 1)
        let after = VideoFrameRenderer.movedWebcamRect(project.webcam, plan: plan, time: 8, outputSize: output, cameraScale: 1)
        XCTAssertLessThan(during.midX, output.width / 2)
        XCTAssertEqual(after, home)
    }

    func testCountsAndMessages() {
        XCTAssertEqual(VideoEditorModel.fitMessage(.init(), mode: .shiftFraming), "No zooms are under the camera")
        XCTAssertEqual(VideoEditorModel.fitMessage(.init(covered: 5, adjusted: 4, unfixed: 1), mode: .shiftFraming),
                       "Adjusted 4 zooms — ⌘Z to undo. 1 zoom can't move far enough — try Move the Camera Instead.")
        XCTAssertEqual(VideoEditorModel.fitMessage(.init(covered: 2, adjusted: 0, unfixed: 2), mode: .moveCamera),
                       "2 zooms have no free corner for the camera.")
    }

    func testFittedZoomsSaveAndLoad() throws {
        var project = coveredProject()
        _ = VideoZoomCameraFit.fit(&project, mode: .shiftFraming, makePlan: plan)
        project.zoomRegions[0].cameraCorner = .topLeft
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded.zoomRegions, project.zoomRegions)
    }
}
