import AppKit
import SwiftUI

// MARK: - Clip

struct VideoTimelineClipView: View, Equatable {
    let model: VideoEditorModel
    let segment: VideoDemoTimelineSegment
    let index: Int
    let pointsPerSecond: CGFloat
    let selected: Bool
    let thumbnails: [VideoTimelineThumbnail]
    let waveform: VideoWaveform?
    let sourceAspect: Double
    let hover: VideoTimelineHover
    /// The track height's scale when it was made: a new track height
    /// redraws it (its height comes from the metrics).
    var rowScale: CGFloat = VideoTimelineMetrics.rowScale

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.segment == b.segment && a.index == b.index && a.pointsPerSecond == b.pointsPerSecond && a.selected == b.selected
            && a.thumbnails.map(\.id) == b.thumbnails.map(\.id) && a.waveform?.peaks.count == b.waveform?.peaks.count && a.sourceAspect == b.sourceAspect
            && a.rowScale == b.rowScale
    }

    @State private var hovered = false
    @State private var trimOrigin: (leading: Bool, source: Double)?
    /// Dragging the clip by its name to another place in the video.
    @State private var reorderOffset: CGFloat?

    private typealias M = VideoTimelineMetrics

    var body: some View {
        let width = max(CGFloat(segment.duration) * pointsPerSecond - 2, 8)
        ZStack(alignment: .topLeading) {
            VideoClipFilmstrip(segment: segment, width: width, height: M.clipTrackHeight, thumbnails: thumbnails, waveform: waveform, sourceAspect: sourceAspect)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Amber identity bar along the bottom, like a film edge.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(VideoEditorTheme.clip)
                    .frame(height: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .allowsHitTesting(false)

            if width > 70 {
                HStack(spacing: 5) {
                    Text(L("Clip \(index + 1)"))
                        .font(.system(size: 10.5, weight: .bold))
                    Text(VideoEditorModel.format(segment.duration))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    if abs(segment.clip.normalizedSpeed - 1) > 0.01 {
                        Text(VideoEditorModel.formatScale(segment.clip.normalizedSpeed))
                            .font(.system(size: 9.5, weight: .heavy))
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                    }
                    if segment.clip.muted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(Capsule().fill(Color.black.opacity(reorderOffset == nil ? 0.62 : 0.85)))
                .contentShape(Capsule())
                .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
                .gesture(reorderGesture)
                .help(L("Drag to move this clip to another place in the video"))
                .padding(5)
            }

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.white : (hovered ? Color.white.opacity(0.35) : Color.white.opacity(0.12)), lineWidth: selected ? 2 : 1)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                trimHandle(leading: true)
                Spacer(minLength: 0)
                trimHandle(leading: false)
            }
        }
        .frame(width: width, height: M.clipTrackHeight)
        // Its zoom keyframes (a zoom cut), as diamonds along its bottom edge.
        .overlay(alignment: .bottomLeading) {
            if let times = segment.clip.keys?.times, !times.isEmpty {
                ZStack(alignment: .bottomLeading) {
                    ForEach(times, id: \.self) { time in
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1)
                            .offset(x: CGFloat(time) * pointsPerSecond - 3.5, y: -2)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovered = inside
            hover.setTrim(inside && model.timelineTool == .trim ? .slide : nil)
        }
        .gesture(scrubGesture)
        .contextMenu { clipMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VideoEditorModel.spokenClip(index: index, segment: segment))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selectClip(segment.id) }
        .accessibilityAction(named: L("Split at Playhead")) { model.splitAtPlayhead() }
        .accessibilityAction(named: L("Move Earlier")) { model.moveClip(segment.id, toIndex: index - 1) }
        .accessibilityAction(named: L("Move Later")) { model.moveClip(segment.id, toIndex: index + 1) }
        .accessibilityAction(named: L("Delete")) { model.deleteClip(segment.id) }
        .offset(x: reorderOffset ?? 0)
        .opacity(reorderOffset == nil ? 1 : 0.85)
        .shadow(color: .black.opacity(reorderOffset == nil ? 0 : 0.6), radius: 10, y: 4)
    }

    /// Where the dragged clip would land: the number of other clips whose
    /// middle is before its middle.
    private func reorderTarget(offset: CGFloat) -> (index: Int, boundary: Double) {
        let center = segment.timelineStart + segment.duration / 2 + Double(offset / pointsPerSecond)
        let others = model.segments.filter { $0.id != segment.id }
        let index = others.filter { $0.timelineStart + $0.duration / 2 < center }.count
        let boundary = index < others.count ? others[index].timelineStart : (others.last?.timelineEnd ?? 0)
        return (index, boundary)
    }

    /// Drag a clip by its name to put it somewhere else in the video.
    private var reorderGesture: some Gesture {
        // Global space: the clip moves under the pointer.
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if reorderOffset == nil {
                    model.pause()
                    hover.setDragging(true)
                }
                NSCursor.closedHand.set()
                reorderOffset = value.translation.width
                hover.setSnap(reorderTarget(offset: value.translation.width).boundary)
            }
            .onEnded { value in
                let target = reorderTarget(offset: value.translation.width)
                reorderOffset = nil
                hover.setDragging(false)
                model.moveClip(segment.id, toIndex: target.index)
                NSCursor.openHand.set()
            }
    }

    @State private var rangeAnchor: Double?

    private func timelineTime(_ localX: CGFloat) -> Double {
        min(max(segment.timelineStart + Double(localX / pointsPerSecond), 0), model.timelineDuration)
    }

    @State private var slideOrigin: Double?

    /// Drag scrubs; ⇧-drag marks a range to delete; a click selects (⇧- or
    /// ⌘-click adds the clip to the selection, or takes it out). With the
    /// Trim tool (1.21.0), a drag slides the clip between its neighbours.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if slideOrigin != nil || (model.timelineTool == .trim && abs(value.translation.width) > 2) {
                    if slideOrigin == nil {
                        slideOrigin = segment.timelineStart
                        model.pause()
                        model.selectClip(segment.id)
                    }
                    let current = model.segments.first { $0.id == segment.id }?.timelineStart ?? segment.timelineStart
                    let target = (slideOrigin ?? 0) + Double(value.translation.width / pointsPerSecond)
                    model.slide(clip: segment.id, by: target - current, coalesce: true)
                    return
                }
                let time = timelineTime(value.location.x)
                if NSEvent.modifierFlags.contains(.shift) || rangeAnchor != nil {
                    // Not a range until it moves: a ⇧-click picks the clip.
                    if rangeAnchor == nil, abs(value.translation.width) < 3 { return }
                    if rangeAnchor == nil { rangeAnchor = timelineTime(value.startLocation.x) }
                    if let rangeAnchor {
                        model.selection = .range(VideoDemoTimelineRange(start: rangeAnchor, end: time).normalized)
                    }
                } else if !NSEvent.modifierFlags.contains(.command) {
                    model.seek(to: time, fast: true)
                }
            }
            .onEnded { value in
                if slideOrigin != nil {
                    slideOrigin = nil
                    model.endRollOrSlide()
                    return
                }
                if rangeAnchor == nil {
                    if abs(value.translation.width) < 3, VideoEditorModel.extendsSelection {
                        model.toggleSelection(.clip(segment.id))
                    } else {
                        model.seek(to: timelineTime(value.location.x), fast: false)
                        if abs(value.translation.width) < 3 {
                            model.selectClip(segment.id)
                        }
                    }
                } else if case .range(let range) = model.selection, range.duration < 0.1 {
                    model.selection = .none
                }
                rangeAnchor = nil
            }
    }

    private func trimHandle(leading: Bool) -> some View {
        let emphasized = hovered || selected || trimOrigin?.leading == leading
        return ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(emphasized ? Color.white : Color.white.opacity(0.35))
                .frame(width: emphasized ? 5 : 3, height: emphasized ? 30 : 20)
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .frame(width: 14, height: M.clipTrackHeight)
        .contentShape(Rectangle())
        .onHover { inside in
            (inside ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            hover.setTrim(inside ? .ripple : nil)
        }
        .highPriorityGesture(
            // Global space: the trailing handle moves with the pointer.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if trimOrigin?.leading != leading {
                        trimOrigin = (leading, leading ? segment.clip.sourceStart : segment.clip.sourceEnd)
                        model.pause()
                        model.selectClip(segment.id)
                    }
                    guard let origin = trimOrigin else { return }
                    let deltaSource = Double(value.translation.width / pointsPerSecond) * segment.clip.normalizedSpeed
                    model.trimClip(segment.id, leading: leading, toSource: origin.source + deltaSource)
                }
                .onEnded { _ in
                    trimOrigin = nil
                    model.endTrim(segment.id, leading: leading)
                }
        )
        .help(leading ? L("Drag to change where this clip starts") : L("Drag to change where this clip ends"))
    }

    @ViewBuilder
    private var clipMenu: some View {
        Button(L("Split at Playhead")) {
            model.splitAtPlayhead()
        }
        Menu(L("Speed")) {
            ForEach([0.5, 1, 1.5, 2, 3, 4, 8, 16], id: \.self) { speed in
                Button {
                    model.setClipSpeed(segment.id, speed)
                    model.endGesture()
                } label: {
                    if abs(segment.clip.normalizedSpeed - speed) < 0.01 {
                        Label(VideoEditorModel.formatScale(speed), systemImage: "checkmark")
                    } else {
                        Text(VideoEditorModel.formatScale(speed))
                    }
                }
            }
        }
        Button(segment.clip.muted ? L("Unmute Clip") : L("Mute Clip")) {
            model.setClipMuted(segment.id, !segment.clip.muted)
        }
        Button(L("Move Earlier")) { model.moveClip(segment.id, toIndex: index - 1) }
            .disabled(index == 0)
        Button(L("Move Later")) { model.moveClip(segment.id, toIndex: index + 1) }
            .disabled(index >= model.segments.count - 1)
        Divider()
        Button(L("Delete Clip"), role: .destructive) {
            model.deleteClip(segment.id)
        }
        .disabled(model.segments.count <= 1)
    }
}

