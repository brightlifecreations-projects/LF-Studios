import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Webcam

/// How the camera bubble sits on the video.
struct VideoWebcamSettings: Codable, Equatable {
    enum Anchor: String, Codable, CaseIterable, Identifiable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

        var id: String { rawValue }

        var title: String {
            switch self {
            case .topLeft: return L("Top left")
            case .top: return L("Top")
            case .topRight: return L("Top right")
            case .left: return L("Left")
            case .right: return L("Right")
            case .bottomLeft: return L("Bottom left")
            case .bottom: return L("Bottom")
            case .bottomRight: return L("Bottom right")
            }
        }

        /// Position on the frame, 0...1 with y down.
        var unit: CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: 0, y: 0)
            case .top: return CGPoint(x: 0.5, y: 0)
            case .topRight: return CGPoint(x: 1, y: 0)
            case .left: return CGPoint(x: 0, y: 0.5)
            case .right: return CGPoint(x: 1, y: 0.5)
            case .bottomLeft: return CGPoint(x: 0, y: 1)
            case .bottom: return CGPoint(x: 0.5, y: 1)
            case .bottomRight: return CGPoint(x: 1, y: 1)
            }
        }

        /// The anchor nearest a unit point (for drag-to-snap).
        static func nearest(to point: CGPoint) -> Anchor {
            allCases.min { a, b in
                hypot(a.unit.x - point.x, a.unit.y - point.y) < hypot(b.unit.x - point.x, b.unit.y - point.y)
            } ?? .bottomRight
        }
    }

    /// The bubble's outline and ratio. `square` and `rectangle` keep their
    /// stored names (projects from before 1.10.0 use them).
    enum Shape: String, Codable, CaseIterable, Identifiable {
        case circle
        /// Rounded rectangle: 4:3 with soft corners (called "Wide" before 1.10.0).
        case rectangle
        /// Square (1:1).
        case square
        /// 16:9.
        case landscape
        /// 9:16.
        case portrait
        /// 4:3.
        case classic
        /// 3:4.
        case classicPortrait
        /// Any width and height (`freeAspect`).
        case free
        /// Just you — no frame, the background removed.
        case cutout

        var id: String { rawValue }
        var title: String {
            switch self {
            case .circle: return L("Circle")
            case .rectangle: return L("Rounded rectangle")
            case .square: return L("Square (1:1)")
            case .landscape: return L("Landscape (16:9)")
            case .portrait: return L("Portrait (9:16)")
            case .classic: return "4:3" // l10n-ignore: a ratio
            case .classicPortrait: return "3:4" // l10n-ignore: a ratio
            case .free: return L("Free")
            case .cutout: return L("Cutout")
            }
        }

        var symbol: String {
            switch self {
            case .circle: return "circle"
            case .rectangle: return "rectangle.roundedtop"
            case .square: return "square"
            case .landscape: return "rectangle.ratio.16.to.9"
            case .portrait: return "rectangle.ratio.9.to.16"
            case .classic: return "rectangle.ratio.4.to.3"
            case .classicPortrait: return "rectangle.ratio.3.to.4"
            case .free: return "rectangle.dashed"
            case .cutout: return "person.crop.rectangle"
            }
        }

        /// The shapes a camera can take before recording (Cutout is a look
        /// chosen in the editor).
        static var recordable: [Shape] { allCases.filter { $0 != .cutout } }

        /// The corners each shape has (0 sharp … 1 a circle), matching
        /// what it was drawn with before roundness was adjustable.
        var roundness: Double {
            switch self {
            case .circle: return 1
            case .square: return 0.44
            case .rectangle: return 0.24
            case .cutout: return 0
            case .landscape, .portrait, .classic, .classicPortrait, .free: return 0.12
            }
        }

        /// Width / height (Free: 1 until it's dragged to another shape).
        var aspect: CGFloat {
            switch self {
            case .rectangle, .classic: return 4 / 3
            case .cutout, .classicPortrait: return 3 / 4
            case .landscape: return 16 / 9
            case .portrait: return 9 / 16
            case .circle, .square, .free: return 1
            }
        }

        /// The roundness slider means something (a circle is always round,
        /// a cutout has no frame).
        var hasCorners: Bool { self != .circle && self != .cutout }
    }

    /// How the camera and the screen share the video, for the whole video
    /// (the Camera lane can switch it for a stretch). Screen only is the
    /// camera hidden (`visible` off).
    enum Layout: String, Codable, CaseIterable, Identifiable {
        case bubble
        /// The screen and the camera each take one part of the video.
        case split
        /// The camera fills the video.
        case cameraOnly

        var id: String { rawValue }

        /// The Camera lane layout that draws the same.
        var regionLayout: VideoCameraLayoutRegion.Layout {
            switch self {
            case .bubble: return .bubble
            case .split: return .sideBySide
            case .cameraOnly: return .fullscreen
            }
        }
    }

    /// Split screen: side by side on a landscape video, one above the
    /// other on a square or vertical one.
    struct Split: Codable, Equatable {
        enum Side: String, Codable, CaseIterable, Identifiable {
            /// Left, or top.
            case first
            /// Right, or bottom.
            case second

            var id: String { rawValue }

            func title(sideBySide: Bool) -> String {
                switch self {
                case .first: return sideBySide ? L("Left") : L("Top")
                case .second: return sideBySide ? L("Right") : L("Bottom")
                }
            }
        }

        /// Side by side (left and right) or stacked (top and bottom).
        enum Direction: String, Codable, CaseIterable, Identifiable {
            case sideBySide
            case stacked

            var id: String { rawValue }
            var title: String {
                switch self {
                case .sideBySide: return L("Side by side")
                case .stacked: return L("Stacked")
                }
            }
            var symbol: String {
                switch self {
                case .sideBySide: return "rectangle.split.2x1"
                case .stacked: return "rectangle.split.1x2"
                }
            }
        }

        var cameraSide: Side = .second
        /// The camera's share of the video (0.5: half).
        var cameraShare: Double = 0.5
        /// Between the parts, as a share of the video's short side; the
        /// video's background shows there.
        var gap: Double = 0
        /// Chosen by hand (nil: from the video's shape — side by side when
        /// it's wider than tall, stacked otherwise, as in 1.10.0).
        var direction: Direction?

        static let shareRange: ClosedRange<Double> = 0.3...0.7
        static let gapRange: ClosedRange<Double> = 0...0.06

        var keptShare: Double { min(max(cameraShare, Self.shareRange.lowerBound), Self.shareRange.upperBound) }
        var keptGap: Double { min(max(gap, Self.gapRange.lowerBound), Self.gapRange.upperBound) }
    }

    /// Where the bubble is and how wide, chosen by hand (dragging it in the
    /// editor, or the camera preview before recording). Normalized on the
    /// output with y down.
    struct Placement: Codable, Equatable {
        /// The bubble's center.
        var x: Double
        var y: Double
        /// Its width, as a share of the output's width.
        var width: Double

        static let widthRange: ClosedRange<Double> = 0.04...1
    }

    /// What's behind you in the camera picture.
    enum Backdrop: String, Codable, CaseIterable, Identifiable {
        case original
        case blur
        /// Replaced with the video's own background.
        case remove

        var id: String { rawValue }
        var title: String {
            switch self {
            case .original: return L("Original")
            case .blur: return L("Blur")
            case .remove: return L("Remove")
            }
        }
    }

    static let sizeRange: ClosedRange<Double> = 0.12...0.5

    var visible = true
    /// Height as a fraction of the output's short side.
    var size = 0.26
    var anchor: Anchor = .bottomRight
    var shape: Shape = .circle
    /// Selfie view: flipped like a mirror.
    var mirror = true
    /// The bubble gets out of the way while the screen is zoomed in.
    var shrinkWhenZoomed = true
    var backdrop: Backdrop = .original
    /// The part of the camera picture that's shown, normalized with y down
    /// on the unmirrored picture (nil: all of it).
    var crop: VideoCropRect?
    /// 0 sharp corners … 1 a full circle (nil: the shape's own corners).
    var roundness: Double?
    /// A colored edge around the bubble (nil: the thin light rim).
    var border: Border?
    /// 0 no shadow … 1 strong (nil: the usual soft shadow, 0.5).
    var shadowStrength: Double?
    /// The camera picture's color and sharpness (nil: as filmed).
    var color: VideoCameraColor?
    /// Free's width / height (nil: 1).
    var freeAspect: Double?
    /// Placed by hand (nil: at `anchor`, `size` big).
    var placement: Placement?
    /// For the whole video (nil: the bubble).
    var layout: Layout?
    /// Split screen's options, also Side by side's on the Camera lane (nil:
    /// Side by side as it was before 1.10.0, the screen letterboxed beside a
    /// narrower camera).
    var split: Split?

    var effectiveLayout: Layout { layout ?? .bubble }
    /// What Split screen and Side by side use.
    var effectiveSplit: Split { split ?? Split() }

    static let freeAspectRange: ClosedRange<Double> = 0.25...4

    struct Border: Codable, Equatable {
        var color: VideoRGBA
        /// Thickness as a fraction of the output's short side.
        var width: Double

        static let widthRange: ClosedRange<Double> = 0.002...0.02
        static let standard = Border(color: VideoRGBA(1, 1, 1), width: 0.006)
    }

    static let defaultShadowStrength = 0.5

    /// Person segmentation is needed for this look.
    var needsPersonMask: Bool { shape == .cutout || backdrop != .original }

    /// The roundness the bubble has now, set or from its shape (0…1).
    var effectiveRoundness: Double {
        if let roundness { return min(max(roundness, 0), 1) }
        return shape.roundness
    }

    /// Width / height of the bubble.
    var effectiveAspect: CGFloat {
        guard shape == .free else { return shape.aspect }
        return CGFloat(min(max(freeAspect ?? 1, Self.freeAspectRange.lowerBound), Self.freeAspectRange.upperBound))
    }

    /// Picks a shape: its own corners again, and Free starts from the
    /// bubble's ratio now. A bubble placed by hand keeps its width and
    /// center.
    mutating func choose(shape newShape: Shape) {
        if newShape == .free, shape != .free { freeAspect = Double(effectiveAspect) }
        shape = newShape
        roundness = nil
    }

    /// The same bubble at `anchor` (a zoom moving it to a free corner):
    /// as big as it is now.
    func at(anchor newAnchor: Anchor, outputSize: CGSize) -> VideoWebcamSettings {
        var moved = self
        moved.anchor = newAnchor
        if placement != nil {
            let rect = VideoFrameRenderer.webcamRect(self, outputSize: outputSize)
            moved.placement = nil
            moved.size = Double(rect.height / max(min(outputSize.width, outputSize.height), 1))
            let free = VideoFrameRenderer.webcamRect(moved, outputSize: outputSize, unclamped: true)
            moved.placement = Placement(x: Double(free.midX / max(outputSize.width, 1)), y: Double(1 - free.midY / max(outputSize.height, 1)), width: Double(rect.width / max(outputSize.width, 1)))
        }
        return moved
    }

    /// The crop, kept inside the picture and at least a sliver big (nil when
    /// it's the whole picture).
    var effectiveCrop: VideoCropRect? {
        guard let crop else { return nil }
        let kept = crop.normalized
        return kept.isFull ? nil : kept
    }

    init() {}

    private enum CodingKeys: String, CodingKey { case visible, size, anchor, shape, mirror, shrinkWhenZoomed, backdrop, crop, roundness, border, shadowStrength, color, freeAspect, placement, layout, split }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VideoWebcamSettings()
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? d.visible
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        anchor = (try? c.decode(Anchor.self, forKey: .anchor)) ?? d.anchor
        shape = (try? c.decode(Shape.self, forKey: .shape)) ?? d.shape
        mirror = try c.decodeIfPresent(Bool.self, forKey: .mirror) ?? d.mirror
        shrinkWhenZoomed = try c.decodeIfPresent(Bool.self, forKey: .shrinkWhenZoomed) ?? d.shrinkWhenZoomed
        backdrop = (try? c.decode(Backdrop.self, forKey: .backdrop)) ?? d.backdrop
        crop = try? c.decodeIfPresent(VideoCropRect.self, forKey: .crop)
        roundness = (try? c.decodeIfPresent(Double.self, forKey: .roundness)).flatMap { $0 }.map { min(max($0, 0), 1) }
        border = try? c.decodeIfPresent(Border.self, forKey: .border)
        shadowStrength = (try? c.decodeIfPresent(Double.self, forKey: .shadowStrength)).flatMap { $0 }.map { min(max($0, 0), 1) }
        color = try? c.decodeIfPresent(VideoCameraColor.self, forKey: .color)
        freeAspect = (try? c.decodeIfPresent(Double.self, forKey: .freeAspect)).flatMap { $0 }
        placement = try? c.decodeIfPresent(Placement.self, forKey: .placement)
        layout = try? c.decodeIfPresent(Layout.self, forKey: .layout)
        split = try? c.decodeIfPresent(Split.self, forKey: .split)
    }
}

