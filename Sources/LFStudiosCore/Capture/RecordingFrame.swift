import AppKit
import SwiftUI

/// The frame bar's shape: a ratio like 16:9, kept in lowest terms.
struct RecordingFrameRatio: Codable, Equatable, Hashable {
    let width: Int
    let height: Int

    init(_ width: Int, _ height: Int) {
        let divisor = Self.gcd(max(width, 1), max(height, 1))
        self.width = max(width, 1) / divisor
        self.height = max(height, 1) / divisor
    }

    var text: String { "\(width):\(height)" } // l10n-ignore: a ratio, the same in every language
    var isPortrait: Bool { height > width }

    struct Preset {
        let ratio: RecordingFrameRatio
        /// The label on its button ("16:10" for 16:10, not "8:5").
        let label: String
        /// What it's for, shown as its tooltip.
        let purpose: String
    }

    // The labels are ratios, the same in every language.
    static let presets: [Preset] = [
        Preset(ratio: RecordingFrameRatio(16, 9), label: "16:9", purpose: L("YouTube")), // l10n-ignore
        Preset(ratio: RecordingFrameRatio(9, 16), label: "9:16", purpose: L("Reels / TikTok / Shorts")), // l10n-ignore
        Preset(ratio: RecordingFrameRatio(1, 1), label: "1:1", purpose: L("Square posts")), // l10n-ignore
        Preset(ratio: RecordingFrameRatio(4, 5), label: "4:5", purpose: L("Instagram feed")), // l10n-ignore
        Preset(ratio: RecordingFrameRatio(4, 3), label: "4:3", purpose: L("Slides / iPad")), // l10n-ignore
        Preset(ratio: RecordingFrameRatio(16, 10), label: "16:10", purpose: L("Mac screen")), // l10n-ignore
        Preset(ratio: RecordingFrameRatio(21, 9), label: "21:9", purpose: L("Cinematic")), // l10n-ignore
    ]

    static let standard = RecordingFrameRatio(16, 9)

    /// The label a ratio shows: a preset's own ("16:10"), else "3:2".
    var label: String {
        Self.presets.first { $0.ratio == self }?.label ?? text
    }

    /// Custom… input: "3:2", "3 x 2", "3×2", "2.39:1" or "1,85:1". Nil
    /// when it isn't a shape, or is too narrow or too detailed to keep
    /// exactly (each side at most 400 in lowest terms, at most 8 to 1).
    static func parse(_ text: String) -> RecordingFrameRatio? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .lowercased()
        let separators = CharacterSet(charactersIn: ":x×/")
        let parts = cleaned.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let a = Decimal(string: parts[0], locale: Locale(identifier: "en_US_POSIX")),
              let b = Decimal(string: parts[1], locale: Locale(identifier: "en_US_POSIX")),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber || $0 == "." } }),
              a > 0, b > 0 else { return nil }
        // Up to two decimals: 2.39:1 is 239:100.
        func hundredths(_ value: Decimal) -> Int? {
            var scaled = value * 100
            var rounded = Decimal()
            NSDecimalRound(&rounded, &scaled, 0, .plain)
            guard rounded == scaled else { return nil }
            return NSDecimalNumber(decimal: rounded).intValue
        }
        guard let w = hundredths(a), let h = hundredths(b), w > 0, h > 0 else { return nil }
        let ratio = RecordingFrameRatio(w, h)
        guard ratio.width <= 400, ratio.height <= 400,
              ratio.width <= ratio.height * 8, ratio.height <= ratio.width * 8 else { return nil }
        return ratio
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}

/// The frame's pure geometry. Sizes are recorded pixels and always a whole
/// number of `step`s, the smallest even size of the ratio, so the video
/// comes out exactly that shape (encoders need even sides).
enum RecordingFrameGeometry {
    struct Pixels: Codable, Equatable, Hashable {
        let width: Int
        let height: Int
    }

    struct SizeChoice: Equatable {
        /// "720p", "1080p", "1440p" or "Largest".
        let name: String
        let pixels: Pixels
    }

    /// The smallest even-sided size of the ratio.
    static func step(_ ratio: RecordingFrameRatio) -> Pixels {
        let k = (ratio.width % 2 == 0 && ratio.height % 2 == 0) ? 1 : 2
        return Pixels(width: ratio.width * k, height: ratio.height * k)
    }

    static func pixels(_ ratio: RecordingFrameRatio, steps: Int) -> Pixels {
        let step = step(ratio)
        return Pixels(width: step.width * steps, height: step.height * steps)
    }

    /// The most steps that fit in `available` pixels.
    static func largestSteps(_ ratio: RecordingFrameRatio, in available: Pixels) -> Int {
        let step = step(ratio)
        return max(1, min(available.width / step.width, available.height / step.height))
    }

