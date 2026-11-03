import AppKit
import SwiftUI

// MARK: - 1.21.0's editor basics
//
// Box selection, gaps, duplicates, pasting attributes, roll and slide,
// Loop playback, solo, track names, Reveal in Library and Match Frame. The
// edits are VideoEditCommands (one ⌘Z step each, refused on a locked
// track), so the AI Assistant and MCP agents get them too.

/// The 1.21.0 edits that take values (VideoEditCommand.basics).
enum VideoBasicsEdit: Equatable {
    /// Closes the empty stretch at `time` on a track above the main track
    /// (or an added sound track): what's after it moves back.
    case deleteGap(track: VideoTimelineTrack, time: Double)
    /// What ⌘C copied, onto the selected clips.
    case pasteAttributes(Set<VideoClipAttribute>)
    /// Moves the cut at the end of `clip` by `by` seconds: the clip and the
    /// one after it both change, with no gap.
    case roll(clip: UUID, by: Double)
    /// Moves `clip` by `by` seconds between its neighbours; they change.
    case slide(clip: UUID, by: Double)
    /// Solo on or off: while any track is soloed only those are heard (in
    /// the editor; the export always has every track).
    case solo(VideoTimelineTrack)
    /// A track's own name ("" goes back to its usual one).
    case renameTrack(VideoTimelineTrack, String)

    var name: String {
        switch self {
        case .deleteGap(let track, let time): return "deleteGap.\(track.key).\(time)"
        case .pasteAttributes(let set): return "pasteAttributes." + set.map(\.rawValue).sorted().joined(separator: ",")
        case .roll(let id, let by): return "roll.\(id).\(by)"
        case .slide(let id, let by): return "slide.\(id).\(by)"
        case .solo(let track): return "solo.\(track.key)"
        case .renameTrack(let track, let name): return "renameTrack.\(track.key).\(name.count)"
        }
    }

    var title: String {
        switch self {
        case .deleteGap: return L("Delete Gap")
        case .pasteAttributes: return L("Paste Attributes")
        case .roll: return L("Roll")
        case .slide: return L("Slide")
        case .solo: return L("Solo")
        case .renameTrack: return L("Rename Track")
        }
    }
}

// MARK: - Box selection

extension VideoEditorModel {
    enum BoxMode {
        /// A plain drag: just what's in the box.
        case replace
        /// ⇧: added to what's selected.
        case add
        /// ⌘: each one in the box in or out.
        case toggle

        static var fromModifiers: BoxMode {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) { return .toggle }
            if flags.contains(.shift) { return .add }
            return .replace
        }
    }

    /// The clips on `tracks` that overlap `start…end` on the timeline: the
    /// main track's clips and the items on the tracks above it.
    func clips(from start: Double, to end: Double, on tracks: Set<VideoTimelineTrack>) -> [Selection] {
        let low = min(start, end), high = max(start, end)
        var found: [Selection] = []
        if tracks.contains(.clips) {
            for segment in segments where segment.timelineStart < high && segment.timelineEnd > low {
                found.append(.clip(segment.id))
            }
        }
        // Top track first, as they're drawn.
        for track in project.layerTracks.reversed() where tracks.contains(.layer(track.id)) {
            for item in track.items where item.at < high && item.end > low {
                found.append(.layer(item.id))
            }
        }
        return found
    }

    /// A box dragged over empty timeline space selects what it touches.
    func boxSelect(_ found: [Selection], mode: BoxMode) {
        switch mode {
        case .replace:
            selection = found.first ?? .none
            extraSelection = Array(found.dropFirst())
        case .add:
            for item in found where !isSelected(item) { toggleSelection(item) }
        case .toggle:
            for item in found { toggleSelection(item) }
        }
        if found.count > 1 { showNotice(L("\(selectedItems.count) clips selected"), symbol: "rectangle.dashed") }
    }
}

// MARK: - Gaps

/// An empty stretch on a track above the main track, or on an added sound
/// track (the main track never has one: it closes up by itself).
struct VideoTimelineGap: Equatable {
    var track: VideoTimelineTrack
    var start: Double
    var end: Double
    var length: Double { end - start }
}

extension VideoEditorModel {
    /// What's on a track that can have gaps, as start…end spans.
    private func gapSpans(_ track: VideoTimelineTrack) -> [(start: Double, end: Double)]? {
        switch track {
        case .layer(let id):
            return project.layerTracks.first { $0.id == id }?.items.map { ($0.at, $0.end) }
        case .sound(let id):
            // A track synced to the recording follows its cuts instead.
            guard let sound = project.audioTracks.first(where: { $0.id == id }), !sound.lockedToRecording else { return nil }
            return sound.pieces.map { ($0.at, $0.end) }
        default:
            return nil
        }
    }

