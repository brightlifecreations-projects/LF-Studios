import AppKit
import AVFoundation
import SwiftUI

// MARK: - Every editing action, by name (1.14.0)

/// Each action of the timeline's toolbar, keys and menus, one case each,
/// run with `VideoEditorModel.perform(_:)`. Each makes one ⌘Z step and
/// refuses on a locked track, so anything that drives the editor (a key, a
/// button, a future MCP connection) gets the same result.
enum VideoEditCommand: Equatable, CaseIterable, Identifiable {
    case selectTool
    case splitTool
    case undo
    case redo
    case split
    case splitAllTracks
    case deleteLeft
    case deleteRight
    case delete
    case addMarker
    case freezeFrame
    case reverse
    case mirror
    case rotate
    case crop
    case recordVoiceover
    case toggleMagnet
    case toggleSnapping
    case toggleLinkage
    case togglePreviewAxis
    case zoomToFit
    case toggleEnabled
    case group
    case ungroup
    case extractAudio
    case selectLeft
    case selectRight
    case copy
    case paste
    case markIn
    case markOut
    case addText
    case addArrow
    case addHighlight
    case addBlur
    // 1.15.0
    case addKeyframe
    case previousKeyframe
    case nextKeyframe
    /// A text clip on a track of its own (VideoTextClips.swift).
    case addTextClip
    /// An edit with values (a setting at the playhead, a mode, a mask…) on
    /// the selected item above the main track (VideoItemEdits.swift).
    case edit(VideoItemEdit)
    /// An edit of the main track's clip (selected, or under the playhead).
    case clip(VideoClipEdit)
    /// A sound's volume keys, loudness, beats.
    case audio(VideoAudioEdit)

    /// The commands without values (keys, menus, the command palette).
    static let allCases: [VideoEditCommand] = [
        .selectTool, .splitTool, .undo, .redo, .split, .splitAllTracks, .deleteLeft, .deleteRight, .delete, .addMarker,
        .freezeFrame, .reverse, .mirror, .rotate, .crop, .recordVoiceover, .toggleMagnet, .toggleSnapping, .toggleLinkage,
        .togglePreviewAxis, .zoomToFit, .toggleEnabled, .group, .ungroup, .extractAudio, .selectLeft, .selectRight,
        .copy, .paste, .markIn, .markOut, .addText, .addArrow, .addHighlight, .addBlur, .addKeyframe, .previousKeyframe, .nextKeyframe,
        .addTextClip,
    ]

    /// A stable name (menus keep it; a future MCP connection can send it).
    var rawValue: String {
        if case .edit(let edit) = self { return "edit." + edit.name }
        if case .clip(let edit) = self { return "clip." + edit.name }
        if case .audio(let edit) = self { return "audio." + edit.name }
        return String(describing: self)
    }