    /// The fewest steps a frame keeps: about 64 pixels on its short side.
    static func smallestSteps(_ ratio: RecordingFrameRatio) -> Int {
        let step = step(ratio)
        return max(1, Int((64.0 / Double(min(step.width, step.height))).rounded(.up)))
    }

    /// The size with the short side closest to `shortSide` (exactly it for
    /// every preset ratio).
    static func pixels(_ ratio: RecordingFrameRatio, shortSide: Int) -> Pixels {
        let step = step(ratio)
        let steps = max(1, Int((Double(shortSide) / Double(min(step.width, step.height))).rounded()))
        return pixels(ratio, steps: steps)
    }

    static func fits(_ pixels: Pixels, in available: Pixels) -> Bool {
        pixels.width <= available.width && pixels.height <= available.height
    }

    /// The size menu: 720p, 1080p and 1440p where they fit, then Largest.
    static func sizeChoices(_ ratio: RecordingFrameRatio, in available: Pixels) -> [SizeChoice] {
        var choices: [SizeChoice] = []
        for (name, short) in [("720p", 720), ("1080p", 1080), ("1440p", 1440)] { // l10n-ignore: video sizes
            let size = pixels(ratio, shortSide: short)
            if fits(size, in: available), !choices.contains(where: { $0.pixels == size }) {
                choices.append(SizeChoice(name: name, pixels: size))
            }
        }
        let largest = pixels(ratio, steps: largestSteps(ratio, in: available))
        if !choices.contains(where: { $0.pixels == largest }) {
            choices.append(SizeChoice(name: L("Largest"), pixels: largest))
        }
        return choices
    }

    /// A new frame's size: 1080p if it fits, else the largest that does.
    static func defaultPixels(_ ratio: RecordingFrameRatio, in available: Pixels) -> Pixels {
        let preferred = pixels(ratio, shortSide: 1080)
        return fits(preferred, in: available) ? preferred : pixels(ratio, steps: largestSteps(ratio, in: available))
    }

    /// The same ratio again in another size: the nearest whole step that fits.
    static func nearest(_ ratio: RecordingFrameRatio, to wanted: Pixels, in available: Pixels) -> Pixels {
        let step = step(ratio)
        let steps = Int((Double(wanted.width) / Double(step.width)).rounded())
        return pixels(ratio, steps: max(smallestSteps(ratio), min(steps, largestSteps(ratio, in: available))))
    }

    /// The display's size in pixels.
    static func available(screenFrame: CGRect, scale: CGFloat) -> Pixels {
        Pixels(width: Int((screenFrame.width * scale).rounded(.down)), height: Int((screenFrame.height * scale).rounded(.down)))
    }

    /// The frame in points for `pixels`, its origin on the display's pixel
    /// grid and kept on the display.
    static func rect(_ pixels: Pixels, origin: CGPoint, screenFrame: CGRect, scale: CGFloat) -> CGRect {
        let scale = max(scale, 1)
        let size = CGSize(width: CGFloat(pixels.width) / scale, height: CGFloat(pixels.height) / scale)
        var x = origin.x - screenFrame.minX
        var y = origin.y - screenFrame.minY
        x = max(0, min(x, screenFrame.width - size.width))
        y = max(0, min(y, screenFrame.height - size.height))
        x = (x * scale).rounded(.down) / scale
        y = (y * scale).rounded(.down) / scale
        return CGRect(x: screenFrame.minX + x, y: screenFrame.minY + y, width: size.width, height: size.height)
    }

    static func centered(_ pixels: Pixels, screenFrame: CGRect, scale: CGFloat) -> CGRect {
        let scale = max(scale, 1)
        let origin = CGPoint(
            x: screenFrame.midX - CGFloat(pixels.width) / scale / 2,
            y: screenFrame.midY - CGFloat(pixels.height) / scale / 2
        )
        return rect(pixels, origin: origin, screenFrame: screenFrame, scale: scale)
    }

    /// Points within which a moved frame snaps.
    static let snapDistance: CGFloat = 8

