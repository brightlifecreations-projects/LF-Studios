import CoreGraphics
import Foundation

// MARK: - The bubble stepping aside

/// A zoom that moves the camera bubble to another corner while it plays.
struct VideoBubbleMove: Equatable {
    /// Seconds the bubble takes to slide over, and back.
    static let slide = 0.45

    /// Timeline seconds.
    let start: Double
    let end: Double
    let corner: VideoWebcamSettings.Anchor

    /// 0 at home … 1 at `corner`.
    func progress(at time: Double) -> Double {
        guard time > start, time < end else { return 0 }
        let ramp = min(Self.slide, (end - start) / 2)
        return min(VideoCameraEasing.spring((time - start) / ramp), VideoCameraEasing.spring((end - time) / ramp))
    }

    static func moves(project: VideoDemoProject, segments: [VideoDemoTimelineSegment]) -> [VideoBubbleMove] {
        project.zoomRegions.compactMap { region in
            guard let corner = region.cameraCorner, corner != project.webcam.anchor else { return nil }
            let ranges = VideoDemoProject.timelineRanges(sourceStart: region.start, sourceEnd: region.end, segments: segments).sorted { $0.lowerBound < $1.lowerBound }
            guard let first = ranges.first, let last = ranges.last else { return nil }
            return VideoBubbleMove(start: first.lowerBound, end: last.upperBound, corner: corner)
        }
    }
}

extension VideoFrameRenderer {
    /// The bubble's place at `time`: home, or on its way to (or at) the
    /// corner a zoom moved it to.
    static func movedWebcamRect(_ settings: VideoWebcamSettings, plan: VideoRenderPlan, time: Double, outputSize: CGSize, cameraScale: Double) -> CGRect {
        let home = webcamRect(settings, outputSize: outputSize, cameraScale: cameraScale)
        guard let move = plan.bubbleMoves.first(where: { time > $0.start && time < $0.end }) else { return home }
        let moved = settings.at(anchor: move.corner, outputSize: outputSize)
        let away = webcamRect(moved, outputSize: outputSize, cameraScale: cameraScale)
        return lerp(home, away, CGFloat(move.progress(at: time)))
    }
}

// MARK: - Fitting zooms around the bubble

enum VideoZoomCameraFit {
    enum Mode: String, CaseIterable, Identifiable {
        /// Move each zoom's framing (or loupe) clear of the bubble; where the
        /// frame's edge is in the way, zoom a little deeper.
        case shiftFraming
        /// Slide the bubble to a free corner while the zoom plays.
        case moveCamera

        var id: String { rawValue }
        var title: String {
            switch self {
            case .shiftFraming: return L("Shift the Zooms")
            case .moveCamera: return L("Move the Camera Instead")
            }
        }
    }

    struct Result: Equatable {
        /// Zooms that were under the bubble.
        var covered = 0
        var adjusted = 0
        /// Covered, but no shift (or corner) clears them.
        var unfixed = 0
    }

    /// Around the subject of a full zoom, the part that has to stay
    /// visible (a share of the output's short side).
    static let subjectMargin: CGFloat = 0.07
    /// Seconds a zoom may spend under the bubble before it counts.
    static let tolerance = 0.25
    private static let step = 0.1

    /// The bubble on the output, normalized with y down (nil: no bubble
    /// at that moment).
    static func bubbleBox(plan: VideoRenderPlan, time: Double, anchor: VideoWebcamSettings.Anchor? = nil) -> CGRect? {
        guard var webcam = plan.webcam, webcam.visible, plan.hasCameraFootage(at: time), plan.cameraLayout(at: time) == nil else { return nil }
        let output = plan.outputCanvasSize
        if let anchor { webcam = webcam.at(anchor: anchor, outputSize: output) }
        let scale = plan.camera.state(at: time).scale
        let rect = VideoFrameRenderer.webcamRect(webcam, outputSize: output, cameraScale: scale)
        let margin = min(output.width, output.height) * 0.015
        let padded = rect.insetBy(dx: -margin, dy: -margin)
        return CGRect(x: padded.minX / output.width, y: (output.height - padded.maxY) / output.height, width: padded.width / output.width, height: padded.height / output.height)
    }

