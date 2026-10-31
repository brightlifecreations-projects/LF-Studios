import AVFoundation
import CoreImage

// MARK: - Video tracks above the main track (1.14.0)

/// A video or a picture on a track above the main track, on the
/// timeline's own clock (it doesn't follow the recording's cuts, like an
/// added sound file).
struct VideoLayerItem: Codable, Equatable, Identifiable {
    var id = UUID()
    /// A video or a picture.
    var kind: VideoMediaKind
    var path: String
    var name: String
    /// Where it starts on the timeline, and for how long it plays.
    var at: Double
    var length: Double
    /// A video's own seconds where it starts, and how fast it plays.
    var fileStart: Double = 0
    var speed: Double = 1
    /// A video's whole length (trimming stops there; 0 for a picture).
    var fileDuration: Double = 0
    /// Width / height of the media, upright.
    var aspect: Double
    /// Its middle in the frame (0…1 from the top left) and its width as a
    /// share of the frame's width.
    var x = 0.5
    var y = 0.5
    var width = 0.4
    /// Degrees clockwise.
    var rotation = 0.0
    /// Flipped left to right.
    var mirrored = false
    var opacity = 1.0
    /// What's kept of the media (nil: all of it).
    var crop: VideoCropRect?
    /// Off (V): kept on the timeline, not drawn or heard.
    var enabled = true
    /// A video's sound.
    var volume = 1.0
    var muted = false
    /// Grouped items (⌘G) move and delete together.
    var group: UUID?
    // 1.15.0 (all optional: 1.14.0's files read as they are).
    /// Animated properties (VideoKeyframes.swift).
    var keys: VideoKeyframes?
    /// A shape that shows (or hides) part of it (VideoMasks.swift).
    var mask: VideoMask?
    /// An effect's or a filter's strength, 0…1 (nil: full).
    var level: Double?
    /// How it mixes with what's under it (nil: normal).
    var blend: VideoBlendMode?
    /// Cutout: just the person (Vision), or a colour taken out.
    var removesBackground: Bool?
    var chroma: VideoChromaKey?
    /// In, Out and Combo animations (VideoAnimations.swift).
    var animation: VideoItemAnimation?
    /// Keep pitch off: faster sounds higher (nil: kept).
    var keepsPitch: Bool?
    /// A video's sound fading in and out at its ends (seconds).
    var soundFadeIn: Double?
    var soundFadeOut: Double?
    /// A text clip's words and look (VideoTextClips.swift); no file then.
    var text: VideoTextContent?
    /// Follows something in the video (VideoMotionTracking.swift).
    var tracking: VideoMotionTrack?

    var intensity: Double {
        get { level ?? 1 }
        set { level = abs(newValue - 1) < 0.0005 ? nil : min(max(newValue, 0), 1) }
    }

    static let speedRange: ClosedRange<Double> = 0.1...100
    static let minimumLength = 0.1
    /// A picture's length when it's placed.
    static let pictureLength = 5.0

    var end: Double { at + length }
    var isVideo: Bool { kind == .video }
    var normalizedSpeed: Double { min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound) }
    /// The video's own seconds this item plays.
    var fileLength: Double { length * normalizedSpeed }
    var fileEnd: Double { fileStart + fileLength }

    func isShowing(at time: Double) -> Bool { time >= at - 0.0005 && time < end - 0.0005 }

    /// Width / height as drawn (after the crop).
    var shownAspect: Double {
        let crop = (crop ?? .full).normalized
        return max(aspect, 0.01) * crop.width / max(crop.height, 0.01)
    }

    /// Where it's drawn on an output `size` (bottom-left origin), before
    /// turning.
    func rect(in size: CGSize) -> CGRect {
        let w = size.width * CGFloat(min(max(width, 0.02), 4))
        let h = w / CGFloat(shownAspect)
        let cx = size.width * CGFloat(x)
        let cy = size.height * (1 - CGFloat(y))
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// A new item filling the frame's width (videos) or a share of it
    /// (pictures), in the middle.
    static func make(kind: VideoMediaKind, path: String, name: String, at: Double, length: Double, fileDuration: Double, aspect: Double, canvas: CGSize) -> VideoLayerItem {
        var item = VideoLayerItem(kind: kind, path: path, name: name, at: max(at, 0), length: max(length, minimumLength), fileDuration: fileDuration, aspect: max(aspect, 0.01))
        // Fits inside the frame: as wide as it can be, or as tall.
        let canvasAspect = Double(canvas.width / max(canvas.height, 1))
        // The widest it can be with its height inside the frame (width is a
        // share of the frame's width; its height then takes width × frame
        // aspect ÷ its aspect of the frame's height).
        let fit = min(1, max(aspect, 0.01) / canvasAspect)
        // A picture starts within 40% of the frame both ways (a logo, not a wall).
        item.width = kind == .video ? fit : 0.4 * fit
        return item
    }
}