    init?(rawValue: String) {
        guard let command = Self.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = command
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selectTool: return L("Select")
        case .splitTool: return L("Split tool")
        case .undo: return L("Undo")
        case .redo: return L("Redo")
        case .split: return L("Split")
        case .splitAllTracks: return L("Split all tracks")
        case .deleteLeft: return L("Delete left")
        case .deleteRight: return L("Delete right")
        case .delete: return L("Delete")
        case .addMarker: return L("Add marker")
        case .freezeFrame: return L("Freeze frame")
        case .reverse: return L("Reverse")
        case .mirror: return L("Mirror")
        case .rotate: return L("Rotate")
        case .crop: return L("Crop")
        case .recordVoiceover: return L("Record voiceover")
        case .toggleMagnet: return L("Main track magnet")
        case .toggleSnapping: return L("Auto snapping")
        case .toggleLinkage: return L("Linkage")
        case .togglePreviewAxis: return L("Preview axis")
        case .zoomToFit: return L("Zoom to fit")
        case .toggleEnabled: return L("Turn clip on or off")
        case .group: return L("Group")
        case .ungroup: return L("Ungroup")
        case .extractAudio: return L("Extract Audio")
        case .selectLeft: return L("Select left of playhead")
        case .selectRight: return L("Select right of playhead")
        case .copy: return L("Copy")
        case .paste: return L("Paste")
        case .markIn: return L("Mark in")
        case .markOut: return L("Mark out")
        case .addText: return L("Text")
        case .addArrow: return L("Arrow")
        case .addHighlight: return L("Highlight")
        case .addBlur: return L("Blur")
        case .addKeyframe: return L("Add keyframe")
        case .previousKeyframe: return L("Previous keyframe")
        case .nextKeyframe: return L("Next keyframe")
        case .addTextClip: return L("Text clip")
        case .edit(let edit): return edit.title
        case .clip(let edit): return edit.title
        case .audio(let edit): return edit.title
        }
    }

    var symbol: String {
        switch self {
        case .selectTool: return "cursorarrow"
        case .splitTool: return "scissors.badge.ellipsis"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .split: return "scissors"
        case .splitAllTracks: return "rectangle.split.3x1"
        case .deleteLeft: return "arrow.left.to.line.compact"
        case .deleteRight: return "arrow.right.to.line.compact"
        case .delete: return "trash"
        case .addMarker: return "flag"
        case .freezeFrame: return "snowflake"
        case .reverse: return "arrow.uturn.left.circle"
        case .mirror: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .rotate: return "rotate.right"
        case .crop: return "crop"
        case .recordVoiceover: return "mic"
        case .toggleMagnet: return "magnet"
        case .toggleSnapping: return "arrow.right.and.line.vertical.and.arrow.left"
        case .toggleLinkage: return "link"
        case .togglePreviewAxis: return "eye"
        case .zoomToFit: return "arrow.left.and.right.square"
        case .toggleEnabled: return "eye.slash"
        case .group: return "rectangle.3.group"
        case .ungroup: return "rectangle.3.group.bubble"
        case .extractAudio: return "waveform.badge.plus"
        case .selectLeft: return "arrow.left.to.line"
        case .selectRight: return "arrow.right.to.line"
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .markIn: return "chevron.left.to.line"
        case .markOut: return "chevron.right.to.line"
        case .addText: return "textformat"
        case .addArrow: return "arrow.up.right"
        case .addHighlight: return "rectangle.dashed"
        case .addBlur: return "eye.slash"
        case .addKeyframe: return "diamond"
        case .previousKeyframe: return "chevron.left.to.line"
        case .nextKeyframe: return "chevron.right.to.line"
        case .addTextClip: return "character.textbox"
        case .edit, .clip, .audio: return "slider.horizontal.3"
        }
    }

    /// The keys, as the Guide and the menus write them ("" for none):
    /// the ones set in Keyboard Shortcuts.
    var keys: String {
        switch self {
        case .undo: return "⌘Z"
        case .redo: return "⇧⌘Z"
        case .delete: return "⌫"
        default: return VideoKeymap.current.binding(for: self)?.display ?? ""
        }
    }

    /// LF Studios' own keys (before any preset or change).
    var standardKeys: String {
        switch self {
        case .selectTool: return "A"
        case .splitTool: return "B"
        case .undo: return "⌘Z"
        case .redo: return "⇧⌘Z"
        case .split: return "⌘B"
        case .splitAllTracks: return "⇧⌘B"
        case .deleteLeft: return "Q"
        case .deleteRight: return "W"
        case .delete: return "⌫"
        case .toggleMagnet: return "P"
        case .toggleSnapping: return "N"
        case .toggleLinkage: return "`"
        case .togglePreviewAxis: return "S"
        case .zoomToFit: return "⇧Z"
        case .toggleEnabled: return "V"
        case .group: return "⌘G"
        case .ungroup: return "⇧⌘G"
        case .extractAudio: return "⇧⌘A"
        case .selectLeft: return "["
        case .selectRight: return "]"
        case .copy: return "⌘C"
        case .paste: return "⌘V"
        case .markIn: return "I"
        case .markOut: return "O"
        case .addText: return "⌥T"
        case .addArrow: return "⌥A"
        case .addHighlight: return "⌥H"
        case .addBlur: return "⌥B"
        case .addKeyframe: return "⌥K"
        case .previousKeyframe: return "⌥["
        case .nextKeyframe: return "⌥]"
        case .addTextClip: return "⌥⇧T"
        case .addMarker, .freezeFrame, .reverse, .mirror, .rotate, .crop, .recordVoiceover, .edit, .clip, .audio: return ""
        }
    }

    /// The command for a key press in the editor (nil: not one of these):
    /// LF Studios' keys, a preset's, or your own (VideoKeymap.swift).
    static func command(key: String, modifiers: NSEvent.ModifierFlags) -> VideoEditCommand? {
        VideoKeymap.current.command(key: key, modifiers: modifiers.intersection([.command, .shift, .option, .control]))
    }

    /// A switch (P, N, ~, S): its state.
    var isSwitch: Bool { [.toggleMagnet, .toggleSnapping, .toggleLinkage, .togglePreviewAxis].contains(self) }
}

