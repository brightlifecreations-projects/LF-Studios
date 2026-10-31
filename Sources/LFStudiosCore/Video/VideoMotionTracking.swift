import AVFoundation
import SwiftUI
import Vision

// MARK: - Motion tracking (1.15.0)

/// Where a clip above the main track is moved to follow something in the
/// video: offsets from its own place (shares of the frame), by its own
/// seconds. Before the first point it stays put; after the last it holds.
struct VideoMotionTrack: Codable, Equatable {
    struct Point: Codable, Equatable {
        var t: Double
        var dx: Double
        var dy: Double
    }

    var points: [Point]

    func offset(at time: Double) -> CGVector {
        guard let first = points.first, let last = points.last else { return .zero }
        if time <= first.t { return CGVector(dx: first.dx, dy: first.dy) }
        if time >= last.t { return CGVector(dx: last.dx, dy: last.dy) }
        let i = points.firstIndex { $0.t > time } ?? points.count - 1
        let a = points[i - 1], b = points[i]
        let f = (time - a.t) / max(b.t - a.t, 0.000_1)
        return CGVector(dx: a.dx + (b.dx - a.dx) * f, dy: a.dy + (b.dy - a.dy) * f)
    }

    /// After a trim or a split (like keyframes).
    mutating func shift(by delta: Double, length: Double) {
        points = points.map { var p = $0; p.t += delta; return p }.filter { $0.t >= -0.0005 && $0.t <= length + 0.0005 }
    }
}

extension VideoLayerItem {
    /// Keys and the motion track applied: where it is at timeline `time`
    /// (the player's handles and the renderer start from this).
    func placed(at time: Double) -> VideoLayerItem {
        var item = resolved(at: time)
        if let tracking {
            let offset = tracking.offset(at: time - at)
            item.x += offset.dx
            item.y += offset.dy
        }
        return item
    }
}

/// Follows a region of a video with Vision (VNTrackObjectRequest).
enum VideoMotionTracker {
    struct Result {
        var points: [VideoMotionTrack.Point]
        /// Where it lost sight of it (seconds into the video), if it did.
        var lostAt: Double?
    }

    /// Follows `region` (shares of the frame, from the top left) from the
    /// video's first frame. Points every `step` seconds, lightly smoothed.
    static func track(_ url: URL, region: CGRect, step: Double = 0.1, progress: @escaping @Sendable (Double) -> Void = { _ in }, cancelled: @escaping @Sendable () -> Bool = { false }) async throws -> Result {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoDemoExportError.exportFailed(L("Couldn't read the video to follow")) }
        let duration = max(try await asset.load(.duration).seconds, 0.001)
        return try await Task.detached(priority: .userInitiated) {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? VideoDemoExportError.exportFailed(L("Couldn't read the video to follow")) }
            defer { reader.cancelReading() }
            let box = CGRect(x: region.minX, y: 1 - region.maxY, width: region.width, height: region.height)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            var observation = VNDetectedObjectObservation(boundingBox: box)
            let handler = VNSequenceRequestHandler()
            var raw: [VideoMotionTrack.Point] = []
            var lostAt: Double?
            var lastStored = -Double.infinity
            while let sample = output.copyNextSampleBuffer() {
                if cancelled() { throw VideoDemoExportError.cancelled }
                guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                let request = VNTrackObjectRequest(detectedObjectObservation: observation)
                request.trackingLevel = .accurate
                try handler.perform([request], on: pixels)
                guard let found = request.results?.first as? VNDetectedObjectObservation, found.confidence > 0.3 else {
                    lostAt = time
                    break
                }
                observation = found
                if time - lastStored >= step - 0.001 {
                    let moved = found.boundingBox
                    raw.append(.init(t: time, dx: Double(moved.midX - box.midX), dy: Double(box.midY - moved.midY)))
                    lastStored = time
                    progress(min(time / duration, 1))
                }
            }
            // A little smoothing (Vision's box jitters by a pixel or two).
            var points = raw
            for i in raw.indices.dropFirst().dropLast() {
                points[i].dx = (raw[i - 1].dx + raw[i].dx * 2 + raw[i + 1].dx) / 4
                points[i].dy = (raw[i - 1].dy + raw[i].dy * 2 + raw[i + 1].dy) / 4
            }
            return Result(points: points, lostAt: lostAt)
        }.value
    }

    /// The edit from `start` to `end` on the timeline as it looks under the
    /// clip `id` (tracks from its own up left out), written small to `url`.
    static func renderUnder(_ id: UUID, project: VideoDemoProject, recording: VideoDemoRecordingMetadata?, from start: Double, to end: Double, url: URL,
                            progress: @escaping @Sendable (Double) async -> Void = { _ in }, cancelled: @escaping @Sendable () async -> Bool = { false }) async throws {
        var under = project
        if let track = project.layerTrackIndex(of: id) { under.layerTracks = Array(project.layerTracks.prefix(track)) }
        if under.cursorSamples.isEmpty, let recording { under.cursorSamples = recording.cursorSamples }
        var settings = VideoExportSettings()
        settings.resolution = .p720
        settings.fps = 30
        settings.endCard = false
        try? FileManager.default.removeItem(at: url)
        try await VideoDemoExporter.export(project: under, recording: recording, destinationURL: url, settings: settings, range: .timeline(start...end), progress: progress, shouldCancel: cancelled)
    }
}

