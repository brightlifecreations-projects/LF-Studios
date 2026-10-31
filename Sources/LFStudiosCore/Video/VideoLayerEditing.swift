import AppKit
import AVFoundation

// MARK: - Editing the tracks above the main track (1.14.0)

extension VideoEditorModel {
    /// The item selected on a track above the main track.
    var selectedLayerItem: VideoLayerItem? {
        guard case .layer(let id) = selection else { return nil }
        return project.layerItem(id)
    }

    /// Where a file dropped on the timeline goes.
    enum LayerPlace: Equatable {
        /// The first track above the main track with room (a new one on top
        /// when none has).
        case automatic
        /// That track (lowest is 0); a new one above it when it's taken.
        case track(Int)
        /// A new track at that index (0: right above the main track).
        case newTrack(Int)
    }

    /// A video or a picture on a track above the main track, starting at
    /// `time` (the playhead when nil). Returns the new item.
    @discardableResult
    func addLayerItem(from url: URL, at time: Double? = nil, place: LayerPlace = .automatic) async -> UUID? {
        guard let kind = VideoMediaKind.of(url), kind != .audio else { return nil }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let start = max(time ?? clock.time, 0)
        var item: VideoLayerItem
        switch kind {
        case .video:
            guard let tracks = try? await VideoSourceTracks.load(url: URL(fileURLWithPath: path)), tracks.duration > 0.1 else {
                showNotice(L("Couldn't open that video"), symbol: "exclamationmark.triangle.fill")
                return nil
            }
            item = .make(kind: .video, path: path, name: url.lastPathComponent, at: start, length: tracks.duration, fileDuration: tracks.duration,
                         aspect: Double(tracks.size.width / max(tracks.size.height, 1)), canvas: project.canvasSize())
        case .image:
            guard let size = VideoImageOverlayRenderer.pixelSize(of: URL(fileURLWithPath: path)) else {
                showNotice(L("Couldn't open that image"), symbol: "exclamationmark.triangle.fill")
                return nil
            }
            item = .make(kind: .image, path: path, name: url.lastPathComponent, at: start, length: VideoLayerItem.pictureLength, fileDuration: 0,
                         aspect: Double(size.width / max(size.height, 1)), canvas: project.canvasSize())
        case .audio:
            return nil
        }
        let id = item.id
        if case .track(let index) = place, project.layerTracks.indices.contains(index), project.isTrackLocked(.layer(project.layerTracks[index].id)) {
            _ = refuseLocked(.layer(project.layerTracks[index].id))
            return nil
        }
        mutate(label: "Add to Track") { project in
            project.insertLayerItem(item, place: place)
        }
        selection = .layer(id)
        return id
    }

    /// Moves an item to `time` on track `track` (a new track there when
    /// `newTrack`), during a drag (`coalesce`) or at once.
    func moveLayerItem(_ id: UUID, to time: Double, track: Int, newTrack: Bool = false, coalesce: Bool = false) {
        guard let item = project.layerItem(id), let from = project.layerTrackIndex(of: id) else { return }
        if refuseLockedLayer(from) { return }
        let moving = project.groupMates(of: id)
        let delta = max(time, 0) - item.at
        mutate(coalesce: coalesce ? "layer-move-\(id)" : nil, label: "Move Clip") { project in
            project.moveLayerItems(moving, by: delta, fromTrack: from, toTrack: track, newTrack: newTrack)
        }
    }

    /// Drags an item's start (`leading`) or end to `time`. A video stops at
    /// its own first and last frame.
    func trimLayerItem(_ id: UUID, leading: Bool, to time: Double, coalesce: Bool = true) {
        guard let track = project.layerTrackIndex(of: id), !refuseLockedLayer(track) else { return }
        mutate(coalesce: coalesce ? "layer-trim-\(id)" : nil, label: "Trim Clip") { project in
            project.trimLayerItem(id, leading: leading, to: time)
        }
    }

    /// Opacity, place, size, turn, mirror, crop, sound, speed, on/off.
    func setLayerItem(_ id: UUID, coalesce: String? = nil, label: String = "Clip Change", _ change: (inout VideoLayerItem) -> Void) {
        guard let track = project.layerTrackIndex(of: id), !refuseLockedLayer(track) else { return }
        mutate(coalesce: coalesce, label: label) { project in
            project.updateLayerItem(id) { item in
                change(&item)
                item.opacity = min(max(item.opacity, 0), 1)
                item.volume = min(max(item.volume, 0), 2)
                item.speed = min(max(item.speed, VideoLayerItem.speedRange.lowerBound), VideoLayerItem.speedRange.upperBound)
                item.width = min(max(item.width, 0.02), 4)
            }
        }
    }

    /// Speed: the item keeps its start; its length follows (a video can't
    /// play past its own end).
    func setLayerSpeed(_ id: UUID, _ speed: Double) {
        setLayerItem(id, coalesce: "layer-speed-\(id)") { item in
            let fileLength = item.fileLength
            item.speed = min(max(speed, VideoLayerItem.speedRange.lowerBound), VideoLayerItem.speedRange.upperBound)
            if item.isVideo { item.length = max(min(fileLength, item.fileDuration - item.fileStart) / item.normalizedSpeed, VideoLayerItem.minimumLength) }
        }
    }

    func deleteLayerItem(_ id: UUID) {
        guard let track = project.layerTrackIndex(of: id), !refuseLockedLayer(track) else { return }
        let gone = project.groupMates(of: id)
        mutate(label: "Delete Clip") { project in
            for t in project.layerTracks.indices { project.layerTracks[t].items.removeAll { gone.contains($0.id) } }
            project.dropEmptyLayerTracks()
        }
        if case .layer(let selected) = selection, gone.contains(selected) { selection = .none }
    }

