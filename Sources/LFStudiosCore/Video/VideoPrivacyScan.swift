import AVFoundation
import CoreImage
import Foundation
import Vision

// MARK: - What a scan reads

/// A box on a frame, normalized, y down.
struct VideoPrivacyBox: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }

    func union(_ other: VideoPrivacyBox) -> VideoPrivacyBox {
        let minX = min(x, other.x), minY = min(y, other.y)
        let maxX = max(x + width, other.x + other.width), maxY = max(y + height, other.y + other.height)
        return VideoPrivacyBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// The text and faces on one frame, as Vision read them. Kept on disk, so
/// a second scan (new custom words too) needs no reading at all.
struct VideoPrivacyFrame: Codable, Equatable {
    struct Word: Codable, Equatable {
        /// Where the word starts and how long it is in its line (UTF-16).
        var start: Int
        var length: Int
        var box: VideoPrivacyBox
    }

    struct Line: Codable, Equatable {
        var text: String
        var words: [Word]
    }

    /// Seconds in the scanned file.
    var time: Double
    var lines: [Line]
    var faces: [VideoPrivacyBox]
}

struct VideoPrivacyFileScan: Codable, Equatable {
    static let version = 1
    var version = Self.version
    var frames: [VideoPrivacyFrame]
}

/// Scans cached per file (its path and when it changed).
enum VideoPrivacyScanStore {
    static func fileURL(for url: URL) -> URL {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let raw = Data("\(url.standardizedFileURL.path)|\(Int(stamp))|v\(VideoPrivacyFileScan.version)".utf8).base64EncodedString()
        let key = String(raw.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "").suffix(80))
        return VideoStorageLocation.root
            .appendingPathComponent("LF Studios", isDirectory: true)
            .appendingPathComponent("PrivacyScans", isDirectory: true)
            .appendingPathComponent(key + ".json")
    }

    static func load(for url: URL) -> VideoPrivacyFileScan? {
        guard let data = try? Data(contentsOf: fileURL(for: url)),
              let scan = try? JSONDecoder().decode(VideoPrivacyFileScan.self, from: data),
              scan.version == VideoPrivacyFileScan.version else { return nil }
        return scan
    }

    static func save(_ scan: VideoPrivacyFileScan, for url: URL) {
        let file = fileURL(for: url)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(scan) { try? data.write(to: file, options: .atomic) }
    }
}

/// Reads a video's frames with Apple's Vision: text (as written, without
/// autocorrect, so keys stay as they are) and faces. All on this Mac.
enum VideoPrivacyReader {
    /// Frames a second, and twice that where text moves (scrolling).
    static let step = 0.25

    static func scan(url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> VideoPrivacyFileScan {
        if let cached = VideoPrivacyScanStore.load(for: url) {
            progress(1)
            return cached
        }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoFaceAnalyzer.Failure.unreadable }
        let duration = max(try await asset.load(.duration).seconds, 0.1)
        let orientation = VideoFaceAnalyzer.orientation(of: try await track.load(.preferredTransform))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard reader.canAdd(output) else { throw VideoFaceAnalyzer.Failure.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? VideoFaceAnalyzer.Failure.unreadable }

        var frames: [VideoPrivacyFrame] = []
        var next = 0.0
        // The frame halfway to the next one, read only if text moved.
        var halfway: (time: Double, buffer: CVPixelBuffer)?
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            if halfway == nil, let last = frames.last, time >= last.time + step / 2 - 0.001, time < next - 0.001 {
                halfway = (time, buffer)
            }
            guard time + 0.0001 >= next else { continue }
            next = time + step
            let frame = read(buffer, time: time, orientation: orientation)
            if let previous = frames.last, let middle = halfway, moved(previous, frame) {
                frames.append(read(middle.buffer, time: middle.time, orientation: orientation))
            }
            halfway = nil
            frames.append(frame)
            progress(min(time / duration, 0.999))
        }
        if reader.status == .failed { throw reader.error ?? VideoFaceAnalyzer.Failure.unreadable }
        let scan = VideoPrivacyFileScan(frames: frames)
        VideoPrivacyScanStore.save(scan, for: url)
        progress(1)
        return scan
    }

    static func read(_ buffer: CVPixelBuffer, time: Double, orientation: CGImagePropertyOrientation) -> VideoPrivacyFrame {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        // Keys and addresses must stay exactly as written.
        text.usesLanguageCorrection = false
        text.minimumTextHeight = 0.006
        let faces = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:]).perform([text, faces])
        func box(_ rect: CGRect) -> VideoPrivacyBox {
            VideoPrivacyBox(x: Double(rect.minX), y: Double(1 - rect.maxY), width: Double(rect.width), height: Double(rect.height))
        }
        var lines: [VideoPrivacyFrame.Line] = []
        for observation in text.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            var words: [VideoPrivacyFrame.Word] = []
            var index = string.startIndex
            while index < string.endIndex {
                guard let start = string[index...].firstIndex(where: { !$0.isWhitespace }) else { break }
                let end = string[start...].firstIndex(where: \.isWhitespace) ?? string.endIndex
                if let rect = try? candidate.boundingBox(for: start..<end)?.boundingBox {
                    let offset = string.utf16.distance(from: string.startIndex, to: start)
                    words.append(.init(start: offset, length: string.utf16.distance(from: start, to: end), box: box(rect)))
                }
                index = end
            }
            lines.append(.init(text: string, words: words))
        }
        return VideoPrivacyFrame(time: time, lines: lines, faces: (faces.results ?? []).map { box($0.boundingBox) })
    }

    /// The same line of text somewhere else: the page moved.
    static func moved(_ a: VideoPrivacyFrame, _ b: VideoPrivacyFrame) -> Bool {
        var before: [String: CGPoint] = [:]
        for line in a.lines where line.text.count >= 6 {
            if let box = line.words.map(\.box).reduce(nil as VideoPrivacyBox?, { $0?.union($1) ?? $1 }) { before[line.text] = box.center }
        }
        for line in b.lines {
            guard let old = before[line.text], let box = line.words.map(\.box).reduce(nil as VideoPrivacyBox?, { $0?.union($1) ?? $1 }) else { continue }
            if abs(box.center.y - old.y) > 0.004 || abs(box.center.x - old.x) > 0.004 { return true }
        }
        return false
    }
}