/// The timeline's pointer: select and move, or split where clicked.
enum VideoTimelineTool: Equatable {
    case select
    case split
}

extension VideoEditorModel {
    /// Runs one editing action. False when it couldn't (nothing to act on,
    /// a locked track); the editor says why.
    @discardableResult
    func perform(_ command: VideoEditCommand) -> Bool {
        switch command {
        case .selectTool:
            timelineTool = .select
        case .splitTool:
            timelineTool = timelineTool == .split ? .select : .split
            if timelineTool == .split { showNotice(L("Click a clip to split it there. A or Esc goes back to Select."), symbol: "scissors") }
        case .undo:
            guard canUndo else { return false }
            undo()
        case .redo:
            guard canRedo else { return false }
            redo()
        case .split:
            return splitSelectedOrMain(at: clock.time)
        case .splitAllTracks:
            return splitAllTracks(at: clock.time)
        case .deleteLeft:
            return deleteSide(leading: true)
        case .deleteRight:
            return deleteSide(leading: false)
        case .delete:
            guard selection != .none || selectedAudioPiece != nil else { return false }
            deleteSelection()
        case .addMarker:
            return addMarker() != nil
        case .freezeFrame:
            Task { await freezeFrame() }
        case .reverse:
            Task { await reverseSelection() }
        case .mirror:
            return turnSelection(mirror: true)
        case .rotate:
            return turnSelection(mirror: false)
        case .crop:
            if case .layer = selection {
                // Its crop is in Properties (VideoLayerViews.swift).
                showNotice(L("Crop it in Properties ▸ Crop"), symbol: "crop")
            } else {
                beginCrop()
            }
        case .recordVoiceover:
            toggleVoiceover()
        case .toggleMagnet:
            Settings.videoTimelineMagnet.toggle()
            switchesChanged()
            showNotice(Settings.videoTimelineMagnet ? L("Main track magnet on: deleting a clip closes the gap") : L("Main track magnet off: deleting a clip leaves a black gap"), symbol: "magnet")
        case .toggleSnapping:
            Settings.videoTimelineSnapping.toggle()
            switchesChanged()
            showNotice(Settings.videoTimelineSnapping ? L("Auto snapping on") : L("Auto snapping off"), symbol: "arrow.right.and.line.vertical.and.arrow.left")
        case .toggleLinkage:
            Settings.videoTimelineLinkage.toggle()
            switchesChanged()
            showNotice(Settings.videoTimelineLinkage ? L("Linkage on: clips on other tracks move with the main track") : L("Linkage off: clips on other tracks stay where they are"), symbol: "link")
        case .togglePreviewAxis:
            Settings.videoTimelinePreviewAxis.toggle()
            switchesChanged()
            showNotice(Settings.videoTimelinePreviewAxis ? L("Preview axis on: the player shows the frame under the pointer") : L("Preview axis off"), symbol: "eye")
        case .zoomToFit:
            timelineZoom = 1
        case .toggleEnabled:
            return toggleSelectionEnabled()
        case .group:
            return groupSelection(true)
        case .ungroup:
            return groupSelection(false)
        case .extractAudio:
            return extractAudioOfSelection()
        case .selectLeft:
            return selectAcross(left: true)
        case .selectRight:
            return selectAcross(left: false)
        case .copy:
            if !copySelection() { copyCurrentFrame() }
        case .paste:
            return pasteClips()
        case .markIn:
            markRange(isIn: true)
        case .markOut:
            markRange(isIn: false)
        case .addText:
            addOverlay(.text)
        case .addArrow:
            addOverlay(.arrow)
        case .addHighlight:
            addOverlay(.highlight)
        case .addBlur:
            addOverlay(.blur)
        case .addKeyframe:
            guard let item = selectedLayerItem else {
                showNotice(L("Select a clip above the main track to add a keyframe"), symbol: "diamond")
                return false
            }
            return addKeyframes(item.id)
        case .previousKeyframe:
            return jumpToKeyframe(forward: false)
        case .nextKeyframe:
            return jumpToKeyframe(forward: true)
        case .addTextClip:
            addTextClip()
        case .edit(let edit):
            return perform(edit)
        case .clip(let edit):
            return perform(edit)
        case .audio(let edit):
            return perform(edit)
        }
        return true
    }