/// One track of items above the main track; they never overlap.
struct VideoLayerTrack: Codable, Equatable, Identifiable {
    var id = UUID()
    var items: [VideoLayerItem] = []

    /// Room for an item from `start` for `length` (leaving out `except`).
    func isFree(from start: Double, length: Double, except: UUID? = nil) -> Bool {
        !items.contains { $0.id != except && $0.at < start + length - 0.0005 && $0.end > start + 0.0005 }
    }

    mutating func sort() { items.sort { $0.at < $1.at } }
}

extension VideoDemoProject {
    /// Every item above the main track with its track, lowest track first.
    var layerItems: [(track: Int, item: VideoLayerItem)] {
        layerTracks.enumerated().flatMap { index, track in track.items.map { (index, $0) } }
    }

    func layerItem(_ id: UUID) -> VideoLayerItem? {
        for track in layerTracks { if let item = track.items.first(where: { $0.id == id }) { return item } }
        return nil
    }

    func layerTrackIndex(of id: UUID) -> Int? {
        layerTracks.firstIndex { $0.items.contains { $0.id == id } }
    }

    mutating func updateLayerItem(_ id: UUID, _ change: (inout VideoLayerItem) -> Void) {
        for t in layerTracks.indices {
            if let i = layerTracks[t].items.firstIndex(where: { $0.id == id }) {
                change(&layerTracks[t].items[i])
                layerTracks[t].sort()
                return
            }
        }
    }

    /// Takes empty tracks away (the timeline shows one empty row to drop on).
    mutating func dropEmptyLayerTracks() {
        layerTracks.removeAll { $0.items.isEmpty }
    }

    /// Linkage (~): each item above the main track keeps to the moment of
    /// the recording under its start, wherever that moment now plays (a
    /// moved, trimmed or retimed clip takes it along). An item whose moment
    /// was cut goes to the cut with the magnet on, and stays put with it
    /// off. Items after the main track's end keep their distance from it.
    mutating func followMainTrack(from old: VideoDemoProject, oldTotal: Double, newTotal: Double, magnet: Bool) {
        let before = old.timelineSegments(totalDuration: oldTotal)
        let after = timelineSegments(totalDuration: newTotal)
        guard let oldFirst = before.first, let oldLast = before.last, let newLast = after.last else { return }
        func moved(_ time: Double) -> Double {
            if time >= oldLast.timelineEnd - 0.0005 { return max(time + newLast.timelineEnd - oldLast.timelineEnd, 0) }
            guard time >= oldFirst.timelineStart - 0.0005,
                  let segment = before.first(where: { time >= $0.timelineStart - 0.0005 && time < $0.timelineEnd }) else { return time }
            let source = segment.sourceTime(forTimelineTime: time)
            // The same clip first, then wherever that moment plays now.
            if let same = after.first(where: { $0.id == segment.id && $0.contains(sourceTime: source) }) { return same.timelineTime(forSourceTime: source) }
            if let now = Self.timelineTimeIfIncluded(sourceTime: source, segments: after) { return now }
            guard magnet else { return time }
            return after.first(where: { $0.clip.sourceStart >= source })?.timelineStart ?? newLast.timelineEnd
        }
        for t in layerTracks.indices {
            for i in layerTracks[t].items.indices {
                layerTracks[t].items[i].at = moved(layerTracks[t].items[i].at)
            }
            // Two that landed on each other: the later one waits its turn.
            layerTracks[t].sort()
            for i in layerTracks[t].items.indices.dropFirst() where layerTracks[t].items[i].at < layerTracks[t].items[i - 1].end {
                layerTracks[t].items[i].at = layerTracks[t].items[i - 1].end
            }
        }
    }

    /// The videos above the main track (to load).
    var layerVideoPaths: [String] {
        Array(Set(layerTracks.flatMap { $0.items.filter(\.isVideo).map(\.path) })).sorted()
    }

    /// What only 1.15.0 and later can show: written as project format 4.
    var needsFormat4: Bool {
        layerTracks.contains { $0.items.contains { $0.needsFormat4 } } || timelineClips.contains { $0.needsFormat4 }
            || audioTracks.contains { $0.volumeKeys != nil || $0.beats != nil } || music?.beats != nil
    }

