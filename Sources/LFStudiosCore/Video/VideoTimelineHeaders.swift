import AppKit
import SwiftUI

// MARK: - Scrolling together

/// Where the lanes are scrolled to: the ruler follows across, the track
/// headers up and down (set by VideoTimelineScroller).
@MainActor
final class VideoTimelineScrollOffsets: ObservableObject {
    @Published var x: CGFloat = 0
    @Published var y: CGFloat = 0

    func update(_ bounds: CGRect) {
        if abs(bounds.minX - x) > 0.25 { x = bounds.minX }
        if abs(bounds.minY - y) > 0.25 { y = bounds.minY }
    }
}

/// The lanes' scroll bar up and down (1.21.0): it shows whenever the
/// tracks don't all fit, so a short timeline says there's more below. Drag
/// it, scroll anywhere over the lanes or the track headers, or click above
/// or below the thumb for a page.
struct VideoTimelineVerticalScrollbar: View {
    @ObservedObject var offsets: VideoTimelineScrollOffsets
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let scroller: VideoTimelineScroller
    @State private var dragStart: CGFloat?
    /// How many show now (tests).
    static var shown = 0

    private var range: CGFloat { max(contentHeight - viewportHeight, 1) }
    private var thumb: CGFloat { min(max(viewportHeight * viewportHeight / max(contentHeight, 1), 24), viewportHeight) }
    private var travel: CGFloat { max(viewportHeight - thumb - 4, 1) }

    var body: some View {
        let top = 2 + travel * min(max(offsets.y / range, 0), 1)
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    scroller.scroll(toY: offsets.y + (location.y < top ? -viewportHeight : viewportHeight))
                }
            Capsule()
                .fill(VideoEditorTheme.textTertiary.opacity(0.75))
                .frame(width: 6, height: thumb)
                .offset(y: top)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStart == nil { dragStart = offsets.y }
                            scroller.scroll(toY: (dragStart ?? 0) + value.translation.height * range / travel)
                        }
                        .onEnded { _ in dragStart = nil }
                )
        }
        .frame(width: 12, height: viewportHeight, alignment: .top)
        .background(VideoEditorTheme.panel.opacity(0.55))
        .help(L("Scroll to see every track"))
        .accessibilityElement()
        .accessibilityLabel(L("Tracks"))
        .accessibilityValue(VideoEditorFormat.percent(Double(min(max(offsets.y / range, 0), 1))))
        .accessibilityAdjustableAction { direction in
            scroller.scroll(toY: offsets.y + (direction == .increment ? 40 : -40))
        }
        .onAppear { Self.shown += 1 }
        .onDisappear { Self.shown -= 1 }
    }
}

/// The ruler strip, moved with the lanes.
struct VideoTimelineRulerStrip<Content: View>: View {
    @ObservedObject var offsets: VideoTimelineScrollOffsets
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Drawn over the space it's given: its full width never widens it.
        Color.clear
            .overlay(alignment: .topLeading) {
                content().offset(x: -offsets.x)
            }
            .clipped()
    }
}

// MARK: - Headers

/// Above the headers: the track height.
struct VideoTimelineHeaderCorner: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        HStack(spacing: 4) {
            Text(L("Tracks"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textTertiary)
            Spacer(minLength: 0)
            Menu {
                ForEach(VideoTimelineTrackHeight.allCases) { height in
                    Button {
                        model.chooseTrackHeight(height)
                    } label: {
                        if height == model.timelineTrackHeight {
                            Label(height.title, systemImage: "checkmark")
                        } else {
                            Text(height.title)
                        }
                    }
                }
            } label: {
                Label(model.timelineTrackHeight.title, systemImage: "arrow.up.and.down")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("Track height"))
            .accessibilityLabel(L("Track height"))
        }
        .padding(.horizontal, 10)
    }
}

