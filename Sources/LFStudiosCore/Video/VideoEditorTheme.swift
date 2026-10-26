import AppKit
import SwiftUI

extension Color {
    /// One color for the dark look and one for the light look, picked by
    /// the appearance the view is drawn in (Settings → General → Appearance).
    static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: .adaptive(dark: dark, light: light))
    }
}

extension NSColor {
    static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

/// The editor's content-first palette, dark or light. The video itself
/// never uses it: the renderer has its own colors.
enum VideoEditorTheme {
    static let window = Color.adaptive(dark: NSColor(srgbRed: 0.047, green: 0.047, blue: 0.055, alpha: 1), light: NSColor(srgbRed: 0.925, green: 0.925, blue: 0.937, alpha: 1))
    static let stage = Color.adaptive(dark: NSColor(srgbRed: 0.035, green: 0.035, blue: 0.043, alpha: 1), light: NSColor(srgbRed: 0.878, green: 0.882, blue: 0.898, alpha: 1))
    static let panel = Color.adaptive(dark: NSColor(srgbRed: 0.075, green: 0.075, blue: 0.086, alpha: 1), light: NSColor(srgbRed: 0.976, green: 0.976, blue: 0.98, alpha: 1))
    /// What chrome is drawn in: white on the dark look, black on the light
    /// one (fills and lines use it faintly).
    static let ink = Color.adaptive(dark: .white, light: .black)
    static let card = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.045), light: NSColor.black.withAlphaComponent(0.04))
    static let cardHover = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.075), light: NSColor.black.withAlphaComponent(0.065))
    static let cardStroke = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.075), light: NSColor.black.withAlphaComponent(0.1))
    static let hairline = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.07), light: NSColor.black.withAlphaComponent(0.1))
    /// A recessed field (segmented controls, text fields).
    static let well = Color.adaptive(dark: NSColor.black.withAlphaComponent(0.28), light: NSColor.black.withAlphaComponent(0.055))
    /// The selected segment, a hovered row.
    static let selectedFill = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.14), light: NSColor.white)
    static let textPrimary = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.93), light: NSColor.black.withAlphaComponent(0.88))
    static let textSecondary = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.58), light: NSColor.black.withAlphaComponent(0.62))
    /// Helper text: still readable on the panel (about 5:1).
    static let textTertiary = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.5), light: NSColor.black.withAlphaComponent(0.55))
    /// Floating panels inside the editor (⌘K, the shortcuts list).
    static let popover = Color.adaptive(dark: NSColor(white: 0.11, alpha: 1), light: NSColor(white: 0.995, alpha: 1))
    /// The tools dock over the stage.
    static let dock = Color.adaptive(dark: NSColor(srgbRed: 0.1, green: 0.1, blue: 0.115, alpha: 0.94), light: NSColor(white: 1, alpha: 0.96))
    /// Tips and suggestions floating over the stage.
    static let floatingPill = Color.adaptive(dark: NSColor.black.withAlphaComponent(0.72), light: NSColor(white: 1, alpha: 0.94))
    /// Shadows read softer on the light look.
    static let shadow = Color.adaptive(dark: NSColor.black.withAlphaComponent(0.45), light: NSColor.black.withAlphaComponent(0.14))
    /// Text on a timeline pill: white on the dark look; on the light one
    /// the pills are pale, so it's dark.
    static func laneText(_ opacity: Double = 0.92) -> Color {
        Color.adaptive(dark: NSColor.white.withAlphaComponent(opacity), light: NSColor.black.withAlphaComponent(min(opacity, 0.86)))
    }
    /// A timeline pill's edge, strong when it's selected.
    static func laneStroke(selected: Bool) -> Color {
        selected
            ? Color.adaptive(dark: NSColor.white.withAlphaComponent(0.95), light: NSColor.black.withAlphaComponent(0.72))
            : Color.adaptive(dark: NSColor.white.withAlphaComponent(0.13), light: NSColor.black.withAlphaComponent(0.12))
    }
    /// Warnings and failures.
    static let warning = Color.adaptive(dark: NSColor(srgbRed: 1, green: 0.58, blue: 0.52, alpha: 1), light: NSColor(srgbRed: 0.78, green: 0.2, blue: 0.13, alpha: 1))
    /// `ink` for AppKit text (the transcript).
    static func inkNS(_ alpha: CGFloat) -> NSColor {
        .adaptive(dark: NSColor.white.withAlphaComponent(alpha), light: NSColor.black.withAlphaComponent(min(alpha, 0.88)))
    }
    /// Red text for Delete and Remove.
    static let destructive = Color.adaptive(dark: NSColor(srgbRed: 1, green: 0.47, blue: 0.47, alpha: 1), light: NSColor(srgbRed: 0.8, green: 0.13, blue: 0.13, alpha: 1))
    static let zoom = Color(red: 0.43, green: 0.39, blue: 1.0)
    static let clip = Color(red: 0.94, green: 0.58, blue: 0.2)
    static let playhead = Color(red: 1.0, green: 0.31, blue: 0.43)
    static let accent = Color.accentColor
    /// Primary buttons: a fixed blue, so white text stays readable whatever
    /// accent color the Mac uses (yellow, orange, green…).
    static let primary = Color(red: 0.04, green: 0.42, blue: 1.0)

    static func overlayTint(_ kind: VideoDemoOverlayEffectKind) -> Color {
        switch kind {
        case .text: return Color(red: 0.62, green: 0.35, blue: 0.95)
        case .highlight: return Color(red: 0.92, green: 0.7, blue: 0.1)
        case .arrow: return Color(red: 0.95, green: 0.55, blue: 0.15)
        case .blur: return Color(white: 0.42)
        case .spotlight: return Color(red: 0.3, green: 0.66, blue: 0.82)
        case .image: return Color(red: 0.2, green: 0.66, blue: 0.9)
        }
    }
}

