import AppKit
import SwiftUI

extension VideoEditorTheme {
    static let caption = Color(red: 0.2, green: 0.74, blue: 0.68)
    static let keys = Color(red: 0.55, green: 0.62, blue: 0.78)
    static let camera = Color(red: 0.3, green: 0.62, blue: 1.0)

    /// The title column of a row like Size · Position: 58 pt as designed,
    /// wider when a translated title (Положение) needs more.
    static func rowTitleWidth(_ titles: [String]) -> CGFloat {
        max(58, TextFitting.widest(titles, font: .systemFont(ofSize: 12, weight: .medium)))
    }
}

// MARK: - Annotation colors

/// Swatches for an annotation, plus any color from the system picker.
/// New annotations of the same kind start with the last color picked.
struct VideoOverlayColorPicker: View {
    @ObservedObject var model: VideoEditorModel
    let overlay: VideoDemoOverlayEffect

    private func same(_ a: VideoRGBA, _ b: VideoRGBA) -> Bool {
        abs(a.r - b.r) < 0.01 && abs(a.g - b.g) < 0.01 && abs(a.b - b.b) < 0.01 && abs(a.a - b.a) < 0.02
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(30), spacing: 8), count: 6)
        let palette = overlay.kind.palette
        let current = overlay.resolvedColor
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Array(palette.enumerated()), id: \.offset) { _, color in
                swatch(color)
            }
            VideoCustomColorSwatch(
                color: current,
                isCustom: !palette.contains { same($0, current) },
                showsAlpha: overlay.kind == .text
            ) { [weak model, id = overlay.id, kind = overlay.kind] picked in
                // The panel outlives the selection (and the editor): only
                // recolor while this annotation is still the one being edited.
                guard let model, model.selection == .overlay(id) else { return }
                var rgba = picked
                // The tag keeps a little see-through unless chosen otherwise.
                if kind != .text { rgba.a = 1 }
                model.setOverlayColor(id, rgba, coalesce: "color-panel-\(id)")
            }
        }
    }

    private func swatch(_ color: VideoRGBA) -> some View {
        let selected = same(overlay.resolvedColor, color)
        let clear = color.a < 0.05
        return Button {
            model.setOverlayColor(overlay.id, color)
            model.endGesture()
        } label: {
            ZStack {
                if clear {
                    Circle().strokeBorder(VideoEditorTheme.ink.opacity(0.45), lineWidth: 1.5)
                    Rectangle()
                        .fill(Color.red.opacity(0.85))
                        .frame(width: 2, height: 24)
                        .rotationEffect(.degrees(45))
                } else {
                    Circle().fill(Color(nsColor: color.withAlpha(1).nsColor))
                    Circle().strokeBorder(VideoEditorTheme.ink.opacity(0.18), lineWidth: 1)
                }
            }
            .frame(width: 24, height: 24)
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? VideoEditorTheme.ink : Color.clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(clear ? L("No background — text only") : L("Use this color"))
        .accessibilityLabel(clear ? L("No background") : L("Color"))
    }
}

/// "Any color": a rainbow swatch that opens the system color panel. Shows
/// the chosen color (ringed) when it isn't one of the swatches.
struct VideoCustomColorSwatch: View {
    let color: VideoRGBA
    let isCustom: Bool
    let showsAlpha: Bool
    let onChange: (VideoRGBA) -> Void

    var body: some View {
        Button {
            VideoColorPanel.shared.open(color: color.nsColor, showsAlpha: showsAlpha, onChange: onChange)
        } label: {
            ZStack {
                Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red], center: .center))
                Circle()
                    .fill(isCustom ? Color(nsColor: color.withAlpha(1).nsColor) : VideoEditorTheme.panel)
                    .padding(4)
                if !isCustom {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                }
            }
            .frame(width: 24, height: 24)
            .padding(3)
            .overlay(Circle().strokeBorder(isCustom ? VideoEditorTheme.ink : Color.clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L("Any color…"))
        .accessibilityLabel(L("Custom color"))
    }
}

/// Forwards the shared color panel's changes to whoever opened it last.
@MainActor
final class VideoColorPanel: NSObject {
    static let shared = VideoColorPanel()
    private var onChange: ((VideoRGBA) -> Void)?

    func open(color: NSColor, showsAlpha: Bool, onChange: @escaping (VideoRGBA) -> Void) {
        let panel = NSColorPanel.shared
        // Setting the panel's color fires its action: connect afterwards.
        self.onChange = nil
        panel.showsAlpha = showsAlpha
        panel.color = color
        panel.isContinuous = true
        self.onChange = onChange
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let color = sender.color.usingColorSpace(.sRGB) else { return }
        onChange?(VideoRGBA(nsColor: color))
    }
}

// MARK: - Keyboard shortcuts

struct VideoKeyboardSection: View {
    @ObservedObject var model: VideoEditorModel

    private func binding<T>(_ keyPath: WritableKeyPath<VideoKeystrokeStyle, T>) -> Binding<T> {
        Binding(get: { model.project.keystrokeStyle[keyPath: keyPath] }, set: { value in model.setStyle { $0.keystrokeStyle[keyPath: keyPath] = value } })
    }

    var body: some View {
        VideoInspectorSection(L("Keys on screen")) {
            if model.project.keystrokes.isEmpty {
                Text(L("None in this recording. Turn on “Show keyboard shortcuts” in Settings → Recording and every ⌘ shortcut you press appears as keycaps. Plain typing is never recorded."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Open Recording Settings…")) {
                    PreferencesWindowController.shared.show(tab: .recording)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            } else {
                VideoToggleRow(
                    title: L("Show shortcuts"),
                    detail: L("\(model.project.keystrokes.count) pressed — select one on the timeline and press ⌫ to hide it"),
                    isOn: binding(\.visible)
                )
                HStack(spacing: 10) {
                    Text(L("Size"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                        .frame(width: VideoEditorTheme.rowTitleWidth([L("Size"), L("Position"), L("Animation")]), alignment: .leading)
                    VideoSegmented(options: VideoTextSize.allCases.map { ($0, $0.title) }, selection: binding(\.size))
                }
                .disabled(!model.project.keystrokeStyle.visible)
                VideoFontPicker(model: model, choice: binding(\.font))
                    .disabled(!model.project.keystrokeStyle.visible)
                HStack(spacing: 10) {
                    Text(L("Position"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                        .frame(width: VideoEditorTheme.rowTitleWidth([L("Size"), L("Position"), L("Animation")]), alignment: .leading)
                    VideoSegmented(options: VideoTextPosition.allCases.map { ($0, $0.title) }, selection: Binding(get: { model.project.keystrokeStyle.position }, set: { model.setKeystrokePreset($0) }))
                }
                .disabled(!model.project.keystrokeStyle.visible)
                VideoPlacementRow(isCustom: model.project.keystrokeStyle.placement != nil, hint: L("Drag the keys on the preview to place them anywhere")) {
                    model.resetKeystrokePosition()
                }
                .disabled(!model.project.keystrokeStyle.visible)
            }
        }
    }
}
