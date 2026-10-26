import AppKit
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import LFStudiosCore

/// Camera footage filmed apart from the recording, in real MP4 exports:
/// lined up by its sound, and styled like a recorded camera.
@Suite("Camera video from elsewhere in a real export", .serialized)
struct VideoImportedCameraExportTests {
    typealias RGB = (r: Double, g: Double, b: Double)

    /// The camera was started this long after the screen recording.
    static let lag = 0.7
    /// Beeps, in seconds of the screen recording.
    static let beeps = [0.4, 1.1, 1.5, 2.6, 3.0, 3.9, 4.3]
    static let palette = TestVideos.quadrantColors

    /// The color both videos show at moment `world` (seconds of the screen
    /// recording): a new one every half second.
    static func colorIndex(world: Double) -> Int { Int((world / 0.5).rounded(.down)) % palette.count }

    private static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-imported-camera-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A frame filled with the moment's color, and its label and frame
    /// number in the middle.
    private static func paint(_ context: CGContext, size: CGSize, world: Double, label: String, frame: Int) {
        let color = palette[colorIndex(world: world)]
        context.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let text = NSAttributedString(string: String(format: "%@ %03d  t=%.2f", label, frame, world), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size.height / 9, weight: .bold),
            .foregroundColor: NSColor.white,
        ])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        // Low in the frame, so the middle stays one flat color to sample.
        context.textPosition = CGPoint(x: (size.width - bounds.width) / 2, y: size.height * 0.08)
        CTLineDraw(line, context)
    }

    /// The screen recording (5 s) and the camera video (4.3 s, started
    /// `lag` later), each with the same beeps in its own sound.
    private func videos(in folder: URL) async throws -> (screen: URL, camera: URL) {
        let fps = 30
        let screenPicture = folder.appendingPathComponent("screen-picture.mp4"), cameraPicture = folder.appendingPathComponent("camera-picture.mp4")
        let screenSize = CGSize(width: 1280, height: 720), cameraSize = CGSize(width: 640, height: 480)
        try await TestVideos.writeVideo(to: screenPicture, size: screenSize, seconds: 5, fps: fps) { context, frame in
            Self.paint(context, size: screenSize, world: Double(frame) / Double(fps), label: "SCREEN", frame: frame)
        }
        try await TestVideos.writeVideo(to: cameraPicture, size: cameraSize, seconds: 5, fps: fps) { context, frame in
            Self.paint(context, size: cameraSize, world: Double(frame) / Double(fps) + Self.lag, label: "CAMERA", frame: frame)
        }
        let screenSound = folder.appendingPathComponent("screen.m4a"), cameraSound = folder.appendingPathComponent("camera.m4a")
        try TestSounds.writeAudio(TestSounds.beeps(at: Self.beeps, seconds: 5), to: screenSound)
        // Another microphone: quieter, more hiss.
        try TestSounds.writeAudio(TestSounds.beeps(at: Self.beeps.map { $0 - Self.lag }, seconds: 4.3, gain: 0.25, noise: 0.03, seed: 9), to: cameraSound)
        let screen = folder.appendingPathComponent("screen.mov"), camera = folder.appendingPathComponent("camera.mov")
        try await TestSounds.mux(video: screenPicture, audio: screenSound, to: screen)
        try await TestSounds.mux(video: cameraPicture, audio: cameraSound, to: camera)
        return (screen, camera)
    }

    private func project(screen: URL, camera: VideoImportedCamera, _ change: (inout VideoDemoProject) -> Void = { _ in }) -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: screen, duration: 5, sourceSize: CGSize(width: 1280, height: 720))
        project.apply(style: .factory)
        project.aspectPreset = .widescreen
        project.background = .color(VideoRGBA(1, 1, 1))
        project.zoomRegions = []
        project.webcam.visible = true
        project.webcam.shrinkWhenZoomed = false
        project.webcam.size = 0.34
        project.webcam.anchor = .bottomRight
        project.webcam.shape = .square
        project.webcam.roundness = 0
        project.webcam.mirror = false
        project.importedCamera = camera
        change(&project)
        return project
    }

    /// The bubble's box in the frame (top-left origin).
    private func bubble(_ settings: VideoWebcamSettings, in frame: CGImage) -> CGRect {
        let size = CGSize(width: frame.width, height: frame.height)
        let rect = VideoFrameRenderer.webcamRect(settings, outputSize: size)
        return CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func average(_ frame: CGImage, _ box: CGRect, at x: Double, _ y: Double) -> RGB {
        TestVideos.averageColor(of: frame, x: (box.minX + box.width * x) / Double(frame.width), y: (box.minY + box.height * y) / Double(frame.height), width: 0.01, height: 0.01)
    }

    @Test func autoSyncLinesTheCameraUpWithTheScreen() async throws {
        try TestVideos.isolateStorage()
        let folder = try Self.folder()
        let (screen, cameraURL) = try await videos(in: folder)
        let frames = try TestVideos.framesDirectory("imported-camera")

        // 1. Sync by sound finds the 0.7 s.
        let match = try await VideoAudioSync.match(reference: screen, other: cameraURL).get()
        print("auto-sync: camera starts \(match.offset) s after the screen (correlation \(match.correlation), lead \(match.distinctness))")
        #expect(abs(match.offset - Self.lag) <= 0.02, "auto-sync found \(match.offset), wanted \(Self.lag) ± 0.02")

        // 2. Exported with that offset, the camera shows the same moment as
        // the screen; exported unsynced (0), it doesn't.
        let camera = try #require(await VideoImportedCamera.read(cameraURL, offset: match.offset))
        let synced = project(screen: screen, camera: camera)
        var unsynced = synced
        unsynced.importedCamera?.offset = 0
        let syncedURL = folder.appendingPathComponent("synced.mp4"), unsyncedURL = folder.appendingPathComponent("unsynced.mp4")
        try await TestVideos.export(synced, to: syncedURL)
        try await TestVideos.export(unsynced, to: unsyncedURL)

        var mismatches = 0
        for time in [1.25, 1.75, 2.25, 2.75, 3.25, 3.75, 4.25] {
            let a = try await TestVideos.frame(ofMovie: syncedURL, at: time)
            let b = try await TestVideos.frame(ofMovie: unsyncedURL, at: time)
            let box = bubble(synced.webcam, in: a)
            let want = Self.palette[Self.colorIndex(world: time)]
            // The screen, away from the bubble, and the bubble's middle.
            let screenColor = TestVideos.averageColor(of: a, x: 0.3, y: 0.3)
            let cameraColor = average(a, box, at: 0.5, 0.45)
            #expect(TestVideos.close(screenColor, want), "screen at \(time)s shows \(screenColor), wanted \(want)")
            #expect(TestVideos.close(cameraColor, want), "synced camera at \(time)s shows \(cameraColor), wanted the screen's \(want)")
            let unsyncedCamera = average(b, box, at: 0.5, 0.45)
            if !TestVideos.close(unsyncedCamera, want) { mismatches += 1 }
            let name = String(format: "%.2fs", time)
            try TestVideos.save(a, as: frames.appendingPathComponent("\(name)-1-synced.png"))
            try TestVideos.save(b, as: frames.appendingPathComponent("\(name)-2-unsynced.png"))
        }
        #expect(mismatches >= 5, "without the offset the camera is out of step (\(mismatches) of 7 differ)")

        // 3. Before the camera started (0.7 s), there's no bubble.
        let early = try await TestVideos.frame(ofMovie: syncedURL, at: 0.3)
        try TestVideos.save(early, as: frames.appendingPathComponent("0.30s-1-synced-before-the-camera-started.png"))
        let spot = average(early, bubble(synced.webcam, in: early), at: 0.5, 0.45)
        let screenThen = Self.palette[Self.colorIndex(world: 0.3)]
        #expect(!TestVideos.close(spot, Self.palette[Self.colorIndex(world: Self.lag)]), "no camera frame before it started: \(spot)")
        #expect(TestVideos.close(spot, screenThen) || TestVideos.close(spot, (1, 1, 1)), "the screen or the background shows there: \(spot)")
        print("Imported camera frames saved in \(frames.path)")
    }

    @Test func everyCameraSettingWorksWithImportedFootage() async throws {
        try TestVideos.isolateStorage()
        let folder = try Self.folder()
        let screen = folder.appendingPathComponent("screen.mp4"), phone = folder.appendingPathComponent("phone.mp4")
        try await TestVideos.writeBars(to: screen, seconds: 3)
        try await TestVideos.writeQuadrants(to: phone, seconds: 3)
        let camera = try #require(await VideoImportedCamera.read(phone, offset: 0))
        let frames = try TestVideos.framesDirectory("imported-camera")
        let yellow = TestVideos.quadrantColors[3], red = TestVideos.quadrantColors[0]
        let blue: RGB = (0, 0.4, 1)
        func render(_ name: String, at time: Double = 1.5, _ change: (inout VideoDemoProject) -> Void) async throws -> (VideoDemoProject, CGImage) {
            let edit = project(screen: screen, camera: camera) { project in
                project.background = .color(VideoRGBA(1, 1, 1))
                change(&project)
            }
            let url = folder.appendingPathComponent("\(name).mp4")
            try await TestVideos.export(edit, to: url)
            let frame = try await TestVideos.frame(ofMovie: url, at: time)
            try TestVideos.save(frame, as: frames.appendingPathComponent("look-\(name).png"))
            return (edit, frame)
        }

        // Crop to one quadrant, a border, a square.
        let (a, frameA) = try await render("crop-border") {
            $0.webcam.crop = VideoCropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
            $0.webcam.border = .init(color: VideoRGBA(blue.r, blue.g, blue.b), width: 0.012)
        }
        let boxA = bubble(a.webcam, in: frameA)
        #expect(TestVideos.close(average(frameA, boxA, at: 0.5, 0.5), yellow), "cropped to the yellow quadrant")
        let thickness = Double(frameA.height) * 0.012
        let edge = TestVideos.averageColor(of: frameA, x: (boxA.minX + thickness / 2) / Double(frameA.width), y: boxA.midY / Double(frameA.height), width: 0.001, height: 0.004)
        #expect(TestVideos.close(edge, blue, within: 0.15), "a blue border: \(edge)")

        // Mirrored, a circle, the top-left quadrant.
        let (b, frameB) = try await render("mirror-circle") {
            $0.webcam.shape = .circle
            $0.webcam.roundness = 1
            $0.webcam.mirror = true
            $0.webcam.crop = VideoCropRect(x: 0, y: 0, width: 0.5, height: 0.5)
        }
        let boxB = bubble(b.webcam, in: frameB)
        #expect(TestVideos.close(average(frameB, boxB, at: 0.5, 0.5), red), "the red quadrant, mirrored")
        #expect(!TestVideos.close(average(frameB, boxB, at: 0.05, 0.05), red, within: 0.25), "the circle's corner is background")

        // Unmirrored and uncropped: red top left; mirrored: green there.
        let (c, frameC) = try await render("whole") { _ in }
        let (_, frameD) = try await render("whole-mirrored") { $0.webcam.mirror = true }
        let boxC = bubble(c.webcam, in: frameC)
        #expect(TestVideos.close(average(frameC, boxC, at: 0.25, 0.25), red), "red top left")
        #expect(TestVideos.close(average(frameD, boxC, at: 0.25, 0.25), TestVideos.quadrantColors[1]), "mirrored: green top left")

        // Shadow: the white just outside the bubble darkens.
        let (_, frameNoShadow) = try await render("shadow-none") { $0.webcam.shadowStrength = 0 }
        let (e, frameShadow) = try await render("shadow-strong") { $0.webcam.shadowStrength = 1 }
        let boxE = bubble(e.webcam, in: frameShadow)
        let below = { (frame: CGImage) in TestVideos.averageColor(of: frame, x: boxE.midX / Double(frame.width), y: (boxE.maxY + 6) / Double(frame.height), width: 0.01, height: 0.006) }
        #expect(below(frameShadow).r < below(frameNoShadow).r - 0.03, "a strong shadow darkens below: \(below(frameShadow)) vs \(below(frameNoShadow))")

        // A full-screen layout shows the footage filling the frame.
        let (_, frameF) = try await render("fullscreen-layout") {
            $0.cameraLayouts = [VideoCameraLayoutRegion(start: 1, end: 2.5, layout: .fullscreen)]
        }
        #expect(TestVideos.close(TestVideos.averageColor(of: frameF, x: 0.3, y: 0.3), red), "full screen: red fills the top left")
        #expect(TestVideos.close(TestVideos.averageColor(of: frameF, x: 0.7, y: 0.7), yellow), "full screen: yellow fills the bottom right")

        // Background blur and removal run on imported footage too.
        let (g, frameG) = try await render("backdrop-blur") { $0.webcam.backdrop = .blur }
        #expect(TestVideos.close(average(frameG, bubble(g.webcam, in: frameG), at: 0.25, 0.25), red, within: 0.2), "blurred: still the camera picture")
        _ = try await render("backdrop-remove") { $0.webcam.backdrop = .remove }
        print("Imported camera look frames saved in \(frames.path)")
    }
}