    /// The gap at `time` on `track` (nil: something's there, or nothing
    /// comes after it).
    func gap(on track: VideoTimelineTrack, at time: Double) -> VideoTimelineGap? {
        guard let spans = gapSpans(track) else { return nil }
        guard !spans.contains(where: { time > $0.start + 0.0005 && time < $0.end - 0.0005 }) else { return nil }
        let start = spans.map(\.end).filter { $0 <= time + 0.0005 }.max() ?? 0
        guard let end = spans.map(\.start).filter({ $0 >= time - 0.0005 }).min(), end - start > 0.001 else { return nil }
        return VideoTimelineGap(track: track, start: start, end: end)
    }

    /// Moves everything on `track` from `from` on by `delta` seconds.
    private static func shift(_ track: VideoTimelineTrack, from: Double, by delta: Double, in project: inout VideoDemoProject) {
        switch track {
        case .layer(let id):
            guard let index = project.layerTracks.firstIndex(where: { $0.id == id }) else { return }
            for item in project.layerTracks[index].items.indices where project.layerTracks[index].items[item].at >= from - 0.0005 {
                project.layerTracks[index].items[item].at = max(project.layerTracks[index].items[item].at + delta, 0)
            }
            project.layerTracks[index].sort()
        case .sound(let id):
            guard let index = project.audioTracks.firstIndex(where: { $0.id == id }) else { return }
            for piece in project.audioTracks[index].pieces.indices where project.audioTracks[index].pieces[piece].at >= from - 0.0005 {
                project.audioTracks[index].pieces[piece].at = max(project.audioTracks[index].pieces[piece].at + delta, 0)
            }
        default:
            break
        }
    }

    /// Right-click empty space ▸ Delete Gap.
    @discardableResult
    func deleteGap(on track: VideoTimelineTrack, at time: Double) -> Bool {
        guard let gap = gap(on: track, at: time) else {
            showNotice(L("No gap here"), symbol: "arrow.left.to.line")
            return false
        }
        if refuseLocked(track) { return false }
        mutate(label: "Delete Gap") { project in
            Self.shift(track, from: gap.end, by: -gap.length, in: &project)
        }
        showNotice(L("Gap of \(VideoEditorModel.format(gap.length)) closed"), symbol: "arrow.left.to.line")
        return true
    }

    /// Delete Gaps After Playhead: on every track above the main track and
    /// every free sound track, what comes after the playhead closes up to
    /// it, one after another.
    @discardableResult
    func deleteGapsAfterPlayhead() -> Bool {
        let time = clock.time
        var closed = 0.0
        mutate(label: "Delete Gaps") { project in
            let before = project
            defer { if closed <= 0.0005 { project = before } } // only sorting changed: no ⌘Z step
            for index in project.layerTracks.indices where !project.isTrackLocked(.layer(project.layerTracks[index].id)) {
                project.layerTracks[index].sort()
                var cursor = time
                for item in project.layerTracks[index].items.indices {
                    let current = project.layerTracks[index].items[item]
                    if current.end <= time + 0.0005 { continue }
                    if current.at < time - 0.0005 { cursor = max(cursor, current.end); continue }
                    if current.at > cursor + 0.0005 {
                        closed += current.at - cursor
                        project.layerTracks[index].items[item].at = cursor
                    }
                    cursor = project.layerTracks[index].items[item].end
                }
            }
            for index in project.audioTracks.indices where !project.audioTracks[index].lockedToRecording && !project.isTrackLocked(.sound(project.audioTracks[index].id)) {
                project.audioTracks[index].pieces.sort { $0.at < $1.at }
                var cursor = time
                for piece in project.audioTracks[index].pieces.indices {
                    let current = project.audioTracks[index].pieces[piece]
                    if current.end <= time + 0.0005 { continue }
                    if current.at < time - 0.0005 { cursor = max(cursor, current.end); continue }
                    if current.at > cursor + 0.0005 {
                        closed += current.at - cursor
                        project.audioTracks[index].pieces[piece].at = cursor
                    }
                    cursor = project.audioTracks[index].pieces[piece].end
                }
            }
        }
        guard closed > 0.0005 else {
            showNotice(L("No gaps after the playhead"), symbol: "arrow.left.to.line")
            return false
        }
        showNotice(L("Gaps after the playhead closed"), symbol: "arrow.left.to.line")
        return true
    }
}

// MARK: - Duplicate