    /// A moved frame snaps its center to the display's center and its
    /// edges to the display's edges (and to the menu bar and Dock's edges).
    static func snapped(_ rect: CGRect, screenFrame: CGRect, visibleFrame: CGRect, scale: CGFloat) -> CGRect {
        var origin = rect.origin
        func snap(_ value: CGFloat, to targets: [CGFloat]) -> CGFloat? {
            targets.map { ($0, abs($0 - value)) }.filter { $0.1 <= snapDistance }.min { $0.1 < $1.1 }?.0
        }
        let xTargets: [(CGFloat, CGFloat)] = [
            (screenFrame.midX, rect.width / 2), (screenFrame.minX, 0), (screenFrame.maxX, rect.width),
            (visibleFrame.minX, 0), (visibleFrame.maxX, rect.width),
        ]
        let yTargets: [(CGFloat, CGFloat)] = [
            (screenFrame.midY, rect.height / 2), (screenFrame.minY, 0), (screenFrame.maxY, rect.height),
            (visibleFrame.minY, 0), (visibleFrame.maxY, rect.height),
        ]
        // Each target says where that edge (or the center) must be: the
        // origin that puts it there.
        if let x = snap(rect.minX, to: xTargets.map { $0.0 - $0.1 }) { origin.x = x }
        if let y = snap(rect.minY, to: yTargets.map { $0.0 - $0.1 }) { origin.y = y }
        let pixels = Pixels(width: Int((rect.width * scale).rounded()), height: Int((rect.height * scale).rounded()))
        return self.rect(pixels, origin: origin, screenFrame: screenFrame, scale: scale)
    }

    enum Corner: CaseIterable {
        case bottomLeft, bottomRight, topLeft, topRight
    }

    /// Resizing from a corner: the opposite corner stays put and the frame
    /// keeps its ratio, a whole number of steps, and on the display.
    static func resized(_ rect: CGRect, corner: Corner, to point: CGPoint, ratio: RecordingFrameRatio, screenFrame: CGRect, scale: CGFloat) -> CGRect {
        let scale = max(scale, 1)
        let anchor: CGPoint
        switch corner {
        case .bottomLeft: anchor = CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomRight: anchor = CGPoint(x: rect.minX, y: rect.maxY)
        case .topLeft: anchor = CGPoint(x: rect.maxX, y: rect.minY)
        case .topRight: anchor = CGPoint(x: rect.minX, y: rect.minY)
        }
        let growsLeft = corner == .bottomLeft || corner == .topLeft
        let growsDown = corner == .bottomLeft || corner == .bottomRight
        let step = step(ratio)
        let stepPoints = CGSize(width: CGFloat(step.width) / scale, height: CGFloat(step.height) / scale)
        // Room from the anchor to the display's edges in that direction.
        let roomX = growsLeft ? anchor.x - screenFrame.minX : screenFrame.maxX - anchor.x
        let roomY = growsDown ? anchor.y - screenFrame.minY : screenFrame.maxY - anchor.y
        let maxSteps = max(1, Int(min(roomX / stepPoints.width, roomY / stepPoints.height) + 0.0001))
        let wantedX = abs(point.x - anchor.x) / stepPoints.width
        let wantedY = abs(point.y - anchor.y) / stepPoints.height
        let steps = min(max(Int(max(wantedX, wantedY).rounded()), smallestSteps(ratio)), max(maxSteps, smallestSteps(ratio)))
        let size = pixels(ratio, steps: steps)
        let width = CGFloat(size.width) / scale
        let height = CGFloat(size.height) / scale
        let origin = CGPoint(x: growsLeft ? anchor.x - width : anchor.x, y: growsDown ? anchor.y - height : anchor.y)
        return self.rect(size, origin: origin, screenFrame: screenFrame, scale: scale)
    }

    static func pixels(of rect: CGRect, scale: CGFloat) -> Pixels {
        Pixels(width: Int((rect.width * scale).rounded()), height: Int((rect.height * scale).rounded()))
    }
}

/// The last frame on each display: its ratio, size and place.
enum RecordingFrameMemory {
    struct Entry: Codable, Equatable {
        let ratio: RecordingFrameRatio
        let pixels: RecordingFrameGeometry.Pixels
        /// Bottom-left corner from the display's bottom-left, in points.
        let offset: CGPoint
    }

    // Not a "recording…" key: those are the recording bar's settings.
    static let key = "frameBarDisplays"

    static func load(display: String) -> Entry? {
        all()[display]
    }

    static func save(_ entry: Entry, display: String) {
        var entries = all()
        guard entries[display] != entry else { return }
        entries[display] = entry
        if let data = try? JSONEncoder().encode(entries) {
            Settings.defaults.set(data, forKey: key)
        }
    }

    static func all() -> [String: Entry] {
        guard let data = Settings.defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return entries
    }

    /// A display's lasting name: its UUID, so it's the same after a restart
    /// or plugging it into another port.
    @MainActor
    static func displayKey(_ screen: NSScreen) -> String {
        guard let id = screen.displayID else { return "main" } // l10n-ignore
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let text = CFUUIDCreateString(nil, uuid) as String? {
            return text
        }
        return String(id)
    }
}

// MARK: - The frame on screen

