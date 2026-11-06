import AppKit
import SwiftUI

// MARK: - Camera

struct VideoCameraInspector: View {
    @ObservedObject var model: VideoEditorModel
    @State private var cropPicture: NSImage?

    private func binding<T>(_ keyPath: WritableKeyPath<VideoWebcamSettings, T>, coalesce: String? = nil) -> Binding<T> {
        Binding(get: { model.project.webcam[keyPath: keyPath] }, set: { value in model.setStyle(coalesce: coalesce) { $0.webcam[keyPath: keyPath] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let missing = model.missingWebcamFile, !model.hasCameraInAnyRecording {
                // Recorded with a camera, but its file moved or was deleted
                // (and no added recording brings one).
                VideoCard {
                    Label(L("Camera footage is missing"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Text(L("This video was recorded with your camera, but “\(missing.lastPathComponent)” isn't in \(missing.deletingLastPathComponent().lastPathComponent) anymore. Put it back there and open the video again to get the camera bubble back."))
                        .font(.system(size: 11))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if FileManager.default.fileExists(atPath: missing.deletingLastPathComponent().path) {
                        Button(L("Show Folder in Finder")) {
                            NSWorkspace.shared.open(missing.deletingLastPathComponent())
                        }
                        .buttonStyle(VideoSecondaryButtonStyle())
                    }
                }
                VideoCameraVideoSection(model: model)
            } else if !model.hasCameraInAnyRecording {
                VideoCard {
                    Label(L("No camera in this recording"), systemImage: "video.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Text(L("Turn on the camera in the recording bar before you record, and your face appears here as a bubble you can place, resize, and restyle."))
                        .font(.system(size: 11))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VideoCameraVideoSection(model: model)
            } else {
                VideoCameraVideoSection(model: model)

                VideoInspectorSection(L("Camera")) {
                    VideoToggleRow(title: L("Show camera"), isOn: binding(\.visible))
                    // A shape is also a corner preset: picking one resets the roundness.
                    VideoCameraShapeMenu(model: model)
                    HStack(spacing: 10) {
                        Text(L("Behind you"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VideoEditorTheme.textPrimary)
                            .fixedSize()
                        VideoSegmented(options: VideoWebcamSettings.Backdrop.allCases.map { ($0, $0.title) }, selection: binding(\.backdrop))
                    }
                    .disabled(model.project.webcam.shape == .cutout)
                    if model.project.webcam.shape == .cutout || model.project.webcam.backdrop == .remove {
                        Text(L("Your video's background shows behind you — found on this Mac, frame by frame."))
                            .font(.system(size: 10.5))
                            .foregroundStyle(VideoEditorTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.project.webcam.placement != nil {
                        // Placed by hand: its width, as a share of the video's.
                        VideoSliderRow(
                            title: L("Size"),
                            value: Binding(get: { model.project.webcam.placement?.width ?? 0.25 }, set: { value in model.setStyle(coalesce: "webcam-size") { $0.webcam.placement?.width = value } }),
                            range: 0.08...0.9,
                            defaultValue: 0.25,
                            format: { VideoEditorFormat.percent($0) },
                            detail: L("Of the video's width"),
                            onEditingEnded: { model.endGesture() }
                        )
                    } else {
                        VideoSliderRow(
                            title: L("Size"),
                            value: binding(\.size, coalesce: "webcam-size"),
                            range: VideoWebcamSettings.sizeRange,
                            defaultValue: VideoWebcamSettings().size,
                            format: { VideoEditorFormat.percent($0) },
                            onEditingEnded: { model.endGesture() }
                        )
                    }
                }
                .disabled(false)

                VideoCameraLayoutSection(model: model)

                cameraLook

                VideoInspectorSection(L("Position")) {
                    // A spot puts a camera placed by hand back on the grid, as big.
                    VideoAnchorPicker(selection: Binding(get: { model.project.webcam.anchor }, set: { anchor in
                        let canvas = model.plan.outputCanvasSize
                        model.setStyle {
                            let rect = VideoFrameRenderer.webcamRect($0.webcam, outputSize: canvas)
                            if $0.webcam.placement != nil {
                                $0.webcam.placement = nil
                                $0.webcam.size = min(max(Double(rect.height / max(min(canvas.width, canvas.height), 1)), VideoWebcamSettings.sizeRange.lowerBound), VideoWebcamSettings.sizeRange.upperBound)
                            }
                            $0.webcam.anchor = anchor
                        }
                    }))
                    Text(L("Or drag the camera on the video: it snaps to the corners, edges and center. Drag its edges and corners to resize it."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.project.webcam.placement != nil || abs(model.project.webcam.size - VideoWebcamSettings().size) > 0.0001 {
                        Button {
                            model.setStyle {
                                $0.webcam.placement = nil
                                $0.webcam.size = VideoWebcamSettings().size
                            }
                        } label: {
                            Label(L("Reset size"), systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(VideoSecondaryButtonStyle())
                        .help(L("Back to the usual size, in the spot chosen above"))
                    }
                }
                .disabled(!model.project.webcam.visible)

                VideoInspectorSection(L("Behavior")) {
                    VideoToggleRow(title: L("Mirror"), detail: L("Flip like a selfie"), isOn: binding(\.mirror))
                    // Part of Auto-zoom on clicks (Zoom panel): greyed out until it's on.
                    VideoToggleRow(title: L("Shrink while zoomed"), detail: model.project.autoZoom ? L("Gets out of the way during zoom moves") : L("Turn on Auto-zoom on clicks (Zoom) to use this"), isOn: binding(\.shrinkWhenZoomed))
                        .disabled(!model.project.autoZoom)
                        .opacity(model.project.autoZoom ? 1 : 0.45)
                }
                .disabled(!model.project.webcam.visible)

                VideoCameraExtrasSections(model: model)

                VideoInspectorSection(L("Layouts")) {
                    Text(L("Switch the camera to full screen for talking points, or put it side by side with the screen — at the playhead. Each shows on the Camera lane."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        // Bubble only means something on a split or camera-only video.
                        ForEach(VideoCameraLayoutRegion.Layout.allCases.filter { $0 != .bubble || model.project.webcam.effectiveLayout != .bubble }) { layout in
                            Button {
                                model.addCameraLayout(layout)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: layout.symbol).font(.system(size: 14, weight: .semibold))
                                    Text(layout.shortTitle).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            }
                            .buttonStyle(VideoSecondaryButtonStyle())
                            .help(L("Add “\(layout.title)” at the playhead"))
                        }
                    }
                    Button {
                        model.addCameraIntroOutro()
                    } label: {
                        Label(L("Full camera for intro & outro"), systemImage: "person.crop.rectangle.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                }
            }
        }
    }
}

extension VideoCameraInspector {
    /// Crop, roundness, border, and shadow (VideoCameraCropSheet.swift).
    @ViewBuilder
    var cameraLook: some View {
        let webcam = model.project.webcam
        VideoInspectorSection(L("Look")) {
            HStack(spacing: 8) {
                Button {
                    cropPicture = model.cameraStill()
                    if cropPicture == nil { model.showNotice(L("Move the playhead to where the camera shows, then crop"), symbol: "video") }
                } label: {
                    Label(webcam.effectiveCrop == nil ? L("Crop…") : L("Edit Crop…"), systemImage: "crop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                if webcam.effectiveCrop != nil {
                    Button(L("Reset Crop")) { model.setStyle { $0.webcam.crop = nil } }
                        .buttonStyle(VideoSecondaryButtonStyle())
                }
            }
            VideoSliderRow(
                title: L("Roundness"),
                value: Binding(get: { webcam.effectiveRoundness }, set: { value in model.setStyle(coalesce: "webcam-roundness") { $0.webcam.roundness = value } }),
                range: 0...1,
                defaultValue: webcam.shape.roundness,
                format: { VideoEditorFormat.percent($0) },
                detail: L("From sharp corners to a circle"),
                onEditingEnded: { model.endGesture() }
            )
            .disabled(webcam.shape == .cutout)
            VideoToggleRow(
                title: L("Border"),
                isOn: Binding(get: { webcam.border != nil }, set: { on in model.setStyle { $0.webcam.border = on ? ($0.webcam.border ?? .standard) : nil } })
            )
            .disabled(webcam.shape == .cutout)
            if let border = webcam.border, webcam.shape != .cutout {
                HStack(spacing: 10) {
                    Text(L("Color"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Spacer()
                    ColorPicker("", selection: Binding(get: { Color(nsColor: border.color.nsColor) }, set: { color in
                        let rgba = VideoRGBA(nsColor: NSColor(color))
                        model.setStyle(coalesce: "webcam-border-color") { $0.webcam.border?.color = rgba }
                    }), supportsOpacity: false)
                    .labelsHidden()
                }
                VideoSliderRow(
                    title: L("Thickness"),
                    value: Binding(get: { border.width }, set: { value in model.setStyle(coalesce: "webcam-border-width") { $0.webcam.border?.width = value } }),
                    range: VideoWebcamSettings.Border.widthRange,
                    defaultValue: VideoWebcamSettings.Border.standard.width,
                    format: { VideoEditorFormat.percent(($0 - VideoWebcamSettings.Border.widthRange.lowerBound) / (VideoWebcamSettings.Border.widthRange.upperBound - VideoWebcamSettings.Border.widthRange.lowerBound)) },
                    onEditingEnded: { model.endGesture() }
                )
            }
            VideoSliderRow(
                title: L("Shadow"),
                value: Binding(get: { webcam.shadowStrength ?? VideoWebcamSettings.defaultShadowStrength }, set: { value in model.setStyle(coalesce: "webcam-shadow") { $0.webcam.shadowStrength = value } }),
                range: 0...1,
                defaultValue: VideoWebcamSettings.defaultShadowStrength,
                format: { VideoEditorFormat.percent($0) },
                onEditingEnded: { model.endGesture() }
            )
        }
        .disabled(!webcam.visible)
        .sheet(isPresented: Binding(get: { cropPicture != nil }, set: { if !$0 { cropPicture = nil } })) {
            if let cropPicture {
                VideoCameraCropSheet(model: model, picture: cropPicture)
            }
        }
    }
}

/// Eight spots around a mini frame.
struct VideoAnchorPicker: View {
    @Binding var selection: VideoWebcamSettings.Anchor

    var body: some View {
        let size = CGSize(width: 150, height: 88)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(VideoEditorTheme.well)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
                .frame(width: size.width, height: size.height)
            ForEach(VideoWebcamSettings.Anchor.allCases) { anchor in
                let selected = anchor == selection
                let inset: CGFloat = 16
                let point = CGPoint(
                    x: inset + (size.width - inset * 2) * anchor.unit.x,
                    y: inset + (size.height - inset * 2) * anchor.unit.y
                )
                Button {
                    selection = anchor
                } label: {
                    Circle()
                        .fill(selected ? VideoEditorTheme.camera : VideoEditorTheme.ink.opacity(0.22))
                        .frame(width: selected ? 16 : 10, height: selected ? 16 : 10)
                        .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(point)
                .help(anchor.title)
                .accessibilityLabel(anchor.title)
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selection)
    }
}

/// Camera shape: the outline and ratio, Free for any (VideoFeatures.swift).
struct VideoCameraShapeMenu: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        let webcam = model.project.webcam
        HStack(spacing: 10) {
            Text(L("Camera shape"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VideoEditorTheme.textPrimary)
                .fixedSize()
            Menu {
                ForEach(VideoWebcamSettings.Shape.allCases) { shape in
                    Button {
                        model.setStyle { $0.webcam.choose(shape: shape) }
                    } label: {
                        Label(shape.title, systemImage: shape == webcam.shape ? "checkmark" : shape.symbol)
                    }
                }
            } label: {
                Label(webcam.shape.title, systemImage: webcam.shape.symbol)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(L("Camera shape"))
            Spacer(minLength: 0)
            if webcam.shape == .free {
                // The ratio it's dragged to, like 1.25:1.
                Text(VideoEditorFormat.ratio(webcam.effectiveAspect))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .help(L("Drag the camera's edges on the video to change its width and height."))
            }
        }
    }
}

/// Layout: Bubble, Split screen, Screen only or Camera only, and Split
/// screen's options (VideoSplitScreen.swift).
struct VideoCameraLayoutSection: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        let webcam = model.project.webcam
        let choice = VideoRecordingCameraSetup.LayoutChoice.of(webcam)
        let sideBySide = VideoSplitLayout.isSideBySide(webcam.effectiveSplit, in: model.plan.outputCanvasSize)
        VideoInspectorSection(L("Layout")) {
            VideoSegmented(
                options: VideoRecordingCameraSetup.LayoutChoice.allCases.map { ($0, $0.title) },
                selection: Binding(get: { choice }, set: { newChoice in model.setStyle { $0.webcam = newChoice.applied(to: $0.webcam) } })
            )
            if choice == .split {
                let split = webcam.effectiveSplit
                HStack(spacing: 10) {
                    Text(L("Direction"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                        .fixedSize()
                    // Chosen once, kept for every ratio (Adapt too).
                    VideoSegmented(
                        options: VideoWebcamSettings.Split.Direction.allCases.map { ($0, $0.title) },
                        selection: Binding(get: { sideBySide ? .sideBySide : .stacked }, set: { direction in model.setStyle { $0.webcam.split = $0.webcam.effectiveSplit; $0.webcam.split?.direction = direction } })
                    )
                }
                HStack(spacing: 10) {
                    Text(L("Camera side"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                        .fixedSize()
                    VideoSegmented(
                        options: VideoWebcamSettings.Split.Side.allCases.map { ($0, $0.title(sideBySide: sideBySide)) },
                        selection: Binding(get: { split.cameraSide }, set: { side in model.setStyle { $0.webcam.split = $0.webcam.effectiveSplit; $0.webcam.split?.cameraSide = side } })
                    )
                }
                VideoSliderRow(
                    title: L("Split size"),
                    value: Binding(get: { split.keptShare }, set: { value in model.setStyle(coalesce: "split-share") { $0.webcam.split = $0.webcam.effectiveSplit; $0.webcam.split?.cameraShare = value } }),
                    range: VideoWebcamSettings.Split.shareRange,
                    defaultValue: 0.5,
                    format: { L("Camera \(VideoEditorFormat.percent($0))") },
                    onEditingEnded: { model.endGesture() }
                )
                VideoSliderRow(
                    title: L("Gap"),
                    value: Binding(get: { split.keptGap }, set: { value in model.setStyle(coalesce: "split-gap") { $0.webcam.split = $0.webcam.effectiveSplit; $0.webcam.split?.gap = value } }),
                    range: VideoWebcamSettings.Split.gapRange,
                    defaultValue: 0,
                    format: { $0 < 0.0005 ? L("None") : VideoEditorFormat.percent($0 / VideoWebcamSettings.Split.gapRange.upperBound) },
                    onEditingEnded: { model.endGesture() }
                )
                Text(L("Drag the divider on the video to change the split; the background (Style) shows in the gap."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if choice == .screenOnly {
                Text(L("The camera is still in the recording: choose another layout to show it."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
