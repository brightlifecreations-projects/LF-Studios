import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// Movable panels (1.18.0): docking on any side of another panel, floating
/// in a window of its own, borders with minimum sizes, Reset Layout and
/// saved layouts, remembered on this Mac.
@MainActor
final class VideoDockTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var store: VideoEditorPanelStore { .shared }
    private typealias T = VideoEditorTestModel

    override func setUp() async throws {
        store.reset()
        for saved in store.savedLayouts { store.deleteLayout(named: saved.name) }
    }

    override func tearDown() async throws {
        store.reset()
        for saved in store.savedLayouts { store.deleteLayout(named: saved.name) }
    }

    private let room = CGRect(x: 0, y: 0, width: 1400, height: 820)

    private func assertNoOverlaps(_ layout: VideoDockLayout, in room: CGRect, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let frames = Array(layout.frames)
        for (i, a) in frames.enumerated() {
            XCTAssertTrue(room.insetBy(dx: -1, dy: -1).contains(a.value), "\(message): \(a.key) inside", file: file, line: line)
            for b in frames.dropFirst(i + 1) {
                XCTAssertFalse(a.value.insetBy(dx: 1, dy: 1).intersects(b.value.insetBy(dx: 1, dy: 1)), "\(message): \(a.key) and \(b.key) overlap", file: file, line: line)
            }
        }
    }

    // MARK: The arrangement

    func testTheStandardLayoutIsDrawnAsBefore() {
        XCTAssertTrue(VideoDockArrangement.standard.isStandard)
        XCTAssertNil(Settings.videoEditorArrangement, "nothing saved until something moves")
        // Shares only (a border dragged in the standard layout): still standard.
        var shares = VideoDockArrangement.standard
        shares.docked = shares.docked.settingShares([0.7, 0.3], at: [])
        store.arrange(shares)
        XCTAssertEqual(store.arrangement, .standard)
        XCTAssertNil(Settings.videoEditorArrangement)
    }

    func testDockingOnEverySideOfEveryPanel() throws {
        for kind in VideoPanelKind.allCases {
            for target in VideoPanelKind.allCases where target != kind {
                for side in VideoDockSide.allCases {
                    let name = "\(kind) \(side) of \(target)"
                    let moved = try XCTUnwrap(VideoDockNode.standard.moving(kind, to: side, of: target), name)
                    XCTAssertEqual(Set(moved.panels), Set(VideoPanelKind.allCases), "\(name): every panel once")
                    XCTAssertEqual(moved.panels.count, 4, name)
                    let layout = VideoDockLayout(moved, in: room)
                    assertNoOverlaps(layout, in: room, name)
                    let a = try XCTUnwrap(layout.frames[kind]), b = try XCTUnwrap(layout.frames[target])
                    switch side {
                    case .left: XCTAssertLessThanOrEqual(a.maxX, b.minX + 1, name)
                    case .right: XCTAssertGreaterThanOrEqual(a.minX, b.maxX - 1, name)
                    case .top: XCTAssertLessThanOrEqual(a.maxY, b.minY + 1, name)
                    case .bottom: XCTAssertGreaterThanOrEqual(a.minY, b.maxY - 1, name)
                    }
                    // Each panel at least its minimum when they fit (when
                    // they don't, each gives way in proportion).
                    let fits = moved.minimumSize.width <= room.width && moved.minimumSize.height <= room.height
                    for (panel, frame) in layout.frames where fits {
                        XCTAssertGreaterThanOrEqual(frame.width + 1, panel.minimumSize.width, "\(name): \(panel) wide enough")
                        XCTAssertGreaterThanOrEqual(frame.height + 1, panel.minimumSize.height, "\(name): \(panel) tall enough")
                    }
                }
            }
        }
        XCTAssertNil(VideoDockNode.standard.moving(.player, to: .left, of: .player), "not next to itself")
    }

    func testMovingAndMovingBackCollapsesTheSplits() throws {
        let moved = try XCTUnwrap(VideoDockNode.standard.moving(.timeline, to: .right, of: .properties))
        // The timeline beside the others: one row of four.
        guard case .split(.horizontal, let row, _) = moved else { return XCTFail("one row: \(moved)") }
        XCTAssertEqual(row.map(\.panels), [[.library], [.player], [.properties], [.timeline]])
        let back = try XCTUnwrap(moved.moving(.timeline, to: .bottom, of: .player))
        XCTAssertEqual(back.panels.count, 4)
        XCTAssertFalse(back.panels.isEmpty)
    }

    func testBordersKeepEachPanelsMinimum() throws {
        let node = VideoDockNode.standard
        let layout = VideoDockLayout(node, in: room)
        let top = try XCTUnwrap(layout.borders.first { $0.path == [0] && $0.index == 0 }, "Library | player")
        // Dragged far left: the Library stops at its minimum.
        let shares = try XCTUnwrap(VideoDockArea.shares(after: top, by: -2000, in: node, layout: layout))
        let resized = node.settingShares(shares, at: [0])
        let after = VideoDockLayout(resized, in: room)
        XCTAssertEqual(try XCTUnwrap(after.frames[.library]).width, VideoPanelKind.library.minimumSize.width, accuracy: 1.5)
        // The timeline's border dragged far down: it keeps its minimum.
        let middle = try XCTUnwrap(layout.borders.first { $0.path == [] })
        let lower = node.settingShares(try XCTUnwrap(VideoDockArea.shares(after: middle, by: 4000, in: node, layout: layout)), at: [])
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(VideoDockLayout(lower, in: room).frames[.timeline]).height + 1, VideoPanelKind.timeline.minimumSize.height)
        // The smallest editor window: nothing overlaps.
        assertNoOverlaps(VideoDockLayout(lower, in: CGRect(x: 0, y: 0, width: 1040, height: 600)), in: CGRect(x: 0, y: 0, width: 1040, height: 600), "smallest")
    }

    func testSharesComeFromWhereThePanelsAreDrawn() {
        let frames: [VideoPanelKind: CGRect] = [
            .library: CGRect(x: 0, y: 0, width: 300, height: 500),
            .player: CGRect(x: 301, y: 0, width: 600, height: 500),
            .properties: CGRect(x: 902, y: 0, width: 318, height: 500),
            .timeline: CGRect(x: 0, y: 501, width: 1220, height: 300),
        ]
        let measured = VideoDockNode.standard.withShares(from: frames)
        let layout = VideoDockLayout(measured, in: CGRect(x: 0, y: 0, width: 1220, height: 801))
        XCTAssertEqual(try XCTUnwrap(layout.frames[.library]).width, 300, accuracy: 2, "nothing jumps when a panel first moves")
        XCTAssertEqual(try XCTUnwrap(layout.frames[.timeline]).height, 300, accuracy: 2)
    }

    // MARK: Floating

    func testFloatingAndDockingBack() throws {
        let frame = CGRect(x: 200, y: 200, width: 640, height: 420)
        store.float(.timeline, frame: frame, screen: 7, current: .standard)
        XCTAssertFalse(store.arrangement.docked.contains(.timeline))
        XCTAssertEqual(store.arrangement.floating, [VideoFloatingPanel(kind: .timeline, frame: frame, screen: 7)])
        XCTAssertFalse(store.arrangement.isStandard)
        XCTAssertEqual(Settings.videoEditorArrangement, store.arrangement, "remembered on this Mac")
        // Moved: remembered there.
        store.moveFloating(.timeline, frame: frame.offsetBy(dx: 50, dy: 0), screen: 7)
        XCTAssertEqual(Settings.videoEditorArrangement?.floating.first?.frame.minX, 250)
        // Dock: back under everything, as it was.
        store.dock(.timeline)
        XCTAssertEqual(store.arrangement, .standard)
        XCTAssertNil(Settings.videoEditorArrangement)

        // Each panel floats and docks back next to where it was.
        for kind in VideoPanelKind.allCases {
            store.float(kind, frame: frame, screen: nil, current: .standard)
            store.dock(kind)
            XCTAssertEqual(store.arrangement, .standard, "\(kind) docks back where it was")
        }

        // Never the last docked panel.
        for kind in [VideoPanelKind.library, .player, .properties] { store.float(kind, frame: frame, screen: nil, current: store.arrangement.docked) }
        XCTAssertEqual(store.arrangement.docked, .panel(.timeline))
        store.float(.timeline, frame: frame, screen: nil, current: store.arrangement.docked)
        XCTAssertEqual(store.arrangement.docked, .panel(.timeline), "one stays in the editor")
        // A floating panel dragged onto the editor docks there.
        store.move(.player, to: .top, of: .timeline, current: store.arrangement.docked)
        XCTAssertTrue(store.arrangement.docked.contains(.player))
        XCTAssertFalse(store.arrangement.floating.contains { $0.kind == .player })
        store.dockAll()
        XCTAssertTrue(store.arrangement.floating.isEmpty)
        XCTAssertEqual(Set(store.arrangement.docked.panels), Set(VideoPanelKind.allCases))
    }

    func testAFloatingPanelReopensOnItsScreenOrTheMainOne() {
        let main = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 2000, y: 300, width: 700, height: 400)
        let screens: [(id: UInt32, frame: CGRect)] = [(1, main), (2, second)]
        XCTAssertEqual(VideoFloatingPanel.restoredFrame(frame, screen: 2, screens: screens, main: main), frame, "the same screen and place")
        let fallback = VideoFloatingPanel.restoredFrame(frame, screen: 2, screens: [(1, main)], main: main)
        XCTAssertTrue(main.contains(fallback), "that screen is gone: on the main one")
        XCTAssertEqual(fallback.size, frame.size)
    }

    /// The one-time tip (1.19.0): until it's closed, or a panel moves.
    func testThePanelTipGoesOnceAPanelMoves() {
        Settings.videoPanelTipSeen = false
        store.arrange(.standard)
        XCTAssertFalse(Settings.videoPanelTipSeen, "nothing moved yet: still to show")
        store.float(.timeline, frame: CGRect(x: 0, y: 0, width: 900, height: 300), screen: nil, current: .standard)
        XCTAssertTrue(Settings.videoPanelTipSeen, "found how to move panels")
    }

    // MARK: Saved layouts and Reset

    func testSavedLayoutsAndReset() throws {
        store.set(VideoEditorPanelLayout(library: 260, properties: 300), remember: true)
        store.move(.properties, to: .left, of: .library, current: .standard)
        store.float(.timeline, frame: CGRect(x: 10, y: 10, width: 700, height: 300), screen: nil, current: store.arrangement.docked)
        let arranged = store.arrangement
        store.saveLayout(named: "  Review  ")
        XCTAssertEqual(store.savedLayouts.map(\.name), ["Review"])
        XCTAssertEqual(store.currentSavedLayout?.name, "Review")

        store.reset()
        XCTAssertEqual(store.arrangement, .standard, "Reset Layout: every panel docked where it starts")
        XCTAssertEqual(store.layout, .standard)
        XCTAssertNil(Settings.videoEditorArrangement)
        XCTAssertNil(store.currentSavedLayout)

        // Kept on this Mac.
        store.reload()
        let saved = try XCTUnwrap(store.savedLayouts.first)
        store.apply(saved)
        XCTAssertEqual(store.arrangement, arranged)
        XCTAssertEqual(store.layout, VideoEditorPanelLayout(library: 260, properties: 300))
        XCTAssertEqual(store.currentSavedLayout?.name, "Review")
        // The same name again: replaced, not added.
        store.saveLayout(named: "Review")
        XCTAssertEqual(store.savedLayouts.count, 1)
        store.deleteLayout(named: "Review")
        XCTAssertTrue(store.savedLayouts.isEmpty)
        XCTAssertTrue(Settings.videoSavedLayouts.isEmpty)
    }

    // MARK: In the editor

    private func host(_ model: VideoEditorModel, dock: VideoDockDrag, size: CGSize = CGSize(width: 1400, height: 880)) async throws -> NSWindow {
        let host = NSHostingView(rootView: VideoEditorRootView(model: model, dock: dock).frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.orderFrontRegardless()
        dock.window = window
        host.layoutSubtreeIfNeeded()
        await T.settle(0.4)
        return window
    }

    /// A point in the editor (top-left origin) on the screens.
    private func screenPoint(_ point: CGPoint, dock: VideoDockDrag, window: NSWindow) throws -> CGPoint {
        let content = try XCTUnwrap(window.contentView)
        let inWindow = CGPoint(x: point.x + dock.room.minX, y: content.bounds.height - (point.y + dock.room.minY))
        return window.convertPoint(toScreen: inWindow)
    }

    /// Nothing moved: each panel exactly where 1.17.0 put it (its widths
    /// and the timeline's height from the same rules), no header drawn.
    func testTheStandardLayoutKeeps117sPlaces() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-dock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try await VideoEditorTestModel.make(in: directory)
        for size in [CGSize(width: 1080, height: 700), CGSize(width: 1400, height: 880), CGSize(width: 1920, height: 1080)] {
            try await forEachEditorStyle { style in
                store.reset()
                let dock = VideoDockDrag()
                let window = try await host(model, dock: dock, size: size)
                defer { window.orderOut(nil) }
                let name = "\(style) \(Int(size.width))×\(Int(size.height))"
                let rail: CGFloat = style.isNew ? VideoEditorNewMetrics.railWidth + 1 : 0
                let widths = store.layout.fitted(windowWidth: size.width - rail)
                XCTAssertEqual(try XCTUnwrap(dock.frames[.library]).width, widths.library, accuracy: 0.5, name)
                XCTAssertEqual(try XCTUnwrap(dock.frames[.player]).width, widths.player, accuracy: 0.5, name)
                XCTAssertEqual(try XCTUnwrap(dock.frames[.properties]).width, widths.properties, accuracy: 0.5, name)
                XCTAssertEqual(try XCTUnwrap(dock.frames[.library]).minX, rail, accuracy: 0.5, name)
                // The editor's own height (under the title bar too).
                let height = dock.room.height
                let timeline = VideoEditorLayout.timelineHeight(windowHeight: height, fraction: VideoEditorLayout.fraction(chosen: nil, windowHeight: height))
                let expected = style.isNew ? max(timeline - VideoEditorNewMetrics.statusHeight - 1, 120) : timeline
                XCTAssertEqual(try XCTUnwrap(dock.frames[.timeline]).height, expected, accuracy: 0.5, name)
                XCTAssertNil(dock.dragging)
            }
        }
    }

    func testDraggingAHeaderDocksAndFloatsInBothLayouts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-dock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try await VideoEditorTestModel.make(in: directory)
        try await forEachEditorStyle { style in
            store.reset()
            let dock = VideoDockDrag()
            let window = try await host(model, dock: dock)
            defer { window.orderOut(nil) }
            // The standard layout: each panel measured where 1.17.0 drew it.
            XCTAssertEqual(Set(dock.frames.keys), Set(VideoPanelKind.allCases), "\(style)")
            let player = try XCTUnwrap(dock.frames[.player])
            let library = try XCTUnwrap(dock.frames[.library])

            // The Library dragged to the right edge of the player.
            let right = try screenPoint(CGPoint(x: player.maxX - 20, y: player.midY), dock: dock, window: window)
            dock.update(.library, screen: right)
            XCTAssertEqual(dock.target, VideoDockDrag.Target(kind: .player, side: .right), "\(style): the drop zone")
            XCTAssertFalse(dock.outside)
            dock.end(.library, screen: right)
            XCTAssertNil(dock.dragging)
            XCTAssertFalse(store.arrangement.isStandard)
            await T.settle(0.4)
            let moved = try XCTUnwrap(dock.frames[.library])
            let playerNow = try XCTUnwrap(dock.frames[.player])
            XCTAssertGreaterThanOrEqual(moved.minX, playerNow.maxX - 1, "\(style): the Library is right of the player")
            XCTAssertGreaterThanOrEqual(playerNow.width + 1, VideoPanelKind.player.minimumSize.width, "\(style): the player keeps its minimum")
            XCTAssertGreaterThanOrEqual(moved.width + 1, VideoPanelKind.library.minimumSize.width, "\(style): so does the Library")
            _ = library

            // The timeline dragged out of the window: it floats there.
            let outside = CGPoint(x: window.frame.maxX + 300, y: window.frame.midY)
            dock.update(.timeline, screen: outside)
            XCTAssertTrue(dock.outside, "\(style)")
            XCTAssertNil(dock.target)
            dock.end(.timeline, screen: outside)
            let floating = try XCTUnwrap(store.arrangement.floating.first)
            XCTAssertEqual(floating.kind, .timeline)
            XCTAssertTrue(floating.frame.contains(outside) || floating.frame.insetBy(dx: -80, dy: -40).contains(outside), "\(style): where it was let go")
            XCTAssertGreaterThanOrEqual(floating.frame.width, VideoPanelKind.timeline.minimumSize.width)

            // Dropped back inside on nothing (the toolbar): nothing changes.
            let before = store.arrangement
            let toolbar = try screenPoint(CGPoint(x: 600, y: 10), dock: dock, window: window)
            dock.end(.player, screen: toolbar)
            XCTAssertEqual(store.arrangement, before)

            store.reset()
            await T.settle(0.3)
            XCTAssertEqual(Set(dock.frames.keys), Set(VideoPanelKind.allCases), "\(style): Reset Layout docks everything")
        }
    }
}
