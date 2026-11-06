import AppKit
import SwiftUI

/// Annotation and zoom tools where people look for them — centered above
/// the preview, like the screenshot editor's dock. One click adds the
/// effect at the playhead, selected, with handles on the video.
struct VideoToolDock: View {
    @ObservedObject var model: VideoEditorModel
    /// Symbols only, for a narrow player (the names show on hover).
    var compact = false

    /// Each tool's tooltip, with its key where it has one.
    static func help(_ kind: VideoDemoOverlayEffectKind) -> String {
        switch kind {
        case .text: return L("Add text at the playhead (⌥T)")
        case .arrow: return L("Add arrow at the playhead (⌥A)")
        case .highlight: return L("Add highlight at the playhead (⌥H)")
        case .blur: return L("Add blur at the playhead (⌥B)")
        case .spotlight: return L("Add spotlight at the playhead")
        case .image: return L("Add image at the playhead")
        }
    }

    private var selectedKind: VideoDemoOverlayEffectKind? {
        guard case .overlay = model.selection else { return nil }
        return model.selectedOverlay?.kind
    }

    var body: some View {
        HStack(spacing: 6) {
            group {
                ForEach(VideoDemoOverlayEffectKind.allCases) { kind in
                    VideoDockButton(
                        title: kind.title,
                        symbol: kind.icon,
                        tint: VideoEditorTheme.overlayTint(kind),
                        active: selectedKind == kind,
                        help: Self.help(kind),
                        compact: compact
                    ) {
                        model.addOverlay(kind)
                    }
                }
            }
            group {
                // Nothing is blurred until you pick (VideoPrivacyPanel.swift).
                VideoDockButton(
                    title: L("Find private info"),
                    symbol: "eye.trianglebadge.exclamationmark",
                    tint: VideoEditorTheme.overlayTint(.blur),
                    active: model.isPrivacyPresented,
                    help: L("Find faces, emails, phone and card numbers, and keys in the video, then choose what to blur"),
                    compact: compact
                ) {
                    model.showPrivacyScan()
                }
            }
            group {
                VideoDockButton(
                    title: L("Zoom"),
                    symbol: "plus.magnifyingglass",
                    tint: VideoEditorTheme.zoom,
                    active: model.selectedZoomID != nil,
                    help: L("Add a zoom at the playhead (Z)"),
                    compact: compact
                ) {
                    model.addZoom(at: model.clock.time)
                    model.inspectorTab = .zoom
                }
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(VideoEditorTheme.dock)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
        .shadow(color: VideoEditorTheme.shadow, radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Tools"))
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) { content() }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(VideoEditorTheme.ink.opacity(0.05)))
    }
}

struct VideoDockButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let active: Bool
    let help: String
    var compact = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active || hovered ? tint : VideoEditorTheme.textPrimary)
                    .frame(height: 17)
                if !compact {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(active ? VideoEditorTheme.textPrimary : VideoEditorTheme.textSecondary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, compact ? 4 : 6)
            .frame(minWidth: compact ? 34 : 62)
            .frame(height: compact ? 34 : 42)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? tint.opacity(0.22) : (hovered ? VideoEditorTheme.ink.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(title)
    }
}

/// Tips under the preview, a few at a time: the arrow shows the next few,
/// and each new editor window starts on the next page. Dismissed tips come
/// back from the command palette or the shortcuts sheet.
struct VideoTipsBar: View {
    @AppStorage("videoEditorTipsDismissed") private var dismissed = false
    @State private var page = 0

    /// A key (or where to act), then what it does. Keys keep their symbols.
    static var pages: [[(String, String)]] {
        [
            [(L("Space"), L("play")), (L("Hover the Zoom track"), L("add a zoom")), (L("Click a zoom"), L("aim or resize it")), ("⌘E", L("export"))],
            [("⌘B", L("split at the skimmer or the playhead")), (L("⇧-drag the timeline"), L("select a part to cut")), ("Q  W", L("delete left / right of the playhead"))],
            [("⌥T ⌥H ⌥A ⌥B", L("text, highlight, arrow, blur")), (L("Click it on the video"), L("select it")), (L("Double-click text"), L("type"))],
            [("⌥← ⌥→", L("step through the timeline")), (L("⌘-scroll"), L("zoom around the skimmer")), ("M", L("mute the preview"))],
            [(L("Captions tab"), L("cut by editing words")), ("⌘K", L("every command")), ("?", L("all shortcuts"))],
        ]
    }

    var body: some View {
        if !dismissed {
            let tips = Self.pages[page % Self.pages.count]
            // One line always: the tips that don't fit a narrow window (in a
            // language that runs long) wait for a wider one.
            ViewThatFits(in: .horizontal) {
                ForEach(Array((1...tips.count).reversed()), id: \.self) { count in
                    bar(Array(tips.prefix(count)))
                }
            }
            .padding(.horizontal, 12)
            .transition(.opacity)
            .onAppear {
                // Each editor window starts on the next page.
                page = Settings.videoEditorTipPage
                Settings.videoEditorTipPage = page + 1
            }
        }
    }

    private func bar(_ tips: [(String, String)]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Color.yellow)
                .accessibilityHidden(true)
            ForEach(Array(tips.enumerated()), id: \.offset) { _, item in
                tip(item.0, item.1)
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { page += 1 }
                Settings.videoEditorTipPage = page + 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(VideoEditorTheme.textSecondary)
            .help(L("More tips"))
            .accessibilityLabel(L("More tips"))
            Button {
                withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(VideoEditorTheme.textSecondary)
            .help(L("Hide tips (bring them back from ⌘K or the shortcuts list)"))
            .accessibilityLabel(L("Dismiss tips"))
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(VideoEditorTheme.floatingPill))
        .overlay(Capsule().strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Tips"))
    }

    private func tip(_ key: String, _ action: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textPrimary)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(VideoEditorTheme.ink.opacity(0.1)))
            Text(action)
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .fixedSize()
        }
    }
}
