import AppKit
import SwiftUI

// MARK: - Roll (1.21.0)

/// Over a cut between two clips that touch: dragging it moves the cut,
/// changing both clips and nothing else (the video keeps its length).
struct VideoRollHandle: View {
    static let width: CGFloat = 10
    let model: VideoEditorModel
    let hover: VideoTimelineHover
    /// The clip before the cut.
    let clip: UUID
    let cut: Double
    let pointsPerSecond: CGFloat
    let height: CGFloat
    @State private var origin: Double?

    private func currentCut() -> Double? {
        if let item = model.project.layerItem(clip) { return item.end }
        return model.segments.first { $0.id == clip }?.timelineEnd
    }

    var body: some View {
        Rectangle()
            .fill(Color.yellow.opacity(origin == nil ? 0.001 : 0.9))
            .frame(width: origin == nil ? Self.width : 2, height: height)
            .frame(width: Self.width, height: height)
            .contentShape(Rectangle())
            .onHover { inside in
                (inside ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                hover.setTrim(inside ? .roll : nil)
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if origin == nil {
                            origin = cut
                            model.pause()
                        }
                        guard let origin, let now = currentCut() else { return }
                        let target = origin + Double(value.translation.width / pointsPerSecond)
                        model.roll(clip: clip, by: target - now, coalesce: true)
                    }
                    .onEnded { _ in
                        origin = nil
                        model.endRollOrSlide()
                    }
            )
            .help(L("Drag to roll this cut: the clips on both sides change, with no gap"))
            .accessibilityElement()
            .accessibilityLabel(L("Cut at \(VideoEditorModel.timecode(cut))"))
            .accessibilityAdjustableAction { direction in
                model.roll(clip: clip, by: direction == .increment ? 1.0 / 30 : -1.0 / 30)
                model.endRollOrSlide()
            }
    }
}
