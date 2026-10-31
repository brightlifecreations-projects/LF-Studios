import AppKit
import SwiftUI

// MARK: - The tracks above the main track on the timeline (1.14.0)

/// One track above the main track: a block per item. Drag a block to
/// another time or track (above the top one makes a new track), its ends
/// to trim it, ⌥-drag inside a video to slip it; click to select it.
struct VideoLayerLane: View, Equatable {
    let track: VideoLayerTrack
    let index: Int
    /// Where each track above the main track starts (their rows), lowest
    /// track first, to tell which one a block is dragged onto.
    let rowTops: [CGFloat]
    let selected: Set<UUID>
    let geometry: VideoTimelineGeometry
    let model: VideoEditorModel
    let hover: VideoTimelineHover

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.track == b.track && a.index == b.index && a.rowTops == b.rowTops && a.selected == b.selected && a.geometry == b.geometry
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(track.items) { item in
                VideoLayerBlock(item: item, trackIndex: index, rowTops: rowTops, isSelected: selected.contains(item.id), geometry: geometry, model: model, hover: hover)
            }
        }
        .frame(width: geometry.width, height: VideoTimelineMetrics.layerLaneHeight, alignment: .topLeading)
    }
}

private struct VideoLayerBlock: View {
    let item: VideoLayerItem
    let trackIndex: Int
    let rowTops: [CGFloat]
    let isSelected: Bool
    let geometry: VideoTimelineGeometry
    let model: VideoEditorModel
    let hover: VideoTimelineHover

    @State private var move: CGSize = .zero
    @State private var trim: (leading: Bool, width: CGFloat)?
    @State private var snapper: VideoTimelineSnapper?
    @State private var slipping = false
    @State private var thumbnail: NSImage?

    private typealias M = VideoTimelineMetrics

