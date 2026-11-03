import AppKit
import Combine
import SwiftUI

// MARK: - Dragging a panel by its header (1.18.0)

/// A panel being dragged by its header, and where it would land: next to
/// another panel (a blue drop zone shows the half it takes), or outside
/// the editor window, in a window of its own.
@MainActor
final class VideoDockDrag: ObservableObject {
    struct Target: Equatable {
        let kind: VideoPanelKind
        let side: VideoDockSide
    }

    /// The editor's coordinate space, where the frames are measured.
    nonisolated static let space = "lfstudiosDockRoom"

    @Published private(set) var dragging: VideoPanelKind?
    @Published private(set) var target: Target?
    /// Outside the editor window: letting go floats it.
    @Published private(set) var outside = false
    /// Each docked panel's frame in the editor.
    var frames: [VideoPanelKind: CGRect] = [:]
    /// The editor in its window (top-left origin).
    var room: CGRect = .zero
    weak var window: NSWindow?

    /// A point on the screens in the editor's coordinates.
    func roomPoint(screen point: CGPoint) -> CGPoint? {
        guard let window, let content = window.contentView else { return nil }
        let inWindow = window.convertPoint(fromScreen: point)
        return CGPoint(x: inWindow.x - room.minX, y: content.bounds.height - inWindow.y - room.minY)
    }

    /// A docked panel's frame on the screens.
    func screenFrame(of kind: VideoPanelKind) -> CGRect? {
        guard let window, let content = window.contentView, let frame = frames[kind] else { return nil }
        let inWindow = CGRect(x: frame.minX + room.minX, y: content.bounds.height - (frame.maxY + room.minY), width: frame.width, height: frame.height)
        return window.convertToScreen(inWindow)
    }

    func update(_ kind: VideoPanelKind, screen point: CGPoint) {
        if dragging != kind { dragging = kind }
        guard let local = roomPoint(screen: point) else {
            target = nil
            outside = true
            return
        }
        let hit = frames.first { $0.key != kind && $0.value.contains(local) }
        let next = hit.map { Target(kind: $0.key, side: VideoDockLayout.side(of: $0.value, at: local)) }
        if next != target { target = next }
        let out = hit == nil && !(window?.frame.contains(point) ?? false)
        if out != outside { outside = out }
    }

    /// Let go at `point`: docked by the target, floated outside the window
    /// (a docked panel only), or nothing.
    func end(_ kind: VideoPanelKind, screen point: CGPoint, store: VideoEditorPanelStore? = nil) {
        let store = store ?? .shared
        update(kind, screen: point)
        defer { cancel() }
        let current = store.arrangement.docked.withShares(from: frames)
        if let target {
            store.move(kind, to: target.side, of: target.kind, current: current)
        } else if outside, current.contains(kind) {
            let size = frames[kind]?.size ?? kind.minimumSize
            store.float(kind, frame: Self.floatingFrame(kind, size: size, at: point), screen: Self.screenID(at: point), current: current)
        }
    }

    func cancel() {
        dragging = nil
        target = nil
        outside = false
    }

    /// Layout ▸ Float: just off where it's docked.
    func float(_ kind: VideoPanelKind, store: VideoEditorPanelStore? = nil) {
        let store = store ?? .shared
        let current = store.arrangement.docked.withShares(from: frames)
        guard current.contains(kind) else { return }
        var frame = screenFrame(of: kind) ?? CGRect(origin: CGPoint(x: 120, y: 120), size: kind.minimumSize)
        frame = frame.offsetBy(dx: 32, dy: -32)
        frame.size.height += VideoFloatingPanels.titleBar
        store.float(kind, frame: frame, screen: Self.screenID(at: CGPoint(x: frame.midX, y: frame.midY)), current: current)
    }

    /// The window a panel floats in, let go at `point`: its size as docked,
    /// the pointer near its title.
    static func floatingFrame(_ kind: VideoPanelKind, size: CGSize, at point: CGPoint) -> CGRect {
        let width = max(size.width, kind.minimumSize.width)
        let height = max(size.height, kind.minimumSize.height) + VideoFloatingPanels.titleBar
        return CGRect(x: point.x - 60, y: point.y - height + 12, width: width, height: height)
    }

    static func screenID(at point: CGPoint) -> UInt32? {
        (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.displayID
    }
}

/// Once, the first time the editor opens in 1.19.0: panels move by their
/// top edge (closed with OK, or once a panel is moved).
struct VideoPanelTipNotice: View {
    @State private var seen = Settings.videoPanelTipSeen
    @ObservedObject private var store = VideoEditorPanelStore.shared

