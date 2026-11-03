import AppKit
import SwiftUI

// MARK: - The LF Studios (new) layout (1.17.0)

/// The tools down the left edge: Select (A), Split tool (B), Split at the
/// playhead, Delete left and right of the playhead, Group, Zoom cut, Add
/// keyframe and Record voiceover. Each shows the keys set for it now
/// (LF Studios', a preset's, or your own).
struct VideoToolRail: View {
    @ObservedObject var model: VideoEditorModel

    static let tools: [[VideoEditCommand]] = [
        [.selectTool, .splitTool],
        [.split, .deleteLeft, .deleteRight, .group],
        [.zoomCut, .addKeyframe, .addMarker],
        [.recordVoiceover],
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Self.tools.indices, id: \.self) { group in
                if group > 0 {
                    Rectangle().fill(VideoEditorTheme.hairline).frame(width: 22, height: 1).padding(.vertical, 4)
                }
                ForEach(Self.tools[group], id: \.self) { command in
                    button(command)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .frame(width: 40)
        .frame(maxHeight: .infinity)
        .background(VideoEditorTheme.panel)
        // A changed key shows at once.
        .id(model.switchesVersion)
    }

    private func button(_ command: VideoEditCommand) -> some View {
        let on = (command == .selectTool && model.timelineTool == .select) || (command == .splitTool && model.timelineTool == .split)
            || (command == .recordVoiceover && model.isOn(command))
        return Button {
            model.perform(command)
        } label: {
            Image(systemName: command == .recordVoiceover && on ? "mic.fill" : command.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? (command == .recordVoiceover ? Color.red : VideoEditorTheme.primary) : VideoEditorTheme.textSecondary)
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? VideoEditorTheme.primary.opacity(0.16) : Color.clear))
        }
        .buttonStyle(VideoToolButtonStyle())
        .help(command.keys.isEmpty ? command.title : L("\(command.title) (\(command.keys))"))
        .accessibilityLabel(command.title)
        .accessibilityValue(on ? L("On") : "")
    }
}

/// The strip along the bottom: the last message on the left, the main keys
/// on the right (the ones set now).
struct VideoStatusStrip: View {
    @ObservedObject var model: VideoEditorModel

    static let keyed: [VideoEditCommand] = [.selectTool, .splitTool, .split, .deleteLeft, .deleteRight, .toggleEnabled, .zoomCut]

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.notice == nil ? VideoEditorTheme.textTertiary.opacity(0.5) : VideoEditorTheme.primary)
                .frame(width: 6, height: 6)
            Text(model.lastNotice?.message ?? (model.isReady ? L("Ready") : L("Opening…")))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 12)
            VideoAgentDot()
            ViewThatFits(in: .horizontal) {
                hints(Self.keyed)
                hints(Array(Self.keyed.prefix(4)))
                hints(Array(Self.keyed.prefix(2)))
                EmptyView()
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { model.isShortcutsPresented = true }
            } label: {
                Text(L("All keys (?)"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(VideoEditorTheme.textSecondary)
            .help(L("Keyboard shortcuts (?)"))
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(VideoEditorTheme.panel)
        .id(model.switchesVersion)
        .accessibilityElement(children: .contain)
    }

    /// Split says where it splits (1.21.0): at the skimmer while the
    /// pointer is over the timeline, else at the playhead.
    private func title(_ command: VideoEditCommand) -> String {
        guard command == .split else { return command.title }
        return model.isSkimming ? L("Split at skimmer") : L("Split at playhead")
    }

    private func hints(_ commands: [VideoEditCommand]) -> some View {
        HStack(spacing: 12) {
            ForEach(commands.filter { !$0.keys.isEmpty }, id: \.self) { command in
                HStack(spacing: 4) {
                    Text(command.keys).foregroundStyle(VideoEditorTheme.textPrimary)
                    Text(title(command)).foregroundStyle(VideoEditorTheme.textTertiary)
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
    }
}

/// The search field in the top bar: everything in one list (⌘K).
struct VideoSearchField: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { model.isCommandPalettePresented = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                Text(L("Search"))
                Spacer(minLength: 24)
                Text(verbatim: "⌘K")
                    .font(.system(size: 10.5, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(VideoEditorTheme.cardStroke))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(VideoEditorTheme.textSecondary)
            .padding(.horizontal, 10)
            .frame(width: 220, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.well))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(VideoEditorTheme.cardStroke))
        }
        .buttonStyle(.plain)
        .help(L("Search commands, media, clips, captions and markers (⌘K)"))
        .accessibilityLabel(L("Search"))
    }
}

enum VideoEditorNewMetrics {
    static let railWidth: CGFloat = 40
    static let statusHeight: CGFloat = 24
}
