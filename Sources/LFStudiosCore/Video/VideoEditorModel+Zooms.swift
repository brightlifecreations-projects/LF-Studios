import AppKit
import AVFoundation
import SwiftUI

/// The editor's zooms: adding, changing and removing them, Auto zoom.
extension VideoEditorModel {
    // MARK: Zooms

    var selectedZoomID: UUID? {
        if case .zoom(let id) = selection { return id }
        return nil
    }

    var selectedZoom: VideoZoomRegion? {
        selectedZoomID.flatMap { id in project.zoomRegions.first { $0.id == id } }
    }

    /// Paused with a manual zoom selected: the preview shows the whole frame
    /// with a draggable target rectangle.
    var isAimingZoom: Bool {
        guard !isPlaying, let zoom = selectedZoom else { return false }
        return !zoom.followsCursor
    }

    /// Timeline ranges occupied by zoom regions (for placement and drawing).
    func zoomTimelineRange(_ region: VideoZoomRegion) -> ClosedRange<Double>? {
        let ranges = VideoDemoProject.timelineRanges(sourceStart: region.start, sourceEnd: region.end, segments: segments)
        guard let first = ranges.first, let last = ranges.last else { return nil }
        return first.lowerBound...last.upperBound
    }

    /// Free space around `time` on the zoom track.
    func zoomGap(around time: Double) -> ClosedRange<Double> {
        var lower = 0.0
        var upper = timelineDuration
        for region in project.zoomRegions {
            guard let range = zoomTimelineRange(region) else { continue }
            if range.upperBound <= time { lower = max(lower, range.upperBound) }
            if range.lowerBound >= time { upper = min(upper, range.lowerBound) }
            if range.contains(time) { return time...time }
        }
        return lower...max(lower, upper)
    }

    /// Times a dragged edge likes to land on (timeline seconds): the
    /// playhead, clip boundaries, clicks and shortcuts, and the edges of
    /// every zoom, annotation, caption, and camera layout but the ones being
    /// dragged.
    func snapTargets(excluding ids: Set<UUID>) -> [Double] {
        // Auto snapping off (N): everything lands where it's let go.
        guard Settings.videoTimelineSnapping else { return [] }
        var targets: [Double] = [0, timelineDuration, clock.time]
        for (_, item) in project.layerItems where !ids.contains(item.id) {
            targets.append(item.at)
            targets.append(item.end)
        }
        // Detect beats (1.15.0): clips land on the beat.
        targets += beatTimes
        for marker in project.markers { if let time = timelineTime(forSource: marker.time) { targets.append(time) } }
        for segment in segments {
            targets.append(segment.timelineStart)
            targets.append(segment.timelineEnd)
        }
        for click in project.clickEvents where !ids.contains(click.id) {
            if let time = timelineTime(forSource: click.time) { targets.append(time) }
        }
        for keystroke in plan.keystrokes { targets.append(keystroke.start) }
        for region in project.zoomRegions where !ids.contains(region.id) {
            if let range = zoomTimelineRange(region) {
                targets.append(range.lowerBound)
                targets.append(range.upperBound)
            }
        }
        for overlay in plan.overlays where !ids.contains(overlay.effect.id) {
            targets.append(overlay.start)
            targets.append(overlay.end)
        }
        for caption in plan.captions where !ids.contains(caption.id) {
            targets.append(caption.start)
            targets.append(caption.end)
        }
        for span in cameraLayoutSpans where !ids.contains(span.region.id) {
            targets.append(span.start)
            targets.append(span.end)
        }
        return targets
    }

    @discardableResult
    func addZoom(at time: Double, length: Double = 3, label: String? = nil, configure: (inout VideoZoomRegion) -> Void = { _ in }) -> UUID? {
        if refuseLocked(.zooms) { return nil }
        let gap = zoomGap(around: time)
        guard gap.upperBound - gap.lowerBound >= VideoZoomRegion.minimumDuration else {
            showNotice(L("There's already a zoom here"), symbol: "plus.magnifyingglass")
            return nil
        }
        var start = max(time - 0.2, gap.lowerBound)
        var end = min(start + length, gap.upperBound)
        if end - start < min(length, 1.2) {
            start = max(gap.lowerBound, end - length)
            end = min(gap.upperBound, start + length)
        }
        let window = sourceWindow(timelineStart: start, timelineEnd: end)
        let sourceStart = window.lowerBound
        let sourceEnd = window.upperBound
        guard sourceEnd - sourceStart >= VideoZoomRegion.minimumDuration else { return nil }
        // Aim where the pointer is, when we know it.
        let pointer = plan.cursorTrack?.visiblePosition(at: sourceTime(forTimeline: min(start + 0.6, end)))
        var region = VideoZoomRegion(
            start: sourceStart,
            end: sourceEnd,
            scale: project.defaultZoomScale,
            followsCursor: plan.cursorTrack != nil,
            focusX: pointer.map { Double($0.x) } ?? 0.5,
            focusY: pointer.map { Double($0.y) } ?? 0.5
        )
        configure(&region)
        mutate(label: label) { project in
            project.zoomRegions.append(region)
            project.zoomRegions.sort { $0.start < $1.start }
        }
        selection = .zoom(region.id)
        return region.id
    }

