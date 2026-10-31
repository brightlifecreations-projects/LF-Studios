import CoreImage
import SwiftUI

// MARK: - In, Out and Combo animations (1.15.0)

/// How an item above the main track comes in, goes out, or moves the whole
/// time it shows. Each starts off and is picked in Properties ▸ Animation.
struct VideoItemAnimation: Codable, Equatable {
    var inPreset: VideoAnimationPreset?
    var inLength = 0.5
    var outPreset: VideoAnimationPreset?
    var outLength = 0.5
    var combo: VideoComboPreset?
    /// Seconds per cycle.
    var comboLength = 1.0

    var isEmpty: Bool { inPreset == nil && outPreset == nil && combo == nil }

    static let lengthRange: ClosedRange<Double> = 0.1...5
}

enum VideoAnimationPreset: String, Codable, CaseIterable, Identifiable {
    case fade, zoomIn, zoomOut, slideLeft, slideRight, slideUp, slideDown, spin, pop, blur

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fade: return L("Fade")
        case .zoomIn: return L("Zoom in")
        case .zoomOut: return L("Zoom out")
        case .slideLeft: return L("Slide left")
        case .slideRight: return L("Slide right")
        case .slideUp: return L("Slide up")
        case .slideDown: return L("Slide down")
        case .spin: return L("Spin")
        case .pop: return L("Pop")
        case .blur: return L("Blur")
        }
    }
    var symbol: String {
        switch self {
        case .fade: return "circle.lefthalf.filled"
        case .zoomIn: return "arrow.up.left.and.arrow.down.right"
        case .zoomOut: return "arrow.down.right.and.arrow.up.left"
        case .slideLeft: return "arrow.left"
        case .slideRight: return "arrow.right"
        case .slideUp: return "arrow.up"
        case .slideDown: return "arrow.down"
        case .spin: return "arrow.clockwise"
        case .pop: return "burst"
        case .blur: return "drop"
        }
    }

    /// The change at `p` (0: fully away, 1: in place).
    func change(_ p: Double) -> VideoAnimationChange {
        let e = VideoEasing.easeOut.apply(p)
        var c = VideoAnimationChange()
        switch self {
        case .fade: c.opacity = e
        case .zoomIn: c.scale = 0.5 + 0.5 * e; c.opacity = min(p * 3, 1)
        case .zoomOut: c.scale = 1.6 - 0.6 * e; c.opacity = min(p * 3, 1)
        case .slideLeft: c.dx = 0.3 * (1 - e); c.opacity = min(p * 2, 1)
        case .slideRight: c.dx = -0.3 * (1 - e); c.opacity = min(p * 2, 1)
        case .slideUp: c.dy = 0.3 * (1 - e); c.opacity = min(p * 2, 1)
        case .slideDown: c.dy = -0.3 * (1 - e); c.opacity = min(p * 2, 1)
        case .spin: c.rotation = -180 * (1 - e); c.scale = 0.3 + 0.7 * e; c.opacity = min(p * 2, 1)
        case .pop:
            // A little past full size, then back.
            let back = p < 0.7 ? VideoEasing.easeOut.apply(p / 0.7) * 1.12 : 1.12 - 0.12 * VideoEasing.easeInOut.apply((p - 0.7) / 0.3)
            c.scale = max(back, 0.01); c.opacity = min(p * 4, 1)
        case .blur: c.blur = 30 * (1 - e); c.opacity = min(p * 2, 1)
        }
        return c
    }
}

enum VideoComboPreset: String, Codable, CaseIterable, Identifiable {
    case wobble, pulse, bounce, swing, shake

    var id: String { rawValue }
    var title: String {
        switch self {
        case .wobble: return L("Wobble")
        case .pulse: return L("Pulse")
        case .bounce: return L("Bounce")
        case .swing: return L("Swing")
        case .shake: return L("Shake")
        }
    }
    var symbol: String {
        switch self {
        case .wobble: return "water.waves"
        case .pulse: return "heart"
        case .bounce: return "arrow.up.arrow.down"
        case .swing: return "metronome"
        case .shake: return "waveform.path"
        }
    }

    /// The change `phase` (0…1) through a cycle.
    func change(_ phase: Double) -> VideoAnimationChange {
        let wave = sin(phase * 2 * .pi)
        var c = VideoAnimationChange()
        switch self {
        case .wobble: c.rotation = 6 * wave; c.scale = 1 + 0.03 * cos(phase * 4 * .pi)
        case .pulse: c.scale = 1 + 0.08 * (0.5 - 0.5 * cos(phase * 2 * .pi))
        case .bounce: c.dy = -0.04 * abs(wave)
        case .swing: c.rotation = 12 * wave
        case .shake: c.dx = 0.012 * sin(phase * 14 * .pi); c.dy = 0.008 * sin(phase * 10 * .pi + 1)
        }
        return c
    }
}

