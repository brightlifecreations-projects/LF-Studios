import AppKit
import SwiftUI

// MARK: - Properties of an item above the main track (1.14.0)

/// Opacity, size, rotation, mirror, crop, sound and speed of a video or
/// picture on a track above the main track.
struct VideoLayerItemEditor: View {
    @ObservedObject var model: VideoEditorModel
    /// The playhead: keyed values show as they are there.
    @ObservedObject var clock: VideoDemoPlaybackClock
    let item: VideoLayerItem

    /// The item as it is at the playhead.
    private var shown: VideoLayerItem { item.resolved(at: clock.time) }

    var body: some View {
        VideoInspectorSection(L("Keyframes")) {
            VideoKeyframeBar(model: model, clock: clock, item: item)
        }

        if let text = item.text {
            VideoTextClipSection(model: model, item: item, content: text)
        }

        VideoInspectorSection(item.isText ? L("Placement") : L("Picture")) {
            VideoToggleRow(title: L("Show"), detail: L("Off, it stays on the timeline but isn't seen or heard (V)"),
                           isOn: Binding(get: { item.enabled }, set: { on in model.setLayerItem(item.id, label: on ? "Turn On Clip" : "Turn Off Clip") { $0.enabled = on } }))
            keyed(L("Position across"), .x, range: -50...150, scale: 100, defaultValue: 50, format: Self.percent)
            keyed(L("Position down"), .y, range: -50...150, scale: 100, defaultValue: 50, format: Self.percent, diamond: false)
            keyed(L("Size"), .width, range: 5...200, scale: 100, defaultValue: nil, format: Self.percent, detail: L("Of the video's width. Or drag a corner on the player."))
            keyed(L("Rotation"), .rotation, range: -180...180, scale: 1, defaultValue: 0, format: { L("\(Int($0.rounded()))°") }, detail: L("Or drag the round knob above it on the player"))
            keyed(L("Opacity"), .opacity, range: 0...100, scale: 100, defaultValue: 100, format: Self.percent)
            HStack(spacing: 8) {
                Button {
                    model.setLayerItem(item.id, label: "Mirror") { $0.mirrored.toggle() }
                } label: {
                    Label(L("Mirror"), systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                Button {
                    model.setLayerAnimated(item.id, label: "Rotate") { $0.rotation = VideoLayerItem.nextQuarterTurn(after: $0.rotation) }
                } label: {
                    Label(L("Rotate 90°"), systemImage: "rotate.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            }
            HStack(spacing: 8) {
                Button {
                    model.setLayerAnimated(item.id, label: "Fit") { $0.fit(in: model.project.canvasSize(), filling: false) }
                } label: {
                    Label(L("Fit"), systemImage: "arrow.down.right.and.arrow.up.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("The whole picture, as big as the video allows"))
                Button {
                    model.setLayerAnimated(item.id, label: "Fill") { $0.fit(in: model.project.canvasSize(), filling: true) }
                } label: {
                    Label(L("Fill"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("Covers the whole video; the edges may be cut off"))
            }
        }

        VideoAnimationSection(model: model, item: item)

        VideoMotionTrackingSection(model: model, item: item)

        VideoInspectorSection(L("Blend")) {
            Picker(L("Blend"), selection: Binding(get: { item.blend ?? .normal }, set: { blend in
                model.selection = .layer(item.id)
                model.perform(.edit(.setBlend(blend)))
            })) {
                ForEach(VideoBlendMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Text(L("How it mixes with what's under it: Screen lightens, Multiply darkens, Overlay adds contrast."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !item.isText {
        VideoInspectorSection(L("Cutout")) {
            VideoToggleRow(title: L("Remove background"), detail: L("Keeps just the person, found on this Mac"),
                           isOn: Binding(get: { item.removesBackground == true }, set: { on in
                               model.selection = .layer(item.id)
                               model.perform(.edit(.setRemoveBackground(on)))
                           }))
            VideoToggleRow(title: L("Chroma key"), detail: L("Takes out one colour, like a green screen"),
                           isOn: Binding(get: { item.chroma != nil }, set: { on in
                               model.selection = .layer(item.id)
                               model.perform(.edit(.setChromaKey(on ? VideoChromaKey() : nil)))
                               model.endGesture()
                           }))
            if let key = item.chroma {
                ColorPicker(L("Colour to take out"), selection: Binding(get: { Color(red: key.color.r, green: key.color.g, blue: key.color.b) }, set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    var next = key
                    next.color = VideoRGBA(Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
                    model.perform(.edit(.setChromaKey(next)))
                }), supportsOpacity: false)
                .font(.system(size: 12, weight: .medium))
                VideoSliderRow(title: L("Strength"), value: Binding(get: { key.strength * 100 }, set: { value in
                    var next = key; next.strength = value / 100
                    model.perform(.edit(.setChromaKey(next)))
                }), range: 0...100, defaultValue: 35, format: Self.percent, onEditingEnded: { model.endGesture() })
                VideoSliderRow(title: L("Shadow"), value: Binding(get: { key.shadow * 100 }, set: { value in
                    var next = key; next.shadow = value / 100
                    model.perform(.edit(.setChromaKey(next)))
                }), range: 0...100, defaultValue: 0, format: Self.percent, detail: L("How much of the shadows on the screen stays"), onEditingEnded: { model.endGesture() })
            }
        }
        }

        VideoInspectorSection(L("Mask")) {
            HStack(spacing: 4) {
                maskButton(nil, title: L("None"), symbol: "nosign")
                ForEach(VideoMask.Shape.allCases) { shape in maskButton(shape, title: shape.title, symbol: shape.symbol) }
            }
            if let mask = item.mask {
                keyed(L("Across"), .maskX, range: 0...100, scale: 100, defaultValue: 50, format: Self.percent)
                keyed(L("Down"), .maskY, range: 0...100, scale: 100, defaultValue: 50, format: Self.percent, diamond: false)
                keyed(L("Size"), .maskSize, range: 1...200, scale: 100, defaultValue: nil, format: Self.percent, diamond: false)
                keyed(L("Rotation"), .maskRotation, range: -180...180, scale: 1, defaultValue: 0, format: { L("\(Int($0.rounded()))°") }, diamond: false)
                keyed(L("Feather"), .maskFeather, range: 0...50, scale: 100, defaultValue: 5, format: Self.percent, diamond: false)
                if mask.shape == .circle || mask.shape == .rectangle {
                    VideoSliderRow(title: L("Shape"), value: Binding(get: { mask.aspect * 100 }, set: { value in
                        var next = mask; next.aspect = value / 100
                        model.perform(.edit(.setMask(next)))
                    }), range: 10...300, defaultValue: 100, format: Self.percent, detail: L("Height compared with width"), onEditingEnded: { model.endGesture() })
                }
                VideoToggleRow(title: L("Invert"), detail: L("Hides what's inside the shape instead"), isOn: Binding(get: { mask.invert }, set: { on in
                    var next = mask; next.invert = on
                    model.perform(.edit(.setMask(next)))
                    model.endGesture()
                }))
            }
        }

        if !item.isText {
        VideoInspectorSection(L("Crop")) {
            keyed(L("Left"), .cropX, range: 0...90, scale: 100, defaultValue: 0, format: Self.percent)
            keyed(L("Top"), .cropY, range: 0...90, scale: 100, defaultValue: 0, format: Self.percent, diamond: false)
            keyed(L("Width"), .cropWidth, range: 8...100, scale: 100, defaultValue: 100, format: Self.percent, diamond: false)
            keyed(L("Height"), .cropHeight, range: 8...100, scale: 100, defaultValue: 100, format: Self.percent, diamond: false)
        }
        }

        if item.isVideo {
            VideoInspectorSection(L("Sound")) {
                VideoToggleRow(title: L("Mute this clip"), isOn: Binding(get: { item.muted }, set: { muted in model.setLayerItem(item.id, label: muted ? "Mute Clip" : "Unmute Clip") { $0.muted = muted } }))
                keyed(L("Volume"), .volume, range: 0...200, scale: 100, defaultValue: 100, format: Self.percent)
                HStack(spacing: 12) {
                    VideoSliderRow(title: L("Fade in"), value: Binding(get: { item.soundFadeIn ?? 0 }, set: { value in
                        model.selection = .layer(item.id)
                        model.perform(.edit(.setSoundFades((value * 10).rounded() / 10, item.soundFadeOut ?? 0)))
                    }), range: 0...5, defaultValue: 0, format: { VideoEditorModel.format($0) }, onEditingEnded: { model.endGesture() })
                    VideoSliderRow(title: L("Fade out"), value: Binding(get: { item.soundFadeOut ?? 0 }, set: { value in
                        model.selection = .layer(item.id)
                        model.perform(.edit(.setSoundFades(item.soundFadeIn ?? 0, (value * 10).rounded() / 10)))
                    }), range: 0...5, defaultValue: 0, format: { VideoEditorModel.format($0) }, onEditingEnded: { model.endGesture() })
                }
                Button {
                    model.selection = .layer(item.id)
                    model.perform(.edit(.normalize))
                } label: {
                    Label(L("Normalize"), systemImage: "waveform.badge.checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("Sets the volume so it's as loud as video sites expect (−16 LUFS)"))
            }
            VideoInspectorSection(L("Speed")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach([0.1, 0.25, 0.5, 1.0, 1.5, 2.0, 4.0, 8.0, 16.0, 100.0], id: \.self) { speed in
                        let selected = abs(item.normalizedSpeed - speed) < 0.001
                        Button {
                            model.selection = .layer(item.id)
                            model.perform(.edit(.setSpeed(speed)))
                            model.endGesture()
                        } label: {
                            Text(VideoEditorModel.formatScale(speed))
                                .font(.system(size: 11, weight: selected ? .bold : .semibold))
                                .foregroundStyle(selected ? Color.black : VideoEditorTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? VideoEditorTheme.layer : VideoEditorTheme.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
                VideoToggleRow(title: L("Keep pitch"), detail: L("Off: faster sounds higher, slower lower. The sound is silent faster than 32× or slower than 1/32×."),
                               isOn: Binding(get: { item.keepsPitch != false }, set: { on in
                                   model.selection = .layer(item.id)
                                   model.perform(.edit(.setKeepPitch(on)))
                               }))
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
            .disabled(!item.isShowing(at: clock.time))
            Text(L("Drag it on the timeline to another time or track; drag its ends to trim. ⌥-drag inside a video to slip it."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func percent(_ value: Double) -> String { L("\(Int(value.rounded()))%") }

    private func maskButton(_ shape: VideoMask.Shape?, title: String, symbol: String) -> some View {
        let selected = item.mask?.shape == shape
        return Button {
            model.selection = .layer(item.id)
            model.perform(.edit(.setMask(shape.map { VideoMask(shape: $0) })))
            model.endGesture()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 9.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .foregroundStyle(selected ? VideoEditorTheme.textPrimary : VideoEditorTheme.textSecondary)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? VideoEditorTheme.layer.opacity(0.25) : VideoEditorTheme.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Mask: \(title)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A slider for an animatable property, showing its value at the
    /// playhead, with its diamond (keyframe at the playhead).
    func keyed(_ title: String, _ property: VideoKeyProperty, range: ClosedRange<Double>, scale: Double, defaultValue: Double?, format: @escaping (Double) -> String, detail: String? = nil, diamond: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VideoSliderRow(
                title: title,
                value: Binding(get: { shown.base(property) * scale }, set: { value in
                    model.selection = .layer(item.id)
                    model.perform(.edit(.setValue(property, value / scale)))
                }),
                range: range, defaultValue: defaultValue, format: format, detail: detail,
                onEditingEnded: { model.endGesture() }
            )
            if diamond {
                VideoKeyDiamond(model: model, clock: clock, item: item, property: property)
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
        }
    }
}

/// ◆: a keyframe for a property (and the ones keyed with it) at the
/// playhead. Filled: there is one; tinted: the property is animated.
struct VideoKeyDiamond: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock
    let item: VideoLayerItem
    let property: VideoKeyProperty

    var body: some View {
        let local = clock.time - item.at
        let here = VideoKeyProperty.group(property).allSatisfy { item.keys?.hasKey($0, at: local) == true }
        let animated = item.keys?.isAnimated(property) == true
        Button {
            model.toggleKeyframe(item.id, property)
        } label: {
            Image(systemName: here ? "diamond.fill" : "diamond")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(here || animated ? VideoEditorTheme.layer : VideoEditorTheme.textTertiary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(here ? L("Remove the keyframe at the playhead") : L("Add a keyframe at the playhead: \(property.title)"))
        .accessibilityLabel(here ? L("Remove keyframe: \(property.title)") : L("Add keyframe: \(property.title)"))
    }
}

/// ◀ ◆ ▶ and the easing of the keys at the playhead.
struct VideoKeyframeBar: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock
    let item: VideoLayerItem

    var body: some View {
        let local = clock.time - item.at
        let times = item.keys?.times ?? []
        let atKey = times.contains { abs($0 - local) < 1.0 / 120 }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { model.perform(.previousKeyframe) } label: { Image(systemName: "chevron.left").frame(width: 26, height: 24) }
                    .buttonStyle(VideoToolButtonStyle())
                    .disabled(!times.contains { $0 < local - 0.001 })
                    .help(L("Previous keyframe"))
                    .accessibilityLabel(L("Previous keyframe"))
                Button { model.perform(.addKeyframe) } label: {
                    Label(atKey ? L("Keyed here") : L("Add keyframe"), systemImage: atKey ? "diamond.fill" : "diamond")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("A keyframe for position, size, rotation and opacity at the playhead"))
                Button { model.perform(.nextKeyframe) } label: { Image(systemName: "chevron.right").frame(width: 26, height: 24) }
                    .buttonStyle(VideoToolButtonStyle())
                    .disabled(!times.contains { $0 > local + 0.001 })
                    .help(L("Next keyframe"))
                    .accessibilityLabel(L("Next keyframe"))
            }
            if atKey {
                Picker(L("Easing"), selection: Binding(get: { Self.easing(item, at: local) }, set: { model.setKeyEasing(item.id, $0) })) {
                    ForEach(VideoEasing.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))
            }
            Text(times.isEmpty
                 ? L("Click ◆ next to a setting to animate it: set a keyframe, move the playhead, change the setting.")
                 : L("\(times.count) keyframes. Change a setting with ◆ lit to add one at the playhead."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func easing(_ item: VideoLayerItem, at local: Double) -> VideoEasing {
        for property in VideoKeyProperty.allCases {
            if let key = item.keys?.keys(property).first(where: { abs($0.time - local) < 1.0 / 120 }) { return key.easing }
        }
        return .linear
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