    func updateZoom(_ id: UUID, coalesce: String? = nil, _ change: (inout VideoZoomRegion) -> Void) {
        mutate(coalesce: coalesce) { project in
            guard let index = project.zoomRegions.firstIndex(where: { $0.id == id }) else { return }
            change(&project.zoomRegions[index])
            project.zoomRegions[index].scale = min(max(project.zoomRegions[index].scale, VideoZoomRegion.scaleRange.lowerBound), VideoZoomRegion.scaleRange.upperBound)
            project.zoomRegions[index].focusX = min(max(project.zoomRegions[index].focusX, 0), 1)
            project.zoomRegions[index].focusY = min(max(project.zoomRegions[index].focusY, 0), 1)
            project.zoomRegions[index].isAuto = false
            project.zoomRegions[index].isTyping = false
        }
    }

    /// Moves / resizes a zoom in timeline seconds, never overlapping its
    /// neighbours.
    func setZoomWindow(_ id: UUID, start: Double, end: Double, coalesce: String) {
        let others = project.zoomRegions.filter { $0.id != id }.compactMap { zoomTimelineRange($0) }
        guard let current = project.zoomRegions.first(where: { $0.id == id }).flatMap({ zoomTimelineRange($0) }) else { return }
        let lowerLimit = others.filter { $0.upperBound <= current.lowerBound + 0.001 }.map(\.upperBound).max() ?? 0
        let upperLimit = others.filter { $0.lowerBound >= current.upperBound - 0.001 }.map(\.lowerBound).min() ?? timelineDuration
        var newStart = max(start, lowerLimit)
        var newEnd = min(end, upperLimit)
        if newEnd - newStart < VideoZoomRegion.minimumDuration {
            if start != current.lowerBound && end != current.upperBound {
                // Moving: keep the length.
                let length = current.upperBound - current.lowerBound
                newStart = min(max(start, lowerLimit), upperLimit - length)
                newEnd = newStart + length
            } else if start != current.lowerBound {
                newStart = newEnd - VideoZoomRegion.minimumDuration
            } else {
                newEnd = newStart + VideoZoomRegion.minimumDuration
            }
        }
        let window = sourceWindow(timelineStart: newStart, timelineEnd: newEnd)
        let sourceStart = window.lowerBound
        let sourceEnd = window.upperBound
        updateZoom(id, coalesce: coalesce) { region in
            region.start = sourceStart
            region.end = max(sourceEnd, sourceStart + VideoZoomRegion.minimumDuration)
        }
    }

    func deleteZoom(_ id: UUID) {
        mutate { project in
            project.zoomRegions.removeAll { $0.id == id }
        }
        if selection == .zoom(id) { selection = .none }
        showNotice(L("Zoom removed — ⌘Z to undo"), symbol: "trash")
    }

