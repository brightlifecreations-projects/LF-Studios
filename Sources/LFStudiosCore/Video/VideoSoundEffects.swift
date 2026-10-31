import AVFoundation
import SwiftUI

// MARK: - Library ▸ Audio ▸ Sound effects (1.15.0)

/// Our own sound effects, made here from sine waves and noise (no
/// recordings from anyone else). See LICENSES.md.
enum VideoSoundEffect: String, CaseIterable, Identifiable {
    case whoosh, riser, pop, click, ding, success, error, notification, boom, kick, clap, shutter, typing, coin, zap, heartbeat, tick

    var id: String { rawValue }
    var title: String {
        switch self {
        case .whoosh: return L("Whoosh")
        case .riser: return L("Riser")
        case .pop: return L("Pop")
        case .click: return L("Click")
        case .ding: return L("Ding")
        case .success: return L("Success")
        case .error: return L("Error")
        case .notification: return L("Notification")
        case .boom: return L("Boom")
        case .kick: return L("Kick drum")
        case .clap: return L("Clap")
        case .shutter: return L("Camera shutter")
        case .typing: return L("Typing")
        case .coin: return L("Coin")
        case .zap: return L("Zap")
        case .heartbeat: return L("Heartbeat")
        case .tick: return L("Clock tick")
        }
    }
    var section: String {
        switch self {
        case .whoosh, .riser, .boom, .zap: return L("Transitions")
        case .pop, .click, .ding, .success, .error, .notification, .coin: return L("Interface")
        case .kick, .clap, .heartbeat, .tick: return L("Rhythm")
        case .shutter, .typing: return L("Everyday")
        }
    }
    var keywords: [String] {
        switch self {
        case .whoosh: return ["swoosh", "swish", "transition"]
        case .riser: return ["build", "tension", "sweep"]
        case .pop: return ["bubble", "appear"]
        case .click: return ["mouse", "button"]
        case .ding: return ["bell"]
        case .success: return ["chime", "done", "win"]
        case .error: return ["buzz", "wrong"]
        case .notification: return ["ping", "alert"]
        case .boom: return ["impact", "hit", "explosion"]
        case .kick: return ["drum", "beat", "bass"]
        case .clap: return ["snare", "hand"]
        case .shutter: return ["photo", "camera"]
        case .typing: return ["keyboard", "keys"]
        case .coin: return ["game", "money"]
        case .zap: return ["laser", "electric"]
        case .heartbeat: return ["pulse"]
        case .tick: return ["clock", "time", "wood"]
        }
    }

    static let sampleRate = 48_000.0

