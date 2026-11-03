import AppKit
import AVFoundation
import XCTest
@testable import LFStudiosCore

/// 1.21.0's editor basics: the skimmer, box selection, gaps, duplicates,
/// pasting attributes, roll and slide, Loop playback, solo, track names,
/// meters, safe zones and Reveal in Library. Each edit is one ⌘Z step.
@MainActor
final class VideoEditorBasicsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!
    private var suiteName: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-basics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "LFStudiosCoreTests.Basics.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
    }

    /// Red for 2 s then blue for 2 s, with sound.
    private func makeModel() async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.red, 2), (.blue, 2)], toneSeconds: 4)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.isReady)
        return model
    }

    /// `action` takes exactly one ⌘Z step, which puts the project back.
    private func oneStep(_ model: VideoEditorModel, _ action: () async -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        let before = model.project
        let depth = model.undoDepth
        await action()
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step", file: file, line: line)
        XCTAssertNotEqual(model.project, before, "it changed something", file: file, line: line)
        model.undo()
        XCTAssertEqual(model.project.timelineClips, before.timelineClips, "⌘Z puts the clips back", file: file, line: line)
        model.redo()
    }

    private func cuts(_ model: VideoEditorModel) -> [Double] {
        model.segments.dropFirst().map { ($0.timelineStart * 100).rounded() / 100 }
    }

    // MARK: The skimmer

    /// ⌘B splits at the skimmer while the pointer is over the timeline, and
    /// at the playhead when it isn't (or the preview axis is off).
    func testSplitIsAtTheSkimmerElseThePlayhead() async throws {
        let model = try await makeModel()
        model.seek(to: 1)
        Settings.videoTimelinePreviewAxis = true
        model.timelinePointerTime = 3
        XCTAssertTrue(model.isSkimming)
        XCTAssertEqual(model.editTime, 3)
        await oneStep(model) { model.perform(.split) }
        XCTAssertEqual(cuts(model), [3], "at the skimmer, not the playhead")
        XCTAssertEqual(model.clock.time, 1, accuracy: 0.001, "the playhead stays put")

        // The pointer leaves the timeline: the playhead.
        model.timelinePointerTime = nil
        XCTAssertFalse(model.isSkimming)
        model.selection = .none
        model.perform(.split)
        XCTAssertEqual(cuts(model), [1, 3])

        // The preview axis off: the playhead too, wherever the pointer is.
        Settings.videoTimelinePreviewAxis = false
        model.timelinePointerTime = 2.5
        XCTAssertNil(model.skimmerTime)
        model.seek(to: 0.5)
        model.selection = .none
        model.perform(.split)
        XCTAssertEqual(cuts(model), [0.5, 1, 3])

        // ⇧⌘B at the skimmer, then the playhead.
        Settings.videoTimelinePreviewAxis = true
        model.timelinePointerTime = 2.2
        model.perform(.splitAllTracks)
        XCTAssertEqual(cuts(model), [0.5, 1, 2.2, 3])
        model.timelinePointerTime = nil
        model.seek(to: 3.5)
        model.perform(.splitAllTracks)
        XCTAssertEqual(cuts(model), [0.5, 1, 2.2, 3, 3.5])
    }

    // MARK: Helpers for clips above the main track

    private func picture(_ name: String, _ color: NSColor = .green) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try VideoInspection.writePNG(to: url, size: CGSize(width: 160, height: 90), color: color)
        return url
    }

    /// Pictures on one track at `spans` (start, length).
    private func pictures(_ model: VideoEditorModel, _ spans: [(Double, Double)]) async throws -> [UUID] {
        var ids: [UUID] = []
        for (index, span) in spans.enumerated() {
            let place: VideoEditorModel.LayerPlace = index == 0 ? .automatic : .track(0)
            let id = try await XCTUnwrapAsync(await model.addLayerItem(from: try picture("p\(index).png"), at: span.0, place: place))
            model.setLayerItem(id) { $0.length = span.1 }
            ids.append(id)
        }
        model.endGesture()
        XCTAssertEqual(model.project.layerTracks.count, 1)
        return ids
    }

    private func at(_ model: VideoEditorModel, _ id: UUID) -> Double {
        ((model.project.layerItem(id)?.at ?? -1) * 1000).rounded() / 1000
    }

    // MARK: Box selection

    private func names(_ items: [VideoEditorModel.Selection]) -> Set<String> { Set(items.map { String(describing: $0) }) }

    func testABoxSelectsTheClipsItTouches() async throws {
        let model = try await makeModel()
        model.seek(to: 2)
        model.perform(.split)
        let ids = try await pictures(model, [(0, 1), (1.5, 1), (3, 0.8)])
        let layer = VideoTimelineTrack.layer(model.project.layerTracks[0].id)

        // A box over the first two pictures and the second half of the main track.
        let found = model.clips(from: 0.5, to: 2.2, on: [layer, .clips])
        model.boxSelect(found, mode: .replace)
        XCTAssertEqual(names(model.selectedItems), names([.layer(ids[0]), .layer(ids[1]), .clip(model.segments[0].id), .clip(model.segments[1].id)]))
        // Only the pictures' track.
        model.boxSelect(model.clips(from: 0.5, to: 2.2, on: [layer]), mode: .replace)
        XCTAssertEqual(names(model.selectedItems), names([.layer(ids[0]), .layer(ids[1])]))
        // ⇧ adds.
        model.boxSelect(model.clips(from: 3.1, to: 3.5, on: [layer]), mode: .add)
        XCTAssertEqual(names(model.selectedItems), names(ids.map { .layer($0) }))
        // ⌘ toggles: the first goes, nothing new comes.
        model.boxSelect(model.clips(from: 0.1, to: 0.2, on: [layer]), mode: .toggle)
        XCTAssertEqual(names(model.selectedItems), names([.layer(ids[1]), .layer(ids[2])]))
    }

    // MARK: Gaps

    func testDeleteGapAndGapsAfterThePlayhead() async throws {
        let model = try await makeModel()
        let ids = try await pictures(model, [(0, 1), (2, 0.5), (3.5, 0.5)])
        let track = VideoTimelineTrack.layer(model.project.layerTracks[0].id)
        XCTAssertEqual(model.gap(on: track, at: 1.5), VideoTimelineGap(track: track, start: 1, end: 2))
        XCTAssertNil(model.gap(on: track, at: 0.5), "a clip is there")
        XCTAssertNil(model.gap(on: .clips, at: 1), "the main track has no gaps")
        await oneStep(model) { _ = model.perform(.basics(.deleteGap(track: track, time: 1.5))) }
        XCTAssertEqual([at(model, ids[0]), at(model, ids[1]), at(model, ids[2])], [0, 1, 2.5], "what came after moved back by the gap")

        // After the playhead: the next one comes to it, the rest follow.
        model.seek(to: 1.25)
        await oneStep(model) { _ = model.perform(.deleteGapsAfterPlayhead) }
        XCTAssertEqual([at(model, ids[0]), at(model, ids[1]), at(model, ids[2])], [0, 1, 1.5], "the one under the playhead stays; the next closes up")
        XCTAssertFalse(model.perform(.deleteGapsAfterPlayhead), "none left")
        // A locked track keeps its gaps.
        model.undo()
        model.toggleTrackLocked(track)
        XCTAssertFalse(model.deleteGap(on: track, at: 2))
    }

    // MARK: Duplicate

    func testDuplicateRightAfterItselfAndOptionDragCopies() async throws {
        let model = try await makeModel()
        let ids = try await pictures(model, [(0, 1), (1, 1)])
        model.selection = .layer(ids[0])
        await oneStep(model) { _ = model.perform(.duplicate) }
        let items = model.project.layerTracks[0].items
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map { ($0.at * 1000).rounded() / 1000 }, [0, 1, 2], "the copy right after it; the next one moved along")
        guard case .layer(let copy) = model.selection else { return XCTFail("the copy is selected") }
        XCTAssertNotEqual(copy, ids[0])
        XCTAssertEqual(at(model, ids[1]), 2)

        // Main-track clips are the recording itself: they say so.
        model.selection = .clip(model.segments[0].id)
        XCTAssertFalse(model.perform(.duplicate))
        XCTAssertEqual(model.segments.count, 1)

        // ⌥-drag: the original stays, a copy lands where it was dropped.
        let depth = model.undoDepth
        model.copyLayerItems([ids[1]], by: 1.5, fromTrack: 0, toTrack: 0, newTrack: false)
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(at(model, ids[1]), 2)
        XCTAssertEqual(model.project.layerItems.count, 4)
        XCTAssertTrue(model.project.layerItems.contains { abs($0.item.at - 3.5) < 0.001 })
    }

    // MARK: Paste attributes

    func testPasteAttributesOntoOtherClips() async throws {
        let model = try await makeModel()
        let ids = try await pictures(model, [(0, 1), (1, 1), (2, 1)])
        model.setLayerItem(ids[0]) { item in
            item.opacity = 0.5
            item.rotation = 30
            item.x = 0.3
            item.adjust = VideoAdjustSettings()
            item.adjust?.exposure = 0.4
            item.animation = VideoItemAnimation()
        }
        model.endGesture()
        model.selection = .layer(ids[0])
        model.perform(.copy)
        XCTAssertEqual(model.copiedAttributes?.set, [.transform, .adjust, .animation])
        model.selection = .layer(ids[1])
        model.extraSelection = [.layer(ids[2])]
        XCTAssertTrue(model.perform(.pasteAttributes))
        XCTAssertTrue(model.isPasteAttributesPresented, "the sheet to tick what to paste")
        model.isPasteAttributesPresented = false
        await oneStep(model) { _ = model.perform(.basics(.pasteAttributes([.transform]))) }
        for id in ids.dropFirst() {
            let item = try XCTUnwrap(model.project.layerItem(id))
            XCTAssertEqual(item.opacity, 0.5, accuracy: 0.001)
            XCTAssertEqual(item.rotation, 30, accuracy: 0.001)
            XCTAssertEqual(item.x, 0.3, accuracy: 0.001)
            XCTAssertNil(item.adjust, "only what was ticked")
        }
        model.perform(.basics(.pasteAttributes([.adjust])))
        XCTAssertEqual(model.project.layerItem(ids[2])?.adjust?.exposure ?? 0, 0.4, accuracy: 0.001)

        // Main-track clips: speed, sound and turns.
        model.seek(to: 2)
        model.selection = .none
        model.perform(.split)
        let first = model.segments[0].id, second = model.segments[1].id
        model.selection = .clip(first)
        model.perform(.clip(.setSpeed(2)))
        model.perform(.mirror)
        model.selection = .clip(first)
        model.perform(.copy)
        model.selection = .clip(second)
        await oneStep(model) { _ = model.perform(.basics(.pasteAttributes([.speed, .transform]))) }
        let clip = try XCTUnwrap(model.project.timelineClips.first { $0.id == second })
        XCTAssertEqual(clip.normalizedSpeed, 2, accuracy: 0.001)
        XCTAssertTrue(clip.mirrored)
    }

    // MARK: Roll and slide

    func testRollAndSlideKeepTheVideosLength() async throws {
        let model = try await makeModel()
        model.seek(to: 1); model.perform(.split)
        model.seek(to: 3); model.selection = .none; model.perform(.split)
        XCTAssertEqual(cuts(model), [1, 3])
        let length = model.timelineDuration
        let first = model.segments[0].id, middle = model.segments[1].id

        await oneStep(model) { _ = model.perform(.basics(.roll(clip: first, by: 0.5))) }
        XCTAssertEqual(cuts(model), [1.5, 3], "the cut moved; the clips on both sides changed")
        XCTAssertEqual(model.timelineDuration, length, accuracy: 0.001)
        XCTAssertEqual(model.segments[1].clip.sourceStart, 1.5, accuracy: 0.001)

        // Right after a split there's no unused part of the recording on
        // either side to slide into: it says so and changes nothing.
        XCTAssertFalse(model.perform(.basics(.slide(clip: middle, by: 0.3))))
        // A cut at the middle clip's start leaves 0.3 s unused before it.
        model.deleteRange(VideoDemoTimelineRange(start: 1.5, end: 1.8))
        XCTAssertEqual(cuts(model), [1.5, 2.7])
        let shorter = model.timelineDuration
        // (A cut makes the clip's rest a new clip.)
        let slid = model.segments[1].id
        await oneStep(model) { _ = model.perform(.basics(.slide(clip: slid, by: 0.2))) }
        XCTAssertEqual(cuts(model), [1.7, 2.9], "the clip moved between its neighbours")
        XCTAssertEqual(model.segments[1].clip.sourceStart, 1.8, accuracy: 0.001, "with the same frames")
        XCTAssertEqual(model.segments[1].clip.sourceEnd, 3, accuracy: 0.001)
        XCTAssertEqual(model.timelineDuration, shorter, accuracy: 0.001)

        // As far as both sides can go: the last clip can't get shorter than its least.
        model.perform(.basics(.roll(clip: slid, by: 5)))
        XCTAssertEqual(model.timelineDuration, shorter, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(model.segments[2].duration, VideoDemoProject.minimumClipDuration - 0.001)
        XCTAssertFalse(model.perform(.basics(.slide(clip: first, by: 0.2))), "the first clip has nothing before it")

        // Above the main track: two pictures that touch.
        let ids = try await pictures(model, [(0, 1), (1, 1)])
        await oneStep(model) { _ = model.perform(.basics(.roll(clip: ids[0], by: 0.25))) }
        XCTAssertEqual(model.project.layerItem(ids[0])?.length ?? 0, 1.25, accuracy: 0.001)
        XCTAssertEqual(at(model, ids[1]), 1.25)
        XCTAssertEqual(model.project.layerItem(ids[1])?.end ?? 0, 2, accuracy: 0.001, "the second still ends where it did")
    }

    // MARK: Loop playback

    func testLoopPlaybackRepeatsTheRange() async throws {
        let model = try await makeModel()
        XCTAssertFalse(model.loopsPlayback, "off to start with")
        XCTAssertEqual(model.loopRange, 0...model.timelineDuration, "the whole video")
        model.seek(to: 2.5)
        model.perform(.split)
        XCTAssertEqual(model.loopRange.lowerBound, 2.5, accuracy: 0.001, "the selected clip")
        model.selection = .range(VideoDemoTimelineRange(start: 0.5, end: 1.2))
        XCTAssertEqual(model.loopRange, 0.5...1.2, "the In/Out range")

        let before = model.project
        model.perform(.toggleLoopPlayback)
        XCTAssertTrue(model.loopsPlayback)
        XCTAssertTrue(model.isOn(.toggleLoopPlayback))
        XCTAssertEqual(model.project, before, "never in the project or the export")
        model.seek(to: 0.5)
        model.togglePlay()
        var times: [Double] = []
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            times.append(model.clock.time)
        }
        model.pause()
        XCTAssertTrue(times.allSatisfy { $0 >= 0.45 && $0 <= 1.25 }, "it stays in the range: \(times)")
        XCTAssertGreaterThan(times.max() ?? 0, 1.0, "and gets to its end")
    }

    // MARK: Solo and track names

    func testSoloIsForListeningAndNamesAreSaved() async throws {
        let model = try await makeModel()
        let video = directory.appendingPathComponent("b.mp4")
        try await VideoInspection.writeColorVideo(to: video, size: CGSize(width: 160, height: 90), colors: [(.green, 2)], toneSeconds: 2)
        let id = try await XCTUnwrapAsync(await model.addLayerItem(from: video, at: 0))
        _ = id
        let layer = VideoTimelineTrack.layer(model.project.layerTracks[0].id)
        XCTAssertFalse(model.project.trackState(layer).solo, "off to start with")
        let exported = model.project.forOutput()

        await oneStep(model) { _ = model.perform(.basics(.solo(layer))) }
        XCTAssertTrue(model.project.trackState(layer).solo)
        let heard = model.listeningProject
        XCTAssertTrue(heard.audio.muted, "the main track isn't heard while another track is soloed")
        XCTAssertFalse(heard.trackState(layer).muted)
        XCTAssertEqual(model.project.forOutput().audio, exported.audio, "the export keeps every track")
        XCTAssertFalse(model.project.forOutput().trackState(layer).muted)
        XCTAssertTrue(model.project.needsFormat8)

        // The main track soloed too: both heard.
        model.perform(.basics(.solo(.clips)))
        XCTAssertFalse(model.listeningProject.audio.muted)

        // Rename: double-click the name.
        await oneStep(model) { _ = model.perform(.basics(.renameTrack(layer, "B-roll"))) }
        XCTAssertEqual(layer.title(in: model.project), "B-roll")
        model.perform(.basics(.renameTrack(layer, "")))
        XCTAssertEqual(layer.title(in: model.project), layer.usualTitle(in: model.project), "an empty name goes back to the usual one")

        // Saved only when used, under the new format.
        let data = try JSONEncoder().encode(model.project)
        let back = try JSONDecoder().decode(VideoDemoProject.self, from: data)
        XCTAssertEqual(back.trackState(layer).solo, true)
        let plain = VideoTrackState()
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(json.contains("solo") || json.contains("name"), "other projects save as before: \(json)")
        XCTAssertTrue(json.contains("hidden"), "with the keys they always had")
    }

    // MARK: Meters

    func testMetersMoveWhilePlaying() async throws {
        XCTAssertEqual(VideoAudioMeters.position(forAmplitude: 1), 1, accuracy: 0.001)
        XCTAssertEqual(VideoAudioMeters.position(forAmplitude: 0.1), 2.0 / 3, accuracy: 0.001, "-20 dB")
        XCTAssertEqual(VideoAudioMeters.position(forAmplitude: 0), 0)
        XCTAssertEqual(VideoAudioMeters.zone(at: VideoAudioMeters.position(forAmplitude: 0.1)), .green)
        XCTAssertEqual(VideoAudioMeters.zone(at: VideoAudioMeters.position(forAmplitude: 0.5)), .yellow, "-6 dB")
        XCTAssertEqual(VideoAudioMeters.zone(at: VideoAudioMeters.position(forAmplitude: 0.9)), .red, "-1 dB")

        let model = try await makeModel()
        XCTAssertFalse(model.showsMeters, "off to start with (listening makes Play start a moment later)")
        XCTAssertNil(model.playback.meterStorage)
        model.showsMeters = true
        XCTAssertNotNil(model.playback.meterStorage)
        model.seek(to: 0.3)
        model.togglePlay()
        var loudest = 0.0
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            loudest = max(loudest, model.meters.left, model.meters.right)
        }
        model.pause()
        XCTAssertGreaterThan(loudest, 0.3, "the tone shows on the meters")
        for _ in 0..<20 where model.isPlaying { try await Task.sleep(nanoseconds: 50_000_000) }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.meters.left, 0, "back to nothing when it stops")
        model.showsMeters = false
        XCTAssertNil(model.playback.meterStorage, "off: no tap on the player")
    }

    // MARK: Safe zones

    func testGuidesAreOffAndNeverInTheProject() async throws {
        let model = try await makeModel()
        XCTAssertTrue(model.playerGuides.isEmpty, "off to start with")
        let before = model.project
        model.togglePlayerGuide(.thirds)
        model.togglePlayerGuide(.tiktok)
        XCTAssertEqual(model.playerGuides, [.thirds, .tiktok])
        XCTAssertEqual(model.project, before, "nothing in the project, so nothing in the export")
        XCTAssertFalse(model.isVertical, "a landscape video: the social apps' areas don't apply")
        XCTAssertEqual(VideoPlayerGuide.tiktok.coveredAreas.count, 3)
        model.togglePlayerGuide(.thirds)
        XCTAssertEqual(model.playerGuides, [.tiktok])
    }

    // MARK: Reveal in Library and Match Frame

    func testRevealInLibraryAndMatchFrame() async throws {
        let model = try await makeModel()
        model.libraryTab = .text
        model.seek(to: 1.5)
        model.selection = .clip(model.segments[0].id)
        XCTAssertTrue(model.perform(.revealInLibrary))
        XCTAssertEqual(model.libraryTab, .media)
        XCTAssertEqual(model.revealedMediaPath, model.project.sourceURL.path)
        XCTAssertTrue(model.perform(.matchFrame))
        let frame = try XCTUnwrap(model.sourceViewer)
        XCTAssertEqual(frame.url, model.project.sourceURL)
        XCTAssertEqual(frame.time, 1.5, accuracy: 0.01, "the same frame")

        // A video above the main track: its own second.
        let video = directory.appendingPathComponent("b.mp4")
        try await VideoInspection.writeColorVideo(to: video, size: CGSize(width: 160, height: 90), colors: [(.green, 3)], toneSeconds: nil)
        let id = try await XCTUnwrapAsync(await model.addLayerItem(from: video, at: 1))
        model.setLayerItem(id) { $0.fileStart = 0.5 }
        model.selection = .layer(id)
        model.seek(to: 2)
        model.sourceViewer = nil
        model.perform(.matchFrame)
        XCTAssertEqual(model.sourceViewer?.url.lastPathComponent, "b.mp4")
        XCTAssertEqual(model.sourceViewer?.time ?? 0, 1.5, accuracy: 0.01, "0.5 s in, plus 1 s on the timeline")
    }

    // MARK: For the AI Assistant and MCP agents

    func testTheNewEditsAreAgentTools() async throws {
        let names = Set(VideoAgentTools.all.map(\.name))
        for name in ["duplicate", "delete_gaps_after_playhead", "toggle_loop_playback", "reveal_in_library", "match_frame",
                     "delete_gap", "paste_attributes", "roll_cut", "slide_clip", "solo_track", "rename_track"] {
            XCTAssertTrue(names.contains(name), name)
        }
        let model = try await makeModel()
        _ = try await pictures(model, [(0, 1), (2, 1)])
        let tool = try XCTUnwrap(VideoAgentTools.all.first { $0.name == "delete_gap" })
        let result = try await tool.run(model, .object(["track": .string(model.project.layerTracks[0].id.uuidString), "time": .number(1.5)]), false)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(model.project.layerTracks[0].items.map(\.at), [0, 1])
    }
}

