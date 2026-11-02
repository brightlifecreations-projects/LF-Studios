import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// 1.15.0's Library tabs, Properties panels, export window and keys editor
/// in the light and the dark look, English and German, at 1920×1200 and a
/// 13" MacBook's size (printed as SNAPSHOT-117: <path>, in
/// lfstudios-editor-117/).
@MainActor
final class VideoEditor117SnapshotTests: XCTestCase {
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
        suiteName = "LFStudiosCoreTests.Editor117.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        Settings.videoShortcutsChangeSeen = true
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

    private static let media = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-117-media", isDirectory: true)
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-117", isDirectory: true)

    /// A recording with text, a sticker, an effect clip, an adjustment clip
    /// and a compound on tracks above it, cuts with transitions.
    private func demoModel() async throws -> VideoEditorModel {
        try FileManager.default.createDirectory(at: Self.media, withIntermediateDirectories: true)
        let url = Self.media.appendingPathComponent("Product demo.mp4")
        if !FileManager.default.fileExists(atPath: url.path) {
            try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 1440, height: 900), seconds: 12, fps: 30, audioSeconds: 12)
        }
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        try? await Task.sleep(nanoseconds: 500_000_000)
        model.seek(to: 4)
        model.perform(.split)
        model.seek(to: 8)
        model.perform(.split)
        model.perform(.clip(.transitionEverywhere(.push, 0.6)))
        let title = model.addTextTemplate(try XCTUnwrap(VideoTextTemplate.all.first { $0.id == "title-pop" }), at: 1)
        model.addSticker(.heart, at: 2)
        model.addEffect(.vhs, at: 5, onSelection: false)
        model.addAdjustment(try XCTUnwrap(VideoAdjustPreset.all.first { $0.id == "teal-shadows" }), at: 6, onSelection: false)
        model.selection = .layer(title)
        model.seek(to: 1.4)
        model.perform(.addKeyframe)
        model.seek(to: 2.2)
        return model
    }

    private func render<Content: View>(_ content: Content, size: CGSize, look: NSAppearance.Name, name: String) async throws {
        let dark = look == .darkAqua
        NSApp.appearance = NSAppearance(named: look)
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: look)
        window.contentView = host
        windows.append(window)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 900_000_000)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let url = Self.folder.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT-117: \(url.path)")
        NSApp.appearance = nil
    }

    private func style(_ style: VideoEditorStyle) {
        Settings.videoEditorStyle = style
        VideoEditorPanelStore.shared.reload()
    }

    /// While building: the main window in a few looks.
    func testQuickLook() async throws {
        let model = try await demoModel()
        // The title's track with its curve lane open (LF Studios layout).
        if let title = model.selectedLayerItem, let track = model.project.layerTrackIndex(of: title.id) {
            model.curveLanes[model.project.layerTracks[track].id] = .width
        }
        for (styleName, s) in [("new", VideoEditorStyle.lfStudios), ("capcut", .capCut)] {
            style(s)
            try await render(VideoEditorRootView(model: model), size: CGSize(width: 1920, height: 1200), look: .darkAqua, name: "quick-\(styleName)-dark-large")
        }
        style(.lfStudios)
        try await render(VideoEditorRootView(model: model), size: CGSize(width: 1920, height: 1200), look: .aqua, name: "quick-new-light-large")
        L10n.use("de")
        try await render(VideoEditorRootView(model: model), size: CGSize(width: 1280, height: 772), look: .darkAqua, name: "quick-new-dark-13-inch-de")
    }
}
