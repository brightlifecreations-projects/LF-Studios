import AVFoundation
import Foundation
import Testing
@testable import LFStudiosCore

/// Beeps for the sound-sync tests: short tones at chosen moments, written
/// as sample arrays or into a video's soundtrack.
enum TestSounds {
    static let sampleRate = 44_100.0

    /// Mono samples `seconds` long: a 1 kHz beep (80 ms) at each time,
    /// over a little hiss of `noise` (seeded, so runs repeat).
    static func beeps(at times: [Double], seconds: Double, rate: Double = sampleRate, gain: Float = 0.6, noise: Float = 0.01, seed: UInt64 = 1) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * rate))
        var state = seed
        for i in samples.indices {
            // xorshift: repeatable hiss.
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            samples[i] = noise * (Float(state % 2001) / 1000 - 1)
        }
        for time in times {
            let start = Int(time * rate), length = Int(0.08 * rate)
            for i in 0..<length where start + i >= 0 && start + i < samples.count {
                let ramp = Float(min(i, length - i, 80)) / 80
                samples[start + i] += gain * ramp * Float(sin(2 * Double.pi * 1000 * Double(i) / rate))
            }
        }
        return samples
    }

    /// An .m4a of `samples`.
    static func writeAudio(_ samples: [Float], to url: URL, rate: Double = sampleRate) throws {
        try? FileManager.default.removeItem(at: url)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000])
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
    }

    /// `video`'s picture with several sound tracks (in order), as one movie.
    static func mux(video: URL, audio tracks: [URL], to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let composition = AVMutableComposition()
        let picture = AVURLAsset(url: video)
        let videoTrack = try #require(try await picture.loadTracks(withMediaType: .video).first)
        let duration = try await picture.load(.duration)
        let v = try #require(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try v.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        for audio in tracks {
            let sound = AVURLAsset(url: audio)
            let audioTrack = try #require(try await sound.loadTracks(withMediaType: .audio).first)
            let audioDuration = try await sound.load(.duration)
            let a = try #require(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
            try a.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: audioTrack, at: .zero)
        }
        let session = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        try await session.export(to: url, as: .mov)
    }

    /// Stereo samples (the same in both channels) as an .m4a.
    static func writeStereo(_ samples: [Float], to url: URL, rate: Double = sampleRate) throws {
        try? FileManager.default.removeItem(at: url)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000])
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for channel in 0..<2 {
            samples.withUnsafeBufferPointer { buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: samples.count) }
        }
        try file.write(from: buffer)
    }

    /// Mono samples of a WAV or other sound file, at `rate`.
    static func read(_ url: URL, rate: Double = 48_000) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = buffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    /// Where loud stretches start (seconds), at least `gap` apart.
    static func onsets(_ samples: [Float], rate: Double = 48_000, threshold: Float = 0.1, gap: Double = 0.2) -> [Double] {
        var onsets: [Double] = []
        var last = -Double.infinity
        let window = Int(rate * 0.005)
        var i = 0
        while i + window < samples.count {
            var peak: Float = 0
            for j in i..<(i + window) { peak = max(peak, abs(samples[j])) }
            let t = Double(i) / rate
            if peak > threshold, t - last > gap {
                onsets.append(t)
                last = t
            }
            if peak > threshold { last = t }
            i += window
        }
        return onsets
    }

    /// `video`'s picture with `audio`'s sound, as one movie.
    static func mux(video: URL, audio: URL, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let composition = AVMutableComposition()
        let picture = AVURLAsset(url: video), sound = AVURLAsset(url: audio)
        let videoTrack = try #require(try await picture.loadTracks(withMediaType: .video).first)
        let audioTrack = try #require(try await sound.loadTracks(withMediaType: .audio).first)
        let duration = try await picture.load(.duration)
        let audioDuration = try await sound.load(.duration)
        let v = try #require(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try v.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        let a = try #require(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try a.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: audioTrack, at: .zero)
        let session = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        session.outputURL = url
        session.outputFileType = .mov
        await session.export()
        #expect(session.status == .completed, "mux: \(String(describing: session.error))")
    }
}
