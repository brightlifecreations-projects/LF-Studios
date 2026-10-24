import AppKit
import SwiftUI

/// Drag handles over the caption and the shortcut keys on the paused
/// preview: drag to place them anywhere (snapping to the middle and the
/// safe margins), right-click to reset. Each handle sits on the box the
/// renderer actually drew (`VideoTextLayout`), so it never drifts from the
/// picture. See VideoTextPlacement.swift.
struct VideoTextHandles: View {
    @ObservedObject var model: VideoEditorModel
    let layout: VideoTextLayout
    let viewSize: CGSize

    enum Kind: Equatable {
        case caption(UUID)
        case keys
    }

    /// What a drag moves.
    private enum Target: Equatable {
        /// Every caption without a spot of its own.
        case allCaptions
        /// This caption only.
        case caption(UUID)
        case keys
    }

    private struct Drag {
        var kind: Kind
        var target: Target
        /// The box when the drag began (view points, top-left origin).
        var origin: CGRect
        var guides: Set<VideoTextSnapGuide> = []
    }

    @State private var drag: Drag?
    @State private var hovering: Kind?

    /// How close a drag comes to a guide before it snaps (view points).
    private static let snapDistance: CGFloat = 6

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let drag {
                guideLines(drag.guides)
            }
            if let caption = layout.caption, let id = caption.captionID {
                handle(.caption(id), box: caption.rect(in: viewSize))
            }
            if let keys = layout.keys {
                handle(.keys, box: keys.rect(in: viewSize))
            }
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
    }

    // MARK: Handles

    private func hasOwnPlacement(_ kind: Kind) -> Bool {
        guard case .caption(let id) = kind else { return false }
        return model.project.captions.first(where: { $0.id == id })?.placement != nil
    }

    /// A caption moves alone once it has its own spot, or while it's the one
    /// selected; otherwise every caption moves together.
    private func target(for kind: Kind) -> Target {
        switch kind {
        case .keys: return .keys
        case .caption(let id):
            if hasOwnPlacement(kind) || model.selection == .caption(id) { return .caption(id) }
            return .allCaptions
        }
    }

    private func handle(_ kind: Kind, box: CGRect) -> some View {
        let active = drag?.kind == kind || hovering == kind
        let padded = box.insetBy(dx: -4, dy: -4)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(drag?.kind == kind ? 0.95 : (active ? 0.7 : 0)), style: StrokeStyle(lineWidth: 1.5, dash: drag?.kind == kind ? [] : [5, 3]))
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(active ? 0.06 : 0.001)))
                .frame(width: padded.width, height: padded.height)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .offset(x: padded.minX, y: padded.minY)
                .onHover { inside in
                    hovering = inside ? kind : (hovering == kind ? nil : hovering)
                    guard drag == nil else { return }
                    (inside ? NSCursor.openHand : NSCursor.arrow).set()
                }
                .gesture(dragGesture(kind, box: box))
                .contextMenu { menu(kind) }
                .help(kind == .keys ? L("Shortcut keys — drag to move them, right-click to reset") : L("Caption — drag to move it, right-click for more"))
            if hasOwnPlacement(kind) {
                VideoCustomPositionBadge()
                    .offset(x: padded.minX, y: max(padded.minY - 20, 2))
                    .allowsHitTesting(false)
            }
        }
    }

    private func dragGesture(_ kind: Kind, box: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(VideoStageInteractionLayer.space))
            .onChanged { value in
                if drag == nil {
                    drag = Drag(kind: kind, target: target(for: kind), origin: box)
                }
                guard var current = drag, hypot(value.translation.width, value.translation.height) > 2 else { return }
                NSCursor.closedHand.set()
                let center = CGPoint(x: current.origin.midX + value.translation.width, y: current.origin.midY + value.translation.height)
                let snapped = VideoTextPlacementGeometry.snapped(center: center, size: current.origin.size, outputSize: viewSize, threshold: Self.snapDistance)
                current.guides = snapped.guides
                drag = current
                move(current.target, to: snapped.placement)
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) > 2
                let ended = drag
                drag = nil
                model.endGesture()
                NSCursor.openHand.set()
                if !moved, let ended {
                    select(ended.kind)
                }
            }
    }

    private func move(_ target: Target, to placement: VideoTextPlacement) {
        switch target {
        case .allCaptions: model.moveCaptions(to: placement, coalesce: "move-captions")
        case .caption(let id): model.moveCaption(id, to: placement, coalesce: "move-caption-\(id)")
        case .keys: model.moveKeystrokes(to: placement, coalesce: "move-keys")
        }
    }

    /// A click: the caption's (or the keys') settings.
    private func select(_ kind: Kind) {
        switch kind {
        case .caption(let id):
            model.selection = .caption(id)
            model.inspectorTab = .captions
        case .keys:
            model.inspectorTab = .cursor
        }
    }

    @ViewBuilder
    private func menu(_ kind: Kind) -> some View {
        switch kind {
        case .caption(let id):
            let own = hasOwnPlacement(kind)
            Button(L("Reset to default position")) { model.resetCaptionPosition(id) }
                .disabled(!own)
            Button(L("Apply this position to all captions")) { model.applyCaptionPositionToAll(from: id) }
                .disabled(!own)
            Divider()
            Button(L("Reset position")) { model.resetCaptionPosition() }
                .disabled(model.project.captionStyle.placement == nil)
        case .keys:
            Button(L("Reset position")) { model.resetKeystrokePosition() }
                .disabled(model.project.keystrokeStyle.placement == nil)
        }
    }

    // MARK: Guides

    private func guideLines(_ guides: Set<VideoTextSnapGuide>) -> some View {
        let margin = VideoTextPlacementGeometry.margin(outputSize: viewSize)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(guides), id: \.self) { guide in
                switch guide {
                case .centerX:
                    line(from: CGPoint(x: viewSize.width / 2, y: 0), to: CGPoint(x: viewSize.width / 2, y: viewSize.height))
                case .centerY:
                    line(from: CGPoint(x: 0, y: viewSize.height / 2), to: CGPoint(x: viewSize.width, y: viewSize.height / 2))
                case .top:
                    line(from: CGPoint(x: 0, y: margin), to: CGPoint(x: viewSize.width, y: margin))
                case .bottom:
                    line(from: CGPoint(x: 0, y: viewSize.height - margin), to: CGPoint(x: viewSize.width, y: viewSize.height - margin))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func line(from start: CGPoint, to end: CGPoint) -> some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(VideoEditorTheme.caption, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
    }
}
