import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// Long timelines: zoom far enough in on any length, keep the playhead (or
/// the pointer) in place while zooming, page along while playing, and keep
/// restore markers from piling up.
@MainActor
final class VideoLongTimelineTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!
    private var window: NSWindow?

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-longline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        if let directory {
            VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private typealias T = VideoEditorTestModel

    private final class Host: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    /// 10 s in a timeline whose lanes are 1000 pt wide (x = 18 + 100·t at 1×).
    /// The lanes 1036 pt wide, past the track headers (1.11.0).
    private static var size: CGSize { CGSize(width: 1036 + VideoTimelineMetrics.headerWidth + 1, height: 300) }

    private func mount(_ model: VideoEditorModel) async {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = Host(rootView: AnyView(VideoTimelineView(model: model).frame(width: Self.size.width, height: Self.size.height)))
        window.orderFrontRegardless()
        self.window = window
        await T.settle(0.3)
    }

    private func horizontalScrollView() throws -> NSScrollView {
        func all(_ view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { all($0) }
        }
        let views = all(try XCTUnwrap(window?.contentView))
        return try XCTUnwrap(views.first { ($0.documentView?.frame.width ?? 0) > $0.contentSize.width + 50 } ?? views.last)
    }

    func testZoomReachesFrameLevelOnLongTakes() async throws {
        let model = try await T.make(in: directory, T.Options(seconds: 10, pointer: false))
        model.timelineViewportWidth = 1000
        XCTAssertEqual(model.maxTimelineZoom, 40, "short takes keep the usual range")
        // What a 30-minute take would get: 150 points a second at the most.
        let perSecond = { (duration: Double) in max(40, duration * 150 / 1000) * 1000 / duration }
        XCTAssertEqual(perSecond(1800), 150, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(perSecond(10), 150)
        model.zoomTimeline(by: 1000)
        XCTAssertEqual(model.timelineZoom, model.maxTimelineZoom)
        model.zoomTimeline(by: 0.0001)
        XCTAssertEqual(model.timelineZoom, 1)
    }

    func testZoomKeepsThePlayheadAndThePointerInPlace() async throws {
        // Both layouts (1.17.0).
        try await forEachEditorStyle { _ in
            let model = try await T.make(in: directory, T.Options(seconds: 10, pointer: false))
            model.seek(to: 7)
            await mount(model)
            let scroll = try horizontalScrollView()
            XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.5)
            // The playhead is 718 pt in; after 4× it stays there on screen.
            model.zoomTimeline(by: 4)
            await T.settle(0.3)
            let playheadX = 18 + 7 * 400.0
            XCTAssertEqual(scroll.contentView.bounds.minX, playheadX - 718, accuracy: 2, "the playhead stays under your eyes")

            // ⌘-scroll or a pinch anchors on the pointer instead: 3 s sits 200
            // pt into the view and stays there.
            model.pendingZoomAnchor = (3, 200)
            model.zoomTimeline(by: 2)
            await T.settle(0.3)
            XCTAssertEqual(scroll.contentView.bounds.minX, 18 + 3 * 800 - 200, accuracy: 2, "the moment under the pointer stays put")
    
        }
    }

    /// 1.21.0: with the pointer over the timeline (the skimmer), zooming
    /// keeps the skimmer's moment where it is on screen. Away from the
    /// timeline, or with the preview axis off, the playhead; a playhead out
    /// of view is brought into the middle.
    func testZoomKeepsTheSkimmerMomentFixed() async throws {
        let previewAxis = Settings.videoTimelinePreviewAxis
        defer { Settings.videoTimelinePreviewAxis = previewAxis }
        try await forEachEditorStyle { _ in
            Settings.videoTimelinePreviewAxis = true
            let model = try await T.make(in: directory, T.Options(seconds: 10, pointer: false))
            model.seek(to: 7)
            await mount(model)
            let scroll = try horizontalScrollView()
            model.zoomTimeline(by: 4)
            await T.settle(0.3)
            // The skimmer at 6.2 s, wherever it is on screen now.
            model.timelinePointerTime = 6.2
            let before = 18 + 6.2 * 400 - scroll.contentView.bounds.minX
            for factor in [2.0, 1.5, 1 / 3.0] {
                model.zoomTimeline(by: factor)
                await T.settle(0.3)
                let perSecond = 1000 * model.timelineZoom / 10
                let after = 18 + 6.2 * perSecond - scroll.contentView.bounds.minX
                XCTAssertEqual(after, before, accuracy: 2, "×\(factor): the skimmer's moment stays under it")
            }

            // The pointer leaves: the playhead stays put instead.
            model.timelinePointerTime = nil
            let playheadBefore = 18 + 7 * 1000 * model.timelineZoom / 10 - scroll.contentView.bounds.minX
            model.zoomTimeline(by: 2)
            await T.settle(0.3)
            let playheadAfter = 18 + 7 * 1000 * model.timelineZoom / 10 - scroll.contentView.bounds.minX
            XCTAssertEqual(playheadAfter, playheadBefore, accuracy: 2, "the playhead stays put")

            // The preview axis off: the pointer over the timeline doesn't count.
            Settings.videoTimelinePreviewAxis = false
            model.timelinePointerTime = 2
            let offBefore = 18 + 7 * 1000 * model.timelineZoom / 10 - scroll.contentView.bounds.minX
            model.zoomTimeline(by: 1.4)
            await T.settle(0.3)
            let offAfter = 18 + 7 * 1000 * model.timelineZoom / 10 - scroll.contentView.bounds.minX
            XCTAssertEqual(offAfter, offBefore, accuracy: 2, "preview axis off: the playhead")
            model.timelinePointerTime = nil

            // The playhead out of view: zooming brings it into the middle.
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            XCTAssertGreaterThan(18 + 7 * 1000 * model.timelineZoom / 10, scroll.contentView.bounds.maxX, "off to the right")
            model.zoomTimeline(by: 1.2)
            await T.settle(0.3)
            let shown = 18 + 7 * 1000 * model.timelineZoom / 10 - scroll.contentView.bounds.minX
            XCTAssertEqual(shown, scroll.contentView.bounds.width / 2, accuracy: 2, "in the middle of the timeline")
        }
    }

    /// 1.21.0: at the timeline panel's smallest height (150 pt, docked or
    /// floating: the same view), every track can be reached by scrolling.
    /// The ruler stays put, the headers move with their lanes, scrolling
    /// over the headers works too, and a scroll bar shows.
    func testVerticalScrollReachesTheLastTrackAtTheSmallestHeight() async throws {
        try await forEachEditorStyle { style in
            var options = T.Options(seconds: 10, audio: true, pointer: true)
            options.keystrokes = [VideoKeystrokeEvent(time: 1, keys: ["⌘", "S"]), VideoKeystrokeEvent(time: 4, keys: ["⌘", "C"])]
            let model = try await T.make(in: directory, options)
            model.mutate { $0.captions = [VideoCaptionLine(start: 1, end: 3, text: "Hello")] }
            let picture = directory.appendingPathComponent("p.png")
            try VideoInspection.writePNG(to: picture, size: CGSize(width: 160, height: 90), color: .green)
            _ = await model.addLayerItem(from: picture, at: 2)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.size.width, height: 150), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = Host(rootView: AnyView(VideoTimelineView(model: model).frame(width: Self.size.width, height: 150)))
            window.setFrameOrigin(NSPoint(x: 40, y: 200))
            window.orderFrontRegardless()
            self.window = window
            await T.settle(0.4)

            func all(_ view: NSView) -> [NSScrollView] {
                ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { all($0) }
            }
            let root = try XCTUnwrap(window.contentView)
            let outer = try XCTUnwrap(all(root).first { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 20 }, "\(style): the tracks are taller than the panel")
            let document = try XCTUnwrap(outer.documentView)
            let tracks = VideoTimelineRowLayout(project: model.project, hasCamera: model.hasWebcamFootage, curves: [], sound: model.timelineSoundRows)
            XCTAssertGreaterThanOrEqual(tracks.rows.count, 6, "\(style): \(tracks.rows.map(\.track.key))")
            XCTAssertGreaterThanOrEqual(document.frame.height + 0.5, tracks.height, "\(style): every track is in the scrolling area")

            // A scroll bar shows (the system's only shows while scrolling).
            XCTAssertGreaterThan(VideoTimelineVerticalScrollbar.shown, 0, "\(style): the tracks' scroll bar shows")

            // Scrolling over the track headers moves the lanes down.
            let header = NSPoint(x: VideoTimelineMetrics.headerWidth / 2, y: 30)
            let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -400, wheel2: 0, wheel3: 0))
            let event = try XCTUnwrap(NSEvent(cgEvent: wheel))
            let scroller = try XCTUnwrap(VideoTimelineScroller.latest)
            XCTAssertTrue(scroller.handleScroll(event, in: window, at: header), "\(style): a scroll over the headers is used")
            XCTAssertFalse(scroller.handleScroll(event, in: window, at: NSPoint(x: VideoTimelineMetrics.headerWidth + 200, y: 30)), "\(style): over the lanes they scroll themselves")
            await T.settle(0.3)
            let visible = outer.contentView.bounds
            let fromTop = document.isFlipped ? visible.minY : document.frame.height - visible.maxY
            XCTAssertGreaterThan(fromTop, 20, "\(style): the wheel over the headers scrolled")
            // To the bottom: the last track is on screen.
            let last = try XCTUnwrap(tracks.rows.last)
            outer.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? document.frame.height : 0))
            outer.reflectScrolledClipView(outer.contentView)
            await T.settle(0.3)
            let bottom = outer.contentView.bounds
            let bottomFromTop = document.isFlipped ? bottom.minY : document.frame.height - bottom.maxY
            XCTAssertLessThanOrEqual(last.top + last.height, bottomFromTop + bottom.height + 1, "\(style): the last track (\(last.track.key)) can be reached")
            window.orderOut(nil)
            self.window = nil
        }
    }

    func testPlaybackPagesAlongUntilYouScroll() async throws {
        // Both layouts (1.17.0).
        try await forEachEditorStyle { _ in
            let model = try await T.make(in: directory, T.Options(seconds: 10, pointer: false))
            await mount(model)
            model.zoomTimeline(by: 4)
            await T.settle(0.3)
            let scroll = try horizontalScrollView()
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            model.seek(to: 2.2)
            await T.settle(0.2)
            // The visible strip ends at 2.5 s; playing past it turns the page.
            model.togglePlay()
            for _ in 0..<30 where scroll.contentView.bounds.minX < 1 {
                await T.settle(0.1)
            }
            XCTAssertGreaterThan(scroll.contentView.bounds.minX, 500, "the timeline followed the playhead")

            // Scrolling by hand stops the following.
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            scroll.contentView.scroll(to: NSPoint(x: 100, y: scroll.contentView.bounds.minY))
            scroll.reflectScrolledClipView(scroll.contentView)
            await T.settle(1.2)
            XCTAssertEqual(scroll.contentView.bounds.minX, 100, accuracy: 1, "left where you put it")
            model.pause()
    
        }
    }

    func testRestoreMarkersGroupWhenTheyCrowd() async throws {
        let model = try await T.make(in: directory, T.Options(seconds: 10, pointer: false))
        // Five little cuts close together, one far away.
        let ranges: [ClosedRange<Double>] = [2.0...2.2, 2.4...2.6, 2.8...3.0, 3.2...3.4, 3.6...3.8, 8.0...8.5]
        model.mutate { _ = $0.removeSourceRanges(ranges, totalDuration: 10) }
        model.endGesture()
        let gaps = model.cutGaps
        XCTAssertEqual(gaps.count, 6)
        // At 100 pt a second, markers within 46 pt share one.
        let groups = VideoEditorModel.CutGap.grouped(gaps, within: 0.46)
        XCTAssertEqual(groups.map(\.count), [5, 1])
        // Zoomed in far enough, each has its own again.
        XCTAssertEqual(VideoEditorModel.CutGap.grouped(gaps, within: 0.05).count, 6)

        let before = model.timelineDuration
        model.restore(groups[0])
        XCTAssertEqual(model.timelineDuration, before + 1.0, accuracy: 0.02, "Restore All brings the five back")
        XCTAssertEqual(model.cutGaps.count, 1)
        model.undo()
        XCTAssertEqual(model.cutGaps.count, 6, "in one undo step")
    }
}
