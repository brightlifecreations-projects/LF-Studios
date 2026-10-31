import AppKit
import AVFoundation
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Projects made with 1.14.0 look exactly as they did, opened from every
/// kind of project file (.lfs, .lfsp, .lfstudios, .shotstyle): frames
/// rendered by this version against the frames LF Studios 1.14.0 rendered
/// (Fixtures/Projects114, written by running this test there with
/// LF_PIXEL_RECORD=1). The older kinds of project are in OldProjectPixelTests.
final class Project114PixelTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Projects114", isDirectory: true)
    private static let oldMedia = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/OldProjects", isDirectory: true)
    private var recording: Bool { ProcessInfo.processInfo.environment["LF_PIXEL_RECORD"] != nil }
    private let size = CGSize(width: 640, height: 360)

    private func file(_ name: String) -> URL { Self.fixtures.appendingPathComponent(name) }

    /// The recordings (OldProjectPixelTests' screen and camera) and a
    /// picture and a video for the tracks above the main track.
    private func media() async throws -> (screen: URL, camera: URL, logo: URL, clip: URL) {
        try FileManager.default.createDirectory(at: Self.fixtures, withIntermediateDirectories: true)
        let screen = Self.oldMedia.appendingPathComponent("screen.mp4"), camera = Self.oldMedia.appendingPathComponent("camera.mp4"), logo = Self.oldMedia.appendingPathComponent("logo.png")
        guard FileManager.default.fileExists(atPath: screen.path) else { throw XCTSkip("Fixtures/OldProjects is missing") }
        let clip = file("clip.mp4")
        if !FileManager.default.fileExists(atPath: clip.path) {
            guard recording else { throw XCTSkip("Fixtures/Projects114 is missing: run once with LF_PIXEL_RECORD=1 on 1.14.0") }
            try await VideoInspection.writeColorVideo(to: clip, size: CGSize(width: 320, height: 180), colors: [(.systemGreen, 2), (.systemPink, 2)])
        }
        return (screen, camera, logo, clip)
    }

    /// Each kind of 1.14.0 project, and the moments compared.
    private func projects(_ media: (screen: URL, camera: URL, logo: URL, clip: URL)) -> [(name: String, project: VideoDemoProject, recording: VideoDemoRecordingMetadata?, camera: Bool, times: [Double])] {
        let size = CGSize(width: 960, height: 600)
        func base() -> VideoDemoProject { VideoDemoProject.make(sourceURL: media.screen, duration: 4, sourceSize: size) }

        // Clips on two tracks above the main track: a turned, faded,
        // cropped, mirrored picture and a video at its own speed.
        var layered = base()
        var picture = VideoLayerItem(kind: .image, path: media.logo.path, name: "logo.png", at: 0.5, length: 3, aspect: 2)
        picture.x = 0.7
        picture.y = 0.3
        picture.width = 0.3
        picture.rotation = 20
        picture.opacity = 0.7
        picture.mirrored = true
        picture.crop = VideoCropRect(x: 0.1, y: 0, width: 0.8, height: 1)
        var video = VideoLayerItem(kind: .video, path: media.clip.path, name: "clip.mp4", at: 1, length: 2.5, fileDuration: 4, aspect: 16.0 / 9)
        video.x = 0.3
        video.y = 0.65
        video.width = 0.35
        video.speed = 1.5
        layered.layerTracks = [VideoLayerTrack(items: [video]), VideoLayerTrack(items: [picture])]

        // The timeline's tools on the main track, a turned camera and text.
        var tools = base()
        tools.timelineClips = [
            VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 1.5),
            VideoDemoTimelineClip(sourceStart: 1.5, sourceEnd: 3),
            VideoDemoTimelineClip(sourceStart: 3, sourceEnd: 4),
        ]
        tools.timelineClips[0].mirrored = true
        tools.timelineClips[1].quarterTurns = 1
        tools.timelineClips[2].disabled = true
        var text = VideoDemoOverlayEffect(kind: .text, time: 0.2, duration: 3.5, x: 0.4, y: 0.35, width: 0.3, height: 0.1, text: "Turned")
        text.rotation = 15
        tools.overlayEffects = [text]
        tools.webcam.visible = true
        tools.webcam.rotation = 30
        var metadata = VideoDemoRecordingMetadata(videoURLPath: media.screen.path, createdAt: Date(timeIntervalSince1970: 0), duration: 4, sourceWidth: 960, sourceHeight: 600, fps: 30,
                                                  nativeCursorVisible: true, cursorSamples: [], clickEvents: [], pointPixelScale: 2, renderCursor: false)
        metadata.webcam = VideoWebcamRecording(path: media.camera.path, offset: 0, width: 320, height: 240)

        return [
            ("layered", layered, nil, false, [0.7, 1.6, 2.9]),
            ("tools", tools, metadata, true, [0.6, 2.1, 3.5]),
        ]
    }

    private func frame(_ url: URL, at time: Double) -> CIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return (try? generator.copyCGImage(at: CMTime(seconds: max(time, 0), preferredTimescale: 600), actualTime: nil)).map { CIImage(cgImage: $0) }
    }

    /// The frame at `time` exactly as the export draws it.
    private func render(_ project: VideoDemoProject, recording: VideoDemoRecordingMetadata?, camera: URL?, at time: Double) throws -> CGImage {
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 4, recording: recording, hasWebcam: camera != nil)
        let sourceTime = plan.sourceTime(forTimelineTime: time)
        var options = VideoFrameRenderer.Options(frameRate: 30)
        if let camera { options.webcamFrame = frame(camera, at: sourceTime) }
        options.layerFrames = VideoLayerStills.frames(for: plan.layers, at: time)
        if let request = plan.heldFrameRequest(at: time) { options.transitionFrame = frame(project.sourceURL, at: request.sourceTime) }
        let image = VideoFrameRenderer().render(source: frame(project.sourceURL, at: sourceTime), timelineTime: time, plan: plan, outputSize: size, options: options)
        return try XCTUnwrap(VideoRenderContext.shared.createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    func testProjectsFrom114LookExactlyAsBefore() async throws {
        let media = try await media()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-114-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var compared = 0
        for kind in projects(media) {
            // Saved, then opened, as every kind of project file.
            for fileExtension in recording ? ["lfs"] : ["lfs", "lfsp", "lfstudios", "shotstyle"] {
                let package = folder.appendingPathComponent("\(kind.name).\(fileExtension)")
                _ = try VideoProjectPackage.save(VideoProjectContents(project: kind.project, recording: kind.recording, sourceRecordings: [:]), to: package, mode: .linked)
                let opened = try VideoProjectPackage.open(package)
                let project = opened.contents.project
                for time in kind.times {
                    let image = try render(project, recording: opened.contents.recording, camera: kind.camera ? media.camera : nil, at: time)
                    let reference = file("\(kind.name)-\(time).png")
                    if recording {
                        let rep = NSBitmapImageRep(cgImage: image)
                        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: reference)
                        continue
                    }
                    let saved = try XCTUnwrap(NSImage(contentsOf: reference)?.cgImage(forProposedRect: nil, context: nil, hints: nil), "\(reference.lastPathComponent) is missing")
                    let a = pixels(image), b = pixels(saved)
                    XCTAssertEqual(a.count, b.count)
                    var worst = 0
                    var differing = 0
                    for index in a.indices where a[index] != b[index] {
                        worst = max(worst, abs(Int(a[index]) - Int(b[index])))
                        differing += 1
                    }
                    XCTAssertLessThanOrEqual(worst, 1, "\(kind.name).\(fileExtension) at \(time) s: \(differing) values differ, by up to \(worst)")
                    compared += 1
                }
            }
        }
        if !recording { XCTAssertEqual(compared, 24) }
    }
}
