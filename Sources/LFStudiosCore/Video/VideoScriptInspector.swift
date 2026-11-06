import AppKit
import SwiftUI

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
                    action: { model.perform(.reviewFillers) }
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
