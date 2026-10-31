import AVFoundation
import XCTest
@testable import LFStudiosCore

/// Audio tools (1.15.0): Detect beats, Normalize loudness, volume
/// keyframes on sound files, a video's sound fades, and the commands.
@MainActor
final class VideoAudioToolsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-audiotools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    /// A click every `every` seconds over a quiet hum (a metronome).
    private func clicks(every: Double, seconds: Double) throws -> URL {
        let url = directory.appendingPathComponent("clicks.caf")
        let rate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let sinceClick = t.truncatingRemainder(dividingBy: every)
            let click = sinceClick < 0.03 ? sin(2 * .pi * 2000 * t) * 0.8 * (1 - sinceClick / 0.03) : 0
            buffer.floatChannelData![0][i] = Float(click + sin(2 * .pi * 110 * t) * 0.02)
        }
        try file.write(from: buffer)
        return url
    }

    func testDetectBeatsFindsTheClicks() throws {
        let beats = VideoAudioAnalysis.beats(try clicks(every: 0.5, seconds: 6))
        XCTAssertGreaterThanOrEqual(beats.count, 10)
        XCTAssertLessThanOrEqual(beats.count, 13)
        for beat in beats {
            let off = abs(beat - (beat / 0.5).rounded() * 0.5)
            XCTAssertLessThan(off, 0.04, "on a click: \(beat)")
        }
        // Silence: none.
        let quiet = directory.appendingPathComponent("quiet.m4a")
        try VideoInspection.writeTone(to: quiet, frequency: 440, seconds: 2, amplitude: 0)
        XCTAssertTrue(VideoAudioAnalysis.beats(quiet).isEmpty)
    }

    func testNormalizeRaisesAQuietSound() throws {
        let quiet = directory.appendingPathComponent("soft.m4a")
        try VideoInspection.writeTone(to: quiet, frequency: 440, seconds: 3, amplitude: 0.05)
        let volume = try XCTUnwrap(VideoAudioAnalysis.normalizedVolume(quiet))
        XCTAssertGreaterThan(volume, 1.2, "a soft tone gets louder")
        let loud = directory.appendingPathComponent("loud.m4a")
        try VideoInspection.writeTone(to: loud, frequency: 440, seconds: 3, amplitude: 0.8)
        XCTAssertLessThan(try XCTUnwrap(VideoAudioAnalysis.normalizedVolume(loud)), 1, "a loud one gets quieter")
    }

    private func makeModel() async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        return model
    }

    func testCommandsKeysBeatsAndSnapping() async throws {
        let model = try await makeModel()
        let added = await model.addAudio([try clicks(every: 0.5, seconds: 4)], at: 0)
        let id = try XCTUnwrap(added.first)
        // Volume keys at the playhead, one step each.
        model.seek(to: 0.5)
        var depth = model.undoDepth
        XCTAssertTrue(model.perform(.audio(.toggleVolumeKey(id))))
        XCTAssertEqual(model.undoDepth, depth + 1)
        model.seek(to: 3)
        model.perform(.audio(.setVolume(id, 0.2)))
        model.endGesture()
        let keys = try XCTUnwrap(model.audioTrack(id)?.volumeKeys)
        XCTAssertEqual(keys.keys(.volume).count, 2)
        XCTAssertEqual(model.audioTrack(id)?.volume, 1, "the base stays")
        XCTAssertTrue(model.project.needsFormat4)
        // Detect beats: one step, marks that clips snap to.
        depth = model.undoDepth
        await model.detectBeats(.sound(id))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertGreaterThan(model.audioTrack(id)?.beats?.count ?? 0, 5)
        let targets = model.snapTargets(excluding: [])
        XCTAssertTrue(targets.contains { abs($0 - 1.5) < 0.04 }, "a beat at 1.5 s is a snap target")
        // Normalize: one step.
        depth = model.undoDepth
        await model.normalize(.sound(id))
        XCTAssertEqual(model.undoDepth, depth + 1)
        // Locked: refused.
        model.toggleTrackLocked(.sound(id))
        let before = model.project.audioTracks
        model.perform(.audio(.toggleVolumeKey(id)))
        await model.detectBeats(.sound(id))
        XCTAssertEqual(model.project.audioTracks, before)
    }

    func testKeyedVolumeInTheExport() async throws {
        let source = directory.appendingPathComponent("white.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        var project = VideoInspection.project(for: source, seconds: 4, size: CGSize(width: 320, height: 180))
        let tone = directory.appendingPathComponent("tone.m4a")
        try VideoInspection.writeTone(to: tone, frequency: 660, seconds: 4)
        var track = VideoExternalAudioTrack(path: tone.path, name: "tone", duration: 4, at: 0)
        var keys = VideoKeyframes()
        keys.set(.volume, at: 0.5, value: 0)
        keys.set(.volume, at: 3.5, value: 1)
        track.volumeKeys = keys
        project.audioTracks = [track]
        let output = directory.appendingPathComponent("keyed.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let samples = try VideoInspection.audio(of: output)
        let early = VideoInspection.toneLevel(samples, frequency: 660, from: 0.1, to: 0.4)
        let late = VideoInspection.toneLevel(samples, frequency: 660, from: 3.6, to: 3.9)
        XCTAssertGreaterThan(late, early * 4 + 0.001, "silent at first, full at the end")
    }

    func testAVideosSoundFades() async throws {
        let source = directory.appendingPathComponent("white.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        var project = VideoInspection.project(for: source, seconds: 4, size: CGSize(width: 320, height: 180))
        let clip = directory.appendingPathComponent("toned.mov")
        try await VideoInspection.writeColorVideo(to: clip, size: CGSize(width: 160, height: 90), colors: [(.red, 4)], toneSeconds: 4, toneFrequency: 770)
        var item = VideoLayerItem(kind: .video, path: clip.path, name: "toned.mov", at: 0, length: 4, fileDuration: 4, aspect: 16.0 / 9)
        item.soundFadeIn = 2
        project.layerTracks = [VideoLayerTrack(items: [item])]
        let output = directory.appendingPathComponent("faded.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let samples = try VideoInspection.audio(of: output)
        XCTAssertGreaterThan(VideoInspection.toneLevel(samples, frequency: 770, from: 2.5, to: 3.5), VideoInspection.toneLevel(samples, frequency: 770, from: 0.05, to: 0.3) * 3 + 0.001)
    }
}
