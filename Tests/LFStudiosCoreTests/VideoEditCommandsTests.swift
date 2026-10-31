import AppKit
import AVFoundation
import CoreImage
import XCTest
@testable import LFStudiosCore

/// The timeline's toolbar and keys (1.14.0): each VideoEditCommand does its
/// job in one ⌘Z step; the magnet, linkage and snapping; freeze frame,
/// reverse and the voiceover (synthetic sound, never the microphone).
@MainActor
final class VideoEditCommandsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!
    private var suiteName: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-commands-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "LFStudiosCoreTests.Commands.\(UUID().uuidString)"
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

    private func picture(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try VideoInspection.writePNG(to: url, size: CGSize(width: 160, height: 90), color: .green)
        return url
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
        XCTAssertEqual(model.project.layerTracks, before.layerTracks, "and the tracks", file: file, line: line)
        model.redo()
    }

    // MARK: Keys

    func testTheKeysAreCapCuts() {
        func command(_ key: String, _ modifiers: NSEvent.ModifierFlags = []) -> VideoEditCommand? { VideoEditCommand.command(key: key, modifiers: modifiers) }
        XCTAssertEqual(command("a"), .selectTool)
        XCTAssertEqual(command("b"), .splitTool)
        XCTAssertEqual(command("b", .command), .split)
        XCTAssertEqual(command("b", [.command, .shift]), .splitAllTracks)
        XCTAssertEqual(command("q"), .deleteLeft)
        XCTAssertEqual(command("w"), .deleteRight)
        XCTAssertEqual(command("p"), .toggleMagnet)
        XCTAssertEqual(command("n"), .toggleSnapping)
        XCTAssertEqual(command("`"), .toggleLinkage)
        XCTAssertEqual(command("s"), .togglePreviewAxis)
        XCTAssertEqual(command("z", .shift), .zoomToFit)
        XCTAssertEqual(command("v"), .toggleEnabled)
        XCTAssertEqual(command("g", .command), .group)
        XCTAssertEqual(command("g", [.command, .shift]), .ungroup)
        XCTAssertEqual(command("a", [.command, .shift]), .extractAudio)
        XCTAssertEqual(command("["), .selectLeft)
        XCTAssertEqual(command("]"), .selectRight)
        XCTAssertEqual(command("i"), .markIn)
        XCTAssertEqual(command("o"), .markOut)
        XCTAssertEqual(command("t", .option), .addText)
        XCTAssertEqual(command("a", .option), .addArrow)
        XCTAssertEqual(command("h", .option), .addHighlight)
        XCTAssertEqual(command("b", .option), .addBlur)
        // Z (zoom), M (mute) and C (split) stay the editor's own.
        XCTAssertNil(command("z"))
        XCTAssertNil(command("m"))
        XCTAssertNil(command("c"))
        XCTAssertNil(command("s", [.command, .shift]), "⇧⌘S stays Save Project As…")
        for command in VideoEditCommand.allCases {
            XCTAssertFalse(command.title.isEmpty)
            XCTAssertFalse(command.symbol.isEmpty)
        }
    }

    // MARK: One step each

    func testEachCommandIsOneUndoStep() async throws {
        let model = try await makeModel()
        model.seek(to: 1)
        await oneStep(model) { model.perform(.split) }
        model.seek(to: 0.5)
        model.selection = .none
        await oneStep(model) { model.perform(.mirror) }
        await oneStep(model) { model.perform(.rotate) }
        await oneStep(model) { model.perform(.toggleEnabled) }
        XCTAssertTrue(model.project.timelineClips[0].disabled)
        model.perform(.toggleEnabled)
        await oneStep(model) { model.perform(.deleteRight) }

        // Items above the main track.
        let added = await model.addLayerItem(from: try picture("a.png"), at: 0.5)
        let id = try XCTUnwrap(added)
        model.seek(to: 1.5)
        await oneStep(model) { model.perform(.split) }
        XCTAssertEqual(model.project.layerItems.count, 2)
        model.selection = .layer(id)
        model.seek(to: 1)
        await oneStep(model) { model.perform(.deleteLeft) }
        XCTAssertEqual(model.project.layerItem(id)?.at ?? 0, 1, accuracy: 0.001)
        await oneStep(model) { model.perform(.mirror) }
        XCTAssertEqual(model.project.layerItem(id)?.mirrored, true)
        await oneStep(model) { model.perform(.rotate) }
        XCTAssertEqual(model.project.layerItem(id)?.rotation, 90)
        await oneStep(model) { model.perform(.toggleEnabled) }
        XCTAssertEqual(model.project.layerItem(id)?.enabled, false)
        await oneStep(model) { model.perform(.delete) }
    }

    func testSplitAllTracksIsOneStep() async throws {
        let model = try await makeModel()
        await model.addLayerItem(from: try picture("a.png"), at: 0)
        await model.addAudio([try soundFile()], at: 0)
        model.selection = .none
        model.seek(to: 1)
        await oneStep(model) { model.perform(.splitAllTracks) }
        XCTAssertEqual(model.segments.count, 2)
        XCTAssertEqual(model.project.layerItems.count, 2)
        XCTAssertEqual(model.project.audioTracks.first?.pieces.count, 2)
    }

    private func soundFile() throws -> URL {
        let url = directory.appendingPathComponent("tone.m4a")
        try VideoInspection.writeTone(to: url, frequency: 440, seconds: 3)
        return url
    }

    // MARK: Groups, selecting, copy and paste, marks

    func testGroupsSelectionCopyPasteAndMarks() async throws {
        let model = try await makeModel()
        let firstID = await model.addLayerItem(from: try picture("a.png"), at: 0)
        let secondID = await model.addLayerItem(from: try picture("b.png"), at: 3)
        let a = try XCTUnwrap(firstID)
        let b = try XCTUnwrap(secondID)
        model.selection = .layer(a)
        model.extraSelection = [.layer(b)]
        XCTAssertTrue(model.perform(.group))
        // Moving one moves the group.
        model.moveLayerItem(a, to: 1, track: model.project.layerTrackIndex(of: a) ?? 0)
        XCTAssertEqual(model.project.layerItem(b)?.at ?? 0, 4, accuracy: 0.001)
        XCTAssertTrue(model.perform(.ungroup))
        XCTAssertNil(model.project.layerItem(a)?.group)

        // [ and ]: what's wholly left / right of the playhead.
        model.seek(to: 4)
        XCTAssertTrue(model.perform(.selectLeft))
        XCTAssertTrue(model.selectedItems.contains(.clip(model.segments[0].id)), "the clip ends at the playhead")
        XCTAssertFalse(model.selectedItems.contains(.layer(a)), "1–6 s isn't left of 4 s")
        model.seek(to: 0.5)
        XCTAssertTrue(model.perform(.selectRight))
        XCTAssertTrue(model.selectedItems.contains(.layer(b)))

        // ⌘C / ⌘V: at the playhead, spacing kept, on a track with room.
        model.selection = .layer(a)
        model.extraSelection = []
        XCTAssertTrue(model.perform(.copy))
        model.seek(to: 2)
        let count = model.project.layerItems.count
        XCTAssertTrue(model.perform(.paste))
        XCTAssertEqual(model.project.layerItems.count, count + 1)
        XCTAssertEqual(model.selectedLayerItem?.at ?? 0, 2, accuracy: 0.001)

        // I and O: the marked range.
        model.seek(to: 1)
        model.perform(.markIn)
        model.seek(to: 3)
        model.perform(.markOut)
        XCTAssertEqual(model.selection, .range(VideoDemoTimelineRange(start: 1, end: 3)))
    }

    // MARK: Magnet, linkage, snapping

    func testTheMagnetAndLinkage() async throws {
        let model = try await makeModel()
        model.seek(to: 2)
        model.perform(.split)
        // A picture over the second clip, at 3 s.
        let added = await model.addLayerItem(from: try picture("a.png"), at: 3)
        let id = try XCTUnwrap(added)
        XCTAssertTrue(Settings.videoTimelineMagnet && Settings.videoTimelineLinkage, "both on to start")
        // Deleting the first clip closes the gap; the picture moves with
        // what's under it.
        model.deleteClip(model.segments[0].id)
        XCTAssertEqual(model.timelineDuration, 2, accuracy: 0.05)
        XCTAssertEqual(model.project.layerItem(id)?.at ?? 0, 1, accuracy: 0.05, "linkage: it kept to its moment")
        model.undo()
        XCTAssertEqual(model.project.layerItem(id)?.at ?? 0, 3, accuracy: 0.001)

        // Linkage off: it stays where it was.
        model.perform(.toggleLinkage)
        model.deleteClip(model.segments[0].id)
        XCTAssertEqual(model.project.layerItem(id)?.at ?? 0, 3, accuracy: 0.001)
        model.undo()
        model.perform(.toggleLinkage)

        // Magnet off: a black gap of the clip's length stays.
        model.perform(.toggleMagnet)
        XCTAssertFalse(Settings.videoTimelineMagnet)
        model.deleteClip(model.segments[0].id)
        XCTAssertEqual(model.timelineDuration, 4, accuracy: 0.05, "the length is kept")
        XCTAssertTrue(model.project.timelineClips[0].disabled, "as a clip that's off")
        XCTAssertEqual(model.project.layerItem(id)?.at ?? 0, 3, accuracy: 0.001)
    }

    func testSnappingOffAndPreviewAxis() async throws {
        let model = try await makeModel()
        XCTAssertFalse(model.snapTargets(excluding: []).isEmpty)
        model.perform(.toggleSnapping)
        XCTAssertTrue(model.snapTargets(excluding: []).isEmpty, "snapping off: nothing pulls")
        model.perform(.toggleSnapping)
        // The preview axis shows another moment; the playhead stays.
        model.seek(to: 1)
        model.previewAxis(at: 3)
        XCTAssertEqual(model.previewAxisTime, 3)
        XCTAssertEqual(model.clock.time, 1, accuracy: 0.001)
        model.previewAxis(at: nil)
        XCTAssertNil(model.previewAxisTime)
        model.perform(.togglePreviewAxis)
        model.previewAxis(at: 2)
        XCTAssertNil(model.previewAxisTime, "off: hovering shows nothing else")
    }

    // MARK: Freeze, reverse, voiceover

    func testFreezeFrameAndReverse() async throws {
        let model = try await makeModel()
        model.seek(to: 1)
        await oneStep(model) { await model.freezeFrame() }
        XCTAssertEqual(model.timelineDuration, 7, accuracy: 0.1, "3 seconds held at the playhead")
        XCTAssertEqual(model.segments.count, 3)
        let frozen = try XCTUnwrap(model.project.sources.last)
        XCTAssertTrue(VideoGeneratedMedia.isGenerated(frozen.path))
        let held = VideoInspection.color(of: try VideoInspection.frame(of: URL(fileURLWithPath: frozen.path), at: 1.5), x: 0.5, y: 0.5)
        XCTAssertGreaterThan(held.r, 0.8, "the red frame at 1 s \(held)")
        model.undo()

        // The whole recording backwards: blue first.
        model.selection = .clip(model.segments[0].id)
        await oneStep(model) { await model.reverseSelection() }
        let reversed = try XCTUnwrap(model.project.sources.last { !$0.isPrimary })
        XCTAssertTrue(VideoGeneratedMedia.isGenerated(reversed.path))
        let start = VideoInspection.color(of: try VideoInspection.frame(of: URL(fileURLWithPath: reversed.path), at: 0.5), x: 0.5, y: 0.5)
        XCTAssertGreaterThan(start.b, 0.7, "it begins with the end (blue) \(start)")
        XCTAssertEqual(model.segments.count, 1, "the clip, reversed, in its place")
        XCTAssertEqual(model.timelineDuration, 4, accuracy: 0.1)
        let sound = try await AVURLAsset(url: URL(fileURLWithPath: reversed.path)).loadTracks(withMediaType: .audio)
        XCTAssertFalse(sound.isEmpty, "its sound comes along")
    }

    /// Saving, and waiting for it.
    private func save(_ model: VideoEditorModel) async throws {
        model.projectFileURL = directory.appendingPathComponent("Demo.lfs")
        model.projectMediaMode = .linked
        model.saveProject()
        let deadline = Date().addingTimeInterval(20)
        while model.isSavingProject, Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(model.isSavingProject)
    }

    func testUnusedMadeVideosGoWhenTheProjectIsSaved() async throws {
        let model = try await makeModel()
        model.seek(to: 1)
        await model.freezeFrame()
        let frozen = try XCTUnwrap(model.project.sources.last { VideoGeneratedMedia.isGenerated($0.path) })
        // One nothing uses (left over from an edit long gone).
        let orphan = try await VideoGeneratedMedia.stillVideo(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)), size: CGSize(width: 64, height: 64), seconds: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        try await save(model)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path), "nothing used it: gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: frozen.path), "the freeze frame is in the video: kept")

        // The freeze frame deleted: it leaves the project when it's saved…
        let clip = try XCTUnwrap(model.segments.first { $0.clip.sourceStart >= frozen.offset - 0.001 })
        model.deleteClip(clip.id)
        try await save(model)
        XCTAssertFalse(model.project.sources.contains { $0.id == frozen.id }, "no clip plays it: out of the project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: frozen.path), "⌘Z can still bring it back: kept")
        // …and once nothing can bring it back (a fresh editor, no undo),
        // its file goes on the next save.
        let url = directory.appendingPathComponent("rec.mp4")
        let reopened = VideoEditorModel(videoURL: url)
        await reopened.load()
        XCTAssertFalse(reopened.project.sources.contains { $0.id == frozen.id })
        try await save(reopened)
        XCTAssertFalse(FileManager.default.fileExists(atPath: frozen.path), "used nowhere: gone")
    }

    func testAVoiceoverBecomesATrackAtThePlayhead() async throws {
        let model = try await makeModel()
        let writer = try VideoVoiceoverWriter(url: directory.appendingPathComponent("vo.m4a"))
        // A second of a quiet tone, as the microphone would hand it over.
        let samples = (0..<48_000).map { Float(sin(Double($0) / 48_000 * 2 * .pi * 300) * 0.2) }
        for chunk in stride(from: 0, to: samples.count, by: 4_800) { writer.append(Array(samples[chunk..<min(chunk + 4_800, samples.count)])) }
        XCTAssertEqual(writer.seconds, 1, accuracy: 0.001)
        let depth = model.undoDepth
        let id = await model.finishVoiceover(writer, at: 1.5)
        let track = try XCTUnwrap(model.project.audioTracks.first { $0.id == id })
        XCTAssertEqual(track.name, "Voiceover")
        XCTAssertEqual(track.pieces.first?.at ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(track.duration, 1, accuracy: 0.1)
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step")
        // Too short to keep: nothing added.
        let empty = try VideoVoiceoverWriter(url: directory.appendingPathComponent("empty.m4a"))
        let none = await model.finishVoiceover(empty, at: 0)
        XCTAssertNil(none)
    }

    func testALockedTrackRefuses() async throws {
        let model = try await makeModel()
        let added = await model.addLayerItem(from: try picture("a.png"), at: 0)
        let id = try XCTUnwrap(added)
        model.toggleTrackLocked(.layer(model.project.layerTracks[0].id))
        model.selection = .layer(id)
        let before = model.project
        model.perform(.mirror)
        model.moveLayerItem(id, to: 2, track: 0)
        model.perform(.delete)
        XCTAssertEqual(model.project.layerTracks, before.layerTracks, "nothing on it changed")
    }
}
