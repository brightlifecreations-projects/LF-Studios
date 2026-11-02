import AVFoundation
import SwiftUI

// MARK: - A video's sound on its own track (1.18.0)

/// The timeline shows a video's sound as its own track under it, like other
/// editors: the recording's microphone and the Mac's sound each on one,
/// and the videos on a track above the main track on one under that track.
/// It's worked out from the clips, nothing more is kept: trimming,
/// splitting, moving or deleting a clip does the same to its sound, and
/// projects play and export exactly as before. Unlink audio (a clip's
/// `audioOffset`) lets the main track's sound move on its own.
extension VideoWaveform {
    /// Peaks of `url`'s sound: one of its sound tracks (`trackIndex`), or
    /// all of them mixed (nil).
    static func peaks(url: URL, trackIndex: Int?) async -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let all = try? await asset.loadTracks(withMediaType: .audio), !all.isEmpty else { return nil }
        let tracks: [AVAssetTrack]
        if let trackIndex {
            guard all.indices.contains(trackIndex) else { return nil }
            tracks = [all[trackIndex]]
        } else {
            tracks = all
        }
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 8_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        let perBucket = Int(8_000 / bucketsPerSecond)
        var peaks: [Float] = []
        var current: Float = 0
        var counted = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr, let pointer else { continue }
            let count = length / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: count) { floats in
                for i in 0..<count {
                    current = max(current, abs(floats[i]))
                    counted += 1
                    if counted >= perBucket {
                        peaks.append(current)
                        current = 0
                        counted = 0
                    }
                }
            }
        }
        if counted > 0 { peaks.append(current) }
        return peaks
    }
}

extension VideoEditorModel {
    /// The sound rows the timeline shows.
    var timelineSoundRows: VideoTimelineSoundRows {
        var rows = VideoTimelineSoundRows()
        if hasAudio { rows.kinds = audioKinds.isEmpty ? [.mixed] : audioKinds }
        for track in project.layerTracks where track.items.contains(where: { $0.isVideo && media.layerFiles[$0.path]?.audio != nil }) {
            rows.layers.insert(track.id)
        }
        return rows
    }

    /// Each of the recording's sound tracks on its own (in the background).
    func loadSoundWaveforms() async {
        let url = project.sourceURL
        let count = max(audioKinds.count, hasAudio ? 1 : 0)
        guard count > 0 else { return }
        var loaded: [Int: VideoWaveform] = [:]
        for index in 0..<count {
            let one = audioKinds.count > 1 ? index : nil
            if let peaks = await Task.detached(priority: .utility, operation: { await VideoWaveform.peaks(url: url, trackIndex: one) }).value {
                loaded[index] = VideoWaveform(peaks: peaks)
            }
        }
        soundWaveforms = loaded
    }

    /// The sound of the videos above the main track that have some.
    func loadLayerSoundWaveforms() async {
        for path in project.layerVideoPaths where layerSoundWaveforms[path] == nil && media.layerFiles[path]?.audio != nil {
            let url = URL(fileURLWithPath: path)
            if let peaks = await Task.detached(priority: .utility, operation: { await VideoWaveform.peaks(url: url, trackIndex: nil) }).value {
                layerSoundWaveforms[path] = VideoWaveform(peaks: peaks)
            }
        }
    }
}

/// A block of sound: its waveform across `width`, for `from…to` seconds of
/// the file.
private struct VideoSoundBlock: View {
    let waveform: VideoWaveform?
    let from: Double
    let to: Double
    let width: CGFloat
    let height: CGFloat
    let muted: Bool
    let unlinked: Bool
    let selected: Bool
    let name: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(red: 0.07, green: 0.3, blue: 0.24).opacity(muted ? 0.35 : 0.85))
            Canvas { context, size in
                guard let waveform, width > 4, to > from else { return }
                let middle = size.height / 2 + 4
                var path = Path()
                var x: CGFloat = 2
                while x < size.width - 2 {
                    let a = from + (to - from) * Double(x / size.width)
                    let b = from + (to - from) * Double((x + 2) / size.width)
                    let h = max(CGFloat(waveform.peak(from: a, to: b)) * (size.height - 14), 1)
                    path.addRect(CGRect(x: x, y: middle - h / 2, width: 1.5, height: h))
                    x += 2
                }
                context.fill(path, with: .color(muted ? Color.white.opacity(0.25) : Color(red: 0.36, green: 0.9, blue: 0.68)))
            }
            if width > 60 {
                HStack(spacing: 3) {
                    Image(systemName: unlinked ? "link.badge.plus" : "waveform")
                        .font(.system(size: 8, weight: .bold))
                    Text(name)
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.top, 2)
            }
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(selected ? Color.white : unlinked ? Color.orange.opacity(0.9) : Color.white.opacity(0.12),
                              style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: unlinked && !selected ? [4, 3] : []))
        )
    }
}