// MARK: - What was found

/// One private thing, followed over time.
struct VideoPrivacyItem: Identifiable, Equatable {
    struct Key: Equatable {
        /// Source seconds.
        var time: Double
        /// On the scanned file's frame.
        var box: VideoPrivacyBox
    }

    let id: UUID
    var kind: VideoPrivacyKind
    /// What it says (empty for faces).
    var text: String
    var keys: [Key]
    /// On the camera video rather than the screen.
    var onCamera: Bool

    /// Source seconds it's visible from and to.
    var start: Double { (keys.first?.time ?? 0) - VideoPrivacyReader.step * 0.6 }
    var end: Double { (keys.last?.time ?? 0) + VideoPrivacyReader.step * 0.6 }

    /// What the list shows: enough to recognize it, not all of it.
    var label: String {
        guard !text.isEmpty else { return kind.title }
        let characters = Array(text)
        guard characters.count > 8 else { return text }
        return String(characters.prefix(4)) + "…" + String(characters.suffix(3))
    }
}

/// Finds turned into items: the patterns on each frame's text, then the
/// same thing linked from frame to frame (following it as the page
/// scrolls), small gaps bridged.
enum VideoPrivacyTracker {
    struct Found {
        var kind: VideoPrivacyKind
        var text: String
        var box: VideoPrivacyBox
    }

    /// One frame's finds.
    static func finds(in frame: VideoPrivacyFrame, customWords: [String]) -> [Found] {
        var found: [Found] = frame.faces.map { Found(kind: .face, text: "", box: $0) }
        for line in frame.lines {
            for match in VideoPrivacyPatterns.matches(in: line.text, customWords: customWords) {
                let start = line.text.utf16.distance(from: line.text.startIndex, to: match.range.lowerBound)
                let end = line.text.utf16.distance(from: line.text.startIndex, to: match.range.upperBound)
                var box: VideoPrivacyBox?
                for word in line.words where word.start < end && word.start + word.length > start {
                    // The part of the word that matched (a "password:x" word
                    // is blurred from the x on).
                    let from = Double(max(start - word.start, 0)) / Double(max(word.length, 1))
                    let to = Double(min(end - word.start, word.length)) / Double(max(word.length, 1))
                    let part = VideoPrivacyBox(x: word.box.x + word.box.width * from, y: word.box.y, width: word.box.width * (to - from), height: word.box.height)
                    box = box?.union(part) ?? part
                }
                if let box { found.append(Found(kind: match.kind, text: match.text, box: box)) }
            }
        }
        return found
    }

