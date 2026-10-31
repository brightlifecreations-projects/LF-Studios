import SwiftUI

// MARK: - Annotations onto a track (1.15.0)

/// 1.14.0's text and picture annotations draw over every track. Move to a
/// track makes one a clip above the main track instead, so it takes its
/// place in the tracks' order (and gets keyframes, animations, effects…).
/// Nothing moves on its own: older projects look as they did.
extension VideoEditorModel {
    /// Text and picture annotations can move to a track.
    func canMoveToTrack(_ overlay: VideoDemoOverlayEffect) -> Bool {
        overlay.kind == .text || (overlay.kind == .image && overlay.image != nil)
    }

    /// The annotation as a clip on a new top track, where it showed. One
    /// ⌘Z step.
    @discardableResult
    func moveAnnotationToTrack(_ id: UUID) -> UUID? {
        if refuseLocked(.annotations) { return nil }
        guard let overlay = project.overlayEffects.first(where: { $0.id == id }), canMoveToTrack(overlay) else {
            showNotice(L("Only text and picture annotations can move to a track"), symbol: "square.2.layers.3d.top.filled")
            return nil
        }
        guard let item = VideoLayerItem.from(overlay, project: project, segments: segments) else { return nil }
        mutate(label: "Move to Track") { project in
            project.overlayEffects.removeAll { $0.id == id }
            // On top: it still draws over the other tracks, as before.
            project.insertLayerItem(item, place: .newTrack(project.layerTracks.count))
        }
        selection = .layer(item.id)
        showNotice(L("“\(item.name)” is a clip on its own track now"), symbol: "square.2.layers.3d.top.filled")
        return item.id
    }
}

extension VideoLayerItem {
    /// A clip that shows what `overlay` showed (frame-pinned, at the
    /// timeline time of its start).
    static func from(_ overlay: VideoDemoOverlayEffect, project: VideoDemoProject, segments: [VideoDemoTimelineSegment]) -> VideoLayerItem? {
        guard let start = VideoDemoProject.timelineTimeIfIncluded(sourceTime: overlay.time, segments: segments) else { return nil }
        let end = VideoDemoProject.timelineTimeIfIncluded(sourceTime: overlay.time + overlay.duration, segments: segments) ?? (start + overlay.duration)
        let length = max(end - start, minimumLength)
        let canvas = project.canvasSize()
        switch overlay.kind {
        case .image:
            guard let image = overlay.image else { return nil }
            // Pictures are already pinned to the frame.
            var item = VideoLayerItem(kind: .image, path: image.path, name: image.name, at: start, length: length, aspect: max(image.aspect, 0.01))
            item.x = overlay.x
            item.y = overlay.y
            item.width = overlay.width
            item.opacity = image.opacity
            item.rotation = image.keptRotation
            return item
        case .text:
            // Text sits on the recording: its place there, on the frame.
            let stage = project.stageRect(in: canvas)
            var content = VideoTextContent(string: overlay.text.isEmpty ? L("Your text") : overlay.text)
            if let family = overlay.font?.family, VideoTextFonts.families.contains(family) { content.font = family }
            content.bold = overlay.font?.weight != .regular
            content.size = max(min(overlay.height * Double(stage.height / max(canvas.height, 1)) * 1080 * 0.55, 300), 12)
            if let color = overlay.color {
                content.background = color.a < 0.05 ? nil : VideoTextContent.Background(color: color, padding: 18, radius: 12)
                if color.a < 0.05 { content.shadow = VideoTextContent.Shadow() }
            } else {
                content.background = VideoTextContent.Background()
            }
            var item = VideoLayerItem.text(content, at: start, canvas: canvas)
            item.length = length
            item.x = Double((stage.minX + CGFloat(overlay.x) * stage.width) / max(canvas.width, 1))
            item.y = Double((stage.minY + CGFloat(overlay.y) * stage.height) / max(canvas.height, 1))
            item.rotation = overlay.rotation ?? 0
            return item
        default:
            return nil
        }
    }
}

/// The annotation inspector's Move to a track button.
struct VideoMoveToTrackButton: View {
    @ObservedObject var model: VideoEditorModel
    let overlay: VideoDemoOverlayEffect

    var body: some View {
        if model.canMoveToTrack(overlay) {
            Button {
                model.moveAnnotationToTrack(overlay.id)
            } label: {
                Label(L("Move to a Track"), systemImage: "square.2.layers.3d.top.filled").frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .help(L("Makes it a clip above the main track: it takes its place in the tracks' order and gets keyframes, animations and effects"))
        }
    }
}
