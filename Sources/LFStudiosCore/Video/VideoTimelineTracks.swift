import CoreGraphics
import Foundation

/// The timeline's tracks (1.11.0), one row each, top to bottom, with a
/// header on the left: Hide, Mute and Lock.
enum VideoTimelineTrack: Hashable, Identifiable {
    case zooms
    /// The recording itself, with the click marks along its top.
    case clips
    /// Camera lane layouts and added camera video.
    case camera
    case captions
    /// Shortcut keys shown on screen.
    case keys
    /// Text, arrows, highlights, blur, and pictures (one lane per layer).
    case annotations
    case music
    /// A sound file added to the video.
    case sound(UUID)
    /// A video or picture track above the main track (1.14.0).
    case layer(UUID)

    var id: String { key }

    /// Where its state is kept in the project.
    var key: String {
        switch self {
        case .zooms: return "zooms"
        case .clips: return "clips"
        case .camera: return "camera"
        case .captions: return "captions"
        case .keys: return "keys"
        case .annotations: return "annotations"
        case .music: return "music"
        case .sound(let id): return "sound-\(id.uuidString)"
        case .layer(let id): return "layer-\(id.uuidString)"
        }
    }

    var symbol: String {
        switch self {
        case .zooms: return "plus.magnifyingglass"
        case .clips: return "film"
        case .camera: return "person.crop.rectangle"
        case .captions: return "captions.bubble"
        case .keys: return "command"
        case .annotations: return "textformat"
        case .music: return "music.note"
        case .sound: return "waveform"
        case .layer: return "square.2.layers.3d.top.filled"
        }
    }

    /// Hide: not drawn in the preview and the export.
    var canHide: Bool {
        switch self {
        case .music, .sound: return false
        default: return true
        }
    }

    /// Mute: not heard in the preview and the export.
    var canMute: Bool {
        switch self {
        case .clips, .music, .sound, .layer: return true
        default: return false
        }
    }
}

/// A track's switches. All off: as before 1.11.0.
struct VideoTrackState: Codable, Equatable {
    var hidden = false
    var muted = false
    var locked = false
    /// Shown as a thin row in the timeline (nothing else changes).
    var collapsed = false

    var isDefault: Bool { self == VideoTrackState() }

    init() {}

    private enum CodingKeys: String, CodingKey { case hidden, muted, locked, collapsed }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hidden = (try? c.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false
        locked = (try? c.decodeIfPresent(Bool.self, forKey: .locked)) ?? false
        collapsed = (try? c.decodeIfPresent(Bool.self, forKey: .collapsed)) ?? false
    }
}

extension VideoDemoProject {
    /// Every track, top to bottom: the ones that are always there, then a
    /// row per added sound file.
    var timelineTracks: [VideoTimelineTrack] {
        // The tracks above the main track, highest first, over it.
        [.zooms] + layerTracks.reversed().map { .layer($0.id) } + [.clips, .camera, .captions, .keys, .annotations, .music] + audioTracks.map { .sound($0.id) }
    }

    /// A track's switches. The keys' Hide and a sound file's or the
    /// recording's Mute are the switches those already had (Keys ▸ Show
    /// keys, the track's and the recording's Mute), so they stay one thing.
    func trackState(_ track: VideoTimelineTrack) -> VideoTrackState {
        var state = trackStates[track.key] ?? VideoTrackState()
        switch track {
        case .keys: state.hidden = !keystrokeStyle.visible
        case .clips: state.muted = audio.muted
        case .sound(let id): state.muted = audioTracks.first { $0.id == id }?.muted ?? false
        default: break
        }
        return state
    }

    mutating func setTrackState(_ track: VideoTimelineTrack, _ change: (inout VideoTrackState) -> Void) {
        var state = trackState(track)
        change(&state)
        switch track {
        case .keys:
            keystrokeStyle.visible = !state.hidden
            state.hidden = false
        case .clips:
            audio.muted = state.muted
            state.muted = false
        case .sound(let id):
            if let index = audioTracks.firstIndex(where: { $0.id == id }) { audioTracks[index].muted = state.muted }
            state.muted = false
        default: break
        }
        trackStates[track.key] = state.isDefault ? nil : state
    }

    func isTrackHidden(_ track: VideoTimelineTrack) -> Bool { trackState(track).hidden }
    func isTrackLocked(_ track: VideoTimelineTrack) -> Bool { trackState(track).locked }

    /// The project as it plays and exports: hidden tracks left out, muted
    /// ones silent. The timeline still shows (and edits) everything.
    func forOutput() -> VideoDemoProject {
        guard !trackStates.isEmpty else { return self }
        var project = self
        if isTrackHidden(.zooms) { project.zoomRegions = [] }
        if isTrackHidden(.camera) {
            // Hidden, not removed: a split recording keeps the video's shape.
            if aspectPreset == .source, webcam.visible, webcam.effectiveLayout == .split, let whole = splitVideoAspect {
                project.aspectPreset = .custom
                project.customAspect = whole
            }
            project.webcam.visible = false
        }
        if isTrackHidden(.captions) { project.captionStyle.visible = false }
        if isTrackHidden(.annotations) { project.overlayEffects = [] }
        if trackState(.music).muted { project.music = nil }
        return project
    }

