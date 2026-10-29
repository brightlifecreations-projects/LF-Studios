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

// MARK: - Script

/// Your words: edit the video by editing them, and turn them into captions.
struct VideoScriptInspector: View {
    @ObservedObject var model: VideoEditorModel
    @AppStorage("videoScriptMode") private var mode = "transcript"

    var body: some View {
        // Edit by text needs real words (a typed line isn't a transcript),
        // and steps aside while a new transcript is being made.
        let running = model.captionJob != nil && model.captionJob?.error == nil
        if !model.hasTranscript || running {
            ScrollView {
                VideoCaptionsInspector(model: model)
                    .padding(16)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                VideoSegmented(options: [("transcript", L("Edit by text")), ("captions", L("Captions"))], selection: $mode)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                if let error = model.captionJob?.error {
                    // Transcribing again failed: the transcript you had stays.
                    HStack(alignment: .top, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button {
                            model.captionJob = nil
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .help(L("Dismiss"))
                        .accessibilityLabel(L("Dismiss"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
                if mode == "transcript" {
                    VideoTranscriptPanel(model: model, timeline: model.timelineState, wantsFind: model.wantsTranscriptFind)
                } else {
                    ScrollView {
                        VideoCaptionsInspector(model: model)
                            .padding(16)
                    }
                }
            }
        }
    }
}

/// Cleanup buttons over the editable transcript.
struct VideoTranscriptPanel: View {
    let model: VideoEditorModel
    /// Counts refresh only when the timeline changes, not on every edit.
    @ObservedObject var timeline: VideoTimelineState
    /// ⌘F was pressed: the transcript opens its find bar.
    var wantsFind = false

    var body: some View {
        let fillers = model.fillerCount
        let pauses = model.pauseRanges
        let pauseSeconds = pauses.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        VStack(alignment: .leading, spacing: 10) {
            // One per row: their counts ("Shorten 12 pauses") need the width.
            VStack(spacing: 6) {
                cleanup(
                    title: fillers > 0 ? L("Remove \(fillers) ums") : L("No ums"),
                    symbol: "wand.and.stars",
                    help: L("Cut filler words like um and uh"),
                    enabled: fillers > 0,
                    action: model.removeFillers
                )
                cleanup(
                    title: pauses.isEmpty ? L("No pauses to shorten") : L("Shorten \(pauses.count) pauses"),
                    symbol: "forward.end",
                    help: model.project.cursorSamples.isEmpty && !model.seesScreenChanges
                        ? L("Shortens every silence over a second (this video has no LF Studios pointer data to spot what happens on screen)")
                        : !model.seesScreenChanges
                        ? (pauses.isEmpty ? L("Silences over a second get shortened — except while you move the pointer, click, or press a shortcut") : L("Saves \(VideoEditorModel.format(pauseSeconds)) — silences where the pointer rests and nothing is clicked or pressed (this older recording can't see typing)"))
                        : pauses.isEmpty
                        ? L("Silences over a second get shortened — except while you click, type, scroll, or move the pointer, so the demo itself is never cut")
                        : L("Saves \(VideoEditorModel.format(pauseSeconds)) — only silences where nothing happens on screen"),
                    enabled: !pauses.isEmpty,
                    action: model.shortenPauses
                )
            }
            Text(L("Select words and press ⌫ to cut them from the video — ⌫ again on crossed-out words puts them back. Click a word to jump there; ⌘F finds."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            VideoTranscriptEditor(model: model, timeline: timeline, clock: model.clock, wantsFind: wantsFind)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(VideoEditorTheme.well))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
        }
        .padding(16)
    }

    private func cleanup(title: String, symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(VideoSecondaryButtonStyle())
        .disabled(!enabled)
        .help(help)
    }
}

// MARK: - Captions

struct VideoCaptionsInspector: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject private var whisper = VideoWhisperModels.shared

    /// The Whisper model to transcribe with, when Whisper is chosen and
    /// downloaded (nil: Apple's recognizer).
    private var whisperChoice: VideoWhisperModel? {
        whisper.engine == .whisper && whisper.installed.contains(whisper.selected) ? whisper.selected : nil
    }

    private var style: VideoCaptionStyle { model.project.captionStyle }

    private func binding<T>(_ keyPath: WritableKeyPath<VideoCaptionStyle, T>) -> Binding<T> {
        Binding(get: { model.project.captionStyle[keyPath: keyPath] }, set: { value in model.setStyle { $0.captionStyle[keyPath: keyPath] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VideoSpeakerNotesCard(model: model)
            if !model.hasTranscript || model.captionJob != nil {
                generateCard
            }
            if !model.project.captions.isEmpty {
                VideoInspectorSection(L("Look")) {
                    VideoToggleRow(title: L("Show captions"), isOn: binding(\.visible))
                    VideoToggleRow(title: L("Highlight words"), detail: L("Words light up as they're spoken"), isOn: binding(\.highlightWords))
                        .disabled(style.animation.colorsWords)
                    // Caption looks (VideoCaptionStyles.swift).
                    VideoCaptionPresetPicker(model: model)
                    VideoFontPicker(model: model, choice: binding(\.font))
                    // How words come in (VideoCaptionAnimation.swift).
                    labeled(L("Animation")) {
                        Menu {
                            ForEach(VideoCaptionAnimation.allCases) { animation in
                                Button {
                                    model.setStyle { $0.captionStyle.animation = animation }
                                } label: {
                                    if animation == style.animation {
                                        Label(animation.title, systemImage: "checkmark")
                                    } else {
                                        Text(animation.title)
                                    }
                                }
                            }
                        } label: {
                            Text(style.animation.title)
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel(L("Caption animation"))
                        Spacer(minLength: 0)
                    }
                    labeled(L("Size")) {
                        VideoSegmented(options: VideoTextSize.allCases.map { ($0, $0.title) }, selection: binding(\.size))
                    }
                    labeled(L("Position")) {
                        VideoSegmented(options: VideoTextPosition.allCases.map { ($0, $0.title) }, selection: Binding(get: { style.position }, set: { model.setCaptionPreset($0) }))
                    }
                    VideoPlacementRow(isCustom: style.placement != nil, hint: L("Drag captions on the preview to place them anywhere")) {
                        model.resetCaptionPosition()
                    }
                }
                .disabled(model.captionJob != nil)

                VideoInspectorSection(L("Lines · \(model.project.captions.count)"), trailing: {
                    Button {
                        model.addCaptionAtPlayhead()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 22, height: 20)
                    }
                    .buttonStyle(VideoToolButtonStyle())
                    .help(L("Add a caption at the playhead"))
                }) {
                    VideoCaptionLinesList(model: model, clock: model.clock)
                }

                // Translated caption tracks (VideoCaptionTranslation.swift).
                VideoCaptionTranslationSection(model: model)

                HStack(spacing: 8) {
                    // .srt or .vtt (VideoCaptionStyles.swift).
                    VideoSubtitlesButton(model: model)
                    Menu {
                        Button(model.hasTranscript ? L("Transcribe Again…") : L("Transcribe…")) { model.transcribeAgain() }
                            .disabled(model.captionTask != nil)
                        if let whisperChoice {
                            Button(L("Transcribe Again with Whisper…")) { model.transcribeAgain(whisper: whisperChoice) }
                                .disabled(model.captionTask != nil)
                        }
                        Menu(L("Language")) { languageItems }
                            .disabled(model.captionTask != nil)
                        Divider()
                        Button(L("Remove Transcript & Captions"), role: .destructive) { model.clearCaptions() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 30, height: 26)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("More"))
                    .accessibilityLabel(L("More caption options"))
                }
            }
        }
        .onAppear { model.loadCaptionLanguages() }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VideoEditorTheme.textPrimary)
                .frame(width: VideoEditorTheme.rowTitleWidth([L("Size"), L("Position"), L("Animation")]), alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private var generateCard: some View {
        VideoCard {
            Label(L("Your words, as text"), systemImage: "text.quote")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textPrimary)
            Text(model.hasAudio
                 ? L("LF Studios listens to the recording right on this Mac — nothing is uploaded. Then cut the video by deleting words, remove ums and long pauses in one click, and add captions.")
                 : L("This recording has no sound. Turn on the microphone before recording to narrate it."))
                .font(.system(size: 11))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let job = model.captionJob, job.error == nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(job.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(VideoEditorTheme.textPrimary)
                        Spacer()
                        // The time spent always moves, even while the
                        // recognizer hasn't said how far it is.
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text([job.fraction.map { VideoEditorFormat.percent($0) }, job.elapsed(at: context.date)].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(VideoEditorTheme.textSecondary)
                        }
                    }
                    if let fraction = job.fraction {
                        ProgressView(value: fraction).progressViewStyle(.linear).tint(VideoEditorTheme.caption)
                    } else {
                        ProgressView().progressViewStyle(.linear).tint(VideoEditorTheme.caption)
                    }
                    Text(L("Keep editing — the words appear here when LF Studios is done listening."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("Cancel")) { model.cancelCaptions() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                }
            } else {
                // Idle, or the last try failed: the language, a retry, and a
                // way out are always there.
                if let job = model.captionJob, let error = job.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if job.needsPrivacySettings {
                        Button(L("Open Privacy Settings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(VideoSecondaryButtonStyle())
                    }
                }
                HStack(spacing: 8) {
                    Text(L("Language"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                    Spacer()
                    Menu {
                        languageItems
                    } label: {
                        Text(model.captionLanguageTitle)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                // Apple (built in) or Whisper (VideoWhisperViews.swift).
                VideoCaptionEngineControls(model: model)
                Button {
                    model.captionJob = nil
                    // Typed lines get replaced: that asks first.
                    model.transcribeAgain(whisper: whisperChoice)
                } label: {
                    Label(model.captionJob?.error != nil ? L("Try Again") : (whisper.engine == .whisper ? L("Transcribe with Whisper") : L("Transcribe")), systemImage: "waveform.badge.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoPrimaryButtonStyle())
                .disabled(!model.hasAudio || (whisper.engine == .whisper && whisperChoice == nil))
                if model.captionJob?.error != nil {
                    Button {
                        model.captionJob = nil
                    } label: {
                        Text(L("Dismiss")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                } else if model.project.captions.isEmpty {
                    Button {
                        model.addCaptionAtPlayhead()
                    } label: {
                        Text(L("Or type one at the playhead"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(VideoEditorTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var languageItems: some View {
        Button(L("\(VideoEditorModel.systemLanguageTitle) (This Mac)")) {
            model.captionLanguage = ""
        }
        if !model.captionLanguages.isEmpty {
            Divider()
            ForEach(model.captionLanguages) { language in
                Button(language.title) { model.captionLanguage = language.identifier }
            }
        }
    }
}

/// Editable caption lines; the one under the playhead is highlighted.
struct VideoCaptionLinesList: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock

    var body: some View {
        let current = model.plan.caption(at: clock.time)?.id
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(model.project.captions) { line in
                VideoCaptionRow(model: model, line: line, isCurrent: current == line.id, isSelected: model.selectedCaptionID == line.id)
            }
        }
    }
}

private struct VideoCaptionRow: View {
    @ObservedObject var model: VideoEditorModel
    let line: VideoCaptionLine
    let isCurrent: Bool
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                model.selectCaption(line.id)
            } label: {
                Text(VideoEditorModel.timecode(model.timelineTime(forSource: line.start) ?? line.start))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isCurrent ? VideoEditorTheme.caption : VideoEditorTheme.textTertiary)
                    .frame(width: 44, alignment: .leading)
                    .padding(.top, 3)
            }
            .buttonStyle(.plain)
            .help(L("Jump here"))
            VStack(alignment: .leading, spacing: 5) {
                TextField(L("Caption"), text: Binding(get: { line.text }, set: { model.updateCaption(line.id, text: $0) }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                    .lineLimit(1...4)
                    .onSubmit { model.endGesture() }
                if line.placement != nil {
                    VideoCustomPositionBadge()
                }
                if isSelected, line.placement != nil {
                    HStack(spacing: 6) {
                        Button(L("Reset to default position")) { model.resetCaptionPosition(line.id) }
                        Button(L("Apply this position to all captions")) { model.applyCaptionPositionToAll(from: line.id) }
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .controlSize(.small)
                }
            }
            if hovering {
                Button {
                    model.deleteCaption(line.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(L("Remove this caption"))
                .accessibilityLabel(L("Remove caption"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? VideoEditorTheme.caption.opacity(0.18) : (isCurrent ? VideoEditorTheme.ink.opacity(0.07) : (hovering ? VideoEditorTheme.ink.opacity(0.04) : Color.clear)))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Custom positions (VideoTextPlacement.swift)

/// Marks a caption that has a spot of its own.
struct VideoCustomPositionBadge: View {
    var body: some View {
        Label(L("Custom position"), systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(VideoEditorTheme.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(VideoEditorTheme.caption.opacity(0.16)))
            .fixedSize()
    }
}

/// Under the Top/Bottom presets: how to move the layer by hand, or a way
/// back once it's been moved.
private struct VideoPlacementRow: View {
    let isCustom: Bool
    let hint: String
    let reset: () -> Void

    var body: some View {
        if isCustom {
            HStack(spacing: 8) {
                VideoCustomPositionBadge()
                Spacer(minLength: 0)
                Button(L("Reset position"), action: reset)
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .controlSize(.small)
            }
        } else {
            Text(hint)
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        let sideBySide = VideoSplitLayout.isSideBySide(model.plan.outputCanvasSize)
        VideoInspectorSection(L("Layout")) {
            VideoSegmented(
                options: VideoRecordingCameraSetup.LayoutChoice.allCases.map { ($0, $0.title) },
                selection: Binding(get: { choice }, set: { newChoice in model.setStyle { $0.webcam = newChoice.applied(to: $0.webcam) } })
            )
            if choice == .split {
                let split = webcam.effectiveSplit
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
                Text(sideBySide
                     ? L("Side by side on this video. Drag the divider on the video to change the split; the background (Style) shows in the gap.")
                     : L("One above the other on this video. Drag the divider on the video to change the split; the background (Style) shows in the gap."))
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