/// What an animation does at one moment, on top of the item as it is.
struct VideoAnimationChange: Equatable {
    var opacity = 1.0
    var scale = 1.0
    /// Shares of the frame's width and height.
    var dx = 0.0
    var dy = 0.0
    var rotation = 0.0
    /// Pixels at 1080 high.
    var blur = 0.0

    static func * (a: Self, b: Self) -> Self {
        Self(opacity: a.opacity * b.opacity, scale: a.scale * b.scale, dx: a.dx + b.dx, dy: a.dy + b.dy, rotation: a.rotation + b.rotation, blur: a.blur + b.blur)
    }
}

extension VideoItemAnimation {
    /// The change at `local` seconds into an item `length` long.
    func change(at local: Double, length: Double) -> VideoAnimationChange {
        var total = VideoAnimationChange()
        let inLength = min(self.inLength, length)
        let outLength = min(self.outLength, length)
        if let inPreset, local < inLength {
            total = total * inPreset.change(local / max(inLength, 0.001))
        }
        if let outPreset, local > length - outLength {
            total = total * outPreset.change((length - local) / max(outLength, 0.001))
        }
        if let combo {
            let period = max(comboLength, 0.1)
            total = total * combo.change(local.truncatingRemainder(dividingBy: period) / period)
        }
        return total
    }
}

extension VideoLayerItem {
    /// As drawn at timeline `time`: keys and animations applied, and how
    /// much it's blurred by an animation.
    func shown(at time: Double) -> (item: VideoLayerItem, blur: Double) {
        var item = resolved(at: time)
        guard let animation, !animation.isEmpty else { return (item, 0) }
        let c = animation.change(at: time - at, length: length)
        item.opacity *= c.opacity
        item.width *= c.scale
        item.x += c.dx
        item.y += c.dy
        item.rotation += c.rotation
        return (item, c.blur)
    }
}

// MARK: - Properties ▸ Animation

/// In, Out, Combo: a grid of presets (None first) and a length.
struct VideoAnimationSection: View {
    @ObservedObject var model: VideoEditorModel
    let item: VideoLayerItem
    @State private var tab = 0

    private var animation: VideoItemAnimation { item.animation ?? VideoItemAnimation() }

    var body: some View {
        VideoInspectorSection(L("Animation")) {
            VideoSegmented(options: [(0, L("In")), (1, L("Out")), (2, L("Combo"))], selection: $tab)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                preset(nil, title: L("None"), symbol: "nosign")
                if tab == 2 {
                    ForEach(VideoComboPreset.allCases) { combo in preset(combo.rawValue, title: combo.title, symbol: combo.symbol) }
                } else {
                    ForEach(VideoAnimationPreset.allCases) { p in preset(p.rawValue, title: p.title, symbol: p.symbol) }
                }
            }
            if let length = currentLength {
                VideoSliderRow(title: L("Length"), value: Binding(get: { length }, set: { value in
                    var next = animation
                    switch tab {
                    case 0: next.inLength = value
                    case 1: next.outLength = value
                    default: next.comboLength = value
                    }
                    apply(next)
                }), range: VideoItemAnimation.lengthRange, defaultValue: tab == 2 ? 1 : 0.5, format: { VideoEditorModel.format($0) },
                detail: tab == 2 ? L("One cycle") : nil, onEditingEnded: { model.endGesture() })
            }
        }
    }

    private var currentLength: Double? {
        switch tab {
        case 0: return animation.inPreset == nil ? nil : animation.inLength
        case 1: return animation.outPreset == nil ? nil : animation.outLength
        default: return animation.combo == nil ? nil : animation.comboLength
        }
    }

    private func selected(_ raw: String?) -> Bool {
        switch tab {
        case 0: return animation.inPreset?.rawValue == raw
        case 1: return animation.outPreset?.rawValue == raw
        default: return animation.combo?.rawValue == raw
        }
    }

    private func preset(_ raw: String?, title: String, symbol: String) -> some View {
        let on = selected(raw)
        return Button {
            var next = animation
            switch tab {
            case 0: next.inPreset = raw.flatMap(VideoAnimationPreset.init(rawValue:))
            case 1: next.outPreset = raw.flatMap(VideoAnimationPreset.init(rawValue:))
            default: next.combo = raw.flatMap(VideoComboPreset.init(rawValue:))
            }
            apply(next)
            model.endGesture()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 9.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(on ? VideoEditorTheme.textPrimary : VideoEditorTheme.textSecondary)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? VideoEditorTheme.layer.opacity(0.25) : VideoEditorTheme.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func apply(_ next: VideoItemAnimation) {
        model.selection = .layer(item.id)
        model.perform(.edit(.setAnimation(next)))
    }
}
