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
    /// LF Studios (new) or CapCut style (1.17.0), remembered on this Mac.
    @Published private(set) var style: VideoEditorStyle = Settings.videoEditorStyle
    /// Where the panels are docked and which float (1.18.0).
    @Published private(set) var arrangement: VideoDockArrangement = Settings.videoEditorArrangement ?? .standard
    /// Layout ▸ Save Layout…'s, by name.
    @Published private(set) var savedLayouts: [VideoSavedLayout] = Settings.videoSavedLayouts

    /// Layout ▸ LF Studios (new) or CapCut style: every open editor redraws.
    func choose(_ style: VideoEditorStyle) {
        guard style != self.style else { return }
        Settings.videoEditorStyle = style
        self.style = style
    }

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
    /// track height back to where they start, every panel docked.
    func reset() {
        layout = .standard
        Settings.videoEditorPanels = nil
        Settings.videoTimelineFraction = nil
        arrange(.standard)
        NotificationCenter.default.post(name: .lfstudiosEditorLayoutReset, object: nil)
    }

    // MARK: Docking and floating (1.18.0)

    /// A new arrangement (the standard one, whatever its shares, is drawn
    /// as in 1.17.0).
    func arrange(_ next: VideoDockArrangement, remember: Bool = true) {
        let next = next.isStandard ? VideoDockArrangement.standard : next
        // Found how to move panels: the tip has done its job.
        if next != .standard { Settings.videoPanelTipSeen = true }
        if next != arrangement { arrangement = next }
        if remember { Settings.videoEditorArrangement = next == .standard ? nil : next }
    }

    /// A panel dragged next to another (`current`: the docked panels with
    /// their shares as drawn). A floating one docks there.
    func move(_ kind: VideoPanelKind, to side: VideoDockSide, of target: VideoPanelKind, current: VideoDockNode) {
        guard let docked = current.moving(kind, to: side, of: target) else { return }
        var next = arrangement
        next.docked = docked
        next.floating.removeAll { $0.kind == kind }
        arrange(next)
    }

    /// A panel in a window of its own (never the last docked one).
    func float(_ kind: VideoPanelKind, frame: CGRect, screen: UInt32?, current: VideoDockNode) {
        var base = arrangement
        base.docked = current
        guard let next = base.floating(kind, frame: frame, screen: screen) else { return }
        arrange(next)
    }

    /// A floating panel back in the editor (Dock, or its close button).
    func dock(_ kind: VideoPanelKind) {
        arrange(arrangement.docking(kind))
    }

    /// The Agent panel shows (docked where it goes), when it's hidden.
    func showAgentPanel() { show(.agent) }

    /// An optional panel (Agent, Assistant) shows, docked where it goes.
    func show(_ kind: VideoPanelKind) {
        guard VideoPanelKind.optionalPanels.contains(kind), !shows(kind) else { return }
        arrange(arrangement.docking(kind))
    }

    /// A panel put away (only the Agent and Assistant panels can be).
    func hide(_ kind: VideoPanelKind) {
        guard VideoPanelKind.optionalPanels.contains(kind) else { return }
        var next = arrangement
        next.floating.removeAll { $0.kind == kind }
        if let rest = next.docked.removing(kind) { next.docked = rest }
        arrange(next)
    }

    func shows(_ kind: VideoPanelKind) -> Bool {
        arrangement.docked.contains(kind) || arrangement.floating.contains { $0.kind == kind }
    }

    var showsAgentPanel: Bool { shows(.agent) }

    /// Every floating panel back in the editor.
    func dockAll() {
        var next = arrangement
        for panel in arrangement.floating { next = next.docking(panel.kind) }
        arrange(next)
    }

    /// A floating panel moved or resized: remembered there.
    func moveFloating(_ kind: VideoPanelKind, frame: CGRect, screen: UInt32?) {
        guard let index = arrangement.floating.firstIndex(where: { $0.kind == kind }) else { return }
        var next = arrangement
        next.floating[index].frame = frame
        next.floating[index].screen = screen
        guard next != arrangement else { return }
        arrange(next)
    }

    /// A border between docked panels dragged (`remember`: let go).
    func resizeDocked(_ docked: VideoDockNode, remember: Bool) {
        var next = arrangement
        next.docked = docked
        arrange(next, remember: remember)
    }

    // MARK: Saved layouts

    /// Layout ▸ Save Layout…: everything as it is now, by name (the same
    /// name: replaced).
    func saveLayout(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var saved = savedLayouts.filter { $0.name != name }
        saved.append(VideoSavedLayout(name: name, arrangement: arrangement, widths: layout, timelineFraction: Settings.videoTimelineFraction))
        savedLayouts = saved
        Settings.videoSavedLayouts = saved
    }

    /// Layout ▸ a saved layout: its panels, widths and timeline height.
    func apply(_ saved: VideoSavedLayout) {
        set(saved.widths, remember: true)
        Settings.videoTimelineFraction = saved.timelineFraction
        arrange(saved.arrangement)
        NotificationCenter.default.post(name: .lfstudiosEditorLayoutApplied, object: nil, userInfo: saved.timelineFraction.map { ["fraction": $0] })
    }

    func deleteLayout(named name: String) {
        savedLayouts.removeAll { $0.name == name }
        Settings.videoSavedLayouts = savedLayouts
    }

    /// The saved layout it is now, if any.
    var currentSavedLayout: VideoSavedLayout? {
        savedLayouts.last { $0.arrangement == arrangement && $0.widths == layout }
    }

    /// Tests: start from nothing remembered.
    func reload() {
        layout = Settings.videoEditorPanels ?? .standard
        style = Settings.videoEditorStyle
        VideoEditorStyle.current = style
        arrangement = Settings.videoEditorArrangement ?? .standard
        savedLayouts = Settings.videoSavedLayouts
    }
}