    /// Whether a switch (P, N, ~, S) is on.
    func isOn(_ command: VideoEditCommand) -> Bool {
        switch command {
        case .toggleMagnet: return Settings.videoTimelineMagnet
        case .toggleSnapping: return Settings.videoTimelineSnapping
        case .toggleLinkage: return Settings.videoTimelineLinkage
        case .togglePreviewAxis: return Settings.videoTimelinePreviewAxis
        case .selectTool: return timelineTool == .select
        case .splitTool: return timelineTool == .split
        case .recordVoiceover: return voiceover != nil
        default: return false
        }
    }

    private func switchesChanged() {
        switchesVersion += 1
    }

    // MARK: Split

    /// ⌘B: the selected item on a track above the main track (or a sound
    /// piece) when it's under the playhead, else the main track.
    func splitSelectedOrMain(at time: Double) -> Bool {
        if let item = selectedLayerItem, item.isShowing(at: time) {
            return splitLayerItem(item.id, at: time) != nil
        }
        if selectedAudioPiece != nil {
            splitAtPlayhead()
            return true
        }
        return splitMain(at: time)
    }

    @discardableResult
    func splitMain(at time: Double) -> Bool {
        if refuseLocked(.clips) { return false }
        guard let segment = segment(atTimeline: time) else { return false }
        let sourceTime = segment.sourceTime(forTimelineTime: time)
        var newID: UUID?
        mutate(label: "Split") { project in
            newID = project.splitClip(atSourceTime: sourceTime, totalDuration: sourceDuration)
        }
        if let newID { selection = .clip(newID) }
        return newID != nil
    }

    /// ⇧⌘B: every track at `time` in one step: the main track and every
    /// item above it and sound piece under the playhead.
    func splitAllTracks(at time: Double) -> Bool {
        var steps = 0
        if !project.isTrackLocked(.clips), splitMain(at: time) { steps += 1 }
        for (track, item) in project.layerItems where item.isShowing(at: time) && !project.isTrackLocked(.layer(project.layerTracks[track].id)) {
            if splitLayerItem(item.id, at: time) != nil { steps += 1 }
        }
        for track in project.audioTracks where !project.isTrackLocked(.sound(track.id)) {
            let before = project.audioTracks
            mutate(label: "Split") { project in
                guard let index = project.audioTracks.firstIndex(where: { $0.id == track.id }) else { return }
                _ = project.audioTracks[index].split(at: time, segments: segments)
            }
            if project.audioTracks != before { steps += 1 }
        }
        guard steps > 0 else {
            showNotice(L("Nothing to split at the playhead"), symbol: "scissors")
            return false
        }
        for _ in 1..<steps { joinLastUndoSteps(label: "Split") }
        selection = .none
        showNotice(L("Split every track at the playhead"), symbol: "scissors")
        return true
    }

    /// The split tool: what was clicked splits there.
    func splitClicked(at time: Double, track: VideoTimelineTrack) {
        switch track {
        case .layer(let id):
            guard let item = project.layerTracks.first(where: { $0.id == id })?.items.first(where: { $0.isShowing(at: time) }) else { return }
            _ = splitLayerItem(item.id, at: time)
        case .clips:
            splitMain(at: time)
        case .sound(let id):
            if refuseLocked(.sound(id)) { return }
            mutate(label: "Split") { project in
                guard let index = project.audioTracks.firstIndex(where: { $0.id == id }) else { return }
                _ = project.audioTracks[index].split(at: time, segments: segments)
            }
        default:
            break
        }
    }

    // MARK: Delete left / right

    /// Q / W: what's left (right) of the playhead goes from the selected
    /// item, or from the main track's clip under it.
    func deleteSide(leading: Bool) -> Bool {
        let time = clock.time
        if let item = selectedLayerItem {
            guard item.isShowing(at: time) else { return false }
            trimLayerItem(item.id, leading: leading, to: time, coalesce: false)
            return true
        }
        if refuseLocked(.clips) { return false }
        guard segment(atTimeline: time) != nil else { return false }
        trimSelectedClipToPlayhead(leading: leading)
        return true
    }

