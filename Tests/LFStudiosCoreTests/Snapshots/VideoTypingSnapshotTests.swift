import SwiftUI
import XCTest
@testable import LFStudiosCore

/// The Zoom panel's typing, loupe and camera buttons, a selected loupe's
/// settings, and the cursor style picker, in English, German (the
/// longest words), French and Russian: everything fits the inspector's width.
@MainActor
final class VideoTypingSnapshotTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        VideoTestStorage.isolate()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-typing-snaps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        L10n.use(nil)
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("recording.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private func render<V: View>(_ view: V, size: CGSize, name: String) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top).background(VideoEditorTheme.panel).environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 400_000_000)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let base = ProcessInfo.processInfo.environment["LFSTUDIOS_TEST_FRAMES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-ux", isDirectory: true)
        let out = base.appendingPathComponent("typing", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let url = out.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT: \(url.path)")
        return rep
    }

    func testPanelsInSeveralLanguages() async throws {
        let url = directory.appendingPathComponent("recording.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 1280, height: 800), seconds: 8, fps: 30)
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 8)
        var metadata = VideoDemoRecordingMetadata(videoURLPath: url.path, createdAt: Date(), duration: 8, sourceWidth: 1280, sourceHeight: 800, fps: 30, nativeCursorVisible: false, cursorSamples: samples, clickEvents: clicks, pointPixelScale: 2, renderCursor: true)
        metadata.textCursor = stride(from: 2.0, through: 6.0, by: 0.15).enumerated().map { VideoTextCursorSample(time: $1, x: 0.2 + Double($0) * 0.004, y: 0.3, width: 0, height: 0.02) }
        VideoDemoSidecarStore.save(metadata, for: url)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.hasTypingPositions)
        model.seek(to: 2)
        model.addLoupe()
        let loupe = try XCTUnwrap(model.project.zoomRegions.first)
        model.setZoomFollow(loupe.id, .typing)
        model.setStyle { $0.cursor.style = .ring }

        for language in ["en", "de", "fr", "ru"] {
            L10n.use(language)
            let zoom = try XCTUnwrap(model.project.zoomRegions.first)
            let panel = try await render(
                ScrollView { VStack(alignment: .leading, spacing: 22) { VideoZoomInspector(model: model) }.padding(16) },
                size: CGSize(width: 320, height: 900), name: "zoom-panel-\(language)")
            XCTAssertGreaterThan(panel.pixelsWide, 0)
            _ = try await render(
                VStack(alignment: .leading, spacing: 22) { VideoZoomBlockControls(model: model, zoom: zoom) }.padding(16),
                size: CGSize(width: 320, height: 760), name: "loupe-controls-\(language)")
            _ = try await render(
                VStack(alignment: .leading, spacing: 22) {
                    VideoCursorStylePicker(model: model)
                    VideoTypingSpeedSection(model: model)
                }.padding(16),
                size: CGSize(width: 320, height: 260), name: "cursor-typing-\(language)")
        }
    }
}
