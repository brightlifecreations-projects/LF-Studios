import CoreGraphics
import Foundation

/// The camera as chosen in the recording bar before recording (Camera
/// shape, the preview's place and size): saved with the recording, and the
/// look a new recording opens with. Only what was chosen is in it — a
/// recording made without touching these opens like any other.
struct VideoRecordingCameraSetup: Codable, Equatable {
    var shape: VideoWebcamSettings.Shape = .circle
    /// Free's width / height.
    var freeAspect: Double?
    /// Set with the Roundness slider (nil: the shape's own corners).
    var roundness: Double?
    /// The preview's place in the recording frame (nil: it wasn't in the
    /// frame, or wasn't moved: the editor's usual spot).
    var placement: VideoWebcamSettings.Placement?

    /// Nothing differs from a plain new recording's camera.
    var isPlain: Bool { shape == .circle && roundness == nil && placement == nil }

    /// The webcam settings a new recording opens with.
    func applied(to webcam: VideoWebcamSettings) -> VideoWebcamSettings {
        var webcam = webcam
        webcam.shape = shape
        webcam.freeAspect = shape == .free ? freeAspect : nil
        webcam.roundness = roundness.map { min(max($0, 0), 1) }
        webcam.placement = placement
        return webcam
    }

    /// The settings the preview is drawn with.
    var webcam: VideoWebcamSettings { applied(to: .plain) }
}

extension VideoDemoProject {
    /// What was chosen before recording, on a new recording's camera.
    mutating func apply(cameraSetup setup: VideoRecordingCameraSetup?) {
        guard let setup, !setup.isPlain else { return }
        webcam = setup.applied(to: webcam)
    }
}

/// The camera preview before and while recording, measured against the
/// recording frame: what's inside the frame is where the camera goes in the
/// video (the plain style draws the video edge to edge, so the frame is the
/// video).
enum VideoCameraPreviewGeometry {
    /// The smallest the preview gets on screen, in points.
    static let minimumSide: CGFloat = 48

    /// Where the camera sits in a new recording's video, on `frame` (screen
    /// points, bottom-left origin) — the preview's spot when nobody moved it.
    static func defaultRect(_ setup: VideoRecordingCameraSetup, in frame: CGRect) -> CGRect {
        var plain = setup
        plain.placement = nil
        return rect(plain, in: frame)
    }

    /// The camera's rect on `frame` for `setup` (screen points).
    static func rect(_ setup: VideoRecordingCameraSetup, in frame: CGRect) -> CGRect {
        let local = VideoFrameRenderer.webcamRect(setup.webcam, outputSize: frame.size)
        var rect = local.offsetBy(dx: frame.minX, dy: frame.minY)
        if rect.width < minimumSide || rect.height < minimumSide {
            // A tiny frame: still a preview you can see.
            let grow = max(minimumSide / max(rect.width, 1), minimumSide / max(rect.height, 1))
            rect = CGRect(x: rect.midX - rect.width * grow / 2, y: rect.midY - rect.height * grow / 2, width: rect.width * grow, height: rect.height * grow)
        }
        return rect
    }

    /// Whether the preview counts as in the video: at least half of it
    /// inside the frame.
    static func isInside(_ preview: CGRect, frame: CGRect) -> Bool {
        let inside = preview.intersection(frame)
        guard !inside.isNull, preview.width > 0, preview.height > 0 else { return false }
        return inside.width * inside.height >= preview.width * preview.height * 0.5
    }

    /// The preview's place in the video (nil: outside the frame — the
    /// editor puts it in its usual spot).
    static func placement(of preview: CGRect, in frame: CGRect) -> VideoWebcamSettings.Placement? {
        guard frame.width > 1, frame.height > 1, isInside(preview, frame: frame) else { return nil }
        let width = min(preview.width, frame.width)
        let height = min(preview.height, frame.height)
        // Kept wholly inside, as the video draws it.
        let midX = min(max(preview.midX, frame.minX + width / 2), frame.maxX - width / 2)
        let midY = min(max(preview.midY, frame.minY + height / 2), frame.maxY - height / 2)
        return VideoWebcamSettings.Placement(
            x: Double((midX - frame.minX) / frame.width),
            y: Double((frame.maxY - midY) / frame.height),
            width: Double(width / frame.width)
        )
    }

    /// What's saved for the recording: the setup with the preview's place,
    /// or no place when it's where the editor puts the camera anyway (a
    /// new recording opens exactly as before).
    static func setup(_ chosen: VideoRecordingCameraSetup, preview: CGRect?, frame: CGRect) -> VideoRecordingCameraSetup {
        var setup = chosen
        setup.placement = nil
        guard let preview, let placement = placement(of: preview, in: frame) else { return setup }
        let usual = defaultRect(chosen, in: frame)
        let tolerance = max(2, min(frame.width, frame.height) * 0.004)
        if abs(preview.midX - usual.midX) <= tolerance, abs(preview.midY - usual.midY) <= tolerance, abs(preview.width - usual.width) <= tolerance {
            return setup
        }
        setup.placement = placement
        return setup
    }

