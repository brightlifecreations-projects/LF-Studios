import AppKit
import SwiftUI

// MARK: - Panel widths (1.13.0)

/// The editor's panels across the top: the Library on the left, the player
/// in the middle, Properties on the right (the timeline below them is
/// VideoEditorLayout's). Borders are dragged; Layout ▸ Default, Player
/// first and Reset Layout set them; remembered on this Mac.
struct VideoEditorPanelLayout: Codable, Equatable {
    var library: CGFloat
    var properties: CGFloat

    static let standard = VideoEditorPanelLayout(library: 300, properties: 318)
    /// The player as big as it gets: the Library and Properties narrower.
    static let playerFirst = VideoEditorPanelLayout(library: 220, properties: 280)

    static let libraryRange: ClosedRange<CGFloat> = 200...480
    static let propertiesRange: ClosedRange<CGFloat> = 280...440
    /// The player never gets narrower than this.
    static let minimumPlayer: CGFloat = 400
    /// The two borders between the panels.
    static let borders: CGFloat = 2

    /// The widths on a window `width` wide: each panel in its range and the
    /// player at least 400 pt; when that doesn't fit, the Library gives way
    /// first, then Properties.
    func fitted(windowWidth width: CGFloat) -> (library: CGFloat, player: CGFloat, properties: CGFloat) {
        var library = min(max(self.library, Self.libraryRange.lowerBound), Self.libraryRange.upperBound)
        var properties = min(max(self.properties, Self.propertiesRange.lowerBound), Self.propertiesRange.upperBound)
        var over = library + properties + Self.borders + Self.minimumPlayer - width
        if over > 0 {
            let fromLibrary = min(over, library - Self.libraryRange.lowerBound)
            library -= fromLibrary
            over -= fromLibrary
            properties -= min(over, properties - Self.propertiesRange.lowerBound)
        }
        return (library, max(width - library - properties - Self.borders, 0), properties)
    }

    /// Which layout it is, when it's one of the two.
    var preset: Preset? {
        if self == .standard { return .standard }
        if self == .playerFirst { return .playerFirst }
        return nil
    }

    enum Preset: String, CaseIterable, Identifiable {
        case standard
        case playerFirst

        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: return L("Default")
            case .playerFirst: return L("Player First")
            }
        }
        var layout: VideoEditorPanelLayout {
            switch self {
            case .standard: return .standard
            case .playerFirst: return .playerFirst
            }
        }
    }
}

/// The panels' widths for everyone watching: the editor and the Layout
/// menu (one per Mac, saved in Settings).
@MainActor
final class VideoEditorPanelStore: ObservableObject {
    static let shared = VideoEditorPanelStore()

    @Published private(set) var layout: VideoEditorPanelLayout = Settings.videoEditorPanels ?? .standard

    /// Dragging a border (`done`: the drag ended, remember it).
    func set(_ layout: VideoEditorPanelLayout, remember: Bool) {
        self.layout = layout
        if remember { Settings.videoEditorPanels = layout }
    }

    /// Layout ▸ Default or Player First.
    func choose(_ preset: VideoEditorPanelLayout.Preset) {
        set(preset.layout, remember: true)
    }

    /// Layout ▸ Reset Layout: the panels, the timeline's height and the
    /// track height back to where they start.
    func reset() {
        layout = .standard
        Settings.videoEditorPanels = nil
        Settings.videoTimelineFraction = nil
        NotificationCenter.default.post(name: .lfstudiosEditorLayoutReset, object: nil)
    }

    /// Tests: start from nothing remembered.
    func reload() {
        layout = Settings.videoEditorPanels ?? .standard
    }
}

extension Notification.Name {
    /// Reset Layout: open editors put the timeline back where it starts.
    static let lfstudiosEditorLayoutReset = Notification.Name("lfstudiosEditorLayoutReset")
}

/// Layout ▸ Default, Player First, Reset Layout (in the editor's toolbar).
struct VideoLayoutMenu: View {
    @ObservedObject private var store = VideoEditorPanelStore.shared

