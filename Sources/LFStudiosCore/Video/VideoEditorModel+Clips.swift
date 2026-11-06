import AppKit
import AVFoundation
import SwiftUI

/// The main track's clips: split, delete, speed, mute, fades, trims and ranges.
extension VideoEditorModel {
    // MARK: Clips

    var selectedClipID: UUID? {
        if case .clip(let id) = selection { return id }
        return nil
    }

    func selectClip(_ id: UUID) {
        selection = .clip(id)
    }

    func splitAtPlayhead() {
        // An added sound piece is selected: S splits that track instead.
        if let piece = selectedAudioPiece {
            if refuseLocked(.sound(piece.track)) { return }
            splitAudioTrack(piece.track)
            return
        }
        if refuseLocked(.clips) { return }
        let time = clock.time
        guard let segment = segment(atTimeline: time) else { return }
        let sourceTime = segment.sourceTime(forTimelineTime: time)
        var newID: UUID?
        mutate { project in
            newID = project.splitClip(atSourceTime: sourceTime, totalDuration: sourceDuration)
        }
        if let newID {
            selection = .clip(newID)
            showNotice(L("Clip split"), symbol: "scissors")
        } else {
            showNotice(L("Move the playhead inside a clip to split"), symbol: "scissors")
        }
    }

    func deleteClip(_ id: UUID) {
        // Magnet off (P): the clip stays as a black, silent gap of its
        // length (V turns it back on).
        if !Settings.videoTimelineMagnet, let index = project.timelineClips.firstIndex(where: { $0.id == id }) {
            if refuseLocked(.clips) { return }
            mutate(label: "Delete Clip") { $0.timelineClips[index].disabled = true }
            showNotice(L("Clip removed, gap left (magnet off) — ⌘Z to undo"), symbol: "trash")
            return
        }
        guard segments.count > 1 else {
            showNotice(L("A video needs at least one clip"), symbol: "exclamationmark.triangle")
            return
        }
        let anchor = segments.first(where: { $0.id == id })?.timelineStart ?? clock.time
        var next: UUID?
        mutate { project in
            next = project.deleteClip(id: id, totalDuration: sourceDuration)
        }
        selection = next.map { .clip($0) } ?? .none
        seek(to: min(anchor, max(timelineDuration - 0.01, 0)))
        showNotice(L("Clip removed — ⌘Z to undo"), symbol: "trash")
    }

    func deleteRange(_ range: VideoDemoTimelineRange) {
        if refuseLocked(.clips) { return }
        let normalized = range.normalized
        var next: UUID?
        mutate(label: "Cut") { project in
            next = project.deleteTimelineRange(start: normalized.start, end: normalized.end, totalDuration: sourceDuration)
        }
        if next == nil {
            showNotice(L("A video needs at least one clip"), symbol: "exclamationmark.triangle")
            return
        }
        selection = .none
        seek(to: min(normalized.start, max(timelineDuration - 0.01, 0)))
        showNotice(L("Removed \(Self.format(normalized.duration)) — ⌘Z to undo"), symbol: "scissors")
    }

    // MARK: Range actions

    /// The recording spans a timeline range covers (one per clip it crosses).
    func sourcePieces(of range: VideoDemoTimelineRange) -> [ClosedRange<Double>] {
        let normalized = range.normalized
        return segments.compactMap { segment in
            let start = max(normalized.start, segment.timelineStart)
            let end = min(normalized.end, segment.timelineEnd)
            guard end - start > 0.01 else { return nil }
            return segment.sourceTime(forTimelineTime: start)...segment.sourceTime(forTimelineTime: end)
        }
    }

    /// Changes just the selected part (speed, sound): its clips split at the
    /// range's edges, and the range follows the same material afterwards.
    func applyToRange(_ range: VideoDemoTimelineRange, label: String, _ change: (inout VideoDemoTimelineClip) -> Void) {
        if refuseLocked(.clips) { return }
        let pieces = sourcePieces(of: range)
        guard !pieces.isEmpty else { return }
        mutate(label: label) { project in
            for piece in pieces {
                _ = project.splitClip(atSourceTime: piece.lowerBound, totalDuration: sourceDuration)
                _ = project.splitClip(atSourceTime: piece.upperBound, totalDuration: sourceDuration)
                // Edges too close to a clip's own edge to split there: that
                // whole clip counts as inside.
                let slack = VideoDemoProject.minimumClipDuration
                for clip in project.normalizedTimelineClips(totalDuration: sourceDuration)
                where clip.sourceStart >= piece.lowerBound - slack && clip.sourceEnd <= piece.upperBound + slack {
                    _ = project.updateClip(id: clip.id, totalDuration: sourceDuration, update: change)
                }
            }
        }
        let spans = pieces.flatMap { VideoDemoProject.timelineRanges(sourceStart: $0.lowerBound, sourceEnd: $0.upperBound, segments: segments) }
        if let first = spans.map(\.lowerBound).min(), let last = spans.map(\.upperBound).max() {
            selection = .range(VideoDemoTimelineRange(start: first, end: last))
        }
    }

