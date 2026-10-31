import SwiftUI

// MARK: - Compound clips (1.15.0)

/// Clips above the main track made into one: shown as one block on the
/// timeline, moved, sized, turned and faded as one. Its clips keep their
/// own tracks and settings (their `group` is the compound's id); Break apart
/// gives them back, looking as they did.
struct VideoCompoundClip: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    /// Its middle (0…1 from the top left), size (1: as made) and turn.
    var x = 0.5
    var y = 0.5
    var scale = 1.0
    var rotation = 0.0
    var opacity = 1.0

    var isIdentity: Bool { abs(x - 0.5) < 0.000_1 && abs(y - 0.5) < 0.000_1 && abs(scale - 1) < 0.000_1 && abs(rotation) < 0.001 && abs(opacity - 1) < 0.000_1 }

    /// `item` as the compound shows it on a `canvas`-shaped frame.
    func apply(to item: VideoLayerItem, canvas: CGSize) -> VideoLayerItem {
        guard !isIdentity else { return item }
        var out = item
        let w = Double(max(canvas.width, 1)), h = Double(max(canvas.height, 1))
        let (x, y) = place(item.x, item.y, w: w, h: h)
        out.x = x
        out.y = y
        out.width = item.width * scale
        out.rotation = item.rotation + rotation
        out.opacity = item.opacity * opacity
        // Keyed places and sizes move with it (each value on its own).
        if var keys = out.keys {
            for property in [VideoKeyProperty.x, .y, .width, .rotation, .opacity] {
                guard let list = keys.tracks[property.rawValue] else { continue }
                keys.tracks[property.rawValue] = list.map { key in
                    var key = key
                    switch property {
                    case .x: key.value = place(key.value, item.y, w: w, h: h).0
                    case .y: key.value = place(item.x, key.value, w: w, h: h).1
                    case .width: key.value *= scale
                    case .rotation: key.value += rotation
                    default: key.value *= opacity
                    }
                    return key
                }
            }
            out.keys = keys
        }
        return out
    }

    /// A point (shares of the frame) scaled and turned about the frame's
    /// middle, then moved to the compound's place.
    private func place(_ px: Double, _ py: Double, w: Double, h: Double) -> (Double, Double) {
        let dx = (px - 0.5) * w * scale, dy = (py - 0.5) * h * scale
        let a = rotation * .pi / 180
        let rx = dx * cos(a) - dy * sin(a), ry = dx * sin(a) + dy * cos(a)
        return (x + rx / w, y + ry / h)
    }
}

extension VideoDemoProject {
    func compound(_ id: UUID?) -> VideoCompoundClip? {
        guard let id else { return nil }
        return compounds?.first { $0.id == id }
    }

    /// The compound's clips, earliest first.
    func compoundMembers(_ id: UUID) -> [(track: Int, item: VideoLayerItem)] {
        layerItems.filter { $0.item.group == id }.sorted { $0.item.at < $1.item.at }
    }

    /// The compound `item` belongs to.
    func compound(of item: VideoLayerItem) -> VideoCompoundClip? { compound(item.group) }
}

extension VideoEditorModel {
    /// The clips a compound would be made of: the selected clips above the
    /// main track (and their groups).
    var compoundCandidates: [UUID] {
        var ids: [UUID] = []
        for selection in [selection] + extraSelection {
            if case .layer(let id) = selection { ids += project.groupMates(of: id) }
        }
        return Array(Set(ids))
    }

    /// Make compound clip (⌥G): the selected clips above the main track as
    /// one. One ⌘Z step.
    @discardableResult
    func makeCompoundClip() -> Bool {
        let ids = compoundCandidates
        guard !ids.isEmpty else {
            showNotice(L("Select clips above the main track to make a compound clip"), symbol: "square.stack.3d.down.right")
            return false
        }
        for id in ids { if let track = project.layerTrackIndex(of: id), refuseLockedLayer(track) { return false } }
        let number = (project.compounds?.count ?? 0) + 1
        let compound = VideoCompoundClip(name: L("Compound clip \(number)"))
        // Clips already in another compound leave it (its transform baked in).
        let old = Set(ids.compactMap { project.layerItem($0)?.group }).compactMap { project.compound($0) }
        let canvas = project.canvasSize()
        mutate(label: "Make Compound Clip") { project in
            for previous in old { project.breakApart(previous.id, canvas: canvas) }
            for id in ids { project.updateLayerItem(id) { $0.group = compound.id } }
            project.compounds = (project.compounds ?? []) + [compound]
        }
        if let first = project.compoundMembers(compound.id).first { selection = .layer(first.item.id) }
        extraSelection = []
        return true
    }

    /// Break apart: the compound's clips on their own again, where they were
    /// shown. One ⌘Z step.
    @discardableResult
    func breakApartCompound() -> Bool {
        guard let item = selectedLayerItem, let compound = project.compound(of: item) else {
            showNotice(L("Select a compound clip to break it apart"), symbol: "square.stack.3d.down.right")
            return false
        }
        for member in project.compoundMembers(compound.id) where refuseLockedLayer(member.track) { return false }
        let canvas = project.canvasSize()
        mutate(label: "Break Apart") { project in project.breakApart(compound.id, canvas: canvas) }
        return true
    }

    /// The selected compound's place, size, turn, fade or name.
    func setCompound(_ id: UUID, coalesce: Bool = true, _ change: (inout VideoCompoundClip) -> Void) {
        for member in project.compoundMembers(id) where refuseLockedLayer(member.track) { return }
        mutate(coalesce: coalesce ? "compound-\(id)" : nil, label: "Compound Clip") { project in
            guard let i = project.compounds?.firstIndex(where: { $0.id == id }) else { return }
            change(&project.compounds![i])
            project.compounds![i].scale = min(max(project.compounds![i].scale, 0.05), 8)
            project.compounds![i].opacity = min(max(project.compounds![i].opacity, 0), 1)
        }
    }
}

