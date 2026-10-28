import Foundation

/// Where a moving blur is at one moment: SOURCE seconds, and its box like
/// the effect's own (center, video-normalized, y down; on the camera
/// picture for a camera blur).
struct VideoOverlayMotionKey: Codable, Equatable {
    var time: Double
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

extension VideoDemoOverlayEffect {
    /// The box at a source moment: on its path between keys, held before
    /// the first and after the last.
    func placed(atSource time: Double) -> VideoDemoOverlayEffect {
        guard let motion, let first = motion.first else { return self }
        var placed = self
        func set(_ key: VideoOverlayMotionKey) {
            placed.x = key.x
            placed.y = key.y
            placed.width = key.width
            placed.height = key.height
        }
        guard time > first.time else { set(first); return placed }
        guard let after = motion.firstIndex(where: { $0.time >= time }) else { set(motion[motion.count - 1]); return placed }
        let b = motion[after]
        let a = motion[max(after - 1, 0)]
        let f = b.time > a.time ? (time - a.time) / (b.time - a.time) : 1
        set(VideoOverlayMotionKey(time: time, x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f, width: a.width + (b.width - a.width) * f, height: a.height + (b.height - a.height) * f))
        return placed
    }

    /// Moved, resized or slid along the timeline by hand: the whole path
    /// goes along (the effect's own box is its path's first key).
    mutating func followMove(from old: VideoDemoOverlayEffect) {
        guard var keys = motion, !keys.isEmpty else { return }
        let dx = x - old.x, dy = y - old.y
        let sw = old.width > 0 ? width / old.width : 1
        let sh = old.height > 0 ? height / old.height : 1
        let dt = time - old.time
        guard dx != 0 || dy != 0 || sw != 1 || sh != 1 || dt != 0 else { return }
        for index in keys.indices {
            keys[index].time += dt
            keys[index].x = min(max(keys[index].x + dx, 0), 1)
            keys[index].y = min(max(keys[index].y + dy, 0), 1)
            keys[index].width = min(max(keys[index].width * sw, 0.01), 1)
            keys[index].height = min(max(keys[index].height * sh, 0.01), 1)
        }
        motion = keys
    }
}