extension VideoEditorModel {
    /// ⌘D: the selection again, right after itself. Zooms and annotations
    /// as before (1.9.0); clips above the main track go on their own track,
    /// pushing what comes after them along. The main track's clips are the
    /// recording itself, each moment once, so they aren't duplicated.
    @discardableResult
    func duplicateSelection() -> Bool {
        if let id = selectedZoomID {
            duplicateZoom(id)
            return true
        }
        if case .overlay(let id) = selection {
            duplicateOverlay(id)
            return true
        }
        let ids = selectedItems.compactMap { item -> UUID? in
            if case .layer(let id) = item { return id }
            return nil
        }
        if !ids.isEmpty { return duplicateLayerItems(Set(ids)) }
        if let piece = selectedAudioPiece { return duplicateAudioPiece(piece) }
        if selectedClipID != nil {
            showNotice(L("Main-track clips are the recording itself. To use a part twice, copy it to a track above (⌘C, ⌘V)."), symbol: "plus.square.on.square")
            return false
        }
        showNotice(L("Select a clip to duplicate"), symbol: "plus.square.on.square")
        return false
    }

    /// Copies of `ids`, right after the selection on each one's track.
    @discardableResult
    func duplicateLayerItems(_ ids: Set<UUID>) -> Bool {
        let items = project.layerItems.filter { ids.contains($0.item.id) }
        guard let first = items.map(\.item.at).min(), let last = items.map(\.item.end).max() else { return false }
        if items.contains(where: { refuseLockedLayer($0.track) }) { return false }
        let length = last - first
        var copies: [UUID] = []
        mutate(label: "Duplicate") { project in
            for track in Set(items.map(\.track)) {
                let trackID = project.layerTracks[track].id
                Self.shift(.layer(trackID), from: last, by: length, in: &project)
                for (_, item) in items.filter({ $0.track == track }) {
                    var copy = item
                    copy.id = UUID()
                    copy.at = item.at + length
                    copy.group = nil
                    copies.append(copy.id)
                    project.layerTracks[track].items.append(copy)
                }
                project.layerTracks[track].sort()
            }
        }
        selection = copies.first.map { .layer($0) } ?? .none
        extraSelection = copies.dropFirst().map { .layer($0) }
        showNotice(copies.count == 1 ? L("Duplicated") : L("Duplicated \(copies.count) clips"), symbol: "plus.square.on.square")
        return !copies.isEmpty
    }

    private func duplicateAudioPiece(_ ref: VideoAudioPieceRef) -> Bool {
        guard let track = project.audioTracks.first(where: { $0.id == ref.track }), let piece = track.pieces.first(where: { $0.id == ref.piece }) else { return false }
        if refuseLocked(.sound(ref.track)) { return false }
        var copy = piece
        copy.id = UUID()
        copy.at = piece.end
        mutate(label: "Duplicate") { project in
            guard let index = project.audioTracks.firstIndex(where: { $0.id == ref.track }) else { return }
            if !project.audioTracks[index].lockedToRecording { Self.shift(.sound(ref.track), from: piece.end, by: piece.length, in: &project) }
            project.audioTracks[index].pieces.append(copy)
            project.audioTracks[index].pieces.sort { $0.at < $1.at }
        }
        selectedAudioPiece = VideoAudioPieceRef(track: ref.track, piece: copy.id)
        showNotice(L("Duplicated"), symbol: "plus.square.on.square")
        return true
    }

    /// ⌥-drag: copies of the dragged items land where they were dropped
    /// (the originals stay). The dragged one's copy goes to track `to`;
    /// the rest of its group keep their tracks.
    func copyLayerItems(_ ids: Set<UUID>, by delta: Double, fromTrack from: Int, toTrack to: Int, newTrack: Bool) {
        let items = project.layerItems.filter { ids.contains($0.item.id) }
        guard !items.isEmpty, !refuseLockedLayer(from) else { return }
        var made: [UUID] = []
        mutate(label: "Copy Clip") { project in
            for (track, item) in items {
                var copy = item
                copy.id = UUID()
                copy.group = nil
                copy.at = max(item.at + delta, 0)
                made.append(copy.id)
                project.insertLayerItem(copy, place: track != from ? .track(track) : newTrack ? .newTrack(to) : .track(to))
            }
        }
        selection = made.first.map { .layer($0) } ?? .none
        extraSelection = made.dropFirst().map { .layer($0) }
        showNotice(made.count == 1 ? L("Copied") : L("Copied \(made.count) clips"), symbol: "plus.square.on.square")
    }
}

// MARK: - Copy and paste attributes

/// What Paste Attributes can carry from one clip to another.
enum VideoClipAttribute: String, CaseIterable, Identifiable, Codable {
    case effects, filters, adjust, speed, volume, transform, animation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .effects: return L("Effects")
        case .filters: return L("Filters")
        case .adjust: return L("Adjust")
        case .speed: return L("Speed")
        case .volume: return L("Volume")
        case .transform: return L("Transform")
        case .animation: return L("Animation")
        }
    }

    var detail: String {
        switch self {
        case .effects: return L("Every effect and its strength")
        case .filters: return L("The filter and its strength")
        case .adjust: return L("Exposure, colour and the rest of Adjust")
        case .speed: return L("How fast it plays (the clip gets longer or shorter)")
        case .volume: return L("Volume, mute and sound fades")
        case .transform: return L("Place, size, turn, mirror, crop, opacity and blend")
        case .animation: return L("In, Out and Combo animations and keyframes")
        }
    }
}