/// The track headers, one per row, moved with the lanes.
struct VideoTimelineTrackHeaders: View {
    @ObservedObject var model: VideoEditorModel
    let rows: VideoTimelineRowLayout
    @ObservedObject var offsets: VideoTimelineScrollOffsets

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows.rows, id: \.track) { row in
                VideoTrackHeader(model: model, row: row)
                    .frame(width: VideoTimelineMetrics.headerWidth, height: row.height)
                    .offset(y: row.top)
                Rectangle()
                    .fill(VideoEditorTheme.hairline)
                    .frame(width: VideoTimelineMetrics.headerWidth, height: VideoTimelineRowLayout.separator)
                    .offset(y: row.top + row.height)
            }
        }
        .frame(width: VideoTimelineMetrics.headerWidth, height: rows.height, alignment: .topLeading)
        .offset(y: -offsets.y)
        .frame(width: VideoTimelineMetrics.headerWidth, alignment: .topLeading)
    }
}

/// A track's icon and name, and its Hide, Mute and Lock buttons.
struct VideoTrackHeader: View {
    @ObservedObject var model: VideoEditorModel
    let row: VideoTimelineRowLayout.Row
    /// Renaming (double-click the name, 1.21.0).
    @State private var draft: String?
    @FocusState private var nameFocused: Bool

    private var curveOpen: Bool {
        guard VideoEditorStyle.current.isNew, case .layer(let id) = row.track, row.showsContent else { return false }
        return model.curveLanes[id] != nil
    }

