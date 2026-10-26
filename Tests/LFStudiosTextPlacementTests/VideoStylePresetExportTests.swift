import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import LFStudiosCore

/// A preset applied to a video changes the real export the way it says:
/// the frames are exported, then checked against the preset and against
/// the renderer's own frame (what the preview shows).
@Suite("Style presets in a real export", .serialized)
struct VideoStylePresetExportTests {
    @Test func anAppliedPresetShowsInTheExport() async throws {
        try TestVideos.isolateStorage()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-preset-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.mp4")
        try await TestVideos.writeBars(to: source)

        var project = VideoDemoProject.make(sourceURL: source, duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        project.apply(style: .factory)
        project.aspectPreset = .widescreen

        var style = VideoStylePreset.factory
        style.background = .color(VideoRGBA(0.1, 0.3, 0.9))
        style.padding = 0.2
        style.cornerRadius = 0
        style.shadow = 0
        style.outline = false
        style.aspectPreset = .square
        let preset = VideoNamedStylePreset(name: "Blue", style: style, includesAspectRatio: false)

        var styled = project
        styled.apply(preset: preset)
        #expect(styled.aspectPreset == .widescreen, "the preset leaves the aspect ratio alone")

        let before = directory.appendingPathComponent("before.mp4")
        let after = directory.appendingPathComponent("after.mp4")
        try await TestVideos.export(project, to: before)
        try await TestVideos.export(styled, to: after)
        let time = 1.5
        let plain = try await TestVideos.frame(ofMovie: before, at: time)
        let frame = try await TestVideos.frame(ofMovie: after, at: time)
        let frames = try TestVideos.framesDirectory("presets")
        try TestVideos.save(plain, as: frames.appendingPathComponent("1-before-built-in-look.png"))
        try TestVideos.save(frame, as: frames.appendingPathComponent("2-after-preset-blue.png"))
        print("Preset frames saved in \(frames.path)")
        #expect(frame.width == 1920 && frame.height == 1080, "still 16:9: \(frame.width)×\(frame.height)")

        // 1. The preset's background, in the corner and the margins.
        for spot in [(0.01, 0.01), (0.97, 0.5), (0.5, 0.97)] {
            let color = TestVideos.averageColor(of: frame, x: spot.0, y: spot.1)
            #expect(abs(color.r - 0.1) < 0.04 && abs(color.g - 0.3) < 0.04 && abs(color.b - 0.9) < 0.04, "background at \(spot): \(color)")
        }
        let builtIn = TestVideos.averageColor(of: plain, x: 0.01, y: 0.01)
        #expect(abs(builtIn.b - 0.9) > 0.1 || abs(builtIn.r - 0.1) > 0.1, "the built-in look's background is different: \(builtIn)")

        // 2. The recording sits where the preset's padding puts it.
        let canvas = styled.canvasSize()
        let stage = styled.stageRect(in: canvas)
        let inside = TestVideos.averageColor(of: frame, x: Double(stage.midX / canvas.width) - 0.01, y: Double(stage.minY / canvas.height) + 0.02)
        #expect(abs(inside.b - 0.9) > 0.15 || abs(inside.r - 0.1) > 0.15, "the recording, not background, just inside its frame: \(inside)")
        let outside = TestVideos.averageColor(of: frame, x: Double(stage.minX / canvas.width) - 0.02, y: 0.5, width: 0.01)
        #expect(abs(outside.b - 0.9) < 0.05, "background just left of the recording: \(outside)")
        #expect(stage.minX / canvas.width > 0.1, "a 20% padding leaves a wide margin: \(stage)")

        // 3. The export draws what the renderer (the preview) draws.
        let sourceFrame = try await TestVideos.frame(ofMovie: source, at: time)
        let plan = VideoDemoExporter.makePlan(project: styled, sourceDuration: 3, recording: nil)
        let rendered = VideoFrameRenderer().render(source: CIImage(cgImage: sourceFrame), timelineTime: time, plan: plan, outputSize: CGSize(width: frame.width, height: frame.height), options: VideoFrameRenderer.Options(frameRate: 30))
        let preview = try #require(CIContext().createCGImage(rendered, from: CGRect(x: 0, y: 0, width: frame.width, height: frame.height), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
        try TestVideos.save(preview, as: frames.appendingPathComponent("3-preview-render.png"))
        let a = TestVideos.rgba(frame), b = TestVideos.rgba(preview)
        var total = 0.0
        for index in stride(from: 0, to: a.count, by: 4) {
            total += Double(abs(Int(a[index]) - Int(b[index])) + abs(Int(a[index + 1]) - Int(b[index + 1])) + abs(Int(a[index + 2]) - Int(b[index + 2]))) / 3
        }
        let meanDifference = total / Double(a.count / 4) / 255
        print("export vs preview render: mean difference \(meanDifference)")
        #expect(meanDifference < 0.02, "the export matches the preview render (mean difference \(meanDifference))")
    }
}