    // MARK: Mirror, rotate, on/off

    /// The main track's clip to act on: the selected one, else the one
    /// under the playhead.
    var targetClip: VideoDemoTimelineSegment? {
        if let id = selectedClipID, let segment = segments.first(where: { $0.id == id }) { return segment }
        return segment(atTimeline: clock.time)
    }

    func turnSelection(mirror: Bool) -> Bool {
        if let item = selectedLayerItem {
            setLayerItem(item.id, label: mirror ? "Mirror" : "Rotate") { item in
                if mirror { item.mirrored.toggle() } else { item.rotation = VideoLayerItem.nextQuarterTurn(after: item.rotation) }
            }
            return true
        }
        if refuseLocked(.clips) { return false }
        guard let clip = targetClip else { return false }
        mutate(label: mirror ? "Mirror" : "Rotate") { project in
            guard let index = project.timelineClips.firstIndex(where: { $0.id == clip.id }) else { return }
            if mirror { project.timelineClips[index].mirrored.toggle() } else { project.timelineClips[index].quarterTurns = (project.timelineClips[index].turns + 1) % 4 }
        }
        return true
    }

    /// V: the selected item (or main clip) off or on again.
    func toggleSelectionEnabled() -> Bool {
        if let item = selectedLayerItem {
            setLayerItem(item.id, label: item.enabled ? "Turn Off Clip" : "Turn On Clip") { $0.enabled.toggle() }
            return true
        }
        if refuseLocked(.clips) { return false }
        guard let clip = targetClip else { return false }
        mutate(label: clip.clip.disabled ? "Turn On Clip" : "Turn Off Clip") { project in
            guard let index = project.timelineClips.firstIndex(where: { $0.id == clip.id }) else { return }
            project.timelineClips[index].disabled.toggle()
        }
        return true
    }

    // MARK: Group

    func groupSelection(_ grouping: Bool) -> Bool {
        let ids = selectedIDs { if case .layer(let id) = $0 { return id } else { return nil } }
        if grouping {
            guard ids.count >= 2 else {
                showNotice(L("Select two or more clips above the main track to group them (⇧-click)"), symbol: "rectangle.3.group")
                return false
            }
            let group = UUID()
            mutate(label: "Group") { project in
                for id in ids { project.updateLayerItem(id) { $0.group = group } }
            }
            showNotice(L("Grouped: they move and delete together"), symbol: "rectangle.3.group")
        } else {
            let groups = Set(ids.compactMap { project.layerItem($0)?.group })
            guard !groups.isEmpty else { return false }
            mutate(label: "Ungroup") { project in
                for (_, item) in project.layerItems where item.group.map(groups.contains) == true { project.updateLayerItem(item.id) { $0.group = nil } }
            }
        }
        return true
    }

    // MARK: Select left / right

    func selectAcross(left: Bool) -> Bool {
        let time = clock.time
        var items: [Selection] = []
        for segment in segments where left ? segment.timelineEnd <= time + 0.001 : segment.timelineStart >= time - 0.001 {
            items.append(.clip(segment.id))
        }
        for (_, item) in project.layerItems where left ? item.end <= time + 0.001 : item.at >= time - 0.001 {
            items.append(.layer(item.id))
        }
        guard let first = items.first else { return false }
        selection = first
        extraSelection = Array(items.dropFirst())
        return true
    }

    // MARK: Copy, paste

    /// ⌘C with items above the main track selected: they're kept to paste.
    func copySelection() -> Bool {
        let ids = selectedIDs { if case .layer(let id) = $0 { return id } else { return nil } }
        let items = project.layerItems.map(\.item).filter { ids.contains($0.id) }
        guard !items.isEmpty else { return false }
        clipboardLayerItems = items
        showNotice(items.count == 1 ? L("Copied — ⌘V pastes it at the playhead") : L("Copied \(items.count) clips — ⌘V pastes them at the playhead"), symbol: "doc.on.doc")
        return true
    }

