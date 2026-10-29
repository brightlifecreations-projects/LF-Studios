import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import LFStudiosCore

/// The timeline's Hide (1.11.0) in the frames themselves: Video clips
/// hidden leaves out only the screen recording.
@Suite("Hidden tracks in the frames")
struct VideoTrackRenderTests {
    private func render(_ project: VideoDemoProject) throws -> [UInt8] {
        let output = project.forOutput()
        let plan = VideoDemoExporter.makePlan(project: output, sourceDuration: 4, recording: nil, hasWebcam: true)
        var options = VideoFrameRenderer.Options(frameRate: 30)
        options.webcamFrame = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.8)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        let size = CGSize(width: 960, height: 540)
        let image = VideoFrameRenderer().render(source: TestVideos.quadrantImage(size: project.sourceSize), timelineTime: 2, plan: plan, outputSize: size, options: options)
        let cgImage = try #require(CIContext().createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
        return TestVideos.rgba(cgImage)
    }

    @Test func hidingVideoClipsLeavesOutOnlyTheScreen() throws {
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/hide.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        project.aspectPreset = .widescreen
        project.background = .color(VideoRGBA(1, 1, 1))
        project.padding = 0.1
        let shown = try render(project)
        let screenSpot = TestVideos.pixel(shown, width: 960, x: 200, y: 150)
        #expect(TestVideos.quadrantColors.contains { TestVideos.close(screenSpot, $0, within: 0.12) }, "the screen is drawn")

        project.setTrackState(.clips) { $0.hidden = true }
        let hidden = try render(project)
        #expect(TestVideos.close(TestVideos.pixel(hidden, width: 960, x: 200, y: 150), (1, 1, 1), within: 0.05), "the background where the screen was")
        let bubble = VideoFrameRenderer.webcamRect(project.webcam, outputSize: CGSize(width: 960, height: 540))
        #expect(TestVideos.close(TestVideos.pixel(hidden, width: 960, x: Int(bubble.midX - bubble.width * 0.2), y: Int(540 - bubble.midY)), (0.9, 0.1, 0.8), within: 0.12), "the camera still is")

        project.setTrackState(.clips) { $0.hidden = false }
        project.setTrackState(.camera) { $0.hidden = true }
        let noCamera = try render(project)
        #expect(!TestVideos.close(TestVideos.pixel(noCamera, width: 960, x: Int(bubble.midX - bubble.width * 0.2), y: Int(540 - bubble.midY)), (0.9, 0.1, 0.8), within: 0.12), "Camera hidden: no bubble")
    }
}
