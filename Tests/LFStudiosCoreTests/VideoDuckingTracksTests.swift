import XCTest
@testable import LFStudiosCore

/// Music ducks under voiceover and imported tracks (1.16.0): a switch on
/// each track, off to start with. Synthetic tones only, no microphone.
@MainActor
final class VideoDuckingTracksTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!
    private let size = CGSize(width: 640, height: 360)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-duck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    /// A silent recording, a song (1760 Hz), and a "voiceover" (440 Hz for
    /// 1.5 s) placed at 1 s on the timeline.
    private func project() async throws -> VideoDemoProject {
        let source = directory.appendingPathComponent("silent.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: size, colors: [(.gray, 4.5)])
        let song = directory.appendingPathComponent("song.m4a")
        try VideoInspection.writeTone(to: song, frequency: 1760, seconds: 5, amplitude: 0.3)
        let voice = directory.appendingPathComponent("voiceover.m4a")
        try VideoInspection.writeTone(to: voice, frequency: 440, seconds: 1.5, amplitude: 0.5)
        var project = VideoInspection.project(for: source, seconds: 4.5, size: size)
        var music = VideoMusicTrack(path: try VideoAssetStore.importFile(song).path, name: "song.m4a", duration: 5)
        music.volume = 1
        music.fadeIn = 0
        music.fadeOut = 0
        music.ducking = true
        music.duckLevel = 0.2
        project.music = music
        project.audioTracks = [VideoExternalAudioTrack(path: try VideoAssetStore.importFile(voice).path, name: "Voiceover", duration: 1.5, at: 1)]
        return project
    }

    private func musicLevels(_ project: VideoDemoProject, name: String) async throws -> (under: Double, alone: Double) {
        let output = directory.appendingPathComponent(name)
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let samples = try VideoInspection.audio(of: output)
        return (VideoInspection.toneLevel(samples, frequency: 1760, from: 1.5, to: 2.2),
                VideoInspection.toneLevel(samples, frequency: 1760, from: 3.6, to: 4.2))
    }

    func testOffToStartWithThenTheMusicMakesRoom() async throws {
        var project = try await project()
        XCTAssertNil(project.audioTracks[0].ducksMusic, "off to start with")
        XCTAssertFalse(project.needsFormat4)
        let off = try await musicLevels(project, name: "off.mp4")
        XCTAssertGreaterThan(off.alone, 0.12, "the song plays: \(off)")
        XCTAssertGreaterThan(off.under, off.alone * 0.8, "switch off: the voiceover doesn't duck it \(off)")

        project.audioTracks[0].ducksMusic = true
        XCTAssertTrue(project.needsFormat4)
        let on = try await musicLevels(project, name: "on.mp4")
        XCTAssertLessThan(on.under, on.alone * 0.45, "switch on: quieter under the voiceover \(on)")
        XCTAssertGreaterThan(on.alone, 0.12, "and back up after it \(on)")
    }

    func testWhatTheMusicDucksUnder() async throws {
        var project = try await project()
        let segments = project.timelineSegments(totalDuration: 4.5)
        let id = project.audioTracks[0].id
        let speech = ["track:\(id.uuidString)": [0.0...1.5]]
        XCTAssertEqual(VideoMusicDucking.musicVoice(project: project, primaryKinds: [], speech: speech, segments: segments), [], "off: nothing")
        project.audioTracks[0].ducksMusic = true
        let ranges = VideoMusicDucking.musicVoice(project: project, primaryKinds: [], speech: speech, segments: segments)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges.first?.lowerBound ?? 0, 1, accuracy: 0.001, "where the track plays on the timeline")
        XCTAssertEqual(ranges.first?.upperBound ?? 0, 2.5, accuracy: 0.001)
        // A muted track, or music without ducking: nothing.
        project.audioTracks[0].muted = true
        XCTAssertEqual(VideoMusicDucking.musicVoice(project: project, primaryKinds: [], speech: speech, segments: segments), [])
        project.audioTracks[0].muted = false
        project.music?.ducking = false
        XCTAssertEqual(VideoMusicDucking.musicVoice(project: project, primaryKinds: [], speech: speech, segments: segments), [])
    }

    func testTheSwitchIsOneStepAndRespectsTheLock() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: size, colors: [(.gray, 3)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let voice = directory.appendingPathComponent("vo.m4a")
        try VideoInspection.writeTone(to: voice, frequency: 440, seconds: 1)
        let track = VideoExternalAudioTrack(path: try VideoAssetStore.importFile(voice).path, name: "Voiceover", duration: 1, at: 0)
        model.mutate { $0.audioTracks = [track] }
        let depth = model.undoDepth
        XCTAssertTrue(model.perform(.audio(.ducksMusic(track.id, true))))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.project.audioTracks[0].ducksMusic, true)
        XCTAssertFalse(model.perform(.audio(.ducksMusic(track.id, true))), "already on")
        model.undo()
        XCTAssertNil(model.project.audioTracks[0].ducksMusic)
        model.toggleTrackLocked(.sound(track.id))
        XCTAssertFalse(model.perform(.audio(.ducksMusic(track.id, true))))
        XCTAssertNil(model.project.audioTracks[0].ducksMusic)
    }
}
