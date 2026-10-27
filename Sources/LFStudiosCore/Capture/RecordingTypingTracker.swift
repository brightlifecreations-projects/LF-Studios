import AppKit
import ApplicationServices
import Carbon
import Foundation

// MARK: - What is saved

/// Where the text cursor was at one moment — a box on the video, nothing
/// else. No text, no keys: the type has no field that could hold them.
struct VideoTextCursorSample: Codable, Equatable {
    /// Source seconds.
    var time: Double
    /// Video-normalized, y down: the box's top-left corner and size.
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }
}

// MARK: - Reading the focused element

/// What has keyboard focus, as far as typing goes: geometry only.
enum RecordingFocusReading: Equatable {
    /// A password field: nothing at all is recorded while it has focus.
    case secure
    /// The text cursor's box (screen, AppKit space: bottom-left origin).
    case caret(CGRect)
    /// A text field whose app doesn't report its text cursor: the field's box.
    case field(CGRect)
    /// Not a text field, or nothing could be read.
    case none
}

protocol RecordingFocusProbing: Sendable {
    func read() -> RecordingFocusReading
}

/// Reads the focused element through Accessibility. It asks only for the
/// element's role, its selection RANGE (two numbers), and screen boxes —
/// never its value or the selected text.
struct RecordingAccessibilityFocusProbe: RecordingFocusProbing {
    static let secureRoles: Set<String> = ["AXSecureTextField"]
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    func read() -> RecordingFocusReading {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .none }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.1)
        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        if Self.isSecure(role: role, subrole: subrole) { return .secure }

        // Web pages and some editors report text areas under other roles;
        // a selection range is what makes it a place to type.
        var rangeValue: CFTypeRef?
        let hasRange = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success
        guard Self.textRoles.contains(role ?? "") || hasRange else { return .none }

        if hasRange, let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var bounds: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &bounds) == .success,
               let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() {
                var rect = CGRect.zero
                // swiftlint:disable:next force_cast
                if AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0, rect.height < 400 {
                    return .caret(Self.appKitRect(fromScreen: rect))
                }
            }
        }
        if let frame = frame(of: element), frame.width > 0, frame.height > 0 {
            return .field(Self.appKitRect(fromScreen: frame))
        }
        return .none
    }

    static func isSecure(role: String?, subrole: String?) -> Bool {
        secureRoles.contains(role ?? "") || secureRoles.contains(subrole ?? "")
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        // swiftlint:disable force_cast
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        // swiftlint:enable force_cast
        return CGRect(origin: origin, size: extent)
    }

    /// Accessibility boxes are top-left based on the main display.
    static func appKitRect(fromScreen rect: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

// MARK: - Tracking

/// "Track where I type" and "Record when keys are pressed": the text
/// cursor's position and the moments keys go down. Which keys, and what
/// was typed, never reach it. While a password field has focus (or macOS
/// has secure keyboard entry on), nothing at all is recorded — the cursor
/// would give away the password's length, the timing could help guess it.
@MainActor
final class RecordingTypingTracker {
    static let probeInterval = 0.125

    let tracksTyping: Bool
    let recordsKeyTiming: Bool
    /// Host clock → video seconds (nil while paused).
    private let time: (CFTimeInterval) -> Double?
    /// A screen box (AppKit space) → video-normalized box, y down.
    private let map: (CGRect) -> CGRect?
    private let probe: RecordingFocusProbing
    private let secureInput: () -> Bool

    private(set) var samples: [VideoTextCursorSample] = []
    private(set) var keyPresses: [Double] = []
    /// A password field has focus: everything waits.
    private(set) var isSecure = false
    /// Video time of the last reading that wasn't a password field: when
    /// one turns up, anything recorded after it is dropped too (a key or
    /// two can land before the next reading).
    private var lastSafeTime: Double?
    private var lastBox: CGRect?

    private var timer: DispatchSourceTimer?
    private var keyMonitor: Any?

    init(
        tracksTyping: Bool,
        recordsKeyTiming: Bool,
        probe: RecordingFocusProbing = RecordingAccessibilityFocusProbe(),
        secureInput: @escaping () -> Bool = { IsSecureEventInputEnabled() },
        time: @escaping (CFTimeInterval) -> Double?,
        map: @escaping (CGRect) -> CGRect?
    ) {
        self.tracksTyping = tracksTyping
        self.recordsKeyTiming = recordsKeyTiming
        self.probe = probe
        self.secureInput = secureInput
        self.time = time
        self.map = map
    }

    var isActive: Bool { tracksTyping || recordsKeyTiming }

    func start() {
        guard isActive, AXIsProcessTrusted() else { return }
        // Password fields are watched for both features, so key timing
        // reads the focus too.
        let probe = self.probe
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: Self.probeInterval, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            let host = CACurrentMediaTime()
            let reading = probe.read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(reading, at: host) }
            }
        }
        timer.resume()
        self.timer = timer

        if recordsKeyTiming {
            // Only the moment: the event's key code and characters are
            // never looked at.
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard !event.isARepeat else { return }
                let host = CACurrentMediaTime()
                MainActor.assumeIsolated { self?.keyDown(at: host) }
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// One focus reading, taken at `host`.
    func handle(_ reading: RecordingFocusReading, at host: CFTimeInterval) {
        guard let now = time(host) else { return }
        if reading == .secure || secureInput() {
            if !isSecure, let lastSafeTime {
                samples.removeAll { $0.time > lastSafeTime }
                keyPresses.removeAll { $0 > lastSafeTime }
            } else if !isSecure {
                samples.removeAll()
                keyPresses.removeAll()
            }
            isSecure = true
            lastBox = nil
            return
        }
        isSecure = false
        lastSafeTime = now
        guard tracksTyping else { return }
        let box: CGRect
        switch reading {
        case .caret(let rect), .field(let rect): box = rect
        case .none, .secure:
            lastBox = nil
            return
        }
        // Only changes are kept: a still text cursor adds nothing.
        guard box != lastBox, let normalized = map(box) else { return }
        lastBox = box
        // Outside the recorded area: not part of the video.
        guard normalized.maxX > 0, normalized.minX < 1, normalized.maxY > 0, normalized.minY < 1 else { return }
        samples.append(VideoTextCursorSample(time: now, x: normalized.minX, y: normalized.minY, width: normalized.width, height: normalized.height))
    }

    /// A key went down at `host` — which one isn't known here.
    func keyDown(at host: CFTimeInterval) {
        guard recordsKeyTiming, !isSecure, !secureInput(), let now = time(host) else { return }
        keyPresses.append(now)
    }

    /// The video's first frame moved t=0.
    func shift(by offset: Double) {
        samples = samples.compactMap { sample in
            var sample = sample
            sample.time -= offset
            return sample.time >= 0 ? sample : nil
        }
        keyPresses = keyPresses.map { $0 - offset }.filter { $0 >= 0 }
        lastSafeTime = lastSafeTime.map { $0 - offset }
    }

    func finish(duration: Double) -> (samples: [VideoTextCursorSample], keyPresses: [Double]) {
        stop()
        // The stop shortcut isn't typing.
        return (samples.filter { $0.time <= duration }, keyPresses.filter { $0 < duration - 0.05 })
    }
}