/// New recording's frame: a highlighted area of an exact ratio and pixel
/// size, the rest of the display dimmed. Only its border and corner
/// handles take the mouse; clicks and scrolling everywhere else, inside
/// the frame too, go to the apps underneath. None of it is ever recorded:
/// it closes before the countdown, and like all of LF Studios' floating UI
/// it's kept out of the video anyway.
@MainActor
final class RecordingFrameController {
    private(set) var screen: NSScreen
    private(set) var ratio: RecordingFrameRatio
    private(set) var rect: CGRect

    /// Split screen (the camera on, Layout ▸ Split screen): the frame is
    /// the whole video, what's recorded is the screen's part of it.
    var split: VideoWebcamSettings.Split? {
        didSet { if split != oldValue { apply(rect, save: false) } }
    }

    /// The frame moved, changed size or moved to another display: what's
    /// recorded (the screen's part, when split).
    var changeHandler: ((CGRect, NSScreen) -> Void)?
    /// Esc, ⌃⌘Esc: the setup ends.
    var cancelHandler: (() -> Void)?
    /// Return.
    var recordHandler: (() -> Void)?

    private var dimWindow: RecordingFrameDimWindow?
    private var handleWindows: [RecordingFrameHandleWindow] = []
    private(set) var isShowing = false
    private var screensObserver: NSObjectProtocol?

    /// Border handles' thickness, straddling the border.
    static let edgeThickness: CGFloat = 10
    static let cornerSize: CGFloat = 20

    init(screen: NSScreen) {
        self.screen = screen
        let available = RecordingFrameGeometry.available(screenFrame: screen.frame, scale: screen.backingScaleFactor)
        if let entry = RecordingFrameMemory.load(display: RecordingFrameMemory.displayKey(screen)),
           RecordingFrameGeometry.fits(entry.pixels, in: available) {
            ratio = entry.ratio
            let pixels = RecordingFrameGeometry.nearest(entry.ratio, to: entry.pixels, in: available)
            let origin = CGPoint(x: screen.frame.minX + entry.offset.x, y: screen.frame.minY + entry.offset.y)
            rect = RecordingFrameGeometry.rect(pixels, origin: origin, screenFrame: screen.frame, scale: screen.backingScaleFactor)
        } else {
            ratio = RecordingFrameRatio.standard
            let pixels = RecordingFrameGeometry.defaultPixels(ratio, in: available)
            rect = RecordingFrameGeometry.centered(pixels, screenFrame: screen.frame, scale: screen.backingScaleFactor)
        }
    }

    /// What's recorded: the frame, or with Split screen the screen's part
    /// of it, in whole even pixels.
    var recordedRect: CGRect {
        guard let split else { return rect }
        let part = VideoSplitLayout.screenPixels(split, video: CGSize(width: pixels.width, height: pixels.height))
        return CGRect(x: rect.minX + part.minX / scale, y: rect.minY + part.minY / scale, width: part.width / scale, height: part.height / scale)
    }

    /// Split screen: the camera's part of the frame (nil: not split).
    var cameraPartRect: CGRect? {
        guard let split else { return nil }
        let part = VideoSplitLayout.parts(split, in: CGSize(width: pixels.width, height: pixels.height)).camera
        return CGRect(x: rect.minX + part.minX / scale, y: rect.minY + part.minY / scale, width: part.width / scale, height: part.height / scale)
    }

    var recordedPixels: RecordingFrameGeometry.Pixels { RecordingFrameGeometry.pixels(of: recordedRect, scale: scale) }

    /// "960 × 1080 · Screen part of a 16:9 split video", or just the size.
    var label: String {
        let size = Self.sizeText(recordedPixels)
        guard split != nil else { return size }
        let whole = ratio.label
        return L("\(size) · Screen part of a \(whole) split video")
    }

    var scale: CGFloat { max(screen.backingScaleFactor, 1) }
    var pixels: RecordingFrameGeometry.Pixels { RecordingFrameGeometry.pixels(of: rect, scale: scale) }
    var available: RecordingFrameGeometry.Pixels { RecordingFrameGeometry.available(screenFrame: screen.frame, scale: scale) }
    var sizeChoices: [RecordingFrameGeometry.SizeChoice] { RecordingFrameGeometry.sizeChoices(ratio, in: available) }

    /// All of the frame's own windows (the dimming, border and handles).
    var windows: [NSWindow] { ([dimWindow] as [NSWindow?]).compactMap { $0 } + handleWindows }

