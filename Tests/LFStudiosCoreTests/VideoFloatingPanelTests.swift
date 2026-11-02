import AppKit
import XCTest
@testable import LFStudiosCore

/// Floating panels (1.18.0): each in a window of its own that belongs to
/// its editor (above it, closed with it, docked by its close button), back
/// where it was when a project opens again (the main screen when that
/// screen is gone), and the editor's keys work whichever panel has focus.
@MainActor
final class VideoFloatingPanelTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private typealias T = VideoEditorTestModel
    private var directory: URL!
    private var controllers: [VideoDemoEditorWindowController] = []
    private var store: VideoEditorPanelStore { .shared }

    override func setUp() async throws {
        _ = NSApplication.shared
        store.reset()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-floating-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        let policy = NSApp.activationPolicy()
        for controller in controllers { controller.window?.close() }
        NSApp.setActivationPolicy(policy)
        controllers = []
        store.reset()
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private func openEditor() async throws -> VideoDemoEditorWindowController {
        let url = directory.appendingPathComponent("rec.mp4")
        if !FileManager.default.fileExists(atPath: url.path) {
            try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 320, height: 200), seconds: 4, fps: 30, audioSeconds: 4)
            VideoDemoDraftStore.delete(for: url)
        }
        let controller = VideoDemoEditorWindowController(videoURL: url)
        controllers.append(controller)
        controller.window?.orderFrontRegardless()
        controller.floatingPanels.start()
        for _ in 0..<60 where !controller.model.isReady { await T.settle(0.05) }
        XCTAssertTrue(controller.model.isReady)
        await T.settle(0.3)
        return controller
    }

    private var mainScreen: (id: UInt32?, frame: CGRect) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        return (screen.displayID, screen.visibleFrame)
    }

    func testAFloatingPanelBelongsToItsEditorAndComesBack() async throws {
        let controller = try await openEditor()
        let editorWindow = try XCTUnwrap(controller.window)
        let main = mainScreen
        let frame = CGRect(x: main.frame.minX + 80, y: main.frame.minY + 80, width: 420, height: 560)
        store.float(.properties, frame: frame, screen: main.id, current: .standard)
        await T.settle(0.3)
        let panel = try XCTUnwrap(controller.floatingPanels.windows[.properties])
        XCTAssertTrue(panel.parent === editorWindow, "above its editor, hidden and closed with it")
        XCTAssertEqual(panel.frame, frame)
        XCTAssertTrue(VideoDemoEditorWindowController.controller(for: panel) === controller)
        XCTAssertTrue(VideoKeyboardBridge.belongs(panel, to: editorWindow))

        // Moved: remembered.
        panel.setFrameOrigin(NSPoint(x: frame.minX + 40, y: frame.minY + 20))
        await T.settle(0.2)
        XCTAssertEqual(store.arrangement.floating.first?.frame.minX, frame.minX + 40)

        // The project closes and opens again: back where it was.
        editorWindow.close()
        XCTAssertTrue(controller.floatingPanels.windows.isEmpty, "closed with its editor")
        XCTAssertFalse(store.arrangement.floating.isEmpty, "the arrangement stays")
        let again = try await openEditor()
        let reopened = try XCTUnwrap(again.floatingPanels.windows[.properties])
        XCTAssertEqual(reopened.frame.origin, NSPoint(x: frame.minX + 40, y: frame.minY + 20))
        XCTAssertFalse(VideoKeyboardBridge.belongs(reopened, to: editorWindow), "not another editor's")

        // Its close button docks it.
        reopened.performClose(nil)
        await T.settle(0.3)
        XCTAssertTrue(again.floatingPanels.windows.isEmpty)
        XCTAssertEqual(store.arrangement, .standard)
    }

    func testOnAScreenThatsGoneItOpensOnTheMainOne() async throws {
        let main = mainScreen
        store.float(.timeline, frame: CGRect(x: 90_000, y: 400, width: 980, height: 300), screen: 987_654, current: .standard)
        let controller = try await openEditor()
        let panel = try XCTUnwrap(controller.floatingPanels.windows[.timeline])
        XCTAssertTrue(main.frame.insetBy(dx: -1, dy: -1).contains(panel.frame), "on the main screen: \(panel.frame)")
    }

    // MARK: Keys

    /// A key pressed with `window` in front, as the editor's key monitor
    /// gets it (test windows can't come to the front here).
    private var editorWindow: NSWindow?
    private var editorModel: VideoEditorModel?

    private func key(_ characters: String, _ code: UInt16, _ modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                     isARepeat: false, keyCode: code)!
        XCTAssertTrue(event.window === window)
        XCTAssertTrue(VideoKeyboardBridge.route(event, editor: editorWindow!, isKey: true, model: editorModel!), "\(characters) used")
    }

    func testEveryEditorKeyWorksWhicheverPanelHasFocus() async throws {
        try await forEachEditorStyle { style in
            let controller = try await openEditor()
            let model = controller.model
            let editorWindow = try XCTUnwrap(controller.window)
            self.editorWindow = editorWindow
            editorModel = model
            // The editor window itself (its docked panels), then each panel
            // floating with its window in front.
            for focus in [nil] + VideoPanelKind.editorPanels.map(Optional.some) {
                let name = "\(style), \(focus.map { "floating \($0)" } ?? "docked")"
                store.reset()
                if let focus {
                    store.float(focus, frame: CGRect(x: mainScreen.frame.minX + 60, y: mainScreen.frame.minY + 60, width: 640, height: 480), screen: mainScreen.id, current: .standard)
                }
                await T.settle(0.3)
                let window: NSWindow = try focus.map { try XCTUnwrap(controller.floatingPanels.windows[$0], name) } ?? editorWindow
                // Menu items (⌘Z in the Edit menu…) act on its editor.
                XCTAssertTrue(VideoDemoEditorWindowController.controller(for: window) === controller, "\(name): its editor")

                // Space plays and pauses.
                key(" ", 49, in: window)
                await T.settle(0.25)
                XCTAssertTrue(model.isPlaying, "\(name): Space plays")
                key(" ", 49, in: window)
                await T.settle(0.25)
                XCTAssertFalse(model.isPlaying, "\(name): Space pauses")
                // B and A: the split tool and back.
                key("b", 11, in: window)
                XCTAssertEqual(model.timelineTool, .split, "\(name): B")
                key("a", 0, in: window)
                XCTAssertEqual(model.timelineTool, .select, "\(name): A")
                // ⌘B splits, ⌘Z puts it back.
                let clips = model.project.timelineClips.count
                model.seek(to: 1.5)
                key("b", 11, .command, in: window)
                XCTAssertEqual(model.project.timelineClips.count, clips + 1, "\(name): ⌘B")
                key("z", 6, .command, in: window)
                XCTAssertEqual(model.project.timelineClips.count, clips, "\(name): ⌘Z")
                // Q cuts what's left of the playhead; ⌘Z again.
                let length = model.timelineDuration
                key("q", 12, in: window)
                XCTAssertLessThan(model.timelineDuration, length - 0.5, "\(name): Q")
                key("z", 6, .command, in: window)
                XCTAssertEqual(model.timelineDuration, length, accuracy: 0.01, "\(name): ⌘Z")
                // V switches the selected clip off and on.
                model.selection = .clip(try XCTUnwrap(model.project.timelineClips.first?.id))
                key("v", 9, in: window)
                XCTAssertEqual(model.project.timelineClips.first?.disabled, true, "\(name): V")
                key("v", 9, in: window)
                XCTAssertEqual(model.project.timelineClips.first?.disabled, false, "\(name): V again")
                // ⌘K: Search; Esc closes it.
                key("k", 40, .command, in: window)
                XCTAssertTrue(model.isCommandPalettePresented, "\(name): ⌘K")
                key("\u{1b}", 53, in: window)
                XCTAssertFalse(model.isCommandPalettePresented, "\(name): Esc")
            }
            editorWindow.close()
            controllers.removeAll { $0 === controller }
            store.reset()
        }
    }
}
