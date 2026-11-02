import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// 1.19.0: an AI agent at work (the Agent panel's feed and Tacks), its
/// changes in review (Keep / Revert all, marked on the timeline), the
/// connected dot, and Settings ▸ Agent, in both layouts and looks (printed
/// as SNAPSHOT-119: <path>, in lfstudios-editor-119/).
@MainActor
final class VideoEditor119SnapshotTests: XCTestCase {
    private var suiteName: String!
    private var windows: [NSWindow] = []
    private var directory: URL!

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
        suiteName = "LFStudiosCoreTests.Editor119.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        Settings.videoShortcutsChangeSeen = true
        Settings.videoPanelTipSeen = true
        VideoEditorPanelStore.shared.reload()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-119-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VideoAgentHub.shared.endpointFile = directory.appendingPathComponent("agent-endpoint.json")
        VideoAgentHub.shared.reset()
    }

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        VideoAgentHub.shared.setEnabled(false)
        VideoAgentHub.shared.reset()
        VideoAgentProtocol.shared.target = { VideoDemoEditorWindowController.agentModel }
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        VideoEditorPanelStore.shared.reload()
        try? FileManager.default.removeItem(at: directory)
    }

    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-119", isDirectory: true)
    private let looks: [(String, NSAppearance.Name)] = [("dark", .darkAqua), ("light", .aqua)]

    /// A recording with captions, worked on by an agent: two cuts, a fixed
    /// caption, a marker, two Tacks.
    private func agentAtWork() async throws -> VideoEditorModel {
        var options = VideoEditorTestModel.Options()
        options.seconds = 12
        options.size = CGSize(width: 1440, height: 900)
        options.audio = true
        let model = try await VideoEditorTestModel.make(in: directory, name: "Product demo.mp4", options)
        model.mutate { project in
            project.captions = [
                VideoCaptionLine(start: 0.4, end: 2.2, text: "Open the setings"),
                VideoCaptionLine(start: 2.6, end: 4.6, text: "and pick a theme"),
                VideoCaptionLine(start: 5, end: 7.5, text: "Your changes save as you go"),
            ]
        }
        model.endGesture()
        let hub = VideoAgentHub.shared
        hub.setEnabled(true)
        for _ in 0..<100 where !hub.isListening { try await Task.sleep(nanoseconds: 20_000_000) }
        hub.noteActivity(client: "Claude")
        VideoAgentProtocol.shared.target = { model }
        let tools = VideoAgentProtocol.shared.tools
        func call(_ name: String, _ args: [String: VideoAgentJSON] = [:]) async {
            guard let tool = tools.first(where: { $0.name == name }) else { return XCTFail(name) }
            _ = await VideoAgentProtocol.shared.call(tool, .object(args))
        }
        await call("begin_agent_session", ["goal": .string("Tighten the intro, fix a caption, and mark where the settings open.")])
        await call("split", ["time": .number(4)])
        await call("split", ["time": .number(8)])
        await call("set_caption_text", ["caption_id": .string(model.project.captions[0].id.uuidString), "text": .string("Open the settings")])
        await call("add_marker", ["time": .number(2.6)])
        await call("add_tack", ["time": .number(4.2), "text": .string("I kept the pause after the click: it gives the menu time to open.")])
        await call("add_tack", ["time": .number(8.6), "text": .string("Cut the last 2 seconds where nothing happens?"), "question": .bool(true)])
        model.seek(to: 5.2)
        return model
    }

    @discardableResult
    private func render<Content: View>(_ content: Content, size: CGSize, look: NSAppearance.Name, name: String) async throws -> URL {
        let dark = look == .darkAqua
        NSApp.appearance = NSAppearance(named: look)
        defer { NSApp.appearance = nil }
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: look)
        window.contentView = host
        window.orderFrontRegardless()
        windows.append(window)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 900_000_000)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let url = Self.folder.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT-119: \(url.path)")
        window.orderOut(nil)
        return url
    }

    func testAnAgentAtWorkIn119() async throws {
        let model = try await agentAtWork()
        let hub = VideoAgentHub.shared
        let run = try XCTUnwrap(hub.run(for: model))
        XCTAssertGreaterThanOrEqual(run.changes.count, 4)
        XCTAssertEqual(run.tacks.count, 2)
        XCTAssertTrue(VideoEditorPanelStore.shared.showsAgentPanel)
        let size = CGSize(width: 1680, height: 1050)
        try await forEachEditorStyle { style in
            let tag = style == .lfStudios ? "new" : "capcut"
            VideoEditorPanelStore.shared.showAgentPanel()
            for (lookName, look) in looks {
                // At work: the feed and the Tacks.
                run.reviewing = false
                try await render(VideoEditorRootView(model: model), size: size, look: look, name: "agent-\(tag)-\(lookName)")
                try await render(VideoAgentPanel(model: model), size: CGSize(width: 380, height: 640), look: look, name: "panel-\(tag)-\(lookName)")
                // Done: Keep or Revert all, the changes marked on the timeline.
                run.reviewing = true
                try await render(VideoEditorRootView(model: model), size: size, look: look, name: "review-\(tag)-\(lookName)")
            }
            run.reviewing = false
        }
        // Settings ▸ Agent, switched on (it has no layouts of its own).
        for (lookName, look) in looks {
            let selection = PreferencesSelectionModel()
            selection.selectedTab = .agent
            try await render(PreferencesRootView(selection: selection), size: CGSize(width: 600, height: 720), look: look, name: "settings-agent-\(lookName)")
        }
    }
}
