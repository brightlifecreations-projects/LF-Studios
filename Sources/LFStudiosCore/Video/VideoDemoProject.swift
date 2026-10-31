import AppKit
import CoreGraphics
import Foundation

// MARK: - Timeline clips

struct VideoDemoTimelineClip: Codable, Equatable, Identifiable {
    static let speedRange: ClosedRange<Double> = 0.25...16

    var id: UUID
    var sourceStart: Double
    var sourceEnd: Double
    var speed: Double
    var muted: Bool
    var fadeIn: Double
    var fadeOut: Double
    /// Sped up by "Speed up typing" — pressing it again changes its speed.
    var typingSpeedUp = false
    /// Flipped left to right (Mirror, 1.14.0).
    var mirrored = false
    /// Quarter turns clockwise (Rotate, 1.14.0): 0…3.
    var quarterTurns = 0
    /// Off (V, 1.14.0): kept on the timeline, shown black and silent.
    var disabled = false

    /// Mirror, Rotate or off: only 1.14.0 and later show it.
    var needsLayerFormat: Bool { mirrored || quarterTurns % 4 != 0 || disabled }
    var turns: Int { ((quarterTurns % 4) + 4) % 4 }

    init(
        id: UUID = UUID(),
        sourceStart: Double,
        sourceEnd: Double,
        speed: Double = 1,
        muted: Bool = false,
        fadeIn: Double = 0,
        fadeOut: Double = 0,
        typingSpeedUp: Bool = false
    ) {
        self.id = id
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.speed = speed
        self.muted = muted
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.typingSpeedUp = typingSpeedUp
    }

    var sourceDuration: Double {
        max(sourceEnd - sourceStart, 0)
    }

    var normalizedSpeed: Double {
        min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
    }

    var outputDuration: Double {
        sourceDuration / normalizedSpeed
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceStart, sourceEnd, speed, muted, fadeIn, fadeOut, typingSpeedUp, mirrored, quarterTurns, disabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceStart = try container.decode(Double.self, forKey: .sourceStart)
        sourceEnd = try container.decode(Double.self, forKey: .sourceEnd)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        fadeIn = try container.decodeIfPresent(Double.self, forKey: .fadeIn) ?? 0
        fadeOut = try container.decodeIfPresent(Double.self, forKey: .fadeOut) ?? 0
        typingSpeedUp = (try? container.decodeIfPresent(Bool.self, forKey: .typingSpeedUp)) ?? false
        mirrored = (try? container.decodeIfPresent(Bool.self, forKey: .mirrored)) ?? false
        quarterTurns = (try? container.decodeIfPresent(Int.self, forKey: .quarterTurns)) ?? 0
        disabled = (try? container.decodeIfPresent(Bool.self, forKey: .disabled)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceStart, forKey: .sourceStart)
        try container.encode(sourceEnd, forKey: .sourceEnd)
        try container.encode(speed, forKey: .speed)
        try container.encode(muted, forKey: .muted)
        try container.encode(fadeIn, forKey: .fadeIn)
        try container.encode(fadeOut, forKey: .fadeOut)
        if typingSpeedUp { try container.encode(true, forKey: .typingSpeedUp) }
        // Only once used: older files stay byte for byte as they were.
        if mirrored { try container.encode(true, forKey: .mirrored) }
        if turns != 0 { try container.encode(turns, forKey: .quarterTurns) }
        if disabled { try container.encode(true, forKey: .disabled) }
    }
}

struct VideoDemoTimelineSegment: Equatable, Identifiable {
    var id: UUID { clip.id }
    let clip: VideoDemoTimelineClip
    let timelineStart: Double

    var timelineEnd: Double {
        timelineStart + duration
    }

    var duration: Double {
        clip.outputDuration
    }

    func contains(sourceTime: Double) -> Bool {
        sourceTime >= clip.sourceStart && sourceTime <= clip.sourceEnd
    }

    func contains(timelineTime: Double) -> Bool {
        timelineTime >= timelineStart && timelineTime <= timelineEnd
    }

    func sourceTime(forTimelineTime timelineTime: Double) -> Double {
        let timelineOffset = min(max(timelineTime - timelineStart, 0), duration)
        return clip.sourceStart + timelineOffset * clip.normalizedSpeed
    }

    func timelineTime(forSourceTime sourceTime: Double) -> Double {
        timelineStart + min(max(sourceTime - clip.sourceStart, 0), clip.sourceDuration) / clip.normalizedSpeed
    }
}

// MARK: - Overlays (text, arrows, highlights, blur)

enum VideoDemoOverlayEffectKind: String, Codable, CaseIterable, Identifiable {
    case text
    case arrow
    case highlight
    // rawValue stays "blur" so saved drafts keep decoding.
    case blur
    /// Dims the picture around a rectangle or an ellipse.
    case spotlight
    /// A logo, watermark, or screenshot (see VideoImageOverlays.swift).
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return L("Text")
        case .arrow: return L("Arrow")
        case .highlight: return L("Highlight")
        case .blur: return L("Blur")
        case .spotlight: return L("Spotlight")
        case .image: return L("Image")
        }
    }

    /// The English name undo steps are labeled with ("Add Arrow"): an
    /// identifier, never shown as is (VideoEditHistory.swift words it).
    var undoName: String {
        switch self {
        case .text: return "Text"
        case .arrow: return "Arrow"
        case .highlight: return "Highlight"
        case .blur: return "Blur"
        case .spotlight: return "Spotlight"
        case .image: return "Image"
        }
    }

    var icon: String {
        switch self {
        case .text: return "textformat"
        case .arrow: return "arrow.up.right"
        case .highlight: return "rectangle.dashed"
        case .blur: return "eye.slash"
        case .spotlight: return "circle.dashed.inset.filled"
        case .image: return "photo"
        }
    }
}

/// Where an arrow starts and points (video-normalized, y down).
struct VideoArrowEnds: Codable, Equatable {
    var tailX: Double
    var tailY: Double
    var headX: Double
    var headY: Double
}

/// The shape a spotlight keeps bright.
enum VideoOverlayShape: String, Codable, CaseIterable, Identifiable {
    case rectangle
    case ellipse

    var id: String { rawValue }
    var title: String { self == .rectangle ? L("Rectangle") : L("Ellipse") }
}

struct VideoDemoOverlayEffect: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: VideoDemoOverlayEffectKind
    /// Source seconds.
    var time: Double
    /// Source seconds.
    var duration: Double
    /// Center, video-normalized, y down.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var text: String
    /// Timeline lane. Stored explicitly so horizontal drags never re-layer
    /// the pill under the cursor; vertical drags change it deliberately.
    var layer: Int
    /// Arrow / highlight color, or the text tag's background (nil = the
    /// kind's default). A clear text tag means text only, with a shadow.
    var color: VideoRGBA?
    var thickness: VideoOverlayThickness
    /// Arrows point any way: nil for arrows made before ends were saved
    /// (those run from the box's lower left to its upper right).
    var arrowEnds: VideoArrowEnds?
    /// A spotlight's shape (nil: rectangle).
    var shape: VideoOverlayShape?
    /// The picture an image annotation shows.
    var image: VideoOverlayImage?
    /// How strongly a blur hides what's under it, 0.1–1 (nil: fully).
    var strength: Double?
    /// A text annotation's typeface (VideoFonts.swift).
    var font: VideoFontChoice?
    /// A blur that follows something as it moves ("Find private info",
    /// VideoOverlayMotion.swift); nil: it stays where it is.
    var motion: [VideoOverlayMotionKey]?
    /// Over the camera picture rather than the recording (true only).
    var onCamera: Bool?
    /// A text annotation turned, degrees clockwise (1.14.0; nil: upright).
    var rotation: Double?

    init(
        id: UUID = UUID(),
        kind: VideoDemoOverlayEffectKind,
        time: Double,
        duration: Double = 2,
        x: Double = 0.5,
        y: Double = 0.5,
        width: Double = 0.28,
        height: Double = 0.14,
        text: String = "Callout",
        layer: Int = 0,
        color: VideoRGBA? = nil,
        thickness: VideoOverlayThickness = .regular
    ) {
        self.id = id
        self.kind = kind
        self.time = time
        self.duration = duration
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.text = text
        self.layer = layer
        self.color = color
        self.thickness = thickness
    }

    /// The color actually drawn.
    var resolvedColor: VideoRGBA { color ?? kind.defaultColor }

    /// A blur's strength as drawn (blurs from before it could be set hide fully).
    var blurStrength: Double { min(max(strength ?? 1, Self.blurStrengthRange.lowerBound), Self.blurStrengthRange.upperBound) }
    static let blurStrengthRange: ClosedRange<Double> = 0.1...1

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(VideoDemoOverlayEffectKind.self, forKey: .kind)
        time = try container.decode(Double.self, forKey: .time)
        duration = try container.decode(Double.self, forKey: .duration)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        text = try container.decode(String.self, forKey: .text)
        layer = try container.decodeIfPresent(Int.self, forKey: .layer) ?? 0
        color = try container.decodeIfPresent(VideoRGBA.self, forKey: .color)
        thickness = (try? container.decode(VideoOverlayThickness.self, forKey: .thickness)) ?? .regular
        arrowEnds = try? container.decodeIfPresent(VideoArrowEnds.self, forKey: .arrowEnds)
        shape = try? container.decodeIfPresent(VideoOverlayShape.self, forKey: .shape)
        image = try? container.decodeIfPresent(VideoOverlayImage.self, forKey: .image)
        strength = try? container.decodeIfPresent(Double.self, forKey: .strength)
        font = try? container.decodeIfPresent(VideoFontChoice.self, forKey: .font)
        motion = try? container.decodeIfPresent([VideoOverlayMotionKey].self, forKey: .motion)
        onCamera = try? container.decodeIfPresent(Bool.self, forKey: .onCamera)
        rotation = (try? container.decodeIfPresent(Double.self, forKey: .rotation)).flatMap { $0 }
    }
}