    /// The sound, mono, at 48 kHz (the same every time).
    func samples() -> [Float] {
        let rate = Self.sampleRate
        func buffer(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * rate)) }
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15 &+ UInt64(rawValue.hashStable)
        func noise() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 20_001) / 10_000 - 1
        }
        /// A tone sweeping from `f0` to `f1` with an exponential fade.
        func tone(_ out: inout [Float], at start: Double, length: Double, f0: Double, f1: Double, decay: Double, gain: Double, square: Bool = false) {
            var phase = 0.0
            let first = Int(start * rate), count = Int(length * rate)
            for i in 0..<count where first + i < out.count {
                let t = Double(i) / rate
                let f = f0 * pow(f1 / f0, t / max(length, 0.001))
                phase += 2 * .pi * f / rate
                let wave = square ? (sin(phase) >= 0 ? 0.6 : -0.6) : sin(phase)
                let attack = min(t / 0.004, 1)
                out[first + i] += Float(wave * exp(-t * decay) * attack * gain)
            }
        }
        /// Noise through a one-pole low-pass sweeping `c0`…`c1` (0…1).
        func hiss(_ out: inout [Float], at start: Double, length: Double, c0: Double, c1: Double, gain: Double, envelope: (Double) -> Double) {
            var low = 0.0
            let first = Int(start * rate), count = Int(length * rate)
            for i in 0..<count where first + i < out.count {
                let p = Double(i) / Double(max(count, 1))
                let c = c0 + (c1 - c0) * p
                low += (noise() - low) * c
                out[first + i] += Float(low * envelope(p) * gain)
            }
        }
        var out: [Float]
        switch self {
        case .whoosh:
            out = buffer(0.9)
            hiss(&out, at: 0, length: 0.9, c0: 0.05, c1: 0.4, gain: 0.9) { p in sin(p * .pi) * sin(p * .pi) }
        case .riser:
            out = buffer(1.6)
            hiss(&out, at: 0, length: 1.6, c0: 0.02, c1: 0.5, gain: 0.5) { p in p * p }
            tone(&out, at: 0, length: 1.6, f0: 200, f1: 1200, decay: -1.2, gain: 0.08)
        case .pop:
            out = buffer(0.15)
            tone(&out, at: 0, length: 0.15, f0: 700, f1: 160, decay: 30, gain: 0.8)
        case .click:
            out = buffer(0.06)
            hiss(&out, at: 0, length: 0.006, c0: 0.9, c1: 0.9, gain: 0.7) { p in 1 - p }
            tone(&out, at: 0, length: 0.06, f0: 2200, f1: 1800, decay: 90, gain: 0.35)
        case .ding:
            out = buffer(1.4)
            for (ratio, gain) in [(1.0, 0.45), (2.76, 0.18), (5.4, 0.08)] {
                tone(&out, at: 0, length: 1.4, f0: 880 * ratio, f1: 880 * ratio, decay: 3 + ratio, gain: gain)
            }
        case .success:
            out = buffer(0.9)
            for (i, f) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
                tone(&out, at: Double(i) * 0.1, length: 0.6, f0: f, f1: f, decay: 6, gain: 0.3)
            }
        case .error:
            out = buffer(0.5)
            tone(&out, at: 0, length: 0.18, f0: 160, f1: 150, decay: 2, gain: 0.35, square: true)
            tone(&out, at: 0.25, length: 0.2, f0: 150, f1: 140, decay: 2, gain: 0.35, square: true)
        case .notification:
            out = buffer(0.6)
            tone(&out, at: 0, length: 0.3, f0: 1318.5, f1: 1318.5, decay: 9, gain: 0.35)
            tone(&out, at: 0.12, length: 0.45, f0: 1760, f1: 1760, decay: 8, gain: 0.35)
        case .boom:
            out = buffer(1.5)
            tone(&out, at: 0, length: 1.5, f0: 70, f1: 32, decay: 2.6, gain: 0.95)
            hiss(&out, at: 0, length: 0.5, c0: 0.12, c1: 0.02, gain: 0.8) { p in pow(1 - p, 2) }
        case .kick:
            out = buffer(0.4)
            tone(&out, at: 0, length: 0.4, f0: 130, f1: 45, decay: 9, gain: 0.95)
        case .clap:
            out = buffer(0.3)
            for d in [0.0, 0.012, 0.024] { hiss(&out, at: d, length: 0.25, c0: 0.6, c1: 0.4, gain: 0.45) { p in exp(-p * 9) } }
        case .shutter:
            out = buffer(0.3)
            hiss(&out, at: 0, length: 0.05, c0: 0.7, c1: 0.5, gain: 0.7) { p in 1 - p }
            hiss(&out, at: 0.11, length: 0.07, c0: 0.6, c1: 0.4, gain: 0.6) { p in 1 - p }
            tone(&out, at: 0.11, length: 0.06, f0: 1400, f1: 900, decay: 50, gain: 0.2)
        case .typing:
            out = buffer(1.4)
            var t = 0.05
            for i in 0..<9 {
                hiss(&out, at: t, length: 0.02, c0: 0.8, c1: 0.6, gain: 0.5) { p in 1 - p }
                tone(&out, at: t, length: 0.03, f0: 1500 + 300 * VideoEffectRenderer.random(i, 7), f1: 1200, decay: 120, gain: 0.2)
                t += 0.09 + 0.08 * VideoEffectRenderer.random(i, 9)
            }
        case .coin:
            out = buffer(0.5)
            tone(&out, at: 0, length: 0.08, f0: 987.8, f1: 987.8, decay: 1, gain: 0.25, square: true)
            tone(&out, at: 0.08, length: 0.4, f0: 1318.5, f1: 1318.5, decay: 6, gain: 0.25, square: true)
        case .zap:
            out = buffer(0.35)
            tone(&out, at: 0, length: 0.35, f0: 2400, f1: 180, decay: 6, gain: 0.45, square: true)
        case .heartbeat:
            out = buffer(1.1)
            tone(&out, at: 0, length: 0.25, f0: 90, f1: 50, decay: 14, gain: 0.95)
            tone(&out, at: 0.22, length: 0.25, f0: 80, f1: 45, decay: 14, gain: 0.7)
        case .tick:
            out = buffer(2)
            for i in 0..<4 { tone(&out, at: Double(i) * 0.5, length: 0.05, f0: i % 2 == 0 ? 1900 : 1600, f1: 1500, decay: 110, gain: 0.5) }
        }
        // No clicks at the ends; never louder than −1 dBFS.
        let peak = out.map(abs).max() ?? 0
        let limit: Float = 0.89
        let scale = peak > limit ? limit / peak : 1
        let edge = min(Int(0.003 * rate), out.count / 2)
        for i in out.indices {
            var v = out[i] * scale
            if i >= out.count - edge { v *= Float(out.count - i) / Float(max(edge, 1)) }
            out[i] = v
        }
        return out
    }

    var length: Double { Double(samples().count) / Self.sampleRate }

    /// The sound as a file (made once, kept with the app's data).
    func fileURL() throws -> URL {
        let folder = VideoStorageLocation.root
            .appendingPathComponent("LF Studios", isDirectory: true)
            .appendingPathComponent("SoundEffects", isDirectory: true)
            .appendingPathComponent("v1-\(rawValue)", isDirectory: true)
        let url = folder.appendingPathComponent("\(title).caf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        let samples = samples()
        let partial = folder.appendingPathComponent("making.caf")
        try? FileManager.default.removeItem(at: partial)
        do {
            let file = try AVAudioFile(forWriting: partial, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            try file.write(from: buffer)
        }
        try FileManager.default.moveItem(at: partial, to: url)
        return url
    }
}

private extension String {
    /// The same number on every Mac and every launch (unlike hashValue).
    var hashStable: Int {
        unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) } & 0x7fff_ffff
    }
}