/// A stretch of the timeline where the camera takes a different layout.
struct VideoCameraLayoutRegion: Codable, Equatable, Identifiable {
    enum Layout: String, Codable, CaseIterable, Identifiable {
        /// The camera in its bubble (on a video that's split or camera only).
        case bubble
        /// The camera fills the frame (intros, outros, talking points).
        case fullscreen
        /// Screen on the left, camera on the right.
        case sideBySide
        /// No camera.
        case hidden

        var id: String { rawValue }
        var title: String {
            switch self {
            case .bubble: return L("Camera bubble")
            case .fullscreen: return L("Full camera")
            case .sideBySide: return L("Side by side")
            case .hidden: return L("Camera hidden")
            }
        }
        /// For narrow buttons.
        var shortTitle: String {
            switch self {
            case .bubble: return L("Bubble")
            case .fullscreen: return L("Full camera")
            case .sideBySide: return L("Side by side")
            case .hidden: return L("Hidden")
            }
        }
        var symbol: String {
            switch self {
            case .bubble: return "person.crop.circle"
            case .fullscreen: return "person.crop.rectangle.fill"
            case .sideBySide: return "rectangle.split.2x1.fill"
            case .hidden: return "eye.slash.fill"
            }
        }
    }

    var id: UUID
    /// Source seconds.
    var start: Double
    var end: Double
    var layout: Layout
    /// Made by "Hide camera during silences": pressing it again replaces
    /// only these.
    var isSilence = false

