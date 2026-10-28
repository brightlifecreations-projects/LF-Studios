import AVFoundation
import Foundation
import Testing
@testable import LFStudiosCore

/// Sound files added to a video (VideoExternalAudio.swift): every format
/// comes in, a track plays where it's placed (on the edit, or locked to the
/// recording through its cuts), Sync by sound lines it up, Use as my voice
/// replaces the microphone, and the tracks reach the export, Full Mix,
/// Creative Handoff, and a recording's folder. All synthetic sound.
@Suite("Added sound files", .serialized)
@MainActor
struct VideoExternalAudioTests {
    let folder: URL

    init() throws {
        try TestVideos.isolateStorage()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-added-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: Fixtures

    /// A sound file in `format` (wav, aiff, caf, flac, m4a) of `samples` at 48 kHz.
    func writeSound(_ samples: [Float], name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        let rate = 48_000.0
        let settings: [String: Any]
        switch url.pathExtension {
        case "wav": settings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        case "aiff": settings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true]
        case "caf": settings = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitDepthHintKey: 16]
        case "flac": settings = [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1]
        default: settings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000]
        }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
        return url
    }

    func tone(_ frequency: Double, from: Double, to: Double, seconds: Double) -> [Float] {
        TestSounds.tone(frequency, from: from, to: to, seconds: seconds, gain: 0.4, rate: 48_000)
    }

    /// A 6 s screen recording whose microphone track is `mic` (mono).
    func recording(mic: [Float]) async throws -> (url: URL, metadata: VideoDemoRecordingMetadata) {
        let picture = folder.appendingPathComponent("picture.mov")
        try await TestVideos.writeBars(to: picture, size: CGSize(width: 640, height: 360), seconds: 6)
        let micFile = folder.appendingPathComponent("mic.m4a")
        try TestSounds.writeAudio(mic, to: micFile, rate: 48_000)
        let screen = folder.appendingPathComponent("Screen.mov")
        try await TestSounds.mux(video: picture, audio: [micFile], to: screen)
        var metadata = VideoDemoRecordingMetadata(videoURLPath: screen.path, createdAt: Date(), duration: 6, sourceWidth: 640, sourceHeight: 360, fps: 30,
                                                  nativeCursorVisible: true, cursorSamples: [], clickEvents: [])
        metadata.audioTracks = [.microphone]
        return (screen, metadata)
    }

    func project(_ screen: URL, metadata: VideoDemoRecordingMetadata) -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: screen, duration: 6, sourceSize: CGSize(width: 640, height: 360))
        project.apply(metadata: metadata)
        project.audio.normalizeLoudness = false
        return project
    }

    func export(_ project: VideoDemoProject, metadata: VideoDemoRecordingMetadata, name: String) async throws -> [Float] {
        var settings = VideoExportSettings()
        settings.resolution = .p720
        settings.fps = 30
        settings.endCard = false
        let url = folder.appendingPathComponent(name)
        try await VideoDemoExporter.export(project: project, recording: metadata, destinationURL: url, settings: settings)
        return try await TestSounds.readTrack(url)
    }

    // MARK: Coming in

    @Test(arguments: ["wav", "aiff", "caf", "flac", "m4a"])
    func everyFormatComesInAsATrack(format: String) async throws {
        let url = try writeSound(tone(660, from: 0, to: 1.5, seconds: 1.5), name: "sound.\(format)")
        let prepared = try await VideoExternalAudioImport.prepare(url)
        #expect(abs(prepared.duration - 1.5) < 0.1, "\(format): \(prepared.duration)")
        #expect(prepared.url.path.hasPrefix(VideoAssetStore.folder.path), "LF Studios keeps its own copy")
        #expect(await VideoExternalAudioImport.playableLength(prepared.url) != nil)
        #expect(VideoExternalAudioTrack.fileExtensions.contains(format))
        #expect(VideoExternalAudioTrack.fileExtensions.isSuperset(of: ["mp3", "aac"]), "MP3 and AAC are offered too")
    }

    @Test func somethingThatIsntSoundIsRefused() async throws {
        let fake = folder.appendingPathComponent("notes.mp3")
        try "not sound".write(to: fake, atomically: true, encoding: .utf8)
        await #expect(throws: VideoExternalAudioImport.Failure.self) { try await VideoExternalAudioImport.prepare(fake) }
    }

    // MARK: Where it plays

    @Test func aFreeTrackPlaysWhereItsPlacedOnTheEdit() async throws {
        let (screen, metadata) = try await recording(mic: tone(440, from: 0, to: 6, seconds: 6))
        let file = try writeSound(tone(880, from: 0, to: 1, seconds: 1), name: "sting.wav")
        var project = project(screen, metadata: metadata)
        project.audioTracks = [VideoExternalAudioTrack(path: file.path, name: "sting.wav", duration: 1, at: 2)]
        let sound = try await export(project, metadata: metadata, name: "free.mp4")
        let during = TestSounds.level(of: 880, in: sound, from: 2.2, to: 2.8)
        let before = TestSounds.level(of: 880, in: sound, from: 0.2, to: 1.8)
        #expect(during > 0.1, "heard at 2 s: \(during)")
        #expect(before < during * 0.1, "not before: \(before)")
        #expect(TestSounds.level(of: 440, in: sound, from: 2.2, to: 2.8) > 0.1, "the recording's own sound still plays")
    }

    @Test func aTrackLockedToTheRecordingFollowsTheCutsAndSpeed() async throws {
        var track = VideoExternalAudioTrack(path: "/tmp/a.wav", name: "a.wav", duration: 2, at: 0)
        track.lock(toRecordingOffset: 3.5)
        #expect(track.lockedToRecording)
        #expect(track.pieces.first?.at == 3.5)
        // The edit keeps 0–2 s, cuts 2–3 s, and plays 3–6 s at 2×.
        let segments = [
            VideoDemoTimelineSegment(clip: VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 2), timelineStart: 0),
            VideoDemoTimelineSegment(clip: VideoDemoTimelineClip(sourceStart: 3, sourceEnd: 6, speed: 2), timelineStart: 2),
        ]
        let placed = track.placed(segments: segments, timelineDuration: 3.5)
        #expect(placed.count == 1)
        #expect(abs((placed.first?.timelineStart ?? 0) - 2.25) < 0.001, "recording 3.5 s is the edit's 2.25 s")
        #expect(placed.first?.speed == 2)
        #expect(abs((placed.first?.fileLength ?? 0) - 2) < 0.001)
        // A free one ignores the cuts, and stops where the edit ends.
        let free = VideoExternalAudioTrack(path: "/tmp/b.wav", name: "b.wav", duration: 5, at: 1)
        #expect(free.placed(segments: segments, timelineDuration: 3.5).map(\.timelineEnd) == [3.5])
    }

    @Test func aLockedTrackIsHeardWhereTheEditPlaysThatMoment() async throws {
        let (screen, metadata) = try await recording(mic: tone(440, from: 0, to: 6, seconds: 6))
        let file = try writeSound(tone(880, from: 0, to: 1, seconds: 1), name: "lav.wav")
        var project = project(screen, metadata: metadata)
        project.timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 2), VideoDemoTimelineClip(sourceStart: 3, sourceEnd: 6)]
        var track = VideoExternalAudioTrack(path: file.path, name: "lav.wav", duration: 1, at: 0)
        track.lock(toRecordingOffset: 3.5)
        project.audioTracks = [track]
        let sound = try await export(project, metadata: metadata, name: "locked.mp4")
        // Recording 3.5–4.5 s plays at the edit's 2.5–3.5 s.
        #expect(TestSounds.level(of: 880, in: sound, from: 2.6, to: 3.4) > 0.1)
        #expect(TestSounds.level(of: 880, in: sound, from: 0.2, to: 2.3) < 0.02)
    }

    // MARK: Editing it

    @Test func splitTrimMoveAndDeleteEachUndo() async throws {
        let (screen, metadata) = try await recording(mic: tone(440, from: 0, to: 6, seconds: 6))
        #expect(VideoDemoSidecarStore.save(metadata, for: screen))
        let file = try writeSound(tone(880, from: 0, to: 4, seconds: 4), name: "voiceover.m4a")
        let model = VideoEditorModel(videoURL: screen)
        await model.load()
        #expect(model.isReady)
        let ids = await model.addAudio([file], at: 1)
        let id = try #require(ids.first)
        #expect(model.project.audioTracks.first?.pieces.first?.at == 1)
        #expect(model.selectedAudioPiece?.track == id)
        #expect(model.undoLabel == "Add Audio")
        model.seek(to: 2.5)
        model.splitAtPlayhead() // S with a piece selected splits the sound
        #expect(model.project.audioTracks.first?.pieces.count == 2)
        #expect(model.project.timelineClips.count == 1, "the video wasn't split")
        let second = try #require(model.project.audioTracks.first?.pieces.last)
        #expect(abs(second.fileStart - 1.5) < 0.05 && abs(second.at - 2.5) < 0.05)
        let ref = VideoAudioPieceRef(track: id, piece: second.id)
        model.trimAudioPiece(ref, leading: true, by: 0.5)
        model.endGesture()
        #expect(abs((model.project.audioTracks.first?.pieces.last?.fileStart ?? 0) - 2.0) < 0.05)
        model.moveAudioPiece(ref, by: 1)
        model.endGesture()
        #expect(abs((model.project.audioTracks.first?.pieces.last?.at ?? 0) - 4.0) < 0.05)
        model.selectedAudioPiece = ref
        model.deleteSelection()
        #expect(model.project.audioTracks.first?.pieces.count == 1)
        model.undo()
        #expect(model.project.audioTracks.first?.pieces.count == 2)
        model.setAudioTrack(id) { $0.volume = 0.5; $0.fadeIn = 1 }
        #expect(model.project.audioTracks.first?.volume == 0.5)
        model.removeAudioTrack(id)
        #expect(model.project.audioTracks.isEmpty)
        model.undo()
        #expect(model.project.audioTracks.count == 1)
    }

    @Test func syncBySoundLinesItUpAndLocksIt() async throws {
        let beeps: [Double] = [0.5, 1.3, 2.9, 3.4, 4.6, 5.2]
        let (screen, metadata) = try await recording(mic: TestSounds.beeps(at: beeps, seconds: 6, rate: 48_000))
        #expect(VideoDemoSidecarStore.save(metadata, for: screen))
        // A separate microphone started 0.8 s after the recording.
        let lav = try writeSound(TestSounds.beeps(at: beeps.map { $0 - 0.8 }.filter { $0 > 0 }, seconds: 5.2, rate: 48_000, seed: 7), name: "lav.wav")
        let model = VideoEditorModel(videoURL: screen)
        await model.load()
        let id = try #require(await model.addAudio([lav], at: 0).first)
        await model.syncAudioTrack(id)
        let track = try #require(model.audioTrack(id))
        #expect(track.lockedToRecording)
        #expect(abs((track.pieces.first?.at ?? 0) - 0.8) < 0.05, "\(track.pieces)")
        #expect(model.undoLabel == "Sync Audio by Sound")
    }

    // MARK: As the voice

    @Test func useAsMyVoiceReplacesTheMicrophone() async throws {
        let (screen, metadata) = try await recording(mic: tone(440, from: 0, to: 6, seconds: 6))
        let file = try writeSound(tone(660, from: 0, to: 6, seconds: 6), name: "voice.wav")
        var project = project(screen, metadata: metadata)
        var track = VideoExternalAudioTrack(path: file.path, name: "voice.wav", duration: 6, at: 0)
        project.audioTracks = [track]
        var sound = try await export(project, metadata: metadata, name: "both.mp4")
        #expect(TestSounds.level(of: 440, in: sound, from: 1, to: 2) > 0.1, "the microphone plays beside an ordinary track")
        track.useAsVoice = true
        project.audioTracks = [track]
        #expect(project.externalVoice?.id == track.id)
        sound = try await export(project, metadata: metadata, name: "voice.mp4")
        #expect(TestSounds.level(of: 440, in: sound, from: 1, to: 2) < 0.01, "the microphone is replaced")
        #expect(TestSounds.level(of: 660, in: sound, from: 1, to: 2) > 0.1)
        // Enhance voice and Podcast mode clean up the added voice.
        project.audio.enhanceVoice = true
        let targets = project.voiceTargets(primaryKinds: [.microphone])
        #expect(targets.contains { $0.url.standardizedFileURL == file.standardizedFileURL && $0.trackIndex == 0 })
    }

    @Test func dipUnderVoiceLowersItOnlyWhileTheVoiceSpeaks() {
        let piece = VideoExternalAudioTrack.Placed(piece: UUID(), fileStart: 0, fileLength: 10, timelineStart: 0, speed: 1)
        let keyframes = VideoExternalAudioInput.envelope(level: 1, piece: piece, fadeIn: 0, fadeOut: 0, dip: 0.3, voice: [3...5])
        func gain(at time: Double) -> Double { keyframes.last { $0.time <= time }?.gain ?? 0 }
        #expect(gain(at: 1) == 1)
        #expect(abs(gain(at: 4) - 0.3) < 0.001)
        #expect(gain(at: 8) == 1)
        let undipped = VideoExternalAudioInput.envelope(level: 1, piece: piece, fadeIn: 2, fadeOut: 0, dip: nil, voice: [3...5])
        #expect(undipped.first?.gain == 0, "fades in from silence")
        #expect(undipped.contains { $0.time == 4 } == false, "no dip unless asked")
        #expect(VideoExternalAudioTrack(path: "/tmp/x.wav", name: "x", duration: 1, at: 0).dipUnderVoice == false, "off to start with")
    }

    // MARK: Everywhere it goes

    @Test func fullMixAndCreativeHandoffCarryTheAddedSound() async throws {
        let (screen, metadata) = try await recording(mic: tone(440, from: 0, to: 6, seconds: 6))
        let file = try writeSound(tone(880, from: 0, to: 1, seconds: 1), name: "sting.wav")
        var project = project(screen, metadata: metadata)
        project.audioTracks = [VideoExternalAudioTrack(path: file.path, name: "sting.wav", duration: 1, at: 2)]
        var settings = VideoExportSettings()
        settings.resolution = .p720
        settings.fps = 30
        settings.endCard = false
        let input = await VideoHandoffInput.gather(name: "Demo", project: project, recording: metadata, appendedMetadata: [:], exportSettings: settings)
        var options = VideoHandoffOptions()
        options.includeFinal = false
        let plan = VideoHandoffPlanner.plan(input, options: options, folderName: "Demo")
        let result = try await VideoHandoffWriter(plan: plan, input: input, parent: folder).run()
        let stem = result.folder.appendingPathComponent("03 Audio/sting.wav")
        #expect(FileManager.default.fileExists(atPath: stem.path))
        let stemSound = try TestSounds.read(stem)
        #expect(TestSounds.level(of: 880, in: stemSound, from: 2.2, to: 2.8) > 0.1, "laid out like the edit")
        let mix = try TestSounds.read(result.folder.appendingPathComponent("03 Audio/Full Mix.wav"))
        #expect(TestSounds.level(of: 880, in: mix, from: 2.2, to: 2.8) > 0.05, "in the full mix")
        let timeline = try String(contentsOf: result.folder.appendingPathComponent("Timeline.fcpxml"), encoding: .utf8)
        #expect(timeline.contains("sting.wav"), "on the timeline files")
        let opened = try VideoProjectPackage.open(result.folder.appendingPathComponent("Demo.lfstudios"))
        let reopened = try #require(opened.contents.project.audioTracks.first)
        #expect(reopened.path.hasPrefix(result.folder.standardizedFileURL.path), "the project points into the handoff")
        #expect(FileManager.default.fileExists(atPath: reopened.path))
        #expect(reopened.pieces == project.audioTracks[0].pieces)
    }

    @Test func aRecordingsFolderHoldsTheAddedSoundOnceAndReopensIt() throws {
        let home = folder.appendingPathComponent("Demo", isDirectory: true)
        let screen = home.appendingPathComponent("01 Screen/Demo.mov")
        try FileManager.default.createDirectory(at: screen.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: screen)
        let file = try writeSound(tone(880, from: 0, to: 1, seconds: 1), name: "outside.wav")
        var project = VideoDemoProject.fresh(sourceURL: screen)
        project.audioTracks = [VideoExternalAudioTrack(path: file.path, name: "outside.wav", duration: 1, at: 0)]
        let contents = VideoProjectContents(project: project, recording: nil, sourceRecordings: [:])
        let package = home.appendingPathComponent("Demo.lfstudios")
        // Written again after every edit: the sound is copied in once.
        for _ in 0..<3 {
            try VideoProjectPackage.save(contents, to: package, mode: .folder, folder: .init(kind: .recording))
        }
        let copies = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("03 Audio").path)
        #expect(copies == ["outside.wav"], "\(copies)")
        let opened = try VideoProjectPackage.open(package)
        #expect(opened.contents.project.audioTracks.first?.path == home.appendingPathComponent("03 Audio/outside.wav").standardizedFileURL.path)
    }

    @Test func projectsWithoutAddedSoundAreUnchangedAndTracksRoundTrip() throws {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 2, sourceSize: CGSize(width: 640, height: 360))
        let plain = try JSONEncoder().encode(project)
        #expect(!String(decoding: plain, as: UTF8.self).contains("audioTracks"), "older projects are written as before")
        var track = VideoExternalAudioTrack(path: "/tmp/b.wav", name: "b.wav", duration: 3, at: 1)
        track.useAsVoice = true
        track.dipUnderVoice = false
        _ = track.split(at: 2, segments: [])
        project.audioTracks = [track]
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: try JSONEncoder().encode(project))
        #expect(decoded.audioTracks == [track])
        #expect(decoded.audioTracks.first?.pieces.count == 2)
    }
}