    /// The screen recording isn't drawn (Hide on Video clips): the
    /// background, the camera and the rest still are.
    var hidesScreen: Bool { trackStates[VideoTimelineTrack.clips.key]?.hidden == true }
}

// MARK: - The editor's track headers

extension VideoTimelineTrack {
    /// The header's name.
    func title(in project: VideoDemoProject) -> String {
        switch self {
        case .zooms: return L("Zooms")
        case .clips: return L("Video clips")
        case .camera: return L("Camera")
        case .captions: return L("Captions")
        case .keys: return L("Keys")
        case .annotations: return L("Text & annotations")
        case .music: return L("Music")
        case .sound(let id): return project.audioTracks.first { $0.id == id }?.name ?? L("Sound")
        case .layer(let id):
            let number = (project.layerTracks.firstIndex { $0.id == id } ?? 0) + 2
            return L("Video \(number)")
        }
    }
}

extension VideoEditorModel {
    func toggleTrackHidden(_ track: VideoTimelineTrack) {
        let hidden = project.isTrackHidden(track)
        mutate(label: hidden ? "Show Track" : "Hide Track") { $0.setTrackState(track) { $0.hidden.toggle() } }
    }

    func toggleTrackMuted(_ track: VideoTimelineTrack) {
        let muted = project.trackState(track).muted
        mutate(label: muted ? "Unmute Track" : "Mute Track") { $0.setTrackState(track) { $0.muted.toggle() } }
    }

    func toggleTrackLocked(_ track: VideoTimelineTrack) {
        let locked = project.isTrackLocked(track)
        mutate(label: locked ? "Unlock Track" : "Lock Track") { $0.setTrackState(track) { $0.locked.toggle() } }
        // A selection on a track that just locked can't be changed.
        if !locked, let selected = trackOfSelection, selected == track { selection = .none }
    }

    func toggleTrackCollapsed(_ track: VideoTimelineTrack) {
        mutate(label: "Collapse Track") { $0.setTrackState(track) { $0.collapsed.toggle() } }
    }

    func isTrackLocked(_ track: VideoTimelineTrack) -> Bool { project.isTrackLocked(track) }

    /// A change to a locked track: refused, and said so. True when refused.
    func refuseLocked(_ track: VideoTimelineTrack) -> Bool {
        guard project.isTrackLocked(track) else { return false }
        showNotice(L("“\(track.title(in: project))” is locked. Unlock it in its header to change it."), symbol: "lock.fill")
        return true
    }

    /// The track the selection is on (nil: none, or a range).
    var trackOfSelection: VideoTimelineTrack? {
        if let piece = selectedAudioPiece { return .sound(piece.track) }
        switch selection {
        case .zoom: return .zooms
        case .clip, .click: return .clips
        case .overlay: return .annotations
        case .caption: return .captions
        case .keystroke: return .keys
        case .cameraLayout: return .camera
        case .layer(let id): return project.layerTrackIndex(of: id).map { .layer(project.layerTracks[$0].id) }
        case .none, .range: return nil
        }
    }

    /// A locked track among what Delete would remove.
    var lockedTrackInSelection: VideoTimelineTrack? {
        if let track = trackOfSelection, project.isTrackLocked(track) { return track }
        if case .range = selection, project.isTrackLocked(.clips) { return .clips }
        return nil
    }
}

// MARK: - Track height

/// Small, Medium or Large lanes (remembered on this Mac).
enum VideoTimelineTrackHeight: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: return L("Small")
        case .medium: return L("Medium")
        case .large: return L("Large")
        }
    }

    /// Small is the timeline as it was before 1.11.0.
    var scale: CGFloat {
        switch self {
        case .small: return 1
        case .medium: return 1.3
        case .large: return 1.65
        }
    }
}

// MARK: - Rows

/// Where each track's row is on the timeline, top to bottom (below the
/// ruler): its lanes, or a thin row with a hint when it's empty or
/// collapsed. The lanes and the headers both follow it.
struct VideoTimelineRowLayout: Equatable {
    struct Row: Equatable {
        let track: VideoTimelineTrack
        let top: CGFloat
        let height: CGFloat
        /// Nothing on it yet: a thin row with an "add" hint.
        let isEmpty: Bool
        let collapsed: Bool

        /// Where its lanes start.
        var contentTop: CGFloat { top + VideoTimelineRowLayout.padding }
        var showsContent: Bool { !isEmpty && !collapsed }
    }

    static let padding: CGFloat = 5
    static let thinHeight: CGFloat = 26
    static let separator: CGFloat = 1

    let rows: [Row]
    /// All the rows, with a little room under the last.
    let height: CGFloat