/// Picking the region to follow, then following it.
struct VideoMotionTrackingState: Equatable {
    var item: UUID
    /// Shares of the frame, from the top left.
    var region: CGRect
    /// nil: still picking; 0…1 while it follows.
    var progress: Double?
}

extension VideoEditorModel {
    /// Track: a box on the player over what the clip should follow (the
    /// clip's own place to begin with).
    func beginMotionTracking(_ id: UUID) {
        guard let item = project.layerItem(id), let track = project.layerTrackIndex(of: id), !refuseLockedLayer(track) else { return }
        playback.pause()
        if !item.isShowing(at: clock.time) { seek(to: item.at) }
        let placed = item.placed(at: clock.time)
        let canvas = project.canvasSize()
        let rect = placed.rect(in: canvas)
        let side = min(max(min(rect.width / canvas.width, rect.height / canvas.height), 0.08), 0.4)
        let h = side * canvas.width / max(canvas.height, 1)
        motionTracking = VideoMotionTrackingState(item: id, region: CGRect(x: placed.x - side / 2, y: placed.y - h / 2, width: side, height: h).clampedToUnit)
    }

    private func setTrackingProgress(_ value: Double) {
        if motionTracking?.progress != nil { motionTracking?.progress = value }
    }

    func cancelMotionTracking() {
        if motionTracking?.progress != nil { trackingCancelFlag.value = true } else { motionTracking = nil }
    }

    /// Follows the box from the playhead to the clip's end; the clip moves
    /// with it (one ⌘Z step). Vision on this Mac; nothing leaves it.
    func trackMotion(_ id: UUID, region: CGRect) async {
        guard let item = project.layerItem(id), let track = project.layerTrackIndex(of: id), !refuseLockedLayer(track) else { return }
        let start = min(max(clock.time, item.at), max(item.end - 0.2, item.at))
        motionTracking = VideoMotionTrackingState(item: id, region: region, progress: 0)
        let flag = trackingCancelFlag
        flag.value = false
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-tracking-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: url)
            motionTracking = nil
        }
        do {
            try await VideoMotionTracker.renderUnder(id, project: project, recording: recording, from: start, to: item.end, url: url,
                                                     progress: { [weak self] p in await self?.setTrackingProgress(p * 0.5) },
                                                     cancelled: { flag.value })
            let result = try await VideoMotionTracker.track(url, region: region, progress: { [weak self] p in
                Task { await self?.setTrackingProgress(0.5 + p * 0.5) }
            }, cancelled: { flag.value })
            guard !result.points.isEmpty else {
                showNotice(L("Couldn't follow that — try a bigger box over something with clear edges"), symbol: "scope")
                return
            }
            let offset = start - item.at
            var points = [VideoMotionTrack.Point(t: offset, dx: 0, dy: 0)]
            points += result.points.map { .init(t: $0.t + offset, dx: $0.dx, dy: $0.dy) }.filter { $0.t > offset + 0.001 }
            mutate(label: "Track Motion") { project in
                project.updateLayerItem(id) { $0.tracking = VideoMotionTrack(points: points) }
            }
            if let lost = result.lostAt {
                showNotice(L("Lost sight of it at \(VideoEditorModel.format(start + lost)) — it holds still from there"), symbol: "scope", duration: 4)
            } else {
                showNotice(L("Following it — play to see"), symbol: "scope")
            }
        } catch VideoDemoExportError.cancelled {
            showNotice(L("Tracking stopped"), symbol: "scope")
        } catch {
            showNotice(L("Couldn't follow it: \(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill")
        }
    }
}