    /// Back to the recording as it was made: every edit goes (one undo
    /// brings them all back).
    func startOver() {
        let alert = NSAlert()
        alert.messageText = L("Start over from the original recording?")
        alert.informativeText = project.hasAppendedSources
            ? L("Every cut, zoom, annotation, caption, and style change on this video is removed — the recordings you added stay. You can undo this.")
            : L("Every cut, zoom, annotation, caption, and style change on this video is removed. You can undo this.")
        alert.addButton(withTitle: L("Start Over"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            // Every added recording's own data first (read off the main thread).
            await loadAppendedMetadata()
            resetToOriginal()
        }
    }

    /// Start Over without asking. Edits go; added recordings stay.
    func resetToOriginal() {
        let primaryDuration = project.sources.first(where: \.isPrimary)?.duration ?? sourceDuration
        var fresh = VideoDemoProject.fresh(sourceURL: project.sourceURL, duration: primaryDuration, sourceSize: project.sourceSize)
        if let recording { fresh.apply(metadata: recording) }
        fresh.sourceWidth = project.sourceWidth
        fresh.sourceHeight = project.sourceHeight
        fresh.ensureTimeline(totalDuration: primaryDuration)
        restoreAddedRecordings(into: &fresh)
        if fresh.sourceHeight > fresh.sourceWidth * 1.1, fresh.aspectPreset == .widescreen || fresh.aspectPreset == .classic {
            fresh.aspectPreset = .source
        }
        selection = .none
        mutate(label: "Start Over") { $0 = fresh }
        endGesture()
        showNotice(L("Back to the original recording — ⌘Z to undo"), symbol: "arrow.counterclockwise")
    }

    /// A copy of an annotation, nudged so both are visible, on top.
    func duplicateOverlay(_ id: UUID) {
        guard let original = project.overlayEffects.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.x = min(original.x + 0.03, 0.98)
        copy.y = min(original.y + 0.03, 0.98)
        copy.refitArrowEnds(from: original)
        let overlapping = project.overlayEffects.filter { $0.time < copy.time + copy.duration && $0.time + $0.duration > copy.time }
        copy.layer = (overlapping.map(\.layer).max() ?? -1) + 1
        mutate { project in
            project.overlayEffects.append(copy)
            project.overlayEffects = VideoDemoProject.normalizedEffectLayers(project.overlayEffects)
        }
        selection = .overlay(copy.id)
        showNotice(L("Duplicated"), symbol: "plus.square.on.square")
    }

    func duplicateZoom(_ id: UUID) {
        guard let region = project.zoomRegions.first(where: { $0.id == id }),
              let range = zoomTimelineRange(region) else { return }
        let length = range.upperBound - range.lowerBound
        let gap = zoomGap(around: range.upperBound + 0.01)
        guard gap.upperBound - gap.lowerBound >= length * 0.5 else {
            showNotice(L("No room after this zoom"), symbol: "plus.square.on.square")
            return
        }
        let start = gap.lowerBound + 0.1
        let end = min(start + length, gap.upperBound)
        var copy = region
        copy.id = UUID()
        let window = sourceWindow(timelineStart: start, timelineEnd: end)
        copy.start = window.lowerBound
        copy.end = max(window.upperBound, window.lowerBound + VideoZoomRegion.minimumDuration)
        copy.isAuto = false
        mutate { project in
            project.zoomRegions.append(copy)
            project.zoomRegions.sort { $0.start < $1.start }
        }
        selection = .zoom(copy.id)
    }

    func applyZoomScaleToAll(_ scale: Double) {
        mutate(label: "Zoom Level for All") { project in
            for index in project.zoomRegions.indices {
                project.zoomRegions[index].scale = scale
            }
            project.defaultZoomScale = scale
        }
        showNotice(L("All zooms set to \(Self.formatScale(scale))"), symbol: "plus.magnifyingglass")
    }

    /// Auto-zoom on clicks, from the Zoom panel's switch (and the toolbar's
    /// Auto Zoom, which turns it on or plans the zooms again): one undo step.
    func setAutoZoom(_ on: Bool) {
        if refuseLocked(.zooms) { return }
        let total = sourceDuration
        var generated = 0
        mutate(label: on ? "Auto-Zoom On" : "Auto-Zoom Off") { generated = $0.setAutoZoom(on, totalDuration: total) }
        if case .zoom = selection, !project.zoomRegions.contains(where: { if case .zoom(let id) = selection { return $0.id == id } else { return false } }) {
            selection = .none
        }
        guard on else {
            showNotice(L("Auto-zoom off — its zooms are gone. ⌘Z to undo"), symbol: "sparkles")
            return
        }
        if generated == 0 {
            showNotice(project.clickEvents.isEmpty ? L("Auto-zoom on — no clicks were recorded, so add zooms by hand") : L("Auto-zoom on — no clicks left on the timeline"), symbol: "sparkles")
        } else {
            showNotice(L("Auto zoom — \(project.zoomRegions.count) zooms"), symbol: "sparkles")
        }
    }

    func autoZoom() { setAutoZoom(true) }

    func removeAllZooms() {
        guard !project.zoomRegions.isEmpty else { return }
        let count = project.zoomRegions.count
        mutate(label: "Remove All Zooms") { project in
            project.zoomRegions.removeAll()
        }
        if case .zoom = selection { selection = .none }
        showNotice(L("Removed \(count) zooms — ⌘Z to undo"), symbol: "trash")
    }
}