    /// Splits the item at `time` into two (nil: the time is outside it).
    @discardableResult
    func splitLayerItem(_ id: UUID, at time: Double) -> UUID? {
        guard let item = project.layerItem(id), let track = project.layerTrackIndex(of: id), !refuseLockedLayer(track),
              time > item.at + VideoLayerItem.minimumLength, time < item.end - VideoLayerItem.minimumLength else { return nil }
        var second = item
        second.id = UUID()
        second.at = time
        second.length = item.end - time
        second.fileStart = item.fileStart + (time - item.at) * item.normalizedSpeed
        mutate(label: "Split Clip") { project in
            project.updateLayerItem(id) { $0.length = time - $0.at }
            project.layerTracks[track].items.append(second)
            project.layerTracks[track].sort()
        }
        return second.id
    }

    /// A change to a locked track above the main track: refused, and said so.
    func refuseLockedLayer(_ track: Int) -> Bool {
        guard project.layerTracks.indices.contains(track) else { return false }
        return refuseLocked(.layer(project.layerTracks[track].id))
    }
}

extension VideoDemoProject {
    /// `item` on the track `place` says (sorted, never overlapping).
    mutating func insertLayerItem(_ item: VideoLayerItem, place: VideoEditorModel.LayerPlace) {
        switch place {
        case .automatic:
            if let index = layerTracks.firstIndex(where: { $0.isFree(from: item.at, length: item.length) && !isTrackLocked(.layer($0.id)) }) {
                layerTracks[index].items.append(item)
                layerTracks[index].sort()
            } else {
                layerTracks.append(VideoLayerTrack(items: [item]))
            }
        case .track(let index):
            if layerTracks.indices.contains(index), layerTracks[index].isFree(from: item.at, length: item.length) {
                layerTracks[index].items.append(item)
                layerTracks[index].sort()
            } else {
                layerTracks.insert(VideoLayerTrack(items: [item]), at: min(max(index + 1, 0), layerTracks.count))
            }
        case .newTrack(let index):
            layerTracks.insert(VideoLayerTrack(items: [item]), at: min(max(index, 0), layerTracks.count))
        }
    }

    /// The items grouped with `id` (⌘G), itself included.
    func groupMates(of id: UUID) -> Set<UUID> {
        guard let group = layerItem(id)?.group else { return [id] }
        return Set(layerItems.filter { $0.item.group == group }.map(\.item.id))
    }

    /// Moves `ids` by `delta` seconds; the one dragged changes track from
    /// `from` to `to` (the rest of a group keep theirs). When there's no
    /// room on `to`, a new track goes above it.
    mutating func moveLayerItems(_ ids: Set<UUID>, by delta: Double, fromTrack from: Int, toTrack to: Int, newTrack: Bool) {
        // Taken out, moved, put back.
        var moved: [(track: Int, item: VideoLayerItem)] = []
        for t in layerTracks.indices {
            for item in layerTracks[t].items where ids.contains(item.id) {
                var shifted = item
                shifted.at = max(item.at + delta, 0)
                moved.append((t == from ? to : t, shifted))
            }
            layerTracks[t].items.removeAll { ids.contains($0.id) }
        }
        var target = min(max(to, 0), layerTracks.count)
        if newTrack || target == layerTracks.count {
            layerTracks.insert(VideoLayerTrack(), at: target)
            // Tracks above the new one moved up by one.
            moved = moved.map { ($0.track >= target && $0.track != to ? $0.track + 1 : $0.track, $0.item) }
        }
        for (track, item) in moved {
            var place = track == to ? target : min(track, layerTracks.count - 1)
            if !layerTracks[place].isFree(from: item.at, length: item.length) {
                // No room: a new track right above.
                place += 1
                layerTracks.insert(VideoLayerTrack(), at: place)
                if track == to { target = place }
            }
            layerTracks[place].items.append(item)
            layerTracks[place].sort()
        }
        dropEmptyLayerTracks()
    }

    mutating func trimLayerItem(_ id: UUID, leading: Bool, to time: Double) {
        updateLayerItem(id) { item in
            let speed = item.normalizedSpeed
            if leading {
                var start = min(max(time, 0), item.end - VideoLayerItem.minimumLength)
                if item.isVideo {
                    // Not before the video's first frame.
                    start = max(start, item.at - item.fileStart / speed)
                    item.fileStart += (start - item.at) * speed
                }
                item.length = item.end - start
                item.at = start
            } else {
                var end = max(time, item.at + VideoLayerItem.minimumLength)
                if item.isVideo { end = min(end, item.at + (item.fileDuration - item.fileStart) / speed) }
                item.length = end - item.at
            }
        }
        // Trimmed into the next item: kept to the room there is.
        if let t = layerTrackIndex(of: id), let item = layerItem(id) {
            let others = layerTracks[t].items.filter { $0.id != id }
            if let next = others.first(where: { $0.at >= item.at + 0.0005 }), item.end > next.at {
                updateLayerItem(id) { $0.length = max(next.at - $0.at, VideoLayerItem.minimumLength) }
            }
            if let previous = others.last(where: { $0.at < item.at }), previous.end > item.at, leading {
                let end = item.end
                updateLayerItem(id) { moved in
                    let shift = previous.end - moved.at
                    moved.at = previous.end
                    moved.fileStart += shift * moved.normalizedSpeed
                    moved.length = max(end - moved.at, VideoLayerItem.minimumLength)
                }
            }
        }
    }
}
