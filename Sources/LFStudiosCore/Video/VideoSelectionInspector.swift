import AppKit
import SwiftUI

// MARK: - Selection

private struct VideoSelectionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct VideoSelectionInspector: View {
    @ObservedObject var model: VideoEditorModel
    /// The most room it takes above the tab (it scrolls past that).
    var maxHeight: CGFloat = .infinity
    @FocusState private var textFocused: Bool
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(16)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: VideoSelectionHeightKey.self, value: proxy.size.height)
                })
            }
            // As tall as its settings, up to the limit.
            .frame(height: min(max(contentHeight, 40), max(maxHeight - 51, 80)))
            .onPreferenceChange(VideoSelectionHeightKey.self) { contentHeight = $0 }
        }
        .background(VideoEditorTheme.ink.opacity(0.02))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Selected \(headerTitle)"))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(headerTint)
                .padding(.leading, 6)
                .accessibilityHidden(true)
            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textPrimary)
            Spacer()
            Button {
                model.deleteSelection()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(VideoToolButtonStyle(destructive: true))
            .help(L("Delete (⌫)"))
            .accessibilityLabel(L("Delete"))
            Button {
                model.selection = .none
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(VideoToolButtonStyle())
            .help(L("Done (Esc)"))
            .accessibilityLabel(L("Done"))
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
    }

    private var headerTitle: String {
        if !model.extraSelection.isEmpty { return L("\(model.selectedItems.count) selected") }
        switch model.selection {
        case .zoom: return L("Zoom")
        case .clip(let id): return L("Clip \((model.segments.firstIndex { $0.id == id } ?? 0) + 1)")
        case .overlay: return model.selectedOverlay?.kind.title ?? L("Annotation")
        case .click: return L("Click")
        case .caption: return L("Caption")
        case .keystroke: return L("Shortcut")
        case .cameraLayout: return L("Camera layout")
        case .layer: return model.selectedLayerItem?.name ?? L("Clip")
        case .range(let range): return L("Selected \(VideoEditorModel.format(range.duration))")
        case .none: return ""
        }
    }

    private var headerSymbol: String {
        if !model.extraSelection.isEmpty { return "square.stack.3d.up" }
        switch model.selection {
        case .zoom: return "plus.magnifyingglass"
        case .clip: return "film"
        case .overlay: return model.selectedOverlay?.kind.icon ?? "text.bubble"
        case .click: return "cursorarrow.click.2"
        case .caption: return "captions.bubble"
        case .keystroke: return "keyboard"
        case .cameraLayout: return "person.crop.rectangle"
        case .layer: return model.selectedLayerItem?.isVideo == true ? "film" : "photo"
        case .range: return "selection.pin.in.out"
        case .none: return ""
        }
    }

    private var headerTint: Color {
        switch model.selection {
        case .zoom: return VideoEditorTheme.zoom
        case .clip: return VideoEditorTheme.clip
        case .overlay: return model.selectedOverlay.map { VideoEditorTheme.overlayTint($0.kind) } ?? VideoEditorTheme.textSecondary
        case .range: return Color.red
        case .caption: return VideoEditorTheme.caption
        case .keystroke: return VideoEditorTheme.keys
        case .cameraLayout: return VideoEditorTheme.camera
        case .layer: return VideoEditorTheme.layer
        default: return VideoEditorTheme.textSecondary
        }
    }

    @ViewBuilder
    private var content: some View {
        if !model.extraSelection.isEmpty {
            multipleContent
        } else {
            singleContent
        }
    }

    /// Several items: what they are, and what can be done with all of them.
    private var multipleContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            let counts = Dictionary(grouping: model.selectedItems, by: ItemKind.init).map { Self.count($0.value.count, of: $0.key) }.sorted()
            Text(counts.joined(separator: " · "))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textPrimary)
            Text(L("Drag one of them on the timeline to move them all together; ⌫ removes them all. ⇧- or ⌘-click adds or takes one out."))
                .font(.system(size: 11))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive) {
                model.deleteSelectedItems()
            } label: {
                Label(L("Remove all \(model.selectedItems.count)"), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle(destructive: true))
        }
    }

    private enum ItemKind: Hashable {
        case zoom, clip, annotation, click, caption, shortcut, cameraLayout, part

        init(_ item: VideoEditorModel.Selection) {
            switch item {
            case .zoom: self = .zoom
            case .clip, .layer: self = .clip
            case .overlay: self = .annotation
            case .click: self = .click
            case .caption: self = .caption
            case .keystroke: self = .shortcut
            case .cameraLayout: self = .cameraLayout
            case .range, .none: self = .part
            }
        }
    }

    /// "2 zooms", "1 clip": one whole phrase for each kind, so each
    /// language puts the number and the plural where it belongs.
    private static func count(_ count: Int, of kind: ItemKind) -> String {
        switch kind {
        case .zoom: return L("\(count) zooms")
        case .clip: return L("\(count) clips")
        case .annotation: return L("\(count) annotations")
        case .click: return L("\(count) clicks")
        case .caption: return L("\(count) captions")
        case .shortcut: return L("\(count) shortcuts")
        case .cameraLayout: return L("\(count) camera layouts")
        case .part: return L("\(count) parts")
        }
    }

    @ViewBuilder
    private var singleContent: some View {
        switch model.selection {
        case .zoom(let id):
            if let zoom = model.project.zoomRegions.first(where: { $0.id == id }) {
                zoomEditor(zoom)
            }
        case .clip(let id):
            if let segment = model.segments.first(where: { $0.id == id }) {
                clipEditor(segment)
            }
        case .overlay(let id):
            if let overlay = model.project.overlayEffects.first(where: { $0.id == id }) {
                overlayEditor(overlay)
            }
        case .click(let id):
            if let click = model.project.clickEvents.first(where: { $0.id == id }) {
                Text(L("Recorded at \(VideoEditorModel.timecode(model.timelineTime(forSource: click.time) ?? click.time)). Drag its dot on the timeline to retime it; ripples and Auto Zoom follow."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .caption(let id):
            if let line = model.project.captions.first(where: { $0.id == id }) {
                captionEditor(line)
            }
        case .keystroke(let id):
            if let event = model.project.keystrokes.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(event.keys.joined(separator: " "))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Text(L("Pressed at \(VideoEditorModel.timecode(model.timelineTime(forSource: event.time) ?? event.time)). Press ⌫ to hide it from the video — handy for a stray ⌘Tab."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .layer(let id):
            if let item = model.project.layerItem(id) {
                VideoLayerItemEditor(model: model, clock: model.clock, item: item)
            }
        case .cameraLayout(let id):
            if let region = model.project.cameraLayouts.first(where: { $0.id == id }) {
                VideoInspectorSection(L("Layout")) {
                    ForEach(VideoCameraLayoutRegion.Layout.allCases) { layout in
                        Button {
                            model.setCameraLayout(id, to: layout)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: layout.symbol)
                                    .frame(width: 20)
                                Text(layout.title)
                                Spacer()
                                if region.layout == layout {
                                    Image(systemName: "checkmark").foregroundStyle(VideoEditorTheme.camera)
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VideoEditorTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(region.layout == layout ? VideoEditorTheme.camera.opacity(0.18) : VideoEditorTheme.ink.opacity(0.04)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(L("Drag the block on the Camera lane to move it, or its edges to change how long it lasts. Each change eases in and out."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .range(let range):
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: "\(VideoEditorModel.timecode(range.start)) → \(VideoEditorModel.timecode(range.end))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Button {
                    model.deleteRange(range)
                } label: {
                    Label(L("Cut this part"), systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoPrimaryButtonStyle())
                Text(L("Removed parts can be restored from the yellow marker on the timeline."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
            }
            // Or change just this part.
            VideoInspectorSection(L("Speed of this part")) {
                let current = model.rangeSpeed(range)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach([0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 8.0, 16.0], id: \.self) { speed in
                        let selected = current.map { abs($0 - speed) < 0.01 } ?? false
                        Button {
                            model.setRangeSpeed(range, speed)
                        } label: {
                            Text(VideoEditorModel.formatScale(speed))
                                .font(.system(size: 11.5, weight: selected ? .bold : .semibold))
                                .foregroundStyle(selected ? Color.black : VideoEditorTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? VideoEditorTheme.clip : VideoEditorTheme.card))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("\(VideoEditorModel.formatScale(speed)) speed"))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            VideoInspectorSection(L("Sound")) {
                VideoToggleRow(title: L("Mute this part"), isOn: Binding(get: { model.rangeIsMuted(range) }, set: { _ in model.toggleRangeMute(range) }))
            }
        case .none:
            EmptyView()
        }
    }

    // MARK: Caption

    @ViewBuilder
    private func captionEditor(_ line: VideoCaptionLine) -> some View {
        VideoInspectorSection(L("Text")) {
            TextField(L("Caption"), text: Binding(get: { line.text }, set: { model.updateCaption(line.id, text: $0) }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(2...6)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VideoEditorTheme.well))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
                .focused($textFocused)
                .onSubmit { model.endGesture() }
        }
        VideoInspectorSection(L("Timing")) {
            timingRow(L("Starts"), time: line.start) { model.setCaptionTiming(line.id, start: $0) }
            timingRow(L("Ends"), time: line.end) { model.setCaptionTiming(line.id, end: $0) }
            Button {
                let now = model.sourceTime(forTimeline: model.clock.time)
                model.setCaptionTiming(line.id, start: now, end: max(line.end, now + 0.5))
                model.endGesture()
            } label: {
                Label(L("Start at the playhead"), systemImage: "arrow.right.to.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
        }
    }

    private func timingRow(_ title: String, time: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VideoEditorTheme.textPrimary)
            Spacer()
            Button {
                set(time - 0.1)
                model.endGesture()
            } label: {
                Image(systemName: "minus").font(.system(size: 9, weight: .bold)).frame(width: 22, height: 20)
            }
            .buttonStyle(VideoToolButtonStyle())
            .help(L("0.1s earlier"))
            Text(VideoEditorModel.timecode(model.timelineTime(forSource: time) ?? time))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .frame(minWidth: 52)
            Button {
                set(time + 0.1)
                model.endGesture()
            } label: {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold)).frame(width: 22, height: 20)
            }
            .buttonStyle(VideoToolButtonStyle())
            .help(L("0.1s later"))
        }
    }

    // MARK: Zoom

    @ViewBuilder
    private func zoomEditor(_ zoom: VideoZoomRegion) -> some View {
        VideoInspectorSection(L("Zoom level")) {
            VideoSliderRow(
                title: L("Level"),
                value: Binding(get: { zoom.scale }, set: { value in model.updateZoom(zoom.id, coalesce: "scale-\(zoom.id)") { $0.scale = value } }),
                range: VideoZoomRegion.scaleRange,
                defaultValue: model.project.defaultZoomScale,
                format: { VideoEditorModel.formatScale($0) },
                onEditingEnded: { model.endGesture() }
            )
            HStack(spacing: 6) {
                ForEach([1.5, 2.0, 2.5, 3.0], id: \.self) { value in
                    let selected = abs(zoom.scale - value) < 0.02
                    Button {
                        model.updateZoom(zoom.id) { $0.scale = value }
                    } label: {
                        Text(VideoEditorModel.formatScale(value))
                            .font(.system(size: 11.5, weight: selected ? .bold : .semibold))
                            .foregroundStyle(selected ? Color.white : VideoEditorTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? VideoEditorTheme.zoom : VideoEditorTheme.card))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Zoom to \(VideoEditorModel.formatScale(value)) (key \([1.5: "2", 2.0: "3", 2.5: "4", 3.0: "5"][value] ?? ""))"))
                }
            }
            Button {
                model.applyZoomScaleToAll(zoom.scale)
            } label: {
                Text(L("Use this level for every zoom"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
        }

        VideoZoomBlockControls(model: model, zoom: zoom)

        if let range = model.zoomTimelineRange(zoom) {
            VideoInspectorSection(L("Timing")) {
                HStack {
                    Text(verbatim: "\(VideoEditorModel.timecode(range.lowerBound)) → \(VideoEditorModel.timecode(range.upperBound))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Spacer()
                    Text(VideoEditorModel.format(range.upperBound - range.lowerBound))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                }
                Button {
                    model.duplicateZoom(zoom.id)
                } label: {
                    Label(L("Duplicate"), systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            }
        }
    }

    // MARK: Clip

    @ViewBuilder
    private func clipEditor(_ segment: VideoDemoTimelineSegment) -> some View {
        // Normal or Curve (VideoSpeed.swift, 1.15.0).
        VideoClipSpeedSection(model: model, segment: segment)
        // Zoom cut's keyframes (VideoZoomCut.swift, 1.16.0).
        VideoClipZoomSection(model: model, clock: model.clock, segment: segment)

        VideoInspectorSection(L("Sound")) {
            VideoToggleRow(title: L("Mute this clip"), isOn: Binding(get: { segment.clip.muted }, set: { model.setClipMuted(segment.id, $0) }))
            VideoSliderRow(
                title: L("Fade in"),
                value: Binding(get: { segment.clip.fadeIn }, set: { model.setClipFade(segment.id, fadeIn: $0) }),
                range: 0...max(min(segment.duration / 2, 3), 0.1),
                defaultValue: 0,
                format: { VideoEditorModel.format($0) },
                onEditingEnded: { model.endGesture() }
            )
            VideoSliderRow(
                title: L("Fade out"),
                value: Binding(get: { segment.clip.fadeOut }, set: { model.setClipFade(segment.id, fadeOut: $0) }),
                range: 0...max(min(segment.duration / 2, 3), 0.1),
                defaultValue: 0,
                format: { VideoEditorModel.format($0) },
                onEditingEnded: { model.endGesture() }
            )
        }

        // How the cut into this clip plays (VideoTransitions.swift).
        VideoClipTransitionSection(model: model, segment: segment)

        VideoInspectorSection(L("Edit")) {
            HStack(spacing: 8) {
                Button {
                    model.trimSelectedClipToPlayhead(leading: true)
                } label: {
                    Label(L("Start here"), systemImage: "arrow.left.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("Trim the clip's start to the playhead (Q)"))
                Button {
                    model.trimSelectedClipToPlayhead(leading: false)
                } label: {
                    Label(L("End here"), systemImage: "arrow.right.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("Trim the clip's end to the playhead (W)"))
            }
            Button {
                model.splitAtPlayhead()
            } label: {
                Label(L("Split at playhead"), systemImage: "scissors")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            if let index = model.segments.firstIndex(where: { $0.id == segment.id }), model.segments.count > 1 {
                // Or drag the clip by its name on the timeline.
                HStack(spacing: 8) {
                    Button {
                        model.moveClip(segment.id, toIndex: index - 1)
                    } label: {
                        Label(L("Move earlier"), systemImage: "arrow.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .disabled(index == 0)
                    Button {
                        model.moveClip(segment.id, toIndex: index + 1)
                    } label: {
                        Label(L("Move later"), systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .disabled(index >= model.segments.count - 1)
                }
            }
        }
    }

    // MARK: Overlay

    @ViewBuilder
    private func overlayEditor(_ overlay: VideoDemoOverlayEffect) -> some View {
        VideoMoveToTrackButton(model: model, overlay: overlay)
        if overlay.kind == .image {
            VideoImageOverlayInspector(model: model, overlay: overlay)
        }
        if overlay.kind == .text {
            VideoInspectorSection(L("Text")) {
                TextField(L("Text"), text: Binding(get: { overlay.text }, set: { value in model.updateOverlay(overlay.id, coalesce: "text-\(overlay.id)") { $0.text = value } }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1...4)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.well))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
                    .focused($textFocused)
                    .onChange(of: model.textEditRequest) { _ in textFocused = true }
                // The size of the letters, apart from the box's width.
                VideoSliderRow(
                    title: L("Size"),
                    value: Binding(get: { model.textSize(of: overlay) }, set: { model.setTextSize($0, of: overlay.id) }),
                    range: 14...64,
                    format: { "\(Int($0.rounded()))" },
                    onEditingEnded: { model.endGesture() }
                )
                VideoFontPicker(model: model, choice: Binding(get: { overlay.font }, set: { font in model.updateOverlay(overlay.id) { $0.font = font } }))
            }
        }
        if overlay.kind.hasColor {
            VideoInspectorSection(overlay.kind == .text ? L("Tag color") : L("Color")) {
                VideoOverlayColorPicker(model: model, overlay: overlay)
            }
        }
        if overlay.kind == .arrow || overlay.kind == .highlight {
            VideoInspectorSection(L("Thickness")) {
                VideoSegmented(
                    options: VideoOverlayThickness.allCases.map { ($0, $0.title) },
                    selection: Binding(get: { overlay.thickness }, set: { model.setOverlayThickness(overlay.id, $0) })
                )
            }
        }
        if overlay.kind == .arrow {
            Button {
                model.flipArrow(overlay.id)
            } label: {
                Label(L("Turn around"), systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .help(L("Swap the arrow's head and tail"))
        }
        if overlay.kind == .blur {
            VideoInspectorSection(L("Blur")) {
                VideoSliderRow(
                    title: L("Strength"),
                    value: Binding(get: { overlay.blurStrength }, set: { model.setBlurStrength($0, of: overlay.id) }),
                    range: VideoDemoOverlayEffect.blurStrengthRange,
                    defaultValue: 1,
                    format: { VideoEditorFormat.percent($0) },
                    onEditingEnded: { model.endGesture() }
                )
            }
        }
        if overlay.kind == .spotlight {
            VideoInspectorSection(L("Shape")) {
                VideoSegmented(
                    options: VideoOverlayShape.allCases.map { ($0, $0.title) },
                    selection: Binding(get: { overlay.shape ?? .rectangle }, set: { model.setOverlayShape(overlay.id, $0) })
                )
            }
        }
        // Images have their own placement controls (VideoImageOverlays.swift).
        if overlay.kind != .image {
            VideoInspectorSection(L("Placement")) {
                Text(placementHelp(overlay.kind))
                    .font(.system(size: 11))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func placementHelp(_ kind: VideoDemoOverlayEffectKind) -> String {
        switch kind {
        case .blur: return L("Drag the box on the preview over anything private. Blur follows zooms and stays until its bar ends.")
        case .arrow: return L("Drag the arrow on the preview to move it; drag its head or tail to point it anywhere. Its bar on the timeline sets when it shows.")
        case .spotlight: return L("Drag the spot on the preview; drag a corner to resize it. Everything around it dims while its bar on the timeline runs.")
        case .text: return L("Drag it on the preview to move it; drag a corner to resize; double-click it to type. Its bar on the timeline sets when it shows.")
        default: return L("Drag it on the preview to move it; drag a corner to resize. Its bar on the timeline sets when it shows.")
        }
    }
}
