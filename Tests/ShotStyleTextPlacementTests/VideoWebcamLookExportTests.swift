import CoreGraphics
import Foundation
import Testing
@testable import ShotStyleCore

/// The camera look in real MP4 exports: a recording with a four-color
/// camera video, the bubble cropped, rounded, bordered, and shadowed.
@Suite("Camera look in a real export", .serialized)
struct VideoWebcamLookExportTests {
    typealias RGB = (r: Double, g: Double, b: Double)

    private func recording(in directory: URL) async throws -> (source: URL, metadata: VideoDemoRecordingMetadata) {
        let source = directory.appendingPathComponent("screen.mp4")
        let camera = directory.appendingPathComponent("camera.mp4")
        try await TestVideos.writeBars(to: source)
        try await TestVideos.writeQuadrants(to: camera)
        var metadata = VideoDemoRecordingMetadata(
            videoURLPath: source.path, createdAt: Date(), duration: 3, sourceWidth: 1280, sourceHeight: 720, fps: 30,
            nativeCursorVisible: false, cursorSamples: [], clickEvents: [], pointPixelScale: 2, renderCursor: false
        )
        metadata.webcam = VideoWebcamRecording(path: camera.path, offset: 0, width: 640, height: 480)
        return (source, metadata)
    }

    private func project(source: URL, metadata: VideoDemoRecordingMetadata, _ change: (inout VideoWebcamSettings) -> Void) -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: source, duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        project.apply(metadata: metadata)
        project.apply(style: .factory)
        project.aspectPreset = .widescreen
        project.background = .color(VideoRGBA(1, 1, 1))
        project.zoomRegions = []
        project.webcam.visible = true
        project.webcam.shrinkWhenZoomed = false
        project.webcam.size = 0.4
        change(&project.webcam)
        return project
    }

    private func export(_ project: VideoDemoProject, metadata: VideoDemoRecordingMetadata, to url: URL) async throws -> CGImage {
        var settings = VideoExportSettings()
        settings.resolution = .p1080
        settings.fps = 30
        settings.endCard = false
        try? FileManager.default.removeItem(at: url)
        try await VideoDemoExporter.export(project: project, recording: metadata, destinationURL: url, settings: settings)
        return try await TestVideos.frame(ofMovie: url, at: 1.5)
    }

    /// The bubble's box in the frame (top-left origin).
    private func bubble(_ settings: VideoWebcamSettings, in frame: CGImage) -> CGRect {
        let size = CGSize(width: frame.width, height: frame.height)
        let rect = VideoFrameRenderer.webcamRect(settings, outputSize: size)
        return CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func color(_ frame: CGImage, _ bytes: [UInt8], _ x: CGFloat, _ y: CGFloat) -> RGB {
        TestVideos.pixel(bytes, width: frame.width, x: Int(x), y: Int(y))
    }

    @Test func theCameraLookShowsInTheExport() async throws {
        try TestVideos.isolateStorage()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shotstyle-camera-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (source, metadata) = try await recording(in: directory)
        let frames = try TestVideos.framesDirectory("camera-look")
        let yellow = TestVideos.quadrantColors[3], red = TestVideos.quadrantColors[0]
        let blue: RGB = (0, 0.4, 1)

        // A: the bottom-right quadrant, square, a blue border, strong shadow.
        let a = project(source: source, metadata: metadata) {
            $0.anchor = .bottomRight
            $0.shape = .square
            $0.mirror = false
            $0.crop = VideoCropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
            $0.roundness = 0
            $0.border = .init(color: VideoRGBA(blue.r, blue.g, blue.b), width: 0.012)
            $0.shadowStrength = 1
        }
        let frameA = try await export(a, metadata: metadata, to: directory.appendingPathComponent("a.mp4"))
        try TestVideos.save(frameA, as: frames.appendingPathComponent("A-crop-yellow-square-blue-border.png"))
        let bytesA = TestVideos.rgba(frameA)
        let boxA = bubble(a.webcam, in: frameA)
        let thickness = CGFloat(frameA.height) * 0.012
        for spot in [(0.3, 0.3), (0.5, 0.5), (0.7, 0.7)] {
            let c = color(frameA, bytesA, boxA.minX + boxA.width * spot.0, boxA.minY + boxA.height * spot.1)
            #expect(TestVideos.close(c, yellow), "A: only the cropped yellow quadrant at \(spot): \(c)")
        }
        let edge = color(frameA, bytesA, boxA.minX + thickness / 2, boxA.midY)
        #expect(TestVideos.close(edge, blue, within: 0.12), "A: blue border at the edge: \(edge)")
        let corner = color(frameA, bytesA, boxA.minX + thickness / 2, boxA.minY + thickness / 2)
        #expect(TestVideos.close(corner, blue, within: 0.15), "A: square corners: the border fills the corner: \(corner)")

        // B: the top-left quadrant, mirrored, a full circle, top left.
        let b = project(source: source, metadata: metadata) {
            $0.anchor = .topLeft
            $0.shape = .circle
            $0.mirror = true
            $0.crop = VideoCropRect(x: 0, y: 0, width: 0.5, height: 0.5)
            $0.roundness = 1
        }
        let frameB = try await export(b, metadata: metadata, to: directory.appendingPathComponent("b.mp4"))
        try TestVideos.save(frameB, as: frames.appendingPathComponent("B-crop-red-mirrored-circle.png"))
        let bytesB = TestVideos.rgba(frameB)
        let boxB = bubble(b.webcam, in: frameB)
        let center = color(frameB, bytesB, boxB.midX, boxB.midY)
        #expect(TestVideos.close(center, red), "B: the cropped red quadrant, even mirrored: \(center)")
        let outside = color(frameB, bytesB, boxB.minX + boxB.width * 0.06, boxB.minY + boxB.height * 0.06)
        #expect(!TestVideos.close(outside, red, within: 0.25), "B: a circle leaves its corner to the background: \(outside)")
        print("Camera look frames saved in \(frames.path)")
    }
}
