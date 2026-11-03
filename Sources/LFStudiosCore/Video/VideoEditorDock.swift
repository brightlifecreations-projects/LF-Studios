import AppKit
import SwiftUI

// MARK: - Movable panels (1.18.0)

/// The editor's four panels. Each can dock on any side of another (drag its
/// header) or float in a window of its own, on any screen.
enum VideoPanelKind: String, Codable, CaseIterable, Identifiable {
    case library
    case player
    case properties
    case timeline
    /// AI agents' run (1.19.0): shown when one starts, hidden by the user.
    case agent
    /// The built-in Assistant's chat (1.20.0): shown and hidden by the user.
    case assistant

    /// The editor's own four (always there, docked or floating).
    static let editorPanels: [VideoPanelKind] = [.library, .player, .properties, .timeline]
    /// The ones that can be put away (Layout brings them back).
    static let optionalPanels: [VideoPanelKind] = [.agent, .assistant]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return L("Library")
        case .player: return L("Player")
        case .properties: return L("Properties")
        case .timeline: return L("Timeline")
        case .agent: return L("Agent")
        case .assistant: return L("Assistant")
        }
    }

    var symbol: String {
        switch self {
        case .library: return "square.grid.2x2"
        case .player: return "play.rectangle"
        case .properties: return "slider.horizontal.3"
        case .timeline: return "timeline.selection"
        case .agent: return "sparkles"
        case .assistant: return "bubble.left.and.text.bubble.right"
        }
    }

    /// Never smaller than this, docked or floating.
    var minimumSize: CGSize {
        switch self {
        case .library: return CGSize(width: VideoEditorPanelLayout.libraryRange.lowerBound, height: 180)
        // Its controls along the bottom need this much once it's moved
        // (in the standard layout it's never narrower).
        case .player: return CGSize(width: 521, height: 220)
        case .properties: return CGSize(width: VideoEditorPanelLayout.propertiesRange.lowerBound, height: 180)
        // Its toolbar's width (in 1.17.0 it always had the window's).
        case .timeline: return CGSize(width: VideoEditorStyle.current.isNew ? 840 : 975, height: 150)
        case .agent: return CGSize(width: 260, height: 200)
        case .assistant: return CGSize(width: 280, height: 260)
        }
    }
}

/// Where a dragged panel lands next to another.
enum VideoDockSide: String, Codable, CaseIterable {
    case left, right, top, bottom

    var axis: VideoDockNode.Axis { self == .left || self == .right ? .horizontal : .vertical }
    var before: Bool { self == .left || self == .top }
}

