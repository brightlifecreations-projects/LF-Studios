import AppKit
import SwiftUI

// MARK: - Move, resize and turn on the player (1.14.0)

/// The box around something selected on the player: drag inside to move
/// it (it lands on the middle and the edges, with guide lines; ⌘ moves
/// freely), a corner to resize it at its shape, the round knob to turn it
/// (⇧: steps of 15°). Positions are view points from the top left.
struct VideoTransformBox: View {
    /// Where it is, before turning.
    let rect: CGRect
    /// Degrees clockwise.
    let rotation: Double
    let viewSize: CGSize
    var resizes = true
    let help: String
    let rotateLabel: String
    /// A new place (and size) while dragging.
    let changed: (CGRect) -> Void
    /// A new angle while turning.
    let turned: (Double) -> Void
    /// The drag or turn ended.
    let ended: () -> Void

    @State private var origin: CGRect?
    @State private var guides: [VideoAlignmentGuides.Guide] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(guides.enumerated()), id: \.offset) { _, guide in
                let vertical = guide.axis == .vertical
                Rectangle()
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: vertical ? 1 : viewSize.width, height: vertical ? viewSize.height : 1)
                    .offset(x: vertical ? guide.position : 0, y: vertical ? 0 : guide.position)
                    .allowsHitTesting(false)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .background(Color.white.opacity(0.001))
                    .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
                    .gesture(moveGesture)
                    .help(help)
                if resizes {
                    ForEach(0..<4, id: \.self) { corner in
                        let isRight = corner == 1 || corner == 3
                        let isBottom = corner >= 2
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                            .frame(width: 11, height: 11)
                            .contentShape(Circle().inset(by: -7))
                            .position(x: isRight ? rect.width : 0, y: isBottom ? rect.height : 0)
                            .onHover { inside in (inside ? NSCursor.crosshair : NSCursor.arrow).set() }
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                    .onChanged { value in
                                        if origin == nil { origin = rect }
                                        guard let origin else { return }
                                        let along = VideoImageOverlayHandles.unturn(value.translation, by: rotation)
                                        changed(Self.resized(origin, isRight: isRight, isBottom: isBottom, by: along, turned: abs(rotation) > 0.01, minimum: viewSize.width * 0.04))
                                    }
                                    .onEnded { _ in
                                        origin = nil
                                        ended()
                                    }
                            )
                    }
                }
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 1.5, height: 16)
                    .position(x: rect.width / 2, y: -8)
                    .allowsHitTesting(false)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                    .overlay(Image(systemName: "arrow.clockwise").font(.system(size: 7, weight: .bold)).foregroundStyle(Color.accentColor))
                    .frame(width: 14, height: 14)
                    .contentShape(Circle().inset(by: -6))
                    .position(x: rect.width / 2, y: -20)
                    .onHover { inside in (inside ? NSCursor.pointingHand : NSCursor.arrow).set() }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(VideoStageInteractionLayer.space))
                            .onChanged { value in
                                turned(VideoAlignmentGuides.rotation(from: CGPoint(x: rect.midX, y: rect.midY), to: value.location, steps: NSEvent.modifierFlags.contains(.shift)))
                            }
                            .onEnded { _ in ended() }
                    )
                    .help(L("Drag to turn it; hold ⇧ for steps of 15°"))
                    .accessibilityLabel(rotateLabel)
            }
            .frame(width: rect.width, height: rect.height)
            .rotationEffect(.degrees(rotation))
            .offset(x: rect.minX, y: rect.minY)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if origin == nil { origin = rect }
                guard let origin else { return }
                NSCursor.closedHand.set()
                let moved = origin.offsetBy(dx: value.translation.width, dy: value.translation.height)
                let snap = NSEvent.modifierFlags.contains(.command) ? (rect: moved, guides: []) : VideoAlignmentGuides.snap(moved, in: viewSize, threshold: 6)
                guides = snap.guides
                changed(snap.rect)
            }
            .onEnded { _ in
                origin = nil
                guides = []
                ended()
            }
    }

    /// A corner dragged by `translation` (along the box's own sides): the
    /// opposite corner stays put (the middle, when it's turned), the shape
    /// is kept.
    static func resized(_ start: CGRect, isRight: Bool, isBottom: Bool, by translation: CGSize, turned: Bool, minimum: CGFloat) -> CGRect {
        let aspect = start.width / max(start.height, 0.01)
        let fixed = CGPoint(x: isRight ? start.minX : start.maxX, y: isBottom ? start.minY : start.maxY)
        let dragged = CGPoint(x: (isRight ? start.maxX : start.minX) + translation.width, y: (isBottom ? start.maxY : start.minY) + translation.height)
        let width = max(max(abs(dragged.x - fixed.x), abs(dragged.y - fixed.y) * aspect), minimum)
        let height = width / aspect
        let minX = turned ? start.midX - width / 2 : (isRight ? fixed.x : fixed.x - width)
        let minY = turned ? start.midY - height / 2 : (isBottom ? fixed.y : fixed.y - height)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}

