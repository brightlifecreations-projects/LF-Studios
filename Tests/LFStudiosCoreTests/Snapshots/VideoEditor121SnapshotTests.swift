import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// 1.21.0: the one-row recording bar (closed, and with the Area popover
/// open), the timeline scrolled down, a box selection, the audio meters and
/// the safe zones, in both layouts and looks (printed as SNAPSHOT-121:
/// <path>, in lfstudios-editor-121/).
@MainActor
final class VideoEditor121SnapshotTests: XCTestCase {
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
        suiteName = "LFStudiosCoreTests.Editor121.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        Settings.videoShortcutsChangeSeen = true
        Settings.videoPanelTipSeen = true
        VideoEditorPanelStore.shared.reload()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-121-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        VideoEditorPanelStore.shared.reload()
        try? FileManager.default.removeItem(at: directory)
    }

    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-121", isDirectory: true)
    private let looks: [(String, NSAppearance.Name)] = [("dark", .darkAqua), ("light", .aqua)]

    /// A demo with captions, keys, sound and three pictures above the main
    /// track (Camera, Keys, Music… make the timeline taller than its panel).
    private func demo(size: CGSize = CGSize(width: 1440, height: 900)) async throws -> VideoEditorModel {
        var options = VideoEditorTestModel.Options()
        options.seconds = 12
        options.size = size
        options.audio = true
        options.keystrokes = [VideoKeystrokeEvent(time: 1.5, keys: ["⌘", "S"]), VideoKeystrokeEvent(time: 6, keys: ["⌘", "K"])]
        let model = try await VideoEditorTestModel.make(in: directory, name: "Product demo.mp4", options)
        model.mutate { project in
            project.captions = [
                VideoCaptionLine(start: 0.4, end: 2.2, text: "Open the settings"),
                VideoCaptionLine(start: 2.6, end: 4.6, text: "and pick a theme"),
                VideoCaptionLine(start: 5, end: 7.5, text: "Your changes save as you go"),
            ]
        }
        for (index, span) in [(1.0, 2.0), (3.0, 1.5), (6.5, 2.0)].enumerated() {
            let url = directory.appendingPathComponent("Shot \(index + 1).png")
            try VideoInspection.writePNG(to: url, size: CGSize(width: 320, height: 180), color: [NSColor.systemTeal, .systemOrange, .systemPurple][index])
            let place: VideoEditorModel.LayerPlace = index == 0 ? .automatic : .track(0)
            if let id = await model.addLayerItem(from: url, at: span.0, place: place) {
                model.setLayerItem(id) { $0.length = span.1 }
            }
        }
        model.seek(to: 4)
        model.perform(.split)
        model.endGesture()
        model.selection = .none
        return model
    }

    @discardableResult
    private func render<Content: View>(_ content: Content, size: CGSize, look: NSAppearance.Name, name: String, prepare: (() async throws -> Void)? = nil) async throws -> URL {
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
        try await Task.sleep(nanoseconds: 700_000_000)
        try await prepare?()
        try await Task.sleep(nanoseconds: 400_000_000)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try write(rep, name: name, window: window)
    }

    private func write(_ rep: NSBitmapImageRep, name: String, window: NSWindow? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let url = Self.folder.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT-121: \(url.path)")
        window?.orderOut(nil)
        return url
    }

    /// The editor with a box selection being dragged, the meters moving,
    /// and the safe zones and grid over the player.
    func testTheEditorIn121() async throws {
        let model = try await demo()
        model.playerGuides = [.titleSafe, .actionSafe, .thirds]
        model.showsMeters = true
        model.meters.show(left: 0.78, right: 0.72, leftPeak: 0.86, rightPeak: 0.83)
        model.loopsPlayback = true
        // Two pictures and the second half of the main track, selected by a box.
        let layer = VideoTimelineTrack.layer(model.project.layerTracks[0].id)
        model.boxSelect(model.clips(from: 2.6, to: 7, on: [layer, .clips]), mode: .replace)
        XCTAssertEqual(model.selectedItems.count, 5, "three pictures and two clips")
        try await forEachEditorStyle { style in
            let tag = style == .lfStudios ? "new" : "capcut"
            for (lookName, look) in looks {
                try await render(VideoEditorRootView(model: model), size: CGSize(width: 1680, height: 1050), look: look, name: "editor-\(tag)-\(lookName)") {
                    // The box as it's dragged (lanes' own coordinates).
                    let tracks = VideoTimelineRowLayout(project: model.project, hasCamera: model.hasWebcamFootage, curves: [], sound: model.timelineSoundRows)
                    let top = tracks.row(.layer(model.project.layerTracks[0].id))?.top ?? 40
                    let clips = tracks.row(.clips).map { $0.top + $0.height } ?? 160
                    let perSecond = max(model.timelineViewportWidth, 100) / CGFloat(max(model.timelineDuration, 1))
                    VideoTimelineBox.latest?.rect = CGRect(x: VideoTimelineMetrics.inset + 2.6 * perSecond, y: top + 4, width: 4.4 * perSecond, height: clips - top - 8)
                }
                VideoTimelineBox.latest?.rect = nil
            }
        }
    }

    /// The timeline at its smallest height, scrolled down to the last
    /// tracks: the ruler stays, the names move with their tracks, and the
    /// scroll bar shows.
    func testTheTimelineScrolledDown() async throws {
        let model = try await demo()
        try await forEachEditorStyle { style in
            let tag = style == .lfStudios ? "new" : "capcut"
            for (lookName, look) in looks {
                try await render(VideoTimelineView(model: model).background(VideoEditorTheme.panel), size: CGSize(width: 1300, height: 190), look: look, name: "timeline-scrolled-\(tag)-\(lookName)") {
                    VideoTimelineScroller.latest?.scroll(toY: 10_000)
                }
            }
        }
    }

    /// A 9:16 video with TikTok's areas and the title-safe box.
    func testSocialGuidesOnAVerticalVideo() async throws {
        var options = VideoEditorTestModel.Options()
        options.seconds = 6
        options.size = CGSize(width: 540, height: 960)
        let model = try await VideoEditorTestModel.make(in: directory, name: "Vertical.mp4", options)
        XCTAssertTrue(model.isVertical)
        model.playerGuides = [.tiktok, .titleSafe]
        for (lookName, look) in looks {
            try await render(VideoStageView(model: model).background(VideoEditorTheme.window), size: CGSize(width: 420, height: 760), look: look, name: "vertical-guides-\(lookName)")
        }
    }

    /// The recording bar: one row, and with the Area popover open above it.
    /// It's always dark (it floats over any screen).
    func testTheRecordingBar() async throws {
        Settings.recordingMicrophone = true
        Settings.recordingCamera = true
        let screen = try XCTUnwrap(NSScreen.main)
        let rect = CGRect(x: screen.frame.midX - 480, y: screen.frame.midY - 270, width: 960, height: 540)
        let bar = RecordingControlsWindow(rect: rect, screen: screen, target: .area, selectedWindow: nil, startHandler: { _, _, _ in }, closeHandler: {})
        defer { bar.closeControls() }
        bar.frameStripModel = RecordingFrameStripModel(ratio: .standard, pixels: .init(width: 1920, height: 1080), sizeChoices: RecordingFrameGeometry.sizeChoices(.standard, in: .init(width: 3840, height: 2160)))
        bar.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - bar.frame.width / 2, y: screen.visibleFrame.minY + 60))
        bar.orderFrontRegardless()
        try await Task.sleep(nanoseconds: 300_000_000)
        let barView = try XCTUnwrap(bar.contentView)
        let barRep = try XCTUnwrap(barView.bitmapImageRepForCachingDisplay(in: barView.bounds))
        barView.cacheDisplay(in: barView.bounds, to: barRep)
        try write(barRep, name: "recording-bar")

        bar.showAreaPopover()
        try await Task.sleep(nanoseconds: 700_000_000)
        let content = try XCTUnwrap(bar.areaPopover.contentViewController?.view)
        content.layoutSubtreeIfNeeded()
        let popRep = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: popRep)
        // The popover over the bar, as it shows.
        let width = max(barView.bounds.width, content.bounds.width) + 40
        let height = barView.bounds.height + content.bounds.height + 60
        let scale: CGFloat = 2
        let canvas = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        canvas.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.52, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        barRep.draw(in: NSRect(x: (width - barView.bounds.width) / 2, y: 20, width: barView.bounds.width, height: barView.bounds.height))
        let popRect = NSRect(x: 40 + 8, y: 20 + barView.bounds.height + 12, width: content.bounds.width, height: content.bounds.height)
        NSBezierPath(roundedRect: popRect.insetBy(dx: -1, dy: -1), xRadius: 10, yRadius: 10).addClip()
        popRep.draw(in: popRect)
        NSGraphicsContext.restoreGraphicsState()
        try write(canvas, name: "recording-bar-area")
        XCTAssertEqual(bar.areaPopoverSections, ["frame", "microphone", "camera"])
    }
}