    func show() {
        guard !isShowing else { return }
        isShowing = true
        let dim = RecordingFrameDimWindow(screen: screen)
        dimWindow = dim
        handleWindows = Self.handleRoles.map { role in
            let window = RecordingFrameHandleWindow(role: role)
            window.controller = self
            return window
        }
        layout()
        dim.orderFrontRegardless()
        handleWindows.forEach { $0.orderFrontRegardless() }
        RecordingStopHotkey.register { [weak self] in self?.cancelHandler?() }
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func close() {
        guard isShowing else { return }
        isShowing = false
        RecordingStopHotkey.unregister()
        if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) }
        screensObserver = nil
        dimWindow?.orderOut(nil)
        dimWindow = nil
        handleWindows.forEach { $0.controller = nil; $0.orderOut(nil) }
        handleWindows = []
    }

    // MARK: Changing the frame

    func setRatio(_ newRatio: RecordingFrameRatio) {
        // The same short side in the new shape, where it fits.
        let short = min(pixels.width, pixels.height)
        ratio = newRatio
        var size = RecordingFrameGeometry.pixels(newRatio, shortSide: short)
        if !RecordingFrameGeometry.fits(size, in: available) {
            size = RecordingFrameGeometry.pixels(newRatio, steps: RecordingFrameGeometry.largestSteps(newRatio, in: available))
        }
        setPixels(size)
    }

    /// A new size, around the same center.
    func setPixels(_ size: RecordingFrameGeometry.Pixels) {
        let width = CGFloat(size.width) / scale
        let height = CGFloat(size.height) / scale
        let origin = CGPoint(x: rect.midX - width / 2, y: rect.midY - height / 2)
        apply(RecordingFrameGeometry.rect(size, origin: origin, screenFrame: screen.frame, scale: scale), save: true)
    }

    /// Arrow keys: one point, or ten with ⇧.
    func nudge(dx: CGFloat, dy: CGFloat) {
        let moved = rect.offsetBy(dx: dx, dy: dy)
        apply(RecordingFrameGeometry.rect(pixels, origin: moved.origin, screenFrame: screen.frame, scale: scale), save: true)
    }

    func move(to origin: CGPoint, snapping: Bool = true) {
        var moved = RecordingFrameGeometry.rect(pixels, origin: origin, screenFrame: screen.frame, scale: scale)
        if snapping {
            moved = RecordingFrameGeometry.snapped(moved, screenFrame: screen.frame, visibleFrame: screen.visibleFrame, scale: scale)
        }
        apply(moved, save: false)
    }

    func resize(corner: RecordingFrameGeometry.Corner, from start: CGRect, to point: CGPoint) {
        apply(RecordingFrameGeometry.resized(start, corner: corner, to: point, ratio: ratio, screenFrame: screen.frame, scale: scale), save: false)
    }

    /// Dragged onto another display: the frame goes with the pointer,
    /// smaller if it has to, and that display's dimming takes over.
    func moveToScreen(_ newScreen: NSScreen, center: CGPoint) {
        guard newScreen != screen else { return }
        screen = newScreen
        let size = RecordingFrameGeometry.fits(pixels, in: available)
            ? pixels
            : RecordingFrameGeometry.pixels(ratio, steps: RecordingFrameGeometry.largestSteps(ratio, in: available))
        let width = CGFloat(size.width) / scale
        let height = CGFloat(size.height) / scale
        dimWindow?.place(on: newScreen)
        apply(RecordingFrameGeometry.rect(size, origin: CGPoint(x: center.x - width / 2, y: center.y - height / 2), screenFrame: newScreen.frame, scale: scale), save: false)
    }

    func dragEnded() {
        remember()
    }

    private func apply(_ newRect: CGRect, save: Bool) {
        rect = newRect
        layout()
        if save { remember() }
        changeHandler?(recordedRect, screen)
    }

    private func remember() {
        let offset = CGPoint(x: rect.minX - screen.frame.minX, y: rect.minY - screen.frame.minY)
        RecordingFrameMemory.save(RecordingFrameMemory.Entry(ratio: ratio, pixels: pixels, offset: offset), display: RecordingFrameMemory.displayKey(screen))
    }

    private func screensChanged() {
        // The display went away or changed size: back on a display that's there.
        let current = NSScreen.screens.first { $0.displayID == screen.displayID } ?? NSScreen.main ?? NSScreen.screens.first
        guard let current else { return }
        screen = current
        dimWindow?.place(on: current)
        let size = RecordingFrameGeometry.fits(pixels, in: available)
            ? pixels
            : RecordingFrameGeometry.pixels(ratio, steps: RecordingFrameGeometry.largestSteps(ratio, in: available))
        apply(RecordingFrameGeometry.rect(size, origin: rect.origin, screenFrame: current.frame, scale: scale), save: false)
    }

    // MARK: Keys

    /// Esc, arrows (⇧: ten points) and Return, when the frame or its bars
    /// have focus. True when the key was the frame's.
    func handleKey(_ event: NSEvent) -> Bool {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 53: cancelHandler?()
        case 36, 76: recordHandler?()
        case 123: nudge(dx: -step, dy: 0)
        case 124: nudge(dx: step, dy: 0)
        case 125: nudge(dx: 0, dy: -step)
        case 126: nudge(dx: 0, dy: step)
        default: return false
        }
        return true
    }

    // MARK: Layout

    static let handleRoles: [RecordingFrameHandleWindow.Role] = [
        .edge(.top), .edge(.bottom), .edge(.left), .edge(.right),
        .corner(.bottomLeft), .corner(.bottomRight), .corner(.topLeft), .corner(.topRight),
    ]

    /// Where each handle sits: on the border, never over the frame's middle.
    static func handleFrame(_ role: RecordingFrameHandleWindow.Role, around rect: CGRect) -> CGRect {
        let t = edgeThickness, c = cornerSize
        switch role {
        case .edge(.top): return CGRect(x: rect.minX + c / 2, y: rect.maxY - t / 2, width: max(rect.width - c, 1), height: t)
        case .edge(.bottom): return CGRect(x: rect.minX + c / 2, y: rect.minY - t / 2, width: max(rect.width - c, 1), height: t)
        case .edge(.left): return CGRect(x: rect.minX - t / 2, y: rect.minY + c / 2, width: t, height: max(rect.height - c, 1))
        case .edge(.right): return CGRect(x: rect.maxX - t / 2, y: rect.minY + c / 2, width: t, height: max(rect.height - c, 1))
        case .corner(.bottomLeft): return CGRect(x: rect.minX - c / 2, y: rect.minY - c / 2, width: c, height: c)
        case .corner(.bottomRight): return CGRect(x: rect.maxX - c / 2, y: rect.minY - c / 2, width: c, height: c)
        case .corner(.topLeft): return CGRect(x: rect.minX - c / 2, y: rect.maxY - c / 2, width: c, height: c)
        case .corner(.topRight): return CGRect(x: rect.maxX - c / 2, y: rect.maxY - c / 2, width: c, height: c)
        }
    }

    private func layout() {
        dimWindow?.update(frame: recordedRect, video: split == nil ? nil : rect, camera: cameraPartRect, label: label)
        for window in handleWindows {
            window.setFrame(Self.handleFrame(window.role, around: rect), display: true)
        }
    }

    /// "1920 × 1080": pixel sizes as plain digits.
    static func sizeText(_ pixels: RecordingFrameGeometry.Pixels) -> String {
        let (width, height) = (String(pixels.width), String(pixels.height))
        return L("\(width) × \(height)")
    }
}

