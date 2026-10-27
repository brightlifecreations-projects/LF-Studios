import CoreGraphics
import Foundation

// MARK: - Where the text cursor was

/// The text cursor's path from "Track where I type", looked up by source
/// time. Between readings it holds where it last was.
final class VideoTypingTrack: @unchecked Sendable {
    /// A text cursor this long without moving no longer counts.
    static let hold = 4.0

    let samples: [VideoTextCursorSample]
    private let times: [Double]

    init?(samples: [VideoTextCursorSample]) {
        guard !samples.isEmpty else { return nil }
        self.samples = samples.sorted { $0.time < $1.time }
        times = self.samples.map(\.time)
    }

    /// The text cursor's middle (video-normalized, y down); nil when it
    /// wasn't seen near `time`.
    func position(at time: Double) -> CGPoint? {
        guard let first = times.first else { return nil }
        if time < first {
            return first - time <= 1 ? samples[0].center : nil
        }
        var low = 0
        var high = times.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if times[mid] <= time { low = mid } else { high = mid - 1 }
        }
        return time - times[low] <= Self.hold ? samples[low].center : nil
    }
}

// MARK: - Typing stretches

/// A stretch of typing, in source seconds.
struct VideoTypingStretch: Equatable {
    var start: Double
    var end: Double

    var duration: Double { max(end - start, 0) }
}

enum VideoTypingDetector {
    /// Where the stretches came from — an estimate says so.
    enum Basis: Equatable {
        case keyTiming
        case textCursor
        case estimate
    }

    struct Tuning {
        /// Presses (or text cursor moves) further apart end a stretch.
        var gap = 1.0
        var minimumCount = 4
        var minimumDuration = 1.0
    }

    /// Runs of key presses close together.
    static func stretches(keyPresses: [Double], tuning: Tuning = Tuning()) -> [VideoTypingStretch] {
        runs(of: keyPresses.sorted(), gap: tuning.gap).compactMap { run in
            guard run.count >= tuning.minimumCount, let first = run.first, let last = run.last,
                  last - first >= tuning.minimumDuration else { return nil }
            // The last key's character appears a moment after it goes down.
            return VideoTypingStretch(start: first, end: last + 0.12)
        }
    }

    /// Runs of small text cursor moves (each typed character moves it a
    /// little; a jump to another field starts a new run).
    static func stretches(textCursor: [VideoTextCursorSample], tuning: Tuning = Tuning()) -> [VideoTypingStretch] {
        let sorted = textCursor.sorted { $0.time < $1.time }
        var result: [VideoTypingStretch] = []
        var run: [VideoTextCursorSample] = []
        func close() {
            defer { run.removeAll() }
            guard run.count >= tuning.minimumCount, let first = run.first, let last = run.last,
                  last.time - first.time >= tuning.minimumDuration else { return }
            result.append(VideoTypingStretch(start: first.time, end: last.time + 0.12))
        }
        for sample in sorted {
            if let last = run.last {
                let jump = hypot(sample.center.x - last.center.x, sample.center.y - last.center.y)
                if sample.time - last.time > tuning.gap || jump > 0.25 { close() }
            }
            run.append(sample)
        }
        close()
        return result
    }

    /// Older recordings saved only WHEN the screen changed, not where, and
    /// nothing about the text cursor — so typing is guessed: the screen
    /// changing in a steady rhythm while the pointer holds still and
    /// nothing is clicked. Over a text field (the I-beam) a shorter run
    /// counts.
    static func estimatedStretches(
        screenActivity: [Double],
        cursorSamples: [VideoDemoCursorSample],
        clicks: [VideoDemoClickEvent],
        isTextPointer: (Double) -> Bool = { _ in false }
    ) -> [VideoTypingStretch] {
        let sortedSamples = cursorSamples.sorted { $0.time < $1.time }
        func pointerTravel(_ start: Double, _ end: Double) -> Double {
            var travel = 0.0
            var previous: VideoDemoCursorSample?
            for sample in sortedSamples where sample.time >= start - 0.05 && sample.time <= end + 0.05 {
                if let previous { travel += hypot(sample.x - previous.x, sample.y - previous.y) }
                previous = sample
            }
            return travel
        }
        var result: [VideoTypingStretch] = []
        for run in runs(of: screenActivity.sorted(), gap: 0.6) {
            guard let first = run.first, let last = run.last else { continue }
            let duration = last - first
            // Typing changes the screen a few times a second, not every frame.
            let rate = Double(run.count) / max(duration, 0.001)
            guard run.count >= 6, rate >= 2.5 else { continue }
            let onText = isTextPointer((first + last) / 2)
            guard duration >= (onText ? 1.2 : 2.0) else { continue }
            guard !clicks.contains(where: { $0.time >= first - 0.2 && $0.time <= last }) else { continue }
            guard pointerTravel(first, last) < 0.02 else { continue }
            result.append(VideoTypingStretch(start: first, end: last + 0.1))
        }
        return result
    }

