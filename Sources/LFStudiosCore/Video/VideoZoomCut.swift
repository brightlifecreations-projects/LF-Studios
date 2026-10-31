import Foundation
import SwiftUI

// MARK: - Zoom cut (1.16.0)

/// A quick punch-in on the clip after a cut: the frame jumps in at the cut
/// and eases back out. It's ordinary zoom keyframes on that clip (Properties
/// ▸ Zoom), so it can be changed or removed like any other.
enum VideoZoomCut {
    static let scaleRange: ClosedRange<Double> = 1.05...2
    static let lengthRange: ClosedRange<Double> = 0.2...3
    static let defaultScale = 1.2
    static let defaultLength = 0.6

    /// In at the cut, back to 1 after `length` (shorter on a shorter clip).
    static func keys(scale: Double, length: Double, clipLength: Double, onto existing: VideoKeyframes? = nil) -> VideoKeyframes {
        let scale = min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
        let length = min(min(max(length, lengthRange.lowerBound), lengthRange.upperBound), max(clipLength, 0.05))
        var keys = existing ?? VideoKeyframes()
        keys.tracks[VideoKeyProperty.zoom.rawValue] = [
            VideoKey(time: 0, value: scale, easing: .easeInOut),
            VideoKey(time: length, value: 1),
        ]
        return keys
    }

    /// The clip a zoom cut goes on: the one starting at the cut nearest
    /// `time` (the first clip has no cut before it).
    static func clip(near time: Double, in segments: [VideoDemoTimelineSegment]) -> VideoDemoTimelineSegment? {
        segments.dropFirst().min { abs($0.timelineStart - time) < abs($1.timelineStart - time) }
    }
}

/// A main-track clip's zoom (the zoom cut's keyframes): its edits, each one
/// undo step, refused on a locked track.
enum VideoClipZoomEdit: Equatable {
    /// A zoom cut on the clip after the cut nearest the playhead.
    case zoomCut(scale: Double, length: Double)
    /// The zoom at the playhead (a key there).
    case setZoom(Double)
    /// A key at the playhead, or none.
    case toggleKey
    case setEasing(VideoEasing)
    /// No zoom on the clip any more.
    case clear

    var name: String {
        switch self {
        case .zoomCut(let s, let l): return "zoomCut.\(s).\(l)"
        case .setZoom(let z): return "setZoom.\(z)"
        case .toggleKey: return "toggleZoomKey"
        case .setEasing(let e): return "setZoomEasing.\(e.rawValue)"
        case .clear: return "clearZoom"
        }
    }

    var title: String {
        switch self {
        case .zoomCut: return L("Zoom cut")
        case .setZoom, .toggleKey, .setEasing: return L("Zoom")
        case .clear: return L("Remove Zoom")
        }
    }
}

extension VideoDemoTimelineClip {
    /// Its zoom at `local` seconds from its start (1: none).
    func zoom(at local: Double) -> Double {
        keys?.value(.zoom, at: local, base: 1) ?? 1
    }

    var hasZoom: Bool { keys?.isAnimated(.zoom) == true }
}

extension VideoEditorModel {
    @discardableResult
    func perform(_ edit: VideoClipZoomEdit) -> Bool {
        if refuseLocked(.clips) { return false }
        if case .zoomCut(let scale, let length) = edit {
            return addZoomCut(scale: scale, length: length)
        }
        guard let segment = targetClip else { return false }
        let local = min(max(clock.time - segment.timelineStart, 0), segment.duration)
        let id = segment.id
        func change(label: String, coalesce: String? = nil, _ body: (inout VideoKeyframes) -> Void) {
            mutate(coalesce: coalesce, label: label) { project in
                guard let index = project.timelineClips.firstIndex(where: { $0.id == id }) else { return }
                var keys = project.timelineClips[index].keys ?? VideoKeyframes()
                body(&keys)
                project.timelineClips[index].keys = keys.isEmpty ? nil : keys
            }
        }
        switch edit {
        case .zoomCut:
            return false
        case .setZoom(let value):
            let value = min(max(value, 1), VideoZoomCut.scaleRange.upperBound * 1.5)
            change(label: "Zoom Change", coalesce: "zoom-\(id)") { $0.set(.zoom, at: local, value: value) }
        case .toggleKey:
            if segment.clip.keys?.hasKey(.zoom, at: local) == true {
                change(label: "Remove Keyframe") { $0.remove(.zoom, at: local) }
            } else {
                let value = segment.clip.zoom(at: local)
                change(label: "Add Keyframe") { $0.set(.zoom, at: local, value: value) }
            }
        case .setEasing(let easing):
            guard segment.clip.keys?.hasKey(.zoom, at: local) == true else { return false }
            change(label: "Keyframe Easing") { $0.setEasing(easing, at: local) }
        case .clear:
            guard segment.clip.hasZoom else { return false }
            change(label: "Remove Zoom") { $0.tracks[VideoKeyProperty.zoom.rawValue] = nil }
        }
        return true
    }

    /// Zoom cut: on the clip after the cut nearest the playhead.
    func addZoomCut(scale: Double = Settings.videoZoomCutScale, length: Double = Settings.videoZoomCutLength) -> Bool {
        if refuseLocked(.clips) { return false }
        guard let segment = VideoZoomCut.clip(near: clock.time, in: segments) else {
            showNotice(L("Split the video first: a zoom cut goes on the clip after a cut"), symbol: "scissors")
            return false
        }
        let id = segment.id
        mutate(label: "Zoom Cut") { project in
            guard let index = project.timelineClips.firstIndex(where: { $0.id == id }) else { return }
            let clip = project.timelineClips[index]
            project.timelineClips[index].keys = VideoZoomCut.keys(scale: scale, length: length, clipLength: clip.outputDuration, onto: clip.keys)
        }
        selection = .clip(id)
        seek(to: segment.timelineStart)
        showNotice(L("Zoom cut added. Change it in Properties ▸ Zoom."), symbol: "arrow.up.left.and.arrow.down.right")
        return true
    }
}