/// The handles of the item selected on a track above the main track.
struct VideoLayerItemHandles: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock
    let stored: VideoLayerItem
    let viewSize: CGSize

    var body: some View {
        // Where it is at the playhead (keyframes applied).
        let item = stored.resolved(at: clock.time)
        let r = item.rect(in: viewSize)
        VideoTransformBox(
            rect: CGRect(x: r.minX, y: viewSize.height - r.maxY, width: r.width, height: r.height),
            rotation: item.rotation,
            viewSize: viewSize,
            help: L("Drag to move; drag a corner to resize, the round knob to turn it"),
            rotateLabel: L("Turn it"),
            changed: { rect in
                model.setLayerAnimated(item.id, coalesce: "layer-place-\(item.id)", label: "Move Clip") { placed in
                    placed.width = Double(rect.width / max(viewSize.width, 1))
                    placed.x = Double(rect.midX / max(viewSize.width, 1))
                    placed.y = Double(rect.midY / max(viewSize.height, 1))
                }
            },
            turned: { degrees in
                model.setLayerAnimated(item.id, coalesce: "layer-rotate-\(item.id)", label: "Rotate") { $0.rotation = degrees }
            },
            ended: { model.endGesture() }
        )
    }
}

/// A round knob above something on the player that turns it (text
/// annotations and the camera bubble, 1.14.0). `rect` is where it is, in
/// the player's own coordinates.
struct VideoRotateKnob: View {
    let rect: CGRect
    let label: String
    let turned: (Double?) -> Void
    let ended: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.5, height: 14)
                .offset(x: rect.midX - 0.75, y: rect.minY - 14)
                .allowsHitTesting(false)
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                .overlay(Image(systemName: "arrow.clockwise").font(.system(size: 7, weight: .bold)).foregroundStyle(Color.accentColor))
                .frame(width: 14, height: 14)
                .contentShape(Circle().inset(by: -6))
                .offset(x: rect.midX - 7, y: rect.minY - 27)
                .onHover { inside in (inside ? NSCursor.pointingHand : NSCursor.arrow).set() }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(VideoStageInteractionLayer.space))
                        .onChanged { value in
                            let degrees = VideoAlignmentGuides.rotation(from: CGPoint(x: rect.midX, y: rect.midY), to: value.location, steps: NSEvent.modifierFlags.contains(.shift))
                            turned(abs(degrees) < 0.01 ? nil : degrees)
                        }
                        .onEnded { _ in ended() }
                )
                .help(L("Drag to turn it; hold ⇧ for steps of 15°. Double-click to put it upright."))
                .accessibilityLabel(label)
                .onTapGesture(count: 2) {
                    turned(nil)
                    ended()
                }
        }
    }
}
