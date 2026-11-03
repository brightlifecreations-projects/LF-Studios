import AppKit
import SwiftUI

// MARK: - Background

struct VideoBackgroundInspector: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject private var swatches = VideoSwatchCache.shared
    @State private var kind: Kind = .wallpaper

    enum Kind: Hashable {
        case wallpaper, gradient, color, image
    }

    private var project: VideoDemoProject { model.project }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Saved looks (VideoStylePresetsMenu.swift).
            VideoStylePresetsSection(model: model)

            VideoInspectorSection(L("Background"), trailing: {
                Button {
                    model.shuffleBackground()
                } label: {
                    Image(systemName: "dice")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(L("Shuffle the background"))
                .accessibilityLabel(L("Shuffle the background"))
            }) {
                VideoSegmented(options: [(.wallpaper, L("Wallpaper")), (.gradient, L("Gradient")), (.color, L("Color")), (.image, L("Image"))], selection: $kind)
                swatchGrid
                if showsBlur {
                    VideoSliderRow(
                        title: L("Background blur"),
                        value: Binding(get: { project.backgroundBlur }, set: { value in model.setStyle(coalesce: "bg-blur") { $0.backgroundBlur = value } }),
                        range: 0...1,
                        defaultValue: 0,
                        format: { VideoEditorFormat.percent($0) },
                        onEditingEnded: { model.endGesture() }
                    )
                }
            }

            VideoInspectorSection(L("Frame")) {
                VideoSliderRow(
                    title: L("Padding"),
                    value: Binding(get: { project.padding }, set: { value in model.setStyle(coalesce: "padding") { $0.padding = value } }),
                    range: 0...0.25,
                    defaultValue: VideoStylePreset.factory.padding,
                    format: { "\(Int(($0 * 400).rounded()))" },
                    onEditingEnded: { model.endGesture() }
                )
                VideoSliderRow(
                    title: L("Roundness"),
                    value: Binding(get: { project.cornerRadius }, set: { value in model.setStyle(coalesce: "radius") { $0.cornerRadius = value } }),
                    range: 0...60,
                    defaultValue: VideoStylePreset.factory.cornerRadius,
                    format: { "\(Int($0.rounded()))" },
                    onEditingEnded: { model.endGesture() }
                )
                // The Shadow slider, or the fine-tuned shadow (VideoShadow.swift).
                VideoShadowControls(model: model)
                VideoToggleRow(
                    title: L("Edge highlight"),
                    detail: L("A hairline that separates dark recordings from the background"),
                    isOn: Binding(get: { project.outline }, set: { value in model.setStyle { $0.outline = value } })
                )
                Button {
                    model.setStyle { $0.toggleBackground() }
                } label: {
                    Label(project.usesRawSourceFrame ? L("Show background") : L("Full frame (no background)"), systemImage: project.usesRawSourceFrame ? "rectangle.inset.filled" : "rectangle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            }

            // Cards, transitions, and more recordings (each in its own file).
            VideoTitleCardsSection(model: model)
            VideoTransitionsSection(model: model)
            VideoSourcesSection(model: model)
        }
        .onAppear { kind = Self.kind(of: project.background) }
        // The dice, undo, or a reset can change it from outside.
        .onChange(of: project.background) { background in kind = Self.kind(of: background) }
    }

    private var showsBlur: Bool {
        switch project.background {
        case .wallpaper, .image, .systemWallpaper: return true
        default: return false
        }
    }

    static func kind(of background: VideoBackground) -> Kind {
        switch background {
        case .wallpaper, .systemWallpaper: return .wallpaper
        case .gradient: return .gradient
        case .color: return .color
        case .image: return .image
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    @ViewBuilder
    private var swatchGrid: some View {
        switch kind {
        case .wallpaper:
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(VideoBackgroundCatalog.wallpapers) { wallpaper in
                    swatch(.wallpaper(wallpaper.id), help: wallpaper.title)
                }
            }
            let system = swatches.systemWallpapers
            if !system.isEmpty {
                Text(L("From your Mac"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .padding(.top, 2)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(system, id: \.path) { url in
                        swatch(.systemWallpaper(url.path), help: url.deletingPathExtension().lastPathComponent)
                    }
                }
            }
        case .gradient:
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(VideoBackgroundCatalog.pickerGradients) { gradient in
                    swatch(.gradient(gradient.id), help: gradient.title)
                }
            }
        case .color:
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(VideoBackgroundCatalog.colors, id: \.self) { color in
                    swatch(.color(color), help: L("Solid color"))
                }
            }
            HStack {
                Text(L("Custom"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Spacer()
                ColorPicker(L("Custom color"), selection: Binding(
                    get: {
                        if case .color(let rgba) = project.background { return Color(nsColor: rgba.nsColor) }
                        return Color.white
                    },
                    set: { color in
                        let rgba = VideoRGBA(nsColor: NSColor(color))
                        model.setStyle(coalesce: "bg-color") { $0.background = .color(rgba.withAlpha(1)) }
                    }
                ), supportsOpacity: false)
                .labelsHidden()
            }
        case .image:
            VStack(alignment: .leading, spacing: 10) {
                if case .image(let path) = project.background {
                    ZStack(alignment: .topTrailing) {
                        if let image = swatches.image(for: project.background) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 110)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VideoEditorTheme.card).frame(height: 110)
                        }
                    }
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 10.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .lineLimit(1)
                }
                Button {
                    model.chooseBackgroundImage()
                } label: {
                    Label(L("Choose Image…"), systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            }
        }
    }

    private func swatch(_ background: VideoBackground, help: String) -> some View {
        let selected = project.background == background
        return Button {
            model.setStyle { $0.background = background }
        } label: {
            ZStack {
                if let image = swatches.image(for: background) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    VideoEditorTheme.ink.opacity(0.06)
                }
            }
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? VideoEditorTheme.ink : VideoEditorTheme.ink.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                    .padding(-3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Cursor

struct VideoCursorInspector: View {
    @ObservedObject var model: VideoEditorModel

    private var cursor: VideoCursorSettings { model.project.cursor }

    private func binding<T>(_ keyPath: WritableKeyPath<VideoCursorSettings, T>, coalesce: String? = nil) -> Binding<T> {
        Binding(get: { model.project.cursor[keyPath: keyPath] }, set: { value in model.setStyle(coalesce: coalesce) { $0.cursor[keyPath: keyPath] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.project.canRenderCursor {
                VideoCard {
                    Label(model.project.nativeCursorVisible ? L("The cursor is part of this video") : L("No cursor data in this video"), systemImage: "cursorarrow.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Text(model.project.nativeCursorVisible
                         ? L("It was recorded into the pixels, so it can't be resized or smoothed. New recordings capture an editable cursor by default (Settings → Recording).")
                         : L("Recordings made with LF Studios capture the pointer so it can be smoothed, resized, and hidden."))
                        .font(.system(size: 11))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VideoInspectorSection(L("Clicks")) {
                    VideoSegmented(options: VideoCursorSettings.ClickEffect.allCases.filter { $0 != .press }.map { ($0, $0.title) }, selection: binding(\.clickEffect))
                }
                VideoInspectorSection(L("Loop")) {
                    VideoToggleRow(
                        title: L("Return to start at the end"),
                        detail: L("Needs a cursor LF Studios draws — this one is part of the video"),
                        isOn: .constant(false)
                    )
                    .disabled(true)
                }
            } else {
                VideoInspectorSection(L("Cursor")) {
                    VideoToggleRow(title: L("Show cursor"), isOn: binding(\.visible))
                    VideoSliderRow(
                        title: L("Size"),
                        value: binding(\.size, coalesce: "cursor-size"),
                        range: VideoCursorSettings.sizeRange,
                        defaultValue: VideoCursorSettings().size,
                        format: { VideoEditorModel.formatScale($0) },
                        onEditingEnded: { model.endGesture() }
                    )
                }
                .disabled(false)

                VideoInspectorSection(L("Movement")) {
                    VideoSegmented(options: VideoCursorSettings.Smoothing.allCases.map { ($0, $0.title) }, selection: binding(\.smoothing))
                    Text(smoothingDetail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    VideoToggleRow(title: L("Motion blur"), detail: L("Soft streaks on fast moves"), isOn: binding(\.motionBlur))
                    VideoToggleRow(title: L("Hide when idle"), detail: L("Fades out after a moment without movement"), isOn: binding(\.hideWhenIdle))
                    VideoToggleRow(title: L("Hide the move to Stop"), detail: L("Skips the dash to the Stop button at the end"), isOn: binding(\.tidyEnding))
                }

                VideoInspectorSection(L("Loop")) {
                    VideoToggleRow(
                        title: L("Return to start at the end"),
                        detail: L("The pointer glides back to where it started, so the video loops without a jump"),
                        isOn: binding(\.returnToStart)
                    )
                    if cursor.returnToStart {
                        VideoSliderRow(
                            title: L("Glide time"),
                            value: binding(\.returnDuration, coalesce: "cursor-return"),
                            range: VideoCursorSettings.returnDurationRange,
                            defaultValue: VideoCursorSettings().returnDuration,
                            format: { VideoEditorModel.formatTenths($0) },
                            onEditingEnded: { model.endGesture() }
                        )
                    }
                }

                VideoInspectorSection(L("Clicks")) {
                    VideoSegmented(options: VideoCursorSettings.ClickEffect.allCases.map { ($0, $0.title) }, selection: binding(\.clickEffect))
                }

                VideoInspectorSection(L("Appearance")) {
                    VideoToggleRow(
                        title: L("Always show the arrow"),
                        detail: model.artwork.hasCapturedShapes ? L("Never switch to the text beam or the hand") : L("This recording only has the arrow"),
                        isOn: binding(\.alwaysArrow)
                    )
                    .disabled(!model.artwork.hasCapturedShapes)
                    VideoCursorStylePicker(model: model)
                }
            }

            VideoKeyboardSection(model: model)
            VideoTypingSpeedSection(model: model)
        }
    }

    private var smoothingDetail: String {
        switch cursor.smoothing {
        case .off: return L("Exactly as recorded.")
        case .light: return L("Removes jitter, keeps it snappy.")
        case .smooth: return L("Glides without lagging behind — clicks still land exactly.")
        case .silky: return L("Extra-fluid curves for slow, cinematic demos.")
        }
    }
}

// MARK: - Zoom

struct VideoZoomInspector: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VideoCard {
                VideoToggleRow(
                    title: L("Auto-zoom on clicks"),
                    detail: L("Off until you turn it on. On, it zooms in on your clicks and switches on its options below; off, its zooms go."),
                    isOn: Binding(get: { model.project.autoZoom }, set: { model.setAutoZoom($0) })
                )
                Text(model.project.clickEvents.isEmpty
                     ? L("No clicks were recorded, so add zooms by hand: hover the zoom track and click.")
                     : L("Plans zooms around your \(model.project.clickEvents.count) clicks. Zooms you placed by hand are kept."))
                    .font(.system(size: 11))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.removeAllZooms()
                } label: {
                    Label(L("Remove all zooms"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle(destructive: true))
                .disabled(model.project.zoomRegions.isEmpty)
            }

            VideoZoomToolsCard(model: model)

            // Auto-zoom's own options: greyed out until it's on. Zooms added
            // by hand keep working either way (each has its own settings).
            VideoInspectorSection(L("New zooms")) {
                VideoSegmented(options: [1.5, 2.0, 2.5, 3.0].map { ($0, VideoEditorModel.formatScale($0)) }, selection: Binding(
                    get: { [1.5, 2.0, 2.5, 3.0].min { abs($0 - model.project.defaultZoomScale) < abs($1 - model.project.defaultZoomScale) } ?? 2 },
                    set: { value in model.setStyle { $0.defaultZoomScale = value } }
                ))
                Button {
                    model.applyZoomScaleToAll(model.project.defaultZoomScale)
                } label: {
                    Text(L("Apply to all zooms"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .disabled(model.project.zoomRegions.isEmpty)
            }
            .disabled(!model.project.autoZoom)
            .opacity(model.project.autoZoom ? 1 : 0.45)

            VideoInspectorSection(L("Motion")) {
                VideoSegmented(options: VideoZoomSpeed.allCases.map { ($0, $0.title) }, selection: Binding(
                    get: { model.project.zoomSpeed },
                    set: { value in model.setStyle { $0.zoomSpeed = value } }
                ))
                VideoSliderRow(
                    title: L("Motion blur"),
                    value: Binding(get: { model.project.motionBlur }, set: { value in model.setStyle(coalesce: "motion-blur") { $0.motionBlur = value } }),
                    range: 0...1,
                    defaultValue: VideoStylePreset.factory.motionBlur,
                    format: { VideoEditorFormat.percent($0) },
                    detail: L("Blurs fast camera moves the way a real camera does."),
                    onEditingEnded: { model.endGesture() }
                )
            }
            .disabled(!model.project.autoZoom)
            .opacity(model.project.autoZoom ? 1 : 0.45)

            if !model.project.zoomRegions.isEmpty {
                VideoInspectorSection(L("Zooms")) {
                    VStack(spacing: 4) {
                        ForEach(model.project.zoomRegions) { region in
                            if let range = model.zoomTimelineRange(region) {
                                Button {
                                    model.selection = .zoom(region.id)
                                    model.seek(to: range.lowerBound + min(1.2, (range.upperBound - range.lowerBound) / 2))
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: region.isLoupe ? "magnifyingglass.circle" : region.followsTyping ? "character.cursor.ibeam" : region.followsCursor ? "cursorarrow.motionlines" : "scope")
                                            .foregroundStyle(VideoEditorTheme.zoom)
                                            .frame(width: 16)
                                        Text(VideoEditorModel.formatScale(region.scale))
                                            .font(.system(size: 12, weight: .semibold))
                                            .monospacedDigit()
                                        Text(region.isLoupe ? L("Loupe") : region.followsTyping ? L("Follows typing") : region.followsCursor ? L("Follows cursor") : L("Aim by hand"))
                                            .font(.system(size: 11))
                                            .foregroundStyle(VideoEditorTheme.textSecondary)
                                        Spacer()
                                        Text(verbatim: "\(VideoEditorModel.timecode(range.lowerBound)) – \(VideoEditorModel.timecode(range.upperBound))")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(VideoEditorTheme.textTertiary)
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.card))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Text(L("Hover the zoom track and click to add a zoom, or press Z at the playhead. Drag a zoom to move it; drag its edges to change how long it lasts."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Audio

struct VideoAudioInspector: View {
    @ObservedObject var model: VideoEditorModel

    private var audio: VideoAudioSettings { model.project.audio }

    private func binding<T>(_ keyPath: WritableKeyPath<VideoAudioSettings, T>, coalesce: String? = nil) -> Binding<T> {
        Binding(get: { model.project.audio[keyPath: keyPath] }, set: { value in model.setStyle(coalesce: coalesce) { $0.audio[keyPath: keyPath] = value } })
    }

    private func level(_ title: String, _ keyPath: WritableKeyPath<VideoAudioSettings, Double>, detail: String? = nil) -> some View {
        VideoSliderRow(
            title: title,
            value: binding(keyPath, coalesce: "volume-\(title)"),
            range: VideoAudioSettings.volumeRange,
            defaultValue: 1,
            format: { VideoEditorFormat.percent($0) },
            detail: detail,
            onEditingEnded: { model.endGesture() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.hasAudio {
                VideoCard {
                    Label(L("This recording has no sound"), systemImage: "speaker.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Text(L("Turn on the microphone or system audio before recording to capture sound."))
                        .font(.system(size: 11))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VideoInspectorSection(L("Sound")) {
                    VideoToggleRow(title: L("Mute video"), detail: L("Exports without sound — to quiet just the preview, press M"), isOn: binding(\.muted))
                    Group {
                        if model.hasSeparateVoiceAndSystem {
                            level(L("Voice"), \.voiceVolume, detail: L("Your microphone"))
                            level(L("Computer sound"), \.systemVolume, detail: L("What was playing on your Mac"))
                        } else {
                            level(L("Volume"), \.volume)
                        }
                    }
                    .disabled(audio.muted)
                }

                if model.canEnhanceVoice {
                    VideoInspectorSection(L("Voice")) {
                        VideoToggleRow(
                            title: L("Enhance voice"),
                            detail: L("Removes background noise and hum, and evens out your level — processed on this Mac"),
                            isOn: binding(\.enhanceVoice)
                        )
                        .disabled(audio.podcast != nil)
                        if audio.podcast != nil {
                            Text(L("Podcast mode below takes care of the voice while it's on."))
                                .font(.system(size: 10.5))
                                .foregroundStyle(VideoEditorTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let progress = model.voiceJob {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(L("Cleaning up your voice…"))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(VideoEditorTheme.textSecondary)
                                    Spacer()
                                    Text(VideoEditorFormat.percent(progress))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(VideoEditorTheme.textSecondary)
                                }
                                ProgressView(value: progress).progressViewStyle(.linear)
                            }
                        } else if let error = model.voiceError, audio.voiceRecipe != nil {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VideoPodcastSection(model: model)

                VideoInspectorSection(L("Export")) {
                    VideoToggleRow(
                        title: L("Even out loudness"),
                        detail: L("Exports at the level video sites expect (−16 LUFS) without clipping"),
                        isOn: binding(\.normalizeLoudness)
                    )
                    .disabled(audio.podcast != nil)
                }

                Text(L("Select a clip on the timeline to mute it or fade it in and out."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Music and click sounds work with or without recorded sound.
            VideoMusicSection(model: model)
            VideoExternalAudioSection(model: model)
            VideoClickSoundSection(model: model)
        }
    }
}