/// A thread-safe flag (the tracker reads it off the main thread).
final class VideoAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

extension CGRect {
    /// Inside 0…1 both ways (keeps its size where it can).
    var clampedToUnit: CGRect {
        let w = min(max(width, 0.02), 1), h = min(max(height, 0.02), 1)
        return CGRect(x: min(max(minX, 0), 1 - w), y: min(max(minY, 0), 1 - h), width: w, height: h)
    }
}

// MARK: - Properties ▸ Tracking

struct VideoMotionTrackingSection: View {
    @ObservedObject var model: VideoEditorModel
    let item: VideoLayerItem

    var body: some View {
        VideoInspectorSection(L("Tracking")) {
            if let state = model.motionTracking, state.item == item.id {
                if let progress = state.progress {
                    ProgressView(value: progress)
                    Button(L("Stop")) { model.cancelMotionTracking() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                } else {
                    Text(L("Drag the box on the player over what the clip should follow, then click Start. It follows from the playhead to the clip's end."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    VideoSliderRow(title: L("Box size"), value: Binding(get: { state.region.width * 100 }, set: { value in
                        guard var region = model.motionTracking?.region else { return }
                        let canvas = model.project.canvasSize()
                        let w = value / 100, h = w * canvas.width / max(canvas.height, 1)
                        region = CGRect(x: region.midX - w / 2, y: region.midY - h / 2, width: w, height: h).clampedToUnit
                        model.motionTracking?.region = region
                    }), range: 4...60, defaultValue: 15, format: { "\(Int($0))%" }) // l10n-ignore: a number
                    HStack(spacing: 8) {
                        Button(L("Cancel")) { model.cancelMotionTracking() }
                            .buttonStyle(VideoSecondaryButtonStyle())
                        Button {
                            model.selection = .layer(item.id)
                            model.perform(.edit(.trackMotion(state.region)))
                        } label: {
                            Label(L("Start"), systemImage: "scope").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(VideoSecondaryButtonStyle())
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        model.beginMotionTracking(item.id)
                    } label: {
                        Label(L("Track"), systemImage: "scope").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .help(L("Makes this clip follow something that moves in the video"))
                    if item.tracking != nil {
                        Button {
                            model.selection = .layer(item.id)
                            model.perform(.edit(.clearTracking))
                        } label: {
                            Label(L("Stop following"), systemImage: "xmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(VideoSecondaryButtonStyle())
                    }
                }
            }
        }
    }
}

/// The box picked to follow, on the player (drag to move it).
struct VideoMotionTrackingBox: View {
    @ObservedObject var model: VideoEditorModel
    let region: CGRect
    let viewSize: CGSize
    @State private var origin: CGRect?

    var body: some View {
        let rect = CGRect(x: region.minX * viewSize.width, y: region.minY * viewSize.height, width: region.width * viewSize.width, height: region.height * viewSize.height)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(Color.yellow)
                .background(Color.yellow.opacity(0.08))
                .overlay(Image(systemName: "scope").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.yellow))
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
                .offset(x: rect.minX, y: rect.minY)
                .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                    if origin == nil { origin = region }
                    guard let origin else { return }
                    model.motionTracking?.region = origin.offsetBy(dx: value.translation.width / max(viewSize.width, 1), dy: value.translation.height / max(viewSize.height, 1)).clampedToUnit
                }.onEnded { _ in origin = nil })
                .help(L("What the clip follows: drag it over the thing that moves"))
                .accessibilityLabel(L("Tracking box"))
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
    }
}
