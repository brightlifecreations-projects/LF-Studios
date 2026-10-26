import Accelerate
import AVFoundation

/// Lines up two recordings of the same moment by their sound: each
/// soundtrack becomes a loudness envelope, and the two are slid against
/// each other (an FFT cross-correlation) to find where they match best.
enum VideoAudioSync {
    /// Envelope samples per second (5 ms steps).
    static let envelopeRate = 200.0
    /// The sound read for the envelope (mono).
    static let readRate = 8000.0
    /// Below this the match is too weak to trust.
    static let minimumCorrelation = 0.35
    /// The best match has to stand out from the next best one by this much.
    static let minimumDistinctness = 0.12

    struct Match: Equatable {
        /// Seconds the second recording started after the first (negative:
        /// before). Second's time = first's time − offset.
        var offset: Double
        /// How alike the two envelopes are at that offset (0…1).
        var correlation: Double
        /// The best match's lead over the next best one (0…1).
        var distinctness: Double
    }

    enum Failure: Error, Equatable {
        /// One of them has no sound (or none worth matching).
        case noSound
        /// They don't share a sound clearly enough.
        case weakMatch(correlation: Double)
    }

    /// Where `other` sits against `reference`, within ±`maximumOffset`.
    static func match(reference: URL, other: URL, maximumOffset: Double = 600) async -> Result<Match, Failure> {
        async let first = envelope(of: reference)
        async let second = envelope(of: other)
        guard let a = await first, let b = await second else { return .failure(.noSound) }
        return await Task.detached(priority: .userInitiated) {
            match(reference: a, other: b, rate: envelopeRate, maximumOffset: maximumOffset)
        }.value
    }

    // MARK: Envelopes

