import AVFoundation
import Foundation
import Testing
@testable import ShotStyleCore

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