    /// What a zoom shows that must stay in view, on the output (normalized,
    /// y down): around its subject for a full zoom, the lens for a loupe.
    static func subjectBox(of region: VideoZoomRegion, plan: VideoRenderPlan, time: Double) -> CGRect {
        let output = plan.outputCanvasSize
        let shortSide = min(output.width, output.height)
        let point = plan.canvasPoint(forVideoPoint: plan.subject(of: region, at: plan.sourceTime(forTimelineTime: time)))
        let window = plan.camera.state(at: time).window(in: plan.canvasSize)
        let p = CGPoint(x: (point.x - window.minX) / max(window.width, 1), y: (point.y - window.minY) / max(window.height, 1))
        if let loupe = region.loupe {
            let half = CGFloat(loupe.clamped.size) * shortSide / 2
            let center = CGPoint(x: p.x + CGFloat(region.offsetX), y: p.y + CGFloat(region.offsetY))
            return CGRect(x: center.x - half / output.width, y: center.y - half / output.height, width: 2 * half / output.width, height: 2 * half / output.height)
        }
        let halfX = subjectMargin * shortSide / output.width
        let halfY = subjectMargin * shortSide / output.height
        return CGRect(x: p.x - halfX, y: p.y - halfY, width: halfX * 2, height: halfY * 2)
    }

    /// The moments a zoom is fully in (timeline seconds).
    static func heldTimes(of region: VideoZoomRegion, plan: VideoRenderPlan) -> [Double] {
        if region.loupe != nil {
            guard let span = plan.loupes.first(where: { $0.region.id == region.id }) else { return [] }
            return stride(from: span.start, through: span.end, by: step).filter { span.openness(at: $0) >= 0.8 }
        }
        let ranges = VideoDemoProject.timelineRanges(sourceStart: region.start, sourceEnd: region.end, segments: plan.segments)
        let target = 1 + (region.scale - 1) * 0.8
        return ranges.flatMap { range in
            stride(from: range.lowerBound, through: range.upperBound, by: step).filter { plan.camera.state(at: $0).scale >= target }
        }
    }

    /// The times a zoom's subject sits under the bubble, and their boxes.
    static func collisions(of region: VideoZoomRegion, plan: VideoRenderPlan, anchor: VideoWebcamSettings.Anchor? = nil) -> [(box: CGRect, bubble: CGRect)] {
        heldTimes(of: region, plan: plan).compactMap { time in
            guard let bubble = bubbleBox(plan: plan, time: time, anchor: anchor) else { return nil }
            let box = subjectBox(of: region, plan: plan, time: time)
            return box.intersects(bubble) ? (box, bubble) : nil
        }
    }

    static func isCovered(_ region: VideoZoomRegion, plan: VideoRenderPlan, anchor: VideoWebcamSettings.Anchor? = nil) -> Bool {
        Double(collisions(of: region, plan: plan, anchor: anchor).count) * step >= tolerance
    }

    /// Checks every zoom and fixes the covered ones. `makePlan` renders
    /// the project's plan (it is rebuilt after each shift).
    static func fit(_ project: inout VideoDemoProject, mode: Mode, makePlan: (VideoDemoProject) -> VideoRenderPlan) -> Result {
        var result = Result()
        var plan = makePlan(project)
        let ids = project.zoomRegions.map(\.id)
        for id in ids {
            guard let index = project.zoomRegions.firstIndex(where: { $0.id == id }),
                  isCovered(project.zoomRegions[index], plan: plan) else { continue }
            result.covered += 1
            switch mode {
            case .moveCamera:
                let region = project.zoomRegions[index]
                if let corner = freeCorner(for: region, plan: plan, home: project.webcam.anchor) {
                    project.zoomRegions[index].cameraCorner = corner
                    result.adjusted += 1
                } else {
                    result.unfixed += 1
                }
            case .shiftFraming:
                let original = project.zoomRegions[index]
                var trial = project
                var cleared = false
                for _ in 0..<4 {
                    let region = trial.zoomRegions[index]
                    let hits = collisions(of: region, plan: plan)
                    guard Double(hits.count) * step >= tolerance else { cleared = true; break }
                    guard let nudge = nudge(for: hits) else { break }
                    trial.zoomRegions[index].offsetX = clampOffset(region.offsetX + Double(nudge.x))
                    trial.zoomRegions[index].offsetY = clampOffset(region.offsetY + Double(nudge.y))
                    guard trial.zoomRegions[index] != region else { break }
                    plan = makePlan(trial)
                }
                if !cleared, !isCovered(trial.zoomRegions[index], plan: plan) { cleared = true }
                if !cleared, original.loupe == nil {
                    // The frame's edge stops the framing from moving (a
                    // subject near a corner): zooming a little deeper pulls
                    // the subject in from the corner instead.
                    trial.zoomRegions[index] = original
                    var scale = original.scale
                    while !cleared, scale < min(original.scale + 1.5, VideoZoomRegion.scaleRange.upperBound) - 0.001 {
                        scale = min(scale + 0.25, VideoZoomRegion.scaleRange.upperBound)
                        trial.zoomRegions[index].scale = scale
                        plan = makePlan(trial)
                        cleared = !isCovered(trial.zoomRegions[index], plan: plan)
                    }
                }
                if cleared {
                    project = trial
                    result.adjusted += 1
                } else {
                    project.zoomRegions[index] = original
                    plan = makePlan(project)
                    result.unfixed += 1
                }
            }
        }
        return result
    }

