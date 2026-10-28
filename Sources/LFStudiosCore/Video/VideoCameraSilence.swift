import Foundation

/// "Hide camera during silences": a "Camera hidden" block on the Camera
/// lane for every silence at least this long. The blocks fade like any
/// other, and can be dragged or deleted.
enum VideoCameraSilence {
    static let minimumRange: ClosedRange<Double> = 1...10
    static let defaultMinimum = 3.0
    /// Kept between the last word and the fade (and before the next word).
    static let margin = 0.2

    /// Silences (source seconds) at least `minimum` long, between `speech`
    /// stretches and at either end of `0…duration`.
    static func silences(speech: [ClosedRange<Double>], duration: Double, minimum: Double) -> [ClosedRange<Double>] {
        guard duration > 0 else { return [] }
        let minimum = min(max(minimum, minimumRange.lowerBound), minimumRange.upperBound)
        // No speech at all is a silent recording, not a long pause.
        let sorted = speech.sorted { $0.lowerBound < $1.lowerBound }
        guard !sorted.isEmpty else { return [] }
        var gaps: [ClosedRange<Double>] = []
        var cursor = 0.0
        for range in sorted {
            if range.lowerBound - cursor >= minimum { gaps.append(cursor...range.lowerBound) }
            cursor = max(cursor, range.upperBound)
        }
        if duration - cursor >= minimum { gaps.append(cursor...duration) }
        return gaps
    }

    /// The hidden blocks for those silences, away from blocks the user
    /// placed (source seconds).
    static func blocks(silences: [ClosedRange<Double>], keeping others: [VideoCameraLayoutRegion]) -> [VideoCameraLayoutRegion] {
        silences.compactMap { silence in
            let start = silence.lowerBound + (silence.lowerBound > 0.001 ? margin : 0)
            let end = silence.upperBound - margin
            guard end - start >= VideoCameraLayoutRegion.minimumDuration,
                  !others.contains(where: { $0.start < end && $0.end > start }) else { return nil }
            return VideoCameraLayoutRegion(start: start, end: end, layout: .hidden, isSilence: true)
        }
    }
}

extension VideoDemoProject {
    /// Replaces the earlier silence blocks with new ones; returns how many.
    @discardableResult
    mutating func hideCameraDuringSilences(speech: [ClosedRange<Double>], duration: Double, minimum: Double) -> Int {
        cameraLayouts.removeAll(where: \.isSilence)
        let silences = VideoCameraSilence.silences(speech: speech, duration: duration, minimum: minimum)
        let blocks = VideoCameraSilence.blocks(silences: silences, keeping: cameraLayouts)
        cameraLayouts.append(contentsOf: blocks)
        cameraLayouts.sort { $0.start < $1.start }
        if !blocks.isEmpty { webcam.visible = true }
        return blocks.count
    }
}
