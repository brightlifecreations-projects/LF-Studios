import AppKit
import AVFoundation
import SwiftUI

/// The editor's annotations (overlays) and clicks.
extension VideoEditorModel {
    // MARK: Overlays

    var selectedOverlay: VideoDemoOverlayEffect? {
        if case .overlay(let id) = selection {
            return project.overlayEffects.first { $0.id == id }
        }
        return nil
    }

    func addOverlay(_ kind: VideoDemoOverlayEffectKind) {
        if refuseLocked(.annotations) { return }
        // A picture needs a file first (VideoImageOverlays.swift).
        guard kind != .image else { return chooseImageOverlay() }
        let time = clock.time
        let window = sourceWindow(timelineStart: time, timelineEnd: min(time + (kind == .blur ? 4 : 3), timelineDuration))
        let sourceStart = window.lowerBound
        let sourceEnd = window.upperBound
        var effect = VideoDemoOverlayEffect(
            kind: kind,
            time: sourceStart,
            duration: max(sourceEnd - sourceStart, 0.5),
            x: 0.5,
            y: kind == .text ? 0.14 : 0.5,
            width: kind == .text ? 0.5 : (kind == .arrow ? 0.18 : 0.3),
            height: kind == .text ? 0.09 : (kind == .arrow ? 0.18 : (kind == .spotlight ? 0.3 : 0.2)),
            // A placeholder the user types over: in their language.
            text: kind == .text ? L("Your text") : kind.title,
            color: VideoOverlayStyleMemory.color(for: kind),
            thickness: VideoOverlayStyleMemory.thickness(for: kind)
        )
        if kind == .spotlight { effect.shape = VideoOverlayStyleMemory.shape }
        if kind == .blur { effect.strength = VideoOverlayStyleMemory.blurStrength }
        // Land where it can be seen: zooms and vertical reframing show only
        // part of the frame, so place (and if needed shrink) it inside that.
        let visible = visibleRegion(at: time)
        effect.width = min(effect.width, Double(visible.width) * 0.9)
        effect.height = min(effect.height, Double(visible.height) * 0.9)
        // Text goes near the top: captions, keycaps, and the camera bubble
        // live at the bottom.
        var center = CGPoint(x: visible.midX, y: kind == .text ? visible.minY + visible.height * 0.14 : visible.midY)
        if kind != .text, let raw = plan.cursorTrack?.visiblePosition(at: sourceStart) {
            // Annotations live in the (cropped) frame's coordinates.
            let pointer = project.crop.normalized.map(raw)
            if visible.insetBy(dx: visible.width * 0.05, dy: visible.height * 0.05).contains(pointer) {
                center = pointer
                if kind == .arrow {
                    // The head (top right) lands just beside the pointer.
                    center.x -= CGFloat(effect.width / 2) - visible.width * 0.02
                    center.y += CGFloat(effect.height / 2) + visible.height * 0.03
                }
            }
        }
        let halfWidth = CGFloat(effect.width / 2)
        let halfHeight = CGFloat(effect.height / 2)
        effect.x = Double(min(max(center.x, visible.minX + halfWidth), visible.maxX - halfWidth))
        effect.y = Double(min(max(center.y, visible.minY + halfHeight), visible.maxY - halfHeight))
        if kind == .arrow {
            // Saved ends: it can be turned to point any way.
            let points = effect.arrowPoints
            effect.setArrow(tail: points.tail, head: points.head)
        }
        // New annotations stack ON TOP of anything they overlap: a higher
        // lane on the timeline, drawn in front in the video.
        let overlapping = project.overlayEffects.filter {
            $0.time < effect.time + effect.duration && $0.time + $0.duration > effect.time
        }
        effect.layer = (overlapping.map(\.layer).max() ?? -1) + 1
        mutate { project in
            project.overlayEffects.append(effect)
            project.overlayEffects = VideoDemoProject.normalizedEffectLayers(project.overlayEffects)
        }
        selection = .overlay(effect.id)
    }

    /// The part of the frame on screen at a timeline moment, in annotation
    /// coordinates (0…1 across the cropped recording): zooms and vertical
    /// reframing show only some of it.
    func visibleRegion(at time: Double) -> CGRect {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        let canvas = plan.canvasSize
        let stage = (project.reframeActive ? project.reframeScene() : project).stageRect(in: canvas)
        guard canvas.width > 0, canvas.height > 0, stage.width > 0, stage.height > 0 else { return whole }
        var window = cameraState(at: time).window(in: canvas)
        if let reframe = plan.reframe {
            // The output is a window across the (camera's) scene.
            let fraction = reframe.windowFraction
            let origin = min(max(reframe.center(at: time) - fraction / 2, 0), 1 - fraction)
            window = CGRect(x: window.minX + window.width * origin, y: window.minY, width: window.width * fraction, height: window.height)
        }
        let region = CGRect(
            x: (window.minX - stage.minX) / stage.width,
            y: (window.minY - stage.minY) / stage.height,
            width: window.width / stage.width,
            height: window.height / stage.height
        ).intersection(whole)
        return region.width > 0.05 && region.height > 0.05 ? region : whole
    }

