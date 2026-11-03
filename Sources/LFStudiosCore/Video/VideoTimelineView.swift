import AppKit
import SwiftUI

/// Layout of the timeline surface.
enum VideoTimelineMetrics {
    static let inset: CGFloat = 18
    static let rulerHeight: CGFloat = 24
    /// Track height (Small, Medium, Large): every lane grows with it.
    nonisolated(unsafe) static var rowScale: CGFloat = VideoTimelineTrackHeight.medium.scale
    static func scaled(_ height: CGFloat) -> CGFloat { (height * rowScale).rounded() }
    static var zoomTrackHeight: CGFloat { scaled(34) }
    static let clickLaneHeight: CGFloat = 14
    static var clipTrackHeight: CGFloat { scaled(66) }
    /// A video or picture track above the main track (1.14.0).
    static var layerLaneHeight: CGFloat { scaled(40) }
    /// A sound track under a video track (1.18.0).
    static var soundLaneHeight: CGFloat { scaled(34) }
    static var overlayLaneHeight: CGFloat { scaled(26) }
    static let overlayLaneGap: CGFloat = 4
    static var captionLaneHeight: CGFloat { scaled(22) }
    static var keysLaneHeight: CGFloat { scaled(18) }
    static var cameraLaneHeight: CGFloat { scaled(22) }
    static let gap: CGFloat = 7
    /// The track headers on the left.
    /// Wider in the LF Studios layout: its tracks' names and the curve
    /// switch, in German, Russian and Ukrainian too (1.17.0).
    static var headerWidth: CGFloat { VideoEditorStyle.current.isNew ? 236 : 204 }

    /// The annotation layers that get a lane, lowest first: one sitting
    /// wholly in a part that was cut away draws nothing and takes none.
    static func overlayLayers(_ project: VideoDemoProject) -> [Int] {
        let clips = project.timelineClips
        let shown = project.overlayEffects.filter { effect in
            clips.isEmpty || clips.contains { $0.sourceStart < effect.time + max(effect.duration, 0.1) && $0.sourceEnd > effect.time }
        }
        return Array(Set(shown.map { max($0.layer, 0) })).sorted()
    }

    static func overlayLanes(_ project: VideoDemoProject) -> Int {
        overlayLayers(project).count
    }

    /// The layer a pill dragged `lanes` lanes up (down when negative) from
    /// `layer` lands on, counting only the lanes on show.
    static func layer(movedFrom layer: Int, by lanes: Int, in layers: [Int]) -> Int {
        guard let index = layers.firstIndex(of: layer) else { return max(layer + lanes, 0) }
        let target = index + lanes
        if target < 0 { return max((layers.first ?? 0) - 1, 0) }
        if target < layers.count { return layers[target] }
        return (layers.last ?? 0) + (target - layers.count + 1)
    }

    /// The ruler and every track's row (VideoTimelineTracks.swift): what
    /// the timeline shows without scrolling up and down.
    static func contentHeight(_ project: VideoDemoProject) -> CGFloat {
        rulerHeight + 1 + VideoTimelineRowLayout(project: project, hasCamera: project.webcam.visible).height
    }
}

/// Redraws only when something on the timeline changes (see
/// `VideoTimelineState`); the toolbar follows the model on its own.
struct VideoTimelineView: View, Equatable {
    let model: VideoEditorModel
    @ObservedObject var timeline: VideoTimelineState

    init(model: VideoEditorModel) {
        self.model = model
        timeline = model.timelineState
    }

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.model === b.model
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoTimelineToolbar(model: model, clock: model.clock)
                .frame(height: 44)
            Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            // Inside a compound clip (1.16.0): where you are, and Back.
            VideoCompoundBreadcrumb(model: model)
            GeometryReader { proxy in
                VideoTimelineSurface(model: model, timeline: timeline, viewport: proxy.size)
            }
        }
        .background(VideoEditorTheme.panel)
    }
}

// MARK: - Surface

struct VideoTimelineSurface: View {
    let model: VideoEditorModel
    @ObservedObject var timeline: VideoTimelineState
    let viewport: CGSize

    /// Held, not observed: hovering redraws only the hover layer.
    @State private var hover = VideoTimelineHover()
    /// A box dragged over empty space (1.21.0).
    @State private var box = VideoTimelineBox()
    @State private var zoomDrag: (id: UUID, start: Double, end: Double)?
    @State private var overlayDrag: (id: UUID, start: Double, end: Double, layer: Int)?
    /// Where the dragged object was when the drag began. SwiftUI hands each
    /// update the freshly rendered closure, so computing from the object's
    /// CURRENT position would compound the movement — always start here.
    @State private var dragOrigin: TimelineDragOrigin?
    /// Where the dragged bar's edges can land, gathered when the drag began.
    @State private var snapper: VideoTimelineSnapper?
    /// The drag moves every selected bar (it began on one of several).
    @State private var movesGroup = false
    /// ⇧ or ⌘ was held when the press began: a click adds or removes.
    @State private var extending = false
    @State private var rangeStart: Double?
    @State private var pinchBase: Double?
    /// Anchored zooming, ⌘-scroll, and paging after the playhead.
    @State private var scroller = VideoTimelineScroller()
    /// Where the lanes are scrolled to (the ruler and headers follow).
    @State private var offsets = VideoTimelineScrollOffsets()

    private typealias M = VideoTimelineMetrics

    /// The main track, or further when something above it runs past its
    /// end (shown, so it can be moved back; the video ends with the main track).
    private var duration: Double { max(model.timelineDuration, model.layoutDurationLock ?? 0, model.project.layerItems.map(\.item.end).max() ?? 0, 0.1) }
    private var contentWidth: CGFloat { max(viewport.width - M.headerWidth - 1 - M.inset * 2, 100) * CGFloat(model.timelineZoom) }
    private var pointsPerSecond: CGFloat { contentWidth / CGFloat(duration) }

