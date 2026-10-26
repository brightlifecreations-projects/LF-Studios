import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import LFStudiosCore

/// Camera crop, roundness, border, and shadow (VideoFeatures.swift,
/// VideoRenderer.swift, VideoCameraCropSheet.swift).
@Suite("Camera crop, roundness, border, shadow")
struct VideoWebcamLookTests {
    typealias RGB = (r: Double, g: Double, b: Double)
    static let red = TestVideos.quadrantColors[0], green = TestVideos.quadrantColors[1], yellow = TestVideos.quadrantColors[3]
    static let white: RGB = (1, 1, 1)
    static let output = CGSize(width: 960, height: 540)

    // MARK: Settings

    @Test func oldProjectsOpenWithTheBubbleTheyHad() throws {
        var settings = VideoWebcamSettings()
        settings.shape = .square
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        for key in ["crop", "roundness", "border", "shadowStrength"] { object.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(VideoWebcamSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.crop == nil && old.roundness == nil && old.border == nil && old.shadowStrength == nil)
        #expect(old.shape == .square)
        #expect(!(try JSONSerialization.jsonObject(with: JSONEncoder().encode(VideoWebcamSettings())) as? [String: Any] ?? [:]).keys.contains("roundness"),
                "nothing set writes no new keys")
    }

    @Test func cornersWithoutARoundnessAreExactlyTheShapesOld() {
        let rects = [CGRect(x: 0, y: 0, width: 200, height: 200), CGRect(x: 0, y: 0, width: 266, height: 200)]
        let legacy: [VideoWebcamSettings.Shape: (CGRect) -> CGFloat] = [
            .circle: { min($0.width, $0.height) / 2 },
            .square: { $0.height * 0.22 },
            .rectangle: { $0.height * 0.12 },
            .cutout: { _ in 0 },
        ]
        for (shape, radius) in legacy {
            var settings = VideoWebcamSettings()
            settings.shape = shape
            for rect in rects {
                #expect(abs(VideoFrameRenderer.webcamCornerRadius(settings, rect: rect) - radius(rect)) < 0.001, "\(shape) at \(rect)")
            }
        }
        var settings = VideoWebcamSettings()
        settings.shape = .square
        settings.roundness = 0
        #expect(VideoFrameRenderer.webcamCornerRadius(settings, rect: rects[0]) == 0)
        settings.roundness = 1
        #expect(VideoFrameRenderer.webcamCornerRadius(settings, rect: rects[0]) == 100)
        settings.shape = .cutout
        #expect(VideoFrameRenderer.webcamCornerRadius(settings, rect: rects[0]) == 0, "a cutout has no card")
    }

    @Test func strayValuesInAFileAreKeptInRange() throws {
        let json = #"{"roundness": 3, "shadowStrength": -1, "crop": {"x": 0.9, "y": -0.2, "width": 0.5, "height": 0.01}}"#
        let settings = try JSONDecoder().decode(VideoWebcamSettings.self, from: Data(json.utf8))
        #expect(settings.roundness == 1)
        #expect(settings.shadowStrength == 0)
        let crop = try #require(settings.effectiveCrop)
        #expect(crop.x + crop.width <= 1.0001 && crop.y >= 0 && crop.height >= VideoCropRect.minimumSide)
    }

    @Test func aCropMapsOntoThePictureWithYUp() {
        var settings = VideoWebcamSettings()
        settings.crop = VideoCropRect(x: 0.25, y: 0.1, width: 0.5, height: 0.4)
        let region = VideoFrameRenderer.webcamCropRegion(settings, extent: CGRect(x: 0, y: 0, width: 640, height: 480))
        #expect(region == CGRect(x: 160, y: 480 * 0.5, width: 320, height: 192))
        settings.crop = .full
        #expect(settings.effectiveCrop == nil, "the whole picture is no crop")
    }

    @Test func theCropSheetShowsTheCropWhereTheMirroredBubbleShowsIt() {
        let crop = VideoCropRect(x: 0.1, y: 0.2, width: 0.3, height: 0.5)
        let shown = VideoCameraCropSheet.flipped(crop, true)
        #expect(abs(shown.x - 0.6) < 1e-9)
        let back = VideoCameraCropSheet.flipped(shown, true)
        #expect(abs(back.x - crop.x) < 1e-9 && back.y == crop.y && back.width == crop.width && back.height == crop.height)
        #expect(VideoCameraCropSheet.flipped(crop, false) == crop)
    }