    init(project: VideoDemoProject, hasCamera: Bool) {
        typealias M = VideoTimelineMetrics
        var rows: [Row] = []
        var top: CGFloat = 0
        for track in project.timelineTracks {
            let content = Self.contentHeight(track, project: project, hasCamera: hasCamera)
            // The zooms and the recording always show (they're where you click to add).
            let alwaysOpen = track == .zooms || track == .clips
            let collapsed = !alwaysOpen && project.trackState(track).collapsed
            let isEmpty = !alwaysOpen && content <= 0
            let height = isEmpty || collapsed ? Self.thinHeight : content + Self.padding * 2
            rows.append(Row(track: track, top: top, height: height, isEmpty: isEmpty, collapsed: collapsed))
            top += height + Self.separator
        }
        self.rows = rows
        height = top + 10
    }

    func row(_ track: VideoTimelineTrack) -> Row? { rows.first { $0.track == track } }

    /// Where a track's lanes start (nil: thin row, nothing drawn).
    func contentTop(_ track: VideoTimelineTrack) -> CGFloat? {
        guard let row = row(track), row.showsContent else { return nil }
        return row.contentTop
    }

    /// How tall a track's lanes are (0: nothing on it).
    static func contentHeight(_ track: VideoTimelineTrack, project: VideoDemoProject, hasCamera: Bool) -> CGFloat {
        typealias M = VideoTimelineMetrics
        switch track {
        case .zooms: return M.zoomTrackHeight
        case .clips: return (project.clickEvents.isEmpty ? 0 : M.clickLaneHeight + 3) + M.clipTrackHeight
        case .camera:
            let layouts = hasCamera && !project.cameraLayouts.isEmpty ? M.cameraLaneHeight : 0
            let footage = project.importedCamera == nil ? 0 : M.cameraFootageLaneHeight
            return layouts + footage + (layouts > 0 && footage > 0 ? M.overlayLaneGap : 0)
        case .captions: return project.captions.isEmpty ? 0 : M.captionLaneHeight
        case .keys: return project.keystrokes.isEmpty ? 0 : M.keysLaneHeight
        case .annotations:
            let lanes = M.overlayLanes(project)
            return lanes == 0 ? 0 : CGFloat(lanes) * M.overlayLaneHeight + CGFloat(lanes - 1) * M.overlayLaneGap
        case .music: return project.music == nil ? 0 : M.musicLaneHeight
        case .sound: return M.musicLaneHeight
        case .layer: return M.layerLaneHeight
        }
    }

    /// The hint on an empty row.
    static func hint(_ track: VideoTimelineTrack) -> String {
        switch track {
        case .zooms, .clips, .sound, .layer: return ""
        case .camera: return L("Camera layouts and added camera video show here: Camera panel ▸ Layouts")
        case .captions: return L("Add captions in the Captions panel")
        case .keys: return L("Shortcuts pressed while recording show here")
        case .annotations: return L("Add text, arrows, highlights, blur or pictures with the tools above the preview")
        case .music: return L("Add music in the Audio panel")
        }
    }
}

// MARK: - The divider between the preview and the timeline

/// How tall the timeline is: the divider's place, kept so that the
/// preview and the timeline both stay usable, a 13" MacBook included.
enum VideoEditorLayout {
    /// The editor's toolbar and the line under it.
    static let toolbarHeight: CGFloat = 53
    /// About a third of the window.
    static let defaultTimelineFraction = 0.36
    /// Shorter windows (a 13" MacBook's): Small tracks and 40%, so Zooms,
    /// Video clips, Camera and Captions show without scrolling.
    static let compactWindowHeight: CGFloat = 1000
    static let compactTimelineFraction = 0.40

    static func isCompact(windowHeight: CGFloat) -> Bool { windowHeight < compactWindowHeight }

    /// Where the divider starts, until it's dragged.
    static func defaultFraction(windowHeight: CGFloat) -> Double {
        isCompact(windowHeight: windowHeight) ? compactTimelineFraction : defaultTimelineFraction
    }

    /// The track height to start with, until one is chosen.
    static func defaultTrackHeight(windowHeight: CGFloat) -> VideoTimelineTrackHeight {
        isCompact(windowHeight: windowHeight) ? .small : .medium
    }

    /// The divider's place: where it was dragged to, or the start for
    /// this window.
    static func fraction(chosen: Double?, windowHeight: CGFloat) -> Double {
        chosen ?? defaultFraction(windowHeight: windowHeight)
    }
    static let minimumTimeline: CGFloat = 200
    /// The preview area: the tools, the picture and the tips under it.
    static let minimumPreview: CGFloat = 300

    /// The timeline's height for a window `windowHeight` tall with the
    /// divider at `fraction` of the space under the toolbar.
    static func timelineHeight(windowHeight: CGFloat, fraction: Double) -> CGFloat {
        let available = max(windowHeight - toolbarHeight, 0)
        let wanted = (available * CGFloat(fraction)).rounded()
        let most = max(available - minimumPreview, minimumTimeline)
        return min(max(wanted, minimumTimeline), most)
    }

    /// Where the divider is after dragging the timeline to `height`.
    static func fraction(forTimelineHeight height: CGFloat, windowHeight: CGFloat) -> Double {
        let available = max(windowHeight - toolbarHeight, 1)
        let kept = timelineHeight(windowHeight: windowHeight, fraction: Double(height / available))
        return Double(kept / available)
    }
}