    /// What only 1.14.0 and later can show: written as project format 3.
    var needsLayerFormat: Bool {
        !layerTracks.isEmpty || timelineClips.contains { $0.needsLayerFormat }
            || (webcam.rotation ?? 0) != 0 || overlayEffects.contains { ($0.rotation ?? 0) != 0 }
    }
}

// MARK: - Into the edit

/// The tracks above the main track, ready to go into an edit.
struct VideoLayerInput {
    struct Track {
        var id: UUID
        var items: [VideoLayerItem]
        /// Each video, loaded, by path.
        var files: [String: VideoLayerFile]
        var muted: Bool
    }

    var tracks: [Track]
    /// Range exports: where the exported part starts on the edit's timeline.
    var timelineOffset: Double = 0

    /// The project's videos above the main track (nil: none, or none
    /// loaded); hidden tracks left out.
    static func make(project: VideoDemoProject, files: [String: VideoLayerFile]) -> VideoLayerInput? {
        let tracks = project.layerTracks.compactMap { track -> Track? in
            guard !project.isTrackHidden(.layer(track.id)) else { return nil }
            let items = track.items.filter { $0.isVideo && $0.enabled && files[$0.path] != nil }
            guard !items.isEmpty else { return nil }
            return Track(id: track.id, items: items, files: files.filter { path, _ in items.contains { $0.path == path } }, muted: project.trackState(.layer(track.id)).muted)
        }
        return tracks.isEmpty ? nil : VideoLayerInput(tracks: tracks)
    }

    struct StructureKey: Equatable {
        let items: [String]
    }

    struct MixKey: Equatable {
        let sound: [String]
    }

    var structureKey: StructureKey {
        StructureKey(items: tracks.map { track in
            track.id.uuidString + ":" + track.items.filter(\.isVideo).map { "\($0.path)|\($0.at)|\($0.length)|\($0.fileStart)|\($0.normalizedSpeed)|\($0.enabled)|\($0.keepsPitch != false)" }.joined(separator: ";")
        })
    }

    var mixKey: MixKey {
        MixKey(sound: tracks.map { track in
            "\(track.muted)" + track.items.filter(\.isVideo).map { "\($0.id)|\($0.volume)|\($0.muted)|\($0.enabled)" }.joined(separator: ";")
        })
    }