/// The clip ⌘C copied, for Paste Attributes.
struct VideoCopiedAttributes {
    var layer: VideoLayerItem?
    var clip: VideoDemoTimelineClip?

    /// What a clip like this has to give.
    var available: [VideoClipAttribute] {
        if layer != nil { return VideoClipAttribute.allCases }
        return [.speed, .volume, .transform]
    }

    /// The ones it has set (ticked to start with).
    var set: Set<VideoClipAttribute> {
        var set: Set<VideoClipAttribute> = []
        if let item = layer {
            if item.effects?.isEmpty == false { set.insert(.effects) }
            if item.filter != nil { set.insert(.filters) }
            if item.adjust != nil { set.insert(.adjust) }
            if abs(item.speed - 1) > 0.001 { set.insert(.speed) }
            if abs(item.volume - 1) > 0.001 || item.muted || (item.soundFadeIn ?? 0) > 0 || (item.soundFadeOut ?? 0) > 0 { set.insert(.volume) }
            if item.rotation != 0 || item.mirrored || item.opacity < 1 || item.crop != nil || item.blend != nil { set.insert(.transform) }
            if item.animation != nil || item.keys?.isEmpty == false { set.insert(.animation) }
        } else if let clip {
            if abs(clip.normalizedSpeed - 1) > 0.001 { set.insert(.speed) }
            if clip.muted || clip.fadeIn > 0 || clip.fadeOut > 0 { set.insert(.volume) }
            if clip.mirrored || clip.turns != 0 { set.insert(.transform) }
        }
        return set
    }
}

extension VideoEditorModel {
    /// ⌘C also remembers the lead clip's attributes.
    func rememberAttributes() {
        switch selection {
        case .layer(let id):
            if let item = project.layerItem(id) { copiedAttributes = VideoCopiedAttributes(layer: item) }
        case .clip(let id):
            if let clip = project.timelineClips.first(where: { $0.id == id }) { copiedAttributes = VideoCopiedAttributes(clip: clip) }
        default:
            break
        }
    }

    /// Paste Attributes… (⇧⌘V): the sheet to tick what to paste.
    @discardableResult
    func showPasteAttributes() -> Bool {
        guard copiedAttributes != nil else {
            showNotice(L("Copy a clip first (⌘C), then select the clips to paste onto"), symbol: "doc.on.clipboard")
            return false
        }
        guard selectedItems.contains(where: { if case .clip = $0 { return true }; if case .layer = $0 { return true }; return false }) else {
            showNotice(L("Select the clips to paste onto"), symbol: "doc.on.clipboard")
            return false
        }
        withAnimation(.easeOut(duration: 0.15)) { isPasteAttributesPresented = true }
        return true
    }

    /// The copied clip's `attributes` onto every selected clip, in one step.
    @discardableResult
    func pasteAttributes(_ attributes: Set<VideoClipAttribute>) -> Bool {
        guard let source = copiedAttributes, !attributes.isEmpty else { return false }
        let targets = selectedItems
        var pasted = 0
        for target in targets {
            if case .layer(let id) = target, let track = project.layerTrackIndex(of: id), refuseLockedLayer(track) { return false }
            if case .clip = target, refuseLocked(.clips) { return false }
        }
        mutate(label: "Paste Attributes") { project in
            for target in targets {
                switch target {
                case .layer(let id):
                    guard let track = project.layerTrackIndex(of: id) else { continue }
                    let room = project.layerTracks[track].items.filter { $0.id != id && $0.at >= (project.layerItem(id)?.end ?? 0) - 0.0005 }.map(\.at).min()
                    project.updateLayerItem(id) { item in
                        if let from = source.layer {
                            Self.paste(attributes, from: from, onto: &item)
                        } else if let clip = source.clip {
                            if attributes.contains(.speed), item.isVideo { Self.setSpeed(clip.normalizedSpeed, of: &item) }
                            if attributes.contains(.transform) { item.mirrored = clip.mirrored }
                        }
                        // A faster or slower clip keeps out of the next one's way.
                        if let room, item.end > room { item.length = max(room - item.at, VideoLayerItem.minimumLength) }
                        item.clampValues()
                    }
                    pasted += 1
                case .clip(let id):
                    _ = project.updateClip(id: id, totalDuration: sourceDuration) { clip in
                        if let from = source.clip {
                            if attributes.contains(.speed) { clip.speed = from.normalizedSpeed; clip.keepsPitch = from.keepsPitch; clip.curve = nil }
                            if attributes.contains(.volume) { clip.muted = from.muted; clip.fadeIn = from.fadeIn; clip.fadeOut = from.fadeOut }
                            if attributes.contains(.transform) { clip.mirrored = from.mirrored; clip.quarterTurns = from.quarterTurns }
                        } else if let item = source.layer {
                            if attributes.contains(.speed), item.isVideo { clip.speed = item.normalizedSpeed; clip.curve = nil }
                            if attributes.contains(.transform) { clip.mirrored = item.mirrored }
                        }
                        clip.fadeIn = min(max(clip.fadeIn, 0), max(clip.outputDuration / 2, 0))
                        clip.fadeOut = min(max(clip.fadeOut, 0), max(clip.outputDuration / 2, 0))
                    }
                    pasted += 1
                default:
                    continue
                }
            }
        }
        if pasted > 0 { showNotice(pasted == 1 ? L("Attributes pasted") : L("Attributes pasted onto \(pasted) clips"), symbol: "doc.on.clipboard") }
        return pasted > 0
    }

