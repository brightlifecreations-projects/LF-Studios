import AppKit
import Foundation

/// The editor's side of typing zooms, loupes, fitting zooms around the
/// camera, cursor styles, and speeding up typing. Each is a button or a
/// switch, and each press is one ⌘Z step.
extension VideoEditorModel {
    // MARK: Typing zooms

    /// The recording saved where the text cursor was.
    var hasTypingPositions: Bool { !project.textCursor.isEmpty }

    func addTypingZooms() {
        guard hasTypingPositions else {
            showNotice(L("Record with “Track where I type” on to zoom in on typing"), symbol: "character.cursor.ibeam")
            return
        }
        let total = sourceDuration
        var count = 0
        mutate(label: "Add Typing Zooms") { count = $0.addTypingZooms(totalDuration: total) }
        if case .zoom(let id) = selection, !project.zoomRegions.contains(where: { $0.id == id }) { selection = .none }
        showNotice(count == 0 ? L("No typing found in this recording") : L("Added \(count) typing zooms — ⌘Z to undo"), symbol: "character.cursor.ibeam")
    }

    func setZoomFollow(_ id: UUID, _ follow: VideoZoomFollow) {
        updateZoom(id) { region in
            region.followsTyping = follow == .typing
            region.followsCursor = follow == .pointer
        }
        if follow == .fixed { pause() }
    }

    // MARK: Loupes

    /// A loupe at the playhead, looking like the last one edited.
    func addLoupe() {
        let style = project.loupeStyle ?? VideoLoupeStyle()
        addZoom(at: clock.time, label: "Add Loupe") { region in
            region.loupe = style
            region.scale = max(region.scale, 2)
        }
    }

    /// Full ⇄ Loupe for one zoom.
    func setZoomIsLoupe(_ id: UUID, _ isLoupe: Bool) {
        let style = project.loupeStyle ?? VideoLoupeStyle()
        updateZoom(id) { region in
            region.loupe = isLoupe ? (region.loupe ?? style) : nil
            region.offsetX = 0
            region.offsetY = 0
        }
    }

    /// Changes a loupe's look; new loupes take it too.
    func updateLoupe(_ id: UUID, coalesce: String? = nil, _ change: (inout VideoLoupeStyle) -> Void) {
        mutate(coalesce: coalesce, label: "Change Loupe") { project in
            guard let index = project.zoomRegions.firstIndex(where: { $0.id == id }), var style = project.zoomRegions[index].loupe else { return }
            change(&style)
            style = style.clamped
            project.zoomRegions[index].loupe = style
            project.zoomRegions[index].isAuto = false
            project.zoomRegions[index].isTyping = false
            project.loupeStyle = style
        }
    }

    // MARK: Fit zooms around the camera

    /// Whether the bubble is there to get in the way.
    var canFitZoomsAroundCamera: Bool {
        hasWebcamFootage && project.webcam.visible && !project.zoomRegions.isEmpty && !project.reframeActive
    }

    func fitZoomsAroundCamera(_ mode: VideoZoomCameraFit.Mode) {
        guard hasWebcamFootage, project.webcam.visible else {
            showNotice(L("This video has no camera bubble"), symbol: "video.slash")
            return
        }
        guard !project.reframeActive else {
            showNotice(L("Turn off vertical reframing to fit zooms around the camera"), symbol: "video")
            return
        }
        let total = sourceDuration
        let recording = recording
        var next = project
        let result = VideoZoomCameraFit.fit(&next, mode: mode) { candidate in
            VideoDemoExporter.makePlan(project: candidate, sourceDuration: total, recording: recording, hasWebcam: true)
        }
        if next != project {
            mutate(label: "Fit Zooms Around Camera") { $0 = next }
        }
        showNotice(Self.fitMessage(result, mode: mode), symbol: "person.crop.square", duration: 3.6)
    }

