import AppKit
import CoreImage
import SwiftUI

/// The frame shadow, fine-tuned (Style ▸ Shadow ▸ Fine-tune). A project or
/// preset without one has the classic shadow, set by the Shadow slider
/// alone and drawn exactly as before.
struct VideoShadowStyle: Codable, Equatable {
    /// The direction the shadow falls, in degrees clockwise from the right:
    /// 90 is straight down.
    var angle: Double = 90
    /// How far it falls, in canvas pixels on the 1080 reference.
    var distance: Double
    /// How soft its edge is (the blur), on the 1080 reference.
    var softness: Double
    /// 0…1
    var opacity: Double
    var color = VideoRGBA(0, 0, 0)
    /// A soft inner edge just inside the frame instead of a drop shadow.
    var inset = false

    static let angleRange: ClosedRange<Double> = 0...360
    static let distanceRange: ClosedRange<Double> = 0...80
    static let softnessRange: ClosedRange<Double> = 0...120
    static let opacityRange: ClosedRange<Double> = 0...1

    /// The fine-tuned values that look like the classic shadow at this
    /// strength, so switching to them changes nothing.
    static func matching(strength: Double) -> VideoShadowStyle {
        let s = min(max(strength, 0), 1)
        // The classic shadow draws nothing below 0.01.
        return VideoShadowStyle(distance: 6 + 16 * s, softness: 14 + 36 * s, opacity: s > 0.01 ? min(0.28 + 0.5 * s, 1) : 0)
    }

    /// Whether anything shows.
    var isVisible: Bool { opacity > 0.005 && color.a > 0.005 }

    /// The offset on the canvas (y down), on the 1080 reference.
    var offset: CGVector {
        let radians = angle * .pi / 180
        return CGVector(dx: cos(radians) * distance, dy: sin(radians) * distance)
    }

    func clamped() -> VideoShadowStyle {
        var style = self
        style.angle = angle.truncatingRemainder(dividingBy: 360)
        if style.angle < 0 { style.angle += 360 }
        style.distance = min(max(distance, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
        style.softness = min(max(softness, Self.softnessRange.lowerBound), Self.softnessRange.upperBound)
        style.opacity = min(max(opacity, 0), 1)
        return style
    }
}

extension VideoDemoProject {
    /// The fine-tuned shadow as it's drawn: none when the frame is just the
    /// recording (no margin for a shadow).
    var effectiveShadowStyle: VideoShadowStyle? {
        guard !usesRawSourceFrame, let shadowStyle, shadowStyle.isVisible else { return nil }
        return shadowStyle.clamped()
    }

    /// Fine-tune on: the values start where the Shadow slider is. Off: the
    /// classic shadow again.
    mutating func setShadowFineTuned(_ on: Bool) {
        if on {
            if shadowStyle == nil { shadowStyle = .matching(strength: shadow) }
        } else {
            shadowStyle = nil
        }
    }
}

// MARK: - Inspector

/// Style ▸ Frame: the Shadow slider, or the fine-tuned shadow's controls.
struct VideoShadowControls: View {
    @ObservedObject var model: VideoEditorModel

    private var project: VideoDemoProject { model.project }

    var body: some View {
        if let style = project.shadowStyle {
            fineTuned(style)
        } else {
            VideoSliderRow(
                title: L("Shadow"),
                value: Binding(get: { project.shadow }, set: { value in model.setStyle(coalesce: "shadow") { $0.shadow = value } }),
                range: 0...1,
                defaultValue: VideoStylePreset.factory.shadow,
                format: { VideoEditorFormat.percent($0) },
                onEditingEnded: { model.endGesture() }
            )
        }
        VideoToggleRow(
            title: L("Fine-tune shadow"),
            detail: L("Angle, distance, softness, opacity, color, and an inner edge"),
            isOn: Binding(get: { project.shadowStyle != nil }, set: { on in model.setStyle { $0.setShadowFineTuned(on) } })
        )
    }

    @ViewBuilder
    private func fineTuned(_ style: VideoShadowStyle) -> some View {
        let classic = VideoShadowStyle.matching(strength: VideoStylePreset.factory.shadow)
        VideoSliderRow(
            title: L("Angle"),
            value: binding(\.angle, "shadow-angle"),
            range: VideoShadowStyle.angleRange,
            defaultValue: classic.angle,
            format: { "\(Int($0.rounded()))°" },
            onEditingEnded: { model.endGesture() }
        )
        VideoSliderRow(
            title: L("Distance"),
            value: binding(\.distance, "shadow-distance"),
            range: VideoShadowStyle.distanceRange,
            defaultValue: classic.distance,
            format: { "\(Int($0.rounded()))" },
            onEditingEnded: { model.endGesture() }
        )
        VideoSliderRow(
            title: L("Softness"),
            value: binding(\.softness, "shadow-softness"),
            range: VideoShadowStyle.softnessRange,
            defaultValue: classic.softness,
            format: { "\(Int($0.rounded()))" },
            onEditingEnded: { model.endGesture() }
        )
        VideoSliderRow(
            title: L("Opacity"),
            value: binding(\.opacity, "shadow-opacity"),
            range: VideoShadowStyle.opacityRange,
            defaultValue: classic.opacity,
            format: { VideoEditorFormat.percent($0) },
            onEditingEnded: { model.endGesture() }
        )
        HStack(spacing: 10) {
            Text(L("Shadow color"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VideoEditorTheme.textPrimary)
            Spacer()
            ColorPicker(L("Shadow color"), selection: Binding(get: { Color(nsColor: style.color.nsColor) }, set: { color in
                let rgba = VideoRGBA(nsColor: NSColor(color))
                model.setStyle(coalesce: "shadow-color") { $0.shadowStyle?.color = rgba }
            }), supportsOpacity: false)
            .labelsHidden()
        }
        VideoToggleRow(
            title: L("Inset"),
            detail: L("A soft inner edge instead of a shadow below"),
            isOn: Binding(get: { style.inset }, set: { on in model.setStyle { $0.shadowStyle?.inset = on } })
        )
    }

    private func binding(_ path: WritableKeyPath<VideoShadowStyle, Double>, _ key: String) -> Binding<Double> {
        Binding(
            get: { project.shadowStyle?[keyPath: path] ?? 0 },
            set: { value in model.setStyle(coalesce: key) { $0.shadowStyle?[keyPath: path] = value } }
        )
    }
}