enum VideoOverlayThickness: String, Codable, CaseIterable, Identifiable {
    case thin, regular, bold

    var id: String { rawValue }
    var title: String {
        switch self {
        case .thin: return L("Thin")
        case .regular: return L("Regular")
        case .bold: return L("Bold")
        }
    }
    var scale: CGFloat {
        switch self {
        case .thin: return 0.6
        case .regular: return 1
        case .bold: return 1.6
        }
    }
}

extension VideoDemoOverlayEffectKind {
    var defaultColor: VideoRGBA {
        switch self {
        case .arrow, .highlight: return VideoRGBA(hex: 0xFFD60A)
        case .text: return VideoRGBA(0.06, 0.06, 0.06, 0.84)
        case .blur, .spotlight, .image: return VideoRGBA(0.5, 0.5, 0.5)
        }
    }

    /// Whether a color can be chosen (blur, spotlight, and images have none).
    var hasColor: Bool { self != .blur && self != .spotlight && self != .image }

    /// Swatches offered for this kind.
    var palette: [VideoRGBA] {
        let bright: [VideoRGBA] = [
            VideoRGBA(hex: 0xFFD60A), VideoRGBA(hex: 0xFF9F0A), VideoRGBA(hex: 0xFF453A), VideoRGBA(hex: 0xFF375F),
            VideoRGBA(hex: 0xBF5AF2), VideoRGBA(hex: 0x0A84FF), VideoRGBA(hex: 0x30D158), VideoRGBA(hex: 0xFFFFFF),
        ]
        switch self {
        case .text:
            return [defaultColor] + bright + [VideoRGBA(0, 0, 0, 0)]
        case .arrow, .highlight:
            return bright + [VideoRGBA(hex: 0x1C1C1E)]
        case .blur, .spotlight, .image:
            return []
        }
    }
}

/// The last color and thickness picked for each kind — new annotations
/// start with them.
enum VideoOverlayStyleMemory {
    static func color(for kind: VideoDemoOverlayEffectKind) -> VideoRGBA? {
        guard let data = UserDefaults.standard.data(forKey: "videoOverlayColor.\(kind.rawValue)") else { return nil }
        return try? JSONDecoder().decode(VideoRGBA.self, from: data)
    }

    static func setColor(_ color: VideoRGBA?, for kind: VideoDemoOverlayEffectKind) {
        let key = "videoOverlayColor.\(kind.rawValue)"
        if let color, let data = try? JSONEncoder().encode(color) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func thickness(for kind: VideoDemoOverlayEffectKind) -> VideoOverlayThickness {
        UserDefaults.standard.string(forKey: "videoOverlayThickness.\(kind.rawValue)").flatMap(VideoOverlayThickness.init(rawValue:)) ?? .regular
    }

    static func setThickness(_ thickness: VideoOverlayThickness, for kind: VideoDemoOverlayEffectKind) {
        UserDefaults.standard.set(thickness.rawValue, forKey: "videoOverlayThickness.\(kind.rawValue)")
    }
}

// MARK: - Camera (zoom regions)

/// A span of the recording where the camera is zoomed in. The camera eases
/// in at the start and back out at the end — outside a region the full
/// frame is always visible. Regions close together chain into one pan.
struct VideoZoomRegion: Codable, Equatable, Identifiable {
    static let scaleRange: ClosedRange<Double> = 1.1...4
    static let minimumDuration = 0.4
    /// How far the framing can be moved off its subject (output units).
    static let offsetRange: ClosedRange<Double> = -0.45...0.45

    var id: UUID
    /// Source seconds.
    var start: Double
    /// Source seconds.
    var end: Double
    var scale: Double
    /// true: the camera glides after the pointer. false: it holds `focus`.
    var followsCursor: Bool
    /// Manual focus, video-normalized, y down.
    var focusX: Double
    var focusY: Double
    /// Created by Auto Zoom — re-running it replaces only these.
    var isAuto: Bool
    /// The camera follows the text cursor ("Track where I type"); wins
    /// over `followsCursor`.
    var followsTyping = false
    /// Made by "Add typing zooms" — pressing it again replaces only these.
    var isTyping = false
    /// A loupe: a magnifier over one spot while the rest of the frame stays
    /// (nil: the whole frame zooms). `scale` is its magnification.
    var loupe: VideoLoupeStyle?
    /// Where the subject sits on the output, off the middle (output units,
    /// y down) — "Fit zooms around camera" moves it clear of the bubble.
    /// For a loupe, how far the loupe sits from its subject.
    var offsetX = 0.0
    var offsetY = 0.0
    /// The camera bubble slides to this corner while the zoom plays (nil:
    /// it stays where it is).
    var cameraCorner: VideoWebcamSettings.Anchor?

    init(
        id: UUID = UUID(),
        start: Double,
        end: Double,
        scale: Double = 2,
        followsCursor: Bool = true,
        focusX: Double = 0.5,
        focusY: Double = 0.5,
        isAuto: Bool = false
    ) {
        self.id = id
        self.start = max(start, 0)
        self.end = max(end, start + Self.minimumDuration)
        self.scale = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        self.followsCursor = followsCursor
        self.focusX = min(max(focusX, 0), 1)
        self.focusY = min(max(focusY, 0), 1)
        self.isAuto = isAuto
    }

    var duration: Double { max(end - start, 0) }
    var isLoupe: Bool { loupe != nil }
    var offset: CGPoint { CGPoint(x: offsetX, y: offsetY) }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, scale, followsCursor, focusX, focusY, isAuto
        case followsTyping, isTyping, loupe, offsetX, offsetY, cameraCorner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        scale = try c.decode(Double.self, forKey: .scale)
        followsCursor = try c.decode(Bool.self, forKey: .followsCursor)
        focusX = try c.decode(Double.self, forKey: .focusX)
        focusY = try c.decode(Double.self, forKey: .focusY)
        isAuto = try c.decode(Bool.self, forKey: .isAuto)
        followsTyping = (try? c.decodeIfPresent(Bool.self, forKey: .followsTyping)) ?? false
        isTyping = (try? c.decodeIfPresent(Bool.self, forKey: .isTyping)) ?? false
        loupe = try? c.decodeIfPresent(VideoLoupeStyle.self, forKey: .loupe)
        offsetX = (try? c.decodeIfPresent(Double.self, forKey: .offsetX)) ?? 0
        offsetY = (try? c.decodeIfPresent(Double.self, forKey: .offsetY)) ?? 0
        cameraCorner = try? c.decodeIfPresent(VideoWebcamSettings.Anchor.self, forKey: .cameraCorner)
    }

    /// The new keys only when used: a project without them saves exactly
    /// as it did.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(scale, forKey: .scale)
        try c.encode(followsCursor, forKey: .followsCursor)
        try c.encode(focusX, forKey: .focusX)
        try c.encode(focusY, forKey: .focusY)
        try c.encode(isAuto, forKey: .isAuto)
        if followsTyping { try c.encode(true, forKey: .followsTyping) }
        if isTyping { try c.encode(true, forKey: .isTyping) }
        try c.encodeIfPresent(loupe, forKey: .loupe)
        if offsetX != 0 { try c.encode(offsetX, forKey: .offsetX) }
        if offsetY != 0 { try c.encode(offsetY, forKey: .offsetY) }
        try c.encodeIfPresent(cameraCorner, forKey: .cameraCorner)
    }
}

enum VideoZoomSpeed: String, Codable, CaseIterable, Identifiable {
    case slow
    case smooth
    case quick
    case instant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slow: return L("Slow")
        case .smooth: return L("Smooth")
        case .quick: return L("Quick")
        case .instant: return L("Instant")
        }
    }

    /// Seconds for a full zoom in or out.
    var transitionDuration: Double {
        switch self {
        case .slow: return 1.7
        case .smooth: return 1.2
        case .quick: return 0.75
        case .instant: return 0.0001
        }
    }

    /// Angular frequency of the spring that glides the camera after the
    /// pointer while zoomed.
    var followStiffness: Double {
        switch self {
        case .slow: return 4
        case .smooth: return 5.5
        case .quick: return 7.5
        case .instant: return 12
        }
    }
}

/// Legacy (pre-regions) camera keyframe. Still decoded so old drafts
/// migrate into regions.
struct VideoDemoZoomKeyframe: Codable, Equatable, Identifiable {
    var id: UUID
    var time: Double
    var scale: Double
    var focusX: Double
    var focusY: Double

    init(id: UUID = UUID(), time: Double, scale: Double = 1.65, focusX: Double = 0.5, focusY: Double = 0.5) {
        self.id = id
        self.time = max(time, 0)
        self.scale = min(max(scale, 1), 3)
        self.focusX = min(max(focusX, 0), 1)
        self.focusY = min(max(focusY, 0), 1)
    }
}

// MARK: - Cursor