    /// The soundtrack's loudness, `envelopeRate` times a second: log energy
    /// with its slow drift taken out, so two microphones at different
    /// levels and distances still look alike. nil without sound.
    static func envelope(of url: URL) async -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
        return await Task.detached(priority: .userInitiated) {
            monoSamples(of: track, in: asset).flatMap { envelope(samples: $0, sampleRate: readRate) }
        }.value
    }

    static func envelope(samples: [Float], sampleRate: Double) -> [Float]? {
        let hop = max(Int(sampleRate / envelopeRate), 1)
        let window = hop * 2
        let count = samples.count >= window ? (samples.count - window) / hop + 1 : 0
        guard count > 0 else { return nil }
        var energy = [Float](repeating: 0, count: count)
        samples.withUnsafeBufferPointer { buffer in
            for i in 0..<count {
                var square: Float = 0
                vDSP_svesq(buffer.baseAddress! + i * hop, 1, &square, vDSP_Length(window))
                energy[i] = log10(square / Float(window) + 1e-7)
            }
        }
        // A one-second running average, taken away: what's left is the
        // sound's shape over time.
        let span = max(Int(envelopeRate), 1)
        var sums = [Double](repeating: 0, count: count + 1)
        for i in 0..<count { sums[i + 1] = sums[i] + Double(energy[i]) }
        var shaped = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let lo = max(0, i - span / 2), hi = min(count, i + span / 2 + 1)
            shaped[i] = energy[i] - Float((sums[hi] - sums[lo]) / Double(hi - lo))
        }
        var mean: Float = 0, deviation: Float = 0
        vDSP_normalize(shaped, 1, &shaped, 1, &mean, &deviation, vDSP_Length(count))
        // Silence (or a steady hum) has nothing to line up.
        guard deviation.isFinite, deviation > 0.02 else { return nil }
        return shaped
    }

    /// The first soundtrack mixed to mono at `readRate`.
    private static func monoSamples(of track: AVAssetTrack, in asset: AVAsset) -> [Float]? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: readRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { bytes in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            samples += chunk
        }
        guard reader.status == .completed, !samples.isEmpty else { return nil }
        return samples
    }

    // MARK: Matching

    /// Slides `other` along `reference` (both from `envelope`) and keeps the
    /// offset where they agree most, read between steps for precision.
    static func match(reference a: [Float], other b: [Float], rate: Double, maximumOffset: Double) -> Result<Match, Failure> {
        guard !a.isEmpty, !b.isEmpty else { return .failure(.noSound) }
        // Lag k: other[i] lines up with reference[i + k].
        let correlation = crossCorrelation(a, b)
        // Each lag is scored over the part both cover, as a true
        // similarity (−1…1): energies from running sums of squares.
        func squares(_ x: [Float]) -> [Double] {
            var sums = [Double](repeating: 0, count: x.count + 1)
            for i in x.indices { sums[i + 1] = sums[i] + Double(x[i] * x[i]) }
            return sums
        }
        let sa = squares(a), sb = squares(b)
        // At least half the shorter one (and two seconds) must overlap, so
        // a lucky match of a few sounds at the edges never wins.
        let shorter = min(a.count, b.count)
        let minimumOverlap = min(max(Int(2 * rate), shorter / 2), shorter)
        let reach = Int(maximumOffset * rate)
        var scores: [(lag: Int, score: Double)] = []
        for lag in max(-(b.count - 1), -reach)...min(a.count - 1, reach) {
            let start = max(0, lag), end = min(a.count, b.count + lag)
            let overlap = end - start
            guard overlap >= minimumOverlap else { continue }
            let energy = (sa[end] - sa[start]) * (sb[end - lag] - sb[start - lag])
            scores.append((lag, energy > 0 ? Double(correlation(lag)) / energy.squareRoot() : 0))
        }
        guard let best = scores.max(by: { $0.score < $1.score }) else { return .failure(.noSound) }
        // The runner-up: the best score a quarter second or more away.
        let gap = Int(0.25 * rate)
        let runnerUp = scores.filter { abs($0.lag - best.lag) > gap }.map(\.score).max() ?? 0
        let distinctness = best.score > 0 ? (best.score - max(runnerUp, 0)) / best.score : 0
        guard best.score >= minimumCorrelation, distinctness >= minimumDistinctness else {
            return .failure(.weakMatch(correlation: max(best.score, 0)))
        }
        // A parabola through the peak and its neighbours: between steps.
        var lag = Double(best.lag)
        if let index = scores.firstIndex(where: { $0.lag == best.lag }), index > 0, index < scores.count - 1,
           scores[index - 1].lag == best.lag - 1, scores[index + 1].lag == best.lag + 1 {
            let l = scores[index - 1].score, c = scores[index].score, r = scores[index + 1].score
            let denominator = l - 2 * c + r
            if denominator < 0 { lag += min(max(0.5 * (l - r) / denominator, -0.5), 0.5) }
        }
        return .success(Match(offset: lag / rate, correlation: min(best.score, 1), distinctness: distinctness))
    }

    /// Σ a[i + k]·b[i] for every lag k, through one FFT each way.
    private static func crossCorrelation(_ a: [Float], _ b: [Float]) -> (Int) -> Float {
        let needed = a.count + b.count
        let log2n = vDSP_Length(ceil(log2(Double(needed))))
        let n = 1 << Int(log2n)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return { _ in 0 } }
        defer { vDSP_destroy_fftsetup(setup) }
        func spectrum(_ x: [Float]) -> ([Float], [Float]) {
            var padded = x + [Float](repeating: 0, count: n - x.count)
            var real = [Float](repeating: 0, count: n / 2), imaginary = [Float](repeating: 0, count: n / 2)
            real.withUnsafeMutableBufferPointer { r in
                imaginary.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    padded.withUnsafeBytes { bytes in
                        vDSP_ctoz(bytes.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
            padded.removeAll()
            return (real, imaginary)
        }
        let (ar, ai) = spectrum(a)
        let (br, bi) = spectrum(b)
        // A · conj(B). Packed format: index 0 holds DC (real) and Nyquist
        // (imaginary), each a plain product.
        var pr = [Float](repeating: 0, count: n / 2), pi = [Float](repeating: 0, count: n / 2)
        pr[0] = ar[0] * br[0]
        pi[0] = ai[0] * bi[0]
        for k in 1..<(n / 2) {
            pr[k] = ar[k] * br[k] + ai[k] * bi[k]
            pi[k] = ai[k] * br[k] - ar[k] * bi[k]
        }
        var result = [Float](repeating: 0, count: n)
        pr.withUnsafeMutableBufferPointer { r in
            pi.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                result.withUnsafeMutableBytes { bytes in
                    vDSP_ztoc(&split, 1, bytes.bindMemory(to: DSPComplex.self).baseAddress!, 2, vDSP_Length(n / 2))
                }
            }
        }
        // zrip scales each forward pass by 2 and the inverse by n.
        var scale = 1 / Float(4 * n)
        vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(n))
        return { lag in result[lag >= 0 ? lag : n + lag] }
    }
}