    var body: some View {
        Menu {
            ForEach(VideoEditorPanelLayout.Preset.allCases) { preset in
                Button {
                    store.choose(preset)
                } label: {
                    if store.layout.preset == preset {
                        Label(preset.title, systemImage: "checkmark")
                    } else {
                        Text(preset.title)
                    }
                }
            }
            Divider()
            Button(L("Reset Layout")) { store.reset() }
        } label: {
            Label(L("Layout"), systemImage: "rectangle.3.group")
                .font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.ink.opacity(0.06)))
        .help(L("Layout: how the editor's panels are arranged"))
        .accessibilityLabel(L("Layout"))
    }
}

/// A border between two panels: drag it, double-click to reset.
struct VideoPanelBorder: View {
    /// Dragged by `delta` points from where it was (`done`: let go).
    let moved: (_ delta: CGFloat, _ done: Bool) -> Void
    let reset: () -> Void
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        Rectangle()
            .fill(VideoEditorTheme.hairline)
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.accentColor.opacity(hovering || dragging ? 0.55 : 0))
                    .frame(width: 2)
            )
            .frame(width: 1)
            .overlay(
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovering = inside
                        (inside ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                dragging = true
                                moved(value.translation.width, false)
                            }
                            .onEnded { value in
                                dragging = false
                                moved(value.translation.width, true)
                            }
                    )
                    .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
            )
            .help(L("Drag to resize the panels. Double-click to reset."))
            .accessibilityElement()
            .accessibilityLabel(L("Panel border"))
    }
}

// MARK: - Under the player

/// Play, frame steps, the time, the aspect ratio, the zoom and full screen.
struct VideoPlayerBar: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                barButton("backward.frame.fill", help: L("Previous frame (←)")) { model.step(frames: -1) } // l10n-ignore: a symbol name
                barButton(model.isPlaying ? "pause.fill" : "play.fill", help: model.isPlaying ? L("Pause (Space)") : L("Play (Space)"), prominent: true) { model.togglePlay() }
                    .accessibilityLabel(model.isPlaying ? L("Pause") : L("Play"))
                barButton("forward.frame.fill", help: L("Next frame (→)")) { model.step(frames: 1) } // l10n-ignore: a symbol name
            }
            HStack(spacing: 0) {
                Text(VideoEditorModel.timecode(clock.time))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Text(" / \(VideoEditorModel.timecode(model.timelineDuration))") // l10n-ignore: a time
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
            }
            .fixedSize()
            Spacer(minLength: 6)
            VideoAspectMenu(model: model)
            Menu {
                ForEach(VideoEditorModel.previewZooms, id: \.self) { zoom in
                    Button {
                        model.previewZoom = zoom
                    } label: {
                        if abs(model.previewZoom - zoom) < 0.001 {
                            Label(VideoEditorModel.previewZoomTitle(zoom), systemImage: "checkmark")
                        } else {
                            Text(VideoEditorModel.previewZoomTitle(zoom))
                        }
                    }
                }
            } label: {
                Text(VideoEditorModel.previewZoomTitle(model.previewZoom))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("Zoom the player"))
            .accessibilityLabel(L("Player zoom"))
            barButton(model.isPlayerFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                      help: model.isPlayerFullScreen ? L("Leave full screen (Esc)") : L("Full-screen preview")) {
                model.isPlayerFullScreen.toggle()
            }
            .accessibilityLabel(model.isPlayerFullScreen ? L("Leave full screen") : L("Full-screen preview"))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private func barButton(_ symbol: String, help: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 13 : 11.5, weight: .bold))
                .frame(width: prominent ? 34 : 26, height: 28)
        }
        .buttonStyle(VideoToolButtonStyle(prominent: prominent))
        .help(help)
    }
}

extension VideoEditorModel {
    /// The player's zoom: Fit, then larger to look closely (it scrolls).
    nonisolated static let previewZooms: [CGFloat] = [1, 1.5, 2, 3]

    nonisolated static func previewZoomTitle(_ zoom: CGFloat) -> String {
        zoom <= 1.001 ? L("Fit") : VideoEditorFormat.percent(Double(zoom))
    }
}