extension VideoEditorModel {
    /// A sound effect as its own sound track at `time` (nil: the playhead).
    @discardableResult
    func addSoundEffect(_ effect: VideoSoundEffect, at time: Double?) async -> UUID? {
        do {
            let url = try effect.fileURL()
            return await addAudio([url], at: time ?? clock.time).first
        } catch {
            showNotice(L("Couldn't make that sound: \(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill")
            return nil
        }
    }
}

/// Plays a sound effect while its tile is hovered.
@MainActor
enum VideoSoundEffectPreviewPlayer {
    private static var player: AVAudioPlayer?
    private static var pending: DispatchWorkItem?

    static func hover(_ effect: VideoSoundEffect?) {
        pending?.cancel()
        player?.stop()
        guard let effect else { return }
        let work = DispatchWorkItem {
            guard let url = try? effect.fileURL(), let next = try? AVAudioPlayer(contentsOf: url) else { return }
            player = next
            next.volume = 0.8
            next.play()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

// MARK: - Library ▸ Audio

struct VideoAudioLibraryTab: View {
    @ObservedObject var model: VideoEditorModel
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            VideoSegmented(options: [(0, L("Your sounds")), (1, L("Sound effects"))], selection: $page)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            if page == 0 {
                VideoMediaBinView(model: model, kinds: [.audio])
            } else {
                VideoLibraryGrid(model: model, tiles: VideoSoundEffect.allCases.map {
                    VideoLibraryTile(payload: .init(kind: "sound", id: $0.rawValue), title: $0.title, keywords: $0.keywords, section: $0.section)
                }, minimum: 84, tileHeight: 40) {
                    Text(L("Our own sound effects, free to use in anything you make. Hover to listen; drag one onto the timeline or click +."))
                        .font(.system(size: 11))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } preview: { tile, hovering in
                    VideoSoundEffectTile(effect: VideoSoundEffect(rawValue: tile.payload.id) ?? .click, hovering: hovering)
                }
            }
        }
    }
}

struct VideoSoundEffectTile: View {
    let effect: VideoSoundEffect
    let hovering: Bool

    var body: some View {
        ZStack {
            VideoEditorTheme.well
            HStack(spacing: 1.5) {
                ForEach(Array(Self.bars(effect).enumerated()), id: \.offset) { _, level in
                    Capsule().fill(hovering ? VideoEditorTheme.layer : VideoEditorTheme.textTertiary).frame(width: 2.5, height: max(CGFloat(level) * 30, 2))
                }
            }
        }
        .onChange(of: hovering) { on in VideoSoundEffectPreviewPlayer.hover(on ? effect : nil) }
    }

    private static var cache: [VideoSoundEffect: [Float]] = [:]

    /// 24 bars of loudness.
    @MainActor
    static func bars(_ effect: VideoSoundEffect) -> [Float] {
        if let cached = cache[effect] { return cached }
        let samples = effect.samples()
        let size = max(samples.count / 24, 1)
        let bars = (0..<24).map { i -> Float in
            let slice = samples[min(i * size, samples.count)..<min((i + 1) * size, samples.count)]
            return min((slice.map(abs).max() ?? 0) * 1.1, 1)
        }
        cache[effect] = bars
        return bars
    }
}