/// The dimming around the frame, its border and its size. Never takes the
/// mouse.
@MainActor
final class RecordingFrameDimWindow: NSPanel {
    private let dimView = RecordingFrameDimView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        appearance = AppAppearance.overlay
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Over the apps, under the recording bar and the frame's handles.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = .none
        contentView = dimView
        setAccessibilityElement(false)
        place(on: screen)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func place(on screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }

    /// `rect` is what's recorded; with Split screen, `video` is the whole
    /// video around it and `camera` the camera's part.
    func update(frame rect: CGRect, video: CGRect? = nil, camera: CGRect? = nil, label: String) {
        dimView.hole = rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
        dimView.video = video?.offsetBy(dx: -frame.minX, dy: -frame.minY)
        dimView.camera = camera?.offsetBy(dx: -frame.minX, dy: -frame.minY)
        dimView.label = label
        dimView.needsDisplay = true
    }

    /// The camera's part as drawn, for tests (nil: not split).
    var drawnCameraPart: CGRect? { dimView.camera }

    /// The frame's place as drawn, for tests (in the window's own points).
    var drawnFrame: CGRect { dimView.hole }
}

@MainActor
private final class RecordingFrameDimView: NSView {
    var hole: CGRect = .zero
    /// Split screen: the whole video and the camera's part of it.
    var video: CGRect?
    var camera: CGRect?
    var label = ""

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: hole))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        if let camera {
            // The camera's part: not recorded from the screen, the camera
            // fills it in the video.
            let part = NSBezierPath(rect: camera.insetBy(dx: 1, dy: 1))
            part.lineWidth = 2
            part.setLineDash([7, 5], count: 2, phase: 0)
            NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
            part.stroke()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            ]
            let text = NSAttributedString(string: L("Camera"), attributes: attributes)
            let size = text.size()
            text.draw(at: CGPoint(x: camera.midX - size.width / 2, y: camera.midY - size.height / 2))
        }

        // The border just outside the frame, so the frame's own pixels
        // show exactly what's recorded.
        let border = NSBezierPath(rect: hole.insetBy(dx: -1, dy: -1))
        border.lineWidth = 2
        NSColor.white.withAlphaComponent(0.95).setStroke()
        border.stroke()

        // Corner handles (on the whole video when it's split).
        NSColor.white.setFill()
        let size: CGFloat = 10
        let handles = video ?? hole
        for corner in [CGPoint(x: handles.minX, y: handles.minY), CGPoint(x: handles.maxX, y: handles.minY), CGPoint(x: handles.minX, y: handles.maxY), CGPoint(x: handles.maxX, y: handles.maxY)] {
            NSBezierPath(roundedRect: CGRect(x: corner.x - size / 2, y: corner.y - size / 2, width: size, height: size), xRadius: 2.5, yRadius: 2.5).fill()
        }

        // The size, just above the frame (inside it when there's no room).
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let textSize = text.size()
        let pill = CGSize(width: textSize.width + 16, height: textSize.height + 6)
        let top = video ?? hole
        var origin = CGPoint(x: top.minX, y: top.maxY + 8)
        if origin.y + pill.height > bounds.maxY - 4 { origin.y = hole.maxY - pill.height - 10; origin.x = hole.minX + 10 }
        let pillRect = CGRect(origin: origin, size: pill)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: CGPoint(x: pillRect.minX + 8, y: pillRect.minY + 3))
    }
}