    /// A video's speed; it keeps its frames, so its length changes.
    static func setSpeed(_ speed: Double, of item: inout VideoLayerItem) {
        let frames = item.fileLength
        item.speed = min(max(speed, VideoLayerItem.speedRange.lowerBound), VideoLayerItem.speedRange.upperBound)
        item.length = max(frames / item.normalizedSpeed, VideoLayerItem.minimumLength)
    }

    static func paste(_ attributes: Set<VideoClipAttribute>, from source: VideoLayerItem, onto item: inout VideoLayerItem) {
        if attributes.contains(.effects) {
            item.effects = source.effects
            if source.role == nil { item.level = source.level }
        }
        if attributes.contains(.filters) {
            item.filter = source.filter
            if source.role == nil { item.level = source.level }
        }
        if attributes.contains(.adjust) { item.adjust = source.adjust }
        if attributes.contains(.speed), item.isVideo, source.isVideo {
            setSpeed(source.normalizedSpeed, of: &item)
            item.keepsPitch = source.keepsPitch
        }
        if attributes.contains(.volume) {
            item.volume = source.volume
            item.muted = source.muted
            item.soundFadeIn = source.soundFadeIn
            item.soundFadeOut = source.soundFadeOut
        }
        if attributes.contains(.transform) {
            item.x = source.x
            item.y = source.y
            item.width = source.width
            item.rotation = source.rotation
            item.mirrored = source.mirrored
            item.opacity = source.opacity
            item.crop = source.crop
            item.blend = source.blend
        }
        if attributes.contains(.animation) {
            item.animation = source.animation
            // Keys from its start, as far as this clip goes.
            item.keys = source.keys
            item.keys?.shift(by: 0, length: item.length)
        }
    }
}

// MARK: - Roll and slide

/// What dragging there does (the label at the pointer, 1.21.0).
enum VideoTrimKind: Equatable {
    case ripple, roll, slide, slip
    /// The Trim tool over a video above the main track.
    case slideOrSlip

    var title: String {
        switch self {
        case .ripple: return L("Ripple")
        case .roll: return L("Roll")
        case .slide: return L("Slide")
        case .slip: return L("Slip")
        case .slideOrSlip: return L("Slide · ⌥ Slip")
        }
    }
}

extension VideoEditorModel {
    /// The main-track clip after `id` (nil: it's the last).
    private func clipAfter(_ id: UUID) -> UUID? {
        guard let index = segments.firstIndex(where: { $0.id == id }), segments.indices.contains(index + 1) else { return nil }
        return segments[index + 1].id
    }

    private func clipBefore(_ id: UUID) -> UUID? {
        guard let index = segments.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        return segments[index - 1].id
    }

    /// Main track: the end of `left` and the start of `right` both move by
    /// `delta` timeline seconds, as far as both can (the video keeps its
    /// length).
    private func rolled(_ project: VideoDemoProject, left: UUID, right: UUID, by delta: Double) -> (VideoDemoProject, Double)? {
        func attempt(_ delta: Double) -> (VideoDemoProject, Double, Double)? {
            var next = project
            let clips = next.normalizedTimelineClips(totalDuration: sourceDuration)
            guard let a = clips.first(where: { $0.id == left }), let b = clips.first(where: { $0.id == right }) else { return nil }
            func trimRight() { _ = next.trimClip(id: right, sourceStart: b.sourceStart + delta * b.normalizedSpeed, totalDuration: sourceDuration) }
            func trimLeft() { _ = next.trimClip(id: left, sourceEnd: a.sourceEnd + delta * a.normalizedSpeed, totalDuration: sourceDuration) }
            // Make room first: the clip that gets shorter goes first.
            if delta > 0 { trimRight(); trimLeft() } else { trimLeft(); trimRight() }
            let after = next.normalizedTimelineClips(totalDuration: sourceDuration)
            guard let a2 = after.first(where: { $0.id == left }), let b2 = after.first(where: { $0.id == right }) else { return nil }
            return (next, a2.outputDuration - a.outputDuration, b.outputDuration - b2.outputDuration)
        }
        guard var result = attempt(delta) else { return nil }
        if abs(result.1 - result.2) > 0.0005 {
            // One side stopped short: both go only as far as it did.
            let reach = delta > 0 ? min(result.1, result.2) : max(result.1, result.2)
            guard let again = attempt(reach) else { return nil }
            result = again
        }
        return (result.0, result.1)
    }