    /// Where the preview goes for a remembered place on `frame`.
    static func previewRect(_ setup: VideoRecordingCameraSetup, in frame: CGRect) -> CGRect {
        rect(setup, in: frame)
    }

    /// The label under the preview: "Camera: 25% of width, bottom right",
    /// or that it isn't in the video.
    static func label(preview: CGRect, frame: CGRect) -> String {
        guard let placement = placement(of: preview, in: frame) else {
            return L("Not in video — position set in the editor")
        }
        let percent = String(Int((placement.width * 100).rounded()))
        return L("Camera: \(percent)% of width, \(spot(placement))")
    }

    /// The part of the video the camera is in, in words.
    static func spot(_ placement: VideoWebcamSettings.Placement) -> String {
        let column = placement.x < 1.0 / 3 ? 0 : (placement.x > 2.0 / 3 ? 2 : 1)
        let row = placement.y < 1.0 / 3 ? 0 : (placement.y > 2.0 / 3 ? 2 : 1)
        switch (row, column) {
        case (0, 0): return L("top left")
        case (0, 1): return L("top")
        case (0, 2): return L("top right")
        case (1, 0): return L("left")
        case (1, 2): return L("right")
        case (2, 0): return L("bottom left")
        case (2, 1): return L("bottom")
        case (2, 2): return L("bottom right")
        default: return L("center")
        }
    }
}

// MARK: - Resizing by hand (the preview's handles, and the editor's)

/// What a handle on the camera moves.
enum VideoCameraHandle: CaseIterable, Equatable {
    case move
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    /// The handles drawn on the camera's edges and corners.
    static var resizing: [VideoCameraHandle] { allCases.filter { $0 != .move } }

    var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
    var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
    var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }

    /// Where it sits on a rect, as a unit point with y down.
    var unit: CGPoint {
        CGPoint(x: movesLeft ? 0 : (movesRight ? 1 : 0.5), y: movesTop ? 0 : (movesBottom ? 1 : 0.5))
    }
}

extension VideoCameraPreviewGeometry {
    /// `rect` (y down) after dragging `handle` by `delta`. With `aspect`, the
    /// shape is kept: the opposite corner (or edge's middle) stays put.
    /// Without it (Free), width and height change on their own.
    static func resized(_ rect: CGRect, handle: VideoCameraHandle, by delta: CGSize, aspect: CGFloat?, minimum: CGFloat, within bounds: CGRect? = nil) -> CGRect {
        if handle == .move {
            var moved = rect.offsetBy(dx: delta.width, dy: delta.height)
            if let bounds {
                moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
                moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
            }
            return moved
        }
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesLeft { minX = min(minX + delta.width, maxX - minimum) }
        if handle.movesRight { maxX = max(maxX + delta.width, minX + minimum) }
        if handle.movesTop { minY = min(minY + delta.height, maxY - minimum) }
        if handle.movesBottom { maxY = max(maxY + delta.height, minY + minimum) }
        if let bounds {
            minX = max(minX, bounds.minX); maxX = min(maxX, bounds.maxX)
            minY = max(minY, bounds.minY); maxY = min(maxY, bounds.maxY)
        }
        var width = maxX - minX, height = maxY - minY
        guard let aspect, aspect > 0 else { return CGRect(x: minX, y: minY, width: width, height: height) }
        // Keeping the shape: the side dragged leads (for a corner, whichever
        // moved further), the other follows.
        if handle.isCorner {
            if abs(delta.width) >= abs(delta.height) * aspect { height = width / aspect } else { width = height * aspect }
        } else if handle.movesLeft || handle.movesRight {
            height = width / aspect
        } else {
            width = height * aspect
        }
        if let bounds {
            // Shrunk to fit, still the shape.
            let fit = min(1, bounds.width / max(width, 1), bounds.height / max(height, 1))
            width *= fit
            height *= fit
        }
        if width < minimum || height < minimum {
            let grow = max(minimum / max(width, 1), minimum / max(height, 1))
            width *= grow
            height *= grow
        }
        let x = handle.movesLeft ? rect.maxX - width : (handle.movesRight ? rect.minX : rect.midX - width / 2)
        let y = handle.movesTop ? rect.maxY - height : (handle.movesBottom ? rect.minY : rect.midY - height / 2)
        var result = CGRect(x: x, y: y, width: width, height: height)
        if let bounds {
            result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
            result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        }
        return result
    }
}