struct VideoCursorSettings: Codable, Equatable {
    enum Smoothing: String, Codable, CaseIterable, Identifiable {
        case off
        case light
        case smooth
        case silky

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return L("Off")
            case .light: return L("Light")
            case .smooth: return L("Smooth")
            case .silky: return L("Silky")
            }
        }

        /// Critically-damped spring frequency (rad/s); nil = raw path.
        var stiffness: Double? {
            switch self {
            case .off: return nil
            case .light: return 26
            case .smooth: return 15
            case .silky: return 9.5
            }
        }
    }

    enum ClickEffect: String, Codable, CaseIterable, Identifiable {
        case none
        case press
        case ripple

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return L("None")
            case .press: return L("Press")
            case .ripple: return L("Ripple")
            }
        }
    }

    static let sizeRange: ClosedRange<Double> = 0.6...4

    var visible: Bool = true
    /// Multiplier on the real pointer size.
    var size: Double = 1.6
    var smoothing: Smoothing = .smooth
    var clickEffect: ClickEffect = .ripple
    var hideWhenIdle: Bool = true
    var motionBlur: Bool = true
    /// Draw the arrow even when the recording captured I-beams, hands…
    var alwaysArrow: Bool = false
    /// Hide the pointer's last dash to the Stop button.
    var tidyEnding: Bool = true
    /// The pointer glides back to where it started over the last
    /// `returnDuration` seconds, so the video loops (VideoCursorLoop.swift).
    var returnToStart: Bool = false
    var returnDuration: Double = 0.8
    /// How the pointer looks (VideoCursorStyles.swift): the recording's own
    /// unless another style is chosen.
    var style: VideoCursorStyle = .classic
    /// The picture for the Custom image style.
    var customImage: VideoCursorImage?

    static let returnDurationRange: ClosedRange<Double> = 0.3...2

    init() {}

    private enum CodingKeys: String, CodingKey {
        case visible, size, smoothing, clickEffect, hideWhenIdle, motionBlur, alwaysArrow, tidyEnding, returnToStart, returnDuration
        case style, customImage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VideoCursorSettings()
        visible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? defaults.visible
        size = try container.decodeIfPresent(Double.self, forKey: .size) ?? defaults.size
        smoothing = try container.decodeIfPresent(Smoothing.self, forKey: .smoothing) ?? defaults.smoothing
        clickEffect = try container.decodeIfPresent(ClickEffect.self, forKey: .clickEffect) ?? defaults.clickEffect
        hideWhenIdle = try container.decodeIfPresent(Bool.self, forKey: .hideWhenIdle) ?? defaults.hideWhenIdle
        motionBlur = try container.decodeIfPresent(Bool.self, forKey: .motionBlur) ?? defaults.motionBlur
        alwaysArrow = try container.decodeIfPresent(Bool.self, forKey: .alwaysArrow) ?? defaults.alwaysArrow
        tidyEnding = try container.decodeIfPresent(Bool.self, forKey: .tidyEnding) ?? defaults.tidyEnding
        returnToStart = try container.decodeIfPresent(Bool.self, forKey: .returnToStart) ?? defaults.returnToStart
        returnDuration = try container.decodeIfPresent(Double.self, forKey: .returnDuration) ?? defaults.returnDuration
        style = (try? container.decodeIfPresent(VideoCursorStyle.self, forKey: .style)) ?? defaults.style
        customImage = try? container.decodeIfPresent(VideoCursorImage.self, forKey: .customImage)
    }

    /// The style keys only once one is chosen: older settings save as before.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visible, forKey: .visible)
        try container.encode(size, forKey: .size)
        try container.encode(smoothing, forKey: .smoothing)
        try container.encode(clickEffect, forKey: .clickEffect)
        try container.encode(hideWhenIdle, forKey: .hideWhenIdle)
        try container.encode(motionBlur, forKey: .motionBlur)
        try container.encode(alwaysArrow, forKey: .alwaysArrow)
        try container.encode(tidyEnding, forKey: .tidyEnding)
        try container.encode(returnToStart, forKey: .returnToStart)
        try container.encode(returnDuration, forKey: .returnDuration)
        if style != .classic { try container.encode(style, forKey: .style) }
        try container.encodeIfPresent(customImage, forKey: .customImage)
    }
}

// MARK: - Audio

struct VideoAudioSettings: Codable, Equatable {
    static let volumeRange: ClosedRange<Double> = 0...1

    var volume: Double = 1
    var muted: Bool = false
    /// Your microphone, when the recording has it on its own track.
    var voiceVolume: Double = 1
    /// Sound from the Mac, when the recording has it on its own track.
    var systemVolume: Double = 1
    /// Voice isolation + rumble filter + gentle compression on the mic.
    var enhanceVoice = false
    /// Exports at a steady −16 LUFS (peaks kept under −1 dBFS).
    var normalizeLoudness = true
    /// Podcast mode's voice chain (nil: off).
    var podcast: VideoPodcastSettings?

    init() {}

    var effectiveVolume: Float { muted ? 0 : Float(min(max(volume, Self.volumeRange.lowerBound), Self.volumeRange.upperBound)) }

    func effectiveVolume(for kind: VideoAudioKind) -> Float {
        let level: Double
        switch kind {
        case .microphone: level = voiceVolume
        case .system: level = systemVolume
        case .mixed: level = 1
        }
        return effectiveVolume * Float(min(max(level, Self.volumeRange.lowerBound), Self.volumeRange.upperBound))
    }

    /// Nothing audible would come out.
    func isSilent(kinds: [VideoAudioKind]) -> Bool {
        kinds.isEmpty || kinds.allSatisfy { effectiveVolume(for: $0) < 0.0005 }
    }

    private enum CodingKeys: String, CodingKey { case volume, muted, voiceVolume, systemVolume, enhanceVoice, normalizeLoudness, podcast }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VideoAudioSettings()
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? d.volume
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? d.muted
        voiceVolume = try c.decodeIfPresent(Double.self, forKey: .voiceVolume) ?? d.voiceVolume
        systemVolume = try c.decodeIfPresent(Double.self, forKey: .systemVolume) ?? d.systemVolume
        enhanceVoice = try c.decodeIfPresent(Bool.self, forKey: .enhanceVoice) ?? d.enhanceVoice
        normalizeLoudness = try c.decodeIfPresent(Bool.self, forKey: .normalizeLoudness) ?? d.normalizeLoudness
        podcast = try? c.decodeIfPresent(VideoPodcastSettings.self, forKey: .podcast)
    }
}

// MARK: - Project

struct VideoDemoProject: Codable, Equatable, Identifiable {
    static let currentVersion = 2

