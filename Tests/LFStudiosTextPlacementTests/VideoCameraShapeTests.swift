import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import LFStudiosCore

/// Camera shape (1.10.0): every shape and ratio, Free, the shape and place
/// chosen before recording, and what an older project keeps
/// (VideoFeatures.swift, VideoCameraSetup.swift, VideoRenderer.swift).
@Suite("Camera shape")
struct VideoCameraShapeTests {
    typealias RGB = (r: Double, g: Double, b: Double)
    static let output = CGSize(width: 960, height: 540)
    static let white: RGB = (1, 1, 1)

    private func project(_ change: (inout VideoWebcamSettings) -> Void) -> VideoDemoProject {
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/shape.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        project.background = .color(VideoRGBA(1, 1, 1))
        project.padding = 0.2
        project.webcam.size = 0.4
        change(&project.webcam)
        return project
    }

    /// The frame's pixels and where the bubble should be (top-left origin).
    private func render(_ project: VideoDemoProject, size: CGSize = output) throws -> (bytes: [UInt8], bubble: CGRect, width: Int) {
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 4, recording: nil, hasWebcam: true)
        var options = VideoFrameRenderer.Options(frameRate: 30)
        options.webcamFrame = TestVideos.quadrantImage()
        let screen = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.25)).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
        let image = VideoFrameRenderer().render(source: screen, timelineTime: 2, plan: plan, outputSize: size, options: options)
        let cgImage = try #require(CIContext().createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
        let rect = VideoFrameRenderer.webcamRect(project.webcam, outputSize: size)
        return (TestVideos.rgba(cgImage), CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height), Int(size.width))
    }

    private func color(_ frame: (bytes: [UInt8], bubble: CGRect, width: Int), _ x: CGFloat, _ y: CGFloat) -> RGB {
        TestVideos.pixel(frame.bytes, width: frame.width, x: Int(x), y: Int(y))
    }

    private func isCamera(_ c: RGB) -> Bool {
        TestVideos.quadrantColors.contains { TestVideos.close(c, $0, within: 0.12) }
    }

    // MARK: Every shape and ratio

    static let ratios: [(VideoWebcamSettings.Shape, CGFloat)] = [
        (.circle, 1), (.rectangle, 4 / 3), (.square, 1), (.landscape, 16 / 9), (.portrait, 9 / 16), (.classic, 4 / 3), (.classicPortrait, 3 / 4), (.free, 1),
    ]

    @Test func everyShapeHasItsRatio() {
        for (shape, aspect) in Self.ratios {
            var settings = VideoWebcamSettings()
            settings.shape = shape
            #expect(abs(settings.effectiveAspect - aspect) < 0.0001, "\(shape)")
            let rect = VideoFrameRenderer.webcamRect(settings, outputSize: Self.output)
            #expect(abs(rect.width / rect.height - aspect) < 0.02, "\(shape) is drawn \(rect.width) × \(rect.height)")
            #expect(CGRect(origin: .zero, size: Self.output).contains(rect), "\(shape) stays in the video")
        }
        #expect(VideoWebcamSettings.Shape.recordable.count == 8, "Cutout is chosen in the editor")
        #expect(!VideoWebcamSettings.Shape.recordable.contains(.cutout))
    }

    @Test(arguments: [VideoWebcamSettings.Shape.circle, .rectangle, .square, .landscape, .portrait, .classic, .classicPortrait, .free])
    func theExportDrawsTheShapeWhereThePreviewShowsIt(shape: VideoWebcamSettings.Shape) throws {
        let small = try render(project { $0.choose(shape: shape) })
        let large = try render(project { $0.choose(shape: shape) }, size: CGSize(width: 1920, height: 1080))
        // The same place on any size (the editor's preview is a smaller render).
        for (a, b) in [(small.bubble.minX * 2, large.bubble.minX), (small.bubble.minY * 2, large.bubble.minY), (small.bubble.width * 2, large.bubble.width), (small.bubble.height * 2, large.bubble.height)] {
            #expect(abs(a - b) <= 2, "\(shape): \(small.bubble) ×2 vs \(large.bubble)")
        }
        for frame in [small, large] {
            let box = frame.bubble
            // (The picture's four colors meet in its middle; the rim is light.)
            #expect(isCamera(color(frame, box.minX + box.width * 0.3, box.minY + box.height * 0.3)), "\(shape): the camera inside")
            #expect(isCamera(color(frame, box.minX + box.width * 0.3, box.minY + box.height * 0.06)), "\(shape): the camera reaches the top edge")
            #expect(TestVideos.close(color(frame, box.minX - 6, box.midY), Self.white, within: 0.2) || !isCamera(color(frame, box.minX - 6, box.midY)), "\(shape): nothing past the edge")
            // Corners: cut away on a circle, there on a sharp rectangle.
            let corner = color(frame, box.minX + 2, box.minY + 2)
            if shape == .circle { #expect(!isCamera(corner), "a circle has no corners") }
        }
    }

    @Test func sharpCornersAreSquareAndRoundnessRoundsThem() throws {
        let sharp = try render(project { $0.choose(shape: .landscape); $0.roundness = 0 })
        #expect(isCamera(color(sharp, sharp.bubble.minX + 2, sharp.bubble.minY + 2)), "0 roundness: a sharp corner")
        let round = try render(project { $0.choose(shape: .landscape); $0.roundness = 1 })
        #expect(!isCamera(color(round, round.bubble.minX + 2, round.bubble.minY + 2)), "full roundness: the corner is cut")
    }

    @Test func freeKeepsAnyRatioAndStartsFromTheShapeBefore() {
        var settings = VideoWebcamSettings()
        settings.choose(shape: .landscape)
        settings.choose(shape: .free)
        #expect(abs(settings.effectiveAspect - 16 / 9) < 0.0001, "Free starts as the bubble was")
        settings.freeAspect = 2.5
        let rect = VideoFrameRenderer.webcamRect(settings, outputSize: Self.output)
        #expect(abs(rect.width / rect.height - 2.5) < 0.02)
        settings.freeAspect = 40
        #expect(settings.effectiveAspect == 4, "kept in range")
        settings.choose(shape: .square)
        #expect(settings.effectiveAspect == 1, "Free's ratio only counts for Free")
    }

    // MARK: Older projects

    @Test func olderShapesKeepTheirLookUnderTheirNewNames() throws {
        for (raw, shape, aspect, title) in [("rectangle", VideoWebcamSettings.Shape.rectangle, 4.0 / 3, "Rounded rectangle"), ("square", .square, 1, "Square (1:1)"), ("circle", .circle, 1, "Circle")] {
            let settings = try JSONDecoder().decode(VideoWebcamSettings.self, from: Data(#"{"shape": "\#(raw)", "size": 0.3}"#.utf8))
            #expect(settings.shape == shape)
            #expect(abs(settings.effectiveAspect - aspect) < 0.0001)
            #expect(settings.shape.title == title)
            #expect(settings.placement == nil && settings.freeAspect == nil)
        }
        #expect(VideoWebcamSettings.Shape.rectangle.roundness == 0.24, "Rounded rectangle: today's Wide corners")
        #expect(VideoWebcamSettings.Shape.square.roundness == 0.44)
    }

    @Test func theUsualBubbleIsWhereItAlwaysWas() {
        // The formula before 1.10.0, for every anchor and a few sizes.
        for anchor in VideoWebcamSettings.Anchor.allCases {
            for size in [0.12, 0.26, 0.5] {
                for shape in [VideoWebcamSettings.Shape.circle, .square, .rectangle] {
                    var settings = VideoWebcamSettings()
                    settings.anchor = anchor
                    settings.size = size
                    settings.shape = shape
                    settings.shrinkWhenZoomed = false
                    for output in [Self.output, CGSize(width: 1080, height: 1920)] {
                        let shortSide = min(output.width, output.height)
                        let height = shortSide * CGFloat(size)
                        let width = height * shape.aspect
                        let margin = (shortSide * 0.04).rounded()
                        let x = margin + (output.width - width - margin * 2) * anchor.unit.x
                        let yFromTop = margin + (output.height - height - margin * 2) * anchor.unit.y
                        let old = CGRect(x: x.rounded(), y: (output.height - yFromTop - height).rounded(), width: width.rounded(), height: height.rounded())
                        #expect(VideoFrameRenderer.webcamRect(settings, outputSize: output) == old, "\(anchor) \(size) \(shape) \(output)")
                    }
                }
            }
        }
    }

    @Test func nothingNewIsWrittenForAnUntouchedCamera() throws {
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(VideoWebcamSettings())) as? [String: Any])
        #expect(!object.keys.contains("placement") && !object.keys.contains("freeAspect"))
    }

    // MARK: Chosen before recording

    private func metadata(setup: VideoRecordingCameraSetup?, camera: Bool = true) -> VideoDemoRecordingMetadata {
        var metadata = VideoDemoRecordingMetadata(videoURLPath: "/tmp/shape.mp4", createdAt: Date(), duration: 4, sourceWidth: 1280, sourceHeight: 720, fps: 30, nativeCursorVisible: true, cursorSamples: [], clickEvents: [])
        if camera { metadata.webcam = VideoWebcamRecording(path: "/tmp/shape-camera.mov", offset: 0, width: 1280, height: 720) }
        metadata.cameraSetup = setup
        return metadata
    }

    @Test func aNewRecordingOpensWithTheCameraChosenBeforeRecording() {
        let placement = VideoWebcamSettings.Placement(x: 0.2, y: 0.3, width: 0.25)
        let setup = VideoRecordingCameraSetup(shape: .portrait, freeAspect: nil, roundness: 0.5, placement: placement)
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/shape.mp4"))
        project.apply(metadata: metadata(setup: setup))
        #expect(project.webcam.shape == .portrait)
        #expect(project.webcam.roundness == 0.5)
        #expect(project.webcam.placement == placement)
        #expect(project.webcam.mirror == false && project.webcam.visible, "otherwise the plain camera")

        var free = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/shape.mp4"))
        free.apply(metadata: metadata(setup: VideoRecordingCameraSetup(shape: .free, freeAspect: 1.8)))
        #expect(abs(free.webcam.effectiveAspect - 1.8) < 0.0001)
    }

    @Test func withoutAChoiceANewRecordingOpensAsBefore() {
        for meta in [metadata(setup: nil), metadata(setup: VideoRecordingCameraSetup()), metadata(setup: VideoRecordingCameraSetup(shape: .landscape), camera: false)] {
            var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/shape.mp4"))
            project.apply(metadata: meta)
            #expect(project.webcam == VideoWebcamSettings.plain)
        }
    }

    @Test func olderRecordingDataHasNoSetup() throws {
        let data = try JSONEncoder().encode(metadata(setup: nil))
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("cameraSetup"))
        let back = try JSONDecoder().decode(VideoDemoRecordingMetadata.self, from: data)
        #expect(back.cameraSetup == nil)
    }

    // MARK: The preview before recording, measured against the frame

    static let frame = CGRect(x: 100, y: 200, width: 800, height: 450)

    @Test(arguments: [VideoWebcamSettings.Shape.circle, .rectangle, .square, .landscape, .portrait, .classic, .classicPortrait, .free])
    func theUntouchedPreviewIsTheUsualBubble(shape: VideoWebcamSettings.Shape) {
        let chosen = VideoRecordingCameraSetup(shape: shape)
        let preview = VideoCameraPreviewGeometry.rect(chosen, in: Self.frame)
        // The same rect, relative to the frame, as the editor's video.
        let video = VideoFrameRenderer.webcamRect(chosen.webcam, outputSize: CGSize(width: 1920, height: 1080))
        #expect(abs((preview.minX - Self.frame.minX) / Self.frame.width - video.minX / 1920) < 0.003)
        #expect(abs((preview.minY - Self.frame.minY) / Self.frame.height - video.minY / 1080) < 0.003)
        #expect(abs(preview.width / Self.frame.width - video.width / 1920) < 0.003)
        #expect(abs(preview.height / preview.width - video.height / video.width) < 0.01, "\(shape): the same shape")
        // Not moved: nothing placed, so the editor draws its usual bubble.
        let saved = VideoCameraPreviewGeometry.setup(chosen, preview: preview, frame: Self.frame)
        #expect(saved.placement == nil)
        #expect(saved.shape == shape)
    }

    @Test func aPreviewMovedInsideTheFrameIsWhereTheCameraGoes() throws {
        // 200 × 200 points, its center 25% across and 30% down the frame.
        let preview = CGRect(x: 100 + 200 - 100, y: 200 + 450 * 0.7 - 100, width: 200, height: 200)
        let placement = try #require(VideoCameraPreviewGeometry.placement(of: preview, in: Self.frame))
        #expect(abs(placement.x - 0.25) < 0.0001 && abs(placement.y - 0.3) < 0.0001 && abs(placement.width - 0.25) < 0.0001)
        #expect(VideoCameraPreviewGeometry.label(preview: preview, frame: Self.frame) == "Camera: 25% of width, top left")

        // Drawn exactly there in the editor, at any video size.
        var webcam = VideoWebcamSettings.plain
        webcam.placement = placement
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 800, height: 450)] {
            let rect = VideoFrameRenderer.webcamRect(webcam, outputSize: size)
            #expect(abs(rect.midX - size.width * 0.25) <= 1 && abs((size.height - rect.midY) - size.height * 0.3) <= 1 && abs(rect.width - size.width * 0.25) <= 1)
        }
    }

    @Test func aPreviewOutOfTheWayIsntInTheVideo() {
        let outside = CGRect(x: 1000, y: 100, width: 160, height: 160)
        #expect(VideoCameraPreviewGeometry.placement(of: outside, in: Self.frame) == nil)
        #expect(VideoCameraPreviewGeometry.label(preview: outside, frame: Self.frame) == "Not in video — position set in the editor")
        let saved = VideoCameraPreviewGeometry.setup(VideoRecordingCameraSetup(shape: .landscape), preview: outside, frame: Self.frame)
        #expect(saved.placement == nil && saved.shape == .landscape, "the shape still counts")
        // Mostly outside counts as outside; mostly inside is kept inside.
        let straddling = CGRect(x: 820, y: 300, width: 100, height: 100)
        let kept = VideoCameraPreviewGeometry.placement(of: straddling, in: Self.frame)
        #expect(kept != nil)
        if let kept { #expect(kept.x + kept.width / 2 <= 1.0001, "pulled wholly inside") }
    }

    @Test func theLabelNamesTheSpot() {
        let spots: [(Double, Double, String)] = [(0.1, 0.1, "top left"), (0.5, 0.1, "top"), (0.9, 0.1, "top right"), (0.1, 0.5, "left"), (0.5, 0.5, "center"),
                                                (0.9, 0.5, "right"), (0.1, 0.9, "bottom left"), (0.5, 0.9, "bottom"), (0.9, 0.9, "bottom right")]
        for (x, y, words) in spots {
            #expect(VideoCameraPreviewGeometry.spot(VideoWebcamSettings.Placement(x: x, y: y, width: 0.2)) == words)
        }
    }

    @Test func aZoomCanStillMoveAPlacedCameraToACorner() {
        var webcam = VideoWebcamSettings.plain
        webcam.placement = VideoWebcamSettings.Placement(x: 0.5, y: 0.5, width: 0.3)
        let home = VideoFrameRenderer.webcamRect(webcam, outputSize: Self.output)
        let moved = VideoFrameRenderer.webcamRect(webcam.at(anchor: .topLeft, outputSize: Self.output), outputSize: Self.output)
        #expect(abs(moved.width - home.width) <= 1 && abs(moved.height - home.height) <= 1, "as big as it was")
        #expect(moved.minX < home.minX && moved.maxY > home.maxY, "in the top left")
    }
}
