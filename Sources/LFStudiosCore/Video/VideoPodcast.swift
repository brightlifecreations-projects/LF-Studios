import AVFoundation
import Foundation

// MARK: - Settings

/// "Podcast mode": a voice chain for spoken audio, each step its own
/// switch. Off (nil) until its button is pressed.
struct VideoPodcastSettings: Codable, Equatable {
    /// The podcast standard: −16 LUFS for stereo.
    static let targetLoudness = -16.0

    /// Apple's voice isolation plus a gate that quiets the room between words.
    var noiseRemoval = true
    /// Tames harsh "s" and "sh" sounds.
    var deEsser = true
    /// Warm and clear: less rumble and mud, more presence.
    var equalizer = true
    /// Evens out loud and quiet words.
    var compressor = true
    /// The whole mix at −16 LUFS, peaks under −1 dB.
    var loudness = true

    init() {}

    private enum CodingKeys: String, CodingKey { case noiseRemoval, deEsser, equalizer, compressor, loudness }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noiseRemoval = (try? c.decodeIfPresent(Bool.self, forKey: .noiseRemoval)) ?? true
        deEsser = (try? c.decodeIfPresent(Bool.self, forKey: .deEsser)) ?? true
        equalizer = (try? c.decodeIfPresent(Bool.self, forKey: .equalizer)) ?? true
        compressor = (try? c.decodeIfPresent(Bool.self, forKey: .compressor)) ?? true
        loudness = (try? c.decodeIfPresent(Bool.self, forKey: .loudness)) ?? true
    }

    /// Any step that works on the voice track itself (loudness works on
    /// the finished mix).
    var processesVoice: Bool { noiseRemoval || deEsser || equalizer || compressor }
}

// MARK: - What is done to the voice

/// How a voice track is cleaned up before it's mixed: Enhance voice's
/// gentle chain, or podcast mode's steps. Each recipe has its own cache.
struct VideoVoiceRecipe: Equatable {
    enum Equalizer: Equatable { case none, gentle, podcast }
    enum Compressor: Equatable { case none, gentle, podcast }

    var isolation: Bool
    var gate: Bool
    var deEsser: Bool
    var equalizer: Equalizer
    var compressor: Compressor
    /// Brings the voice to a steady level with its peaks held, so the mix
    /// can reach −16 LUFS without clipping.
    var level: Bool

    /// Enhance voice, as it always was.
    static let enhance = VideoVoiceRecipe(isolation: true, gate: false, deEsser: false, equalizer: .gentle, compressor: .gentle, level: false)

    static func podcast(_ settings: VideoPodcastSettings) -> VideoVoiceRecipe {
        VideoVoiceRecipe(
            isolation: settings.noiseRemoval,
            gate: settings.noiseRemoval,
            deEsser: settings.deEsser,
            equalizer: settings.equalizer ? .podcast : .none,
            compressor: settings.compressor ? .podcast : .none,
            level: settings.loudness
        )
    }

    /// Part of the cache file's name (empty for Enhance voice, so its
    /// files made before stay valid).
    var signature: String {
        guard self != .enhance else { return "" }
        func flag(_ on: Bool) -> String { on ? "1" : "0" }
        let eq: String = { switch equalizer { case .none: return "n"; case .gentle: return "g"; case .podcast: return "p" } }()
        let comp: String = { switch compressor { case .none: return "n"; case .gentle: return "g"; case .podcast: return "p" } }()
        return "|podcast\(VideoVoiceDSP.version)-\(flag(isolation))\(flag(gate))\(flag(deEsser))\(eq)\(comp)\(flag(level))"
    }

    /// Steps run after the Audio Unit chain, in our own code.
    var needsPostProcessing: Bool { gate || deEsser || level }
}

extension VideoAudioSettings {
    /// What's done to the voice before mixing (nil: the recording's own).
    var voiceRecipe: VideoVoiceRecipe? {
        if let podcast, podcast.processesVoice { return .podcast(podcast) }
        if podcast == nil, enhanceVoice { return .enhance }
        return nil
    }

    /// The export is brought to −16 LUFS.
    var normalizesLoudness: Bool { podcast?.loudness ?? normalizeLoudness }
}

// MARK: - Our own processing

/// The podcast chain's steps written here: a de-esser, a noise gate, and
/// a peak limiter. Mono float samples, processed in chunks.
enum VideoVoiceDSP {
    static let version = 1

    /// A two-pole filter (RBJ cookbook formulas).
    struct Biquad {
        var b0, b1, b2, a1, a2: Float
        var z1: Float = 0, z2: Float = 0