    /// Each track's videos on one composition video track (and their sound
    /// on one audio track), at their timeline times.
    func insert(into composition: AVMutableComposition, duration: Double) -> (video: [(id: UUID, track: AVMutableCompositionTrack)], audio: [(id: UUID, track: AVMutableCompositionTrack, items: [VideoLayerItem])]) {
        var videos: [(UUID, AVMutableCompositionTrack)] = []
        var sounds: [(UUID, AVMutableCompositionTrack, [VideoLayerItem])] = []
        for input in tracks {
            let items = input.items.filter { $0.isVideo && $0.enabled }.map { item -> VideoLayerItem in
                var shifted = item
                shifted.at -= timelineOffset
                return shifted
            }.filter { $0.end > 0.001 && $0.at < duration - 0.001 }
            guard !items.isEmpty else { continue }
            guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            // Keep pitch off: a sound track of its own (pitch is per track).
            var varispeed: AVMutableCompositionTrack?
            var placedVideo = false
            var placedSound: [VideoLayerItem] = []
            var placedVarispeed: [VideoLayerItem] = []
            for item in items {
                guard let file = input.files[item.path] else { continue }
                // Before the start of a range export: only the part inside.
                let skip = max(-item.at, 0)
                let at = VideoCompositionBuilder.time(item.at + skip)
                let length = min(item.length - skip, duration - (item.at + skip))
                guard length > 0.01 else { continue }
                let speed = item.normalizedSpeed
                let wanted = CMTimeRange(start: VideoCompositionBuilder.time(item.fileStart + skip * speed), duration: VideoCompositionBuilder.time(length * speed))
                let range = wanted.intersection(CMTimeRange(start: .zero, duration: VideoCompositionBuilder.time(file.duration)))
                guard range.duration.seconds > 0.01 else { continue }
                do {
                    try video.insertTimeRange(range, of: file.video, at: at)
                    if abs(speed - 1) > 0.0001 {
                        video.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: VideoCompositionBuilder.time(range.duration.seconds / speed))
                    }
                    placedVideo = true
                } catch {
                    continue
                }
                let audible = speed >= 1.0 / 32 - 0.000_1 && speed <= 32 + 0.000_1
                if item.keepsPitch == false, varispeed == nil, audible, file.audio != nil {
                    varispeed = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                if audible, let target = item.keepsPitch == false ? varispeed : audio, let sound = file.audio {
                    do {
                        try target.insertTimeRange(range, of: sound, at: at)
                        if abs(speed - 1) > 0.0001 {
                            target.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: VideoCompositionBuilder.time(range.duration.seconds / speed))
                        }
                        if item.keepsPitch == false { placedVarispeed.append(item) } else { placedSound.append(item) }
                    } catch {}
                }
            }
            if placedVideo {
                videos.append((input.id, video))
            } else {
                composition.removeTrack(video)
            }
            if let audio {
                if placedSound.isEmpty { composition.removeTrack(audio) } else { sounds.append((input.id, audio, placedSound)) }
            }
            if let varispeed {
                if placedVarispeed.isEmpty { composition.removeTrack(varispeed) } else { sounds.append((input.id, varispeed, placedVarispeed)) }
            }
        }
        return (videos, sounds)
    }

    /// Each video's own level, silent between them.
    func apply(to params: AVMutableAudioMixInputParameters, track id: UUID, items: [VideoLayerItem], audio: VideoAudioSettings) {
        let trackMuted = tracks.first { $0.id == id }?.muted ?? false
        params.setVolume(0, at: .zero)
        if items.contains(where: { $0.keepsPitch == false }) { params.audioTimePitchAlgorithm = .varispeed }
        for item in items {
            let silent = audio.muted || trackMuted || item.muted
            func level(_ volume: Double) -> Float { silent ? 0 : Float(min(max(volume, 0), 2) * audio.volume) }
            let keys = item.keys?.keys(.volume) ?? []
            if keys.isEmpty {
                params.setVolume(level(item.volume), at: VideoCompositionBuilder.time(max(item.at, 0)))
            } else {
                // Volume keyframes: ramps between them, eased in steps.
                params.setVolume(level(item.value(.volume, at: item.at)), at: VideoCompositionBuilder.time(max(item.at, 0)))
                let steps = 8
                for (a, b) in zip(keys, keys.dropFirst()) {
                    for step in 0..<steps {
                        let t0 = a.time + (b.time - a.time) * Double(step) / Double(steps)
                        let t1 = a.time + (b.time - a.time) * Double(step + 1) / Double(steps)
                        let start = item.at + t0
                        guard start >= 0, t1 > t0 else { continue }
                        params.setVolumeRamp(fromStartVolume: level(item.value(.volume, at: item.at + t0)), toEndVolume: level(item.value(.volume, at: item.at + t1)),
                                             timeRange: CMTimeRange(start: VideoCompositionBuilder.time(start), duration: VideoCompositionBuilder.time(t1 - t0)))
                    }
                }
            }
            // Fades at its ends (volume keys, when it has them, do the
            // shaping instead: ramps can't overlap).
            let fadeIn = keys.isEmpty ? min(item.soundFadeIn ?? 0, item.length / 2) : 0
            let fadeOut = keys.isEmpty ? min(item.soundFadeOut ?? 0, item.length / 2) : 0
            if fadeIn > 0.01, item.at >= 0 {
                params.setVolumeRamp(fromStartVolume: 0, toEndVolume: level(item.value(.volume, at: item.at + fadeIn)),
                                     timeRange: CMTimeRange(start: VideoCompositionBuilder.time(item.at), duration: VideoCompositionBuilder.time(fadeIn)))
            }
            if fadeOut > 0.01, item.end - fadeOut >= 0 {
                params.setVolumeRamp(fromStartVolume: level(item.value(.volume, at: item.end - fadeOut)), toEndVolume: 0,
                                     timeRange: CMTimeRange(start: VideoCompositionBuilder.time(item.end - fadeOut), duration: VideoCompositionBuilder.time(fadeOut)))
            }
            params.setVolume(0, at: VideoCompositionBuilder.time(max(item.end, 0)))
        }
    }
}

/// A video on a track above the main track, loaded.
struct VideoLayerFile {
    let asset: AVURLAsset
    let video: AVAssetTrack
    let audio: AVAssetTrack?
    let duration: Double

    static func load(_ url: URL) async -> VideoLayerFile? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let video = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { return nil }
        let audio = try? await asset.loadTracks(withMediaType: .audio).first
        return VideoLayerFile(asset: asset, video: video, audio: audio, duration: duration)
    }
}