/// A layout saved by name (Layout ▸ Save Layout…, 1.18.0).
struct VideoSavedLayout: Codable, Equatable, Identifiable {
    var name: String
    var arrangement: VideoDockArrangement
    var widths: VideoEditorPanelLayout
    var timelineFraction: Double?

    var id: String { name }
}

extension Notification.Name {
    /// Reset Layout: open editors put the timeline back where it starts.
    static let lfstudiosEditorLayoutReset = Notification.Name("lfstudiosEditorLayoutReset")
    /// A saved layout chosen: open editors take its timeline height
    /// (userInfo "fraction", none: where it starts).
    static let lfstudiosEditorLayoutApplied = Notification.Name("lfstudiosEditorLayoutApplied")
}

/// Layout ▸ Default, Player First, Reset Layout (in the editor's toolbar).
struct VideoLayoutMenu: View {
    @ObservedObject private var store = VideoEditorPanelStore.shared

    var body: some View {
        Menu {
            // The editor's look and layout (1.17.0).
            ForEach(VideoEditorStyle.allCases) { style in
                Button {
                    store.choose(style)
                } label: {
                    if store.style == style {
                        Label(style.title, systemImage: "checkmark")
                    } else {
                        Text(style.title)
                    }
                }
            }
            Divider()
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
            // Saved layouts (1.18.0).
            Divider()
            ForEach(store.savedLayouts) { saved in
                Button {
                    store.apply(saved)
                } label: {
                    if store.currentSavedLayout == saved {
                        Label(saved.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: saved.name)
                    }
                }
            }
            Button(L("Save Layout…")) { Self.askToSave(store) }
            if !store.savedLayouts.isEmpty {
                Menu(L("Delete Saved Layout")) {
                    ForEach(store.savedLayouts) { saved in
                        Button { store.deleteLayout(named: saved.name) } label: { Text(verbatim: saved.name) }
                    }
                }
            }
            if !store.arrangement.floating.isEmpty {
                Button(L("Dock All Panels")) { store.dockAll() }
            }
            // AI agents' panel (1.19.0) and the Assistant (1.20.0).
            Button {
                if store.shows(.assistant) { store.hide(.assistant) } else { store.show(.assistant) }
            } label: {
                if store.shows(.assistant) { Label(L("Assistant Panel"), systemImage: "checkmark") } else { Text(L("Assistant Panel")) }
            }
            Button {
                if store.showsAgentPanel { store.hide(.agent) } else { store.showAgentPanel() }
            } label: {
                if store.showsAgentPanel { Label(L("Agent Panel"), systemImage: "checkmark") } else { Text(L("Agent Panel")) }
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

extension VideoLayoutMenu {
    /// Save Layout…: asks for a name.
    static func askToSave(_ store: VideoEditorPanelStore) {
        let alert = NSAlert()
        alert.messageText = L("Save Layout")
        alert.informativeText = L("Name this layout. It's kept on this Mac, in the Layout menu.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = L("Layout name")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.saveLayout(named: field.stringValue)
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
            VideoProxyMenu(model: model)
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
