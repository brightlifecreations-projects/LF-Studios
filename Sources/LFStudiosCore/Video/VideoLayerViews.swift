import AppKit
import SwiftUI

// MARK: - Properties of an item above the main track (1.14.0)

/// Opacity, size, rotation, mirror, crop, sound and speed of a video or
/// picture on a track above the main track.
struct VideoLayerItemEditor: View {
    @ObservedObject var model: VideoEditorModel
    let item: VideoLayerItem

    var body: some View {
        VideoInspectorSection(L("Picture")) {
            VideoToggleRow(title: L("Show"), detail: L("Off, it stays on the timeline but isn't seen or heard (V)"),
                           isOn: Binding(get: { item.enabled }, set: { on in model.setLayerItem(item.id, label: on ? "Turn On Clip" : "Turn Off Clip") { $0.enabled = on } }))
            VideoSliderRow(
                title: L("Opacity"),
                value: Binding(get: { item.opacity * 100 }, set: { value in model.setLayerItem(item.id, coalesce: "layer-opacity-\(item.id)") { $0.opacity = value / 100 } }),
                range: 0...100, defaultValue: 100, format: { L("\(Int($0.rounded()))%") },
                onEditingEnded: { model.endGesture() }
            )
            VideoSliderRow(
                title: L("Size"),
                value: Binding(get: { item.width * 100 }, set: { value in model.setLayerItem(item.id, coalesce: "layer-size-\(item.id)") { $0.width = value / 100 } }),
                range: 5...200, defaultValue: nil, format: { L("\(Int($0.rounded()))%") },
                detail: L("Of the video's width. Or drag a corner on the player."),
                onEditingEnded: { model.endGesture() }
            )
            VideoSliderRow(
                title: L("Rotation"),
                value: Binding(get: { item.rotation }, set: { value in model.setLayerItem(item.id, coalesce: "layer-rotate-\(item.id)") { $0.rotation = value } }),
                range: -180...180, defaultValue: 0, format: { L("\(Int($0.rounded()))°") },
                detail: L("Or drag the round knob above it on the player"),
                onEditingEnded: { model.endGesture() }
            )
            HStack(spacing: 8) {
                Button {
                    model.setLayerItem(item.id, label: "Mirror") { $0.mirrored.toggle() }
                } label: {
                    Label(L("Mirror"), systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                Button {
                    model.setLayerItem(item.id, label: "Rotate") { $0.rotation = VideoLayerItem.nextQuarterTurn(after: $0.rotation) }
                } label: {
                    Label(L("Rotate 90°"), systemImage: "rotate.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            }
            HStack(spacing: 8) {
                Button {
                    model.setLayerItem(item.id, label: "Fit") { $0.fit(in: model.project.canvasSize(), filling: false) }
                } label: {
                    Label(L("Fit"), systemImage: "arrow.down.right.and.arrow.up.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("The whole picture, as big as the video allows"))
                Button {
                    model.setLayerItem(item.id, label: "Fill") { $0.fit(in: model.project.canvasSize(), filling: true) }
                } label: {
                    Label(L("Fill"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("Covers the whole video; the edges may be cut off"))
            }
        }

        VideoInspectorSection(L("Crop")) {
            let crop = (item.crop ?? .full).normalized
            VideoSliderRow(title: L("Left"), value: cropBinding(\.x, crop), range: 0...0.9, defaultValue: 0, format: Self.percent, onEditingEnded: { model.endGesture() })
            VideoSliderRow(title: L("Right"), value: Binding(get: { 1 - crop.x - crop.width }, set: { value in setCrop { $0.width = 1 - $0.x - value } }), range: 0...0.9, defaultValue: 0, format: Self.percent, onEditingEnded: { model.endGesture() })
            VideoSliderRow(title: L("Top"), value: cropBinding(\.y, crop), range: 0...0.9, defaultValue: 0, format: Self.percent, onEditingEnded: { model.endGesture() })
            VideoSliderRow(title: L("Bottom"), value: Binding(get: { 1 - crop.y - crop.height }, set: { value in setCrop { $0.height = 1 - $0.y - value } }), range: 0...0.9, defaultValue: 0, format: Self.percent, onEditingEnded: { model.endGesture() })
        }

        if item.isVideo {
            VideoInspectorSection(L("Sound")) {
                VideoToggleRow(title: L("Mute this clip"), isOn: Binding(get: { item.muted }, set: { muted in model.setLayerItem(item.id, label: muted ? "Mute Clip" : "Unmute Clip") { $0.muted = muted } }))
                VideoSliderRow(
                    title: L("Volume"),
                    value: Binding(get: { item.volume * 100 }, set: { value in model.setLayerItem(item.id, coalesce: "layer-volume-\(item.id)") { $0.volume = value / 100 } }),
                    range: 0...200, defaultValue: 100, format: { L("\(Int($0.rounded()))%") },
                    onEditingEnded: { model.endGesture() }
                )
            }
            VideoInspectorSection(L("Speed")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach([0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0], id: \.self) { speed in
                        let selected = abs(item.normalizedSpeed - speed) < 0.01
                        Button {
                            model.setLayerSpeed(item.id, speed)
                            model.endGesture()
                        } label: {
                            Text(VideoEditorModel.formatScale(speed))
                                .font(.system(size: 11.5, weight: selected ? .bold : .semibold))
                                .foregroundStyle(selected ? Color.black : VideoEditorTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? VideoEditorTheme.layer : VideoEditorTheme.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        VideoInspectorSection(L("Edit")) {
            Button {
                _ = model.splitLayerItem(item.id, at: model.clock.time)
            } label: {
                Label(L("Split at playhead"), systemImage: "scissors")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .disabled(!item.isShowing(at: model.clock.time))
            Text(L("Drag it on the timeline to another time or track; drag its ends to trim. ⌥-drag inside a video to slip it."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func percent(_ value: Double) -> String { L("\(Int((value * 100).rounded()))%") }

    private func cropBinding(_ key: WritableKeyPath<VideoCropRect, Double>, _ crop: VideoCropRect) -> Binding<Double> {
        Binding(get: { crop[keyPath: key] }, set: { value in
            setCrop { rect in
                // The far edge stays put.
                if key == \VideoCropRect.x { rect.width += rect.x - value } else { rect.height += rect.y - value }
                rect[keyPath: key] = value
            }
        })
    }

    private func setCrop(_ change: @escaping (inout VideoCropRect) -> Void) {
        model.setLayerItem(item.id, coalesce: "layer-crop-\(item.id)", label: "Crop") { item in
            var rect = (item.crop ?? .full).normalized
            change(&rect)
            rect = rect.normalized
            item.crop = rect.isFull ? nil : rect
        }
    }
}

extension VideoLayerItem {
    /// The next quarter turn clockwise (0, 90, 180, −90).
    static func nextQuarterTurn(after degrees: Double) -> Double {
        let next = ((degrees / 90).rounded(.down) + 1) * 90
        let wrapped = next.truncatingRemainder(dividingBy: 360)
        return wrapped > 180 ? wrapped - 360 : wrapped
    }

    /// Fit: the whole item inside the frame. Fill: covering the frame.
    mutating func fit(in canvas: CGSize, filling: Bool) {
        let canvasAspect = Double(canvas.width / max(canvas.height, 1))
        let byWidth = 1.0
        let byHeight = shownAspect / max(canvasAspect, 0.01)
        width = filling ? max(byWidth, byHeight) : min(byWidth, byHeight)
        x = 0.5
        y = 0.5
        rotation = 0
    }
}
