import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// The editor's four panels and the Library's media (1.13.0), in the light
/// and the dark look, English and German, at a large window, a 13"
/// MacBook's and the smallest (printed as SNAPSHOT-EDITOR: <path>, in
/// lfstudios-editor-113/).
@MainActor
final class VideoEditorLayoutSnapshotTests: XCTestCase {
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
        suiteName = "LFStudiosCoreTests.EditorSnapshots.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        VideoEditorPanelStore.shared.reload()
    }

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        L10n.use(nil)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        VideoEditorPanelStore.shared.reload()
    }

    private static let media = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-113-media", isDirectory: true)

    private func tone(_ name: String, seconds: Double) throws -> URL {
        let url = Self.media.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for frame in 0..<Int(frames) { buffer.floatChannelData![0][frame] = Float(sin(Double(frame) / 48_000 * 2 * .pi * 330) * 0.15) }
        try file.write(from: buffer)
        return url
    }

    private func picture(_ name: String, _ color: CIColor, size: CGSize) throws -> URL {
        let url = Self.media.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            let image = CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
                .composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(origin: .zero, size: size)))
            try VideoTestSupport.writePNG(image, size: size, to: url)
        }
        return url
    }

    private func video(_ name: String, seconds: Double, size: CGSize) async throws -> URL {
        let url = Self.media.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try await VideoTestSupport.writeFakeRecording(to: url, size: size, seconds: seconds, fps: 30, audioSeconds: seconds)
        }
        return url
    }

    /// A recording with its camera, a few tracks, and media in the Library.
    private func demoModel() async throws -> VideoEditorModel {
        try FileManager.default.createDirectory(at: Self.media, withIntermediateDirectories: true)
        let url = try await video("Product demo.mp4", seconds: 12, size: CGSize(width: 1440, height: 900))
        let cameraURL = Self.media.appendingPathComponent("camera.mov")
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
        model.mutate { project in
            project.zoomRegions = [VideoZoomRegion(start: 2, end: 4.5, scale: 2, followsCursor: true)]
            project.captions = VideoCaptionBuilder.lines(from: words.map { VideoCaptionWord(text: $0.0, start: $0.1, end: $0.1 + 0.3) })
            project.overlayEffects = [VideoDemoOverlayEffect(kind: .text, time: 4, duration: 2.5, text: "Settings")]
        }
        await model.addMusic(from: try tone("Calm piano.wav", seconds: 20))
        // In the video: a logo and a voiceover; in the Library only: more.
        await model.placeMedia([try picture("Logo.png", CIColor(red: 0.04, green: 0.42, blue: 1), size: CGSize(width: 400, height: 400))], at: 1)
        await model.placeMedia([try tone("Voiceover.wav", seconds: 4)], at: 6)
        model.importMedia([
            try await video("B-roll — office.mov", seconds: 8, size: CGSize(width: 1280, height: 720)),
            try picture("Screenshot.png", CIColor(red: 0.94, green: 0.58, blue: 0.2), size: CGSize(width: 1600, height: 1000)),
            try tone("Whoosh.wav", seconds: 1),
        ])
        let folder = model.newMediaFolder(named: "Interviews")
        model.importMedia([try await video("Interview 1.mov", seconds: 10, size: CGSize(width: 1280, height: 720))], into: folder)
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
        // Thumbnails load in the background.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-113", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT-EDITOR: \(url.path)")
        NSApp.appearance = nil
    }

    func testTheEditorsPanelsInBothLooksAndLanguagesAtThreeSizes() async throws {
        let sizes: [(String, CGSize)] = [("large", CGSize(width: 1920, height: 1200)), ("13-inch", CGSize(width: 1280, height: 772))]
        for language in ["en", "de"] {
            L10n.use(language)
            let model = try await demoModel()
            for (sizeName, size) in sizes {
                for (lookName, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    try await render(model, size: size, look: look, name: "editor-\(language)-\(lookName)-\(sizeName)")
                }
            }
        }
        // The smallest window, Player First, and the Audio tab as a list.
        L10n.use("en")
        let model = try await demoModel()
        try await render(model, size: CGSize(width: 1080, height: 700), look: .aqua, name: "editor-en-light-smallest")
        VideoEditorPanelStore.shared.choose(.playerFirst)
        try await render(model, size: CGSize(width: 1440, height: 900), look: .darkAqua, name: "editor-en-dark-player-first")
        VideoEditorPanelStore.shared.reset()
        Settings.videoMediaBinAsList = true
        model.libraryTab = .audio
        try await render(model, size: CGSize(width: 1440, height: 900), look: .aqua, name: "editor-en-light-audio-list")
    }
}