    var body: some View {
        if !seen, store.arrangement == .standard {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(L("Tip: drag a panel's top edge to move it"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("OK")) {
                    Settings.videoPanelTipSeen = true
                    seen = true
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 460)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(VideoEditorTheme.popover))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke))
            .shadow(color: VideoEditorTheme.shadow, radius: 10, y: 4)
            .accessibilityElement(children: .contain)
        }
    }
}

/// Each docked panel's frame, measured where it's drawn.
struct VideoDockFramesKey: PreferenceKey {
    static let defaultValue: [VideoPanelKind: CGRect] = [:]
    static func reduce(value: inout [VideoPanelKind: CGRect], nextValue: () -> [VideoPanelKind: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// A panel that can be moved: it reports its frame, and has a header to
    /// drag it by (`permanent`), or one that shows while the pointer is at
    /// its top edge (the standard layout, drawn as in 1.17.0).
    func dockPanel(_ kind: VideoPanelKind, dock: VideoDockDrag, permanent: Bool) -> some View {
        modifier(VideoDockPanelModifier(kind: kind, dock: dock, permanent: permanent))
    }
}

private struct VideoDockPanelModifier: ViewModifier {
    let kind: VideoPanelKind
    @ObservedObject var dock: VideoDockDrag
    let permanent: Bool
    @State private var revealed = false

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if permanent {
                VideoPanelHeader(kind: kind, dock: dock, floating: false)
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            }
            content
                // The standard layout: the header shows at the top edge.
                .onContinuousHover { phase in
                    guard !permanent else { return }
                    if case .active(let point) = phase, point.y < 6 { revealed = true }
                }
                .overlay(alignment: .top) {
                    if !permanent, revealed || dock.dragging == kind {
                        VideoPanelHeader(kind: kind, dock: dock, floating: false)
                            .shadow(color: VideoEditorTheme.shadow, radius: 6, y: 2)
                            .onHover { inside in if !inside, dock.dragging != kind { revealed = false } }
                            .transition(.opacity)
                    }
                }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: VideoDockFramesKey.self, value: [kind: proxy.frame(in: .named(VideoDockDrag.space))])
        })
    }
}

/// A panel's header: drag it to another side of another panel, or out of
/// the window to float it. Float or Dock on the right.
struct VideoPanelHeader: View {
    static let height: CGFloat = 24

