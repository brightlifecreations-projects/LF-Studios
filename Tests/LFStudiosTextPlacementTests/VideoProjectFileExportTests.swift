import CoreGraphics
import Foundation
import Testing
@testable import LFStudiosCore

/// A project saved with its media, its original recording deleted and the
/// package moved, then opened again: it exports the same frames as before
/// it was saved.
@Suite("Project files in a real export", .serialized)
struct VideoProjectFileExportTests {
    private static func meanDifference(_ a: CGImage, _ b: CGImage) -> Double {
        let x = TestVideos.rgba(a), y = TestVideos.rgba(b)
        var total = 0.0
        for i in stride(from: 0, to: min(x.count, y.count), by: 4) {
            total += Double(abs(Int(x[i]) - Int(y[i])) + abs(Int(x[i + 1]) - Int(y[i + 1])) + abs(Int(x[i + 2]) - Int(y[i + 2]))) / 3
        }
        return total / Double(x.count / 4) / 255
    }

    @Test func aReopenedProjectExportsTheSameVideo() async throws {
        try TestVideos.isolateStorage()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-project-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("recording.mp4")
        try await TestVideos.writeBars(to: source)

        var project = VideoDemoProject.make(sourceURL: source, duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        project.apply(style: .factory)
        project.aspectPreset = .widescreen
        project.background = .color(VideoRGBA(0.95, 0.55, 0.1))
        project.padding = 0.16
        project.cornerRadius = 0
        project.captions = [VideoCaptionLine(start: 0.5, end: 2.5, text: "Saved, closed, and opened again")]
        project.captionStyle.highlightWords = false
        project.captionStyle.placement = VideoTextPlacement(x: 0.5, y: 0.2)
        let before = folder.appendingPathComponent("before.mp4")
        try await TestVideos.export(project, to: before)

        let package = folder.appendingPathComponent("Demo.lfstudios")
        try VideoProjectPackage.save(VideoProjectContents(project: project, recording: nil, sourceRecordings: [:]), to: package, mode: .included)
        try FileManager.default.removeItem(at: source)
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-project-elsewhere-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let moved = elsewhere.appendingPathComponent("Demo.lfstudios")
        try FileManager.default.moveItem(at: package, to: moved)

        let opened = try VideoProjectPackage.open(moved)
        #expect(FileManager.default.fileExists(atPath: opened.contents.project.sourcePath))
        let after = folder.appendingPathComponent("after.mp4")
        try await TestVideos.export(opened.contents.project, to: after)

        let frames = try TestVideos.framesDirectory("project-files")
        for time in [1.0, 2.0] {
            let a = try await TestVideos.frame(ofMovie: before, at: time)
            let b = try await TestVideos.frame(ofMovie: after, at: time)
            try TestVideos.save(a, as: frames.appendingPathComponent("\(Int(time))s-1-before-saving.png"))
            try TestVideos.save(b, as: frames.appendingPathComponent("\(Int(time))s-2-reopened-project.png"))
            let difference = Self.meanDifference(a, b)
            print("project at \(time)s: before saving vs reopened \(difference)")
            #expect(difference < 0.002, "the reopened project exports the same frame at \(time)s (\(difference))")
            let corner = TestVideos.averageColor(of: b, x: 0.01, y: 0.01)
            #expect(TestVideos.close(corner, (0.95, 0.55, 0.1), within: 0.06), "its background came back: \(corner)")
        }
        print("Project frames saved in \(frames.path)")
    }
}
