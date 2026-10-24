import Combine
import CoreGraphics
import Foundation

/// Where a caption or the shortcut keys sit once moved by hand: the center
/// of the box as a fraction of the frame (0...1, y down), so the spot holds
/// for any aspect ratio. Always drawn kept inside the frame's safe margin
/// (`VideoTextPlacementGeometry.rect`).
struct VideoTextPlacement: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    private enum CodingKeys: String, CodingKey { case x, y }

    /// A stray value in a project file lands back inside the frame.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(Double.self, forKey: .x)
        let y = try c.decode(Double.self, forKey: .y)
        self.x = x.isFinite ? min(max(x, 0), 1) : 0.5
        self.y = y.isFinite ? min(max(y, 0), 1) : 0.5
    }
}

/// The lines a dragged caption or keycap snaps to.
enum VideoTextSnapGuide: Hashable {
    case centerX
    case centerY
    /// The box's top on the top safe margin (where the Top preset puts it).
    case top
    /// The box's bottom on the bottom safe margin (the Bottom preset).
    case bottom
}

/// Turns a placement into a box on the frame, the same way for the
/// renderer (preview and every export) and the preview's drag handles.
enum VideoTextPlacementGeometry {
    /// Distance kept from each edge, in output pixels: the margin the
    /// Top/Bottom presets use.
    static func margin(outputSize: CGSize) -> CGFloat {
        (min(outputSize.width, outputSize.height) * 0.055).rounded()
    }

    /// The box of a layer of `size` centered on `placement`, kept inside the
    /// safe margin (centered when it's larger than the room inside it), in
    /// output pixels with a top-left origin.
    static func rect(size: CGSize, placement: VideoTextPlacement, outputSize: CGSize) -> CGRect {
        let margin = margin(outputSize: outputSize)
        func axis(center: CGFloat, length: CGFloat, total: CGFloat) -> CGFloat {
            let room = total - margin * 2
            guard length <= room else { return (total - length) / 2 }
            return min(max(center - length / 2, margin), total - margin - length)
        }
        let x = axis(center: CGFloat(placement.x) * outputSize.width, length: size.width, total: outputSize.width)
        let y = axis(center: CGFloat(placement.y) * outputSize.height, length: size.height, total: outputSize.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The placement of a box at `rect` (top-left origin) on the frame.
    static func placement(of rect: CGRect, outputSize: CGSize) -> VideoTextPlacement {
        VideoTextPlacement(
            x: Double(rect.midX / max(outputSize.width, 1)),
            y: Double(rect.midY / max(outputSize.height, 1))
        )
    }

    /// A box of `size` dragged so its center is at `center` (top-left
    /// origin): snapped to the guides within `threshold`, then kept inside
    /// the frame. Returns the placement to store and the guides it's on.
    static func snapped(center: CGPoint, size: CGSize, outputSize: CGSize, threshold: CGFloat) -> (placement: VideoTextPlacement, guides: Set<VideoTextSnapGuide>) {
        let margin = margin(outputSize: outputSize)
        var center = center
        var guides: Set<VideoTextSnapGuide> = []
        if abs(center.x - outputSize.width / 2) <= threshold {
            center.x = outputSize.width / 2
            guides.insert(.centerX)
        }
        let vertical: [(VideoTextSnapGuide, CGFloat)] = [
            (.centerY, outputSize.height / 2),
            (.top, margin + size.height / 2),
            (.bottom, outputSize.height - margin - size.height / 2),
        ]
        if let nearest = vertical.min(by: { abs($0.1 - center.y) < abs($1.1 - center.y) }), abs(nearest.1 - center.y) <= threshold {
            center.y = nearest.1
            guides.insert(nearest.0)
        }
        let kept = rect(size: size, placement: VideoTextPlacement(x: Double(center.x / max(outputSize.width, 1)), y: Double(center.y / max(outputSize.height, 1))), outputSize: outputSize)
        return (placement(of: kept, outputSize: outputSize), guides)
    }
}

// MARK: - Project

extension VideoDemoProject {
    /// Where a caption is drawn: its own spot, else where every caption
    /// goes, else nil (stacked at the Top/Bottom preset).
    func captionPlacement(for id: UUID) -> VideoTextPlacement? {
        captions.first(where: { $0.id == id })?.placement ?? captionStyle.placement
    }

    /// Moves every caption that has no spot of its own (nil: back to the
    /// Top/Bottom preset).
    mutating func placeAllCaptions(at placement: VideoTextPlacement?) {
        captionStyle.placement = placement
    }

    /// Moves one caption only (nil: it follows the others again).
    mutating func placeCaption(_ id: UUID, at placement: VideoTextPlacement?) {
        guard let index = captions.firstIndex(where: { $0.id == id }) else { return }
        captions[index].placement = placement
    }

    /// "Reset position": every caption back to the Bottom preset; captions
    /// with a spot of their own keep it.
    mutating func resetCaptionPlacement() {
        captionStyle.placement = nil
        captionStyle.position = .bottom
    }

    /// Where this caption is, for every caption: it becomes everyone's spot
    /// and no caption keeps one of its own.
    mutating func applyCaptionPlacementToAll(from id: UUID) {
        guard let placement = captionPlacement(for: id) else { return }
        captionStyle.placement = placement
        for index in captions.indices {
            captions[index].placement = nil
        }
    }

    /// A Top/Bottom preset for every caption (their own spots stay).
    mutating func setCaptionPreset(_ position: VideoTextPosition) {
        captionStyle.position = position
        captionStyle.placement = nil
    }

    var hasCaptionsWithOwnPlacement: Bool {
        captions.contains { $0.placement != nil }
    }

    /// The shortcut keys at a spot (nil: back to the Top/Bottom preset).
    mutating func placeKeystrokes(at placement: VideoTextPlacement?) {
        keystrokeStyle.placement = placement
    }

    mutating func resetKeystrokePlacement() {
        keystrokeStyle.placement = nil
        keystrokeStyle.position = .bottom
    }

    mutating func setKeystrokePreset(_ position: VideoTextPosition) {
        keystrokeStyle.position = position
        keystrokeStyle.placement = nil
    }
}

/// Where a frame's caption and shortcut keys were drawn, as fractions of
/// the frame (top-left origin): what the preview's drag handles grab.
struct VideoTextLayout: Equatable {
    struct Box: Equatable {
        /// 0...1 of the frame, top-left origin.
        var rect: CGRect
        /// The caption drawn (nil: the shortcut keys).
        var captionID: UUID?

        init(rect: CGRect, outputSize: CGSize, captionID: UUID?) {
            let width = max(outputSize.width, 1)
            let height = max(outputSize.height, 1)
            self.rect = CGRect(x: rect.minX / width, y: rect.minY / height, width: rect.width / width, height: rect.height / height)
            self.captionID = captionID
        }

        /// The box in a view of `size` (top-left origin).
        func rect(in size: CGSize) -> CGRect {
            CGRect(x: rect.minX * size.width, y: rect.minY * size.height, width: rect.width * size.width, height: rect.height * size.height)
        }
    }

    var caption: Box?
    var keys: Box?
}

/// The live preview's `VideoTextLayout`, for SwiftUI.
@MainActor
final class VideoTextLayoutStore: ObservableObject {
    @Published var layout = VideoTextLayout()
}