    /// Roll (drag a cut): the clip and the one after it change together;
    /// nothing else moves. Works on the main track and on two touching
    /// clips above it.
    @discardableResult
    func roll(clip id: UUID, by delta: Double, coalesce: Bool = false) -> Bool {
        if project.layerItem(id) != nil { return rollLayer(id, by: delta, coalesce: coalesce) }
        guard let right = clipAfter(id) else {
            showNotice(L("Roll needs a clip after this one"), symbol: "arrow.left.and.right")
            return false
        }
        if refuseLocked(.clips) { return false }
        guard let (next, moved) = rolled(project, left: id, right: right, by: delta), abs(moved) > 0.0005 else { return false }
        if layoutDurationLock == nil, coalesce { layoutDurationLock = timelineDuration }
        mutate(coalesce: coalesce ? "roll-\(id)" : nil, label: "Roll") { $0 = next }
        return true
    }

    /// Slide: the clip keeps its frames and moves between its neighbours;
    /// the one before gets longer and the one after shorter (or the other
    /// way). The video keeps its length.
    @discardableResult
    func slide(clip id: UUID, by delta: Double, coalesce: Bool = false) -> Bool {
        if project.layerItem(id) != nil { return slideLayer(id, by: delta, coalesce: coalesce) }
        guard let left = clipBefore(id), let right = clipAfter(id) else {
            showNotice(L("Slide needs a clip on each side"), symbol: "arrow.left.and.right")
            return false
        }
        if refuseLocked(.clips) { return false }
        // The clip before gets `delta` longer, the one after `delta` shorter.
        func attempt(_ delta: Double) -> (VideoDemoProject, Double, Double)? {
            var next = project
            let clips = next.normalizedTimelineClips(totalDuration: sourceDuration)
            guard let a = clips.first(where: { $0.id == left }), let c = clips.first(where: { $0.id == right }) else { return nil }
            func trimAfter() { _ = next.trimClip(id: right, sourceStart: c.sourceStart + delta * c.normalizedSpeed, totalDuration: sourceDuration) }
            func trimBefore() { _ = next.trimClip(id: left, sourceEnd: a.sourceEnd + delta * a.normalizedSpeed, totalDuration: sourceDuration) }
            if delta > 0 { trimAfter(); trimBefore() } else { trimBefore(); trimAfter() }
            let after = next.normalizedTimelineClips(totalDuration: sourceDuration)
            guard let a2 = after.first(where: { $0.id == left }), let c2 = after.first(where: { $0.id == right }) else { return nil }
            return (next, a2.outputDuration - a.outputDuration, c.outputDuration - c2.outputDuration)
        }
        guard var result = attempt(delta) else { return false }
        if abs(result.1 - result.2) > 0.0005 {
            let reach = delta > 0 ? min(result.1, result.2) : max(result.1, result.2)
            guard let again = attempt(reach) else { return false }
            result = again
        }
        guard abs(result.1) > 0.0005 else {
            // The clips around it use the recording right up to it.
            if !coalesce || abs(delta) > 0.05 { showNotice(L("Nothing of the recording is left on that side to slide into. Slide works where a part was cut out."), symbol: "arrow.left.and.right") }
            return false
        }
        if layoutDurationLock == nil, coalesce { layoutDurationLock = timelineDuration }
        mutate(coalesce: coalesce ? "slide-\(id)" : nil, label: "Slide") { $0 = result.0 }
        return true
    }

    /// Ends a roll or slide drag.
    func endRollOrSlide() {
        endGesture()
        layoutDurationLock = nil
    }

    // Above the main track: two clips that touch.

    private func touching(_ id: UUID, after: Bool) -> VideoLayerItem? {
        guard let item = project.layerItem(id), let track = project.layerTrackIndex(of: id) else { return nil }
        return project.layerTracks[track].items.first { other in
            other.id != id && (after ? abs(other.at - item.end) < 0.002 : abs(other.end - item.at) < 0.002)
        }
    }