    /// The clips a range crosses.
    private func segments(in range: VideoDemoTimelineRange) -> [VideoDemoTimelineSegment] {
        let normalized = range.normalized
        return segments.filter { min(normalized.end, $0.timelineEnd) - max(normalized.start, $0.timelineStart) > 0.01 }
    }

    /// The speed the whole range plays at (nil when its clips differ).
    func rangeSpeed(_ range: VideoDemoTimelineRange) -> Double? {
        let speeds = Set(segments(in: range).map { ($0.clip.normalizedSpeed * 100).rounded() / 100 })
        return speeds.count == 1 ? speeds.first : nil
    }

    func rangeIsMuted(_ range: VideoDemoTimelineRange) -> Bool {
        let crossed = segments(in: range)
        return !crossed.isEmpty && crossed.allSatisfy(\.clip.muted)
    }

    func setRangeSpeed(_ range: VideoDemoTimelineRange, _ speed: Double) {
        applyToRange(range, label: "Speed Change") { $0.speed = speed }
    }

    func toggleRangeMute(_ range: VideoDemoTimelineRange) {
        let muted = rangeIsMuted(range)
        applyToRange(range, label: muted ? "Unmute Part" : "Mute Part") { $0.muted = !muted }
    }

    func setClipSpeed(_ id: UUID, _ speed: Double) {
        mutate(coalesce: "speed-\(id)") { project in
            _ = project.updateClip(id: id, totalDuration: sourceDuration) { $0.speed = speed }
        }
    }

    func setClipMuted(_ id: UUID, _ muted: Bool) {
        mutate { project in
            _ = project.updateClip(id: id, totalDuration: sourceDuration) { $0.muted = muted }
        }
    }

    func setClipFade(_ id: UUID, fadeIn: Double? = nil, fadeOut: Double? = nil) {
        mutate(coalesce: "fade-\(id)") { project in
            _ = project.updateClip(id: id, totalDuration: sourceDuration) { clip in
                if let fadeIn { clip.fadeIn = fadeIn }
                if let fadeOut { clip.fadeOut = fadeOut }
            }
        }
    }

    /// Live clip-edge trim. `sourceTime` is the new edge; the preview peeks
    /// at it while dragging.
    func trimClip(_ id: UUID, leading: Bool, toSource sourceTime: Double) {
        if layoutDurationLock == nil { layoutDurationLock = timelineDuration }
        holdsPlayerRebuild = true
        mutate(coalesce: "trim-\(id)-\(leading)") { project in
            if leading {
                _ = project.trimClip(id: id, sourceStart: sourceTime, totalDuration: sourceDuration)
            } else {
                _ = project.trimClip(id: id, sourceEnd: sourceTime, totalDuration: sourceDuration)
            }
        }
        if let clip = project.timelineClips.first(where: { $0.id == id }) {
            trimPeekSourceTime = leading ? clip.sourceStart : max(clip.sourceEnd - 0.02, clip.sourceStart)
        }
        previewRenderer.invalidate()
    }

    func endTrim(_ id: UUID, leading: Bool) {
        endGesture()
        trimPeekSourceTime = nil
        layoutDurationLock = nil
        if holdsPlayerRebuild {
            holdsPlayerRebuild = false
            playback.apply(segments: segments, audio: playbackAudio, keepSourceTime: nil, extras: editExtras)
        }
        if let segment = segments.first(where: { $0.id == id }) {
            seek(to: leading ? segment.timelineStart : max(segment.timelineEnd - 0.02, segment.timelineStart))
        }
    }

    func trimSelectedClipToPlayhead(leading: Bool) {
        let time = clock.time
        // The selected clip, when the playhead is in it; else the clip the
        // playhead is in — on a cut, the one after it for "starts here" and
        // the one before it for "ends here".
        let selected = selectedClipID.flatMap { id in
            segments.first { $0.id == id && time >= $0.timelineStart - 0.001 && time <= $0.timelineEnd + 0.001 }
        }
        let underPlayhead = leading
            ? segments.first { time >= $0.timelineStart - 0.001 && time < $0.timelineEnd - 0.001 }
            : segments.first { time > $0.timelineStart + 0.001 && time <= $0.timelineEnd + 0.001 }
        guard let segment = selected ?? underPlayhead else { return }
        let sourceTime = segment.sourceTime(forTimelineTime: time)
        mutate { project in
            if leading {
                _ = project.trimClip(id: segment.id, sourceStart: sourceTime, totalDuration: sourceDuration)
            } else {
                _ = project.trimClip(id: segment.id, sourceEnd: sourceTime, totalDuration: sourceDuration)
            }
        }
        selection = .clip(segment.id)
        showNotice(leading ? L("Clip now starts here") : L("Clip now ends here"), symbol: leading ? "arrow.left.to.line" : "arrow.right.to.line")
    }