    @Test func presetsCarryTheNewCameraLook() throws {
        var style = VideoStylePreset.factory
        style.webcam.crop = VideoCropRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        style.webcam.roundness = 0.3
        style.webcam.border = .init(color: VideoRGBA(0, 0.5, 1), width: 0.01)
        style.webcam.shadowStrength = 0.9
        let loaded = try JSONDecoder().decode(VideoStylePreset.self, from: JSONEncoder().encode(style))
        #expect(loaded.webcam == style.webcam)
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/cam.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        project.apply(preset: VideoNamedStylePreset(name: "Cam", style: loaded))
        #expect(project.webcam.border?.width == 0.01)
        #expect(project.webcam.roundness == 0.3)
    }

    // MARK: What the renderer draws (the preview and every export)

    private func project(_ change: (inout VideoWebcamSettings) -> Void, layouts: [VideoCameraLayoutRegion] = []) -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/cam.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        project.apply(style: .factory)
        project.aspectPreset = .widescreen
        project.background = .color(VideoRGBA(1, 1, 1))
        project.webcam.shape = .square
        project.webcam.mirror = false
        project.webcam.shrinkWhenZoomed = false
        project.webcam.size = 0.4
        project.webcam.anchor = .bottomRight
        change(&project.webcam)
        project.cameraLayouts = layouts
        return project
    }

    /// The frame's pixels and the bubble's box (top-left origin, pixels).
    private func render(_ project: VideoDemoProject, mask: CIImage? = nil, at time: Double = 2) throws -> (bytes: [UInt8], bubble: CGRect) {
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 4, recording: nil, hasWebcam: true)
        var options = VideoFrameRenderer.Options(frameRate: 30)
        options.webcamFrame = TestVideos.quadrantImage()
        options.webcamMask = mask
        let screen = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.25)).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
        let image = VideoFrameRenderer().render(source: screen, timelineTime: time, plan: plan, outputSize: Self.output, options: options)
        let cgImage = try #require(CIContext().createCGImage(image, from: CGRect(origin: .zero, size: Self.output), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
        let rect = VideoFrameRenderer.webcamRect(project.webcam, outputSize: Self.output)
        return (TestVideos.rgba(cgImage), CGRect(x: rect.minX, y: Self.output.height - rect.maxY, width: rect.width, height: rect.height))
    }

    private func color(_ frame: (bytes: [UInt8], bubble: CGRect), _ x: CGFloat, _ y: CGFloat) -> RGB {
        TestVideos.pixel(frame.bytes, width: Int(Self.output.width), x: Int(x), y: Int(y))
    }

    @Test(arguments: [false, true])
    func aCropShowsThatPartOfThePicture(mirrored: Bool) throws {
        let whole = try render(project { $0.mirror = mirrored })
        // Uncropped: the top-left of the bubble is the picture's top left
        // (red), or its top right (green) once mirrored like a selfie.
        let topLeft = color(whole, whole.bubble.minX + whole.bubble.width * 0.2, whole.bubble.minY + whole.bubble.height * 0.2)
        #expect(TestVideos.close(topLeft, mirrored ? Self.green : Self.red), "uncropped top left: \(topLeft)")

        let cropped = try render(project { $0.mirror = mirrored; $0.crop = VideoCropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5) })
        for spot in [(0.2, 0.2), (0.5, 0.5), (0.8, 0.8)] {
            let c = color(cropped, cropped.bubble.minX + cropped.bubble.width * spot.0, cropped.bubble.minY + cropped.bubble.height * spot.1)
            #expect(TestVideos.close(c, Self.yellow), "cropped to the bottom-right quadrant (mirrored: \(mirrored)) at \(spot): \(c)")
        }
    }

    @Test func roundnessGoesFromSharpCornersToACircle() throws {
        let sharp = try render(project { $0.crop = VideoCropRect(x: 0, y: 0, width: 0.5, height: 0.5); $0.roundness = 0 })
        let corner = color(sharp, sharp.bubble.minX + 3, sharp.bubble.minY + 3)
        #expect(TestVideos.close(corner, Self.red, within: 0.15), "sharp: the picture reaches the corner: \(corner)")

        let circle = try render(project { $0.crop = VideoCropRect(x: 0, y: 0, width: 0.5, height: 0.5); $0.roundness = 1 })
        let outside = color(circle, circle.bubble.minX + circle.bubble.width * 0.08, circle.bubble.minY + circle.bubble.height * 0.08)
        #expect(!TestVideos.close(outside, Self.red, within: 0.25), "a circle leaves its corner to the background: \(outside)")
        let center = color(circle, circle.bubble.midX, circle.bubble.midY)
        #expect(TestVideos.close(center, Self.red))
    }

    @Test func aBorderHasItsColorAndThickness() throws {
        let blue: RGB = (0, 0.4, 1)
        let framed = try render(project {
            $0.crop = VideoCropRect(x: 0, y: 0, width: 0.5, height: 0.5)
            $0.roundness = 0
            $0.border = .init(color: VideoRGBA(blue.r, blue.g, blue.b), width: 0.012)
        })
        let thickness = min(Self.output.width, Self.output.height) * 0.012
        let edge = color(framed, framed.bubble.minX + thickness / 2, framed.bubble.midY)
        #expect(TestVideos.close(edge, blue, within: 0.1), "the border at the bubble's edge: \(edge)")
        let inside = color(framed, framed.bubble.minX + thickness * 2.5, framed.bubble.midY)
        #expect(TestVideos.close(inside, Self.red, within: 0.12), "the picture right inside it: \(inside)")

        let plain = try render(project { $0.crop = VideoCropRect(x: 0, y: 0, width: 0.5, height: 0.5); $0.roundness = 0 })
        #expect(!TestVideos.close(color(plain, plain.bubble.minX + thickness / 2, plain.bubble.midY), blue, within: 0.2), "no border without one")
    }

    @Test func shadowGoesFromNoneToStrong() throws {
        func shade(_ strength: Double) throws -> Double {
            // Top left: the white margin left of the recording is under its
            // left edge, where the shadow falls below it.
            let frame = try render(project { $0.roundness = 0; $0.shadowStrength = strength; $0.anchor = .topLeft; $0.size = 0.2 })
            let below = color(frame, frame.bubble.minX + 6, frame.bubble.maxY + 6)
            return (below.r + below.g + below.b) / 3
        }
        let none = try shade(0), usual = try shade(0.5), strong = try shade(1)
        #expect(none > 0.97, "no shadow: the white background below: \(none)")
        #expect(usual < none - 0.03, "the usual shadow: \(usual)")
        #expect(strong < usual - 0.03, "a strong shadow is darker still: \(strong)")
    }

    @Test(arguments: [VideoCameraLayoutRegion.Layout.fullscreen, .sideBySide])
    func theCropHoldsInTheCameraLayouts(layout: VideoCameraLayoutRegion.Layout) throws {
        let frame = try render(project({ $0.crop = VideoCropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5) }, layouts: [VideoCameraLayoutRegion(start: 0, end: 4, layout: layout)]))
        // Full camera: the middle of the frame; side by side: the camera
        // panel on the right.
        let spot = layout == .fullscreen ? CGPoint(x: Self.output.width / 2, y: Self.output.height / 2) : CGPoint(x: Self.output.width * 0.82, y: Self.output.height / 2)
        let c = color(frame, spot.x, spot.y)
        #expect(TestVideos.close(c, Self.yellow, within: 0.12), "\(layout): \(c)")
    }

    @Test func backgroundRemovalStaysOnThePersonInACrop() throws {
        // The "person" is the picture's top-left quadrant (mask, y up).
        let size = CGSize(width: 640, height: 480)
        let black = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: size.height / 2, width: size.width / 2, height: size.height / 2)).composited(over: black)

        let person = try render(project { $0.backdrop = .remove; $0.crop = VideoCropRect(x: 0, y: 0, width: 0.5, height: 0.5) }, mask: mask)
        let onPerson = color(person, person.bubble.midX, person.bubble.midY)
        #expect(TestVideos.close(onPerson, Self.red, within: 0.12), "cropped onto the person: kept: \(onPerson)")

        let away = try render(project { $0.backdrop = .remove; $0.crop = VideoCropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5) }, mask: mask)
        let offPerson = color(away, away.bubble.midX, away.bubble.midY)
        #expect(TestVideos.close(offPerson, Self.white, within: 0.08), "cropped away from the person: the video's background: \(offPerson)")
    }
}

