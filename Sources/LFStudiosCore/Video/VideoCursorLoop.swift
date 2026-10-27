import CoreGraphics
import Foundation

/// Cursor ▸ Return to start at the end: over the video's last moments the
/// drawn pointer glides back to where it was on the first frame (its
/// place, its shape, whether it shows), so a looping video has no jump.
struct VideoCursorLoop {
    /// Timeline seconds the glide starts and ends. It ends just before the
    /// video's end, so the last frame at any frame rate is the first one's.
    let start: Double
    let end: Double
    /// The pointer on the first frame (video-normalized, y down).
    let firstPosition: CGPoint
    let firstAlpha: Double
    /// Source time of the first frame, for its pointer shape.
    let firstSourceTime: Double

    /// The last frame comes at most this long before the end (20 fps or more).
    static let lastFrameMargin = 0.05

    init?(settings: VideoCursorSettings, track: VideoCursorTrack?, timelineDuration: Double, firstSourceTime: Double) {
        guard settings.returnToStart, let track, timelineDuration > 0.2 else { return nil }
        let length = min(
            max(settings.returnDuration, VideoCursorSettings.returnDurationRange.lowerBound),
            VideoCursorSettings.returnDurationRange.upperBound,
            timelineDuration / 2
        )
        end = max(timelineDuration - Self.lastFrameMargin, 0)
        start = max(end - length, 0)
        firstPosition = track.position(at: firstSourceTime)
        firstAlpha = track.alpha(at: firstSourceTime)
        self.firstSourceTime = firstSourceTime
    }

    /// 0 until the glide starts, 1 from its end on; eased both ways.
    func weight(at timelineTime: Double) -> Double {
        guard timelineTime > start else { return 0 }
        guard timelineTime < end, end > start else { return 1 }
        let t = (timelineTime - start) / (end - start)
        // Smootherstep: no jolt as it sets off or arrives.
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    func position(_ recorded: CGPoint, at timelineTime: Double) -> CGPoint {
        let w = weight(at: timelineTime)
        guard w > 0 else { return recorded }
        return CGPoint(
            x: recorded.x + (firstPosition.x - recorded.x) * w,
            y: recorded.y + (firstPosition.y - recorded.y) * w
        )
    }

    func alpha(_ recorded: Double, at timelineTime: Double) -> Double {
        let w = weight(at: timelineTime)
        return recorded + (firstAlpha - recorded) * w
    }

    /// Past halfway the pointer takes the first frame's shape.
    func shapeSourceTime(_ sourceTime: Double, at timelineTime: Double) -> Double {
        weight(at: timelineTime) >= 0.5 ? firstSourceTime : sourceTime
    }
}