    let kind: VideoPanelKind
    @ObservedObject var dock: VideoDockDrag
    /// In a window of its own.
    let floating: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(VideoEditorTheme.textTertiary)
            Image(systemName: kind.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textSecondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                if floating {
                    VideoEditorPanelStore.shared.dock(kind)
                } else {
                    dock.float(kind)
                }
            } label: {
                Image(systemName: floating ? "rectangle.inset.filled.and.person.filled" : "macwindow.badge.plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 22, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(VideoEditorTheme.textSecondary)
            .help(floating ? L("Dock: put it back in the editor window") : L("Float: in a window of its own"))
            .accessibilityLabel(floating ? L("Dock") : L("Float"))
            // The Agent and Assistant panels can be put away (Layout brings
            // them back).
            if VideoPanelKind.optionalPanels.contains(kind) {
                Button { VideoEditorPanelStore.shared.hide(kind) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .frame(width: 20, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .help(kind == .agent ? L("Hide the Agent panel") : L("Hide the Assistant panel"))
                .accessibilityLabel(L("Hide"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(dock.dragging == kind ? VideoEditorTheme.cardHover : VideoEditorTheme.panel)
        .contentShape(Rectangle())
        .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { _ in
                    NSCursor.closedHand.set()
                    dock.update(kind, screen: NSEvent.mouseLocation)
                }
                .onEnded { _ in
                    NSCursor.arrow.set()
                    dock.end(kind, screen: NSEvent.mouseLocation)
                }
        )
        .help(floating ? L("Drag onto the editor to dock it") : L("Drag to move this panel; drop it outside the window to float it"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.title)
        .accessibilityAction(named: floating ? L("Dock") : L("Float")) {
            if floating { VideoEditorPanelStore.shared.dock(kind) } else { dock.float(kind) }
        }
    }

    private var title: String {
        guard dock.dragging == kind else { return kind.title }
        if let target = dock.target { return L("Dock next to \(target.kind.title)") }
        if dock.outside, !floating { return L("Let go to float") }
        return kind.title
    }
}

/// The blue half of the panel a dragged one would take.
struct VideoDockDropZone: View {
    @ObservedObject var dock: VideoDockDrag

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target = dock.target, let frame = dock.frames[target.kind] {
                let zone = VideoDockLayout.dropZone(of: frame, side: target.side).insetBy(dx: 3, dy: 3)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .systemBlue).opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .systemBlue), lineWidth: 2))
                    .frame(width: zone.width, height: zone.height)
                    .offset(x: zone.minX, y: zone.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: dock.target)
    }
}

// MARK: - The docked panels

/// What a panel shows, docked or floating.
struct VideoPanelContent: View {
    let kind: VideoPanelKind
    let model: VideoEditorModel

    var body: some View {
        switch kind {
        case .library:
            VideoLibraryPanel(model: model)
        case .player:
            VStack(spacing: 0) {
                VideoPlayerPanel(model: model)
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                VideoPlayerBar(model: model, clock: model.clock)
                    .background(VideoEditorTheme.panel)
            }
        case .properties:
            if VideoEditorStyle.current.isNew {
                VideoPropertiesPanel(model: model)
            } else {
                VideoInspectorView(model: model)
            }
        case .timeline:
            VideoTimelineView(model: model).equatable()
        case .agent:
            VideoAgentPanel(model: model)
        case .assistant:
            VideoAssistantPanel(model: model)
        }
    }
}

/// The docked panels where the arrangement puts them, with a border
/// between each two to drag.
struct VideoDockArea: View {
    let node: VideoDockNode
    let model: VideoEditorModel
    @ObservedObject var dock: VideoDockDrag
    @State private var resizing: (node: VideoDockNode, layout: VideoDockLayout)?

    var body: some View {
        GeometryReader { proxy in
            let layout = VideoDockLayout(node, in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                ForEach(node.panels) { kind in
                    if let frame = layout.frames[kind] {
                        // Sized to its place before it's measured.
                        VideoPanelContent(kind: kind, model: model)
                            .frame(width: frame.width, height: max(frame.height - VideoPanelHeader.height - 1, 0))
                            .dockPanel(kind, dock: dock, permanent: true)
                            .frame(width: frame.width, height: frame.height)
                            .clipped()
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
                ForEach(Array(layout.borders.enumerated()), id: \.offset) { _, border in
                    VideoDockBorder(axis: border.axis) { delta, done in
                        resize(border, by: delta, done: done, layout: layout)
                    }
                    .frame(width: border.frame.width, height: border.frame.height)
                    .offset(x: border.frame.minX, y: border.frame.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    /// A border dragged by `delta`: the two panels (or groups) on either
    /// side change size, never under their minimums.
    private func resize(_ border: VideoDockLayout.Border, by delta: CGFloat, done: Bool, layout: VideoDockLayout) {
        let start = resizing ?? (node, layout)
        if resizing == nil { resizing = start }
        if done { resizing = nil }
        guard let shares = Self.shares(after: border, by: delta, in: start.node, layout: start.layout) else { return }
        VideoEditorPanelStore.shared.resizeDocked(start.node.settingShares(shares, at: border.path), remember: done)
    }

    static func shares(after border: VideoDockLayout.Border, by delta: CGFloat, in node: VideoDockNode, layout: VideoDockLayout) -> [Double]? {
        guard case .split(let axis, let children, _) = node.node(at: border.path) ?? node,
              children.indices.contains(border.index + 1) else { return nil }
        let lengths: [CGFloat] = children.map { child in
            let union = child.panels.compactMap { layout.frames[$0] }.reduce(CGRect.null) { $0.union($1) }
            return axis == .horizontal ? union.width : union.height
        }
        let minimums = children.map { axis == .horizontal ? $0.minimumSize.width : $0.minimumSize.height }
        var sizes = lengths
        let i = border.index
        let pair = sizes[i] + sizes[i + 1]
        sizes[i] = min(max(sizes[i] + delta, minimums[i]), pair - minimums[i + 1])
        sizes[i + 1] = pair - sizes[i]
        return sizes.map(Double.init)
    }
}

/// A border between two docked panels: drag it, either way.
struct VideoDockBorder: View {
    let axis: VideoDockNode.Axis
    let moved: (_ delta: CGFloat, _ done: Bool) -> Void
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        let across = axis == .horizontal
        Rectangle()
            .fill(VideoEditorTheme.hairline)
            .overlay(Rectangle().fill(Color.accentColor.opacity(hovering || dragging ? 0.55 : 0)).frame(width: across ? 2 : nil, height: across ? nil : 2))
            .overlay(
                Color.clear
                    .frame(width: across ? 9 : nil, height: across ? nil : 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovering = inside
                        (inside ? (across ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown) : NSCursor.arrow).set()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                dragging = true
                                moved(across ? value.translation.width : value.translation.height, false)
                            }
                            .onEnded { value in
                                dragging = false
                                moved(across ? value.translation.width : value.translation.height, true)
                            }
                    )
            )
            .help(L("Drag to resize the panels"))
            .accessibilityElement()
            .accessibilityLabel(L("Panel border"))
    }
}

// MARK: - Floating panels

/// A panel's own window. It belongs to its editor: it stays above it, hides
/// and closes with it, and the editor's keys work in it.
final class VideoFloatingPanelWindow: NSWindow {
    weak var editor: VideoDemoEditorWindowController?
    var kind: VideoPanelKind = .library
    /// Once it has been in front: from then on, what the user focused stays.
    var settled = false
}

/// An editor's floating panels: opened and closed as the arrangement
/// changes, where they were (the main screen when that screen is gone).
@MainActor
final class VideoFloatingPanels: NSObject, NSWindowDelegate {
    /// The window's title bar, added to a panel's own size.
    static let titleBar: CGFloat = 28

    private weak var owner: VideoDemoEditorWindowController?
    private let model: VideoEditorModel
    private let dock: VideoDockDrag
    private(set) var windows: [VideoPanelKind: VideoFloatingPanelWindow] = [:]
    private var watching: AnyCancellable?

    init(owner: VideoDemoEditorWindowController, model: VideoEditorModel, dock: VideoDockDrag) {
        self.owner = owner
        self.model = model
        self.dock = dock
        super.init()
    }

    /// From now on (the editor's window is up).
    func start() {
        watching = VideoEditorPanelStore.shared.$arrangement.sink { [weak self] arrangement in
            // After the change lands.
            DispatchQueue.main.async { self?.sync(arrangement) }
        }
    }

    var isKey: Bool { windows.values.contains { $0.isKeyWindow } }

    func sync(_ arrangement: VideoDockArrangement) {
        let wanted = Dictionary(arrangement.floating.map { ($0.kind, $0) }, uniquingKeysWith: { $1 })
        for kind in windows.keys where wanted[kind] == nil { close(kind) }
        for (kind, panel) in wanted where windows[kind] == nil { open(panel) }
    }

    private func open(_ panel: VideoFloatingPanel) {
        guard let editorWindow = owner?.window else { return }
        let screens = NSScreen.screens.compactMap { screen in screen.displayID.map { (id: $0, frame: screen.visibleFrame) } }
        // At least its minimum size, then on a screen.
        var wanted = panel.frame
        wanted.size.width = max(wanted.width, panel.kind.minimumSize.width)
        wanted.size.height = max(wanted.height, panel.kind.minimumSize.height + VideoPanelHeader.height + Self.titleBar)
        let frame = VideoFloatingPanel.restoredFrame(wanted, screen: panel.screen, screens: screens, main: (NSScreen.main ?? editorWindow.screen)?.visibleFrame ?? editorWindow.frame)
        let window = VideoFloatingPanelWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.editor = owner
        window.kind = panel.kind
        window.title = panel.kind.title
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        window.backgroundColor = editorWindow.backgroundColor
        window.contentMinSize = NSSize(width: panel.kind.minimumSize.width, height: panel.kind.minimumSize.height + VideoPanelHeader.height)
        let hosting = NSHostingView(rootView: VideoFloatingPanelContent(kind: panel.kind, model: model, dock: dock))
        // Its size is the window's (the minimum above), not what SwiftUI
        // would like.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setFrame(frame, display: false)
        window.delegate = self
        editorWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        // AppKit puts a new window's first text field in focus (the
        // Library's search): the editor's keys would type there instead.
        window.makeFirstResponder(nil)
        windows[panel.kind] = window
    }

    private func close(_ kind: VideoPanelKind) {
        guard let window = windows.removeValue(forKey: kind) else { return }
        window.parent?.removeChildWindow(window)
        window.delegate = nil
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    /// The editor closes: its panels go with it (the arrangement stays).
    func closeAll() {
        watching = nil
        for kind in Array(windows.keys) { close(kind) }
    }

    private func remember(_ notification: Notification) {
        guard let window = notification.object as? VideoFloatingPanelWindow, windows[window.kind] === window else { return }
        VideoEditorPanelStore.shared.moveFloating(window.kind, frame: window.frame, screen: window.screen?.displayID)
    }

    func windowDidMove(_ notification: Notification) { remember(notification) }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? VideoFloatingPanelWindow, !window.settled else { return }
        window.settled = true
        if window.firstResponder is NSText { window.makeFirstResponder(nil) }
    }
    func windowDidEndLiveResize(_ notification: Notification) { remember(notification) }

    /// Its close button docks it.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let window = sender as? VideoFloatingPanelWindow else { return true }
        VideoEditorPanelStore.shared.dock(window.kind)
        return false
    }
}

/// A floating panel's window: its header (drag it onto the editor to dock
/// it, or Dock) and the panel.
struct VideoFloatingPanelContent: View {
    let kind: VideoPanelKind
    let model: VideoEditorModel
    @ObservedObject var dock: VideoDockDrag
    @ObservedObject private var panels = VideoEditorPanelStore.shared

    var body: some View {
        VStack(spacing: 0) {
            VideoPanelHeader(kind: kind, dock: dock, floating: true)
            Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            VideoPanelContent(kind: kind, model: model)
        }
        .background(VideoEditorTheme.window)
        .id(panels.style)
    }
}
