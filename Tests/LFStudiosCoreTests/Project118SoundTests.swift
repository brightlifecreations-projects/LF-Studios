import AppKit
import AVFoundation
import XCTest
@testable import LFStudiosCore

/// Projects made before 1.18.0 (their sound now on rows of its own) export
/// the same picture and sound as LF Studios 1.17.0 did: each kind of
/// project's export, measured, against what 1.17.0 measured of the same
/// recordings (Fixtures/Projects118, written by running this test there
/// with LF_PIXEL_RECORD=1).
///
/// One intended difference (1.19.1): the "layered" project's video above
/// the main track used to fade from full to nearly silent across its 2.5 s;
/// it now keeps its level. Its sound there is checked to be steady
/// instead; its picture, and its sound before and after it, still match.
@MainActor
final class Project118SoundTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Projects118", isDirectory: true)
    private var recording: Bool { ProcessInfo.processInfo.environment["LF_PIXEL_RECORD"] != nil }
    private var output: URL!

    override func setUp() async throws {
        output = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-118-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: output)
    }

    private func file(_ name: String) -> URL { Self.fixtures.appendingPathComponent(name) }

    struct Media {
        let tone: URL
        let twoTracks: URL
        let voiceover: URL
        let song: URL
    }

    /// What every export is made from (written once, then kept).
    func media() async throws -> Media {
        try FileManager.default.createDirectory(at: Self.fixtures, withIntermediateDirectories: true)
        let media = Media(tone: file("tone.mp4"), twoTracks: file("two-tracks.mov"), voiceover: file("voiceover.m4a"), song: file("song.m4a"))
        func missing(_ url: URL) throws -> Bool {
            if FileManager.default.fileExists(atPath: url.path) { return false }
            guard recording else { throw XCTSkip("Fixtures/Projects118 is missing: run once with LF_PIXEL_RECORD=1 on 1.18.0") }
            return true
        }
        if try missing(media.tone) {
            try await VideoInspection.writeColorVideo(to: media.tone, size: CGSize(width: 320, height: 180), colors: [(.red, 1), (.green, 1), (.blue, 2)], toneSeconds: 3)
        }
        if try missing(media.twoTracks) { try await writeTwoTracks(to: media.twoTracks, seconds: 4) }
        if try missing(media.voiceover) { try VideoInspection.writeTone(to: media.voiceover, frequency: 660, seconds: 1.5, amplitude: 0.3) }
        if try missing(media.song) { try VideoInspection.writeTone(to: media.song, frequency: 220, seconds: 6, amplitude: 0.2) }
        return media
    }

    /// A picture with the microphone (440 Hz) and the Mac's sound (880 Hz)
    /// on two sound tracks.
    private func writeTwoTracks(to url: URL, seconds: Double) async throws {
        let picture = output.appendingPathComponent("picture.mp4")
        try await VideoTestSupport.writeFakeRecording(to: picture, size: CGSize(width: 320, height: 200), seconds: seconds, fps: 30)
        let composition = AVMutableComposition()
        var range = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600))
        // The assets stay alive while their tracks are copied.
        let pictureAsset = AVURLAsset(url: picture)
        let videoTracks = try await pictureAsset.loadTracks(withMediaType: .video)
        let source = try XCTUnwrap(videoTracks.first)
        // No longer than what's there.
        range.duration = min(range.duration, try await source.load(.timeRange).duration)
        try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)).insertTimeRange(range, of: source, at: .zero)
        var toneAssets: [AVURLAsset] = []
        for (frequency, amplitude) in [(440.0, 0.4), (880.0, 0.25)] {
            let tone = output.appendingPathComponent("tone-\(Int(frequency)).caf")
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
            let file = try AVAudioFile(forWriting: tone, settings: format.settings)
            let frames = AVAudioFrameCount((seconds + 0.5) * 48_000)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            buffer.frameLength = frames
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![0][frame] = Float(sin(2 * .pi * frequency * Double(frame) / 48_000) * amplitude)
            }
            try file.write(from: buffer)
            let toneAsset = AVURLAsset(url: tone)
            toneAssets.append(toneAsset)
            let audioTracks = try await toneAsset.loadTracks(withMediaType: .audio)
            let audio = try XCTUnwrap(audioTracks.first)
            try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)).insertTimeRange(range, of: audio, at: .zero)
        }
        let session = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
        session.outputURL = url
        session.outputFileType = .mov
        await session.export()
        withExtendedLifetime((pictureAsset, toneAssets)) {}
        XCTAssertEqual(session.status, .completed, session.error?.localizedDescription ?? "")
    }

    typealias Kind = (name: String, project: VideoDemoProject, recording: VideoDemoRecordingMetadata?)

    /// Each kind of project with sound, as 1.17.0 saved them.
    func projects(_ media: Media) -> [Kind] {
        func base(_ url: URL) -> VideoDemoProject {
            var project = VideoDemoProject.make(sourceURL: url, duration: 4, sourceSize: CGSize(width: 320, height: 180))
            project.audio.normalizeLoudness = false
            return project
        }

        let plain = base(media.tone)

        var edited = base(media.tone)
        var first = VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 1.5, speed: 2)
        first.fadeIn = 0.2
        // (A muted clip played half loud before 1.18.0: VideoLinkedAudioTests.)
        let second = VideoDemoTimelineClip(sourceStart: 1.5, sourceEnd: 2.5)
        var third = VideoDemoTimelineClip(sourceStart: 2.5, sourceEnd: 4)
        third.fadeOut = 0.5
        edited.timelineClips = [first, second, third]
        edited.audio.volume = 0.7

        var mixed = base(media.twoTracks)
        mixed.timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 1.8), VideoDemoTimelineClip(sourceStart: 2.2, sourceEnd: 4)]
        mixed.audio.voiceVolume = 0.5
        mixed.audio.systemVolume = 1.4
        let metadata = VideoDemoRecordingMetadata(videoURLPath: media.twoTracks.path, createdAt: Date(timeIntervalSince1970: 0), duration: 4, sourceWidth: 320, sourceHeight: 180, fps: 30,
                                                  nativeCursorVisible: true, cursorSamples: [], clickEvents: [], audioTracks: [.microphone, .system])

        var extras = base(media.tone)
        extras.audioTracks = [VideoExternalAudioTrack(path: media.voiceover.path, name: "Voiceover", duration: 1.5, at: 2)]
        extras.music = VideoMusicTrack(path: media.song.path, name: "Song", duration: 6)
        extras.audio.normalizeLoudness = true

        var muted = base(media.tone)
        var quiet = VideoDemoTimelineClip(sourceStart: 1, sourceEnd: 2)
        quiet.muted = true
        muted.timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 1), quiet, VideoDemoTimelineClip(sourceStart: 2, sourceEnd: 4)]

        var layered = base(media.tone)
        var above = VideoLayerItem(kind: .video, path: media.twoTracks.path, name: "two-tracks.mov", at: 0.5, length: 2.5, fileDuration: 4, aspect: 1.6)
        above.width = 0.5
        above.volume = 0.8
        var keys = VideoKeyframes()
        keys.tracks[VideoKeyProperty.opacity.rawValue] = [VideoKey(time: 0, value: 1, easing: .easeInOut), VideoKey(time: 2, value: 0.3)]
        above.keys = keys
        layered.layerTracks = [VideoLayerTrack(items: [above])]

        return [("plain", plain, nil), ("edited", edited, nil), ("mixed", mixed, metadata), ("extras", extras, nil), ("muted", muted, nil), ("layered", layered, nil)]
    }

    private struct Fingerprint: Codable {
        /// Loudness every 0.1 s.
        var rms: [Double]
        /// Each tone's level every 0.5 s.
        var tones: [String: [Double]]
        /// The middle of the picture every 0.5 s (0…255).
        var frames: [[Double]]
    }

    private func fingerprint(_ url: URL) async throws -> Fingerprint {
        let samples = try VideoInspection.audio(of: url)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        var print = Fingerprint(rms: [], tones: [:], frames: [])
        for i in 0..<Int(duration * 10) {
            print.rms.append(VideoInspection.rms(samples, from: Double(i) / 10, to: Double(i + 1) / 10))
        }
        for frequency in [220.0, 440, 660, 880] {
            print.tones["\(Int(frequency))"] = (0..<Int(duration * 2)).map { VideoInspection.toneLevel(samples, frequency: frequency, from: Double($0) / 2, to: Double($0 + 1) / 2) }
        }
        for i in 0..<Int(duration * 2) {
            let image = try VideoInspection.frame(of: url, at: Double(i) / 2 + 0.25)
            let c = VideoInspection.color(of: image, x: 0.5, y: 0.5)
            print.frames.append([c.r * 255, c.g * 255, c.b * 255])
        }
        return print
    }

    func testOlderProjectsSoundAndLookAsBefore() async throws {
        let media = try await media()
        var settings = VideoExportSettings()
        settings.resolution = .p720
        settings.fps = 30
        settings.endCard = false
        for kind in projects(media) {
            let url = output.appendingPathComponent("\(kind.name).mp4")
            try await VideoDemoExporter.export(project: kind.project, recording: kind.recording, destinationURL: url, settings: settings)
            let measured = try await fingerprint(url)
            let reference = file("\(kind.name).json")
            if recording {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(measured).write(to: reference)
                continue
            }
            let saved = try JSONDecoder().decode(Fingerprint.self, from: Data(contentsOf: reference))
            // The layered project's video above plays from 0.5 s to 3 s.
            let changed: (Double, Double) -> Bool = { start, end in kind.name == "layered" && end > 0.5 && start < 3 }
            XCTAssertEqual(measured.rms.count, saved.rms.count, "\(kind.name): as long as before")
            for (i, (a, b)) in zip(measured.rms, saved.rms).enumerated() where !changed(Double(i) / 10, Double(i + 1) / 10) {
                XCTAssertEqual(a, b, accuracy: 0.005 + b * 0.03, "\(kind.name): loudness at \(Double(i) / 10) s")
            }
            for (tone, levels) in saved.tones {
                for (i, (a, b)) in zip(measured.tones[tone] ?? [], levels).enumerated() where !changed(Double(i) / 2, Double(i + 1) / 2) {
                    XCTAssertEqual(a, b, accuracy: 0.005 + b * 0.03, "\(kind.name): \(tone) Hz at \(Double(i) / 2) s")
                }
            }
            if kind.name == "layered" {
                // Its sound (its first sound track, the microphone), as loud
                // at its end as at its start.
                for tone in ["440"] {
                    let levels = measured.tones[tone] ?? []
                    guard levels.count > 5 else { XCTFail("layered: \(tone) Hz measured"); continue }
                    XCTAssertGreaterThan(levels[2], 0.01, "layered: \(tone) Hz heard")
                    XCTAssertEqual(levels[5], levels[2], accuracy: levels[2] * 0.15, "layered: \(tone) Hz keeps its level")
                }
            }
            XCTAssertEqual(measured.frames.count, saved.frames.count)
            for (i, (a, b)) in zip(measured.frames, saved.frames).enumerated() {
                for channel in 0..<3 {
                    XCTAssertEqual(a[channel], b[channel], accuracy: 3, "\(kind.name): picture at \(Double(i) / 2 + 0.25) s")
                }
            }
        }
    }
}
