import AppKit
import AVFoundation
import SwiftUI

/// Time on the timeline and in the recording, the timeline's scale, and playing and seeking.
extension VideoEditorModel {
    // MARK: Time mapping

    /// The clips plus the intro and outro cards.
    var timelineDuration: Double { project.outputDuration(segments: segments) }

    func sourceTime(forTimeline time: Double) -> Double {
        VideoDemoProject.sourceTime(forTimelineTime: time, segments: segments)
    }

    /// A timeline window as a stretch of the recording: from where `start`
    /// plays (on a cut, the clip after it), on through the clips that follow
    /// it in the recording's own order. A clip moved out of order ends it —
    /// otherwise the stretch would run backwards or over other clips.
    func sourceWindow(timelineStart: Double, timelineEnd: Double) -> ClosedRange<Double> {
        let segments = self.segments
        guard let first = segments.first, let last = segments.last else { return timelineStart...max(timelineEnd, timelineStart) }
        let start = min(max(timelineStart, first.timelineStart), last.timelineEnd)
        let end = max(timelineEnd, start)
        var index = segments.firstIndex { start >= $0.timelineStart - 0.0005 && start < $0.timelineEnd - 0.0005 } ?? (segments.count - 1)
        let sourceStart = segments[index].sourceTime(forTimelineTime: start)
        while index + 1 < segments.count, end > segments[index].timelineEnd + 0.0005,
              segments[index + 1].clip.sourceStart >= segments[index].clip.sourceEnd - 0.0005 {
            index += 1
        }
        let sourceEnd = segments[index].sourceTime(forTimelineTime: min(end, segments[index].timelineEnd))
        return sourceStart...max(sourceEnd, sourceStart)
    }

    /// The whole recording the timeline uses, whatever order its clips are in.
    var sourceSpanOnTimeline: ClosedRange<Double>? {
        guard let start = segments.map(\.clip.sourceStart).min(), let end = segments.map(\.clip.sourceEnd).max() else { return nil }
        return start...max(end, start)
    }

    /// The moment of the recording something new at the playhead starts
    /// from. On a cut that's the frame after it — the one on screen — not
    /// the last frame of the material before it.
    func placementSourceTime(forTimeline time: Double) -> Double {
        if let next = segments.first(where: { abs($0.timelineStart - time) < 0.001 }) {
            return next.clip.sourceStart
        }
        return sourceTime(forTimeline: time)
    }

    func timelineTime(forSource time: Double) -> Double? {
        segment(containingSource: time)?.timelineTime(forSourceTime: time)
    }

    /// The clip that plays this moment of the recording (binary search; the
    /// first in timeline order where two clips meet).
    func segment(containingSource time: Double) -> VideoDemoTimelineSegment? {
        let sorted = segmentsBySource
        var low = 0
        var high = sorted.count
        // First clip that ends at or after `time`.
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid].clip.sourceEnd < time { low = mid + 1 } else { high = mid }
        }
        var found: VideoDemoTimelineSegment?
        var index = low
        while index < sorted.count, sorted[index].clip.sourceStart <= time {
            if sorted[index].contains(sourceTime: time), found.map({ sorted[index].timelineStart < $0.timelineStart }) ?? true {
                found = sorted[index]
            }
            index += 1
        }
        return found
    }

    func segment(atTimeline time: Double) -> VideoDemoTimelineSegment? {
        segments.first { time >= $0.timelineStart - 0.0001 && time <= $0.timelineEnd + 0.0001 }
    }

    /// Camera at a timeline moment (for preview handles).
    func cameraState(at time: Double) -> VideoCameraState {
        plan.camera.state(at: time)
    }

    // MARK: Timeline scale

    /// Zoomed all the way in, a second is 150 points on any length of
    /// recording (a 30-minute take can be trimmed frame by frame too).
    var maxTimelineZoom: Double {
        max(40, timelineDuration * 150 / Double(max(timelineViewportWidth, 100)))
    }

    /// = / − and the buttons: in or out around the skimmer, else the
    /// playhead (VideoTimelineScroller.anchor).
    func zoomTimeline(by factor: Double) {
        timelineZoom = min(max(timelineZoom * factor, 1), maxTimelineZoom)
    }

    // MARK: Transport

    func togglePlay() {
        shuttleRate = 1
        if isPlaying {
            playback.pause()
        } else {
            if case .zoom = selection, isAimingZoom { selection = .none }
            loopStartIfNeeded()
            playback.play()
        }
    }

    func pause() {
        playback.pause()
    }

    func seek(to time: Double, fast: Bool = false) {
        let target = min(max(time, 0), timelineDuration)
        previewAxisTime = nil
        clock.time = target
        if !fast { VideoRenderWarmup.warm(project, from: target, height: 1080) }
        // Fast seeks come while the playhead is dragged; the exact one on
        // release ends it.
        isScrubbing = fast
        updatePreviewQuality()
        playback.seek(to: target, fast: fast)
        previewRenderer.invalidate()
    }

    /// 4K and bigger recordings.
    var hasLargeSource: Bool { project.sourceWidth * project.sourceHeight >= 3840 * 2160 * 0.9 }

    /// While a big recording plays or scrubs, the preview draws in draft
    /// quality from smaller frames; the paused frame is full quality.
    var previewPrefersSpeed: Bool { hasLargeSource && (isPlaying || isScrubbing) }

    func updatePreviewQuality() {
        playback.setUsesSmallFrames(previewPrefersSpeed)
    }

    func step(frames: Int) {
        playback.pause()
        seek(to: clock.time + Double(frames) / max(sourceFrameRate, 24))
    }

    func jump(by seconds: Double) {
        seek(to: clock.time + seconds)
    }

    /// L in J/K/L: play, then 2x, 4x on repeated presses.
    func shuttleForward() {
        if isPlaying {
            shuttleRate = min(shuttleRate * 2, 4)
            playback.setRate(shuttleRate)
            showNotice(L("Playing \(Int(shuttleRate))×"), symbol: "forward.fill")
        } else {
            playback.play()
        }
    }

    /// J: step back a second (reverse playback of long-GOP video is choppy).
    func shuttleBackward() {
        playback.pause()
        jump(by: -1)
    }
}
