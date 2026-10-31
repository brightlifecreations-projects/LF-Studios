import SwiftUI

// MARK: - Remove ums: check them first (1.16.0)

/// One um (or uh, or a run of them) found in the narration, with the words
/// around it so you can tell whether it should go.
struct VideoFillerCandidate: Identifiable, Equatable {
    /// The transcript index of its first word.
    let id: Int
    let run: ClosedRange<Int>
    /// Source seconds that go when it's cut.
    let range: ClosedRange<Double>
    let filler: String
    let before: String
    let after: String
}

/// Remove ums' list: every um found, ticked; only the ticked ones are cut.
struct VideoFillerReview: Equatable {
    var candidates: [VideoFillerCandidate]
    var ticked: Set<Int>

    init(candidates: [VideoFillerCandidate]) {
        self.candidates = candidates
        ticked = Set(candidates.map(\.id))
    }
}

extension VideoEditorModel {
    /// The ums still in the video, with up to three words either side.
    var fillerCandidates: [VideoFillerCandidate] {
        let words = transcriptWords
        return VideoTranscript.fillerCuts(words: words, sound: waveform) { isIncluded(sourceTime: $0) }.map { cut in
            let before = words[max(cut.run.lowerBound - 3, 0)..<cut.run.lowerBound]
            let after = words[min(cut.run.upperBound + 1, words.count)..<min(cut.run.upperBound + 4, words.count)]
            return VideoFillerCandidate(
                id: cut.run.lowerBound,
                run: cut.run,
                range: cut.range,
                filler: words[cut.run].map(\.text).joined(separator: " "),
                before: before.map(\.text).joined(separator: " "),
                after: after.map(\.text).joined(separator: " ")
            )
        }
    }

    /// Remove ums: the list to check first (nothing is cut yet).
    func reviewFillers() {
        let candidates = fillerCandidates
        guard !candidates.isEmpty else {
            showNotice(L("No ums or uhs left"), symbol: "checkmark.circle")
            return
        }
        pause()
        withAnimation(.easeOut(duration: 0.15)) { fillerReview = VideoFillerReview(candidates: candidates) }
    }

    /// Cuts the ums whose first word is in `ids` (one undo step).
    @discardableResult
    func removeFillers(_ ids: Set<Int>) -> Bool {
        let words = transcriptWords
        let cuts = VideoTranscript.fillerCuts(words: words, sound: waveform) { isIncluded(sourceTime: $0) }
            .filter { ids.contains($0.run.lowerBound) }
        guard !cuts.isEmpty else { return false }
        if refuseLocked(.clips) { return false }
        let before = timelineDuration
        mutate(label: "Remove Ums") { project in
            guard project.removeSourceRanges(VideoTranscript.merge(cuts.map(\.range)), totalDuration: sourceDuration) else { return }
            for cut in cuts { project.retime(Array(words[cut.run]), into: cut.range) }
        }
        let shorter = Self.format(max(before - timelineDuration, 0))
        showNotice(L("Removed \(cuts.count) filler words — \(shorter) shorter"), symbol: "wand.and.stars")
        return true
    }

    /// ▶ next to an um: a second before it, the um, and a moment after.
    func playFiller(_ candidate: VideoFillerCandidate) {
        let start = timelineTime(forSource: max(candidate.range.lowerBound - 1, 0))
            ?? segments.first { $0.clip.sourceEnd > candidate.range.lowerBound - 1 }?.timelineStart ?? 0
        let end = (timelineTime(forSource: candidate.range.upperBound) ?? start) + 0.6
        fillerPreview?.cancel()
        pause()
        seek(to: start)
        togglePlay()
        fillerPreview = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(end - start, 0.3) * 1_000_000_000))
            guard !Task.isCancelled, let self, self.isPlaying else { return }
            self.pause()
        }
    }
}

/// The list: a tick, the words around it, ▶ to hear it.
struct VideoFillerReviewSheet: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        let review = model.fillerReview ?? VideoFillerReview(candidates: [])
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("Remove Ums"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Spacer()
                    Button { close() } label: {
                        Image(systemName: "xmark").frame(width: 26, height: 26)
                    }
                    .buttonStyle(VideoToolButtonStyle())
                    .help(L("Close (Esc)"))
                    .accessibilityLabel(L("Close"))
                }
                Text(L("Untick the ones to keep. ▶ plays each one with the words around it."))
                    .font(.system(size: 12))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(L("Tick All")) { model.fillerReview?.ticked = Set(review.candidates.map(\.id)) }
                        .disabled(review.ticked.count == review.candidates.count)
                    Button(L("Untick All")) { model.fillerReview?.ticked = [] }
                        .disabled(review.ticked.isEmpty)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.accentColor)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(review.candidates) { candidate in
                            row(candidate, ticked: review.ticked.contains(candidate.id))
                        }
                    }
                }
                .frame(maxHeight: 340)
                HStack {
                    Spacer()
                    Button(L("Cancel")) { close() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(review.ticked.isEmpty ? L("Remove None") : L("Remove \(review.ticked.count) ums")) {
                        let ticked = review.ticked
                        close()
                        model.perform(.removeFillers(ticked.sorted()))
                    }
                    .buttonStyle(VideoPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(review.ticked.isEmpty)
                }
            }
            .frame(width: 480)
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VideoEditorTheme.popover))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
            .shadow(color: VideoEditorTheme.shadow, radius: 30, y: 16)
        }
    }

    private func row(_ candidate: VideoFillerCandidate, ticked: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { ticked }, set: { on in
                if on { model.fillerReview?.ticked.insert(candidate.id) } else { model.fillerReview?.ticked.remove(candidate.id) }
            })) { EmptyView() }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(L("Remove “\(candidate.filler)”"))
            Button { model.playFiller(candidate) } label: {
                Image(systemName: "play.fill").font(.system(size: 10)).frame(width: 22, height: 22)
            }
            .buttonStyle(VideoToolButtonStyle())
            .help(L("Play it with the words around it"))
            .accessibilityLabel(L("Play “\(candidate.filler)”"))
            (Text(candidate.before.isEmpty ? "" : "…" + candidate.before + " ").foregroundColor(VideoEditorTheme.textSecondary)
                + Text(candidate.filler).bold().foregroundColor(ticked ? VideoEditorTheme.textPrimary : VideoEditorTheme.textTertiary).strikethrough(ticked)
                + Text(candidate.after.isEmpty ? "" : " " + candidate.after + "…").foregroundColor(VideoEditorTheme.textSecondary))
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(VideoEditorModel.timecode(model.timelineTime(forSource: candidate.range.lowerBound) ?? 0))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(VideoEditorTheme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ticked ? VideoEditorTheme.ink.opacity(0.04) : Color.clear))
    }

    private func close() {
        model.fillerPreview?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { model.fillerReview = nil }
    }
}