/// A piece of the frame's border (drag to move) or a corner (drag to
/// resize). The only parts of the frame that take the mouse.
@MainActor
final class RecordingFrameHandleWindow: NSPanel {
    enum Edge { case top, bottom, left, right }
    enum Role: Equatable {
        case edge(Edge)
        case corner(RecordingFrameGeometry.Corner)
    }

    let role: Role
    weak var controller: RecordingFrameController?

    init(role: Role) {
        self.role = role
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        // Clear but there, so it takes the mouse.
        backgroundColor = NSColor.white.withAlphaComponent(0.001)
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = .none
        let view = RecordingFrameHandleView(frame: .zero)
        view.handle = self
        contentView = view
        switch role {
        case .edge: setAccessibilityLabel(L("Frame border: drag to move"))
        case .corner: setAccessibilityLabel(L("Frame corner: drag to resize"))
        }
    }

    // Clicking the border lets Esc and the arrows reach the frame, without
    // taking over from the app being recorded.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var cursor: NSCursor {
        switch role {
        case .edge: return .openHand
        case let .corner(corner):
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition
                switch corner {
                case .bottomLeft: position = .bottomLeft
                case .bottomRight: position = .bottomRight
                case .topLeft: position = .topLeft
                case .topRight: position = .topRight
                }
                return NSCursor.frameResize(position: position, directions: .all)
            }
            return .crosshair
        }
    }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true { super.keyDown(with: event) }
    }
}

@MainActor
private final class RecordingFrameHandleView: NSView {
    weak var handle: RecordingFrameHandleWindow?
    private var startMouse: CGPoint = .zero
    private var startRect: CGRect = .zero

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { handle?.cursor.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        guard let handle, let controller = handle.controller else { return }
        handle.makeKey()
        startMouse = NSEvent.mouseLocation
        startRect = controller.rect
        if case .edge = handle.role { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let handle, let controller = handle.controller else { return }
        let mouse = NSEvent.mouseLocation
        switch handle.role {
        case .edge:
            if let other = NSScreen.screens.first(where: { $0.frame.contains(mouse) }), other != controller.screen {
                controller.moveToScreen(other, center: mouse)
                startMouse = mouse
                startRect = controller.rect
                return
            }
            controller.move(to: CGPoint(x: startRect.minX + mouse.x - startMouse.x, y: startRect.minY + mouse.y - startMouse.y))
        case let .corner(corner):
            controller.resize(corner: corner, from: startRect, to: mouse)
        }
    }

    override func mouseUp(with event: NSEvent) {
        handle?.cursor.set()
        handle?.controller?.dragEnded()
    }
}

// MARK: - The frame strip

/// What the frame strip shows and does.
@MainActor
final class RecordingFrameStripModel: ObservableObject {
    @Published var ratio: RecordingFrameRatio
    @Published var pixels: RecordingFrameGeometry.Pixels
    @Published var sizeChoices: [RecordingFrameGeometry.SizeChoice]

    var chooseRatio: (RecordingFrameRatio) -> Void = { _ in }
    var chooseSize: (RecordingFrameGeometry.Pixels) -> Void = { _ in }
    var fitWindow: () -> Void = {}
    var recordWindow: () -> Void = {}
    var recordFullScreen: () -> Void = {}
    var selectManually: () -> Void = {}