/// The main track's sound for one of the recording's sound tracks: a block
/// under each clip (moved by its offset when unlinked). Click: the clip;
/// drag an unlinked one to move it; right-click: Unlink or Link.
struct VideoClipSoundLane: View {
    let model: VideoEditorModel
    let index: Int
    let kind: VideoAudioKind
    let waveform: VideoWaveform?
    let geometry: VideoTimelineGeometry
    let segments: [VideoDemoTimelineSegment]
    let selected: Set<UUID>
    let muted: Bool
    @State private var dragStart: Double?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(segments) { segment in
                let offset = segment.clip.audioOffset ?? 0
                let x = geometry.x(segment.timelineStart + offset)
                let width = max(CGFloat(segment.duration) * geometry.pointsPerSecond - 2, 4)
                VideoSoundBlock(
                    waveform: waveform, from: segment.clip.sourceStart, to: segment.clip.sourceEnd,
                    width: width, height: VideoTimelineMetrics.soundLaneHeight - 2,
                    muted: muted || segment.clip.muted || segment.clip.disabled,
                    unlinked: segment.clip.audioOffset != nil,
                    selected: selected.contains(segment.id),
                    name: VideoTimelineTrack.clipSound(index, kind).title(in: model.project)
                )
                .offset(x: x + 1, y: 1)
                .onTapGesture { model.click(.clip(segment.id)) }
                .gesture(moveGesture(segment), including: segment.clip.audioOffset != nil ? .all : .none)
                .contextMenu { menu(segment) }
                .help(segment.clip.audioOffset != nil ? L("Unlinked sound: drag to move it") : L("Linked to its clip: trims, splits, moves and deletes with it"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Sound of clip \((segments.firstIndex { $0.id == segment.id } ?? 0) + 1)"))
            }
        }
        .frame(width: geometry.width, height: VideoTimelineMetrics.soundLaneHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func menu(_ segment: VideoDemoTimelineSegment) -> some View {
        if segment.clip.audioOffset == nil {
            Button(L("Unlink Audio")) {
                model.selection = .clip(segment.id)
                model.perform(.clip(.unlinkAudio))
            }
        } else {
            Button(L("Link Audio")) {
                model.selection = .clip(segment.id)
                model.perform(.clip(.linkAudio))
            }
        }
    }

    private func moveGesture(_ segment: VideoDemoTimelineSegment) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { drag in
                let start = dragStart ?? (segment.clip.audioOffset ?? 0)
                if dragStart == nil { dragStart = start }
                model.selection = .clip(segment.id)
                model.perform(.clip(.setAudioOffset(start + Double(drag.translation.width / max(geometry.pointsPerSecond, 0.001)))))
            }
            .onEnded { _ in
                dragStart = nil
                model.endGesture()
            }
    }
}

/// The sound of the videos on a track above the main track, under them.
/// Linked: click selects the video; it moves, trims and splits with it.
struct VideoLayerSoundLane: View {
    let model: VideoEditorModel
    let track: VideoLayerTrack
    let geometry: VideoTimelineGeometry
    let selected: Set<UUID>

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(track.items.filter(\.isVideo)) { item in
                let width = max(CGFloat(item.length) * geometry.pointsPerSecond - 2, 4)
                VideoSoundBlock(
                    waveform: model.layerSoundWaveforms[item.path],
                    from: item.fileStart, to: item.fileStart + item.length * item.normalizedSpeed,
                    width: width, height: VideoTimelineMetrics.soundLaneHeight - 2,
                    muted: !item.enabled || item.volume < 0.000_1 || model.project.trackState(.layer(track.id)).muted,
                    unlinked: false, selected: selected.contains(item.id), name: item.name
                )
                .offset(x: geometry.x(item.at) + 1, y: 1)
                .onTapGesture { model.click(.layer(item.id)) }
                .help(L("Linked to its video: moves, trims and splits with it"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Sound of \(item.name)"))
            }
        }
        .frame(width: geometry.width, height: VideoTimelineMetrics.soundLaneHeight, alignment: .topLeading)
    }
}
