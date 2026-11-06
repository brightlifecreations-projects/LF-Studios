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
                // Extract Audio works in the background: wait for it to land
                // (one ⌘Z step), so it isn't counted with the next selection.
                if Self.name(command) == "extractAudio" {
                    for _ in 0..<500 where model.undoStack.isEmpty || model.isExtractingAudio {
                        try? await Task.sleep(nanoseconds: 20_000_000)
                    }
                }
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
        let median = { (values: [Double]) in values.sorted()[values.count / 2] * 1000 }
        print(String(format: "AUDIT-PERF 10-minute: open %.0f ms, split %.1f ms, undo/redo %.1f ms, zoom frame median %.1f worst %.1f ms, drag frame median %.1f worst %.1f ms",
                     open * 1000, split * 1000, undo * 1000, median(frames), worst(frames), median(drag), worst(drag)))
        XCTAssertLessThan(open, 5, "opens in under 5 s")
        XCTAssertLessThan(split, 0.1, "a cut takes under 100 ms")
        XCTAssertLessThan(undo, 0.1)
    }

    /// AUDIT A2: Home reads recording folders off the main thread, so a slow
    /// network or iCloud folder doesn't freeze the window each time it's clicked.
    func testHomeReadsFoldersOffTheMainThread() async throws {
        let storage = directory.appendingPathComponent("history", isDirectory: true)
        let model = HomeModel(historyManager: HistoryManager(storageDir: storage), actions: HomeActions(newRecording: {}, takeScreenshot: {}, scrollCapture: {}, openVideo: {}))
        let scanned = expectation(description: "scanned")
        nonisolated(unsafe) var onMain = true
        HomeModel.diskScanWillStart = {
            onMain = Thread.isMainThread
            Thread.sleep(forTimeInterval: 0.5) // a slow folder
            scanned.fulfill()
        }
        let start = Date()
        model.reload()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1, "reload returns before the folders are read")
        await fulfillment(of: [scanned], timeout: 5)
        HomeModel.diskScanWillStart = nil
        XCTAssertFalse(onMain)
    }

    /// Captions (audit C1–C3): Start at the playhead moves a line past its
    /// own end; clearing a line on the way to new words keeps the voice's
    /// word timings; a locked Captions track can't be changed from the inspector.
    func testCaptionEditsFromTheInspector() async throws {
        let model = try await richModel()
        let first = try XCTUnwrap(model.project.captions.first)   // 0.5–2 s, "Hello there"
        // Start at the playhead, past the line's end and past the next line (4 s).
        model.setCaptionTiming(first.id, start: 5, end: max(first.end, 5.5))
        model.endGesture()
        let moved = try XCTUnwrap(model.project.captions.first { $0.id == first.id })
        XCTAssertEqual(moved.start, 5, accuracy: 0.001)
        XCTAssertEqual(moved.end, 5.5, accuracy: 0.001)
        XCTAssertEqual(model.project.captions.map(\.start), model.project.captions.map(\.start).sorted(), "the Lines list stays in order")

        // Word timings through ⌘A, Delete, typing.
        model.mutate { project in
            let index = project.captions.firstIndex { $0.id == first.id }!
            project.captions[index].text = "Hello there"
            project.captions[index].words = [VideoCaptionWord(text: "Hello", start: 5, end: 5.2), VideoCaptionWord(text: "there", start: 5.2, end: 5.5)]
        }
        model.endGesture()
        for text in ["", "H", "Hello", "Hello world"] { model.updateCaption(first.id, text: text) }
        model.endGesture()
        let retyped = try XCTUnwrap(model.project.captions.first { $0.id == first.id })
        XCTAssertEqual(retyped.words.map(\.text), ["Hello", "world"])
        XCTAssertEqual(retyped.words.first?.start ?? 0, 5, accuracy: 0.001, "the kept word keeps the voice's time")

        // Locked: text, timing and delete are refused.
        model.toggleTrackLocked(.captions)
        let locked = model.project
        model.updateCaption(first.id, text: "Changed")
        model.setCaptionTiming(first.id, start: 1)
        model.deleteCaption(first.id)
        XCTAssertEqual(model.project, locked)
    }

    /// Timeline (audit T1–T5): nothing lands on, moves onto, or is cut from a
    /// locked track by any route; files it can't take are said, not dropped silently.
    func testLockedTracksStayAsTheyAreHoweverTheyAreReached() async throws {
        let model = try await richModel()
        let picture = try XCTUnwrap(model.project.layerTracks.first?.items.first)
        // A second track above, with its own picture.
        var other = picture
        other.id = UUID()
        other.at = 5
        model.mutate { $0.insertLayerItem(other, place: .newTrack(1)) }
        model.endGesture()
        XCTAssertEqual(model.project.layerTracks.count, 2)
        let lockedID = model.project.layerTracks[0].id
        model.toggleTrackLocked(.layer(lockedID))

        // T1: a Library item aimed at the locked track goes on a new one.
        var sticker = picture
        sticker.id = UUID()
        sticker.at = 6
        model.mutate { $0.insertLayerItem(sticker, place: .track(0)) }
        model.endGesture()
        XCTAssertEqual(model.project.layerTracks.first { $0.id == lockedID }?.items.map(\.id), [picture.id])

        // T2: dragged from the free track onto the locked one: refused.
        var before = model.project
        let lockedIndex = try XCTUnwrap(model.project.layerTracks.firstIndex { $0.id == lockedID })
        model.moveLayerItem(other.id, to: 7, track: lockedIndex)
        XCTAssertEqual(model.project, before)

        // T3: a box over every track and Select Left/Right skip the locked
        // one's items; one picked anyway makes ⌫ refuse.
        let everything = Set([VideoTimelineTrack.clips] + model.project.layerTracks.map { .layer($0.id) })
        XCTAssertFalse(model.clips(from: 0, to: 10, on: everything).contains(.layer(picture.id)))
        model.seek(to: 0)
        XCTAssertTrue(model.selectAcross(left: false))
        XCTAssertFalse(model.selectedItems.contains(.layer(picture.id)))
        model.selection = .layer(other.id)
        model.extraSelection = [.layer(picture.id)]
        XCTAssertEqual(model.lockedTrackInSelection, .layer(lockedID))

        // T4: a range on the locked main track: cut, speed and mute refused.
        model.selection = .none
        model.toggleTrackLocked(.clips)
        before = model.project
        let range = VideoDemoTimelineRange(start: 1, end: 2)
        model.deleteRange(range)
        model.setRangeSpeed(range, 2)
        model.toggleRangeMute(range)
        XCTAssertEqual(model.project, before)

        // T5: a PDF dropped on the timeline is said.
        let pdf = directory.appendingPathComponent("notes.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        model.notice = nil
        await model.placeMedia([pdf], at: 0)
        XCTAssertEqual(model.notice?.message, L("Some files weren't added: LF Studios takes videos, pictures, and sound files"))
    }

    /// Export (audit E1, E2): a name an export still running will write
    /// counts as taken; H.264 at 4K of a wide video fits H.264's 4096 limit.
    func testExportNamesAndWide4KH264() {
        let url = directory.appendingPathComponent("Demo (edited).mp4")
        XCTAssertFalse(VideoEditorModel.taken(url, running: []))
        XCTAssertTrue(VideoEditorModel.taken(url, running: [url]))
        var settings = VideoExportSettings()
        settings.format = .mp4
        settings.codec = .h264
        settings.resolution = .p2160
        let wide = settings.outputSize(canvas: CGSize(width: 2520, height: 1080))   // 21:9
        XCTAssertLessThanOrEqual(wide.width, 4096)
        XCTAssertTrue(RecordingVideoFormat.fitsH264(width: Int(wide.width), height: Int(wide.height), fps: settings.fps))
        XCTAssertEqual(settings.outputSize(canvas: CGSize(width: 1920, height: 1080)), CGSize(width: 3840, height: 2160), "16:9 4K unchanged")
        settings.codec = .hevc
        XCTAssertEqual(settings.outputSize(canvas: CGSize(width: 2520, height: 1080)).height, 2160, "HEVC keeps the full size")
    }
}