/// How the docked panels sit: a panel, or panels side by side
/// (`horizontal`) or one above the other (`vertical`), each taking a share.
indirect enum VideoDockNode: Codable, Equatable {
    enum Axis: String, Codable { case horizontal, vertical }

    case panel(VideoPanelKind)
    case split(Axis, [VideoDockNode], [Double])

    /// 1.17.0's: the Library, the player and Properties across the top, the
    /// timeline under them.
    static let standard: VideoDockNode = .split(.vertical, [
        .split(.horizontal, [.panel(.library), .panel(.player), .panel(.properties)], [0.25, 0.5, 0.25]),
        .panel(.timeline),
    ], [0.6, 0.4])

    var panels: [VideoPanelKind] {
        switch self {
        case .panel(let kind): return [kind]
        case .split(_, let children, _): return children.flatMap(\.panels)
        }
    }

    func contains(_ kind: VideoPanelKind) -> Bool { panels.contains(kind) }

    /// The same arrangement, whatever the shares: the standard one is
    /// drawn exactly as 1.17.0 did.
    var shape: VideoDockNode {
        switch self {
        case .panel: return self
        case .split(let axis, let children, _):
            return .split(axis, children.map(\.shape), children.map { _ in 0 })
        }
    }

    var isStandardShape: Bool { shape == Self.standard.shape }

    /// Without `kind` (a split left with one panel becomes that panel).
    func removing(_ kind: VideoPanelKind) -> VideoDockNode? {
        switch self {
        case .panel(let k): return k == kind ? nil : self
        case .split(let axis, let children, let shares):
            var kept: [VideoDockNode] = []
            var keptShares: [Double] = []
            for (child, share) in zip(children, shares) {
                if let left = child.removing(kind) {
                    kept.append(left)
                    keptShares.append(share)
                }
            }
            if kept.isEmpty { return nil }
            if kept.count == 1 { return kept[0] }
            return .split(axis, kept, Self.normalized(keptShares)).flattened
        }
    }

    /// `kind` docked on `side` of `target`, taking half of its room.
    func inserting(_ kind: VideoPanelKind, at side: VideoDockSide, of target: VideoPanelKind) -> VideoDockNode {
        switch self {
        case .panel(let k):
            guard k == target else { return self }
            let pair: [VideoDockNode] = side.before ? [.panel(kind), self] : [self, .panel(kind)]
            return .split(side.axis, pair, [0.5, 0.5])
        case .split(let axis, let children, let shares):
            // Next to a panel that's directly in a split the same way: a
            // place in that split, sharing the target's room.
            if axis == side.axis, let index = children.firstIndex(of: .panel(target)) {
                var children = children
                var shares = shares
                let half = shares[index] / 2
                shares[index] = half
                let at = side.before ? index : index + 1
                children.insert(.panel(kind), at: at)
                shares.insert(half, at: at)
                return .split(axis, children, shares)
            }
            return .split(axis, children.map { $0.inserting(kind, at: side, of: target) }, shares)
        }
    }

    /// A panel moved next to another (nil: it can't go there).
    func moving(_ kind: VideoPanelKind, to side: VideoDockSide, of target: VideoPanelKind) -> VideoDockNode? {
        guard kind != target, contains(target) else { return nil }
        guard let without = removing(kind), without.contains(target) else { return nil }
        return without.inserting(kind, at: side, of: target)
    }

    /// Splits inside a split the same way become one.
    var flattened: VideoDockNode {
        guard case .split(let axis, let children, let shares) = self else { return self }
        var flat: [VideoDockNode] = []
        var flatShares: [Double] = []
        for (child, share) in zip(children.map(\.flattened), shares) {
            if case .split(let inner, let grandchildren, let innerShares) = child, inner == axis {
                flat.append(contentsOf: grandchildren)
                flatShares.append(contentsOf: innerShares.map { $0 * share })
            } else {
                flat.append(child)
                flatShares.append(share)
            }
        }
        return .split(axis, flat, Self.normalized(flatShares))
    }

    static func normalized(_ shares: [Double]) -> [Double] {
        let total = shares.reduce(0, +)
        guard total > 0 else { return shares.map { _ in 1 / Double(max(shares.count, 1)) } }
        return shares.map { $0 / total }
    }

    /// The smallest it can be: its panels' minimums, side by side or stacked.
    var minimumSize: CGSize {
        switch self {
        case .panel(let kind): return kind.minimumSize
        case .split(let axis, let children, _):
            let sizes = children.map(\.minimumSize)
            let gaps = CGFloat(max(children.count - 1, 0)) * VideoDockLayout.border
            switch axis {
            case .horizontal: return CGSize(width: sizes.map(\.width).reduce(0, +) + gaps, height: sizes.map(\.height).max() ?? 0)
            case .vertical: return CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).reduce(0, +) + gaps)
            }
        }
    }

    /// The same arrangement with shares measured from where its panels
    /// are drawn (the standard layout's widths and timeline height), so
    /// nothing jumps when a panel first moves.
    func withShares(from frames: [VideoPanelKind: CGRect]) -> VideoDockNode {
        guard case .split(let axis, let children, let shares) = self else { return self }
        let lengths: [Double] = children.map { child in
            let union = child.panels.compactMap { frames[$0] }.reduce(CGRect.null) { $0.union($1) }
            guard !union.isNull else { return 0 }
            return Double(axis == .horizontal ? union.width : union.height)
        }
        let measured = lengths.allSatisfy { $0 > 0 } ? Self.normalized(lengths) : shares
        return .split(axis, children.map { $0.withShares(from: frames) }, measured)
    }

    /// The node at `path` (child indexes from here).
    func node(at path: [Int]) -> VideoDockNode? {
        guard let first = path.first else { return self }
        guard case .split(_, let children, _) = self, children.indices.contains(first) else { return nil }
        return children[first].node(at: Array(path.dropFirst()))
    }

    /// The split at `path` with new shares.
    func settingShares(_ new: [Double], at path: [Int]) -> VideoDockNode {
        guard case .split(let axis, var children, let shares) = self else { return self }
        guard let first = path.first else { return .split(axis, children, new.count == shares.count ? Self.normalized(new) : shares) }
        guard children.indices.contains(first) else { return self }
        children[first] = children[first].settingShares(new, at: Array(path.dropFirst()))
        return .split(axis, children, shares)
    }
}

