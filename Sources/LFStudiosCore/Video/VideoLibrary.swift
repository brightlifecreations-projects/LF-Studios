import AppKit
import SwiftUI

// MARK: - The Library panel (1.13.0)

/// The editor's top-left panel: the project's media and sound, and (1.15.0)
/// text, stickers, effects, transitions, captions, filters and adjustments
/// to drag onto the timeline.
enum VideoLibraryTab: String, CaseIterable, Identifiable {
    case media
    case audio
    case text
    case stickers
    case effects
    case transitions
    case captions
    case filters
    case adjustment

    var id: String { rawValue }
    var title: String {
        switch self {
        case .media: return L("Media")
        case .audio: return L("Audio")
        case .text: return L("Text")
        case .stickers: return L("Stickers")
        case .effects: return L("Effects")
        case .filters: return L("Filters")
        case .adjustment: return L("Adjust")
        case .captions: return L("Captions")
        case .transitions: return L("Transitions")
        }
    }
    var symbol: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .audio: return "music.note"
        case .text: return "textformat"
        case .stickers: return "face.smiling"
        case .effects: return "sparkles"
        case .filters: return "camera.filters"
        case .adjustment: return "slider.horizontal.3"
        case .captions: return "captions.bubble"
        case .transitions: return "rectangle.portrait.on.rectangle.portrait.angled"
        }
    }
}

struct VideoLibraryPanel: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        VStack(spacing: 0) {
            // Nine tabs in rows that share the width (no scrolling to find one).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 2)], spacing: 2) {
                    ForEach(VideoLibraryTab.allCases) { tab in
                        Button {
                            model.libraryTab = tab
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: tab.symbol)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(tab.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .foregroundStyle(model.libraryTab == tab ? VideoEditorTheme.textPrimary : VideoEditorTheme.textSecondary)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(model.libraryTab == tab ? VideoEditorTheme.ink.opacity(0.08) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(tab.title)
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
                case .audio: VideoAudioLibraryTab(model: model)
                case .text: VideoTextLibraryTab(model: model)
                case .stickers: VideoStickersLibraryTab(model: model)
                case .effects: VideoEffectsLibraryTab(model: model)
                case .filters: VideoFiltersLibraryTab(model: model)
                case .adjustment: VideoAdjustmentLibraryTab(model: model)
                case .captions: VideoCaptionsLibraryTab(model: model)
                case .transitions: VideoTransitionsLibraryTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(VideoEditorTheme.panel)
    }
}
