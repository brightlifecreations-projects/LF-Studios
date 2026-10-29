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
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(row.isEmpty ? VideoEditorTheme.textTertiary : VideoEditorTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(title)
            Spacer(minLength: 2)
            if track.canHide {
                headerButton(state.hidden ? "eye.slash" : "eye", on: state.hidden,
                             help: state.hidden ? L("Show “\(title)” in the video") : L("Hide “\(title)” in the preview and the export"),
                             label: state.hidden ? L("Show \(title)") : L("Hide \(title)")) { model.toggleTrackHidden(track) }
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
        .background(VideoEditorTheme.ink.opacity(row.isEmpty ? 0.015 : 0.03))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
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
