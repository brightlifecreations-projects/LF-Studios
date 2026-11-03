import AppKit
import SwiftUI

// MARK: - Toolbar

struct VideoTimelineToolbar: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock

    var body: some View {
        HStack(spacing: 6) {
            // Play, pause and the time are under the player (1.13.0).
            // Tools (1.14.0): what they do and their keys show on hover.
            // LF Studios layout: Select, Split tool, undo and redo are in the
            // tool rail and the top bar.
            if !VideoEditorStyle.current.isNew {
                HStack(spacing: 2) {
                    command(.selectTool)
                    command(.splitTool)
                    command(.trimTool)
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VideoEditorTheme.ink.opacity(0.05)))
                command(.undo).disabled(!model.canUndo)
                command(.redo).disabled(!model.canRedo)
                toolbarDivider
            }
            command(.split)
            command(.deleteLeft)
            command(.deleteRight)
            command(.delete).disabled(model.selection == .none && model.selectedAudioPiece == nil)
            toolbarDivider
            command(.addMarker)
            command(.freezeFrame)
            command(.reverse).disabled(model.generating != nil)
            command(.mirror)
            command(.rotate)
            command(.crop)
            toolbarDivider
            iconButton(symbol: "plus.magnifyingglass", help: L("Add a zoom at the playhead (Z)"), label: L("Zoom")) { model.addZoom(at: clock.time) }
            VideoZoomCutButton(model: model)
            iconButton(symbol: model.project.autoZoom ? "sparkles.rectangle.stack.fill" : "sparkles", help: model.project.autoZoom ? L("Auto-zoom on clicks is on — click to turn it off and remove its zooms") : L("Turn on Auto-zoom on clicks — keeps zooms you placed by hand"), label: L("Auto Zoom")) { model.setAutoZoom(!model.project.autoZoom) }
            iconButton(symbol: "hare", help: L("Fast-forward moments where nothing happens"), label: L("Speed Up Idle")) { model.speedUpIdle() }
            if !model.project.markers.isEmpty {
                iconButton(symbol: "flag.2.crossed", help: L("Split the clips at every marker"), label: L("Split at Markers")) { model.splitAtMarkers() }
            }

            Spacer(minLength: 8)

            command(.recordVoiceover)
            toolbarDivider
            command(.toggleMagnet)
            command(.toggleSnapping)
            command(.toggleLinkage)
            command(.togglePreviewAxis)
            toolbarDivider

            if model.hasAudio {
                iconButton(symbol: model.previewMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           help: model.previewMuted ? L("Unmute the preview (M)") : L("Mute the preview (M) — the export keeps its sound"),
                           label: model.previewMuted ? L("Unmute preview") : L("Mute preview")) { model.togglePreviewMute() }
            }

            HStack(spacing: 6) {
                Button {
                    model.zoomTimeline(by: 1 / 1.4)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .accessibilityLabel(L("Show more of the timeline"))
                Slider(value: Binding(get: { log(model.timelineZoom) / log(model.maxTimelineZoom) }, set: { model.timelineZoom = pow(model.maxTimelineZoom, $0) }), in: 0...1)
                    .frame(width: 80)
                    .controlSize(.small)
                    .accessibilityLabel(L("Timeline scale"))
                Button {
                    model.zoomTimeline(by: 1.4)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .accessibilityLabel(L("Show the timeline in more detail"))
                command(.zoomToFit)
            }
            .font(.system(size: 12, weight: .semibold))
            .help(L("Timeline scale (pinch, or ⌘-scroll)"))
        }
        .padding(.horizontal, 12)
        // The switches live in Settings: redraw when one changes.
        .id(model.switchesVersion)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(VideoEditorTheme.hairline)
            .frame(width: 1, height: 18)
    }

    /// A command's button: its symbol, its name and keys on hover; a
    /// switch or a tool shows whether it's on.
    private func command(_ command: VideoEditCommand) -> some View {
        let on = model.isOn(command)
        let shows = command.isSwitch || command == .selectTool || command == .splitTool || command == .recordVoiceover
        return Button {
            model.perform(command)
        } label: {
            Image(systemName: command == .recordVoiceover && on ? "mic.fill" : command.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(shows && on ? (command == .recordVoiceover ? Color.red : Color.accentColor) : VideoEditorTheme.textPrimary)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(shows && on && !command.isSwitch ? Color.accentColor.opacity(0.16) : Color.clear))
        }
        .buttonStyle(VideoToolButtonStyle())
        .help(command.keys.isEmpty ? command.title : L("\(command.title) (\(command.keys))"))
        .accessibilityLabel(command.title)
        .accessibilityValue(command.isSwitch ? (on ? L("On") : L("Off")) : "")
    }

    private func iconButton(symbol: String, help: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(VideoToolButtonStyle())
        .help(help)
        .accessibilityLabel(label)
    }
}
