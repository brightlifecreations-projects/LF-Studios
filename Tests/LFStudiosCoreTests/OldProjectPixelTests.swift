import AppKit
import AVFoundation
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Projects made before 1.14.0 look exactly as they did: frames of each
/// kind of project, rendered by this version, against the frames LF Studios
/// 1.13.0 rendered of the same recordings (Fixtures/OldProjects, written
/// by running this test there with LF_PIXEL_RECORD=1).
final class OldProjectPixelTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/OldProjects", isDirectory: true)
    private var recording: Bool { ProcessInfo.processInfo.environment["LF_PIXEL_RECORD"] != nil }
    private let size = CGSize(width: 640, height: 360)

    private func file(_ name: String) -> URL { Self.fixtures.appendingPathComponent(name) }

    /// The recordings every frame is made from (written once, then kept).
    private func media() async throws -> (screen: URL, camera: URL, logo: URL) {
        try FileManager.default.createDirectory(at: Self.fixtures, withIntermediateDirectories: true)
        let screen = file("screen.mp4"), camera = file("camera.mp4"), logo = file("logo.png")
        if !FileManager.default.fileExists(atPath: screen.path) {
            guard recording else { throw XCTSkip("Fixtures/OldProjects is missing: run once with LF_PIXEL_RECORD=1 on 1.13.0") }
            try await VideoTestSupport.writeFakeRecording(to: screen, size: CGSize(width: 960, height: 600), seconds: 4, fps: 30)
            try await VideoInspection.writeColorVideo(to: camera, size: CGSize(width: 320, height: 240), colors: [(.orange, 2), (.purple, 2)])
            try VideoInspection.writePNG(to: logo, size: CGSize(width: 120, height: 60), color: .systemTeal)
        }
        return (screen, camera, logo)
    }

    /// Each kind of project from before 1.14.0, and the moments compared.
    private func projects(_ media: (screen: URL, camera: URL, logo: URL)) -> [(name: String, project: VideoDemoProject, recording: VideoDemoRecordingMetadata?, camera: Bool, times: [Double])] {
        let size = CGSize(width: 960, height: 600)
        func base() -> VideoDemoProject { VideoDemoProject.make(sourceURL: media.screen, duration: 4, sourceSize: size) }
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 4)
        var metadata = VideoDemoRecordingMetadata(videoURLPath: media.screen.path, createdAt: Date(timeIntervalSince1970: 0), duration: 4, sourceWidth: 960, sourceHeight: 600, fps: 30,
                                                  nativeCursorVisible: false, cursorSamples: samples, clickEvents: clicks, pointPixelScale: 2, renderCursor: true)

        var styled = base()
        styled.background = .gradient("graphite")
        styled.shadow = 0.8

        var zoomed = base()
        zoomed.cursorSamples = samples
        zoomed.clickEvents = clicks
        zoomed.nativeCursorVisible = false
        zoomed.zoomRegions = [VideoZoomRegion(start: 1, end: 3.5, scale: 2, followsCursor: true)]

        var annotated = base()
        annotated.overlayEffects = [
            VideoDemoOverlayEffect(kind: .text, time: 0.5, duration: 3, x: 0.3, y: 0.3, width: 0.3, height: 0.1, text: "Settings"),
            VideoDemoOverlayEffect(kind: .arrow, time: 0.5, duration: 3, x: 0.6, y: 0.5, layer: 1),
            VideoDemoOverlayEffect(kind: .highlight, time: 0.5, duration: 3, x: 0.7, y: 0.7, width: 0.2, height: 0.1, layer: 2),
            VideoDemoOverlayEffect(kind: .blur, time: 0.5, duration: 3, x: 0.2, y: 0.75, width: 0.2, height: 0.1, layer: 3),
        ]
        var picture = VideoDemoOverlayEffect(kind: .image, time: 0.5, duration: 3, x: 0.85, y: 0.15, width: 0.15, height: 0.1, text: "logo", layer: 4)
        picture.image = VideoOverlayImage(path: media.logo.path, name: "logo.png", aspect: 2)
        annotated.overlayEffects.append(picture)

        var captioned = base()
        captioned.captions = VideoCaptionBuilder.lines(from: [("Open", 0.5), ("the", 0.8), ("settings", 1.0), ("panel.", 1.4)].map { VideoCaptionWord(text: $0.0, start: $0.1, end: $0.1 + 0.3) })
        captioned.keystrokes = [VideoKeystrokeEvent(time: 1.0, keys: ["⌘", ","])]
        captioned.keystrokeStyle.visible = true

        var edited = base()
        edited.timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 1.5, speed: 2), VideoDemoTimelineClip(sourceStart: 2, sourceEnd: 4)]
        edited.cards.intro = VideoTitleCard(enabled: true, title: "Welcome", subtitle: "A short tour", duration: 1)
        edited.transitions.betweenClips = .dissolve
        edited.transitions.fadeIn = 0.3

        var camera = base()
        metadata.webcam = VideoWebcamRecording(path: media.camera.path, offset: 0, width: 320, height: 240)
        camera.webcam.visible = true
        camera.webcam.shape = .rectangle

        return [
            ("styled", styled, nil, false, [0.5, 2]),
            ("zoomed", zoomed, metadata, false, [0.8, 2.2]),
            ("annotated", annotated, nil, false, [1.5]),
            ("captioned", captioned, nil, false, [1.1]),
            ("edited", edited, nil, false, [0.5, 1.2, 1.76, 2.6]),
            ("camera", camera, metadata, true, [1, 3]),
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

    func testOlderProjectsLookExactlyAsBefore() async throws {
        let media = try await media()
        var compared = 0
        for kind in projects(media) {
            // Saved by this version: nothing only 1.14.0 shows.
            XCTAssertFalse(kind.project.needsLayerFormat, kind.name)
            let encoded = String(decoding: try JSONEncoder().encode(kind.project), as: UTF8.self)
            for key in ["layerTracks", "mirrored", "quarterTurns", "disabled", "rotation\""] {
                XCTAssertFalse(encoded.contains(key), "\(kind.name) writes nothing new (\(key))")
            }
            for time in kind.times {
                let image = try render(kind.project, recording: kind.recording, camera: kind.camera ? media.camera : nil, at: time)
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
                XCTAssertLessThanOrEqual(worst, 1, "\(kind.name) at \(time) s: \(differing) values differ, by up to \(worst)")
                compared += 1
            }
        }
        if !recording { XCTAssertEqual(compared, 12) }
    }
}
