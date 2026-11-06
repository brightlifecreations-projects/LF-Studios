import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// The 1.23.0 audit (AUDIT-1.23.md): every editing action on every kind of
/// selection makes exactly one ⌘Z step (none when nothing changes), and ⌘Z
/// and ⇧⌘Z give back exactly the project before and after; a drag is one
/// step even when the hand rests mid-drag; a 10-minute project stays quick.
/// Windows are offscreen. Runs alone (scripts/test-groups.sh, UI).
@MainActor
final class Audit123Tests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!
    private var window: NSWindow?

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        if let directory {
            for name in ["rec.mp4", "long.mp4"] { VideoDemoDraftStore.delete(for: directory.appendingPathComponent(name)) }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// 10 s with sound, cut at 3 s and 6 s, a picture on a track above,
    /// two captions, a zoom and a text overlay.
    private func richModel() async throws -> VideoEditorModel {
        var options = VideoEditorTestModel.Options()
        options.seconds = 10
        options.audio = true
        let model = try await VideoEditorTestModel.make(in: directory, options)
        model.mutate {
            $0.captions = [VideoCaptionLine(start: 0.5, end: 2, text: "Hello there"), VideoCaptionLine(start: 4, end: 5.5, text: "Second line")]
            $0.zoomRegions = [VideoZoomRegion(start: 7, end: 8.5, scale: 2, followsCursor: false)]
        }
        let picture = directory.appendingPathComponent("Shot.png")
        try VideoInspection.writePNG(to: picture, size: CGSize(width: 320, height: 180), color: .systemOrange)
        if let id = await model.addLayerItem(from: picture, at: 1) { model.setLayerItem(id) { $0.length = 2 } }
        for time in [3.0, 6.0] {
            model.selection = .none
            model.seek(to: time)
            model.perform(.split)
            model.endGesture()
        }
        model.selection = .none
        model.perform(.addText)
        model.endGesture()
        return model
    }

    /// Commands that change settings, open windows, record, or finish later
    /// (freeze frame, reverse) are checked elsewhere.
    private static let skipped: Set<String> = [
        "recordVoiceover", "toggleMagnet", "toggleSnapping", "toggleLinkage", "togglePreviewAxis",
        "showProjectSettings", "toggleLoopPlayback", "revealInLibrary", "matchFrame", "freezeFrame",
        "reverse", "undo", "redo", "crop",
    ]

    private static func name(_ command: VideoEditCommand) -> String {
        String(describing: command).components(separatedBy: "(").first ?? "?"
    }

    func testEveryCommandIsOneUndoStepAndUndoesExactly() async throws {
        let model = try await richModel()
        let base = model.project
        let project = base
        var selections: [(String, VideoEditorModel.Selection)] = [("nothing", .none)]
        if let clip = project.timelineClips.dropFirst().first { selections.append(("main clip", .clip(clip.id))) }
        if let layer = project.layerTracks.first?.items.first { selections.append(("picture", .layer(layer.id))) }
        if let caption = project.captions.first { selections.append(("caption", .caption(caption.id))) }
        if let zoom = project.zoomRegions.first { selections.append(("zoom", .zoom(zoom.id))) }
        if let overlay = project.overlayEffects.first { selections.append(("text overlay", .overlay(overlay.id))) }
        selections.append(("range", .range(VideoDemoTimelineRange(start: 2, end: 5))))

        var problems: [String] = []
        var checked = 0
        for command in VideoEditCommand.allCases where !Self.skipped.contains(Self.name(command)) {
            for (label, selection) in selections {
                model.project = base
                model.undoStack.removeAll()
                model.redoStack.removeAll()
                model.canUndo = false
                model.canRedo = false
                model.endGesture()
                model.seek(to: 4.5)
                model.selection = selection
                let before = model.project
                model.perform(command)
                model.endGesture()
                try? await Task.sleep(nanoseconds: 20_000_000)
                let after = model.project
                let steps = model.undoStack.count
                let what = "\(Self.name(command)) with \(label) selected"
                checked += 1
                if after == before {
                    if steps != 0 { problems.append("\(what): \(steps) empty ⌘Z step(s)") }
                    continue
                }
                if steps != 1 { problems.append("\(what): \(steps) ⌘Z steps for one action"); continue }
                model.undo()
                if model.project != before { problems.append("\(what): ⌘Z doesn't give back the project as it was") }
                model.redo()
                if model.project != after { problems.append("\(what): ⇧⌘Z doesn't give back the edit") }
            }
        }
        print("AUDIT checked \(checked) command × selection pairs")
        for problem in problems { print("AUDIT-PROBLEM \(problem)") }
        XCTAssertEqual(problems, [], "\(problems.count) problems")
    }

    // MARK: Save and reopen

    /// Every edit survives ⌘S and reopening, linked and with the media in.
    func testARichProjectSavesAndReopensUnchanged() async throws {
        let model = try await richModel()
        let edited = model.project
        for (mode, ext) in [(VideoProjectDocument.MediaMode.linked, "lfs"), (.included, "lfs")] {
            let package = directory.appendingPathComponent("Saved-\(mode).\(ext)", isDirectory: true)
            try VideoProjectPackage.save(model.projectContents, to: package, mode: mode)
            let opened = try VideoProjectPackage.open(package).contents.project
            XCTAssertEqual(opened.timelineClips, edited.timelineClips, "\(mode): cuts")
            XCTAssertEqual(opened.captions, edited.captions, "\(mode): captions")
            XCTAssertEqual(opened.zoomRegions, edited.zoomRegions, "\(mode): zooms")
            XCTAssertEqual(opened.overlayEffects, edited.overlayEffects, "\(mode): text")
            XCTAssertEqual(opened.layerTracks.flatMap(\.items).count, edited.layerTracks.flatMap(\.items).count, "\(mode): the picture")
            if mode == .linked { XCTAssertEqual(opened, edited, "linked: the whole project") }
        }
    }

    // MARK: Drags

    private final class Host: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private static var lanesX: CGFloat { VideoTimelineMetrics.headerWidth + 1 }
    private static var size: CGSize { CGSize(width: 1036 + lanesX, height: 360) }

    private func mount(_ model: VideoEditorModel) async {
        VideoTimelineMetrics.rowScale = VideoTimelineTrackHeight.small.scale
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = Host(rootView: AnyView(VideoTimelineView(model: model).frame(width: Self.size.width, height: Self.size.height)))
        self.window = window
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    /// A person often stops mid-drag to look before letting go: still one
    /// ⌘Z step (it was two when the hand rested over 1.5 s). Two presses
    /// stay two steps. The press is what AppKit numbers each mouse-down by.
    func testADragWithARestIsOneUndoStep() async throws {
        let model = try await VideoEditorTestModel.make(in: directory, VideoEditorTestModel.Options(seconds: 10, pointer: false))
        model.mutate { $0.zoomRegions = [VideoZoomRegion(start: 2, end: 4, scale: 2, followsCursor: false)] }
        model.undoStack.removeAll()
        model.endGesture()
        let mouse = VideoEditorModel.mouseStroke
        defer { VideoEditorModel.mouseStroke = mouse }
        let id = try XCTUnwrap(model.project.zoomRegions.first?.id)
        func move(to start: Double) { model.setZoomWindow(id, start: start, end: start + 2, coalesce: "zoom-move-\(id)") }

        // One press: moves, a 2 s rest, more moves, let go.
        VideoEditorModel.mouseStroke = { 41 }
        move(to: 2.5)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        move(to: 3.5)
        XCTAssertEqual(model.undoStack.count, 1, "one drag with a rest is one ⌘Z step")
        XCTAssertEqual(model.project.zoomRegions.first?.start ?? -1, 3.5, accuracy: 0.001)

        // A second press 2 s later on the same block, never ended: its own step.
        try await Task.sleep(nanoseconds: 2_000_000_000)
        VideoEditorModel.mouseStroke = { 42 }
        move(to: 5)
        XCTAssertEqual(model.undoStack.count, 2, "the next drag is a step of its own")
        model.undo()
        XCTAssertEqual(model.project.zoomRegions.first?.start ?? -1, 3.5, accuracy: 0.001)
        model.undo()
        XCTAssertEqual(model.project.zoomRegions.first?.start ?? -1, 2, accuracy: 0.001, "⌘Z puts it back where the drag began")
    }

    // MARK: A 10-minute project

    func testATenMinuteProjectStaysQuick() async throws {
        let url = directory.appendingPathComponent("long.mp4")
        // 1080p, one still colour per minute, 2 frames a second: small on disk.
        let colors: [NSColor] = [.darkGray, .systemBlue, .systemTeal, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemRed, .systemYellow, .gray]
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 1920, height: 1080), colors: colors.map { ($0, 60.0) }, fps: 2)
        VideoDemoDraftStore.delete(for: url)
        var start = Date()
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let open = Date().timeIntervalSince(start)
        XCTAssertTrue(model.isReady, model.loadError ?? "not ready")
        XCTAssertEqual(model.timelineDuration, 600, accuracy: 1)

        // 60 cuts, a caption every 10 s, 20 zooms.
        start = Date()
        for i in 1..<60 {
            model.selection = .none
            model.seek(to: Double(i) * 10)
            model.perform(.split)
            model.endGesture()
        }
        let split = Date().timeIntervalSince(start) / 59
        model.mutate {
            $0.captions = (0..<60).map { VideoCaptionLine(start: Double($0) * 10 + 1, end: Double($0) * 10 + 4, text: "Line \($0)") }
            $0.zoomRegions = (0..<20).map { VideoZoomRegion(start: Double($0) * 30 + 5, end: Double($0) * 30 + 8, scale: 2, followsCursor: false) }
        }
        model.endGesture()
        XCTAssertEqual(model.project.timelineClips.count, 60)

        start = Date()
        for _ in 0..<20 { model.undo() }
        for _ in 0..<20 { model.redo() }
        let undo = Date().timeIntervalSince(start) / 40

        await mount(model)
        let host = try XCTUnwrap(window?.contentView)
        var frames: [Double] = []
        for step in 0..<30 {
            let t0 = Date()
            model.zoomTimeline(by: step < 15 ? 1.25 : 0.8)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            frames.append(Date().timeIntervalSince(t0))
        }
        var drag: [Double] = []
        for step in 0..<30 {
            let t0 = Date()
            model.mutate(coalesce: "audit-zoom") { $0.zoomRegions[0].start = 5 + Double(step) * 0.05; $0.zoomRegions[0].end = 8 + Double(step) * 0.05 }
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            drag.append(Date().timeIntervalSince(t0))
        }
        model.endGesture()
        let worst = { (values: [Double]) in (values.max() ?? 0) * 1000 }
        print(String(format: "AUDIT-PERF 10-minute: open %.0f ms, split %.1f ms, undo/redo %.1f ms, zoom frame worst %.1f ms, drag frame worst %.1f ms",
                     open * 1000, split * 1000, undo * 1000, worst(frames), worst(drag)))
        XCTAssertLessThan(open, 5, "opens in under 5 s")
        XCTAssertLessThan(split, 0.1, "a cut takes under 100 ms")
        XCTAssertLessThan(undo, 0.1)
    }
}