/// Values the editor shows, written the way the user's language writes them.
enum VideoEditorFormat {
    /// A fraction as a percentage: "42%" ("42 %" in German and French).
    static func percent(_ fraction: Double) -> String {
        L("\(Int((fraction * 100).rounded()))%")
    }
}

// MARK: - Buttons

struct VideoToolButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        VideoToolButtonBody(configuration: configuration, prominent: prominent, destructive: destructive)
    }

    private struct VideoToolButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let destructive: Bool
        @State private var hovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(foreground)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(background)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovered = $0 }
        }

        private var foreground: Color {
            guard isEnabled else { return VideoEditorTheme.textTertiary }
            if destructive { return VideoEditorTheme.destructive }
            return VideoEditorTheme.textPrimary
        }

        private var background: Color {
            if prominent { return VideoEditorTheme.ink.opacity(configuration.isPressed ? 0.2 : (hovered ? 0.16 : 0.11)) }
            if configuration.isPressed { return VideoEditorTheme.ink.opacity(0.14) }
            return hovered && isEnabled ? VideoEditorTheme.ink.opacity(0.08) : Color.clear
        }
    }
}

struct VideoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration)
    }

    private struct PrimaryBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : VideoEditorTheme.textTertiary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isEnabled ? VideoEditorTheme.primary : VideoEditorTheme.ink.opacity(0.08))
                        .brightness(configuration.isPressed ? -0.08 : 0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isEnabled ? Color.white.opacity(0.18) : VideoEditorTheme.cardStroke, lineWidth: 1)
                )
                .shadow(color: VideoEditorTheme.primary.opacity(isEnabled ? 0.35 : 0), radius: 8, y: 2)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}

struct VideoSecondaryButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration, destructive: destructive)
    }

    private struct SecondaryBody: View {
        let configuration: ButtonStyleConfiguration
        let destructive: Bool
        @State private var hovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? (destructive ? VideoEditorTheme.destructive : VideoEditorTheme.textPrimary) : VideoEditorTheme.textTertiary)
                .padding(.horizontal, 12)
                .frame(minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(VideoEditorTheme.ink.opacity(configuration.isPressed ? 0.14 : (hovered && isEnabled ? 0.1 : 0.06)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onHover { hovered = $0 }
        }
    }
}

// MARK: - Inspector building blocks

struct VideoInspectorSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                trailing()
            }
            content()
        }
    }
}

extension VideoInspectorSection where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, trailing: { EmptyView() }, content: content)
    }
}

/// A labeled slider with its value and a reset button that appears when
/// the value differs from the default.
struct VideoSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double?
    var format: (Double) -> String
    var detail: String?
    var onEditingEnded: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Spacer()
                if let defaultValue, abs(value - defaultValue) > (range.upperBound - range.lowerBound) * 0.004 {
                    Button {
                        value = defaultValue
                        onEditingEnded()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(VideoEditorTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Reset"))
                    .accessibilityLabel(L("Reset \(title)"))
                }
                Text(format(value))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .frame(minWidth: 38, alignment: .trailing)
            }
            Slider(value: $value, in: range, onEditingChanged: { editing in
                if !editing { onEditingEnded() }
            })
            .controlSize(.small)
            .accessibilityLabel(title)
            .accessibilityValue(format(value))
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct VideoToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }
}

/// Pill segmented control that matches the editor chrome.
struct VideoSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        VideoSegmentsLayout(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? VideoEditorTheme.textPrimary : VideoEditorTheme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? VideoEditorTheme.selectedFill : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // VoiceOver says which option is on.
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(VideoEditorTheme.well)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1)
        )
    }
}

/// Segments side by side: equal while every title fits its share. When one
/// doesn't (German and French run long), each segment gets its title's width
/// and some room around it, and they share what's left; titles truncate only
/// when even that doesn't fit.
struct VideoSegmentsLayout: Layout {
    var spacing: CGFloat
    /// Room on each side of a title when widths follow the titles.
    var titlePadding: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let spacings = spacing * CGFloat(max(subviews.count - 1, 0))
        let idealWidth = ideals.reduce(spacings) { $0 + $1.width + 2 * titlePadding }
        return CGSize(width: proposal.width ?? idealWidth, height: ideals.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let count = CGFloat(subviews.count)
        let available = max(bounds.width - spacing * (count - 1), 0)
        let share = available / count
        let titles = subviews.map { $0.sizeThatFits(.unspecified).width }
        var widths = Array(repeating: share, count: subviews.count)
        if titles.contains(where: { $0 > share }) {
            let needed = titles.map { $0 + 2 * titlePadding }
            let total = needed.reduce(0, +)
            let extra = available - total
            widths = extra >= 0 ? needed.map { $0 + extra / count } : needed.map { $0 * available / max(total, 1) }
        }
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: widths[index], height: bounds.height))
            x += widths[index] + spacing
        }
    }
}

struct VideoCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(VideoEditorTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
    }
}

/// Lets empty chrome drag the window (the toolbar lives in the title bar).
struct VideoWindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