    private var geometry: VideoTimelineGeometry {
        VideoTimelineGeometry(pointsPerSecond: pointsPerSecond, duration: duration, width: contentWidth + M.inset * 2)
    }

    private func x(_ time: Double) -> CGFloat { M.inset + CGFloat(time) * pointsPerSecond }
    private func time(_ x: CGFloat) -> Double { min(max(Double((x - M.inset) / pointsPerSecond), 0), duration) }

    /// Every track's row (VideoTimelineTracks.swift), below the ruler.
    private var rows: VideoTimelineRowLayout {
        VideoTimelineRowLayout(project: model.project, hasCamera: model.hasWebcamFootage, curves: VideoEditorStyle.current.isNew ? Set(model.curveLanes.keys) : [], sound: model.timelineSoundRows)
    }
    /// Far above the lanes: a row that shows nothing.
    private static let nowhere: CGFloat = -10_000
    private var captionTop: CGFloat { rows.contentTop(.captions) ?? Self.nowhere }
    private var keysTop: CGFloat { rows.contentTop(.keys) ?? Self.nowhere }
    private var cameraLaneTop: CGFloat { rows.contentTop(.camera) ?? Self.nowhere }
    private var overlayTop: CGFloat { rows.contentTop(.annotations) ?? Self.nowhere }
    private var zoomTop: CGFloat { rows.contentTop(.zooms) ?? 0 }
    private var clickTop: CGFloat { rows.contentTop(.clips) ?? 0 }
    private var clipTop: CGFloat { clickTop + (model.project.clickEvents.isEmpty ? 0 : M.clickLaneHeight + 3) }

    private func shows(_ track: VideoTimelineTrack) -> Bool { rows.row(track)?.showsContent ?? false }

    /// Lane `layer` sits higher the higher its layer (and draws in front);
    /// only the layers on show count.
    private func laneY(_ layer: Int, in layers: [Int]) -> CGFloat {
        let index = layers.firstIndex(of: layer) ?? layers.filter { $0 < layer }.count
        return CGFloat(max(layers.count - 1 - index, 0)) * (M.overlayLaneHeight + M.overlayLaneGap)
    }

    /// A moved bar, from where it was when the drag began, landing an edge
    /// on anything within reach.
    private func movedWindow(_ origin: TimelineDragOrigin, by translation: CGFloat) -> (start: Double, end: Double) {
        let length = origin.end - origin.start
        let raw = min(max(origin.start + Double(translation / pointsPerSecond), 0), max(duration - length, 0))
        let shift = snapper?.shift(start: raw, end: raw + length)
        hover.setSnap(shift?.target)
        let start = min(max(raw + (shift?.delta ?? 0), 0), max(duration - length, 0))
        return (start, start + length)
    }

    /// A dragged edge, landing on anything within reach.
    private func snappedEdge(_ time: Double) -> Double {
        guard let snapped = snapper?.snap(time) else { return time }
        hover.setSnap(snapped.target)
        return snapped.time
    }