    func updateOverlay(_ id: UUID, coalesce: String? = nil, _ change: (inout VideoDemoOverlayEffect) -> Void) {
        mutate(coalesce: coalesce) { project in
            guard let index = project.overlayEffects.firstIndex(where: { $0.id == id }) else { return }
            let old = project.overlayEffects[index]
            change(&project.overlayEffects[index])
            var effect = project.overlayEffects[index]
            effect.width = min(max(effect.width, 0.04), 1)
            effect.height = min(max(effect.height, 0.03), 1)
            effect.x = min(max(effect.x, 0.02), 0.98)
            effect.y = min(max(effect.y, 0.02), 0.98)
            effect.duration = max(effect.duration, 0.2)
            // A moved or resized arrow takes its ends along; a blur that
            // follows something takes its path along.
            effect.refitArrowEnds(from: old)
            effect.followMove(from: old)
            project.overlayEffects[index] = effect
        }
    }

    /// Text size in canvas points (a 1080-tall frame's): it follows the
    /// box's height, so the size control sets that and keeps the width.
    func textSize(of effect: VideoDemoOverlayEffect) -> Double {
        let stage = (project.reframeActive ? project.reframeScene() : project).stageRect(in: plan.canvasSize)
        return min(Double(stage.height) * effect.height * Self.textSizePerBoxHeight, 64)
    }

    func setTextSize(_ size: Double, of id: UUID) {
        let stage = (project.reframeActive ? project.reframeScene() : project).stageRect(in: plan.canvasSize)
        guard stage.height > 0 else { return }
        updateOverlay(id, coalesce: "text-size-\(id)") { effect in
            effect.height = size / Self.textSizePerBoxHeight / Double(stage.height)
        }
    }

    /// The renderer draws text at 0.46 of its box's height (at most 64).
    static let textSizePerBoxHeight = 0.46

    func setOverlayWindow(_ id: UUID, start: Double, end: Double, coalesce: String) {
        let safeStart = min(max(start, 0), max(timelineDuration - 0.2, 0))
        let safeEnd = min(max(end, safeStart + 0.2), timelineDuration)
        let window = sourceWindow(timelineStart: safeStart, timelineEnd: safeEnd)
        let sourceStart = window.lowerBound
        let sourceEnd = window.upperBound
        updateOverlay(id, coalesce: coalesce) { effect in
            effect.time = sourceStart
            effect.duration = max(sourceEnd - sourceStart, 0.2)
        }
    }

    func setOverlayLayer(_ id: UUID, layer: Int, coalesce: String) {
        updateOverlay(id, coalesce: coalesce) { effect in
            effect.layer = min(max(layer, 0), 7)
        }
    }

    /// Settles lanes after a pill drag.
    func finishOverlayDrag() {
        endGesture()
        let normalized = VideoDemoProject.normalizedEffectLayers(project.overlayEffects)
        if normalized != project.overlayEffects {
            // Part of the same gesture's undo step.
            var next = project
            next.overlayEffects = normalized
            project = next
        }
    }

    func deleteOverlay(_ id: UUID) {
        mutate { project in
            project.overlayEffects.removeAll { $0.id == id }
            project.overlayEffects = VideoDemoProject.normalizedEffectLayers(project.overlayEffects)
        }
        if selection == .overlay(id) { selection = .none }
        showNotice(L("Removed — ⌘Z to undo"), symbol: "trash")
    }

    // MARK: Clicks

    func moveClick(_ id: UUID, toTimeline time: Double, coalesce: String? = nil) {
        let sourceTime = sourceTime(forTimeline: min(max(time, 0), timelineDuration))
        mutate(coalesce: coalesce ?? "click-\(id)") { project in
            guard let index = project.clickEvents.firstIndex(where: { $0.id == id }) else { return }
            let press = project.clickEvents[index].pressDuration
            project.clickEvents[index].time = sourceTime
            project.clickEvents[index].endTime = sourceTime + press
            project.clickEvents.sort { $0.time < $1.time }
        }
    }

    func deleteClick(_ id: UUID) {
        mutate { project in
            project.clickEvents.removeAll { $0.id == id }
        }
        if selection == .click(id) { selection = .none }
        showNotice(L("Click removed — ⌘Z to undo"), symbol: "trash")
    }
}