    /// Material cut between two clips (or before the first / after the last).
    struct CutGap: Identifiable {
        var id: String { "\(afterClip?.uuidString ?? "start")-\(sourceStart)" }
        let timelineTime: Double
        let sourceStart: Double
        let sourceEnd: Double
        let afterClip: UUID?
        var duration: Double { sourceEnd - sourceStart }

        /// Runs of gaps whose markers sit within `spacing` timeline seconds
        /// of each other.
        static func grouped(_ gaps: [CutGap], within spacing: Double) -> [[CutGap]] {
            var groups: [[CutGap]] = []
            for gap in gaps.sorted(by: { $0.timelineTime < $1.timelineTime }) {
                if let last = groups.last?.last, gap.timelineTime - last.timelineTime < spacing {
                    groups[groups.count - 1].append(gap)
                } else {
                    groups.append([gap])
                }
            }
            return groups
        }
    }

    /// Parts of the recording no clip plays, each marked where restoring it
    /// would bring it back: after the clip that ends where it starts (clips
    /// may be in any order on the timeline).
    var cutGaps: [CutGap] {
        var gaps: [CutGap] = []
        let bySource = segmentsBySource
        guard let first = bySource.first, let last = bySource.last else { return gaps }
        if first.clip.sourceStart > 0.05 {
            gaps.append(CutGap(timelineTime: first.timelineStart, sourceStart: 0, sourceEnd: first.clip.sourceStart, afterClip: nil))
        }
        for (a, b) in zip(bySource, bySource.dropFirst()) where b.clip.sourceStart - a.clip.sourceEnd > 0.05 {
            gaps.append(CutGap(timelineTime: a.timelineEnd, sourceStart: a.clip.sourceEnd, sourceEnd: b.clip.sourceStart, afterClip: a.id))
        }
        if sourceDuration - last.clip.sourceEnd > 0.05 {
            gaps.append(CutGap(timelineTime: last.timelineEnd, sourceStart: last.clip.sourceEnd, sourceEnd: sourceDuration, afterClip: last.id))
        }
        return gaps
    }

    /// Puts removed material back (the neighbouring clip grows over it, and
    /// merges with the next one when they meet again).
    func restore(_ gap: CutGap) {
        mutate(label: "Restore Cut") { project in
            project.restoreSourceRange(gap.sourceStart...gap.sourceEnd, totalDuration: sourceDuration)
        }
        showNotice(L("Restored \(Self.format(gap.duration))"), symbol: "arrow.uturn.backward")
    }

    /// Moves a clip to another place in the video.
    func moveClip(_ id: UUID, toIndex index: Int) {
        var moved = false
        mutate(label: "Move Clip") { moved = $0.moveClip(id: id, toIndex: index, totalDuration: sourceDuration) }
        guard moved else { return }
        selection = .clip(id)
        if let segment = segments.first(where: { $0.id == id }) { seek(to: segment.timelineStart) }
        showNotice(L("Clip moved — ⌘Z to undo"), symbol: "arrow.left.arrow.right")
    }

    /// Several cuts back at once (one undo step).
    func restore(_ gaps: [CutGap]) {
        guard !gaps.isEmpty else { return }
        mutate(label: "Restore Cuts") { project in
            for gap in gaps {
                project.restoreSourceRange(gap.sourceStart...gap.sourceEnd, totalDuration: sourceDuration)
            }
        }
        let total = gaps.reduce(0) { $0 + $1.duration }
        showNotice(L("Restored \(gaps.count) cuts — \(Self.format(total))"), symbol: "arrow.uturn.backward")
    }

    // MARK: Delete / Escape

    func deleteSelection() {
        if let track = lockedTrackInSelection {
            _ = refuseLocked(track)
            return
        }
        if let piece = selectedAudioPiece {
            deleteAudioPiece(piece)
            return
        }
        if !extraSelection.isEmpty {
            deleteSelectedItems()
            return
        }
        switch selection {
        case .none:
            break
        case .zoom(let id):
            deleteZoom(id)
        case .overlay(let id):
            deleteOverlay(id)
        case .click(let id):
            deleteClick(id)
        case .caption(let id):
            deleteCaption(id)
        case .keystroke(let id):
            deleteKeystroke(id)
        case .cameraLayout(let id):
            deleteCameraLayout(id)
        case .layer(let id):
            deleteLayerItem(id)
        case .clip(let id):
            deleteClip(id)
        case .range(let range):
            deleteRange(range)
        }
    }
}