    init(id: UUID = UUID(), start: Double, end: Double, layout: Layout, isSilence: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.layout = layout
        self.isSilence = isSilence
    }

    static let minimumDuration = 0.8

    private enum CodingKeys: String, CodingKey { case id, start, end, layout, isSilence }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        layout = try c.decode(Layout.self, forKey: .layout)
        isSilence = (try? c.decodeIfPresent(Bool.self, forKey: .isSilence)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(layout, forKey: .layout)
        if isSilence { try c.encode(true, forKey: .isSilence) }
    }
}

/// The camera footage recorded alongside a screen recording.
struct VideoWebcamRecording: Codable, Equatable {
    var path: String
    /// Seconds the camera's first frame arrived after the screen's first
    /// frame (negative: before). Camera time = screen time − offset.
    var offset: Double
    var width: Double
    var height: Double

    var url: URL { URL(fileURLWithPath: path) }
}

// MARK: - Captions

struct VideoCaptionWord: Codable, Equatable {
    var text: String
    /// Source seconds.
    var start: Double
    var end: Double
}

struct VideoCaptionLine: Codable, Equatable, Identifiable {
    var id: UUID
    /// Source seconds.
    var start: Double
    var end: Double
    var text: String
    /// Word timings for highlighting; dropped when the text is edited.
    var words: [VideoCaptionWord]
    /// This caption's own spot (nil: where every caption goes). Optional,
    /// so projects saved before it existed still open.
    var placement: VideoTextPlacement?