    init(ratio: RecordingFrameRatio, pixels: RecordingFrameGeometry.Pixels, sizeChoices: [RecordingFrameGeometry.SizeChoice]) {
        self.ratio = ratio
        self.pixels = pixels
        self.sizeChoices = sizeChoices
    }
}

/// The strip above the recording bar: the frame's ratio and size, fitting
/// a window to it, and the other ways to record.
@MainActor
final class RecordingFrameStripWindow: NSPanel {
    static let height: CGFloat = 80
    static let gap: CGFloat = 6

    let model: RecordingFrameStripModel
    /// Esc, arrows and Return when the strip has focus.
    var keyHandler: ((NSEvent) -> Bool)?

    init(model: RecordingFrameStripModel, width: CGFloat) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: Self.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        appearance = AppAppearance.overlay
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = .none
        let hosting = NSHostingView(rootView: RecordingFrameStripView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: Self.height)
        hosting.autoresizingMask = [.width, .height]
        let container = RecordingFrameStripContainer(frame: hosting.frame)
        container.addSubview(hosting)
        contentView = container
        setAccessibilityLabel(L("Frame"))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }
}

/// Dragging the strip's background drags the recording bar it sits on.
private final class RecordingFrameStripContainer: NSView {
    override func mouseDown(with event: NSEvent) {
        if let parent = window?.parent { parent.performDrag(with: event) } else { super.mouseDown(with: event) }
    }
}

private struct RecordingFrameStripView: View {
    @ObservedObject var model: RecordingFrameStripModel
    @State private var showsCustom = false
    @State private var customText = ""
    @State private var customError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 18)
                    .help(L("Drag to move the bars"))
                ForEach(RecordingFrameRatio.presets, id: \.label) { preset in
                    ratioButton(preset.label, selected: model.ratio == preset.ratio) {
                        model.chooseRatio(preset.ratio)
                    }
                    .help(preset.purpose)
                    .accessibilityLabel(Text(verbatim: "\(preset.label), \(preset.purpose)"))
                }
                let isCustom = !RecordingFrameRatio.presets.contains { $0.ratio == model.ratio }
                ratioButton(isCustom ? model.ratio.label : L("Custom…"), selected: isCustom) {
                    customText = isCustom ? model.ratio.text : ""
                    customError = false
                    showsCustom = true
                }
                .help(L("Any shape, like 3:2"))
                .popover(isPresented: $showsCustom, arrowEdge: .bottom) { customPopover }
                Spacer(minLength: 8)
                sizeMenu
            }
            HStack(spacing: 6) {
                Spacer().frame(width: 18)
                actionButton(L("Fit a window to the frame…"), symbol: "macwindow.badge.plus", action: model.fitWindow)
                    .help(L("Resizes a window of another app to exactly the frame, so it fills the recording"))
                Spacer(minLength: 8)
                actionButton(L("Window"), symbol: "macwindow", action: model.recordWindow)
                    .help(L("Record one window instead"))
                actionButton(L("Full screen"), symbol: "display", action: model.recordFullScreen)
                    .help(L("Record the whole screen instead"))
                actionButton(L("Select area manually"), symbol: "selection.pin.in.out", action: model.selectManually)
                    .help(L("Drag out any area instead, of any shape"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: NSColor(white: 0.1, alpha: 0.92)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
        )
        .environment(\.colorScheme, .dark)
    }

    private func ratioButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.88))
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Color.white : Color.white.opacity(0.1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sizeMenu: some View {
        Menu {
            ForEach(model.sizeChoices, id: \.pixels) { choice in
                Button {
                    model.chooseSize(choice.pixels)
                } label: {
                    Text(verbatim: "\(choice.name) · \(RecordingFrameController.sizeText(choice.pixels))")
                }
            }
        } label: {
            Text(verbatim: RecordingFrameController.sizeText(model.pixels))
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("The video's size in pixels. Drag a corner of the frame for any other size."))
    }

    private var customPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Custom shape"))
                .font(.headline)
            HStack {
                TextField(L("3:2"), text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onSubmit(applyCustom)
                Button(L("Use"), action: applyCustom)
                    .keyboardShortcut(.defaultAction)
            }
            Text(customError ? L("Type a shape like 3:2 or 2.39:1.") : L("Width and height, like 3:2 or 2.39:1."))
                .font(.caption)
                .foregroundStyle(customError ? Color.red : Color.secondary)
        }
        .padding(12)
        .frame(width: 240)
    }

    private func applyCustom() {
        guard let ratio = RecordingFrameRatio.parse(customText) else {
            customError = true
            return
        }
        showsCustom = false
        model.chooseRatio(ratio)
    }
}