/// Where everything docked goes in the editor's room: each panel's frame
/// and each border between two of them.
struct VideoDockLayout: Equatable {
    static let border: CGFloat = 1

    struct Border: Equatable {
        /// The split it divides (child indexes from the top).
        let path: [Int]
        /// Between child `index` and `index + 1`.
        let index: Int
        let axis: VideoDockNode.Axis
        let frame: CGRect
    }

    var frames: [VideoPanelKind: CGRect] = [:]
    var borders: [Border] = []

    init(_ node: VideoDockNode, in rect: CGRect) {
        place(node, in: rect, path: [])
    }

    private mutating func place(_ node: VideoDockNode, in rect: CGRect, path: [Int]) {
        switch node {
        case .panel(let kind):
            frames[kind] = rect.integral
        case .split(let axis, let children, let shares):
            let length = axis == .horizontal ? rect.width : rect.height
            let sizes = Self.sizes(length: length - CGFloat(children.count - 1) * Self.border, shares: shares,
                                   minimums: children.map { axis == .horizontal ? $0.minimumSize.width : $0.minimumSize.height })
            var at = axis == .horizontal ? rect.minX : rect.minY
            for (index, child) in children.enumerated() {
                let frame = axis == .horizontal
                    ? CGRect(x: at, y: rect.minY, width: sizes[index], height: rect.height)
                    : CGRect(x: rect.minX, y: at, width: rect.width, height: sizes[index])
                place(child, in: frame, path: path + [index])
                at += sizes[index]
                if index < children.count - 1 {
                    let line = axis == .horizontal
                        ? CGRect(x: at, y: rect.minY, width: Self.border, height: rect.height)
                        : CGRect(x: rect.minX, y: at, width: rect.width, height: Self.border)
                    borders.append(Border(path: path, index: index, axis: axis, frame: line))
                    at += Self.border
                }
            }
        }
    }

    /// Lengths from shares, each at least its minimum while there's room
    /// (the others give way, in proportion); with no room, in proportion.
    static func sizes(length: CGFloat, shares: [Double], minimums: [CGFloat]) -> [CGFloat] {
        let shares = VideoDockNode.normalized(shares)
        var sizes = shares.map { CGFloat($0) * max(length, 0) }
        guard minimums.reduce(0, +) <= length else {
            let total = minimums.reduce(0, +)
            return minimums.map { total > 0 ? $0 / total * max(length, 0) : 0 }
        }
        // Raise the ones under their minimum; take it from the others.
        for _ in 0..<sizes.count {
            let short = sizes.indices.filter { sizes[$0] < minimums[$0] - 0.5 }
            guard !short.isEmpty else { break }
            var needed: CGFloat = 0
            for i in short {
                needed += minimums[i] - sizes[i]
                sizes[i] = minimums[i]
            }
            let givers = sizes.indices.filter { !short.contains($0) && sizes[$0] > minimums[$0] }
            let spare = givers.map { sizes[$0] - minimums[$0] }.reduce(0, +)
            guard spare > 0 else { break }
            for i in givers { sizes[i] -= needed * (sizes[i] - minimums[i]) / spare }
        }
        return sizes.map { $0.rounded() }
    }

    /// Which side of `frame` a point at `location` lands on: the nearest
    /// edge (the frame cut along its diagonals).
    static func side(of frame: CGRect, at location: CGPoint) -> VideoDockSide {
        let x = (location.x - frame.minX) / max(frame.width, 1)
        let y = (location.y - frame.minY) / max(frame.height, 1)
        let distances: [(VideoDockSide, CGFloat)] = [(.left, x), (.right, 1 - x), (.top, y), (.bottom, 1 - y)]
        return distances.min { $0.1 < $1.1 }!.0
    }

