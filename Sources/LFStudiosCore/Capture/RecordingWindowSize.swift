import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Window mode's "Window size": resizes the chosen window so the recording
/// comes out an exact pixel size (1920×1080 is a 960×540-point window on a
/// Retina display), centered on its display, through Accessibility.
/// "Restore size" puts it back.
enum RecordingWindowSize {
    struct Preset: Equatable {
        let width: Int
        let height: Int
    }

    static let presets = [
        Preset(width: 1280, height: 720),
        Preset(width: 1920, height: 1080),
        Preset(width: 1440, height: 900),
        Preset(width: 1080, height: 1080),
        Preset(width: 1080, height: 1920),
    ]

    static let pixelRange = 64...8192

    /// The window's size in points for this many pixels.
    static func points(width: Int, height: Int, scale: CGFloat) -> CGSize {
        let scale = max(scale, 1)
        return CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
    }

    /// Whether a window that size fits in the display's free area.
    static func fits(width: Int, height: Int, scale: CGFloat, in visible: CGRect) -> Bool {
        let size = points(width: width, height: height, scale: scale)
        return size.width <= visible.width + 0.5 && size.height <= visible.height + 0.5
    }

    /// The largest size of the same shape that fits, in even pixels.
    static func largestFitting(width: Int, height: Int, scale: CGFloat, in visible: CGRect) -> Preset {
        let size = points(width: width, height: height, scale: scale)
        let shrink = min(visible.width / max(size.width, 1), visible.height / max(size.height, 1), 1)
        func even(_ value: CGFloat) -> Int { max(Int((value / 2).rounded(.down)) * 2, 2) }
        return Preset(width: even(CGFloat(width) * shrink), height: even(CGFloat(height) * shrink))
    }

    /// Centered in the display's free area (AppKit coordinates).
    static func centered(_ size: CGSize, in visible: CGRect) -> CGRect {
        CGRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    // MARK: Resizing

    enum Outcome: Equatable {
        /// Exactly the size asked for.
        case resized(Preset)
        /// The app kept it at another size (its smallest or largest).
        case limited(asked: Preset, got: Preset)
        /// The app doesn't let this window be resized.
        case notResizable
        /// The window couldn't be found to resize.
        case notFound

        /// What to tell the user (nil: nothing went wrong).
        func message(appName: String) -> String? {
            switch self {
            case .resized:
                return nil
            case let .limited(asked, got):
                // Pixel sizes as plain digits ("1920", not "1,920").
                let (gotWidth, gotHeight) = (String(got.width), String(got.height))
                let (askedWidth, askedHeight) = (String(asked.width), String(asked.height))
                if got.width > asked.width || got.height > asked.height {
                    return L("“\(appName)” keeps this window at least \(gotWidth) × \(gotHeight) pixels, so it can't be made \(askedWidth) × \(askedHeight).")
                }
                return L("“\(appName)” keeps this window at most \(gotWidth) × \(gotHeight) pixels, so it can't be made \(askedWidth) × \(askedHeight).")
            case .notResizable:
                return L("“\(appName)” doesn't let this window be resized.")
            case .notFound:
                return L("Couldn't find that window to resize it. Choose it again and try once more.")
            }
        }
    }

    /// Resizes the window to `pixels` and centers it in `visible`; reads
    /// the size back to see what the app allowed.
    @MainActor
    static func resize(_ window: RecordingResizableWindow, toPixels pixels: Preset, scale: CGFloat, in visible: CGRect) -> Outcome {
        guard window.isResizable else { return .notResizable }
        let target = centered(points(width: pixels.width, height: pixels.height, scale: scale), in: visible)
        window.setFrame(target)
        guard let actual = window.frame else { return .notFound }
        // An app that keeps a minimum size: centered at the size it kept.
        if abs(actual.width - target.width) > 0.5 || abs(actual.height - target.height) > 0.5 {
            window.setFrame(centered(actual.size, in: visible))
        }
        let got = Preset(width: Int((actual.width * scale).rounded()), height: Int((actual.height * scale).rounded()))
        // A point of rounding either way is the same size.
        if abs(got.width - pixels.width) <= Int(scale.rounded()), abs(got.height - pixels.height) <= Int(scale.rounded()) {
            return .resized(pixels)
        }
        return .limited(asked: pixels, got: got)
    }

    /// The frame bar's "Fit a window to the frame": the window takes
    /// exactly that place and size; read back to see what the app allowed.
    @MainActor
    static func fit(_ window: RecordingResizableWindow, to target: CGRect, scale: CGFloat) -> Outcome {
        guard window.isResizable else { return .notResizable }
        let pixels = Preset(width: Int((target.width * scale).rounded()), height: Int((target.height * scale).rounded()))
        window.setFrame(target)
        guard let actual = window.frame else { return .notFound }
        // An app that keeps a minimum size: centered on the frame instead.
        if abs(actual.width - target.width) > 0.5 || abs(actual.height - target.height) > 0.5 {
            window.setFrame(centered(actual.size, in: target))
        }
        let got = Preset(width: Int((actual.width * scale).rounded()), height: Int((actual.height * scale).rounded()))
        if abs(got.width - pixels.width) <= Int(scale.rounded()), abs(got.height - pixels.height) <= Int(scale.rounded()) {
            return .resized(pixels)
        }
        return .limited(asked: pixels, got: got)
    }
}

/// A window whose frame can be read and set (AppKit coordinates).
@MainActor
protocol RecordingResizableWindow: AnyObject {
    var frame: CGRect? { get }
    var isResizable: Bool { get }
    func setFrame(_ frame: CGRect)
}

/// Another app's window, moved through Accessibility.
@MainActor
final class RecordingAccessibilityWindow: RecordingResizableWindow {
    private let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    /// The Accessibility window for a ScreenCaptureKit window: the one of
    /// its app at the same place and size.
    static func find(_ window: SCWindow) -> RecordingAccessibilityWindow? {
        guard let pid = window.owningApplication?.processID else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        let target = window.frame // CG space, top-left origin, like AX
        let best = windows.min { a, b in distance(cgFrame(a), target) < distance(cgFrame(b), target) }
        guard let best, distance(cgFrame(best), target) < 40 else { return nil }
        return RecordingAccessibilityWindow(element: best)
    }

    private static func cgFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        // swiftlint:disable:next force_cast
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private static func distance(_ a: CGRect?, _ b: CGRect) -> CGFloat {
        guard let a else { return .infinity }
        return abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    var frame: CGRect? {
        Self.cgFrame(element).map(ScreenCoordinates.appKitRect(fromCG:))
    }

    var isResizable: Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success && settable.boolValue
    }

    func setFrame(_ frame: CGRect) {
        let cg = ScreenCoordinates.cgRect(fromAppKit: frame)
        var origin = cg.origin
        var size = cg.size
        // Move, size, and move again: some apps only take a size that fits
        // where the window is.
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        }
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        }
    }
}

/// Where each window was before it was resized, for "Restore size".
@MainActor
enum RecordingWindowSizeMemory {
    private static var frames: [CGWindowID: CGRect] = [:]

    static func remember(_ frame: CGRect, for window: CGWindowID) {
        // The first size is the one to go back to.
        if frames[window] == nil { frames[window] = frame }
    }

    static func previous(for window: CGWindowID) -> CGRect? { frames[window] }

    static func forget(_ window: CGWindowID) { frames[window] = nil }
}