    init(id: UUID = UUID(), start: Double, end: Double, text: String, words: [VideoCaptionWord] = [], placement: VideoTextPlacement? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.words = words
        self.placement = placement
    }
}

enum VideoTextSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: return L("S")
        case .medium: return L("M")
        case .large: return L("L")
        }
    }
    /// Font height as a fraction of the output's short side.
    var scale: CGFloat {
        switch self {
        case .small: return 0.032
        case .medium: return 0.04
        case .large: return 0.05
        }
    }
}

enum VideoTextPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, top

    var id: String { rawValue }
    var title: String { self == .bottom ? L("Bottom") : L("Top") }
}

struct VideoCaptionStyle: Codable, Equatable {
    var visible = true
    var size: VideoTextSize = .medium
    var position: VideoTextPosition = .bottom
    /// Where every caption goes once dragged on the preview (nil: stacked at
    /// `position`).
    var placement: VideoTextPlacement?
    /// Brightens each word as it's spoken.
    var highlightWords = true
    /// The look (see VideoCaptionStyles.swift).
    var preset: VideoCaptionPreset = .classic
    /// The spoken word's color (nil: the look's own).
    var highlightColor: VideoRGBA?
    /// Typeface (VideoFonts.swift); nil: the look's own.
    var font: VideoFontChoice?
    /// How words come in (VideoCaptionAnimation.swift).
    var animation: VideoCaptionAnimation = .none

