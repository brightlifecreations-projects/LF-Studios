import AVFoundation
import XCTest
@testable import LFStudiosCore

/// A video's sound on its own track (1.18.0): a row per sound track under
/// the clips, linked to them until Unlink Audio, each change one ⌘Z step.
@MainActor
final class VideoLinkedAudioTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-linked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    /// 4 s of picture with a tone for the first second.
    private func makeModel() async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 4)], toneSeconds: 1)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        return model
    }

    private var settings: VideoExportSettings {
        var settings = VideoExportSettings()
        settings.resolution = .p720
        settings.fps = 30
        settings.endCard = false
        return settings
    }

    private func export(_ model: VideoEditorModel, _ name: String) async throws -> [Float] {
        let url = directory.appendingPathComponent("\(name).mp4")
        try await VideoDemoExporter.export(project: model.project, recording: model.recording, destinationURL: url, settings: settings)
        return try VideoInspection.audio(of: url)
    }

    func testTheSoundHasItsOwnRowAndLeavesTheClip() async throws {
        let model = try await makeModel()
        XCTAssertTrue(model.hasAudio)
        let rows = model.timelineSoundRows
        XCTAssertEqual(rows.kinds.count, 1, "an imported video: one sound row")
        let layout = VideoTimelineRowLayout(project: model.project, hasCamera: false, sound: rows)
        let tracks = layout.rows.map(\.track)
        let clips = try XCTUnwrap(tracks.firstIndex(of: .clips))
        XCTAssertEqual(tracks[clips + 1], .clipSound(0, rows.kinds[0]), "right under the video")
        XCTAssertNotNil(layout.contentTop(.clipSound(0, rows.kinds[0])))
        await model.loadSoundWaveforms()
        let waveform = try XCTUnwrap(model.soundWaveforms[0])
        XCTAssertGreaterThan(waveform.peak(from: 0, to: 0.9), 0.05, "the tone")
        XCTAssertLessThan(waveform.peak(from: 1.5, to: 3.5), 0.01, "then quiet")
        // A recording with a microphone and the Mac's sound: one row each.
        let two = VideoTimelineRowLayout(project: model.project, hasCamera: false, sound: VideoTimelineSoundRows(kinds: [.microphone, .system]))
        XCTAssertNotNil(two.row(.clipSound(0, .microphone)))
        XCTAssertNotNil(two.row(.clipSound(1, .system)))
    }

    func testLinkedSoundFollowsSplitAndDelete() async throws {
        let model = try await makeModel()
        // Split at 0.5 s and delete the first part: the sound goes with it.
        model.seek(to: 0.5)
        XCTAssertTrue(model.perform(.split))
        XCTAssertEqual(model.project.timelineClips.count, 2)
        model.selection = .clip(try XCTUnwrap(model.project.timelineClips.first?.id))
        XCTAssertTrue(model.perform(.delete))
        let samples = try await export(model, "cut")
        XCTAssertGreaterThan(VideoInspection.rms(samples, from: 0.05, to: 0.4), 0.05, "the tone's last half second plays first")
        XCTAssertLessThan(VideoInspection.rms(samples, from: 0.7, to: 3.0), 0.01, "then quiet, as the picture")
    }

    func testUnlinkMoveAndLinkAreOneStepEach() async throws {
        let model = try await makeModel()
        let id = try XCTUnwrap(model.project.timelineClips.first?.id)
        model.selection = .clip(id)
        let before = model.project
        XCTAssertFalse(model.perform(.clip(.setAudioOffset(1))), "linked sound doesn't move on its own")

        var depth = model.undoDepth
        XCTAssertTrue(model.perform(.clip(.unlinkAudio)))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.project.timelineClips.first?.audioOffset, 0)
        XCTAssertFalse(model.perform(.clip(.unlinkAudio)), "already unlinked")

        // A drag: many changes, one step.
        depth = model.undoDepth
        for offset in stride(from: 0.1, through: 2, by: 0.1) { XCTAssertTrue(model.perform(.clip(.setAudioOffset(offset)))) }
        model.endGesture()
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step for the whole drag")
        XCTAssertEqual(model.project.timelineClips.first?.audioOffset ?? 0, 2, accuracy: 0.000_1)
        // Never before the start of the video.
        XCTAssertTrue(model.perform(.clip(.setAudioOffset(-5))))
        model.endGesture()
        XCTAssertEqual(model.project.timelineClips.first?.audioOffset ?? 1, 0, accuracy: 0.000_1)
        model.undo()
        XCTAssertEqual(model.project.timelineClips.first?.audioOffset ?? 0, 2, accuracy: 0.000_1)

        // Split keeps both halves' sound where it was.
        model.seek(to: 2)
        XCTAssertTrue(model.perform(.split))
        XCTAssertEqual(model.project.timelineClips.map(\.audioOffset), [2, 2])
        model.undo()

        depth = model.undoDepth
        XCTAssertTrue(model.perform(.clip(.linkAudio)))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertNil(model.project.timelineClips.first?.audioOffset)
        XCTAssertEqual(model.project, before, "linked again: as before")
        model.undo()
        XCTAssertEqual(model.project.timelineClips.first?.audioOffset ?? 0, 2, accuracy: 0.000_1)
    }

    func testUnlinkedSoundExportsWhereItWasMoved() async throws {
        let model = try await makeModel()
        model.selection = .clip(try XCTUnwrap(model.project.timelineClips.first?.id))
        let linked = try await export(model, "linked")
        XCTAssertGreaterThan(VideoInspection.rms(linked, from: 0.1, to: 0.9), 0.05)

        XCTAssertTrue(model.perform(.clip(.unlinkAudio)))
        let unmoved = try await export(model, "unmoved")
        XCTAssertGreaterThan(VideoInspection.rms(unmoved, from: 0.1, to: 0.9), 0.05, "unlinked but not moved: the same")
        XCTAssertLessThan(VideoInspection.rms(unmoved, from: 1.2, to: 3.8), 0.01)

        XCTAssertTrue(model.perform(.clip(.setAudioOffset(2))))
        model.endGesture()
        let moved = try await export(model, "moved")
        XCTAssertLessThan(VideoInspection.rms(moved, from: 0.1, to: 1.8), 0.01, "nothing before it")
        XCTAssertGreaterThan(VideoInspection.rms(moved, from: 2.1, to: 2.9), 0.05, "the tone two seconds later")
        XCTAssertLessThan(VideoInspection.rms(moved, from: 3.2, to: 3.8), 0.01)
    }

    func testOnlyUnlinkedSoundNeedsTheNewFormat() async throws {
        let model = try await makeModel()
        XCTAssertFalse(model.project.needsFormat5, "linked sound changes nothing in the file")
        let plain = try VideoProjectDocument(mediaMode: .linked, project: model.project, recording: nil).encoded()
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("audioOffset"))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("\"requires\" : 5"))

        model.selection = .clip(try XCTUnwrap(model.project.timelineClips.first?.id))
        XCTAssertTrue(model.perform(.clip(.unlinkAudio)))
        XCTAssertTrue(model.perform(.clip(.setAudioOffset(1.5))))
        model.endGesture()
        XCTAssertTrue(model.project.needsFormat5)
        let document = VideoProjectDocument(mediaMode: .linked, project: model.project, recording: nil)
        XCTAssertEqual(document.version, 5)
        let data = try document.encoded()
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"requires\" : 5"), "1.15–1.17 say it needs a newer version")
        let read = try VideoProjectDocument.decode(data)
        XCTAssertEqual(read.project.timelineClips.first?.audioOffset, 1.5, "this version reads it back")
    }

    /// A muted clip is silent and the clips around it keep their level,
    /// with or without fades and speed (before 1.18.0 a muted clip played
    /// half loud and the clip before it faded out).
    func testAMutedClipIsSilentBetweenFullClips() async throws {
        let url = directory.appendingPathComponent("tone.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.red, 4)], toneSeconds: 4)
        for (speed, fade) in [(1.0, 0.0), (2.0, 0.0), (1.0, 0.2), (2.0, 0.2)] {
            var project = VideoDemoProject.make(sourceURL: url, duration: 4, sourceSize: CGSize(width: 320, height: 180))
            project.audio.normalizeLoudness = false
            var first = VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 1.5, speed: speed)
            first.fadeIn = fade
            var muted = VideoDemoTimelineClip(sourceStart: 1.5, sourceEnd: 2.5)
            muted.muted = true
            project.timelineClips = [first, muted, VideoDemoTimelineClip(sourceStart: 2.5, sourceEnd: 4)]
            let out = directory.appendingPathComponent("muted-\(speed)-\(fade).mp4")
            try await VideoDemoExporter.export(project: project, recording: nil, destinationURL: out, settings: settings)
            let samples = try VideoInspection.audio(of: out)
            let edge = first.outputDuration
            let name = "speed \(speed), fade \(fade)"
            XCTAssertGreaterThan(VideoInspection.rms(samples, from: edge - 0.3, to: edge - 0.05), 0.3, "\(name): the clip before at its level")
            XCTAssertLessThan(VideoInspection.rms(samples, from: edge + 0.1, to: edge + 0.9), 0.001, "\(name): the muted clip is silent")
            XCTAssertGreaterThan(VideoInspection.rms(samples, from: edge + 1.1, to: edge + 1.4), 0.3, "\(name): the clip after at its level")
        }
    }

    /// A video on a track above keeps its level to its end (before 1.19.1
    /// it faded from full to nearly silent across the item), with fades,
    /// volume keyframes, unlinked sound and a muted neighbour; muted stays
    /// silent.
    func testAVideoAboveTheMainTrackKeepsItsLevel() async throws {
        let silent = directory.appendingPathComponent("silent.mp4")
        try await VideoInspection.writeColorVideo(to: silent, size: CGSize(width: 320, height: 180), colors: [(.white, 8)])
        let toned = directory.appendingPathComponent("toned.mp4")
        try await VideoInspection.writeColorVideo(to: toned, size: CGSize(width: 320, height: 180), colors: [(.red, 4)], toneSeconds: 4)
        func item(at: Double) -> VideoLayerItem {
            VideoLayerItem(kind: .video, path: toned.path, name: "toned.mp4", at: at, length: 3, fileDuration: 4, aspect: 16.0 / 9)
        }
        func exported(_ name: String, _ items: [VideoLayerItem], trackMuted: Bool = false) async throws -> [Float] {
            var project = VideoDemoProject.make(sourceURL: silent, duration: 8, sourceSize: CGSize(width: 320, height: 180))
            project.audio.normalizeLoudness = false
            let track = VideoLayerTrack(items: items)
            project.layerTracks = [track]
            if trackMuted { project.setTrackState(.layer(track.id)) { $0.muted = true } }
            let out = directory.appendingPathComponent("\(name).mp4")
            try await VideoDemoExporter.export(project: project, recording: nil, destinationURL: out, settings: settings)
            return try VideoInspection.audio(of: out)
        }
        func steady(_ samples: [Float], from start: Double, to end: Double, _ name: String) {
            let first = VideoInspection.rms(samples, from: start, to: start + 0.3)
            let last = VideoInspection.rms(samples, from: end - 0.3, to: end)
            XCTAssertGreaterThan(first, 0.1, "\(name): heard")
            XCTAssertEqual(last, first, accuracy: first * 0.1, "\(name): as loud at its end as at its start")
        }

        steady(try await exported("plain", [item(at: 1)]), from: 1.1, to: 3.9, "plain")

        var faded = item(at: 1)
        faded.soundFadeIn = 0.5
        faded.soundFadeOut = 0.5
        let fadedSound = try await exported("faded", [faded])
        steady(fadedSound, from: 1.6, to: 3.4, "between its fades")
        XCTAssertLessThan(VideoInspection.rms(fadedSound, from: 3.9, to: 4), VideoInspection.rms(fadedSound, from: 3.1, to: 3.4) * 0.5, "the fade out still fades")

        var keyed = item(at: 1)
        keyed.volume = 1
        var keys = VideoKeyframes()
        keys.set(.volume, at: 1, value: 1)
        keys.set(.volume, at: 1.5, value: 0.5)
        keyed.keys = keys
        let keyedSound = try await exported("keyed", [keyed])
        steady(keyedSound, from: 1.1, to: 1.9, "before the first key")
        steady(keyedSound, from: 2.6, to: 3.9, "after the last key")
        XCTAssertEqual(VideoInspection.rms(keyedSound, from: 3.4, to: 3.9), VideoInspection.rms(keyedSound, from: 1.2, to: 1.7) * 0.5, accuracy: 0.03, "at the last key's level")

        var unlinked = item(at: 1)
        unlinked.audioOffset = 1
        steady(try await exported("unlinked", [unlinked]), from: 2.1, to: 4.9, "unlinked and moved")

        var quiet = item(at: 4)
        quiet.muted = true
        let neighbours = try await exported("neighbours", [item(at: 1), quiet])
        steady(neighbours, from: 1.1, to: 3.9, "before a muted item")
        XCTAssertLessThan(VideoInspection.rms(neighbours, from: 4.1, to: 6.9), 0.001, "the muted item is silent")

        let mutedTrack = try await exported("muted-track", [item(at: 1)], trackMuted: true)
        XCTAssertLessThan(VideoInspection.rms(mutedTrack, from: 1.1, to: 3.9), 0.001, "a muted track is silent")
    }

    /// A video on a track above (1.19.0): its sound unlinked and moved
    /// plays later; one ⌘Z step each; the new format only then.
    func testAVideoAboveTheMainTrackUnlinksToo() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 5)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let above = directory.appendingPathComponent("above.mp4")
        try await VideoInspection.writeColorVideo(to: above, size: CGSize(width: 320, height: 180), colors: [(.red, 1)], toneSeconds: 1)
        await model.placeMedia([above], at: 1, target: .layer(.newTrack(0)))
        for _ in 0..<40 where model.media.layerFiles.isEmpty { try await Task.sleep(nanoseconds: 50_000_000) }
        let item = try XCTUnwrap(model.project.layerTracks.first?.items.first)
        model.selection = .layer(item.id)
        XCTAssertTrue(model.timelineSoundRows.layers.contains(try XCTUnwrap(model.project.layerTracks.first?.id)))
        XCTAssertFalse(model.project.needsFormat5)
        let linked = try await export(model, "layer-linked")
        XCTAssertGreaterThan(VideoInspection.rms(linked, from: 1.1, to: 1.9), 0.05, "its sound with its picture")

        var depth = model.undoDepth
        XCTAssertTrue(model.perform(.edit(.unlinkAudio)))
        XCTAssertEqual(model.undoDepth, depth + 1)
        depth = model.undoDepth
        for offset in stride(from: 0.25, through: 2, by: 0.25) { XCTAssertTrue(model.perform(.edit(.setAudioOffset(offset)))) }
        model.endGesture()
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step for the drag")
        XCTAssertTrue(model.project.needsFormat5, "1.18 would play it linked: it says it needs a newer version")
        let moved = try await export(model, "layer-moved")
        XCTAssertLessThan(VideoInspection.rms(moved, from: 1.1, to: 2.9), 0.01, "nothing under its picture")
        XCTAssertGreaterThan(VideoInspection.rms(moved, from: 3.1, to: 3.9), 0.05, "two seconds later")
        // Never before the start of the video.
        XCTAssertTrue(model.perform(.edit(.setAudioOffset(-10))))
        model.endGesture()
        XCTAssertEqual(model.project.layerItem(item.id)?.audioOffset ?? 0, -1, accuracy: 0.000_1)
        XCTAssertTrue(model.perform(.edit(.linkAudio)))
        XCTAssertNil(model.project.layerItem(item.id)?.audioOffset)
        XCTAssertFalse(model.project.needsFormat5)
    }
}
