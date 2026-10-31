import AppKit
import SwiftUI

// MARK: - The Library panel (1.13.0)

/// The editor's top-left panel: the project's media, its sound, and the
/// way to text, captions and transitions.
enum VideoLibraryTab: String, CaseIterable, Identifiable {
    case media
    case audio
    case text
    case captions
    case transitions

    var id: String { rawValue }
    var title: String {
        switch self {
        case .media: return L("Media")
        case .audio: return L("Audio")
        case .text: return L("Text")
        case .captions: return L("Captions")
        case .transitions: return L("Transitions")
        }
    }
    var symbol: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .audio: return "music.note"
        case .text: return "textformat"
        case .captions: return "captions.bubble"
        case .transitions: return "rectangle.portrait.on.rectangle.portrait.angled"
        }
    }
}

struct VideoLibraryPanel: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        VStack(spacing: 0) {
            // Five tabs share the width (no scrolling to find one).
            HStack(spacing: 2) {
                    ForEach(VideoLibraryTab.allCases) { tab in
                        Button {
                            model.libraryTab = tab
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tab.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(tab.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundStyle(model.libraryTab == tab ? VideoEditorTheme.textPrimary : VideoEditorTheme.textSecondary)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(model.libraryTab == tab ? VideoEditorTheme.ink.opacity(0.08) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(model.libraryTab == tab ? .isSelected : [])
                    }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            Group {
                switch model.libraryTab {
                case .media: VideoMediaBinView(model: model, kinds: [.video, .image, .audio])
                case .audio: VideoMediaBinView(model: model, kinds: [.audio])
                case .text: textTab
                case .captions: captionsTab
                case .transitions: transitionsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(VideoEditorTheme.panel)
    }

    // MARK: Pointers to where these live today

    private var textTab: some View {
        VideoLibraryPointer(
            text: L("Text, arrows, highlights, blur and pictures go on the video with the tools above the player. Pick one here to add it at the playhead."),
            actions: [
                (L("Text"), "textformat", { model.addOverlay(.text) }),
                (L("Arrow"), "arrow.up.right", { model.addOverlay(.arrow) }),
                (L("Highlight"), "rectangle.dashed", { model.addOverlay(.highlight) }),
                (L("Blur"), "eye.slash", { model.addOverlay(.blur) }),
                (L("Spotlight"), "circle.dashed.inset.filled", { model.addOverlay(.spotlight) }),
                (L("Image"), "photo", { model.addOverlay(.image) }),
            ]
        )
    }

    private var captionsTab: some View {
        VideoLibraryPointer(
            text: L("Captions live in the Captions panel on the right: make them from your voice, type them, translate and style them."),
            actions: [(L("Open Captions"), "captions.bubble", { model.selection = .none; model.inspectorTab = .captions })]
        )
    }

    private var transitionsTab: some View {
        VideoLibraryPointer(
            text: L("Transitions go on the cuts between clips: click the + between two clips on the timeline, or set them all in Style ▸ Transitions."),
            actions: [(L("Open Transitions"), "rectangle.portrait.on.rectangle.portrait.angled", { model.selection = .none; model.inspectorTab = .background })]
        )
    }
}

/// A short note on where a feature lives, with buttons that go there.
struct VideoLibraryPointer: View {
    let text: String
    let actions: [(String, String, () -> Void)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        Button(action: action.2) {
                            VStack(spacing: 5) {
                                Image(systemName: action.1).font(.system(size: 15, weight: .semibold))
                                Text(action.0).font(.system(size: 11, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                        }
                        .buttonStyle(VideoSecondaryButtonStyle())
                    }
                }
            }
            .padding(12)
        }
    }
}