    private func rollLayer(_ id: UUID, by delta: Double, coalesce: Bool) -> Bool {
        guard let item = project.layerItem(id), let next = touching(id, after: true), let track = project.layerTrackIndex(of: id) else {
            showNotice(L("Roll needs a clip right after this one"), symbol: "arrow.left.and.right")
            return false
        }
        if refuseLockedLayer(track) { return false }
        // As far as both can go: neither shorter than the least, a video
        // not past its own frames.
        var low = -(item.length - VideoLayerItem.minimumLength)
        var high = next.length - VideoLayerItem.minimumLength
        if item.isVideo { high = min(high, (item.fileDuration - item.fileEnd) / item.normalizedSpeed) }
        if next.isVideo { low = max(low, -next.fileStart / next.normalizedSpeed) }
        let shift = min(max(delta, low), high)
        guard abs(shift) > 0.0005 else { return false }
        let cut = item.end + shift
        mutate(coalesce: coalesce ? "roll-\(id)" : nil, label: "Roll") { project in
            if shift > 0 {
                project.trimLayerItem(next.id, leading: true, to: cut)
                project.trimLayerItem(id, leading: false, to: cut)
            } else {
                project.trimLayerItem(id, leading: false, to: cut)
                project.trimLayerItem(next.id, leading: true, to: cut)
            }
        }
        return true
    }

    private func slideLayer(_ id: UUID, by delta: Double, coalesce: Bool) -> Bool {
        guard let item = project.layerItem(id), let track = project.layerTrackIndex(of: id) else { return false }
        if refuseLockedLayer(track) { return false }
        let before = touching(id, after: false)
        let after = touching(id, after: true)
        let others = project.layerTracks[track].items.filter { $0.id != id && $0.id != before?.id && $0.id != after?.id }
        // Neighbours with room between bound it; touching ones give way.
        var low = -(item.at - (others.filter { $0.end <= item.at + 0.002 }.map(\.end).max() ?? 0))
        var high = (others.filter { $0.at >= item.end - 0.002 }.map(\.at).min() ?? .infinity) - item.end
        if let before {
            low = max(low, -(before.length - VideoLayerItem.minimumLength))
            if before.isVideo { high = min(high, (before.fileDuration - before.fileEnd) / before.normalizedSpeed) }
        }
        if let after {
            high = min(high, after.length - VideoLayerItem.minimumLength)
            if after.isVideo { low = max(low, -after.fileStart / after.normalizedSpeed) }
        }
        let shift = min(max(delta, low), high)
        guard abs(shift) > 0.0005 else { return false }
        mutate(coalesce: coalesce ? "slide-\(id)" : nil, label: "Slide") { project in
            func move() {
                project.updateLayerItem(id) { $0.at = item.at + shift }
                project.layerTracks[track].sort()
            }
            if shift > 0 {
                if let after { project.trimLayerItem(after.id, leading: true, to: after.at + shift) }
                move()
                if let before { project.trimLayerItem(before.id, leading: false, to: before.end + shift) }
            } else {
                if let before { project.trimLayerItem(before.id, leading: false, to: before.end + shift) }
                move()
                if let after { project.trimLayerItem(after.id, leading: true, to: after.at + shift) }
            }
        }
        return true
    }
}

// MARK: - Loop playback

extension VideoEditorModel {
    /// What Loop playback (⌘L) repeats: the In/Out range, else the
    /// selected clip, else the whole video.
    var loopRange: ClosedRange<Double> {
        if case .range(let range) = selection {
            let r = range.normalized
            if r.duration >= 0.1 { return r.start...r.end }
        }
        if let id = selectedClipID, let segment = segments.first(where: { $0.id == id }) {
            return segment.timelineStart...segment.timelineEnd
        }
        if let item = selectedLayerItem { return item.at...min(item.end, timelineDuration) }
        return 0...timelineDuration
    }

    func toggleLoopPlayback() {
        loopsPlayback.toggle()
        let range = loopRange
        let whole = range.lowerBound < 0.001 && range.upperBound > timelineDuration - 0.001
        showNotice(loopsPlayback ? (whole ? L("Loop playback on: the whole video") : L("Loop playback on: \(VideoEditorModel.timecode(range.lowerBound)) to \(VideoEditorModel.timecode(range.upperBound))")) : L("Loop playback off"), symbol: "repeat")
    }

    /// Called as it plays: back to the start of the range.
    func loopIfNeeded(at time: Double) {
        guard loopsPlayback else { return }
        let range = loopRange
        guard range.upperBound - range.lowerBound > 0.05 else { return }
        guard isPlaying, time >= range.upperBound - 0.01 else { return }
        seek(to: range.lowerBound)
    }

    /// The player reached the video's end by itself (a range that ends
    /// there): start the range again. A pause never gets here.
    func loopAtVideoEnd() {
        guard loopsPlayback else { return }
        let range = loopRange
        guard range.upperBound - range.lowerBound > 0.05 else { return }
        seek(to: range.lowerBound)
        playback.play()
    }

    /// Starting to play with Loop playback on, outside its range: from the
    /// range's start.
    func loopStartIfNeeded() {
        guard loopsPlayback else { return }
        let range = loopRange
        if clock.time < range.lowerBound - 0.01 || clock.time >= range.upperBound - 0.01 { seek(to: range.lowerBound) }
    }
}

// MARK: - Solo and track names

