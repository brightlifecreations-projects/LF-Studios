import AppKit
import SwiftUI

/// Background swatch thumbnails, rendered once.
@MainActor
final class VideoSwatchCache: ObservableObject {
    static let shared = VideoSwatchCache()

    @Published private(set) var pictures: [String: NSImage] = [:]
    private var images: [VideoBackground: NSImage] = [:]
    private var loading: Set<String> = []
    lazy var systemWallpapers: [URL] = VideoBackgroundCatalog.systemWallpapers()

    func image(for background: VideoBackground) -> NSImage? {
        if let cached = images[background] { return cached }
        switch background {
        case .wallpaper, .gradient, .color:
            let size = CGSize(width: 176, height: 110)
            let image = VideoBackgroundRenderer.image(for: background, blur: 0, size: size)
            guard let cgImage = VideoRenderContext.shared.createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
            let result = NSImage(cgImage: cgImage, size: NSSize(width: size.width / 2, height: size.height / 2))
            images[background] = result
            return result
        case .image(let path), .systemWallpaper(let path):
            if let picture = pictures[path] { return picture }
            loadPicture(path)
            return nil
        }
    }

    private func loadPicture(_ path: String) {
        guard !loading.contains(path) else { return }
        loading.insert(path)
        Task.detached(priority: .utility) {
            let thumbnail = VideoBackgroundRenderer.thumbnail(path: path, maxPixel: 240)
            await MainActor.run {
                if let thumbnail { self.pictures[path] = thumbnail }
            }
        }
    }
}

struct VideoInspectorView: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                tabBar
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                // The selected object's settings sit above the tab, which
                // stays where it was (its list keeps its scroll position).
                if model.selection != .none {
                    // The tab keeps room to work in — the transcript most.
                    let keep: CGFloat = model.inspectorTab == .captions ? 330 : 220
                    VideoSelectionInspector(model: model, maxHeight: max(min(proxy.size.height * 0.6, proxy.size.height - 58 - keep), 170))
                    Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                }
                tabContent
            }
        }
        .background(VideoEditorTheme.panel)
    }

    @ViewBuilder
    private var tabContent: some View {
        if model.inspectorTab == .captions {
            // The transcript scrolls itself, so this tab fills the height.
            VideoScriptInspector(model: model)
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch model.inspectorTab {
                    case .background: VideoBackgroundInspector(model: model)
                    case .cursor: VideoCursorInspector(model: model)
                    case .zoom: VideoZoomInspector(model: model)
                    case .camera: VideoCameraInspector(model: model)
                    case .captions: VideoCaptionsInspector(model: model)
                    case .audio: VideoAudioInspector(model: model)
                    }
                }
                .padding(16)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(VideoEditorModel.InspectorTab.allCases) { tab in
                let selected = model.inspectorTab == tab
                Button {
                    model.inspectorTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(height: 17)
                        // Never wraps: a longer name ("Untertitel") takes a
                        // little room from the others.
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                            .fixedSize()
                    }
                    .foregroundStyle(selected ? VideoEditorTheme.textPrimary : VideoEditorTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? VideoEditorTheme.ink.opacity(0.08) : Color.clear)
                    )
                    .overlay(alignment: .topTrailing) {
                        // A narrated video nobody transcribed yet.
                        if tab == .captions, model.suggestsTranscript {
                            Circle()
                                .fill(VideoEditorTheme.caption)
                                .frame(width: 7, height: 7)
                                .padding(.top, 7)
                                .padding(.trailing, 9)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab == .captions && model.suggestsTranscript ? L("Your narration can become captions — transcribe it here") : tab.help)
                .accessibilityLabel(tab.title)
                .accessibilityHint(tab.help)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Inspector tabs"))
    }
}