// MARK: - The toolbar button

/// Zoom cut: click to add one; ⌄ sets how far and how long.
struct VideoZoomCutButton: View {
    @ObservedObject var model: VideoEditorModel
    @State private var showsOptions = false
    @State private var scale = Settings.videoZoomCutScale
    @State private var length = Settings.videoZoomCutLength

    var body: some View {
        HStack(spacing: 0) {
            Button {
                model.perform(.zoomCut)
            } label: {
                Image(systemName: VideoEditCommand.zoomCut.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(VideoToolButtonStyle())
            .help(L("\(VideoEditCommand.zoomCut.title) (\(VideoEditCommand.zoomCut.keys))") + " — " + L("a quick punch-in on the clip after the nearest cut"))
            .accessibilityLabel(VideoEditCommand.zoomCut.title)
            Button {
                showsOptions.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 12, height: 24)
            }
            .buttonStyle(VideoToolButtonStyle())
            .help(L("Zoom cut settings"))
            .accessibilityLabel(L("Zoom cut settings"))
            .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Zoom cut")).font(.system(size: 13, weight: .semibold))
                    VideoSliderRow(
                        title: L("Scale"),
                        value: Binding(get: { scale }, set: { scale = $0; Settings.videoZoomCutScale = $0 }),
                        range: VideoZoomCut.scaleRange, defaultValue: VideoZoomCut.defaultScale,
                        format: { "\(Int(($0 * 100).rounded())) %" }
                    )
                    VideoSliderRow(
                        title: L("Duration"),
                        value: Binding(get: { length }, set: { length = $0; Settings.videoZoomCutLength = $0 }),
                        range: VideoZoomCut.lengthRange, defaultValue: VideoZoomCut.defaultLength,
                        format: { String(format: "%.1f s", $0) }
                    )
                    Text(L("Jumps in at the cut, then eases back out. It's zoom keyframes on the clip: change or remove them in Properties ▸ Zoom."))
                        .font(.system(size: 11))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("Add Zoom Cut")) {
                        showsOptions = false
                        model.perform(.zoomCut)
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(14)
                .frame(width: 260)
            }
        }
    }
}

// MARK: - Properties ▸ Zoom (a main-track clip)

/// The clip's zoom at the playhead, with its ◆, ◀ ▶ and easing.
struct VideoClipZoomSection: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock
    let segment: VideoDemoTimelineSegment

    var body: some View {
        let clip = segment.clip
        let local = clock.time - segment.timelineStart
        let keys = clip.keys?.keys(.zoom) ?? []
        let atKey = clip.keys?.hasKey(.zoom, at: local) == true
        VideoInspectorSection(L("Zoom")) {
            HStack(alignment: .top, spacing: 6) {
                VideoSliderRow(
                    title: L("Zoom"),
                    value: Binding(get: { clip.zoom(at: local) * 100 }, set: { value in
                        model.selection = .clip(segment.id)
                        model.perform(.zoom(.setZoom(value / 100)))
                    }),
                    range: 100...300, defaultValue: 100,
                    format: { "\(Int($0.rounded())) %" },
                    onEditingEnded: { model.endGesture() }
                )
                Button {
                    model.selection = .clip(segment.id)
                    model.perform(.zoom(.toggleKey))
                } label: {
                    Image(systemName: atKey ? "diamond.fill" : "diamond")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(atKey || !keys.isEmpty ? VideoEditorTheme.layer : VideoEditorTheme.textTertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(atKey ? L("Remove the keyframe at the playhead") : L("Add a keyframe at the playhead: \(VideoKeyProperty.zoom.title)"))
                .accessibilityLabel(atKey ? L("Remove keyframe: \(VideoKeyProperty.zoom.title)") : L("Add keyframe: \(VideoKeyProperty.zoom.title)"))
            }
            if keys.isEmpty {
                Text(L("Zoom cut (⌥Z) punches in here at a cut. Or click ◆, move the playhead and change the zoom."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    Button { model.seek(to: segment.timelineStart + (keys.last { $0.time < local - 0.001 }?.time ?? 0)) } label: {
                        Image(systemName: "chevron.left").frame(width: 26, height: 24)
                    }
                    .buttonStyle(VideoToolButtonStyle())
                    .disabled(!keys.contains { $0.time < local - 0.001 })
                    .help(L("Previous keyframe"))
                    .accessibilityLabel(L("Previous keyframe"))
                    Button { model.seek(to: segment.timelineStart + (keys.first { $0.time > local + 0.001 }?.time ?? local)) } label: {
                        Image(systemName: "chevron.right").frame(width: 26, height: 24)
                    }
                    .buttonStyle(VideoToolButtonStyle())
                    .disabled(!keys.contains { $0.time > local + 0.001 })
                    .help(L("Next keyframe"))
                    .accessibilityLabel(L("Next keyframe"))
                    if let key = keys.first(where: { abs($0.time - local) < 1.0 / 120 }) {
                        Picker(L("Easing"), selection: Binding(get: { key.easing }, set: { model.perform(.zoom(.setEasing($0))) })) {
                            ForEach(VideoEasing.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: 150)
                    }
                    Spacer(minLength: 0)
                    Button(L("Remove Zoom")) { model.perform(.zoom(.clear)) }
                        .controlSize(.small)
                }
            }
        }
    }
}
