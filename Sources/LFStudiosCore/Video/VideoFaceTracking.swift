import AVFoundation
import CoreImage
import Foundation
import Vision

// MARK: - Settings (per project)

/// "Keep face centered": the bubble's crop follows the face found in the
/// camera video. Off until the button analyzes the video.
struct VideoFaceTracking: Codable, Equatable {
    static let smoothnessRange: ClosedRange<Double> = 0...1
    static let tightnessRange: ClosedRange<Double> = 0...1

    var enabled = true
    /// 0 follows quickly … 1 drifts slowly after the face.
    var smoothness = 0.6
    /// 0 loose (head and shoulders) … 1 tight (the face fills the bubble).
    var tightness = 0.45

    init() {}

    private enum CodingKeys: String, CodingKey { case enabled, smoothness, tightness }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VideoFaceTracking()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        smoothness = (try? c.decodeIfPresent(Double.self, forKey: .smoothness)) ?? d.smoothness
        tightness = (try? c.decodeIfPresent(Double.self, forKey: .tightness)) ?? d.tightness
    }
}

// MARK: - Faces found

/// Where the face was in one camera frame: camera seconds, and a box on
/// the upright picture, normalized with y down.
struct VideoFaceDetection: Codable, Equatable {
    var time: Double
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }
}

/// One camera video's analysis: the frames looked at and the faces found.
struct VideoFaceAnalysis: Codable, Equatable {
    static let version = 1

    var version = Self.version
    /// Camera seconds looked at, in order (a frame without a face is in
    /// here but not in `faces`).
    var times: [Double]
    var faces: [VideoFaceDetection]
    var duration: Double
}

/// Analyses kept on disk, one per camera file (its path and when it
/// changed), so a video is never analyzed twice.
enum VideoFaceStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var memory: [String: VideoFaceAnalysis] = [:]

    static func key(for url: URL) -> String {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let raw = Data("\(url.standardizedFileURL.path)|\(Int(stamp))|v\(VideoFaceAnalysis.version)".utf8).base64EncodedString()
        return String(raw.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "").suffix(80))
    }

    static func fileURL(for url: URL) -> URL {
        VideoStorageLocation.root
            .appendingPathComponent("LF Studios", isDirectory: true)
            .appendingPathComponent("FaceTracking", isDirectory: true)
            .appendingPathComponent(key(for: url) + ".json")
    }

    static func load(for url: URL) -> VideoFaceAnalysis? {
        let key = key(for: url)
        lock.lock()
        if let cached = memory[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let data = try? Data(contentsOf: fileURL(for: url)),
              let analysis = try? JSONDecoder().decode(VideoFaceAnalysis.self, from: data),
              analysis.version == VideoFaceAnalysis.version else { return nil }
        lock.lock()
        memory[key] = analysis
        lock.unlock()
        return analysis
    }

    static func save(_ analysis: VideoFaceAnalysis, for url: URL) {
        let file = fileURL(for: url)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(analysis) { try? data.write(to: file, options: .atomic) }
        lock.lock()
        memory[key(for: url)] = analysis
        lock.unlock()
    }
}

/// Finds the face in a camera video with Apple's Vision face detection,
/// a few frames a second.
enum VideoFaceAnalyzer {
    static let framesPerSecond = 8.0

    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? { L("The camera video couldn't be read, so no face could be found.") }
    }

    /// The face in each looked-at frame: the biggest, or the one nearest the
    /// last when several are close in size.
    static func analyze(url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> VideoFaceAnalysis {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.unreadable }
        let duration = max(try await asset.load(.duration).seconds, 0.1)
        let transform = try await track.load(.preferredTransform)
        let orientation = Self.orientation(of: transform)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw Failure.unreadable }

        var times: [Double] = []
        var faces: [VideoFaceDetection] = []
        var next = 0.0
        var previous: CGPoint?
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time + 0.0001 >= next, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            next = time + 1 / framesPerSecond
            times.append(time)
            let request = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:]).perform([request])
            let found = (request.results ?? []).map { observation -> VideoFaceDetection in
                // Vision: normalized, origin at the bottom left.
                let box = observation.boundingBox
                return VideoFaceDetection(time: time, x: Double(box.minX), y: Double(1 - box.maxY), width: Double(box.width), height: Double(box.height))
            }
            if let face = choose(found, near: previous) {
                faces.append(face)
                previous = face.center
            }
            progress(min(time / duration, 1))
        }
        if reader.status == .failed { throw reader.error ?? Failure.unreadable }
        progress(1)
        return VideoFaceAnalysis(times: times, faces: faces, duration: duration)
    }

    static func choose(_ faces: [VideoFaceDetection], near previous: CGPoint?) -> VideoFaceDetection? {
        guard let biggest = faces.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
        guard let previous else { return biggest }
        // Someone walking past in the back doesn't steal the framing.
        let close = faces.filter { $0.width * $0.height >= biggest.width * biggest.height * 0.6 }
        return close.min { hypot($0.center.x - previous.x, $0.center.y - previous.y) < hypot($1.center.x - previous.x, $1.center.y - previous.y) } ?? biggest
    }

    static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}