    var body: some View {
        let track = row.track
        let state = model.project.trackState(track)
        let title = track.title(in: model.project)
        HStack(spacing: 4) {
            if track != .zooms, track != .clips {
                Button {
                    model.toggleTrackCollapsed(track)
                } label: {
                    Image(systemName: row.collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .disabled(row.isEmpty && !row.collapsed)
                .opacity(row.isEmpty && !row.collapsed ? 0.3 : 1)
                .help(row.collapsed ? L("Show this track") : L("Collapse this track"))
                .accessibilityLabel(row.collapsed ? L("Show \(title)") : L("Collapse \(title)"))
            } else {
                Color.clear.frame(width: 12)
            }
            Image(systemName: track.symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .frame(width: 16)
            if let current = draft {
                TextField(track.usualTitle(in: model.project), text: Binding(get: { current }, set: { draft = $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onExitCommand { draft = nil }
                    .onChange(of: nameFocused) { focused in if !focused { commitName() } }
                    .accessibilityLabel(L("Track name"))
            } else {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(row.isEmpty ? VideoEditorTheme.textTertiary : VideoEditorTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(L("\(title) — double-click to rename"))
                    .onTapGesture(count: 2) { startRenaming() }
                    .accessibilityAction(named: L("Rename Track")) { startRenaming() }
            }
            Spacer(minLength: 2)
            // LF Studios layout: the keyframe curve lane under this track.
            if VideoEditorStyle.current.isNew, case .layer(let id) = track, row.showsContent {
                headerButton(VideoCurveLane.symbol, on: model.curveLanes[id] != nil,
                             help: model.curveLanes[id] != nil ? L("Hide the keyframe curve") : L("Show a keyframe curve under this track"),
                             label: L("Keyframe curve: \(title)")) { model.toggleCurveLane(id) }
            }
            if track.canHide {
                headerButton(state.hidden ? "eye.slash" : "eye", on: state.hidden,
                             help: state.hidden ? L("Show “\(title)” in the video") : L("Hide “\(title)” in the preview and the export"),
                             label: state.hidden ? L("Show \(title)") : L("Hide \(title)")) { model.toggleTrackHidden(track) }
            }
            if track.canSolo {
                headerButton("headphones", on: state.solo,
                             help: state.solo ? L("Stop soloing “\(title)”") : L("Solo “\(title)”: hear only soloed tracks while editing (the export keeps every track)"),
                             label: state.solo ? L("Unsolo \(title)") : L("Solo \(title)")) { model.perform(.basics(.solo(track))) }
            }
            if track.canMute {
                headerButton(state.muted ? "speaker.slash" : "speaker.wave.2", on: state.muted,
                             help: state.muted ? L("Unmute “\(title)”") : L("Mute “\(title)” in the preview and the export"),
                             label: state.muted ? L("Unmute \(title)") : L("Mute \(title)")) { model.toggleTrackMuted(track) }
            }
            headerButton(state.locked ? "lock.fill" : "lock.open", on: state.locked,
                         help: state.locked ? L("Unlock “\(title)”") : L("Lock “\(title)”: nothing on it can be changed"),
                         label: state.locked ? L("Unlock \(title)") : L("Lock \(title)")) { model.toggleTrackLocked(track) }
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .frame(maxHeight: .infinity)
        // The curve lane's setting, beside the lane (LF Studios layout).
        .frame(height: curveOpen ? VideoTimelineMetrics.layerLaneHeight + VideoTimelineRowLayout.padding * 2 : nil)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottomLeading) {
            if curveOpen, case .layer(let id) = track {
                VideoCurveLaneHeader(model: model, track: id)
                    .padding(.leading, 34)
                    .padding(.bottom, VideoCurveLane.height / 2 - 8)
            }
        }
        .background(VideoEditorTheme.ink.opacity(row.isEmpty ? 0.015 : 0.03))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func startRenaming() {
        draft = model.project.trackStates[row.track.key]?.name ?? row.track.title(in: model.project)
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitName() {
        guard let name = draft else { return }
        draft = nil
        // The usual name typed back in: just the usual name again.
        let usual = row.track.usualTitle(in: model.project)
        model.perform(.basics(.renameTrack(row.track, name == usual ? "" : name)))
    }

    private func headerButton(_ symbol: String, on: Bool, help: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(on ? VideoEditorTheme.accent.opacity(0.18) : Color.clear))
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? VideoEditorTheme.accent : VideoEditorTheme.textTertiary)
        .help(help)
        .accessibilityLabel(label)
    }
}

// MARK: - Rows in the lanes

/// Each row's band and the line under it; a locked row is striped.
struct VideoTimelineRowBackgrounds: View {
    let rows: VideoTimelineRowLayout
    let width: CGFloat
    let locked: Set<VideoTimelineTrack>

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(rows.rows.enumerated()), id: \.element.track) { index, row in
                Rectangle()
                    .fill(VideoEditorTheme.ink.opacity(index.isMultiple(of: 2) ? 0.02 : 0))
                    .frame(width: width, height: row.height)
                    .offset(y: row.top)
                if locked.contains(row.track) {
                    VideoLockedStripes()
                        .frame(width: width, height: row.height)
                        .offset(y: row.top)
                }
                Rectangle()
                    .fill(VideoEditorTheme.hairline)
                    .frame(width: width, height: VideoTimelineRowLayout.separator)
                    .offset(y: row.top + row.height)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Diagonal stripes over a locked row.
struct VideoLockedStripes: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 10
            }
            context.stroke(path, with: .color(VideoEditorTheme.ink.opacity(0.07)), lineWidth: 1)
        }
    }
}

/// "Add …" on an empty row; nothing on a collapsed one.
struct VideoTimelineRowHints: View {
    let rows: VideoTimelineRowLayout
    let inset: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows.rows.filter { $0.isEmpty && !$0.collapsed }, id: \.track) { row in
                Text(VideoTimelineRowLayout.hint(row.track))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .lineLimit(1)
                    .frame(width: max(width, 40), height: row.height, alignment: .leading)
                    .offset(x: inset, y: row.top)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The divider above the timeline

/// Drag to give the timeline more or less room; double-click to go back to
/// where it starts for this window. A drag is remembered on this Mac.
struct VideoTimelineDivider: View {
    /// Where it is now.
    let fraction: Double
    let windowHeight: CGFloat
    /// Dragged (`done`: the drag ended, remember it).
    let moved: (_ fraction: Double, _ done: Bool) -> Void
    /// Double-clicked.
    let reset: () -> Void
    @State private var start: Double?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            Capsule()
                .fill(VideoEditorTheme.ink.opacity(hovering || start != nil ? 0.35 : 0.14))
                .frame(width: 36, height: 4)
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            (inside ? NSCursor.resizeUpDown : NSCursor.arrow).set()
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if start == nil { start = fraction }
                    let height = VideoEditorLayout.timelineHeight(windowHeight: windowHeight, fraction: start ?? fraction) - value.translation.height
                    moved(VideoEditorLayout.fraction(forTimelineHeight: height, windowHeight: windowHeight), false)
                }
                .onEnded { _ in
                    start = nil
                    moved(fraction, true)
                }
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        .help(L("Drag to resize the timeline. Double-click for the usual size."))
        .accessibilityElement()
        .accessibilityLabel(L("Timeline size"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: moved(min(fraction + 0.05, 0.9), true)
            case .decrement: moved(max(fraction - 0.05, 0.1), true)
            @unknown default: break
            }
        }
    }
}
