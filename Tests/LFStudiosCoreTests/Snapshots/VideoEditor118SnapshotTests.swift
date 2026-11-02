import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// 1.18.0: the editor in both layouts and looks, panels moved, the blue
/// drop zone, a floating panel, the sound tracks and the playhead close up
/// (printed as SNAPSHOT-118: <path>, in lfstudios-editor-118/).
@MainActor
final class VideoEditor118SnapshotTests: XCTestCase {
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
        suiteName = "LFStudiosCoreTests.Editor118.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        Settings.videoShortcutsChangeSeen = true
        Settings.videoPanelTipSeen = true
        VideoEditorPanelStore.shared.reload()
    }

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        VideoEditorPanelStore.shared.reload()
    }

    private static let media = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-118-media", isDirectory: true)
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-118", isDirectory: true)
    private let looks: [(String, NSAppearance.Name)] = [("dark", .darkAqua), ("light", .aqua)]

    /// A recording with its microphone and the Mac's sound, cut in three,
    /// captions, a title above, and the last clip's sound unlinked and moved.
    private func demoModel() async throws -> VideoEditorModel {
        try FileManager.default.createDirectory(at: Self.media, withIntermediateDirectories: true)
        var options = VideoEditorTestModel.Options()
        options.seconds = 12
        options.size = CGSize(width: 1440, height: 900)
        options.audio = true
        options.audioTracks = [.microphone, .system]
        let directory = Self.media.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = try await VideoEditorTestModel.make(in: directory, name: "Product demo.mp4", options)
        try? await Task.sleep(nanoseconds: 500_000_000)
        model.mutate { project in
            project.captions = [
                VideoCaptionLine(start: 0.4, end: 2.2, text: "Open the settings"),
                VideoCaptionLine(start: 2.6, end: 4.6, text: "and pick a theme"),
                VideoCaptionLine(start: 5, end: 7.5, text: "Your changes save as you go"),
            ]
        }
        model.seek(to: 4)
        model.perform(.split)
        model.seek(to: 8)
        model.perform(.split)
        _ = model.addTextTemplate(try XCTUnwrap(VideoTextTemplate.all.first { $0.id == "title-pop" }), at: 1)
        model.selection = .clip(try XCTUnwrap(model.project.timelineClips.last?.id))
        model.perform(.clip(.unlinkAudio))
        model.perform(.clip(.setAudioOffset(0.8)))
        model.endGesture()
        model.selection = .none
        await model.loadSoundWaveforms()
        model.seek(to: 5.2)
        return model
    }

    @discardableResult
    private func render<Content: View>(_ content: Content, size: CGSize, look: NSAppearance.Name, name: String, before: ((NSWindow) async throws -> Void)? = nil, crop: CGRect? = nil) async throws -> URL {
        let dark = look == .darkAqua
        NSApp.appearance = NSAppearance(named: look)
        defer { NSApp.appearance = nil }
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: look)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: 60, y: 60))
        window.orderFrontRegardless()
        windows.append(window)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 900_000_000)
        try await before?(window)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        var image = try XCTUnwrap(rep.cgImage)
        if let crop {
            let scale = CGFloat(image.width) / size.width
            image = try XCTUnwrap(image.cropping(to: CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)))
        }
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let url = Self.folder.appendingPathComponent("\(name).png")
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT-118: \(url.path)")
        window.orderOut(nil)
        return url
    }

    func testTheEditorIn118() async throws {
        let model = try await demoModel()
        let store = VideoEditorPanelStore.shared
        let size = CGSize(width: 1680, height: 1050)
        try await forEachEditorStyle { style in
            let tag = style == .lfStudios ? "new" : "capcut"
            for (lookName, look) in looks {
                // As it opens: the panels where 1.17.0 had them.
                store.reset()
                try await render(VideoEditorRootView(model: model), size: size, look: look, name: "editor-\(tag)-\(lookName)")
                // The sound tracks, the captions track on top.
                try await render(VideoTimelineView(model: model), size: CGSize(width: 1500, height: 470), look: look, name: "tracks-\(tag)-\(lookName)")
                // The playhead close up.
                let x = VideoTimelineMetrics.headerWidth + VideoTimelineMetrics.inset + CGFloat(5.2) * 1500 / 14
                try await render(VideoTimelineView(model: model), size: CGSize(width: 1500, height: 300), look: look, name: "playhead-\(tag)-\(lookName)",
                                 crop: CGRect(x: max(x - 180, 0), y: 30, width: 360, height: 170))
            }
            // A panel being dragged: the blue drop zone.
            store.reset()
            let dock = VideoDockDrag()
            try await render(VideoEditorRootView(model: model, dock: dock), size: size, look: .darkAqua, name: "dropzone-\(tag)-dark") { window in
                dock.window = window
                let player = try XCTUnwrap(dock.frames[.player])
                let content = try XCTUnwrap(window.contentView)
                let point = window.convertPoint(toScreen: CGPoint(x: player.maxX - 40 + dock.room.minX, y: content.bounds.height - (player.midY + dock.room.minY)))
                dock.update(.library, screen: point)
                try await Task.sleep(nanoseconds: 400_000_000)
            }
            dock.cancel()
            // Panels moved: Properties on the left, the timeline beside the player.
            store.move(.properties, to: .left, of: .library, current: .standard)
            store.move(.library, to: .bottom, of: .properties, current: store.arrangement.docked)
            for (lookName, look) in looks {
                try await render(VideoEditorRootView(model: model), size: size, look: look, name: "moved-\(tag)-\(lookName)")
            }
            // The player floating: the editor, and its window.
            store.reset()
            store.float(.player, frame: CGRect(x: 100, y: 100, width: 760, height: 520), screen: nil, current: .standard)
            try await render(VideoEditorRootView(model: model), size: size, look: .darkAqua, name: "floating-editor-\(tag)-dark")
            try await render(VideoFloatingPanelContent(kind: .player, model: model, dock: VideoDockDrag()), size: CGSize(width: 760, height: 492), look: .darkAqua, name: "floating-player-\(tag)-dark")
            store.reset()
        }
    }
}