    static func items(from scan: VideoPrivacyFileScan, timeOffset: Double, onCamera: Bool, customWords: [String], kinds: Set<VideoPrivacyKind> = Set(VideoPrivacyKind.allCases)) -> [VideoPrivacyItem] {
        struct Track {
            var kind: VideoPrivacyKind
            var key: String
            var text: String
            var keys: [VideoPrivacyItem.Key]
        }
        let maxGap = 1.0
        var open: [Track] = []
        var done: [Track] = []
        for frame in scan.frames.sorted(by: { $0.time < $1.time }) {
            let time = frame.time + timeOffset
            // Tracks this frame can't continue are finished.
            let (stale, live) = open.reduce(into: ([Track](), [Track]())) { result, track in
                if time - (track.keys.last?.time ?? time) > maxGap { result.0.append(track) } else { result.1.append(track) }
            }
            done += stale
            open = live
            var taken = Set<Int>()
            for find in finds(in: frame, customWords: customWords) where kinds.contains(find.kind) {
                let key = find.kind == .face ? "face" : find.text.lowercased().filter { !$0.isWhitespace }
                // The nearest track of the same thing not yet continued here.
                let reach = find.kind == .face ? 0.2 : 0.35
                var best: (index: Int, distance: Double)?
                for (index, track) in open.enumerated() where !taken.contains(index) && track.kind == find.kind && track.key == key {
                    guard let last = track.keys.last, last.time < time else { continue }
                    let distance = hypot(last.box.center.x - find.box.center.x, last.box.center.y - find.box.center.y)
                    if distance < reach, distance < (best?.distance ?? .infinity) { best = (index, Double(distance)) }
                }
                if let best {
                    open[best.index].keys.append(.init(time: time, box: find.box))
                    taken.insert(best.index)
                } else {
                    open.append(Track(kind: find.kind, key: key, text: find.text, keys: [.init(time: time, box: find.box)]))
                    taken.insert(open.count - 1)
                }
            }
        }
        done += open
        return done
            // A face or word seen once, for a moment, is likely a misread.
            .filter { $0.keys.count >= 2 || $0.kind == .secret || $0.kind == .card }
            .sorted { ($0.keys.first?.time ?? 0) < ($1.keys.first?.time ?? 0) }
            .map { VideoPrivacyItem(id: UUID(), kind: $0.kind, text: $0.text, keys: $0.keys, onCamera: onCamera) }
    }
}

// MARK: - Into blur blocks

extension VideoPrivacyItem {
    /// A normal blur block that follows the item, in annotation
    /// coordinates (`crop` maps the screen recording's frame into them; a
    /// camera blur stays on the camera's picture).
    func blurEffect(crop: VideoCropRect, layer: Int, strength: Double? = nil) -> VideoDemoOverlayEffect {
        func placed(_ box: VideoPrivacyBox) -> VideoOverlayMotionKey.Box {
            // A little larger than the text, and never too small to edit.
            let padX = max(box.width * 0.08, 0.006), padY = max(box.height * 0.3, 0.006)
            var rect = CGRect(x: box.x - padX, y: box.y - padY, width: box.width + padX * 2, height: box.height + padY * 2)
            if !onCamera {
                let a = crop.map(CGPoint(x: rect.minX, y: rect.minY)), b = crop.map(CGPoint(x: rect.maxX, y: rect.maxY))
                rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
            }
            let width = min(max(Double(rect.width), 0.04), 1)
            let height = min(max(Double(rect.height), 0.03), 1)
            return .init(x: min(max(Double(rect.midX), 0.02), 0.98), y: min(max(Double(rect.midY), 0.02), 0.98), width: width, height: height)
        }
        let boxes = keys.map { (time: $0.time, box: placed($0.box)) }
        let first = boxes[0].box
        var effect = VideoDemoOverlayEffect(kind: .blur, time: max(start, 0), duration: max(end - max(start, 0), 0.3), x: first.x, y: first.y, width: first.width, height: first.height, text: kind.title, layer: layer)
        effect.strength = strength
        // Moving: a path; still: one box.
        let moves = boxes.contains { abs($0.box.x - first.x) > 0.003 || abs($0.box.y - first.y) > 0.003 || abs($0.box.width - first.width) > 0.006 }
        if moves {
            effect.motion = boxes.map { VideoOverlayMotionKey(time: $0.time, x: $0.box.x, y: $0.box.y, width: $0.box.width, height: $0.box.height) }
        }
        if onCamera { effect.onCamera = true }
        return effect
    }
}

extension VideoOverlayMotionKey {
    struct Box {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }
}