        static func highPass(frequency: Double, q: Double, sampleRate: Double) -> Biquad {
            let w = 2 * Double.pi * frequency / sampleRate
            let alpha = sin(w) / (2 * q)
            let c = cos(w)
            let a0 = 1 + alpha
            return Biquad(b0: Float((1 + c) / 2 / a0), b1: Float(-(1 + c) / a0), b2: Float((1 + c) / 2 / a0), a1: Float(-2 * c / a0), a2: Float((1 - alpha) / a0))
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    /// Follows a level up quickly and down slowly.
    struct Envelope {
        let attack: Float
        let release: Float
        var value: Float = 0

        init(attack: Double, release: Double, sampleRate: Double) {
            self.attack = Float(1 - exp(-1 / (attack * sampleRate)))
            self.release = Float(1 - exp(-1 / (release * sampleRate)))
        }

        mutating func process(_ x: Float) -> Float {
            let level = abs(x)
            value += (level - value) * (level > value ? attack : release)
            return value
        }
    }

    /// Listens to the "s" band (5 kHz and up) and turns the voice down for
    /// the moment it's much louder than the rest — a wideband de-esser (a
    /// filtered copy can't be subtracted cleanly: the filter shifts its
    /// phase).
    struct DeEsser {
        var split: Biquad
        var split2: Biquad
        var hiss: Envelope
        var body: Envelope
        var gain: Float = 1
        let smoothing: Float
        /// The "s" band may be this share of the whole before it's turned down.
        let ratio: Float = 0.42

        init(sampleRate: Double) {
            split = .highPass(frequency: 5_000, q: 0.707, sampleRate: sampleRate)
            split2 = .highPass(frequency: 5_000, q: 0.707, sampleRate: sampleRate)
            hiss = Envelope(attack: 0.001, release: 0.06, sampleRate: sampleRate)
            body = Envelope(attack: 0.005, release: 0.08, sampleRate: sampleRate)
            smoothing = Float(1 - exp(-1 / (0.002 * sampleRate)))
        }

        mutating func process(_ x: Float) -> Float {
            let high = split2.process(split.process(x))
            let h = hiss.process(high)
            let b = body.process(x)
            var target: Float = 1
            if h > 0.003, h > b * ratio {
                // Down by as much as 10 dB.
                target = max(powf(b * ratio / h, 0.7), 0.32)
            }
            gain += (target - gain) * smoothing
            return x * gain
        }
    }

    /// Lowers the room's noise between words: below the threshold the
    /// sound fades down by `depth` (not to silence).
    struct Gate {
        var envelope: Envelope
        var gain: Float = 1
        let threshold: Float
        let floorGain: Float
        let open: Float
        let close: Float

        init(threshold: Float, depthDecibels: Float = 14, sampleRate: Double) {
            envelope = Envelope(attack: 0.002, release: 0.08, sampleRate: sampleRate)
            self.threshold = threshold
            floorGain = powf(10, -depthDecibels / 20)
            open = Float(1 - exp(-1 / (0.004 * sampleRate)))
            close = Float(1 - exp(-1 / (0.18 * sampleRate)))
        }

        mutating func process(_ x: Float) -> Float {
            let level = envelope.process(x)
            let target: Float = level >= threshold ? 1 : max(floorGain, min(level / threshold, 1) * 0.5)
            gain += (target - gain) * (target > gain ? open : close)
            return x * gain
        }
    }

    /// Holds peaks under `ceiling`, looking 5 ms ahead so it never clips.
    struct Limiter {
        let ceiling: Float
        let lookahead: Int
        let release: Float
        private var delay: [Float]
        private var gains: [Float]
        private var index = 0
        private var gain: Float = 1

        init(ceiling: Float, sampleRate: Double) {
            self.ceiling = ceiling
            lookahead = max(Int(sampleRate * 0.005), 1)
            release = Float(1 - exp(-1 / (0.08 * sampleRate)))
            delay = Array(repeating: 0, count: lookahead)
            gains = Array(repeating: 1, count: lookahead)
        }

        mutating func process(_ x: Float) -> Float {
            let needed: Float = abs(x) > ceiling ? ceiling / abs(x) : 1
            gains[index] = needed
            let out = delay[index]
            delay[index] = x
            index = (index + 1) % lookahead
            // The lowest gain any sample in the window needs.
            let target = gains.min() ?? 1
            gain = target < gain ? target : gain + (target - gain) * release
            let y = out * gain
            return max(min(y, ceiling), -ceiling)
        }

        /// The samples still in the window, at the end.
        mutating func flush() -> [Float] {
            (0..<lookahead).map { _ in process(0) }
        }
    }

    /// The room's noise level: a quiet percentile of short-window levels.
    static func noiseFloor(of samples: [Float], sampleRate: Double) -> Float {
        let window = max(Int(sampleRate * 0.02), 1)
        var levels: [Float] = []
        var index = 0
        while index + window <= samples.count {
            var peak: Float = 0
            for value in samples[index..<(index + window)] { peak = max(peak, abs(value)) }
            levels.append(peak)
            index += window
        }
        guard !levels.isEmpty else { return 0 }
        levels.sort()
        return levels[min(levels.count / 10, levels.count - 1)]
    }

    /// The rendered voice (mono float file) through our steps: de-esser and
    /// gate, then, with `level`, a steady −20 LUFS with peaks held 15 dB
    /// above that — room for the mix to reach −16 LUFS under −1 dB.
    static func postProcess(_ input: URL, to output: URL, recipe: VideoVoiceRecipe, progress: (Double) -> Void) throws {
        let reader = try AVAudioFile(forReading: input, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = reader.processingFormat
        let rate = format.sampleRate
        let total = max(reader.length, 1)
        let chunk: AVAudioFrameCount = 16_384

        func read(_ file: AVAudioFile, _ body: (UnsafeMutablePointer<Float>, Int) throws -> Void) throws {
            file.framePosition = 0
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { return }
            while file.framePosition < file.length {
                try file.read(into: buffer, frameCount: chunk)
                guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
                try body(data[0], Int(buffer.frameLength))
            }
        }

        // Pass 1: noise floor (for the gate), from the first minutes.
        var threshold: Float = 0
        if recipe.gate {
            var sample: [Float] = []
            try read(reader) { data, count in
                if sample.count < Int(rate * 180) { sample.append(contentsOf: UnsafeBufferPointer(start: data, count: count)) }
            }
            threshold = max(noiseFloor(of: sample, sampleRate: rate) * 2.5, 0.0015)
        }

        // Pass 2: de-esser and gate, measuring the loudness as it goes.
        let middle = output.deletingLastPathComponent().appendingPathComponent("podcast-middle.caf")
        let writer = try AVAudioFile(forWriting: middle, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var deEsser = DeEsser(sampleRate: rate)
        var gate = Gate(threshold: threshold, sampleRate: rate)
        let meter = VideoLoudnessMeter(channels: 1, sampleRate: rate)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
        var done: AVAudioFramePosition = 0
        try read(reader) { data, count in
            let target = out.floatChannelData![0]
            for i in 0..<count {
                var x = data[i]
                if recipe.deEsser { x = deEsser.process(x) }
                if recipe.gate { x = gate.process(x) }
                target[i] = x
            }
            out.frameLength = AVAudioFrameCount(count)
            meter.add(interleaved: UnsafeBufferPointer(start: target, count: count))
            try writer.write(from: out)
            done += AVAudioFramePosition(count)
            progress(Double(done) / Double(total) * (recipe.level ? 0.5 : 1))
        }

        // Pass 3: a steady level with its peaks held.
        let processed = try AVAudioFile(forReading: middle, commonFormat: .pcmFormatFloat32, interleaved: false)
        let final = try AVAudioFile(forWriting: output, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let voiceTarget = -20.0
        let gain = Float(meter.integratedLoudness.map { pow(10, min(max(voiceTarget - $0, -30), 30) / 20) } ?? 1)
        var limiter = Limiter(ceiling: Float(pow(10, (voiceTarget + 15) / 20)), sampleRate: rate)
        var skipped = 0
        done = 0
        try read(processed) { data, count in
            let target = out.floatChannelData![0]
            var written = 0
            for i in 0..<count {
                let x = recipe.level ? limiter.process(data[i] * gain) : data[i]
                // The limiter's look-ahead delays the sound: drop its start.
                if recipe.level, skipped < limiter.lookahead {
                    skipped += 1
                    continue
                }
                target[written] = x
                written += 1
            }
            out.frameLength = AVAudioFrameCount(written)
            if written > 0 { try final.write(from: out) }
            done += AVAudioFramePosition(count)
            progress(recipe.level ? 0.5 + Double(done) / Double(total) * 0.5 : 1)
        }
        if recipe.level {
            let tail = limiter.flush()
            tail.withUnsafeBufferPointer { values in
                out.frameLength = AVAudioFrameCount(values.count)
                out.floatChannelData![0].update(from: values.baseAddress!, count: values.count)
            }
            try final.write(from: out)
        }
        try? FileManager.default.removeItem(at: middle)
    }
}