    /// The lanes scroll both ways; the ruler follows them across and the
    /// track headers up and down (VideoTimelineScroller.swift).
    var body: some View {
        let rows = self.rows
        let lanesViewport = CGSize(width: max(viewport.width - M.headerWidth - 1, 100), height: max(viewport.height - M.rulerHeight - 1, 40))
        let height = max(rows.height, lanesViewport.height)
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VideoTimelineHeaderCorner(model: model)
                    .frame(height: M.rulerHeight)
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                // Drawn over the space it's given: all the rows never stretch it.
                Color.clear
                    .overlay(alignment: .topLeading) {
                        VideoTimelineTrackHeaders(model: model, rows: rows, offsets: offsets)
                    }
                    .clipped()
            }
            .frame(width: M.headerWidth)
            .background(VideoEditorTheme.panel)
            Rectangle().fill(VideoEditorTheme.hairline).frame(width: 1)
            VStack(spacing: 0) {
                rulerStrip
                    .frame(height: M.rulerHeight)
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                // Up and down outside, across inside (as before 1.11.0). The
                // tracks that don't fit get a scroll bar that always shows
                // (1.21.0; the system's shows only while scrolling).
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: model.timelineZoom > 1.01) {
                            lanes(rows: rows, height: height)
                        }
                        .frame(height: height)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if height > lanesViewport.height + 0.5 {
                        VideoTimelineVerticalScrollbar(offsets: offsets, contentHeight: height, viewportHeight: lanesViewport.height, scroller: scroller)
                    }
                }
            }
            .coordinateSpace(name: "lanesArea")
            // The playhead's handle (1.18.0): over the ruler and the lanes,
            // never clipped by either; drag it to move the playhead.
            .overlay(alignment: .topLeading) {
                // An agent's Tacks, and its changes in review (1.19.0).
                VideoAgentTimelineMarks(model: model, offsets: offsets, x: { x($0) })
                VideoPlayheadHandle(model: model, clock: model.clock, offsets: offsets, x: { x($0) }, time: { time($0) }, width: lanesViewport.width)
            }
        }
        .onAppear {
            VideoTimelineBox.latest = box
            scroller.pointsPerSecond = pointsPerSecond
            scroller.offsets = offsets
            model.timelineViewportWidth = max(lanesViewport.width - M.inset * 2, 100)
        }
        .onChange(of: viewport.width) { width in
            model.timelineViewportWidth = max(width - M.headerWidth - 1 - M.inset * 2, 100)
        }
        .onChange(of: contentWidth) { _ in
            // A new scale: the moment under the pointer (or the playhead)
            // stays where it was once the strip has its new width.
            let anchor = scroller.anchor(playhead: model.clock.time)
            let scale = pointsPerSecond
            scroller.pointsPerSecond = scale
            DispatchQueue.main.async {
                scroller.restore(anchor, pointsPerSecond: scale)
                scroller.revealScrollers(force: true)
            }
        }
        .onChange(of: duration) { _ in scroller.pointsPerSecond = pointsPerSecond }
    }

    /// The ruler with the markers, following the lanes across.
    private var rulerStrip: some View {
        VideoTimelineRulerStrip(offsets: offsets) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(scrubGesture)
                VideoTimelineRuler(duration: duration, pointsPerSecond: pointsPerSecond, inset: M.inset)
                    .frame(width: contentWidth + M.inset * 2, height: M.rulerHeight)
                    .allowsHitTesting(false)
                if !model.project.markers.isEmpty {
                    VideoMarkerFlags(model: model, geometry: geometry, height: M.rulerHeight)
                }
            }
            .frame(width: contentWidth + M.inset * 2, height: M.rulerHeight, alignment: .topLeading)
        }
    }

    /// A track's lanes as the header says: dimmed while hidden, not to be
    /// touched while locked.
    private func trackLook<Content: View>(_ track: VideoTimelineTrack, @ViewBuilder _ content: () -> Content) -> some View {
        let state = model.project.trackState(track)
        // Inside an open compound only its clips (above the main track) can
        // be reached; the rest stays in view, dimmed.
        var outside = model.openCompound != nil
        if case .layer = track { outside = false }
        return content()
            .opacity(state.hidden ? 0.4 : outside ? 0.3 : 1)
            .allowsHitTesting(!state.locked && !outside)
    }

    private func lanes(rows: VideoTimelineRowLayout, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Files dropped on the timeline (from Finder or the Library)
            // land on the track and at the time under the pointer.
            Color.clear
                .onDrop(of: [.fileURL, .plainText], delegate: VideoMediaDrop(model: model) { location in
                    (max(geometry.time(location.x), 0), Self.dropTarget(atY: location.y, rows: rows, project: model.project))
                })
            // Empty space (1.21.0): a click moves the playhead, a drag
            // selects the clips in a box, a right-click closes gaps.
            Color.clear
                .contentShape(Rectangle())
                .gesture(emptySpaceGesture)
                .contextMenu { emptySpaceMenu }
            VideoTimelineRowBackgrounds(rows: rows, width: contentWidth + M.inset * 2, locked: Set(rows.rows.filter { model.project.isTrackLocked($0.track) }.map(\.track)))

            trackLook(.zooms) { zoomTrack }
            // The tracks above the main track (1.14.0).
            let compoundBlocks = VideoCompoundBlock.blocks(model.project).filter { $0.id != model.openCompound }
            let layerTops = model.project.layerTracks.map { rows.contentTop(.layer($0.id)) ?? rows.row(.layer($0.id))?.top ?? 0 }
            ForEach(Array(model.project.layerTracks.enumerated()), id: \.element.id) { index, track in
                if let top = rows.contentTop(.layer(track.id)) {
                    trackLook(.layer(track.id)) {
                        VideoLayerLane(
                            track: track,
                            index: index,
                            rowTops: layerTops,
                            selected: model.selectedIDs { if case .layer(let id) = $0 { return id } else { return nil } },
                            geometry: geometry,
                            model: model,
                            hover: hover,
                            compounds: compoundBlocks,
                            openCompound: model.openCompound
                        )
                        .equatable()
                        .offset(y: top)
                        // Its keyframe curve lane, when open (LF Studios layout).
                        if VideoEditorStyle.current.isNew, let property = model.curveLanes[track.id] {
                            VideoCurveLaneView(model: model, track: track, property: property, geometry: geometry)
                                .offset(y: top + VideoTimelineMetrics.layerLaneHeight + VideoCurveLane.gap)
                        }
                    }
                }
            }
            trackLook(.clips) {
                ZStack(alignment: .topLeading) {
                    if !model.project.clickEvents.isEmpty {
                        VideoClickLane(
                            items: model.project.clickEvents.compactMap { click in
                                model.timelineTime(forSource: click.time).map { VideoClickLane.Item(id: click.id, time: $0) }
                            },
                            selectedIDs: model.selectedIDs { if case .click(let id) = $0 { return id } else { return nil } },
                            geometry: geometry,
                            model: model,
                            hover: hover
                        )
                        .equatable()
                        .offset(y: clickTop)
                    }
                    clipTrack
                }
            }
            // The main track's sound, one row per sound track (1.18.0).
            let soundRows = model.timelineSoundRows
            ForEach(Array(soundRows.kinds.enumerated()), id: \.offset) { index, kind in
                if let top = rows.contentTop(.clipSound(index, kind)) {
                    trackLook(.clipSound(index, kind)) {
                        VideoClipSoundLane(
                            model: model, index: index, kind: kind,
                            waveform: model.soundWaveforms[index] ?? model.waveform,
                            geometry: geometry, segments: model.segments,
                            selected: model.selectedIDs { if case .clip(let id) = $0 { return id } else { return nil } },
                            muted: model.project.trackState(.clipSound(index, kind)).muted
                        )
                        .offset(y: top)
                    }
                }
            }
            // The sound of the videos above the main track.
            ForEach(model.project.layerTracks.filter { soundRows.layers.contains($0.id) }) { track in
                if let top = rows.contentTop(.layerSound(track.id)) {
                    trackLook(.layerSound(track.id)) {
                        VideoLayerSoundLane(
                            model: model, track: track, geometry: geometry,
                            selected: model.selectedIDs { if case .layer(let id) = $0 { return id } else { return nil } }
                        )
                        .offset(y: top)
                    }
                }
            }
            // Cards, cut markers and recording boundaries on the clips;
            // added camera video, music and sound files on their rows.
            VideoTimelineExtrasLayer(model: model, geometry: geometry, clipTop: clipTop, rows: rows)
            if shows(.annotations) { trackLook(.annotations) { overlayLanes } }
            if shows(.captions) {
                trackLook(.captions) {
                    VideoCaptionLane(
                        items: model.plan.captions.map { VideoCaptionLane.Item(id: $0.id, start: $0.start, end: $0.end, text: $0.text, hasOwnPlacement: $0.placement != nil) },
                        selectedIDs: model.selectedIDs { if case .caption(let id) = $0 { return id } else { return nil } },
                        geometry: geometry,
                        model: model,
                        hover: hover
                    )
                    .equatable()
                    .offset(y: captionTop)
                }
            }
            if shows(.keys) {
                trackLook(.keys) {
                    VideoKeysLane(
                        items: model.project.keystrokes.compactMap { event in
                            model.timelineTime(forSource: event.time).map { VideoKeysLane.Item(id: event.id, time: $0, label: event.keys.joined()) }
                        },
                        selectedIDs: model.selectedIDs { if case .keystroke(let id) = $0 { return id } else { return nil } },
                        hidden: !model.project.keystrokeStyle.visible,
                        geometry: geometry,
                        model: model
                    )
                    .equatable()
                    .offset(y: keysTop)
                }
            }
            if shows(.camera), !model.project.cameraLayouts.isEmpty, model.hasWebcamFootage {
                trackLook(.camera) {
                    VideoCameraLayoutLane(
                        items: model.cameraLayoutSpans.map { VideoCameraLayoutLane.Item(id: $0.region.id, start: $0.start, end: $0.end, layout: $0.region.layout) },
                        selectedIDs: model.selectedIDs { if case .cameraLayout(let id) = $0 { return id } else { return nil } },
                        geometry: geometry,
                        model: model,
                        hover: hover
                    )
                    .equatable()
                    .offset(y: cameraLaneTop)
                }
            }
            VideoTimelineRowHints(rows: rows, inset: M.inset, width: min(contentWidth, max(viewport.width - M.headerWidth - M.inset * 2, 100)))

            VideoTimelineHoverLayer(
                hover: hover,
                model: model,
                geometry: geometry,
                height: height,
                zoomTop: zoomTop,
                showsZoomHint: model.project.zoomRegions.isEmpty,
                viewportWidth: viewport.width - M.headerWidth,
                linesTop: 0
            )
            VideoTimelinePlayhead(clock: model.clock, x: { x($0) }, height: height, showsKnob: false)
            // The split tool (B): a click splits what's under it there.
            VideoSplitToolLayer(model: model, rows: rows, time: { time($0) })
            VideoTimelineBoxView(box: box)
            VideoTimelinePlayheadFollower(clock: model.clock, model: model, scroller: scroller, x: { x($0) })
        }
        .frame(width: contentWidth + M.inset * 2, height: height, alignment: .topLeading)
        .background(VideoTimelineScrollFinder(scroller: scroller, model: model))
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hover.update(time: time(location.x), overZoomTrack: location.y >= zoomTop && location.y <= zoomTop + M.zoomTrackHeight)
                model.timelinePointerTime = time(location.x)
                model.timelinePointerY = location.y
                scroller.pointerIsOver(true)
                // The preview axis (S): the player shows what's under the pointer.
                if !hover.dragging { model.previewAxis(at: time(location.x)) }
            case .ended:
                hover.update(time: nil, overZoomTrack: false)
                model.timelinePointerTime = nil
                model.timelinePointerY = nil
                scroller.pointerIsOver(false)
                model.previewAxis(at: nil)
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    if pinchBase == nil { pinchBase = model.timelineZoom }
                    // Pinching zooms around the skimmer, else the playhead.
                    model.timelineZoom = min(max((pinchBase ?? 1) * value, 1), model.maxTimelineZoom)
                }
                .onEnded { _ in pinchBase = nil }
        )
    }

    /// A drag over empty space selects what the box touches (⇧ adds, ⌘
    /// toggles); a click moves the playhead there, as before.
    private var emptySpaceGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let moved = hypot(value.translation.width, value.translation.height) > 4
                guard box.rect != nil || moved else { return }
                if box.rect == nil {
                    model.pause()
                    hover.setDragging(true)
                }
                box.rect = CGRect(x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y),
                                  width: abs(value.translation.width), height: abs(value.translation.height))
            }
            .onEnded { value in
                if let rect = box.rect {
                    let tracks = Set(rows.rows.filter { $0.top < rect.maxY && $0.top + $0.height > rect.minY }.map(\.track))
                    model.boxSelect(model.clips(from: time(rect.minX), to: time(rect.maxX), on: tracks), mode: .fromModifiers)
                    box.rect = nil
                    hover.setDragging(false)
                } else {
                    if model.selection != .none, !isRangeSelection, !VideoEditorModel.extendsSelection { model.selection = .none }
                    model.seek(to: time(value.location.x), fast: false)
                }
            }
    }

    /// Right-click on empty space: close the gap there, or every gap
    /// after the playhead.
    @ViewBuilder
    private var emptySpaceMenu: some View {
        let at = model.timelinePointerTime ?? model.clock.time
        let track = model.timelinePointerY.flatMap { y in rows.rows.first { y >= $0.top && y < $0.top + $0.height + VideoTimelineRowLayout.separator }?.track }
        let gap = track.flatMap { model.gap(on: $0, at: at) }
        Button(gap.map { L("Delete Gap (\(VideoEditorModel.format($0.length)))") } ?? L("Delete Gap")) {
            if let gap { model.perform(.basics(.deleteGap(track: gap.track, time: at))) }
        }
        .disabled(gap == nil)
        Button(L("Delete Gaps After Playhead")) { model.perform(.deleteGapsAfterPlayhead) }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let t = time(value.location.x)
                if NSEvent.modifierFlags.contains(.shift) {
                    if rangeStart == nil { rangeStart = time(value.startLocation.x) }
                    if let rangeStart {
                        model.selection = .range(VideoDemoTimelineRange(start: rangeStart, end: t).normalized)
                    }
                } else {
                    if value.translation == .zero, model.selection != .none, !isRangeSelection {
                        model.selection = .none
                    }
                    model.seek(to: t, fast: true)
                }
            }
            .onEnded { value in
                if rangeStart == nil {
                    model.seek(to: time(value.location.x), fast: false)
                } else if case .range(let range) = model.selection, range.duration < 0.1 {
                    // A ⇧-click, not a drag: nothing to cut.
                    model.selection = .none
                }
                rangeStart = nil
            }
    }

    /// The track under a drop: the main track, a track above it, a new
    /// track on top (over the highest one), or anywhere it fits.
    static func dropTarget(atY y: CGFloat, rows: VideoTimelineRowLayout, project: VideoDemoProject) -> VideoEditorModel.DropTarget {
        guard let row = rows.rows.first(where: { y >= $0.top && y < $0.top + $0.height + VideoTimelineRowLayout.separator }) else { return .anywhere }
        switch row.track {
        case .clips: return .main
        case .layer(let id): return .layer(project.layerTracks.firstIndex { $0.id == id }.map { .track($0) } ?? .automatic)
        case .zooms: return .layer(.newTrack(project.layerTracks.count))
        default: return .anywhere
        }
    }

    private var isRangeSelection: Bool {
        if case .range = model.selection { return true }
        return false
    }

    // MARK: Zoom track

    private var zoomTrack: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(VideoEditorTheme.ink.opacity(0.035))
                .frame(width: contentWidth, height: M.zoomTrackHeight)
                .offset(x: M.inset)
                .onTapGesture { location in
                    let at = time(location.x + M.inset)
                    if let id = model.addZoom(at: at),
                       let range = model.project.zoomRegions.first(where: { $0.id == id }).flatMap({ model.zoomTimelineRange($0) }) {
                        // Park inside the new zoom so the preview shows it.
                        model.seek(to: min(range.lowerBound + min(1.2, (range.upperBound - range.lowerBound) / 2), range.upperBound))
                        model.inspectorTab = .zoom
                    }
                }

            ForEach(model.project.zoomRegions) { region in
                if let range = model.zoomTimelineRange(region) {
                    zoomBlock(region, range: range)
                }
            }
        }
        .offset(y: zoomTop)
    }

    private func zoomBlock(_ region: VideoZoomRegion, range: ClosedRange<Double>) -> some View {
        let selected = model.isSelected(.zoom(region.id))
        let shown = zoomDrag?.id == region.id ? (zoomDrag!.start...zoomDrag!.end) : range
        let width = max(CGFloat(shown.upperBound - shown.lowerBound) * pointsPerSecond, 14)
        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [VideoEditorTheme.zoom, VideoEditorTheme.zoom.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                .opacity(selected ? 1 : 0.82)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.95 : 0.16), lineWidth: selected ? 1.5 : 1)
            if width > 44 {
                HStack(spacing: 4) {
                    Image(systemName: region.isLoupe ? "magnifyingglass.circle" : region.followsTyping ? "character.cursor.ibeam" : region.followsCursor ? "cursorarrow.motionlines" : "scope")
                        .font(.system(size: 9.5, weight: .bold))
                    Text(width > 80 ? (region.isLoupe ? L("\(VideoEditorModel.formatScale(region.scale)) Loupe") : L("\(VideoEditorModel.formatScale(region.scale)) Zoom")) : VideoEditorModel.formatScale(region.scale))
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        // The level stays whole; the tag after it gives way first.
                        .layoutPriority(1)
                    if width > 150 {
                        Text(region.followsTyping ? L("· follows typing") : region.followsCursor ? L("· follows cursor") : L("· aim by hand"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    if region.isAuto, width > 150 {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
            }
            HStack(spacing: 0) {
                edgeHandle
                    .gesture(zoomEdgeGesture(region, range: range, leading: true))
                Spacer(minLength: 0)
                edgeHandle
                    .gesture(zoomEdgeGesture(region, range: range, leading: false))
            }
        }
        .frame(width: width, height: M.zoomTrackHeight - 4)
        .shadow(color: selected ? VideoEditorTheme.zoom.opacity(0.5) : .clear, radius: 8)
        .contentShape(Rectangle())
        .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
        .gesture(zoomMoveGesture(region, range: range))
        .contextMenu { zoomMenu(region) }
        .offset(x: x(shown.lowerBound), y: 2)
        .help(L("Zoom — drag to move, drag an edge to resize, click to edit"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityDescription(of: .zoom(region.id)))
        .accessibilityHint(L("Adjust to move it half a second"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            model.selection = .zoom(region.id)
            model.inspectorTab = .zoom
        }
        .accessibilityAction(named: L("Delete")) { model.deleteZoom(region.id) }
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.5 : -0.5
            model.setZoomWindow(region.id, start: range.lowerBound + step, end: range.upperBound + step, coalesce: "zoom-nudge")
            model.endGesture()
        }
    }

    private var edgeHandle: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: 9)
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 2.5, height: 12)
            )
            .onHover { inside in (inside ? NSCursor.resizeLeftRight : NSCursor.openHand).set() }
    }

    private func zoomMoveGesture(_ region: VideoZoomRegion, range: ClosedRange<Double>) -> some Gesture {
        // Global space: the block moves under the pointer, so local
        // coordinates would lag behind it.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin?.id != region.id {
                    dragOrigin = TimelineDragOrigin(id: region.id, start: range.lowerBound, end: range.upperBound)
                    beginBarDrag(.zoom(region.id))
                    zoomDrag = (region.id, range.lowerBound, range.upperBound)
                    hover.setDragging(true)
                    if !movesGroup, !extending {
                        model.selection = .zoom(region.id)
                        if !region.followsCursor { model.pause() }
                    }
                }
                guard let origin = dragOrigin, abs(value.translation.width) > 2 else { return }
                NSCursor.closedHand.set()
                let moved = movedWindow(origin, by: value.translation.width)
                if movesGroup {
                    model.moveGroup(by: moved.start - origin.start)
                } else {
                    model.setZoomWindow(region.id, start: moved.start, end: moved.end, coalesce: "zoom-move-\(region.id)")
                }
                if let updated = model.project.zoomRegions.first(where: { $0.id == region.id }).flatMap({ model.zoomTimelineRange($0) }) {
                    zoomDrag = (region.id, updated.lowerBound, updated.upperBound)
                }
            }
            .onEnded { value in
                let origin = dragOrigin ?? TimelineDragOrigin(id: region.id, start: range.lowerBound, end: range.upperBound)
                let clicked = abs(value.translation.width) <= 2
                if !clicked {
                    let moved = movedWindow(origin, by: value.translation.width)
                    if movesGroup {
                        model.moveGroup(by: moved.start - origin.start)
                    } else {
                        model.setZoomWindow(region.id, start: moved.start, end: moved.end, coalesce: "zoom-move-\(region.id)")
                    }
                }
                let wasExtending = extending
                endBarDrag()
                zoomDrag = nil
                model.endGesture()
                if clicked {
                    if wasExtending {
                        model.toggleSelection(.zoom(region.id))
                    } else {
                        model.selection = .zoom(region.id)
                        model.inspectorTab = .zoom
                        if !(region.followsCursor) || !model.isPlaying {
                            // Show the zoom: park inside it once the camera arrived.
                            let target = min(origin.start + min(1.2, (origin.end - origin.start) / 2), origin.end)
                            model.seek(to: target)
                        }
                    }
                }
                NSCursor.openHand.set()
            }
    }

    /// A press on a bar begins: will a click add to the selection, and does
    /// a drag move the whole selection?
    private func beginBarDrag(_ item: VideoEditorModel.Selection) {
        extending = VideoEditorModel.extendsSelection
        movesGroup = !extending && model.movesAsGroup(item)
        let excluded = Set((movesGroup ? model.selectedItems : [item]).compactMap(\.itemID))
        snapper = VideoTimelineSnapper(targets: model.snapTargets(excluding: excluded), pointsPerSecond: pointsPerSecond)
        if movesGroup { model.beginGroupMove() }
    }

    private func endBarDrag() {
        if movesGroup { model.endGroupMove() }
        movesGroup = false
        extending = false
        dragOrigin = nil
        snapper = nil
        hover.setDragging(false)
    }

    private func zoomEdgeGesture(_ region: VideoZoomRegion, range: ClosedRange<Double>, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin?.id != region.id {
                    dragOrigin = TimelineDragOrigin(id: region.id, start: range.lowerBound, end: range.upperBound)
                    snapper = VideoTimelineSnapper(targets: model.snapTargets(excluding: [region.id]), pointsPerSecond: pointsPerSecond)
                    zoomDrag = (region.id, range.lowerBound, range.upperBound)
                    hover.setDragging(true)
                    model.selection = .zoom(region.id)
                }
                guard let origin = dragOrigin else { return }
                let (start, end) = zoomEdges(origin, leading: leading, by: value.translation.width)
                model.setZoomWindow(region.id, start: start, end: end, coalesce: "zoom-edge-\(region.id)")
                if let updated = model.project.zoomRegions.first(where: { $0.id == region.id }).flatMap({ model.zoomTimelineRange($0) }) {
                    zoomDrag = (region.id, updated.lowerBound, updated.upperBound)
                }
            }
            .onEnded { value in
                let origin = dragOrigin ?? TimelineDragOrigin(id: region.id, start: range.lowerBound, end: range.upperBound)
                let (start, end) = zoomEdges(origin, leading: leading, by: value.translation.width)
                model.setZoomWindow(region.id, start: start, end: end, coalesce: "zoom-edge-\(region.id)")
                zoomDrag = nil
                dragOrigin = nil
                snapper = nil
                hover.setDragging(false)
                model.endGesture()
            }
    }

    /// A zoom with one edge dragged (snapping), never shorter than a zoom
    /// can be.
    private func zoomEdges(_ origin: TimelineDragOrigin, leading: Bool, by translation: CGFloat) -> (Double, Double) {
        let delta = Double(translation / pointsPerSecond)
        if leading {
            return (min(snappedEdge(origin.start + delta), origin.end - VideoZoomRegion.minimumDuration), origin.end)
        }
        return (origin.start, max(snappedEdge(origin.end + delta), origin.start + VideoZoomRegion.minimumDuration))
    }

    @ViewBuilder
    private func zoomMenu(_ region: VideoZoomRegion) -> some View {
        Button(region.followsCursor || region.followsTyping ? L("Aim by Hand") : L("Follow Cursor")) {
            model.setZoomFollow(region.id, region.followsCursor || region.followsTyping ? .fixed : .pointer)
        }
        if model.hasTypingPositions, !region.followsTyping {
            Button(L("Follow Typing")) { model.setZoomFollow(region.id, .typing) }
        }
        Button(region.isLoupe ? L("Make Full Zoom") : L("Make Loupe")) {
            model.setZoomIsLoupe(region.id, !region.isLoupe)
        }
        Menu(L("Zoom Level")) {
            ForEach([1.25, 1.5, 2, 2.5, 3, 4], id: \.self) { scale in
                Button(VideoEditorModel.formatScale(scale)) {
                    model.updateZoom(region.id) { $0.scale = scale }
                }
            }
        }
        Button(L("Duplicate")) { model.duplicateZoom(region.id) }
        Divider()
        Button(L("Delete Zoom"), role: .destructive) { model.deleteZoom(region.id) }
    }

    // MARK: Clip track

    private var clipTrack: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.segments.enumerated()), id: \.element.id) { index, segment in
                VideoTimelineClipView(
                    model: model,
                    segment: segment,
                    index: index,
                    pointsPerSecond: pointsPerSecond,
                    selected: model.isSelected(.clip(segment.id)),
                    thumbnails: model.thumbnails,
                    // Its sound has a row of its own under it (1.18.0).
                    waveform: model.timelineSoundRows.kinds.isEmpty ? model.waveform : nil,
                    sourceAspect: model.project.sourceHeight > 0 ? model.project.sourceWidth / model.project.sourceHeight : 16 / 9,
                    hover: hover
                )
                .equatable()
                .offset(x: x(segment.timelineStart) + 1)
            }
            // Roll (1.21.0): drag a cut; the clips on both sides change.
            ForEach(Array(model.segments.dropLast().enumerated()), id: \.element.id) { _, segment in
                VideoRollHandle(model: model, hover: hover, clip: segment.id, cut: segment.timelineEnd, pointsPerSecond: pointsPerSecond, height: M.clipTrackHeight)
                    .offset(x: x(segment.timelineEnd) - VideoRollHandle.width / 2)
            }

            if case .range(let range) = model.selection {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.red.opacity(0.8), lineWidth: 1.5))
                    .frame(width: max(CGFloat(range.duration) * pointsPerSecond, 3), height: M.clipTrackHeight)
                    .offset(x: x(range.start))
                    .allowsHitTesting(false)
            }

            // Markers closer than a marker's width share one (Remove Ums can
            // leave dozens): it lists each cut and can restore them all.
            ForEach(VideoEditorModel.CutGap.grouped(model.cutGaps, within: 46 / pointsPerSecond), id: \.first!.id) { group in
                if group.count == 1, let gap = group.first {
                    Button {
                        model.restore(gap)
                    } label: {
                        restorePill(symbol: "scissors", text: VideoEditorModel.format(gap.duration))
                    }
                    .buttonStyle(.plain)
                    .help(L("Removed \(VideoEditorModel.format(gap.duration)) — click to restore"))
                    .accessibilityLabel(L("Restore \(VideoEditorModel.format(gap.duration)) cut at \(VideoEditorModel.timecode(gap.timelineTime))"))
                    .offset(x: x(gap.timelineTime) - 24, y: -9)
                } else {
                    let total = group.reduce(0) { $0 + $1.duration }
                    Menu {
                        ForEach(group) { gap in
                            Button(L("Restore \(VideoEditorModel.format(gap.duration)) at \(VideoEditorModel.timecode(gap.timelineTime))")) { model.restore(gap) }
                        }
                        Divider()
                        Button(L("Restore All \(group.count)")) { model.restore(group) }
                    } label: {
                        restorePill(symbol: "scissors", text: "\(group.count) · \(VideoEditorModel.format(total))")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("\(group.count) cuts here (\(VideoEditorModel.format(total)) removed) — click to restore some or all"))
                    .accessibilityLabel(L("\(group.count) cuts, \(VideoEditorModel.format(total)) removed"))
                    .offset(x: x(group.first?.timelineTime ?? 0) - 24, y: -9)
                }
            }
        }
        .offset(y: clipTop)
    }

    private func restorePill(symbol: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 9.5, weight: .bold))
        .foregroundStyle(Color.black.opacity(0.8))
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(Capsule().fill(Color(red: 1, green: 0.84, blue: 0.3)))
    }

    // MARK: Overlays

    private var overlayLanes: some View {
        // Where each annotation is on screen after cuts — the same span the
        // renderer draws (its first moment may have been cut away).
        let spans = Dictionary(model.plan.overlays.map { ($0.effect.id, ($0.start, $0.end)) }, uniquingKeysWith: { first, _ in first })
        let layers = M.overlayLayers(model.project)
        return ZStack(alignment: .topLeading) {
            ForEach(model.project.overlayEffects) { effect in
                if let span = spans[effect.id] {
                    overlayPill(effect, start: span.0, end: max(span.1, span.0 + 0.1), layers: layers)
                }
            }
        }
        .offset(y: overlayTop)
    }

    private func overlayPill(_ effect: VideoDemoOverlayEffect, start: Double, end: Double, layers: [Int]) -> some View {
        let selected = model.isSelected(.overlay(effect.id))
        let shown = overlayDrag?.id == effect.id ? (overlayDrag!.start, overlayDrag!.end) : (start, end)
        let width = max(CGFloat(shown.1 - shown.0) * pointsPerSecond, 26)
        // The pill wears the annotation's own color, so the two match up.
        let custom = effect.color.flatMap { $0.a > 0.1 && effect.kind.hasColor ? $0 : nil }
        let tint = custom.map { Color(nsColor: $0.withAlpha(1).nsColor) } ?? VideoEditorTheme.overlayTint(effect.kind)
        let ink: Color = (custom?.luminance ?? 0) > 0.62 ? Color.black.opacity(0.8) : VideoEditorTheme.laneText(1)
        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(selected ? 0.9 : 0.62))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(VideoEditorTheme.laneStroke(selected: selected), lineWidth: selected ? 1.5 : 1)
            HStack(spacing: 4) {
                Image(systemName: effect.kind.icon)
                    .font(.system(size: 9.5, weight: .bold))
                if width > 70 {
                    Text(effect.kind == .text ? effect.text : effect.kind.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            HStack(spacing: 0) {
                edgeHandle.gesture(overlayEdgeGesture(effect, start: start, end: end, leading: true))
                Spacer(minLength: 0)
                edgeHandle.gesture(overlayEdgeGesture(effect, start: start, end: end, leading: false))
            }
        }
        .frame(width: width, height: M.overlayLaneHeight)
        .contentShape(Rectangle())
        .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
        .gesture(overlayMoveGesture(effect, start: start, end: end, layers: layers))
        .contextMenu {
            Button(L("Delete"), role: .destructive) { model.deleteOverlay(effect.id) }
        }
        .offset(x: x(shown.0), y: laneY(effect.layer, in: layers))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityDescription(of: .overlay(effect.id)))
        .accessibilityHint(L("Adjust to move it half a second"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selection = .overlay(effect.id) }
        .accessibilityAction(named: L("Delete")) { model.deleteOverlay(effect.id) }
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.5 : -0.5
            model.setOverlayWindow(effect.id, start: start + step, end: end + step, coalesce: "overlay-nudge")
            model.endGesture()
        }
    }

    private func overlayMoveGesture(_ effect: VideoDemoOverlayEffect, start: Double, end: Double, layers: [Int]) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin?.id != effect.id {
                    dragOrigin = TimelineDragOrigin(id: effect.id, start: start, end: end, layer: effect.layer, layers: layers)
                    beginBarDrag(.overlay(effect.id))
                    overlayDrag = (effect.id, start, end, effect.layer)
                    hover.setDragging(true)
                    if !movesGroup, !extending { model.selection = .overlay(effect.id) }
                }
                guard let origin = dragOrigin, abs(value.translation.width) > 2 || abs(value.translation.height) > 4 else { return }
                let moved = movedWindow(origin, by: value.translation.width)
                overlayDrag = (effect.id, moved.start, moved.end, origin.layer)
                if movesGroup {
                    // Everything selected moves along in time (lanes stay).
                    model.moveGroup(by: moved.start - origin.start)
                    return
                }
                model.setOverlayWindow(effect.id, start: moved.start, end: moved.end, coalesce: "overlay-\(effect.id)")
                // Dragging UP brings it forward (a higher lane).
                let lanes = Int((-value.translation.height / (M.overlayLaneHeight + M.overlayLaneGap)).rounded())
                model.setOverlayLayer(effect.id, layer: M.layer(movedFrom: origin.layer, by: lanes, in: origin.layers), coalesce: "overlay-\(effect.id)")
            }
            .onEnded { value in
                let origin = dragOrigin ?? TimelineDragOrigin(id: effect.id, start: start, end: end, layer: effect.layer)
                let wasExtending = extending
                let wasGroup = movesGroup
                endBarDrag()
                overlayDrag = nil
                if !wasGroup { model.finishOverlayDrag() }
                if abs(value.translation.width) <= 2, abs(value.translation.height) <= 4 {
                    if wasExtending {
                        model.toggleSelection(.overlay(effect.id))
                    } else {
                        model.selection = .overlay(effect.id)
                        model.seek(to: origin.start + min(0.3, (origin.end - origin.start) / 2))
                    }
                }
            }
    }

    private func overlayEdgeGesture(_ effect: VideoDemoOverlayEffect, start: Double, end: Double, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin?.id != effect.id {
                    dragOrigin = TimelineDragOrigin(id: effect.id, start: start, end: end, layer: effect.layer)
                    snapper = VideoTimelineSnapper(targets: model.snapTargets(excluding: [effect.id]), pointsPerSecond: pointsPerSecond)
                    overlayDrag = (effect.id, start, end, effect.layer)
                    hover.setDragging(true)
                    model.selection = .overlay(effect.id)
                }
                guard let origin = dragOrigin else { return }
                let delta = Double(value.translation.width / pointsPerSecond)
                let newStart = leading ? min(max(snappedEdge(origin.start + delta), 0), origin.end - 0.2) : origin.start
                let newEnd = leading ? origin.end : min(max(snappedEdge(origin.end + delta), origin.start + 0.2), duration)
                overlayDrag = (effect.id, newStart, newEnd, origin.layer)
                model.setOverlayWindow(effect.id, start: newStart, end: newEnd, coalesce: "overlay-edge-\(effect.id)")
            }
            .onEnded { _ in
                overlayDrag = nil
                dragOrigin = nil
                snapper = nil
                hover.setDragging(false)
                model.finishOverlayDrag()
            }
    }
}

struct TimelineDragOrigin: Equatable {
    let id: UUID
    let start: Double
    let end: Double
    var layer: Int = 0
    /// The annotation layers on show when the drag began.
    var layers: [Int] = []
}