    private static func clampOffset(_ value: Double) -> Double {
        min(max(value, VideoZoomRegion.offsetRange.lowerBound), VideoZoomRegion.offsetRange.upperBound)
    }

    /// The smallest move that takes the boxes out from under the bubble:
    /// sideways or up/down, whichever is shorter and keeps them on screen.
    static func nudge(for hits: [(box: CGRect, bubble: CGRect)]) -> CGPoint? {
        guard !hits.isEmpty else { return nil }
        let gap: CGFloat = 0.012
        var best: (move: CGPoint, cost: CGFloat)?
        let candidates: [(CGRect, CGRect) -> CGPoint] = [
            { box, bubble in CGPoint(x: bubble.minX - box.maxX - gap, y: 0) },
            { box, bubble in CGPoint(x: bubble.maxX - box.minX + gap, y: 0) },
            { box, bubble in CGPoint(x: 0, y: bubble.minY - box.maxY - gap) },
            { box, bubble in CGPoint(x: 0, y: bubble.maxY - box.minY + gap) },
        ]
        for candidate in candidates {
            // The move that clears every moment in this direction.
            var move = CGPoint.zero
            for hit in hits {
                let m = candidate(hit.box, hit.bubble)
                if abs(m.x) > abs(move.x) { move.x = m.x }
                if abs(m.y) > abs(move.y) { move.y = m.y }
            }
            let fits = hits.allSatisfy { hit in
                let moved = hit.box.offsetBy(dx: move.x, dy: move.y)
                return moved.minX >= -0.001 && moved.maxX <= 1.001 && moved.minY >= -0.001 && moved.maxY <= 1.001
            }
            guard fits else { continue }
            let cost = abs(move.x) + abs(move.y)
            if best == nil || cost < best!.cost { best = (move, cost) }
        }
        return best?.move
    }

    /// The nearest corner where the bubble leaves the zoom clear: across
    /// first, then up or down, then diagonally.
    static func freeCorner(for region: VideoZoomRegion, plan: VideoRenderPlan, home: VideoWebcamSettings.Anchor) -> VideoWebcamSettings.Anchor? {
        let corners: [VideoWebcamSettings.Anchor] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let unit = home.unit
        let ordered = corners.filter { $0 != home }.sorted { a, b in
            func cost(_ c: VideoWebcamSettings.Anchor) -> Double {
                let dx = abs(c.unit.x - unit.x), dy = abs(c.unit.y - unit.y)
                // Across (same height) is the least surprising move.
                return Double(dx) + Double(dy) * 1.1
            }
            return cost(a) < cost(b)
        }
        return ordered.first { !isCovered(region, plan: plan, anchor: $0) && !collidesAnywhere(region, plan: plan, anchor: $0) }
    }

    /// Even a moment under the bubble in its new corner is too many.
    private static func collidesAnywhere(_ region: VideoZoomRegion, plan: VideoRenderPlan, anchor: VideoWebcamSettings.Anchor) -> Bool {
        !collisions(of: region, plan: plan, anchor: anchor).isEmpty
    }
}
