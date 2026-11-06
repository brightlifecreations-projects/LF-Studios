import AppKit
import AVFoundation
import SwiftUI

/// Undo and redo: one step per edit, kept while the app runs when a project closes and reopens.
extension VideoEditorModel {
    // MARK: Undo

    /// One step back: the project before an edit, and what the edit was
    /// ("Delete Zoom").
    struct UndoStep {
        var project: VideoDemoProject
        var label: String
    }

    /// Every edit goes through here. `coalesce` merges a continuous gesture
    /// (a slider drag, a block drag) into ONE undo step. `label` names it
    /// for the undo message (worked out from the change when not given).
    func mutate(coalesce key: String? = nil, label: String? = nil, _ change: (inout VideoDemoProject) -> Void) {
        var next = project
        change(&next)
        guard next != project else { return }
        // Inside an open compound only its clips change (1.16.0).
        guard allowsInsideOpenCompound(from: project, to: &next) else {
            showNotice(L("Inside a compound clip only its clips change. Esc goes back to the whole video."), symbol: "square.stack.3d.down.right")
            return
        }
        // Linkage (~): what's on the tracks above the main track follows
        // the main track's clips (VideoLayers.swift).
        if Settings.videoTimelineLinkage, !project.layerTracks.isEmpty, next.layerTracks == project.layerTracks,
           next.timelineClips != project.timelineClips || next.timelineLeadIn != project.timelineLeadIn {
            next.followMainTrack(from: project, oldTotal: sourceDuration, newTotal: next.sourceAxisDuration ?? sourceDuration, magnet: Settings.videoTimelineMagnet)
        }
        let now = Date()
        // One press of the mouse is one step however long the hand rests
        // mid-drag; apart from that, 1.5 s apart starts a new step.
        let stroke = Self.mouseStroke()
        let sameStroke = stroke != nil && stroke == lastMutationStroke
        if key == nil || key != lastCoalesceKey || (now.timeIntervalSince(lastMutation) > 1.5 && !sameStroke) {
            undoStack.append(UndoStep(project: project, label: label ?? pendingUndoLabel ?? VideoEditDescription.describe(from: project, to: next)))
            pendingUndoLabel = nil
            if undoStack.count > 300 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        lastCoalesceKey = key
        lastMutation = now
        lastMutationStroke = stroke
        project = next
        canUndo = !undoStack.isEmpty
        canRedo = false
    }

    /// The mouse press the current event belongs to: AppKit gives a press's
    /// down, drags and up the same event number. Nil outside a drag.
    nonisolated(unsafe) static var mouseStroke: () -> Int? = {
        guard let event = NSApp?.currentEvent,
              [.leftMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(event.type) else { return nil }
        return event.eventNumber
    }

    /// Ends a coalesced gesture so the next edit starts a new undo step.
    func endGesture() {
        lastCoalesceKey = nil
    }

    /// The last edit joins the one before it: one ⌘Z takes back both (an
    /// action made of two steps, like adding a recording and moving it).
    func joinLastUndoSteps(label: String? = nil) {
        guard undoStack.count >= 2 else { return }
        let last = undoStack.removeLast()
        if let label { undoStack[undoStack.count - 1].label = label } else { _ = last }
        canUndo = !undoStack.isEmpty
    }

    /// Something is being dragged (a slider, a clip edge, the playhead).
    var isGestureInProgress: Bool {
        (lastCoalesceKey != nil && Date().timeIntervalSince(lastMutation) < 1.5) || holdsPlayerRebuild || isScrubbing || layoutDurationLock != nil
    }

    /// What ⌘Z would undo, and ⇧⌘Z redo.
    var undoLabel: String? { undoStack.last?.label }
    var redoLabel: String? { redoStack.last?.label }

    func undo() {
        guard let step = undoStack.popLast() else { return }
        redoStack.append(UndoStep(project: project, label: step.label))
        lastCoalesceKey = nil
        project = step.project.keepingNotes(of: project)
        validateSelection()
        canUndo = !undoStack.isEmpty
        canRedo = true
        showNotice(VideoEditDescription.undoTitle(step.label), symbol: "arrow.uturn.backward")
    }

    func redo() {
        guard let step = redoStack.popLast() else { return }
        undoStack.append(UndoStep(project: project, label: step.label))
        lastCoalesceKey = nil
        project = step.project.keepingNotes(of: project)
        validateSelection()
        canUndo = true
        canRedo = !redoStack.isEmpty
        showNotice(VideoEditDescription.redoTitle(step.label), symbol: "arrow.uturn.forward")
    }

    // MARK: Undo across reopening

    private struct KeptHistory {
        let project: VideoDemoProject
        let undo: [UndoStep]
        let redo: [UndoStep]
    }

    /// Undo and redo of editors closed this session, by recording: open
    /// the video again (before quitting) and ⌘Z still steps back.
    private static var keptHistory: [String: KeptHistory] = [:]
    private static var keptHistoryOrder: [String] = []

    private var historyKey: String { VideoFileIdentity.canonicalURL(project.sourceURL).path }

    /// Pictures and songs this editor's project, undo, and redo use.
    func assetPathsInHistory() -> Set<String> {
        var paths = project.assetPaths
        for step in undoStack + redoStack { paths.formUnion(step.project.assetPaths) }
        return paths
    }

    /// Pictures and songs closed editors' kept undo history uses.
    static func keptHistoryAssetPaths() -> Set<String> {
        var paths = Set<String>()
        for kept in keptHistory.values {
            paths.formUnion(kept.project.assetPaths)
            for step in kept.undo + kept.redo { paths.formUnion(step.project.assetPaths) }
        }
        return paths
    }

    func keepHistoryForSession() {
        guard isReady, !undoStack.isEmpty || !redoStack.isEmpty else { return }
        let key = historyKey
        Self.keptHistory[key] = KeptHistory(project: project, undo: undoStack, redo: redoStack)
        Self.keptHistoryOrder.removeAll { $0 == key }
        Self.keptHistoryOrder.append(key)
        while Self.keptHistoryOrder.count > 12 {
            Self.keptHistory.removeValue(forKey: Self.keptHistoryOrder.removeFirst())
        }
    }

    /// The history kept when this recording's editor closed, if the draft
    /// it reopens with is still exactly what it closed with.
    func restoreKeptHistory(for opened: VideoDemoProject) {
        guard let kept = Self.keptHistory[VideoFileIdentity.canonicalURL(opened.sourceURL).path], kept.project == opened else { return }
        undoStack = kept.undo
        redoStack = kept.redo
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func validateSelection(keepingRange: Bool = false) {
        validateExtraSelection()
        switch selection {
        case .zoom(let id) where !project.zoomRegions.contains(where: { $0.id == id }),
             .overlay(let id) where !project.overlayEffects.contains(where: { $0.id == id }),
             .click(let id) where !project.clickEvents.contains(where: { $0.id == id }),
             .caption(let id) where !project.captions.contains(where: { $0.id == id }),
             .keystroke(let id) where !project.keystrokes.contains(where: { $0.id == id }),
             .cameraLayout(let id) where !project.cameraLayouts.contains(where: { $0.id == id }),
             .clip(let id) where !project.timelineClips.contains(where: { $0.id == id }):
            selection = .none
        case .range where !keepingRange:
            selection = .none
        default:
            break
        }
    }
}
