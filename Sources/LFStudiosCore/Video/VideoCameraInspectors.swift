import SwiftUI

/// Keep face centered, Hide camera during silences, and Color — the
/// Camera panel's sections for these.
struct VideoCameraExtrasSections: View {
    @ObservedObject var model: VideoEditorModel
    @AppStorage("videoCameraSilenceMinimum") private var silenceMinimum = VideoCameraSilence.defaultMinimum

    private var tracking: VideoFaceTracking? { model.project.faceTracking }
    private var color: VideoCameraColor { model.project.webcam.color ?? VideoCameraColor() }

    var body: some View {
        faceSection
        silenceSection
        colorSection
    }

    // MARK: Face

    @ViewBuilder
    private var faceSection: some View {
        VideoInspectorSection(L("Face tracking")) {
            if let progress = model.faceAnalysisProgress {
                HStack(spacing: 10) {
                    ProgressView(value: progress)
                        .controlSize(.small)
                    Text(VideoEditorFormat.percent(progress))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                    Button(L("Cancel")) { model.cancelFaceAnalysis() }
                        .controlSize(.small)
                }
                hint(L("Looking for your face in the camera video. This happens once; the result is kept."))
            } else if let tracking {
                VideoToggleRow(
                    title: L("Keep face centered"),
                    detail: L("The bubble's framing follows your face"),
                    isOn: Binding(get: { tracking.enabled }, set: { on in
                        if on, !model.hasFaceAnalysis { model.keepFaceCentered() } else { model.setFaceTracking { $0.enabled = on } }
                    })
                )
                Group {
                    VideoSliderRow(
                        title: L("Smoothness"),
                        value: Binding(get: { tracking.smoothness }, set: { value in model.setFaceTracking(coalesce: "face-smooth") { $0.smoothness = value } }),
                        range: VideoFaceTracking.smoothnessRange,
                        defaultValue: VideoFaceTracking().smoothness,
                        format: { VideoEditorFormat.percent($0) },
                        detail: L("Higher glides calmly after you; lower keeps up with quick moves"),
                        onEditingEnded: { model.endGesture() }
                    )
                    VideoSliderRow(
                        title: L("Framing"),
                        value: Binding(get: { tracking.tightness }, set: { value in model.setFaceTracking(coalesce: "face-tight") { $0.tightness = value } }),
                        range: VideoFaceTracking.tightnessRange,
                        defaultValue: VideoFaceTracking().tightness,
                        format: { $0 < 0.34 ? L("Loose") : ($0 > 0.66 ? L("Tight") : L("Medium")) },
                        detail: L("How much of the bubble your face fills"),
                        onEditingEnded: { model.endGesture() }
                    )
                }
                .disabled(!tracking.enabled)
            } else {
                Button {
                    model.keepFaceCentered()
                } label: {
                    Label(L("Keep face centered"), systemImage: "face.smiling")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                hint(L("Finds your face in the camera video on this Mac, then the bubble's framing follows it. Where no face is found, it keeps the last good framing."))
            }
        }
    }

    // MARK: Silences

    private var silenceSection: some View {
        VideoInspectorSection(L("Silences")) {
            Button {
                model.hideCameraDuringSilences(minimum: silenceMinimum)
            } label: {
                Label(L("Hide camera during silences"), systemImage: "video.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            VideoSliderRow(
                title: L("Minimum silence"),
                value: $silenceMinimum,
                range: VideoCameraSilence.minimumRange,
                defaultValue: VideoCameraSilence.defaultMinimum,
                format: { VideoEditorModel.formatTenths($0) },
                onEditingEnded: {}
            )
            hint(L("Adds a Camera hidden block for each pause at least this long. Drag or delete them on the Camera lane; pressing again replaces only these."))
        }
    }

    // MARK: Color

    private func colorBinding(_ path: WritableKeyPath<VideoCameraColor, Double>, _ key: String) -> Binding<Double> {
        Binding(get: { color[keyPath: path] }, set: { value in model.setCameraColor(coalesce: "camera-color-\(key)") { $0[keyPath: path] = value } })
    }

    private func slider(_ title: String, _ path: WritableKeyPath<VideoCameraColor, Double>, _ key: String, _ range: ClosedRange<Double>, neutral: Double, format: @escaping (Double) -> String) -> some View {
        VideoSliderRow(
            title: title,
            value: colorBinding(path, key),
            range: range,
            defaultValue: neutral,
            format: format,
            onEditingEnded: { model.endGesture() }
        )
    }

    private func signed(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return percent > 0 ? "+\(percent)" : "\(percent)"
    }

    private var colorSection: some View {
        VideoInspectorSection(L("Color")) {
            HStack(spacing: 6) {
                ForEach(VideoCameraColor.Look.allCases) { look in
                    let selected = color.look == look
                    Button {
                        model.applyCameraLook(look)
                    } label: {
                        Text(look.title)
                            .font(.system(size: 11, weight: selected ? .bold : .semibold))
                            .foregroundStyle(selected ? Color.white : VideoEditorTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? VideoEditorTheme.accent : VideoEditorTheme.card))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            slider(L("Brightness"), \.brightness, "brightness", VideoCameraColor.brightnessRange, neutral: 0) { signed($0 / 0.3) }
            slider(L("Contrast"), \.contrast, "contrast", VideoCameraColor.contrastRange, neutral: 1) { signed($0 - 1) }
            slider(L("Saturation"), \.saturation, "saturation", VideoCameraColor.saturationRange, neutral: 1) { signed($0 - 1) }
            slider(L("Warmth"), \.warmth, "warmth", VideoCameraColor.warmthRange, neutral: 0) { signed($0) }
            slider(L("Tint"), \.tint, "tint", VideoCameraColor.tintRange, neutral: 0) { signed($0) }
            slider(L("Sharpness"), \.sharpness, "sharpness", VideoCameraColor.sharpnessRange, neutral: 0) { VideoEditorFormat.percent($0) }
            HStack(spacing: 8) {
                Button {
                    model.autoAdjustCameraColor()
                } label: {
                    Label(L("Auto adjust"), systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .disabled(model.isAutoAdjustingColor)
                Button {
                    model.resetCameraColor()
                } label: {
                    Text(L("Reset"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .disabled(model.project.webcam.color == nil)
            }
            hint(L("For the camera only; the screen stays as recorded."))
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(VideoEditorTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