extension VideoTimelineTrack {
    /// Solo: tracks with sound.
    var canSolo: Bool { canMute }
}

extension VideoDemoProject {
    /// Tracks soloed now.
    var soloedTracks: Set<String> { Set(trackStates.filter { $0.value.solo }.map(\.key)) }

    /// As heard in the editor while some tracks are soloed: the others
    /// silent. Never the export (VideoExporter uses forOutput()). A video
    /// track and its sound row count as one, and so do the main track and
    /// its sound rows.
    func forListening(sound: VideoTimelineSoundRows) -> VideoDemoProject {
        let soloed = soloedTracks
        guard !soloed.isEmpty else { return self }
        func heard(_ track: VideoTimelineTrack) -> Bool {
            if soloed.contains(track.key) { return true }
            switch track {
            case .clipSound: return soloed.contains(VideoTimelineTrack.clips.key)
            case .clips: return soloed.contains { $0.hasPrefix("clipSound-") }
            case .layerSound(let id): return soloed.contains(VideoTimelineTrack.layer(id).key)
            case .layer(let id): return soloed.contains(VideoTimelineTrack.layerSound(id).key)
            default: return false
            }
        }
        var project = self
        for track in timelineTracks(sound: sound) where track.canSolo && !heard(track) {
            project.setTrackState(track) { $0.muted = true }
        }
        return project
    }

    /// The name shown on a track's header: its own, else the usual one.
    func trackName(_ track: VideoTimelineTrack) -> String? {
        trackStates[track.key]?.name
    }
}

extension VideoEditorModel {
    @discardableResult
    func toggleSolo(_ track: VideoTimelineTrack) -> Bool {
        guard track.canSolo else { return false }
        let on = !project.trackState(track).solo
        mutate(label: on ? "Solo" : "Unsolo") { project in
            project.setTrackState(track) { $0.solo = on }
        }
        refreshPlayback()
        let title = track.title(in: project)
        showNotice(on ? L("\(title) soloed: only soloed tracks are heard") : L("\(title) no longer soloed"), symbol: "headphones")
        return true
    }

    @discardableResult
    func renameTrack(_ track: VideoTimelineTrack, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = project.trackStates[track.key]?.name ?? ""
        guard trimmed != current, trimmed.count <= 60 else { return false }
        mutate(label: "Rename Track") { project in
            project.setTrackState(track) { $0.name = trimmed.isEmpty ? nil : trimmed }
        }
        return true
    }
}

// MARK: - Reveal in Library and Match Frame

/// The source a clip shows, at one frame (Match Frame).
struct VideoSourceFrame: Equatable, Identifiable {
    var url: URL
    var time: Double
    var name: String
    var kind: VideoMediaKind
    var id: String { "\(url.path)@\(time)" }
}

extension VideoEditorModel {
    /// The file the selected clip (or the one under the playhead) shows,
    /// and its own second at the playhead.
    func sourceFrame() -> VideoSourceFrame? {
        let time = clock.time
        if let item = selectedLayerItem ?? project.layerItems.map(\.item).last(where: { $0.isShowing(at: time) && $0.hasFile }), item.hasFile {
            let local = min(max(time, item.at), item.end) - item.at
            return VideoSourceFrame(url: URL(fileURLWithPath: item.path), time: item.isVideo ? item.fileStart + local * item.normalizedSpeed : 0, name: item.name, kind: item.kind)
        }
        if let id = selectedClipID, let segment = segments.first(where: { $0.id == id }) {
            let source = segment.sourceTime(forTimelineTime: min(max(time, segment.timelineStart), segment.timelineEnd))
            return VideoSourceFrame(url: project.sourceURL, time: source, name: project.sourceURL.lastPathComponent, kind: .video)
        }
        guard let segment = segment(atTimeline: time) else { return nil }
        return VideoSourceFrame(url: project.sourceURL, time: segment.sourceTime(forTimelineTime: time), name: project.sourceURL.lastPathComponent, kind: .video)
    }

    /// Reveal in Library (⇧F): the clip's file, selected in Library ▸ Media.
    @discardableResult
    func revealInLibrary() -> Bool {
        guard let frame = sourceFrame() else {
            showNotice(L("Select a clip to find its file in the Library"), symbol: "magnifyingglass")
            return false
        }
        libraryTab = .media
        VideoEditorPanelStore.shared.show(.library)
        revealedMediaPath = frame.url.path
        showNotice(L("“\(frame.name)” in the Library"), symbol: "magnifyingglass")
        return true
    }

    /// Match Frame: the clip's file, opened at the frame under the playhead.
    @discardableResult
    func matchFrame() -> Bool {
        guard let frame = sourceFrame() else {
            showNotice(L("Select a clip to see its source"), symbol: "film")
            return false
        }
        revealedMediaPath = frame.url.path
        sourceViewer = frame
        return true
    }
}