// MARK: - The crop that follows the face

/// The bubble's crop over time: centered on the face, as tight as asked,
/// gliding after it on a smooth spring, holding the last good framing
/// where no face was found. Sampled in camera seconds.
final class VideoFaceCropPath: @unchecked Sendable {
    static let sampleRate = 30.0

    /// Camera time = source time − offset.
    let offset: Double
    private let crops: [VideoCropRect]

    init?(analysis: VideoFaceAnalysis, settings: VideoFaceTracking, pictureSize: CGSize, bubbleAspect: CGFloat, offset: Double) {
        let faces = analysis.faces.sorted { $0.time < $1.time }
        guard settings.enabled, let first = faces.first, pictureSize.width > 0, pictureSize.height > 0 else { return nil }
        self.offset = offset
        let count = max(Int((analysis.duration * Self.sampleRate).rounded(.up)) + 1, 2)
        // The face fills this much of the crop's height.
        let fill = 0.28 + 0.4 * min(max(settings.tightness, 0), 1)
        let pictureAspect = Double(pictureSize.width / pictureSize.height)
        let aspect = Double(bubbleAspect)
        // Spring stiffness: quick at 0, slow and calm at 1.
        let omega = 9 - 7.5 * min(max(settings.smoothness, 0), 1)
        let dt = 1 / Self.sampleRate

        var target = first
        var faceIndex = 0
        var position = first.center
        var size = first.height
        var velocity = CGVector.zero
        var sizeVelocity = 0.0
        var crops: [VideoCropRect] = []
        crops.reserveCapacity(count)
        for index in 0..<count {
            let time = Double(index) * dt
            // The latest face found at or before now (before the first, the
            // first): no face for a while keeps the last good one.
            while faceIndex + 1 < faces.count, faces[faceIndex + 1].time <= time {
                faceIndex += 1
            }
            if faces[faceIndex].time <= time || faceIndex == 0 { target = faces[faceIndex] }
            // A little below the face's middle: head and a bit of shoulder.
            let aim = CGPoint(x: target.center.x, y: target.center.y + target.height * 0.12)
            if index == 0 {
                position = aim
                size = target.height
            } else {
                for _ in 0..<2 {
                    let h = dt / 2
                    velocity.dx += (omega * omega * (aim.x - position.x) - 2 * omega * velocity.dx) * h
                    velocity.dy += (omega * omega * (aim.y - position.y) - 2 * omega * velocity.dy) * h
                    position.x += velocity.dx * h
                    position.y += velocity.dy * h
                    // The size follows more calmly than the position.
                    let slow = omega * 0.6
                    sizeVelocity += (slow * slow * (target.height - size) - 2 * slow * sizeVelocity) * h
                    size += sizeVelocity * h
                }
            }
            var height = min(max(size / fill, 0.15), 1)
            var width = height * aspect / pictureAspect
            if width > 1 {
                width = 1
                height = width * pictureAspect / aspect
            }
            let x = min(max(Double(position.x) - width / 2, 0), 1 - width)
            let y = min(max(Double(position.y) - height / 2, 0), 1 - height)
            crops.append(VideoCropRect(x: x, y: y, width: width, height: height))
        }
        self.crops = crops
    }

    /// The crop at a camera moment.
    func crop(atCameraTime time: Double) -> VideoCropRect {
        let position = min(max(time, 0) * Self.sampleRate, Double(crops.count - 1))
        let lower = Int(position)
        let upper = min(lower + 1, crops.count - 1)
        let f = position - Double(lower)
        let a = crops[lower], b = crops[upper]
        return VideoCropRect(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f, width: a.width + (b.width - a.width) * f, height: a.height + (b.height - a.height) * f)
    }

    func crop(atSourceTime time: Double) -> VideoCropRect { crop(atCameraTime: time - offset) }

    /// The path for a project's camera, from its saved analysis (nil: face
    /// tracking off, or the video wasn't analyzed).
    static func make(project: VideoDemoProject, recordedCamera: VideoWebcamRecording?) -> VideoFaceCropPath? {
        guard let settings = project.faceTracking, settings.enabled,
              let camera = project.activeCamera(recorded: recordedCamera) else { return nil }
        let url = project.importedCamera?.resolved() ?? camera.url
        guard let analysis = VideoFaceStore.load(for: url) else { return nil }
        return VideoFaceCropPath(analysis: analysis, settings: settings, pictureSize: CGSize(width: camera.width, height: camera.height), bubbleAspect: project.webcam.shape.aspect, offset: camera.offset)
    }
}
