import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// The bigger timeline (1.11.0) with every kind of track, in the light and
/// the dark look, English and German, at a large and a 13" MacBook window
/// (printed as SNAPSHOT-TIMELINE: <path>, in lfstudios-timeline-111/).
@MainActor
final class VideoTimelineSnapshotTests: XCTestCase {
    private var suiteName: String!
    private var windows: [NSWindow] = []

    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
        VideoStageView.drawsStills = true
    }

    override class func tearDown() {
        VideoStageView.drawsStills = false
        super.tearDown()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        suiteName = "LFStudiosCoreTests.TimelineSnapshots.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        L10n.use(nil)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
    }

    /// A recording with the camera, and something on every track.
    private func demoModel() async throws -> VideoEditorModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-timeline-111-media", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Product demo.mp4")
        let cameraURL = directory.appendingPathComponent("camera.mov")
        if !FileManager.default.fileExists(atPath: url.path) {
            try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 1440, height: 900), seconds: 12, fps: 30, audioSeconds: 12)
        }
        if !FileManager.default.fileExists(atPath: cameraURL.path) {
            try await VideoTestSupport.writeFakeRecording(to: cameraURL, size: CGSize(width: 640, height: 480), seconds: 12, fps: 30)
        }
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 12)
        var metadata = VideoDemoRecordingMetadata(videoURLPath: url.path, createdAt: Date(), duration: 12, sourceWidth: 1440, sourceHeight: 900, fps: 30, nativeCursorVisible: false, cursorSamples: samples, clickEvents: clicks, pointPixelScale: 2, renderCursor: true)
        metadata.webcam = VideoWebcamRecording(path: cameraURL.path, offset: 0, width: 640, height: 480)
        VideoDemoSidecarStore.save(metadata, for: url)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        try? await Task.sleep(nanoseconds: 600_000_000)
        let words: [(String, Double)] = [("Open", 1.0), ("the", 1.3), ("settings", 1.45), ("panel.", 1.9), ("Then", 3.0), ("pick", 3.3), ("a", 3.5), ("theme.", 3.6)]
        let voiceover = VideoExternalAudioTrack(path: directory.appendingPathComponent("voiceover.wav").path, name: "Voiceover.wav", duration: 4, at: 6)
        model.mutate { project in
            project.zoomRegions = [VideoZoomRegion(start: 2, end: 4.5, scale: 2, followsCursor: true)]
            project.captions = VideoCaptionBuilder.lines(from: words.map { VideoCaptionWord(text: $0.0, start: $0.1, end: $0.1 + 0.3) })
            project.keystrokes = [VideoKeystrokeEvent(time: 2.0, keys: ["⌘", ","]), VideoKeystrokeEvent(time: 5.2, keys: ["⇧", "⌘", "S"])]
            project.keystrokeStyle.visible = true
            project.overlayEffects = [
                VideoDemoOverlayEffect(kind: .text, time: 4, duration: 2.5, text: "Settings"),
                VideoDemoOverlayEffect(kind: .arrow, time: 5, duration: 2, layer: 1),
            ]
            project.cameraLayouts = [VideoCameraLayoutRegion(start: 8, end: 10.5, layout: .sideBySide)]
            project.music = VideoMusicTrack(path: directory.appendingPathComponent("song.m4a").path, name: "Calm piano.m4a", duration: 30)
            project.audioTracks = [voiceover]
            project.setTrackState(.music) { $0.muted = true }
            project.setTrackState(.annotations) { $0.locked = true }
        }
        model.seek(to: 7)
        model.splitAtPlayhead()
        model.selection = .none
        model.seek(to: 3.2)
        return model
    }

    private func render(_ model: VideoEditorModel, size: CGSize, look: NSAppearance.Name, name: String) async throws {
        let dark = look == .darkAqua
        NSApp.appearance = NSAppearance(named: look)
        let host = NSHostingView(rootView: VideoEditorRootView(model: model).frame(width: size.width, height: size.height).environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: look)
        window.contentView = host
        windows.append(window)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 700_000_000)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-timeline-111", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT-TIMELINE: \(url.path)")
        NSApp.appearance = nil
    }

    func testTheEditorWithItsTracksInBothLooksAndLanguagesAtTwoSizes() async throws {
        let sizes: [(String, CGSize)] = [("large", CGSize(width: 1920, height: 1200)), ("13-inch", CGSize(width: 1280, height: 772))]
        for language in ["en", "de"] {
            L10n.use(language)
            let model = try await demoModel()
            for (sizeName, size) in sizes {
                // The timeline as it opens: a third of a large window, 40%
                // and Small tracks on a 13" one.
                let timeline = VideoEditorLayout.timelineHeight(windowHeight: size.height, fraction: VideoEditorLayout.defaultFraction(windowHeight: size.height))
                XCTAssertGreaterThanOrEqual(size.height - VideoEditorLayout.toolbarHeight - timeline, VideoEditorLayout.minimumPreview)
                for (lookName, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    try await render(model, size: size, look: look, name: "editor-\(language)-\(lookName)-\(sizeName)")
                }
            }
            // German names fit their headers (or show whole on hover).
            if language == "de" {
                XCTAssertEqual(VideoTimelineTrack.annotations.title(in: model.project), "Text & Anmerkungen")
            }
        }
    }
}
