import SwiftUI

// MARK: - Captions in the LF Studios (new) layout (1.17.0)

extension VideoEditorModel {
    /// Restyle all: every caption in one look, in one step. `template`: a
    /// caption style from Library ▸ Captions (nil: the look stays); then
    /// the size and the place, and no caption keeps a place of its own.
    func restyleCaptions(template: String?, size: VideoTextSize, position: VideoTextPosition) -> Bool {
        if refuseLocked(.captions) { return false }
        let chosen = template.flatMap { id in VideoCaptionTemplate.all.first { $0.id == id } }
        var next = project
        if let chosen { chosen.apply(to: &next.captionStyle) }
        next.captionStyle.size = size
        next.captionStyle.position = position
        next.captionStyle.placement = nil
        for i in next.captions.indices { next.captions[i].placement = nil }
        guard next != project else { return false }
        mutate(label: "Restyle Captions") { $0 = next }
        showNotice(L("Every caption restyled"), symbol: "captions.bubble")
        return true
    }
}

/// Properties ▸ Captions: every caption as a line you can edit (with its
/// time; click the time to go there), one restyle for all of them, and the
/// transcript and caption tools as before.
struct VideoCaptionsPanel: View {
    @ObservedObject var model: VideoEditorModel
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            VideoSegmented(options: [(0, L("Captions")), (1, L("Transcript"))], selection: $page)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            if page == 0 {
                VideoCaptionCues(model: model, clock: model.clock)
            } else {
                VideoScriptInspector(model: model)
            }
        }
    }
}

/// The list of captions, then Restyle all.
struct VideoCaptionCues: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock
    @State private var template: String?
    @State private var size: VideoTextSize = .medium
    @State private var position: VideoTextPosition = .bottom

    var body: some View {
        let captions = model.project.captions
        let current = model.plan.caption(at: clock.time)?.id
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VideoSectionLabel(L("\(captions.count) captions"))
                    Spacer()
                    Button(L("Add at Playhead")) {
                        model.inspectorTab = .captions
                        model.addCaptionAtPlayhead()
                    }
                    .controlSize(.small)
                }
                if captions.isEmpty {
                    Text(L("No captions yet. Transcribe the narration (Transcript), import an .srt or .vtt file from Library ▸ Captions, or add one at the playhead."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 4) {
                    ForEach(captions) { line in
                        VideoCaptionCueRow(model: model, line: line, current: line.id == current)
                    }
                }
                if !captions.isEmpty {
                    restyle
                }
            }
            .padding(14)
        }
        .onAppear {
            size = model.project.captionStyle.size
            position = model.project.captionStyle.position
        }
    }

    private var restyle: some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoSectionLabel(L("Restyle all captions"))
            Picker(L("Style"), selection: $template) {
                Text(L("Keep the current style")).tag(String?.none)
                ForEach(VideoCaptionTemplate.all) { t in Text(t.title).tag(String?.some(t.id)) }
            }
            .pickerStyle(.menu)
            VideoSegmented(options: VideoTextSize.allCases.map { ($0, $0.title) }, selection: $size)
            VideoSegmented(options: VideoTextPosition.allCases.map { ($0, $0.title) }, selection: $position)
            Button {
                model.perform(.restyleCaptions(template: template, size: size, position: position))
            } label: {
                Text(L("Apply to Every Caption")).frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoPrimaryButtonStyle())
            Text(L("One step: ⌘Z puts every caption back as it was. Captions moved on their own go back to the shared place."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }
}

/// One caption: its time (click to go there) and its words (edit them;
/// Return or leaving the field keeps them).
struct VideoCaptionCueRow: View {
    @ObservedObject var model: VideoEditorModel
    let line: VideoCaptionLine
    let current: Bool
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        let time = model.timelineTime(forSource: line.start)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                if let time { model.seek(to: time) }
            } label: {
                Text(VideoEditorModel.timecode(time ?? line.start))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(time == nil ? VideoEditorTheme.textTertiary : VideoEditorTheme.textSecondary)
                    .frame(width: 52, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(time == nil ? L("This part is cut from the video") : L("Go to this caption"))
            TextField(L("Caption"), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...3)
                .focused($editing)
                .onSubmit(commit)
                .onChange(of: editing) { if !$0 { commit() } }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(current ? VideoEditorTheme.primary.opacity(0.14) : VideoEditorTheme.card))
        .onAppear { text = line.text }
        .onChange(of: line.text) { if !editing { text = $0 } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != line.text, !trimmed.isEmpty else { text = line.text; return }
        model.perform(.setCaptionText(line.id, trimmed))
        model.endGesture()
    }
}