    var body: some View {
        let x = geometry.x(item.at)
        let width = max(CGFloat(item.length) * geometry.pointsPerSecond, 8)
        let leading = trim?.leading == true ? trim!.width : 0
        let trailing = trim?.leading == false ? trim!.width : 0
        let tint = VideoEditorTheme.layer
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(item.enabled ? 0.28 : 0.1))
            if let thumbnail, width > 30 {
                // The first frame (or the picture), repeated along the block.
                GeometryReader { box in
                    let tile = max(box.size.height * 16 / 9, 20)
                    HStack(spacing: 0) {
                        ForEach(0..<max(Int(ceil(box.size.width / tile)), 1), id: \.self) { _ in
                            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill).frame(width: tile, height: box.size.height).clipped()
                        }
                    }
                    .frame(width: box.size.width, alignment: .leading)
                    .clipped()
                }
                .opacity(item.enabled ? 0.55 : 0.2)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if width > 50 {
                HStack(spacing: 4) {
                    Image(systemName: item.isText ? "textformat" : item.isVideo ? "film" : "photo")
                        .font(.system(size: 9, weight: .bold))
                    Text(item.name)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    if !item.enabled {
                        Image(systemName: "eye.slash").font(.system(size: 9, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1.5)
                .padding(.horizontal, 7)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(isSelected ? Color.white : tint.opacity(0.75), lineWidth: isSelected ? 2 : 1))
        // Its keyframes, as diamonds along its bottom edge.
        .overlay(alignment: .bottomLeading) {
            if let times = item.keys?.times, !times.isEmpty {
                ZStack(alignment: .bottomLeading) {
                    ForEach(times, id: \.self) { time in
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1)
                            .offset(x: CGFloat(time) * geometry.pointsPerSecond - 3.5, y: -2)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .leading) { edge(leading: true) }
        .overlay(alignment: .trailing) { edge(leading: false) }
        .frame(width: max(width - leading + trailing, 8), height: M.layerLaneHeight)
        .offset(x: x + (slipping ? 0 : move.width) + leading, y: move.height)
        .zIndex(move == .zero ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { model.click(.layer(item.id)) }
        .gesture(moveGesture)
        .task(id: item.path) {
            guard !item.isText else { return }
            thumbnail = await VideoMediaThumbnails.shared.image(item.path, kind: item.kind, frame: nil)
        }
        .help(L("“\(item.name)” — drag to move it in time or to another track, drag an end to trim, ⌥-drag a video to slip it"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityDescription(of: .layer(item.id)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selection = .layer(item.id) }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if snapper == nil {
                    snapper = VideoTimelineSnapper(targets: model.snapTargets(excluding: [item.id]), pointsPerSecond: geometry.pointsPerSecond)
                    slipping = item.isVideo && NSEvent.modifierFlags.contains(.option)
                    hover.setDragging(true)
                    if !model.isSelected(.layer(item.id)) { model.selection = .layer(item.id) }
                }
                if slipping {
                    move = CGSize(width: value.translation.width, height: 0)
                    let shift = -Double(value.translation.width / geometry.pointsPerSecond) * item.normalizedSpeed
                    model.setLayerItem(item.id, coalesce: "layer-slip-\(item.id)", label: "Slip Clip") { slipped in
                        slipped.fileStart = min(max(item.fileStart + shift, 0), max(item.fileDuration - item.fileLength, 0))
                    }
                    return
                }
                let raw = max(item.at + Double(value.translation.width / geometry.pointsPerSecond), 0)
                let shift = snapper?.shift(start: raw, end: raw + item.length)
                hover.setSnap(shift?.target)
                let start = max(raw + (shift?.delta ?? 0), 0)
                move = CGSize(width: CGFloat(start - item.at) * geometry.pointsPerSecond, height: value.translation.height)
            }
            .onEnded { value in
                defer {
                    move = .zero
                    snapper = nil
                    slipping = false
                    hover.setDragging(false)
                }
                if slipping {
                    model.endGesture()
                    return
                }
                let start = item.at + Double(move.width / geometry.pointsPerSecond)
                let target = Self.target(fromTrack: trackIndex, rowTops: rowTops, dy: value.translation.height)
                if abs(start - item.at) < 0.0005, target.track == trackIndex, !target.newTrack { return }
                model.moveLayerItem(item.id, to: start, track: target.track, newTrack: target.newTrack)
                model.endGesture()
            }
    }

    /// The track a block dragged `dy` points lands on: the row under its
    /// middle; above the top track, a new track on top.
    static func target(fromTrack index: Int, rowTops: [CGFloat], dy: CGFloat) -> (track: Int, newTrack: Bool) {
        guard rowTops.indices.contains(index) else { return (index, false) }
        let middle = rowTops[index] + dy + M.layerLaneHeight / 2
        // Rows run top to bottom on screen; the highest track has the smallest top.
        if let top = rowTops.min(), middle < top - 4 { return (rowTops.count, true) }
        var best = index
        var distance = CGFloat.infinity
        for (track, rowTop) in rowTops.enumerated() {
            let gap = abs(rowTop + M.layerLaneHeight / 2 - middle)
            if gap < distance { distance = gap; best = track }
        }
        return (best, false)
    }

    private func edge(leading: Bool) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: 7)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if snapper == nil {
                            snapper = VideoTimelineSnapper(targets: model.snapTargets(excluding: [item.id]), pointsPerSecond: geometry.pointsPerSecond)
                            hover.setDragging(true)
                        }
                        let raw = (leading ? item.at : item.end) + Double(value.translation.width / geometry.pointsPerSecond)
                        let snapped = snapper?.snap(raw) ?? (time: raw, target: nil)
                        hover.setSnap(snapped.target)
                        trim = (leading, CGFloat(snapped.time - (leading ? item.at : item.end)) * geometry.pointsPerSecond)
                    }
                    .onEnded { _ in
                        if let trim {
                            let time = (leading ? item.at : item.end) + Double(trim.width / geometry.pointsPerSecond)
                            model.trimLayerItem(item.id, leading: leading, to: time, coalesce: false)
                        }
                        trim = nil
                        snapper = nil
                        hover.setDragging(false)
                    }
            )
    }
}

/// Over the lanes while the split tool (B) is on: a click splits the clip
/// under the pointer at that moment, on whichever track it is.
struct VideoSplitToolLayer: View {
    @ObservedObject var model: VideoEditorModel
    let rows: VideoTimelineRowLayout
    let time: (CGFloat) -> Double

    var body: some View {
        if model.timelineTool == .split {
            Color.white.opacity(0.001)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active = phase { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
                }
                .onTapGesture(coordinateSpace: .local) { location in
                    guard let row = rows.rows.first(where: { location.y >= $0.top && location.y < $0.top + $0.height }) else { return }
                    model.splitClicked(at: time(location.x), track: row.track)
                }
                .accessibilityHidden(true)
        }
    }
}