/// Thumbnails for the clip's source range, plus its waveform.
struct VideoClipFilmstrip: View {
    let segment: VideoDemoTimelineSegment
    let width: CGFloat
    let height: CGFloat
    let thumbnails: [VideoTimelineThumbnail]
    let waveform: VideoWaveform?
    let sourceAspect: Double

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.16)))
            let aspect = sourceAspect
            // LF Studios layout: the pictures above the sound strip.
            let pictures = VideoEditorStyle.current.isNew && waveform != nil ? size.height - min(18, size.height * 0.3) : size.height
            let tileWidth = max(pictures * CGFloat(aspect), 20)
            if !thumbnails.isEmpty {
                var x: CGFloat = 0
                while x < size.width {
                    let fraction = Double((x + tileWidth / 2) / max(size.width, 1))
                    let sourceTime = segment.clip.sourceStart + segment.clip.sourceDuration * min(max(fraction, 0), 1)
                    let nearest = thumbnails.min { abs($0.time - sourceTime) < abs($1.time - sourceTime) }
                    if let nearest {
                        context.draw(Image(nsImage: nearest.image), in: CGRect(x: x, y: 0, width: tileWidth, height: pictures))
                    }
                    x += tileWidth
                }
            }
            // LF Studios layout (1.17.0): the sound as its own strip under
            // the pictures.
            if VideoEditorStyle.current.isNew, let waveform {
                let strip = min(18, size.height * 0.3)
                let band = CGRect(x: 0, y: size.height - strip, width: size.width, height: strip)
                context.fill(Path(band), with: .color(Color(red: 0.05, green: 0.16, blue: 0.13)))
                let middle = band.midY
                var path = Path()
                var x: CGFloat = 1
                while x < size.width - 1 {
                    let a = segment.clip.sourceStart + segment.clip.sourceDuration * Double(x / size.width)
                    let b = segment.clip.sourceStart + segment.clip.sourceDuration * Double((x + 2) / size.width)
                    let h = max(CGFloat(waveform.peak(from: a, to: b)) * (strip - 4), 1)
                    path.addRect(CGRect(x: x, y: middle - h / 2, width: 1.5, height: h))
                    x += 2
                }
                context.fill(path, with: .color(segment.clip.muted ? Color.white.opacity(0.25) : Color(red: 0.2, green: 0.83, blue: 0.6)))
            } else if let waveform {
                let barWidth: CGFloat = 2
                let spacing: CGFloat = 1
                let baseline = size.height - 3
                let maxHeight = size.height * 0.42
                var path = Path()
                var x: CGFloat = 2
                while x < size.width - 2 {
                    let a = segment.clip.sourceStart + segment.clip.sourceDuration * Double(x / size.width)
                    let b = segment.clip.sourceStart + segment.clip.sourceDuration * Double((x + barWidth + spacing) / size.width)
                    let peak = CGFloat(waveform.peak(from: a, to: b))
                    let h = max(peak * maxHeight, 1)
                    path.addRoundedRect(in: CGRect(x: x, y: baseline - h, width: barWidth, height: h), cornerSize: CGSize(width: 1, height: 1))
                    x += barWidth + spacing
                }
                context.fill(path, with: .color(segment.clip.muted ? Color.white.opacity(0.25) : Color.white.opacity(0.78)))
            }
        }
        .frame(width: width, height: height)
    }
}
