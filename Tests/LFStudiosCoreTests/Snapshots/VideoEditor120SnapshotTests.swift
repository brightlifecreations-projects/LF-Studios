import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// 1.20.0: the built-in Assistant, after a request that edited the video
/// (its changes waiting for Keep or Revert All), and Settings ▸ AI, in both
/// layouts and looks (printed as SNAPSHOT-120: <path>, in
/// lfstudios-editor-120/). The provider is a local mock; the keys are
/// made up.
@MainActor
final class VideoEditor120SnapshotTests: XCTestCase {
    private var suiteName: String!
    private var windows: [NSWindow] = []
    private var directory: URL!
    private var server: MockAIServer!

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
        suiteName = "LFStudiosCoreTests.Editor120.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        Settings.videoShortcutsChangeSeen = true
        Settings.videoPanelTipSeen = true
        VideoEditorPanelStore.shared.reload()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-120-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VideoAgentHub.shared.reset()
        let keys = VideoAIMemoryKeys()
        try keys.setKey("sk-ant-api03-EXAMPLEKEY-x9Q2", for: .anthropic)
        try keys.setKey("sk-proj-EXAMPLEKEY-0000000000-Lm4T", for: .openAI)
        VideoAIKeys.store = keys
        Settings.videoAIProvider = .anthropic
        Settings.setVideoAIModelList([
            VideoAIModel(id: "claude-opus-5-5", name: "Claude Opus 5.5", created: 3), VideoAIModel(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", created: 2),
            VideoAIModel(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", created: 1),
        ], for: .anthropic)
        Settings.setVideoAIModel("claude-opus-5-5", for: .anthropic)
        Settings.setVideoAIModelList([VideoAIModel(id: "gpt-6.1-sol", name: "gpt-6.1-sol", created: 2), VideoAIModel(id: "gpt-6-luna", name: "gpt-6-luna", created: 1)], for: .openAI)
        Settings.setVideoAIModel("gpt-6.1-sol", for: .openAI)
        VideoAISettingsModel.shared.status = [:]
        VideoAISettingsModel.shared.refresh()
        server = try MockAIServer()
        VideoAIHTTP.baseURLs[.anthropic] = server.url
    }

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        VideoAgentHub.shared.reset()
        VideoAIHTTP.baseURLs = VideoAIHTTP.defaultBaseURLs
        VideoAIKeys.store = VideoAIMemoryKeys()
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        VideoEditorPanelStore.shared.reload()
        server = nil
        try? FileManager.default.removeItem(at: directory)
    }

    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-120", isDirectory: true)
    private let looks: [(String, NSAppearance.Name)] = [("dark", .darkAqua), ("light", .aqua)]

    private func event(_ type: String, _ fields: [String: VideoAgentJSON] = [:]) -> VideoAgentJSON {
        .object(fields.merging(["type": .string(type)]) { a, _ in a })
    }

    /// A tool call in Anthropic's streaming format.
    private func call(_ id: String, _ name: String, _ arguments: String, input: Int, output: Int) -> MockAIServer.Response {
        .events([
            event("message_start", ["message": .object(["usage": .object(["input_tokens": .number(Double(input)), "output_tokens": .number(1)])])]),
            event("content_block_start", ["index": .number(0), "content_block": .object(["type": .string("tool_use"), "id": .string(id), "name": .string(name), "input": .object([:])])]),
            event("content_block_delta", ["index": .number(0), "delta": .object(["type": .string("input_json_delta"), "partial_json": .string(arguments)])]),
            event("content_block_stop", ["index": .number(0)]),
            event("message_delta", ["delta": .object(["stop_reason": .string("tool_use")]), "usage": .object(["output_tokens": .number(Double(output))])]),
        ])
    }

    private func answer(_ text: String, input: Int, output: Int) -> MockAIServer.Response {
        .events([
            event("message_start", ["message": .object(["usage": .object(["input_tokens": .number(Double(input)), "output_tokens": .number(1)])])]),
            event("content_block_start", ["index": .number(0), "content_block": .object(["type": .string("text"), "text": .string("")])]),
            event("content_block_delta", ["index": .number(0), "delta": .object(["type": .string("text_delta"), "text": .string(text)])]),
            event("content_block_stop", ["index": .number(0)]),
            event("message_delta", ["delta": .object(["stop_reason": .string("end_turn")]), "usage": .object(["output_tokens": .number(Double(output))])]),
        ])
    }

    /// A recording, and one request to the Assistant that split it, added
    /// a marker and answered.
    private func assistantAtWork() async throws -> VideoEditorModel {
        var options = VideoEditorTestModel.Options()
        options.seconds = 12
        options.size = CGSize(width: 1440, height: 900)
        options.audio = true
        let model = try await VideoEditorTestModel.make(in: directory, name: "Product demo.mp4", options)
        model.mutate { project in
            project.captions = [
                VideoCaptionLine(start: 0.4, end: 2.2, text: "Open the settings"),
                VideoCaptionLine(start: 2.6, end: 4.6, text: "and pick a theme"),
                VideoCaptionLine(start: 5, end: 7.5, text: "Your changes save as you go"),
            ]
        }
        model.endGesture()
        server.script(call("t1", "get_timeline", "{}", input: 2_840, output: 38),
                      call("t2", "split", #"{"time": 4.8}"#, input: 3_910, output: 41),
                      call("t3", "add_marker", #"{"time": 2.6}"#, input: 4_020, output: 36),
                      answer("I split the clip at 0:04.8, where the theme picker closes, and added a marker at 0:02.6 where the settings open. Keep them, or Revert All to undo both.", input: 4_150, output: 64))
        let assistant = VideoAIAssistant.of(model)
        assistant.send("Split where the theme picker closes and mark where the settings open")
        for _ in 0..<200 where assistant.isWorking { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(assistant.isWorking)
        model.seek(to: 4.8)
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
        print("SNAPSHOT-120: \(url.path)")
        window.orderOut(nil)
        return url
    }

    func testTheAssistantIn120() async throws {
        let model = try await assistantAtWork()
        let messages = try XCTUnwrap(model.project.aiChat?.messages)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last?.actions?.count, 2, "split and marker")
        XCTAssertEqual(VideoAgentHub.shared.run(for: model)?.reviewing, true)
        let size = CGSize(width: 1680, height: 1050)
        try await forEachEditorStyle { style in
            let tag = style == .lfStudios ? "new" : "capcut"
            VideoEditorPanelStore.shared.show(.assistant)
            for (lookName, look) in looks {
                try await render(VideoEditorRootView(model: model), size: size, look: look, name: "assistant-\(tag)-\(lookName)")
                try await render(VideoAssistantPanel(model: model), size: CGSize(width: 380, height: 700), look: look, name: "panel-\(tag)-\(lookName)")
            }
        }
        // Settings ▸ AI (it has no layouts of its own): two keys saved, one
        // being checked, frames off.
        VideoAISettingsModel.shared.status = [.openAI: L("The key works: \(2) models")]
        for (lookName, look) in looks {
            let selection = PreferencesSelectionModel()
            selection.selectedTab = .ai
            try await render(PreferencesRootView(selection: selection), size: CGSize(width: 700, height: 900), look: look, name: "settings-ai-\(lookName)")
        }
        // No key key ever shows: the dots and the last 4 characters only.
        XCTAssertEqual(VideoAISettingsModel.shared.masked(.anthropic), "••••x9Q2")
    }
}