    init() {}

    private enum CodingKeys: String, CodingKey { case visible, size, position, placement, highlightWords, preset, highlightColor, font, animation }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VideoCaptionStyle()
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? d.visible
        size = (try? c.decode(VideoTextSize.self, forKey: .size)) ?? d.size
        position = (try? c.decode(VideoTextPosition.self, forKey: .position)) ?? d.position
        placement = try? c.decodeIfPresent(VideoTextPlacement.self, forKey: .placement)
        highlightWords = try c.decodeIfPresent(Bool.self, forKey: .highlightWords) ?? d.highlightWords
        preset = (try? c.decode(VideoCaptionPreset.self, forKey: .preset)) ?? d.preset
        highlightColor = try? c.decodeIfPresent(VideoRGBA.self, forKey: .highlightColor)
        font = try? c.decodeIfPresent(VideoFontChoice.self, forKey: .font)
        animation = (try? c.decodeIfPresent(VideoCaptionAnimation.self, forKey: .animation)) ?? d.animation
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(visible, forKey: .visible)
        try c.encode(size, forKey: .size)
        try c.encode(position, forKey: .position)
        try c.encodeIfPresent(placement, forKey: .placement)
        try c.encode(highlightWords, forKey: .highlightWords)
        try c.encode(preset, forKey: .preset)
        try c.encodeIfPresent(highlightColor, forKey: .highlightColor)
        try c.encodeIfPresent(font, forKey: .font)
        // Only once chosen: files from before stay as they were.
        if animation != .none { try c.encode(animation, forKey: .animation) }
    }
}

// MARK: - Keyboard shortcuts

struct VideoKeystrokeEvent: Codable, Equatable, Identifiable {
    var id: UUID
    /// Source seconds.
    var time: Double
    /// Display labels, modifiers first: ["⌘", "⇧", "4"].
    var keys: [String]

    init(id: UUID = UUID(), time: Double, keys: [String]) {
        self.id = id
        self.time = time
        self.keys = keys
    }
}

struct VideoKeystrokeStyle: Codable, Equatable {
    var visible = true
    var size: VideoTextSize = .medium
    var position: VideoTextPosition = .bottom
    /// Where the keys go once dragged on the preview (nil: stacked at
    /// `position`).
    var placement: VideoTextPlacement?
    /// Typeface for the key labels (VideoFonts.swift).
    var font: VideoFontChoice?

    init() {}

    private enum CodingKeys: String, CodingKey { case visible, size, position, placement, font }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VideoKeystrokeStyle()
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? d.visible
        size = (try? c.decode(VideoTextSize.self, forKey: .size)) ?? d.size
        position = (try? c.decode(VideoTextPosition.self, forKey: .position)) ?? d.position
        placement = try? c.decodeIfPresent(VideoTextPlacement.self, forKey: .placement)
        font = try? c.decodeIfPresent(VideoFontChoice.self, forKey: .font)
    }
}