/// Frames of each video track above the main track, handed over by the
/// compositor (like the camera's), by layer track.
final class VideoLayerFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stores: [UUID: VideoCameraFrameStore] = [:]

    func put(_ buffer: CVPixelBuffer?, track: UUID, at time: Double) {
        guard let buffer else { return }
        store(for: track).put(buffer, at: time)
    }

    /// The frame composed nearest to `time` on each track.
    func frames(at time: Double, tolerance: Double = 0.08) -> [UUID: CIImage] {
        lock.lock()
        let all = stores
        lock.unlock()
        var frames: [UUID: CIImage] = [:]
        for (id, store) in all { if let image = store.frame(at: time, tolerance: tolerance) { frames[id] = image } }
        return frames
    }

    func removeAll() {
        lock.lock()
        let all = stores.values
        lock.unlock()
        all.forEach { $0.removeAll() }
    }

    private func store(for track: UUID) -> VideoCameraFrameStore {
        lock.lock()
        defer { lock.unlock() }
        if let store = stores[track] { return store }
        let store = VideoCameraFrameStore(capacity: 12, maximumHeight: 1080)
        stores[track] = store
        return store
    }
}

// MARK: - Drawing

enum VideoLayerRenderer {
    /// `frame` (a video's) or the picture, cropped, mirrored, placed and
    /// turned on an output `size`.
    static func image(for item: VideoLayerItem, frame: CIImage?, outputSize: CGSize, time: Double = 0) -> CIImage? {
        guard item.enabled, item.opacity > 0.001 else { return nil }
        // (`item` is already resolved at the moment drawn: keys applied.)
        var media: CIImage
        if let text = item.text {
            let height = item.rect(in: outputSize).height
            guard let image = VideoTextClipRenderer.image(text, pixelHeight: height) else { return nil }
            media = image
        } else if item.isVideo {
            guard let frame else { return nil }
            media = frame
        } else {
            guard let picture = VideoImageOverlayRenderer.picture(path: item.path) else { return nil }
            media = picture
        }
        // Cutout first: on the whole picture, before it's cut down.
        if let key = item.chroma { media = VideoCutout.chroma(media, key: key) }
        if item.removesBackground == true {
            let frameTime = item.isVideo ? ((item.fileStart + (time - item.at) * item.normalizedSpeed) * 30).rounded() / 30 : 0
            media = VideoCutout.person(media, key: "\(item.path)@\(frameTime)")
        }
        let extent = media.extent
        if let crop = item.crop?.normalized, !crop.isFull {
            // Top-left crop → bottom-left pixels.
            let rect = CGRect(x: extent.minX + extent.width * crop.x, y: extent.minY + extent.height * (1 - crop.y - crop.height),
                              width: extent.width * crop.width, height: extent.height * crop.height)
            media = media.cropped(to: rect)
        }
        if item.mirrored {
            let shown = media.extent
            media = media.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: shown.minX + shown.maxX, ty: 0))
        }
        if let mask = item.mask { media = mask.apply(to: media) }
        return VideoImageOverlayRenderer.placed(media, in: item.rect(in: outputSize), opacity: min(max(item.opacity, 0), 1), rotation: item.rotation)
    }
}

/// Frames of the videos above the main track decoded one at a time, for
/// stills (offscreen windows and tests, which play nothing).
enum VideoLayerStills {
    static func frames(for layers: [(track: UUID, item: VideoLayerItem)], at time: Double) -> [UUID: CIImage] {
        var frames: [UUID: CIImage] = [:]
        for layer in layers where layer.item.isVideo && layer.item.isShowing(at: time) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: layer.item.path)))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let at = layer.item.fileStart + (time - layer.item.at) * layer.item.normalizedSpeed
            if let image = try? generator.copyCGImage(at: CMTime(seconds: at, preferredTimescale: 600), actualTime: nil) {
                frames[layer.track] = CIImage(cgImage: image)
            }
        }
        return frames
    }
}

extension VideoLayerItem {
    /// Uses something only 1.15.0 shows.
    var needsFormat4: Bool {
        (keys.map { !$0.isEmpty } ?? false) || mask != nil || level != nil || blend != nil || removesBackground != nil || chroma != nil || text != nil || tracking != nil || animation != nil || keepsPitch != nil || soundFadeIn != nil || soundFadeOut != nil || speed < 0.25 - 0.000_1 || speed > 4 + 0.000_1
    }
}