    nonisolated static func fitMessage(_ result: VideoZoomCameraFit.Result, mode: VideoZoomCameraFit.Mode) -> String {
        guard result.covered > 0 else { return L("No zooms are under the camera") }
        var sentences: [String] = []
        if result.adjusted > 0 { sentences.append(L("Adjusted \(result.adjusted) zooms — ⌘Z to undo.")) }
        if result.unfixed > 0 {
            sentences.append(mode == .shiftFraming
                ? L("\(result.unfixed) zooms can't move far enough — try Move the Camera Instead.")
                : L("\(result.unfixed) zooms have no free corner for the camera."))
        }
        return sentences.joined(separator: " ")
    }

    // MARK: Cursor styles

    func setCursorStyle(_ style: VideoCursorStyle) {
        if style == .custom, project.cursor.customImage == nil {
            chooseCursorImage()
            return
        }
        setStyle { $0.cursor.style = style }
    }

    /// Picks a PNG to use as the pointer.
    func chooseCursorImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png]
        panel.message = L("Choose a PNG to use as the pointer, then click where it points")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setCursorImage(from: url)
    }

    @discardableResult
    func setCursorImage(from url: URL) -> Bool {
        guard let picture = NSImage(contentsOf: url), picture.size.width > 0, picture.size.height > 0,
              let stored = try? VideoAssetStore.importFile(url) else {
            showNotice(L("Couldn't open that image"), symbol: "exclamationmark.triangle.fill")
            return false
        }
        let image = VideoCursorImage(path: stored.path, name: url.lastPathComponent, hotSpotX: 0, hotSpotY: 0, aspect: Double(picture.size.width / picture.size.height))
        setStyle { project in
            project.cursor.customImage = image
            project.cursor.style = .custom
        }
        return true
    }

    /// Where the custom pointer points (0…1 from its top left).
    func setCursorHotSpot(x: Double, y: Double) {
        setStyle(coalesce: "cursor-hot-spot") { project in
            project.cursor.customImage?.hotSpotX = min(max(x, 0), 1)
            project.cursor.customImage?.hotSpotY = min(max(y, 0), 1)
        }
    }

    // MARK: Speeding up typing

    /// Typing in this recording, from the best data it has.
    var typingStretches: (stretches: [VideoTypingStretch], basis: VideoTypingDetector.Basis)? {
        let artwork = plan.artwork
        return VideoTypingDetector.stretches(project: project, screenActivity: screenActivityOnAxis) { time in
            artwork.kind(of: artwork.shape(at: time, alwaysArrow: false)) == .text
        }
    }

    func speedUpTyping(_ speed: Double) {
        guard let found = typingStretches else {
            showNotice(L("This recording didn't save key timing or screen changes, so typing can't be found"), symbol: "keyboard")
            return
        }
        let total = sourceDuration
        var result = VideoDemoProject.TypingSpeedUp()
        mutate(label: "Speed Up Typing") { result = $0.speedUpTyping(found.stretches, speed: speed, totalDuration: total) }
        let typingClips = project.timelineClips.filter(\.typingSpeedUp).count
        guard result.stretches > 0 || typingClips > 0 else {
            showNotice(L("No typing found to speed up"), symbol: "keyboard")
            return
        }
        let shorter = VideoEditorModel.format(result.saved)
        var message = result.stretches > 0
            ? L("Sped up \(result.stretches) typing stretches to \(VideoEditorModel.formatScale(speed)) — \(shorter) shorter")
            : L("Typing now plays at \(VideoEditorModel.formatScale(speed))")
        if found.basis == .estimate {
            message += " " + L("(estimated from screen changes — check the speed blocks)")
        }
        showNotice(message, symbol: "hare", duration: 4)
    }
}

/// What a zoom block's camera looks at.
enum VideoZoomFollow: String, CaseIterable, Identifiable {
    case pointer
    case typing
    case fixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pointer: return L("Follow cursor")
        case .typing: return L("Follow typing")
        case .fixed: return L("Aim by hand")
        }
    }

    init(_ region: VideoZoomRegion) {
        self = region.followsTyping ? .typing : (region.followsCursor ? .pointer : .fixed)
    }
}