    /// The half of `frame` a panel dropped on `side` would take.
    static func dropZone(of frame: CGRect, side: VideoDockSide) -> CGRect {
        switch side {
        case .left: return CGRect(x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height)
        case .right: return CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
        case .top: return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height / 2)
        case .bottom: return CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: frame.height / 2)
        }
    }
}

/// A panel in a window of its own: where, and on which screen.
struct VideoFloatingPanel: Codable, Equatable {
    var kind: VideoPanelKind
    /// The window's frame (screen coordinates).
    var frame: CGRect
    /// The screen it was on (its display number), or nil.
    var screen: UInt32?

    /// Where it opens: where it was, or on the main screen when that
    /// screen is gone (moved fully onto it).
    static func restoredFrame(_ frame: CGRect, screen: UInt32?, screens: [(id: UInt32, frame: CGRect)], main: CGRect) -> CGRect {
        if let screen, screens.contains(where: { $0.id == screen }) { return frame }
        // Another screen that holds most of it (screens re-numbered).
        if screen == nil, let holding = screens.first(where: { $0.frame.intersects(frame) }) { return fit(frame, in: holding.frame) }
        return fit(frame, in: main)
    }

    static func fit(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var frame = frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }
}

/// The whole arrangement: what's docked where, what floats, remembered on
/// this Mac and saved by name.
struct VideoDockArrangement: Codable, Equatable {
    var docked: VideoDockNode = .standard
    var floating: [VideoFloatingPanel] = []

    static let standard = VideoDockArrangement()

    /// As 1.17.0 drew it: nothing moved (the widths and the timeline's
    /// height are still VideoEditorPanelLayout's and the divider's).
    var isStandard: Bool { floating.isEmpty && docked.isStandardShape }

    /// `kind` floating at `frame` (out of the docked ones; never the last
    /// docked panel).
    func floating(_ kind: VideoPanelKind, frame: CGRect, screen: UInt32?) -> VideoDockArrangement? {
        var next = self
        if docked.contains(kind) {
            guard let rest = docked.removing(kind) else { return nil }
            next.docked = rest
        }
        next.floating.removeAll { $0.kind == kind }
        next.floating.append(VideoFloatingPanel(kind: kind, frame: frame, screen: screen))
        return next
    }

    /// A floating panel docked again: next to `target`, or where it is in
    /// the standard layout (Dock).
    func docking(_ kind: VideoPanelKind, at side: VideoDockSide? = nil, of target: VideoPanelKind? = nil) -> VideoDockArrangement {
        var next = self
        next.floating.removeAll { $0.kind == kind }
        if let side, let target, next.docked.contains(target) {
            next.docked = next.docked.removing(kind).map { $0.inserting(kind, at: side, of: target) } ?? .panel(kind)
            return next
        }
        guard !next.docked.contains(kind) else { return next }
        next.docked = Self.homeSide(of: kind, in: next.docked).map { next.docked.inserting(kind, at: $0.side, of: $0.target) }
            ?? .split(.vertical, [next.docked, .panel(kind)], [0.6, 0.4])
        return next
    }

    /// Where a panel goes back to (Dock): its side of a panel it sits next
    /// to in the standard layout.
    static func homeSide(of kind: VideoPanelKind, in node: VideoDockNode) -> (side: VideoDockSide, target: VideoPanelKind)? {
        let choices: [VideoPanelKind: [(VideoDockSide, VideoPanelKind)]] = [
            .library: [(.left, .player), (.left, .properties), (.top, .timeline)],
            .player: [(.right, .library), (.left, .properties), (.top, .timeline)],
            .properties: [(.right, .player), (.right, .library), (.top, .timeline)],
            .timeline: [(.bottom, .player), (.bottom, .library), (.bottom, .properties)],
            .agent: [(.bottom, .properties), (.right, .player), (.right, .library)],
            .assistant: [(.bottom, .properties), (.right, .player), (.right, .library)],
        ]
        for (side, target) in choices[kind] ?? [] where node.contains(target) {
            if kind == .timeline {
                // Under everything across the top.
                return nil
            }
            return (side, target)
        }
        return nil
    }
}