    /// The stretches for a project, from the best data it has.
    static func stretches(project: VideoDemoProject, screenActivity: [Double]?, isTextPointer: (Double) -> Bool = { _ in false }) -> (stretches: [VideoTypingStretch], basis: Basis)? {
        if !project.keyPresses.isEmpty {
            return (stretches(keyPresses: project.keyPresses), .keyTiming)
        }
        if !project.textCursor.isEmpty {
            return (stretches(textCursor: project.textCursor), .textCursor)
        }
        guard let screenActivity, !screenActivity.isEmpty else { return nil }
        return (estimatedStretches(screenActivity: screenActivity, cursorSamples: project.cursorSamples, clicks: project.clickEvents, isTextPointer: isTextPointer), .estimate)
    }

    private static func runs(of times: [Double], gap: Double) -> [[Double]] {
        var runs: [[Double]] = []
        for time in times {
            if let last = runs.last?.last, time - last <= gap {
                runs[runs.count - 1].append(time)
            } else {
                runs.append([time])
            }
        }
        return runs
    }
}

// MARK: - Typing zooms

enum VideoTypingZoomPlanner {
    /// Zooms that follow the text cursor through each stretch of typing.
    static func regions(project: VideoDemoProject, totalDuration: Double) -> [VideoZoomRegion] {
        guard let track = VideoTypingTrack(samples: project.textCursor) else { return [] }
        var stretches = VideoTypingDetector.stretches(textCursor: project.textCursor)
        if !project.keyPresses.isEmpty {
            // Key timing is sharper; keep the runs where the text cursor was seen.
            stretches = VideoTypingDetector.stretches(keyPresses: project.keyPresses).filter { track.position(at: $0.start) != nil }
        }
        let scale = project.defaultZoomScale
        let lead = VideoCameraTrack.transitionDuration(scale: scale, speed: project.zoomSpeed) + 0.2
        var regions: [VideoZoomRegion] = []
        for stretch in stretches {
            let start = max(stretch.start - lead, 0)
            let end = min(stretch.end + 0.8, totalDuration > 0 ? totalDuration : stretch.end + 0.8)
            guard end - start >= VideoZoomRegion.minimumDuration else { continue }
            if var last = regions.last, start <= last.end + 0.3 {
                last.end = max(last.end, end)
                regions[regions.count - 1] = last
                continue
            }
            let focus = track.position(at: stretch.start) ?? CGPoint(x: 0.5, y: 0.5)
            var region = VideoZoomRegion(start: start, end: end, scale: scale, followsCursor: false, focusX: Double(focus.x), focusY: Double(focus.y))
            region.followsTyping = true
            region.isTyping = true
            regions.append(region)
        }
        return regions
    }
}

extension VideoDemoProject {
    /// "Add typing zooms": replaces the earlier ones; returns how many.
    @discardableResult
    mutating func addTypingZooms(totalDuration: Double) -> Int {
        let regions = VideoTypingZoomPlanner.regions(project: self, totalDuration: totalDuration)
        zoomRegions.removeAll { $0.isTyping }
        zoomRegions.append(contentsOf: regions)
        zoomRegions.sort { $0.start < $1.start }
        return regions.count
    }
}

// MARK: - Speeding up typing

extension VideoDemoProject {
    static let typingSpeeds: [Double] = [2, 3, 4, 6, 8]

    struct TypingSpeedUp: Equatable {
        var stretches = 0
        /// Seconds the edited video got shorter.
        var saved = 0.0
    }

    /// "Speed up typing": each stretch becomes a clip of its own playing at
    /// `speed`. Clips it sped up before take the new speed; clips the user
    /// set to another speed are left alone.
    @discardableResult
    mutating func speedUpTyping(_ stretches: [VideoTypingStretch], speed: Double, totalDuration: Double) -> TypingSpeedUp {
        timelineClips = normalizedTimelineClips(totalDuration: totalDuration)
        let before = timelineDuration(totalDuration: totalDuration)
        var result = TypingSpeedUp()
        let speed = min(max(speed, Self.typingSpeeds[0]), Self.typingSpeeds[Self.typingSpeeds.count - 1])
        for index in timelineClips.indices where timelineClips[index].typingSpeedUp {
            timelineClips[index].speed = speed
        }
        for stretch in stretches where stretch.duration >= 0.6 {
            // Only typing still at normal speed.
            let covering = timelineClips.filter { $0.sourceStart < stretch.end && $0.sourceEnd > stretch.start }
            guard !covering.isEmpty, covering.allSatisfy({ abs($0.normalizedSpeed - 1) < 0.001 && !$0.typingSpeedUp }) else { continue }
            _ = splitClip(atSourceTime: stretch.start, totalDuration: totalDuration)
            _ = splitClip(atSourceTime: stretch.end, totalDuration: totalDuration)
            var changed = false
            for index in timelineClips.indices {
                let clip = timelineClips[index]
                // (A stretch this close to a clip's edge isn't split there.)
                let slack = Self.minimumClipDuration + 0.001
                guard clip.sourceStart >= stretch.start - slack, clip.sourceEnd <= stretch.end + slack,
                      clip.sourceStart < stretch.end, clip.sourceEnd > stretch.start else { continue }
                timelineClips[index].speed = speed
                timelineClips[index].typingSpeedUp = true
                changed = true
            }
            if changed { result.stretches += 1 }
        }
        result.saved = max(before - timelineDuration(totalDuration: totalDuration), 0)
        return result
    }
}
