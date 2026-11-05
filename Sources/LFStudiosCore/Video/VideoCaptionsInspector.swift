import AppKit
import SwiftUI

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
struct VideoPlacementRow: View {
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