extension VideoDemoProject {
    /// The compound's look baked into its clips, which go back on their own.
    mutating func breakApart(_ id: UUID, canvas: CGSize) {
        guard let compound = compound(id) else { return }
        for t in layerTracks.indices {
            for i in layerTracks[t].items.indices where layerTracks[t].items[i].group == id {
                var item = compound.apply(to: layerTracks[t].items[i], canvas: canvas)
                item.group = nil
                layerTracks[t].items[i] = item
            }
        }
        compounds?.removeAll { $0.id == id }
        if compounds?.isEmpty == true { compounds = nil }
    }

    /// Compounds whose clips are all gone (deleted) go too.
    mutating func dropEmptyCompounds() {
        guard let list = compounds else { return }
        let used = Set(layerItems.compactMap(\.item.group))
        let kept = list.filter { used.contains($0.id) }
        if kept.count != list.count { compounds = kept.isEmpty ? nil : kept }
    }
}

// MARK: - Properties ▸ Compound clip

struct VideoCompoundSection: View {
    @ObservedObject var model: VideoEditorModel
    let compound: VideoCompoundClip

    var body: some View {
        VideoInspectorSection(L("Compound clip")) {
            TextField(L("Name"), text: Binding(get: { compound.name }, set: { name in model.setCompound(compound.id) { $0.name = name } }))
                .textFieldStyle(.roundedBorder)
            slider(L("Position across"), get: { $0.x * 100 }, set: { $0.x = $1 / 100 }, range: -50...150, defaultValue: 50)
            slider(L("Position down"), get: { $0.y * 100 }, set: { $0.y = $1 / 100 }, range: -50...150, defaultValue: 50)
            slider(L("Size"), get: { $0.scale * 100 }, set: { $0.scale = $1 / 100 }, range: 5...400, defaultValue: 100)
            slider(L("Rotation"), get: { $0.rotation }, set: { $0.rotation = $1 }, range: -180...180, defaultValue: 0, format: { L("\(Int($0.rounded()))°") })
            slider(L("Opacity"), get: { $0.opacity * 100 }, set: { $0.opacity = $1 / 100 }, range: 0...100, defaultValue: 100)
            Button {
                model.perform(.breakApart)
            } label: {
                Label(L("Break Apart"), systemImage: "square.stack.3d.up.slash").frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .help(L("Its clips on their own again, looking as they do now (⇧⌥G)"))
            Text(L("Its clips keep their own settings: break it apart to change one."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func slider(_ title: String, get: @escaping (VideoCompoundClip) -> Double, set: @escaping (inout VideoCompoundClip, Double) -> Void,
                        range: ClosedRange<Double>, defaultValue: Double, format: @escaping (Double) -> String = VideoLayerItemEditor.percent) -> some View {
        VideoSliderRow(title: title, value: Binding(get: { get(compound) }, set: { value in model.setCompound(compound.id) { set(&$0, value) } }),
                       range: range, defaultValue: defaultValue, format: format, onEditingEnded: { model.endGesture() })
    }
}

/// The compound's box on the player: drag to move it, a corner to size it.
struct VideoCompoundHandles: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock
    let compound: VideoCompoundClip
    let viewSize: CGSize

    var body: some View {
        // The box around its clips as made, then as the compound shows it.
        let members = model.project.compoundMembers(compound.id).map(\.item).filter { $0.isShowing(at: clock.time) }
        let local = members.map { $0.placed(at: clock.time).rect(in: viewSize) }.reduce(CGRect.null) { $0.union($1) }
        if !local.isNull {
            let center = Self.shown(CGPoint(x: local.midX / viewSize.width, y: 1 - local.midY / viewSize.height), compound: compound, size: viewSize)
            let w = local.width * compound.scale, h = local.height * compound.scale
            VideoTransformBox(
                rect: CGRect(x: center.x * viewSize.width - w / 2, y: center.y * viewSize.height - h / 2, width: w, height: h),
                rotation: compound.rotation,
                viewSize: viewSize,
                help: L("Drag to move the compound clip; drag a corner to size it"),
                rotateLabel: L("Turn it"),
                changed: { rect in
                    let scale = Double(rect.width / max(local.width, 1))
                    // Where its middle has to be so the box lands on `rect`.
                    let a = compound.rotation * .pi / 180
                    let dx = (Double(local.midX / viewSize.width) - 0.5) * Double(viewSize.width) * scale
                    let dy = (0.5 - Double(local.midY / viewSize.height)) * Double(viewSize.height) * scale
                    let rx = dx * cos(a) - dy * sin(a), ry = dx * sin(a) + dy * cos(a)
                    model.setCompound(compound.id) {
                        $0.scale = scale
                        $0.x = Double(rect.midX / viewSize.width) - rx / Double(viewSize.width)
                        $0.y = Double(rect.midY / viewSize.height) - ry / Double(viewSize.height)
                    }
                },
                turned: { degrees in model.setCompound(compound.id) { $0.rotation = degrees } },
                ended: { model.endGesture() }
            )
        }
    }

    /// A point (shares from the top left) as the compound shows it.
    static func shown(_ point: CGPoint, compound: VideoCompoundClip, size: CGSize) -> CGPoint {
        var probe = VideoLayerItem(kind: .image, path: "", name: "", at: 0, length: 1, aspect: 1)
        probe.x = Double(point.x)
        probe.y = Double(point.y)
        let moved = compound.apply(to: probe, canvas: size)
        return CGPoint(x: moved.x, y: moved.y)
    }
}
