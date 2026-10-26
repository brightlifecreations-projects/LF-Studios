import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import LFStudiosCore

/// Fonts in a real export: a font only LF Studios has (added from a file
/// that's deleted afterwards) in the intro card, captions, keys, and a text
/// annotation. The export draws what the preview draws, the font shows,
/// and a missing font falls back to the built-in one.
@Suite("Custom fonts in a real export", .serialized)
struct VideoFontExportTests {
    static let cardTime = 0.8
    /// Timeline seconds: the caption, keys, and annotation all show (the
    /// 1.5 s intro card comes first).
    static let textTime = 3.0

    private func project(source: URL, font: VideoFontChoice?) -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: source, duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        project.apply(style: .factory)
        project.aspectPreset = .widescreen
        project.zoomRegions = []
        project.cards.intro = VideoTitleCard(enabled: true, title: "Chalk Fonts", subtitle: "Added from a file", duration: 1.5)
        project.cards.font = font
        project.captions = [VideoCaptionLine(start: 0.8, end: 2.6, text: "Every caption in chalk")]
        project.captionStyle.highlightWords = false
        // Outlined captions in all three, so only the family differs.
        project.captionStyle.font = VideoFontChoice(family: font?.family, outline: true)
        project.keystrokes = [VideoKeystrokeEvent(time: 1.3, keys: ["⌘", "⇧", "K"])]
        project.keystrokeStyle.font = font
        var note = VideoDemoOverlayEffect(kind: .text, time: 1.0, duration: 1.6, x: 0.3, y: 0.3, width: 0.34, height: 0.14, text: "Chalk note")
        note.font = font
        project.overlayEffects = [note]
        return project
    }

    /// The mean difference (0…1) inside `region` (fractions of the frame,
    /// top-left origin).
    private static func meanDifference(_ a: CGImage, _ b: CGImage, in region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> Double {
        let x = TestVideos.rgba(a), y = TestVideos.rgba(b)
        let x0 = Int(region.minX * CGFloat(a.width)), x1 = Int(region.maxX * CGFloat(a.width))
        let y0 = Int(region.minY * CGFloat(a.height)), y1 = Int(region.maxY * CGFloat(a.height))
        var total = 0.0, count = 0.0
        for py in y0..<min(y1, a.height) {
            for px in x0..<min(x1, a.width) {
                let i = (py * a.width + px) * 4
                total += Double(abs(Int(x[i]) - Int(y[i])) + abs(Int(x[i + 1]) - Int(y[i + 1])) + abs(Int(x[i + 2]) - Int(y[i + 2]))) / 3
                count += 1
            }
        }
        return total / max(count, 1) / 255
    }

    /// Where the words are: the card's title and subtitle; the annotation,
    /// keys, and caption.
    static let textRegions: [String: [CGRect]] = [
        "card": [CGRect(x: 0.3, y: 0.38, width: 0.4, height: 0.22)],
        "text": [CGRect(x: 0.2, y: 0.25, width: 0.3, height: 0.12), CGRect(x: 0.3, y: 0.8, width: 0.4, height: 0.17)],
    ]

    /// The renderer's own frame (what the preview shows) at a timeline time.
    private func previewFrame(_ project: VideoDemoProject, source: URL, at time: Double, size: CGSize) async throws -> CGImage {
        let segments = project.timelineSegments(totalDuration: 3)
        // The segments start after the intro card already.
        let sourceTime = VideoDemoProject.sourceTime(forTimelineTime: time, segments: segments)
        let sourceFrame = try await TestVideos.frame(ofMovie: source, at: sourceTime)
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 3, recording: nil)
        let image = VideoFrameRenderer().render(source: CIImage(cgImage: sourceFrame), timelineTime: time, plan: plan, outputSize: size, options: VideoFrameRenderer.Options(frameRate: 30))
        return try #require(CIContext().createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
    }

    @Test func fontsInTheExportMatchThePreview() async throws {
        try TestVideos.isolateStorage()
        try TestFonts.addToLFStudios()
        #expect(VideoFonts.isAvailable(TestFonts.family))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-font-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.mp4")
        try await TestVideos.writeBars(to: source)
        let frames = try TestVideos.framesDirectory("fonts")

        let chalk = project(source: source, font: VideoFontChoice(family: TestFonts.family))
        let builtIn = project(source: source, font: nil)
        let missing = project(source: source, font: VideoFontChoice(family: "No Such Font 9183"))
        let urls = ["chalk", "built-in", "missing"].map { directory.appendingPathComponent("\($0).mp4") }
        for (project, url) in zip([chalk, builtIn, missing], urls) {
            try await TestVideos.export(project, to: url)
        }

        for (name, time) in [("card", Self.cardTime), ("text", Self.textTime)] {
            let exported = try await TestVideos.frame(ofMovie: urls[0], at: time)
            let size = CGSize(width: exported.width, height: exported.height)
            let preview = try await previewFrame(chalk, source: source, at: time, size: size)
            let plain = try await TestVideos.frame(ofMovie: urls[1], at: time)
            let fallback = try await TestVideos.frame(ofMovie: urls[2], at: time)
            try TestVideos.save(exported, as: frames.appendingPathComponent("\(name)-1-export-added-font.png"))
            try TestVideos.save(preview, as: frames.appendingPathComponent("\(name)-2-preview-added-font.png"))
            try TestVideos.save(plain, as: frames.appendingPathComponent("\(name)-3-export-built-in.png"))
            try TestVideos.save(fallback, as: frames.appendingPathComponent("\(name)-4-export-missing-font.png"))

            let toPreview = Self.meanDifference(exported, preview)
            #expect(toPreview < 0.02, "\(name): the export draws what the preview draws (\(toPreview))")
            for region in Self.textRegions[name] ?? [] {
                let wordsToPreview = Self.meanDifference(exported, preview, in: region)
                let wordsToBuiltIn = Self.meanDifference(exported, plain, in: region)
                let fallbackToBuiltIn = Self.meanDifference(fallback, plain, in: region)
                print("fonts \(name) \(region): export vs preview \(wordsToPreview), vs built-in \(wordsToBuiltIn); missing-font export vs built-in \(fallbackToBuiltIn)")
                #expect(wordsToPreview < 0.02, "\(name): the words in the export match the preview (\(wordsToPreview))")
                #expect(wordsToBuiltIn > max(wordsToPreview * 3, 0.01), "\(name): the added font shows (\(wordsToBuiltIn) vs \(wordsToPreview))")
                #expect(fallbackToBuiltIn < 0.002, "\(name): a missing font draws like the built-in one (\(fallbackToBuiltIn))")
            }
        }
        print("Font frames saved in \(frames.path)")
    }
}