// MARK: - Crop

/// The part of the recording that's kept, normalized with y down.
struct VideoCropRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = VideoCropRect(x: 0, y: 0, width: 1, height: 1)
    static let minimumSide = 0.08

    var isFull: Bool {
        abs(x) < 0.0005 && abs(y) < 0.0005 && abs(width - 1) < 0.0005 && abs(height - 1) < 0.0005
    }

    /// Clamped inside the frame with a minimum size.
    var normalized: VideoCropRect {
        let w = min(max(width, Self.minimumSide), 1)
        let h = min(max(height, Self.minimumSide), 1)
        return VideoCropRect(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h), width: w, height: h)
    }

    /// Source-normalized point → position inside the crop (0...1 inside).
    func map(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - CGFloat(x)) / CGFloat(max(width, 0.0001)), y: (point.y - CGFloat(y)) / CGFloat(max(height, 0.0001)))
    }

    /// Inverse of `map`.
    func unmap(_ point: CGPoint) -> CGPoint {
        CGPoint(x: CGFloat(x) + point.x * CGFloat(width), y: CGFloat(y) + point.y * CGFloat(height))
    }

    /// Whether a source-normalized point survives the crop.
    func keeps(_ point: CGPoint) -> Bool {
        let inside = map(point)
        return inside.x >= -0.005 && inside.x <= 1.005 && inside.y >= -0.005 && inside.y <= 1.005
    }
}

extension VideoDemoProject {
    /// Recorded clicks the crop keeps (ripples and Auto Zoom ignore the rest).
    var clicksInsideCrop: [VideoDemoClickEvent] {
        let crop = self.crop.normalized
        return crop.isFull ? clickEvents : clickEvents.filter { crop.keeps(CGPoint(x: $0.x, y: $0.y)) }
    }
}

// MARK: - Keystroke capture

/// Turns key presses into shortcut labels — and ignores plain typing, so
/// passwords and messages never end up in a recording.
enum VideoKeystrokeFormatter {
    // Keycap legends drawn into the video, as printed on the keys (kept
    // as they are in every language).
    private static let specialKeys: [UInt16: String] = [
        36: "↩", 76: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "esc",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// US-layout shifted symbols back to their key (⇧⌘4, not ⇧⌘$).
    private static let unshifted: [Character: String] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
    ]

    static func keys(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> [String]? {
        let flags = modifiers.intersection([.control, .option, .shift, .command])
        let special = specialKeys[keyCode]
        let isFunctionKey = special?.hasPrefix("F") == true && special != nil
        let isEscape = keyCode == 53
        // ⌥ alone types characters on many layouts (@ on German, ł and ó
        // on Polish): with a character key it's typing, not a shortcut.
        // Only ⌘ or ⌃ make a character key a shortcut; ⌥ counts with keys
        // that type nothing (arrows, Delete, Return, Tab).
        let hasShortcutModifier = !flags.intersection([.control, .command]).isEmpty
        let optionWithNonCharacter = flags.contains(.option) && special != nil && keyCode != 49
        // Plain typing (letters, Return, arrows, Delete…) is never recorded.
        guard hasShortcutModifier || optionWithNonCharacter || isFunctionKey || isEscape else { return nil }

        var labels: [String] = []
        if flags.contains(.control) { labels.append("⌃") }
        if flags.contains(.option) { labels.append("⌥") }
        if flags.contains(.shift) { labels.append("⇧") }
        if flags.contains(.command) { labels.append("⌘") }

        if let special {
            labels.append(special)
        } else if let characters, let first = characters.first {
            labels.append(unshifted[first] ?? String(first).uppercased())
        } else {
            return nil
        }
        return labels
    }

    /// Whether macOS lets LF Studios see key presses in other apps.
    static var isAllowed: Bool { AXIsProcessTrusted() }

    /// Asks macOS for the permission (opens the system prompt).
    @discardableResult
    static func requestAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
