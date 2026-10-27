import AppKit
import SwiftUI

// MARK: - Zoom panel buttons

/// Typing zooms, loupes, and fitting zooms around the camera: buttons in
/// the Zoom panel, each one ⌘Z step.
struct VideoZoomToolsCard: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        VideoCard {
            Button {
                model.addTypingZooms()
            } label: {
                Label(L("Add typing zooms"), systemImage: "character.cursor.ibeam")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .disabled(!model.hasTypingPositions)
            .help(L("Zooms that follow the text cursor while you type"))
            Text(model.hasTypingPositions
                 ? L("Follows where you typed. Pressing it again replaces only these zooms.")
                 : L("Record with “Track where I type” on (Settings → Recording) to zoom in on typing."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.addLoupe()
            } label: {
                Label(L("Add Loupe"), systemImage: "magnifyingglass.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .help(L("A magnifier over one spot at the playhead; the rest of the frame stays in view"))

            VStack(alignment: .leading, spacing: 6) {
                Label(L("Fit zooms around camera"), systemImage: "person.crop.square")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                ForEach(VideoZoomCameraFit.Mode.allCases) { mode in
                    Button {
                        model.fitZoomsAroundCamera(mode)
                    } label: {
                        Text(mode.title)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                }
                Text(model.hasWebcamFootage
                     ? L("Finds zooms the camera bubble covers and moves their framing, or the bubble, out of the way")
                     : L("This video has no camera bubble"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!model.canFitZoomsAroundCamera)
        }
    }
}

// MARK: - One zoom block

/// Type, framing, and the loupe's look for the selected zoom.
struct VideoZoomBlockControls: View {
    @ObservedObject var model: VideoEditorModel
    let zoom: VideoZoomRegion

    var body: some View {
        VideoInspectorSection(L("Type")) {
            VideoSegmented(options: [(false, L("Full")), (true, L("Loupe"))], selection: Binding(
                get: { zoom.isLoupe },
                set: { model.setZoomIsLoupe(zoom.id, $0) }
            ))
            Text(zoom.isLoupe
                 ? L("A magnifier over one spot; the rest of the frame stays in view.")
                 : L("The whole frame zooms in."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
        }

        VideoInspectorSection(L("Framing")) {
            let follows: [VideoZoomFollow] = model.hasTypingPositions || zoom.followsTyping ? [.pointer, .typing, .fixed] : [.pointer, .fixed]
            VideoSegmented(options: follows.map { ($0, $0.title) }, selection: Binding(
                get: { VideoZoomFollow(zoom) },
                set: { model.setZoomFollow(zoom.id, $0) }
            ))
            switch VideoZoomFollow(zoom) {
            case .pointer:
                hint(zoom.isLoupe ? L("The loupe stays over your cursor.") : L("The camera keeps your cursor in view and glides after it."))
            case .typing:
                hint(zoom.isLoupe ? L("The loupe stays over the text cursor.") : L("The camera follows the text cursor as you type."))
            case .fixed:
                hint(L("Drag the frame on the preview to aim; drag its corners to zoom in or out."))
                Button {
                    model.updateZoom(zoom.id) { $0.focusX = 0.5; $0.focusY = 0.5 }
                } label: {
                    Text(L("Center"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            }
            if zoom.offsetX != 0 || zoom.offsetY != 0 || zoom.cameraCorner != nil {
                hint(zoom.cameraCorner.map { L("While this zoom plays, the camera bubble moves to: \($0.title)") } ?? L("Moved clear of the camera bubble."))
                Button {
                    model.updateZoom(zoom.id) { region in
                        region.offsetX = 0
                        region.offsetY = 0
                        region.cameraCorner = nil
                    }
                } label: {
                    Text(L("Undo camera fit"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            }
        }

        if let loupe = zoom.loupe {
            VideoInspectorSection(L("Loupe")) {
                VideoSliderRow(
                    title: L("Size"),
                    value: binding(\.size, "size"),
                    range: VideoLoupeStyle.sizeRange,
                    defaultValue: VideoLoupeStyle().size,
                    format: { VideoEditorFormat.percent($0) },
                    onEditingEnded: { model.endGesture() }
                )
                VideoSegmented(options: VideoLoupeStyle.Shape.allCases.map { ($0, $0.title) }, selection: Binding(
                    get: { loupe.shape },
                    set: { shape in model.updateLoupe(zoom.id) { $0.shape = shape } }
                ))
                VideoSliderRow(
                    title: L("Border"),
                    value: binding(\.borderWidth, "border"),
                    range: VideoLoupeStyle.borderRange,
                    defaultValue: VideoLoupeStyle().borderWidth,
                    format: { $0 < 0.0005 ? L("None") : VideoEditorFormat.percent($0 / VideoLoupeStyle.borderRange.upperBound) },
                    onEditingEnded: { model.endGesture() }
                )
                HStack(spacing: 10) {
                    Text(L("Border color"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Spacer()
                    ColorPicker(L("Border color"), selection: Binding(get: { Color(nsColor: loupe.borderColor.nsColor) }, set: { color in
                        let rgba = VideoRGBA(nsColor: NSColor(color))
                        model.updateLoupe(zoom.id, coalesce: "loupe-color-\(zoom.id)") { $0.borderColor = rgba }
                    }), supportsOpacity: false)
                    .labelsHidden()
                }
                VideoSliderRow(
                    title: L("Shadow"),
                    value: binding(\.shadow, "shadow"),
                    range: 0...1,
                    defaultValue: VideoLoupeStyle().shadow,
                    format: { VideoEditorFormat.percent($0) },
                    onEditingEnded: { model.endGesture() }
                )
                VideoSliderRow(
                    title: L("Open and close"),
                    value: binding(\.animation, "animation"),
                    range: VideoLoupeStyle.animationRange,
                    defaultValue: VideoLoupeStyle().animation,
                    format: { VideoEditorModel.format($0) },
                    detail: L("How long the loupe takes to grow in and fade out"),
                    onEditingEnded: { model.endGesture() }
                )
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(VideoEditorTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func binding(_ path: WritableKeyPath<VideoLoupeStyle, Double>, _ key: String) -> Binding<Double> {
        Binding(
            get: { model.project.zoomRegions.first { $0.id == zoom.id }?.loupe?[keyPath: path] ?? 0 },
            set: { value in model.updateLoupe(zoom.id, coalesce: "loupe-\(key)-\(zoom.id)") { $0[keyPath: path] = value } }
        )
    }
}

// MARK: - Cursor style

struct VideoCursorStylePicker: View {
    @ObservedObject var model: VideoEditorModel

    private var cursor: VideoCursorSettings { model.project.cursor }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Style"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Spacer()
                Picker(L("Style"), selection: Binding(get: { cursor.style }, set: { model.setCursorStyle($0) })) {
                    ForEach(VideoCursorStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if cursor.style == .custom, let image = cursor.customImage {
                VideoCursorHotSpotPicker(model: model, image: image)
            } else if cursor.style != .classic {
                Text(L("Its own arrow, text and hand pointers, drawn for the video."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The custom pointer picture: click where it points.
struct VideoCursorHotSpotPicker: View {
    @ObservedObject var model: VideoEditorModel
    let image: VideoCursorImage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                GeometryReader { geometry in
                    let side = geometry.size
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(VideoEditorTheme.card)
                        if let picture = NSImage(contentsOfFile: image.path) {
                            Image(nsImage: picture)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: side.width, height: side.height)
                        }
                        Circle()
                            .stroke(Color.red, lineWidth: 1.5)
                            .background(Circle().fill(Color.red.opacity(0.35)))
                            .frame(width: 9, height: 9)
                            .offset(x: CGFloat(image.hotSpotX) * side.width - 4.5, y: CGFloat(image.hotSpotY) * side.height - 4.5)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        model.setCursorHotSpot(x: Double(value.location.x / max(side.width, 1)), y: Double(value.location.y / max(side.height, 1)))
                    }.onEnded { _ in model.endGesture() })
                }
                .frame(width: 64 * CGFloat(min(max(image.aspect, 0.5), 2)), height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(image.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(L("Click the picture where it points."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("Choose Another…")) { model.chooseCursorImage() }
                        .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Speeding up typing

struct VideoSpeedUpTypingButtons: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("Speed up typing to"), systemImage: "hare")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VideoEditorTheme.textPrimary)
            HStack(spacing: 6) {
                ForEach(VideoDemoProject.typingSpeeds, id: \.self) { speed in
                    Button {
                        model.speedUpTyping(speed)
                    } label: {
                        Text(VideoEditorModel.formatScale(speed))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(VideoEditorTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(VideoEditorTheme.card))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Finds typing and plays it faster, as speed blocks you can change"))
                }
            }
        }
    }
}

/// The Cursor panel's typing section.
struct VideoTypingSpeedSection: View {
    @ObservedObject var model: VideoEditorModel

    private var detail: String {
        if !model.project.keyPresses.isEmpty {
            return L("Uses the key timing saved with this recording (never which keys). Shortcut keycaps stay on screen long enough to read.")
        }
        if model.hasTypingPositions {
            return L("Uses where the text cursor moved while you typed.")
        }
        return L("This recording didn't save key timing, so typing is estimated from screen changes while the pointer holds still. Check the speed blocks it makes.")
    }

    var body: some View {
        VideoInspectorSection(L("Typing")) {
            VideoSpeedUpTypingButtons(model: model)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