    enum AspectPreset: String, Codable, CaseIterable, Identifiable {
        case source
        case widescreen
        case classic
        case square
        case portrait
        case vertical
        /// 16:10, a Mac screen.
        case mac
        /// 21:9, cinematic.
        case cinema
        /// Any shape (the project's `customAspect`).
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .source: return L("Auto")
            case .widescreen: return "16:9"
            case .classic: return "4:3"
            case .square: return "1:1"
            case .portrait: return "4:5"
            case .vertical: return "9:16"
            case .mac: return "16:10"
            case .cinema: return "21:9"
            case .custom: return L("Custom…")
            }
        }

        var detail: String {
            switch self {
            case .source: return L("Match the recording")
            case .widescreen: return L("YouTube, presentations")
            case .classic: return L("Docs, slides")
            case .square: return L("Social feeds")
            case .portrait: return L("Instagram, LinkedIn")
            case .vertical: return L("Reels, TikTok, Shorts")
            case .mac: return L("Mac screen")
            case .cinema: return L("Cinematic")
            case .custom: return L("Any shape, like 3:2")
            }
        }

        var symbol: String {
            switch self {
            case .source: return "rectangle.dashed"
            case .widescreen: return "rectangle.ratio.16.to.9"
            case .classic: return "rectangle.ratio.4.to.3"
            case .square: return "square"
            case .portrait: return "rectangle.portrait"
            case .vertical: return "rectangle.ratio.9.to.16"
            case .mac: return "rectangle"
            case .cinema: return "rectangle.ratio.16.to.9"
            case .custom: return "aspectratio"
            }
        }

        /// Width / height, nil for "match the recording".
        var ratio: CGFloat? {
            switch self {
            case .source: return nil
            case .widescreen: return 16 / 9
            case .classic: return 4 / 3
            case .square: return 1
            case .portrait: return 4 / 5
            case .vertical: return 9 / 16
            case .mac: return 16 / 10
            case .cinema: return 21 / 9
            // The project's own (see `VideoDemoProject.canvasSize()`).
            case .custom: return nil
            }
        }

        /// Logical canvas: the short side is always 1080 so padding, corner
        /// radius, and type sizes mean the same thing in every aspect. The
        /// export picks the real pixel size independently.
        func canvasSize(sourceSize: CGSize) -> CGSize {
            let size = sourceSize.width > 0 && sourceSize.height > 0 ? sourceSize : CGSize(width: 1920, height: 1080)
            let ratio = self.ratio ?? (size.width / size.height)
            if ratio >= 1 {
                return CGSize(width: Self.even(1080 * ratio), height: 1080)
            }
            return CGSize(width: 1080, height: Self.even(1080 / ratio))
        }

        func previewAspectRatio(sourceSize: CGSize) -> CGFloat {
            let size = canvasSize(sourceSize: sourceSize)
            guard size.height > 0 else { return 16 / 9 }
            return size.width / size.height
        }

        static func even(_ value: CGFloat) -> CGFloat {
            let rounded = max(2, Int(value.rounded()))
            return CGFloat(rounded.isMultiple(of: 2) ? rounded : rounded + 1)
        }
    }

    static let minimumClipDuration = 0.1
    static let paddingRange: ClosedRange<Double> = 0...0.3
    static let cornerRadiusRange: ClosedRange<Double> = 0...80

    var version: Int
    var id: UUID
    var sourcePath: String
    var createdAt: Date
    var sourceWidth: Double
    var sourceHeight: Double
    var trimStart: Double
    var trimEnd: Double
    var timelineClips: [VideoDemoTimelineClip]

    // Frame
    var aspectPreset: AspectPreset
    var background: VideoBackground
    /// 0...1 — softens image and wallpaper backgrounds.
    var backgroundBlur: Double
    /// Margin around the video, as a fraction of the canvas's short side.
    var padding: Double
    /// Canvas pixels on the 1080 reference.
    var cornerRadius: Double
    /// 0...1
    var shadow: Double
    /// The shadow fine-tuned (VideoShadow.swift); nil: the classic shadow
    /// from `shadow` alone.
    var shadowStyle: VideoShadowStyle?
    /// Hairline highlight around the video edge.
    var outline: Bool

    // Camera
    var zoomRegions: [VideoZoomRegion]
    var zoomSpeed: VideoZoomSpeed
    var defaultZoomScale: Double
    /// 0...1 — blur along fast camera moves.
    var motionBlur: Double

    var overlayEffects: [VideoDemoOverlayEffect]

    // Pointer
    var cursorSamples: [VideoDemoCursorSample]
    var clickEvents: [VideoDemoClickEvent]
    /// The recording already contains the system cursor in its pixels.
    var nativeCursorVisible: Bool
    var cursor: VideoCursorSettings

    var audio: VideoAudioSettings

    // Webcam, captions, keyboard shortcuts, crop
    var webcam: VideoWebcamSettings
    /// Where the camera switches to full screen, side by side, or hides.
    var cameraLayouts: [VideoCameraLayoutRegion] = []
    /// Camera footage filmed apart from the recording; shown instead of the
    /// recorded camera (VideoImportedCamera.swift).
    var importedCamera: VideoImportedCamera?
    /// Recorded for split screen: the whole video's width / height (the
    /// recording is only the screen's part). Auto uses it while the video
    /// is split.
    var splitVideoAspect: Double?
    /// Custom… in the ratio menu: width / height.
    var customAspect: Double?
    /// The timeline's Hide, Mute, Lock and collapsed rows, by track
    /// (VideoTimelineTracks.swift); none set: everything shows and plays.
    var trackStates: [String: VideoTrackState] = [:]
    /// Auto-zoom on clicks (the Zoom panel's switch). New recordings start
    /// with it off; projects saved before it existed count as on, so their
    /// zoom options stay as they were (VideoManualOnly.swift).
    var autoZoom = true
    /// Narrow outputs (9:16, 4:5, 1:1) fill the frame and pan with the
    /// pointer instead of letterboxing the recording.
    var reframe = false
    var captions: [VideoCaptionLine]
    /// The language the captions were transcribed in (BCP-47), for
    /// language-aware cleanup like "Remove ums".
    var transcriptLanguage: String?
    var captionStyle: VideoCaptionStyle
    var keystrokes: [VideoKeystrokeEvent]
    var keystrokeStyle: VideoKeystrokeStyle
    var crop: VideoCropRect

    // Title cards, music, click sounds, transitions, translated captions,
    // and appended recordings — each lives in its own file.
    var cards = VideoTitleCards()
    var music: VideoMusicTrack?
    /// Sound files added to the video, each its own track (VideoExternalAudio.swift).
    var audioTracks: [VideoExternalAudioTrack] = []
    var clickSounds = VideoClickSoundSettings()
    var transitions = VideoTransitionSettings()
    var captionTracks = VideoCaptionTracks()
    /// Every recording on the source axis, in order (empty: just this one).
    var sources: [VideoProjectSource] = []
    /// Flagged moments, in recorded time (VideoMarkers.swift).
    var markers: [VideoMarker] = []
    /// Where the text cursor was while recording ("Track where I type"):
    /// positions only.
    var textCursor: [VideoTextCursorSample] = []
    /// When keys went down while recording ("Record when keys are
    /// pressed"): times only, never which keys.
    var keyPresses: [Double] = []
    /// The look new loupes get (the last one edited, or a preset's).
    var loupeStyle: VideoLoupeStyle?
    /// "Keep face centered" (nil: never analyzed / off).
    var faceTracking: VideoFaceTracking?
    /// The cleaned-up voices this edit plays, named so a saved project or
    /// handoff carries them to another Mac (VideoProjectCaches.swift).
    var carriedVoices: [VideoCarriedVoice] = []
    /// The speaker notes read while recording (nil: none).
    var speakerNotes: String?
    /// "Adapt to this ratio" (VideoRatioVersions.swift): each adapted ratio's
    /// own version, keyed by AspectPreset raw value…
    var ratioVersions: [String: VideoRatioVersion] = [:]
    /// …the values every other ratio shares (nil: nothing adapted yet)…
    var ratioShared: VideoRatioVersion?
    /// …the ratio the project was in before the first one was adapted…
    var ratioBase: AspectPreset?
    /// …and the ratio before the last switch.
    var previousRatio: AspectPreset?
    /// The reframing window keeps zoom targets in view (set by Adapt).
    var reframeFollowsZooms = false
    /// The Library's media: files imported but not (yet) in the video, and
    /// the names and folders given there (nil: never used,
    /// VideoMediaBin.swift).
    var mediaBin: VideoMediaBin?
    /// Video and picture tracks above the main track, lowest first
    /// (VideoLayers.swift, 1.14.0).
    var layerTracks: [VideoLayerTrack] = []

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
    var sourceSize: CGSize { CGSize(width: sourceWidth, height: sourceHeight) }
    /// The recording's pixel size after cropping.
    var croppedSourceSize: CGSize {
        let crop = self.crop.normalized
        return CGSize(width: sourceWidth * crop.width, height: sourceHeight * crop.height)
    }

    /// True when the frame is just the recording: no margin, so background,
    /// corners, and shadow can't show.
    var usesRawSourceFrame: Bool { padding <= 0.0005 }
    var effectiveCornerRadius: Double { usesRawSourceFrame ? 0 : cornerRadius }
    /// The classic shadow (none while the shadow is fine-tuned).
    var effectiveShadow: Double { usesRawSourceFrame || shadowStyle != nil ? 0 : shadow }

    /// Whether a drawn pointer can appear at all (the recording captured the
    /// path, and the pixels don't already contain the system cursor).
    var canRenderCursor: Bool { !cursorSamples.isEmpty && (!nativeCursorVisible || appendedSourceHasPointer) }
    var rendersCursor: Bool { canRenderCursor && cursor.visible }

    static func make(sourceURL: URL, duration: Double = 0, sourceSize: CGSize = .zero) -> VideoDemoProject {
        var project = VideoDemoProject(
            version: currentVersion,
            id: UUID(),
            sourcePath: sourceURL.path,
            createdAt: Date(),
            sourceWidth: Double(sourceSize.width),
            sourceHeight: Double(sourceSize.height),
            trimStart: 0,
            trimEnd: max(duration, 0),
            timelineClips: duration > 0 ? [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: max(duration, 0))] : [],
            aspectPreset: .widescreen,
            background: VideoBackgroundCatalog.defaultBackground,
            backgroundBlur: 0,
            padding: 0.085,
            cornerRadius: 18,
            shadow: 0.55,
            outline: true,
            zoomRegions: [],
            zoomSpeed: .smooth,
            defaultZoomScale: 2,
            motionBlur: 0.5,
            overlayEffects: [],
            cursorSamples: [],
            clickEvents: [],
            nativeCursorVisible: true,
            cursor: VideoCursorSettings(),
            audio: VideoAudioSettings(),
            webcam: VideoWebcamSettings(),
            captions: [],
            captionStyle: VideoCaptionStyle(),
            keystrokes: [],
            keystrokeStyle: VideoKeystrokeStyle(),
            crop: .full
        )
        // Nothing is applied by itself: My Style is a button (Style ▸ Apply my
        // style), and new recordings open plain (`fresh`).
        return project
    }

    mutating func apply(metadata: VideoDemoRecordingMetadata) {
        sourceWidth = metadata.sourceWidth
        sourceHeight = metadata.sourceHeight
        nativeCursorVisible = metadata.nativeCursorVisible
        cursorSamples = metadata.cursorSamples
        clickEvents = metadata.clickEvents
        keystrokes = metadata.keystrokes ?? []
        markers = metadata.markers ?? []
        textCursor = metadata.textCursor ?? []
        keyPresses = metadata.keyPresses ?? []
        speakerNotes = metadata.speakerNotes
        cursor.visible = metadata.shouldRenderCursor
        if metadata.webcam != nil { apply(cameraSetup: metadata.cameraSetup) }
        if trimEnd <= 0 {
            trimEnd = metadata.duration
        }
        ensureTimeline(totalDuration: metadata.duration)
    }

    mutating func apply(aspectPreset preset: AspectPreset) {
        aspectPreset = preset
    }

    // MARK: Trim + timeline math

    func normalizedTrim(totalDuration: Double) -> (start: Double, end: Double) {
        let total = max(totalDuration, 0)
        guard total > 0 else { return (0, 0) }
        let start = min(max(trimStart, 0), max(total - 0.1, 0))
        let end = min(max(trimEnd, start + 0.1), total)
        return (start, end)
    }

    mutating func ensureTimeline(totalDuration: Double) {
        let clips = normalizedTimelineClips(totalDuration: totalDuration)
        if clips.isEmpty, totalDuration > 0 {
            timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: totalDuration)]
        } else {
            timelineClips = clips
        }
        syncTrimToTimeline(totalDuration: totalDuration)
    }

    func normalizedTimelineClips(totalDuration: Double) -> [VideoDemoTimelineClip] {
        let total = max(totalDuration, 0)
        guard total > 0 else { return [] }

        let fallbackTrim = normalizedTrim(totalDuration: total)
        let sourceClips = timelineClips.isEmpty
            ? [VideoDemoTimelineClip(sourceStart: fallbackTrim.start, sourceEnd: fallbackTrim.end)]
            : timelineClips

        return sourceClips.compactMap { clip in
            let start = min(max(clip.sourceStart, 0), max(total - Self.minimumClipDuration, 0))
            let end = min(max(clip.sourceEnd, start + Self.minimumClipDuration), total)
            guard end - start >= Self.minimumClipDuration else { return nil }
            var kept = clip
            kept.sourceStart = start
            kept.sourceEnd = end
            return kept
        }
    }

    func timelineSegments(totalDuration: Double) -> [VideoDemoTimelineSegment] {
        // An intro card plays first; the clips follow it.
        var timelineStart = timelineLeadIn
        return normalizedTimelineClips(totalDuration: totalDuration).map { clip in
            let segment = VideoDemoTimelineSegment(clip: clip, timelineStart: timelineStart)
            timelineStart += clip.outputDuration
            return segment
        }
    }

    func timelineDuration(totalDuration: Double) -> Double {
        outputDuration(segments: timelineSegments(totalDuration: totalDuration))
    }

    func sourceTime(forTimelineTime timelineTime: Double, totalDuration: Double) -> Double {
        Self.sourceTime(forTimelineTime: timelineTime, segments: timelineSegments(totalDuration: totalDuration))
    }

    static func sourceTime(forTimelineTime timelineTime: Double, segments: [VideoDemoTimelineSegment]) -> Double {
        guard let first = segments.first else { return 0 }
        let safeTimeline = min(max(timelineTime, 0), max(segments.last?.timelineEnd ?? 0, 0))
        for segment in segments where safeTimeline <= segment.timelineEnd {
            return segment.sourceTime(forTimelineTime: safeTimeline)
        }
        return segments.last?.clip.sourceEnd ?? first.clip.sourceStart
    }

    func timelineTime(forSourceTime sourceTime: Double, totalDuration: Double) -> Double {
        let segments = timelineSegments(totalDuration: totalDuration)
        guard let first = segments.first else { return 0 }

        if let included = timelineTimeIfIncluded(sourceTime: sourceTime, segments: segments) {
            return included
        }

        var nearest = (distance: abs(sourceTime - first.clip.sourceStart), timelineTime: first.timelineStart)
        for segment in segments {
            let startDistance = abs(sourceTime - segment.clip.sourceStart)
            if startDistance < nearest.distance {
                nearest = (startDistance, segment.timelineStart)
            }
            let endDistance = abs(sourceTime - segment.clip.sourceEnd)
            if endDistance < nearest.distance {
                nearest = (endDistance, segment.timelineEnd)
            }
        }
        return nearest.timelineTime
    }

    func timelineTimeIfIncluded(sourceTime: Double, totalDuration: Double) -> Double? {
        timelineTimeIfIncluded(sourceTime: sourceTime, segments: timelineSegments(totalDuration: totalDuration))
    }

    func timelineTimeIfIncluded(sourceTime: Double, segments: [VideoDemoTimelineSegment]) -> Double? {
        Self.timelineTimeIfIncluded(sourceTime: sourceTime, segments: segments)
    }

    static func timelineTimeIfIncluded(sourceTime: Double, segments: [VideoDemoTimelineSegment]) -> Double? {
        for segment in segments where segment.contains(sourceTime: sourceTime) {
            return segment.timelineTime(forSourceTime: sourceTime)
        }
        return nil
    }

    /// Maps a source-time span onto the edited timeline: one piece per clip
    /// it survives in (cuts split it, speed changes stretch it).
    static func timelineRanges(sourceStart: Double, sourceEnd: Double, segments: [VideoDemoTimelineSegment]) -> [ClosedRange<Double>] {
        guard sourceEnd > sourceStart else { return [] }
        var ranges: [ClosedRange<Double>] = []
        for segment in segments {
            let start = max(sourceStart, segment.clip.sourceStart)
            let end = min(sourceEnd, segment.clip.sourceEnd)
            guard end > start else { continue }
            let a = segment.timelineTime(forSourceTime: start)
            let b = segment.timelineTime(forSourceTime: end)
            if let last = ranges.last, abs(last.upperBound - a) < 0.0005 {
                ranges[ranges.count - 1] = last.lowerBound...b
            } else {
                ranges.append(a...b)
            }
        }
        return ranges
    }

    mutating func splitClip(atSourceTime sourceTime: Double, totalDuration: Double) -> UUID? {
        var clips = normalizedTimelineClips(totalDuration: totalDuration)
        guard let index = clips.firstIndex(where: {
            sourceTime > $0.sourceStart + Self.minimumClipDuration &&
            sourceTime < $0.sourceEnd - Self.minimumClipDuration
        }) else {
            return nil
        }

        // Both halves keep everything else about the clip (speed, sound,
        // mirror, turn, on/off).
        let original = clips[index]
        var first = original
        first.sourceEnd = sourceTime
        first.fadeOut = 0
        var second = original
        second.id = UUID()
        second.sourceStart = sourceTime
        second.fadeIn = 0
        clips.replaceSubrange(index...index, with: [first, second])
        timelineClips = clips
        syncTrimToTimeline(totalDuration: totalDuration)
        return second.id
    }

    mutating func deleteClip(id: UUID, totalDuration: Double) -> UUID? {
        var clips = normalizedTimelineClips(totalDuration: totalDuration)
        guard clips.count > 1, let index = clips.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        clips.remove(at: index)
        timelineClips = clips
        syncTrimToTimeline(totalDuration: totalDuration)
        return clips[min(index, clips.count - 1)].id
    }

    mutating func deleteTimelineRange(start: Double, end: Double, totalDuration: Double) -> UUID? {
        let duration = timelineDuration(totalDuration: totalDuration)
        guard duration > Self.minimumClipDuration else { return nil }

        let rangeStart = min(max(min(start, end), 0), max(duration - Self.minimumClipDuration, 0))
        let rangeEnd = min(max(max(start, end), rangeStart + Self.minimumClipDuration), duration)
        guard rangeEnd - rangeStart >= Self.minimumClipDuration else { return nil }

        var remaining: [VideoDemoTimelineClip] = []
        for segment in timelineSegments(totalDuration: totalDuration) {
            if segment.timelineEnd <= rangeStart || segment.timelineStart >= rangeEnd {
                remaining.append(segment.clip)
                continue
            }

            if rangeStart > segment.timelineStart + Self.minimumClipDuration {
                let sourceEnd = segment.sourceTime(forTimelineTime: min(rangeStart, segment.timelineEnd))
                if sourceEnd - segment.clip.sourceStart >= Self.minimumClipDuration {
                    var kept = segment.clip
                    kept.sourceEnd = sourceEnd
                    kept.fadeOut = 0
                    remaining.append(kept)
                }
            }

            if rangeEnd < segment.timelineEnd - Self.minimumClipDuration {
                let sourceStart = segment.sourceTime(forTimelineTime: max(rangeEnd, segment.timelineStart))
                if segment.clip.sourceEnd - sourceStart >= Self.minimumClipDuration {
                    var kept = segment.clip
                    kept.id = UUID()
                    kept.sourceStart = sourceStart
                    kept.fadeIn = 0
                    remaining.append(kept)
                }
            }
        }

        guard !remaining.isEmpty else { return nil }
        timelineClips = remaining
        syncTrimToTimeline(totalDuration: totalDuration)

        let nextTimeline = min(rangeStart, max(timelineDuration(totalDuration: totalDuration) - 0.001, 0))
        return timelineSegments(totalDuration: totalDuration).first(where: { $0.contains(timelineTime: nextTimeline) })?.id
            ?? timelineClips.last?.id
    }

    mutating func trimClip(id: UUID, sourceStart: Double? = nil, sourceEnd: Double? = nil, totalDuration: Double) -> Bool {
        var clips = normalizedTimelineClips(totalDuration: totalDuration)
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return false }

        var clip = clips[index]
        // A clip may not grow into the source range of any other clip (clips
        // can be in any order on the timeline).
        let others = clips.indices.filter { $0 != index }.map { clips[$0] }
        let lowerBound = others.map(\.sourceEnd).filter { $0 <= clip.sourceStart + 0.0001 }.max() ?? 0
        let upperBound = others.map(\.sourceStart).filter { $0 >= clip.sourceEnd - 0.0001 }.min() ?? totalDuration
        if let sourceStart {
            let floor = min(lowerBound, clip.sourceStart)
            clip.sourceStart = min(max(sourceStart, floor, 0), clip.sourceEnd - Self.minimumClipDuration)
        }
        if let sourceEnd {
            let ceiling = max(upperBound, clip.sourceEnd)
            clip.sourceEnd = min(max(sourceEnd, clip.sourceStart + Self.minimumClipDuration), min(ceiling, totalDuration))
        }

        guard clip.sourceDuration >= Self.minimumClipDuration else { return false }
        clip.speed = clip.normalizedSpeed
        clip.fadeIn = min(max(clip.fadeIn, 0), max(clip.outputDuration / 2, 0))
        clip.fadeOut = min(max(clip.fadeOut, 0), max(clip.outputDuration / 2, 0))
        clips[index] = clip
        timelineClips = clips
        syncTrimToTimeline(totalDuration: totalDuration)
        return true
    }

    mutating func updateClip(id: UUID, totalDuration: Double, update: (inout VideoDemoTimelineClip) -> Void) -> Bool {
        var clips = normalizedTimelineClips(totalDuration: totalDuration)
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return false }
        update(&clips[index])
        clips[index].speed = clips[index].normalizedSpeed
        clips[index].fadeIn = min(max(clips[index].fadeIn, 0), max(clips[index].outputDuration / 2, 0))
        clips[index].fadeOut = min(max(clips[index].fadeOut, 0), max(clips[index].outputDuration / 2, 0))
        timelineClips = clips
        syncTrimToTimeline(totalDuration: totalDuration)
        return true
    }

    func overlayEffectsActive(at sourceTime: Double) -> [VideoDemoOverlayEffect] {
        overlayEffects.filter { effect in
            sourceTime >= effect.time && sourceTime <= effect.time + max(effect.duration, 0.1)
        }
    }

    /// Makes effect layers consistent: each effect keeps its chosen layer
    /// unless it overlaps an earlier effect on that layer (then it takes the
    /// next free one), and empty layers are compacted away. Returns the
    /// effects sorted by time. Runs at load and when a drag ends — never
    /// mid-drag, which is what kept re-layering pills under the cursor.
    static func normalizedEffectLayers(_ effects: [VideoDemoOverlayEffect]) -> [VideoDemoOverlayEffect] {
        var placed: [VideoDemoOverlayEffect] = []
        let ordered = effects.sorted {
            $0.time != $1.time ? $0.time < $1.time : $0.id.uuidString < $1.id.uuidString
        }
        for var effect in ordered {
            let start = effect.time
            let end = effect.time + max(effect.duration, 0.05)
            func conflicts(_ layer: Int) -> Bool {
                placed.contains {
                    $0.layer == layer && $0.time < end - 0.0001 && ($0.time + max($0.duration, 0.05)) > start + 0.0001
                }
            }
            var layer = max(effect.layer, 0)
            while conflicts(layer) { layer += 1 }
            effect.layer = layer
            placed.append(effect)
        }

        let usedLayers = Set(placed.map(\.layer)).sorted()
        let remap = Dictionary(uniqueKeysWithValues: usedLayers.enumerated().map { ($0.element, $0.offset) })
        return placed.map { effect in
            var updated = effect
            updated.layer = remap[effect.layer] ?? 0
            return updated
        }
    }

    mutating func setSingleTrim(start: Double, end: Double, totalDuration: Double) {
        let total = max(totalDuration, 0)
        guard total > 0 else {
            trimStart = 0
            trimEnd = 0
            timelineClips = []
            return
        }

        let safeStart = min(max(start, 0), max(total - Self.minimumClipDuration, 0))
        let safeEnd = min(max(end, safeStart + Self.minimumClipDuration), total)
        timelineClips = [VideoDemoTimelineClip(sourceStart: safeStart, sourceEnd: safeEnd)]
        syncTrimToTimeline(totalDuration: total)
    }

    mutating func syncTrimToTimeline(totalDuration: Double) {
        let clips = normalizedTimelineClips(totalDuration: totalDuration)
        guard let first = clips.first, let last = clips.last else {
            trimStart = 0
            trimEnd = 0
            return
        }
        trimStart = first.sourceStart
        trimEnd = last.sourceEnd
    }

    // MARK: Geometry

    /// Logical canvas (short side 1080). Top-left origin everywhere in the
    /// model; the renderer flips at its boundary.
    func canvasSize() -> CGSize {
        if aspectPreset == .custom {
            // Custom…: its own shape (Auto until one is chosen).
            let custom = Self.keptCustomAspect(customAspect)
            return aspectPreset.canvasSize(sourceSize: custom.map { CGSize(width: 1080 * $0, height: 1080) } ?? croppedSourceSize)
        }
        if aspectPreset == .source, let whole = splitVideoAspect, whole > 0.1, webcam.visible, webcam.effectiveLayout == .split {
            // Recorded as the screen's part of a split video: Auto is the whole video.
            return aspectPreset.canvasSize(sourceSize: CGSize(width: 1080 * whole, height: 1080))
        }
        return aspectPreset.canvasSize(sourceSize: croppedSourceSize)
    }

    /// Custom…'s shape, kept between 1:8 and 8:1 (nil: none chosen).
    static func keptCustomAspect(_ aspect: Double?) -> Double? {
        guard let aspect, aspect.isFinite, aspect > 0 else { return nil }
        return min(max(aspect, 1.0 / 8), 8)
    }

    /// The ratio's name: "16:9", or Custom's own shape, like "2.39:1".
    func title(of preset: AspectPreset) -> String {
        guard preset == .custom, let custom = Self.keptCustomAspect(customAspect) else { return preset.title }
        return VideoEditorFormat.ratio(CGFloat(custom))
    }

    var aspectTitle: String { title(of: aspectPreset) }

    /// The output is narrower than the recording (9:16, 4:5, 1:1 of a wide
    /// screen): reframing can fill it.
    var canReframe: Bool {
        var landscape = self
        landscape.aspectPreset = .source
        let output = canvasSize()
        let scene = landscape.canvasSize()
        return VideoReframe.windowFraction(outputAspect: output.width / max(output.height, 1), sceneAspect: scene.width / max(scene.height, 1)) != nil
    }

    var reframeActive: Bool { reframe && canReframe }

    /// What gets rendered before the reframing window crops it: the same
    /// project at the recording's own shape.
    func reframeScene() -> VideoDemoProject {
        var scene = self
        scene.aspectPreset = .source
        return scene
    }

    /// Where the recording sits on the canvas when the camera is at rest.
    /// Always centered, so it is the same rect in top-left and bottom-left
    /// coordinates.
    func stageRect(in canvasSize: CGSize) -> CGRect {
        let margin = min(canvasSize.width, canvasSize.height) * CGFloat(min(max(padding, Self.paddingRange.lowerBound), Self.paddingRange.upperBound))
        let available = CGRect(origin: .zero, size: canvasSize).insetBy(dx: margin, dy: margin)
        guard available.width > 1, available.height > 1 else { return CGRect(origin: .zero, size: canvasSize) }
        let cropped = croppedSourceSize
        let sourceRatio = cropped.width > 0 && cropped.height > 0 ? cropped.width / cropped.height : 16 / 9
        let availableRatio = available.width / max(available.height, 1)

        let fitted: CGSize
        if sourceRatio > availableRatio {
            fitted = CGSize(width: available.width, height: available.width / sourceRatio)
        } else {
            fitted = CGSize(width: available.height * sourceRatio, height: available.height)
        }
        return CGRect(
            x: available.midX - fitted.width / 2,
            y: available.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// Canvas point (top-left origin) for a point on the RECORDING
    /// (source-normalized) — the crop is applied.
    func canvasPoint(forVideoPoint point: CGPoint, canvasSize: CGSize) -> CGPoint {
        let stage = stageRect(in: canvasSize)
        let inCrop = crop.normalized.map(point)
        return CGPoint(x: stage.minX + stage.width * inCrop.x, y: stage.minY + stage.height * inCrop.y)
    }

    // MARK: Style

    var style: VideoStylePreset {
        VideoStylePreset(
            aspectPreset: aspectPreset,
            background: background,
            backgroundBlur: backgroundBlur,
            padding: padding,
            cornerRadius: cornerRadius,
            shadow: shadow,
            outline: outline,
            zoomSpeed: zoomSpeed,
            defaultZoomScale: defaultZoomScale,
            motionBlur: motionBlur,
            cursor: cursor,
            webcam: webcam,
            captionStyle: captionStyle,
            keystrokeStyle: keystrokeStyle,
            titleFont: cards.font,
            autoZoom: autoZoom,
            shadowStyle: shadowStyle,
            loupeStyle: loupeStyle,
            customAspect: aspectPreset == .custom ? customAspect : nil
        )
    }

    /// Applies a saved look. The pointer's visibility is a per-recording
    /// fact (was it captured?) so it is left alone.
    mutating func apply(style: VideoStylePreset) {
        aspectPreset = style.aspectPreset
        if style.aspectPreset == .custom, let custom = style.customAspect { customAspect = custom }
        background = style.background
        backgroundBlur = style.backgroundBlur
        padding = style.padding
        cornerRadius = style.cornerRadius
        shadow = style.shadow
        shadowStyle = style.shadowStyle
        outline = style.outline
        zoomSpeed = style.zoomSpeed
        defaultZoomScale = style.defaultZoomScale
        motionBlur = style.motionBlur
        let visible = cursor.visible
        cursor = style.cursor
        cursor.visible = visible
        webcam = style.webcam
        captionStyle = style.captionStyle
        keystrokeStyle = style.keystrokeStyle
        cards.font = style.titleFont
        // A preset with a loupe look restyles the loupes (magnification
        // stays each loupe's own).
        if let loupe = style.loupeStyle {
            loupeStyle = loupe
            for index in zoomRegions.indices where zoomRegions[index].loupe != nil {
                zoomRegions[index].loupe = loupe
            }
        }
    }
}

// MARK: - Codable (versioned, with legacy migration)

extension VideoDemoProject {
    private enum CodingKeys: String, CodingKey {
        case version, id, sourcePath, createdAt, sourceWidth, sourceHeight, trimStart, trimEnd, timelineClips
        case aspectPreset, background, backgroundBlur, padding, cornerRadius, shadow, shadowStyle, outline
        case zoomRegions, zoomSpeed, defaultZoomScale, motionBlur
        case overlayEffects, cursorSamples, clickEvents, nativeCursorVisible, cursor, audio
        case webcam, cameraLayouts, importedCamera, splitVideoAspect, customAspect, trackStates, autoZoom, reframe, captions, transcriptLanguage, captionStyle, keystrokes, keystrokeStyle, crop
        case cards, music, audioTracks, clickSounds, transitions, captionTracks, sources, imageOverlayEffects, markers
        case textCursor, keyPresses, loupeStyle, faceTracking, carriedVoices, speakerNotes
        case ratioVersions, ratioShared, ratioBase, previousRatio, reframeFollowsZooms, mediaBin, layerTracks
        // Legacy (v1) keys
        case backgroundPreset, customBackgroundPath, stageInset, shadowStrength, zoomKeyframes
        case showCursorOverlay, enlargeCursor, showClickRipple, smoothCursor, cursorScale, clickSpotlight, cursorMotionBlur
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceWidth = try container.decode(Double.self, forKey: .sourceWidth)
        sourceHeight = try container.decode(Double.self, forKey: .sourceHeight)
        trimStart = try container.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0
        trimEnd = try container.decodeIfPresent(Double.self, forKey: .trimEnd) ?? 0
        timelineClips = try container.decodeIfPresent([VideoDemoTimelineClip].self, forKey: .timelineClips) ?? []
        // Image annotations are stored apart so older versions still open
        // the draft (they just don't see the pictures).
        overlayEffects = Self.normalizedEffectLayers(
            (try container.decodeIfPresent([VideoDemoOverlayEffect].self, forKey: .overlayEffects) ?? [])
                + ((try? container.decodeIfPresent([VideoDemoOverlayEffect].self, forKey: .imageOverlayEffects)) ?? [])
        )
        cursorSamples = try container.decodeIfPresent([VideoDemoCursorSample].self, forKey: .cursorSamples) ?? []
        clickEvents = try container.decodeIfPresent([VideoDemoClickEvent].self, forKey: .clickEvents) ?? []
        nativeCursorVisible = try container.decodeIfPresent(Bool.self, forKey: .nativeCursorVisible) ?? true
        version = Self.currentVersion
        webcam = (try? container.decode(VideoWebcamSettings.self, forKey: .webcam)) ?? VideoWebcamSettings()
        cameraLayouts = (try? container.decode([VideoCameraLayoutRegion].self, forKey: .cameraLayouts)) ?? []
        importedCamera = try? container.decodeIfPresent(VideoImportedCamera.self, forKey: .importedCamera)
        splitVideoAspect = (try? container.decodeIfPresent(Double.self, forKey: .splitVideoAspect)).flatMap { $0 }
        customAspect = (try? container.decodeIfPresent(Double.self, forKey: .customAspect)).flatMap { $0 }
        trackStates = (try? container.decodeIfPresent([String: VideoTrackState].self, forKey: .trackStates)).flatMap { $0 } ?? [:]
        autoZoom = (try? container.decodeIfPresent(Bool.self, forKey: .autoZoom)) ?? true
        reframe = try container.decodeIfPresent(Bool.self, forKey: .reframe) ?? false
        captions = (try? container.decode([VideoCaptionLine].self, forKey: .captions)) ?? []
        transcriptLanguage = try? container.decodeIfPresent(String.self, forKey: .transcriptLanguage)
        captionStyle = (try? container.decode(VideoCaptionStyle.self, forKey: .captionStyle)) ?? VideoCaptionStyle()
        keystrokes = (try? container.decode([VideoKeystrokeEvent].self, forKey: .keystrokes)) ?? []
        keystrokeStyle = (try? container.decode(VideoKeystrokeStyle.self, forKey: .keystrokeStyle)) ?? VideoKeystrokeStyle()
        crop = (try? container.decode(VideoCropRect.self, forKey: .crop))?.normalized ?? .full
        cards = (try? container.decode(VideoTitleCards.self, forKey: .cards)) ?? VideoTitleCards()
        music = try? container.decodeIfPresent(VideoMusicTrack.self, forKey: .music)
        audioTracks = (try? container.decode([VideoExternalAudioTrack].self, forKey: .audioTracks)) ?? []
        clickSounds = (try? container.decode(VideoClickSoundSettings.self, forKey: .clickSounds)) ?? VideoClickSoundSettings()
        transitions = (try? container.decode(VideoTransitionSettings.self, forKey: .transitions)) ?? VideoTransitionSettings()
        captionTracks = (try? container.decode(VideoCaptionTracks.self, forKey: .captionTracks)) ?? VideoCaptionTracks()
        sources = (try? container.decode([VideoProjectSource].self, forKey: .sources)) ?? []
        markers = (try? container.decode([VideoMarker].self, forKey: .markers)) ?? []
        textCursor = (try? container.decode([VideoTextCursorSample].self, forKey: .textCursor)) ?? []
        keyPresses = (try? container.decode([Double].self, forKey: .keyPresses)) ?? []
        loupeStyle = try? container.decodeIfPresent(VideoLoupeStyle.self, forKey: .loupeStyle)
        faceTracking = try? container.decodeIfPresent(VideoFaceTracking.self, forKey: .faceTracking)
        carriedVoices = (try? container.decodeIfPresent([VideoCarriedVoice].self, forKey: .carriedVoices)) ?? []
        speakerNotes = try? container.decodeIfPresent(String.self, forKey: .speakerNotes)
        ratioVersions = (try? container.decodeIfPresent([String: VideoRatioVersion].self, forKey: .ratioVersions)) ?? [:]
        ratioShared = try? container.decodeIfPresent(VideoRatioVersion.self, forKey: .ratioShared)
        ratioBase = try? container.decodeIfPresent(AspectPreset.self, forKey: .ratioBase)
        previousRatio = try? container.decodeIfPresent(AspectPreset.self, forKey: .previousRatio)
        reframeFollowsZooms = (try? container.decodeIfPresent(Bool.self, forKey: .reframeFollowsZooms)) ?? false
        mediaBin = (try? container.decodeIfPresent(VideoMediaBin.self, forKey: .mediaBin)).flatMap { $0 }
        layerTracks = (try? container.decodeIfPresent([VideoLayerTrack].self, forKey: .layerTracks)).flatMap { $0 } ?? []

        let storedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        if storedVersion >= 2 {
            aspectPreset = (try? container.decode(AspectPreset.self, forKey: .aspectPreset)) ?? .widescreen
            background = (try? container.decode(VideoBackground.self, forKey: .background)) ?? VideoBackgroundCatalog.defaultBackground
            backgroundBlur = try container.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 0
            padding = try container.decodeIfPresent(Double.self, forKey: .padding) ?? 0.085
            cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 18
            shadow = try container.decodeIfPresent(Double.self, forKey: .shadow) ?? 0.55
            shadowStyle = try? container.decodeIfPresent(VideoShadowStyle.self, forKey: .shadowStyle)
            outline = try container.decodeIfPresent(Bool.self, forKey: .outline) ?? true
            zoomRegions = try container.decodeIfPresent([VideoZoomRegion].self, forKey: .zoomRegions) ?? []
            zoomSpeed = (try? container.decode(VideoZoomSpeed.self, forKey: .zoomSpeed)) ?? .smooth
            defaultZoomScale = try container.decodeIfPresent(Double.self, forKey: .defaultZoomScale) ?? 2
            motionBlur = try container.decodeIfPresent(Double.self, forKey: .motionBlur) ?? 0.5
            cursor = try container.decodeIfPresent(VideoCursorSettings.self, forKey: .cursor) ?? VideoCursorSettings()
            audio = try container.decodeIfPresent(VideoAudioSettings.self, forKey: .audio) ?? VideoAudioSettings()
            return
        }

        // v1 drafts: keyframe camera, preset backgrounds, flat cursor flags.
        let legacyAspect = try container.decodeIfPresent(String.self, forKey: .aspectPreset) ?? "widescreen"
        aspectPreset = AspectPreset(rawValue: legacyAspect) ?? .widescreen
        let legacyBackground = try container.decodeIfPresent(String.self, forKey: .backgroundPreset) ?? "graphite"
        let customPath = try container.decodeIfPresent(String.self, forKey: .customBackgroundPath) ?? ""
        background = customPath.isEmpty ? .gradient(legacyBackground) : .image(customPath)
        let legacyBlur = try container.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 0
        backgroundBlur = min(max(legacyBlur / 18, 0), 1)
        let legacyInset = try container.decodeIfPresent(Double.self, forKey: .stageInset) ?? 0.085
        padding = legacyAspect == "source" ? 0 : legacyInset
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 18
        let legacyShadow = try container.decodeIfPresent(Double.self, forKey: .shadowStrength) ?? 0.42
        shadow = min(max(legacyShadow / 0.8, 0), 1)
        outline = true
        let keyframes = try container.decodeIfPresent([VideoDemoZoomKeyframe].self, forKey: .zoomKeyframes) ?? []
        zoomRegions = Self.migrateZoomKeyframes(keyframes)
        zoomSpeed = .smooth
        defaultZoomScale = 2
        motionBlur = 0.5

        var cursor = VideoCursorSettings()
        cursor.visible = try container.decodeIfPresent(Bool.self, forKey: .showCursorOverlay) ?? !nativeCursorVisible
        if let scale = try container.decodeIfPresent(Double.self, forKey: .cursorScale) {
            cursor.size = min(max(scale, VideoCursorSettings.sizeRange.lowerBound), VideoCursorSettings.sizeRange.upperBound)
        }
        let smooth = try container.decodeIfPresent(Bool.self, forKey: .smoothCursor) ?? true
        cursor.smoothing = smooth ? .smooth : .off
        let ripple = try container.decodeIfPresent(Bool.self, forKey: .showClickRipple) ?? true
        cursor.clickEffect = ripple ? .ripple : .none
        cursor.motionBlur = try container.decodeIfPresent(Bool.self, forKey: .cursorMotionBlur) ?? false
        self.cursor = cursor
        audio = VideoAudioSettings()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(sourceWidth, forKey: .sourceWidth)
        try container.encode(sourceHeight, forKey: .sourceHeight)
        try container.encode(trimStart, forKey: .trimStart)
        try container.encode(trimEnd, forKey: .trimEnd)
        try container.encode(timelineClips, forKey: .timelineClips)
        try container.encode(aspectPreset, forKey: .aspectPreset)
        try container.encode(background, forKey: .background)
        try container.encode(backgroundBlur, forKey: .backgroundBlur)
        try container.encode(padding, forKey: .padding)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(shadow, forKey: .shadow)
        try container.encodeIfPresent(shadowStyle, forKey: .shadowStyle)
        try container.encode(outline, forKey: .outline)
        try container.encode(zoomRegions, forKey: .zoomRegions)
        try container.encode(zoomSpeed, forKey: .zoomSpeed)
        try container.encode(defaultZoomScale, forKey: .defaultZoomScale)
        try container.encode(motionBlur, forKey: .motionBlur)
        try container.encode(overlayEffects.filter { $0.kind != .image }, forKey: .overlayEffects)
        let images = overlayEffects.filter { $0.kind == .image }
        if !images.isEmpty { try container.encode(images, forKey: .imageOverlayEffects) }
        if !markers.isEmpty { try container.encode(markers, forKey: .markers) }
        if !textCursor.isEmpty { try container.encode(textCursor, forKey: .textCursor) }
        if !keyPresses.isEmpty { try container.encode(keyPresses, forKey: .keyPresses) }
        try container.encodeIfPresent(loupeStyle, forKey: .loupeStyle)
        try container.encodeIfPresent(faceTracking, forKey: .faceTracking)
        if !carriedVoices.isEmpty { try container.encode(carriedVoices, forKey: .carriedVoices) }
        if let speakerNotes, !speakerNotes.isEmpty { try container.encode(speakerNotes, forKey: .speakerNotes) }
        // Only once used: older files stay byte for byte as they were.
        if !ratioVersions.isEmpty { try container.encode(ratioVersions, forKey: .ratioVersions) }
        try container.encodeIfPresent(ratioShared, forKey: .ratioShared)
        try container.encodeIfPresent(ratioBase, forKey: .ratioBase)
        try container.encodeIfPresent(previousRatio, forKey: .previousRatio)
        if reframeFollowsZooms { try container.encode(true, forKey: .reframeFollowsZooms) }
        if let mediaBin, !mediaBin.isEmpty { try container.encode(mediaBin, forKey: .mediaBin) }
        if !layerTracks.isEmpty { try container.encode(layerTracks, forKey: .layerTracks) }
        try container.encode(cursorSamples, forKey: .cursorSamples)
        try container.encode(clickEvents, forKey: .clickEvents)
        try container.encode(nativeCursorVisible, forKey: .nativeCursorVisible)
        try container.encode(cursor, forKey: .cursor)
        try container.encode(audio, forKey: .audio)
        try container.encode(webcam, forKey: .webcam)
        try container.encode(cameraLayouts, forKey: .cameraLayouts)
        try container.encodeIfPresent(importedCamera, forKey: .importedCamera)
        try container.encodeIfPresent(splitVideoAspect, forKey: .splitVideoAspect)
        try container.encodeIfPresent(customAspect, forKey: .customAspect)
        if !trackStates.isEmpty { try container.encode(trackStates, forKey: .trackStates) }
        try container.encode(autoZoom, forKey: .autoZoom)
        try container.encode(reframe, forKey: .reframe)
        try container.encode(captions, forKey: .captions)
        try container.encodeIfPresent(transcriptLanguage, forKey: .transcriptLanguage)
        try container.encode(captionStyle, forKey: .captionStyle)
        try container.encode(keystrokes, forKey: .keystrokes)
        try container.encode(keystrokeStyle, forKey: .keystrokeStyle)
        try container.encode(crop, forKey: .crop)
        try container.encode(cards, forKey: .cards)
        try container.encodeIfPresent(music, forKey: .music)
        if !audioTracks.isEmpty { try container.encode(audioTracks, forKey: .audioTracks) }
        try container.encode(clickSounds, forKey: .clickSounds)
        try container.encode(transitions, forKey: .transitions)
        try container.encode(captionTracks, forKey: .captionTracks)
        if !sources.isEmpty { try container.encode(sources, forKey: .sources) }
    }

    /// Converts the old keyframe camera into regions: each run of zoomed
    /// keyframes holding one focus becomes a region spanning its ramp in
    /// and ramp out; a pan between zoomed focuses splits at the midpoint.
    static func migrateZoomKeyframes(_ keyframes: [VideoDemoZoomKeyframe]) -> [VideoZoomRegion] {
        let sorted = keyframes.sorted { $0.time < $1.time }
        var regions: [VideoZoomRegion] = []
        var index = 0
        while index < sorted.count {
            let keyframe = sorted[index]
            guard keyframe.scale > 1.02 else {
                index += 1
                continue
            }
            // Extend the run while the camera holds the same shot.
            var last = index
            while last + 1 < sorted.count,
                  sorted[last + 1].scale > 1.02,
                  abs(sorted[last + 1].focusX - keyframe.focusX) < 0.02,
                  abs(sorted[last + 1].focusY - keyframe.focusY) < 0.02,
                  abs(sorted[last + 1].scale - keyframe.scale) < 0.02 {
                last += 1
            }
            let previous = index > 0 ? sorted[index - 1] : nil
            let next = last + 1 < sorted.count ? sorted[last + 1] : nil
            let start: Double
            if let previous {
                start = previous.scale <= 1.02 ? previous.time : (previous.time + keyframe.time) / 2
            } else {
                start = max(keyframe.time - 0.8, 0)
            }
            let end: Double
            if let next {
                end = next.scale <= 1.02 ? next.time : (sorted[last].time + next.time) / 2
            } else {
                end = sorted[last].time + 1.5
            }
            regions.append(VideoZoomRegion(
                start: start,
                end: max(end, start + VideoZoomRegion.minimumDuration),
                scale: keyframe.scale,
                followsCursor: false,
                focusX: keyframe.focusX,
                focusY: keyframe.focusY,
                isAuto: false
            ))
            index = last + 1
        }
        return regions
    }
}

// MARK: - Style presets

/// Everything about the look of a video that isn't tied to one recording —
/// saved as the default for new recordings.
struct VideoStylePreset: Codable, Equatable {
    var aspectPreset: VideoDemoProject.AspectPreset
    var background: VideoBackground
    var backgroundBlur: Double
    var padding: Double
    var cornerRadius: Double
    var shadow: Double
    var outline: Bool
    var zoomSpeed: VideoZoomSpeed
    var defaultZoomScale: Double
    var motionBlur: Double
    var cursor: VideoCursorSettings
    var webcam: VideoWebcamSettings = VideoWebcamSettings()
    var captionStyle: VideoCaptionStyle = VideoCaptionStyle()
    var keystrokeStyle: VideoKeystrokeStyle = VideoKeystrokeStyle()
    /// The title cards' typeface (captions and keys carry theirs).
    var titleFont: VideoFontChoice?
    /// Auto-zoom on clicks, on or off (nil: a preset saved before this
    /// existed, which leaves auto-zoom as it is).
    var autoZoom: Bool? = nil
    /// The shadow fine-tuned (nil: the classic shadow from `shadow`).
    var shadowStyle: VideoShadowStyle? = nil
    /// The loupe look (nil: saved before loupes, or none was styled).
    var loupeStyle: VideoLoupeStyle? = nil
    /// Custom…'s shape, when that's the ratio.
    var customAspect: Double? = nil

    /// The built-in LF Studios look.
    static let factory = VideoStylePreset(
        aspectPreset: .widescreen,
        background: VideoBackgroundCatalog.defaultBackground,
        backgroundBlur: 0,
        padding: 0.085,
        cornerRadius: 18,
        shadow: 0.55,
        outline: true,
        zoomSpeed: .smooth,
        defaultZoomScale: 2,
        motionBlur: 0.5,
        cursor: VideoCursorSettings(),
        webcam: VideoWebcamSettings(),
        captionStyle: VideoCaptionStyle(),
        keystrokeStyle: VideoKeystrokeStyle()
    )

    /// The preset new recordings start from (VideoStylePresets.swift).
    static var savedDefaultPreset: VideoNamedStylePreset? {
        VideoStylePresetStore.load(root: VideoStorageLocation.root).defaultPreset
    }

    static var savedDefault: VideoStylePreset? { savedDefaultPreset?.style }

    /// This look for new recordings: the default preset takes it (one is
    /// made, "My Look", when there's none); nil: the built-in look again.
    static func saveAsDefault(_ preset: VideoStylePreset?) {
        let root = VideoStorageLocation.root
        var library = VideoStylePresetStore.load(root: root)
        if let preset {
            if let id = library.defaultID {
                library.update(id, with: preset)
            } else {
                let mine = library.add(name: L("My Look"), style: preset, includesAspectRatio: true)
                library.setDefault(mine.id)
            }
        } else {
            library.setDefault(nil)
        }
        _ = VideoStylePresetStore.save(library, root: root)
    }
}

extension VideoStylePreset {
    private enum CodingKeys: String, CodingKey {
        case aspectPreset, background, backgroundBlur, padding, cornerRadius, shadow, outline
        case zoomSpeed, defaultZoomScale, motionBlur, cursor, webcam, captionStyle, keystrokeStyle, titleFont, autoZoom, shadowStyle, loupeStyle, customAspect
    }

    /// Looks saved before a field existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let f = VideoStylePreset.factory
        aspectPreset = (try? c.decode(VideoDemoProject.AspectPreset.self, forKey: .aspectPreset)) ?? f.aspectPreset
        background = (try? c.decode(VideoBackground.self, forKey: .background)) ?? f.background
        backgroundBlur = try c.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? f.backgroundBlur
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? f.padding
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? f.cornerRadius
        shadow = try c.decodeIfPresent(Double.self, forKey: .shadow) ?? f.shadow
        outline = try c.decodeIfPresent(Bool.self, forKey: .outline) ?? f.outline
        zoomSpeed = (try? c.decode(VideoZoomSpeed.self, forKey: .zoomSpeed)) ?? f.zoomSpeed
        defaultZoomScale = try c.decodeIfPresent(Double.self, forKey: .defaultZoomScale) ?? f.defaultZoomScale
        motionBlur = try c.decodeIfPresent(Double.self, forKey: .motionBlur) ?? f.motionBlur
        cursor = (try? c.decode(VideoCursorSettings.self, forKey: .cursor)) ?? f.cursor
        webcam = (try? c.decode(VideoWebcamSettings.self, forKey: .webcam)) ?? f.webcam
        captionStyle = (try? c.decode(VideoCaptionStyle.self, forKey: .captionStyle)) ?? f.captionStyle
        keystrokeStyle = (try? c.decode(VideoKeystrokeStyle.self, forKey: .keystrokeStyle)) ?? f.keystrokeStyle
        titleFont = try? c.decodeIfPresent(VideoFontChoice.self, forKey: .titleFont)
        autoZoom = try? c.decodeIfPresent(Bool.self, forKey: .autoZoom)
        shadowStyle = try? c.decodeIfPresent(VideoShadowStyle.self, forKey: .shadowStyle)
        loupeStyle = try? c.decodeIfPresent(VideoLoupeStyle.self, forKey: .loupeStyle)
        customAspect = (try? c.decodeIfPresent(Double.self, forKey: .customAspect)).flatMap { $0 }
    }
}