    /// ⌘V: the copied items at the playhead, keeping their spacing.
    func pasteClips() -> Bool {
        guard let first = clipboardLayerItems.map(\.at).min() else { return false }
        let shift = clock.time - first
        let pasted = clipboardLayerItems.map { item -> VideoLayerItem in
            var copy = item
            copy.id = UUID()
            copy.at = max(item.at + shift, 0)
            copy.group = nil
            return copy
        }
        mutate(label: "Paste") { project in
            for item in pasted { project.insertLayerItem(item, place: .automatic) }
        }
        selection = pasted.first.map { .layer($0.id) } ?? .none
        extraSelection = pasted.dropFirst().map { .layer($0.id) }
        return true
    }

    // MARK: Mark in / out

    /// I / O: the start (end) of the marked range at the playhead; Export
    /// can export just that part, ⌫ removes it.
    func markRange(isIn: Bool) {
        let time = clock.time
        var range: VideoDemoTimelineRange
        if case .range(let current) = selection {
            range = current.normalized
            if isIn { range.start = time } else { range.end = time }
        } else {
            range = isIn ? VideoDemoTimelineRange(start: time, end: timelineDuration) : VideoDemoTimelineRange(start: 0, end: time)
        }
        range = range.normalized
        guard range.end - range.start >= 0.05 else { return }
        selection = .range(range)
        showNotice(isIn ? L("Marked in at \(VideoEditorModel.timecode(time))") : L("Marked out at \(VideoEditorModel.timecode(time))"), symbol: isIn ? "chevron.left.to.line" : "chevron.right.to.line")
    }

    // MARK: Extract audio

    func extractAudioOfSelection() -> Bool {
        let entries = mediaEntries
        let entry: VideoMediaEntry?
        if let item = selectedLayerItem, item.isVideo {
            entry = entries.first { $0.path == item.path }
        } else {
            entry = entries.first { $0.origin == .recording }
        }
        guard let entry, entry.kind == .video else { return false }
        Task { await extractAudio(entry) }
        return true
    }
}

extension VideoEditorModel {
    /// The preview axis (S): hovering the timeline shows that moment in
    /// the player; leaving it goes back to the playhead.
    func previewAxis(at time: Double?) {
        guard !isPlaying, voiceover == nil else { return }
        if let time, Settings.videoTimelinePreviewAxis {
            guard abs((previewAxisTime ?? clock.time) - time) > 0.0005 else { return }
            previewAxisTime = time
            playback.seek(to: time, fast: true)
            previewRenderer.invalidate()
        } else if previewAxisTime != nil {
            previewAxisTime = nil
            playback.seek(to: clock.time, fast: false)
            previewRenderer.invalidate()
        }
    }
}

/// Once, in the editor after updating to 1.14.0: the keys that changed,
/// and the way to all of them.
struct VideoShortcutsChangedNotice: View {
    @State private var seen = Settings.videoShortcutsChangeSeen || !Self.editedBefore

    /// Someone who edited a video before this launch (a draft older than
    /// it): only they had the old keys to unlearn.
    static var editedBefore: Bool = {
        let start = NSRunningApplication.current.launchDate ?? Date()
        let drafts = (try? FileManager.default.contentsOfDirectory(at: VideoDemoDraftStore.directory(), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return drafts.contains { url in
            ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture) < start
        }
    }()

    var body: some View {
        if !seen {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Keyboard shortcuts changed"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Text(L("The timeline now uses CapCut's keys: ⌘B splits (C still does), S turns the preview axis on and off, I and O mark in and out, and Q and W delete left and right of the playhead. Text, arrow, highlight and blur are ⌥T, ⌥A, ⌥H and ⌥B."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(L("See all shortcuts")) {
                            close()
                            HomeWindowController.showGuide(at: .chapter(.shortcuts))
                        }
                        .buttonStyle(VideoSecondaryButtonStyle())
                        Button(L("OK")) { close() }
                            .buttonStyle(VideoSecondaryButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .frame(maxWidth: 460, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(VideoEditorTheme.popover))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke))
            .shadow(color: VideoEditorTheme.shadow, radius: 16, y: 6)
            .accessibilityElement(children: .contain)
        }
    }

    private func close() {
        Settings.videoShortcutsChangeSeen = true
        seen = true
    }
}

/// Commands as dictionary keys and in sets (by their stable name).
extension VideoEditCommand: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}
