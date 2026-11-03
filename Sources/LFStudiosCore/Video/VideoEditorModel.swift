import AppKit
import AVFoundation
import SwiftUI

struct VideoTimelineThumbnail: Identifiable {
    let id = UUID()
    /// Source seconds.
    let time: Double
    let image: NSImage

    /// A filmstrip in one pass through the recording: one decoder for all
    /// the pictures, where a picture at a time opened one each (160 for a
    /// long recording). `offset` moves them onto the source axis.
    static func generate(with generator: AVAssetImageGenerator, at times: [Double], offset: Double = 0) async -> [VideoTimelineThumbnail] {
        let requests = times.map { CMTime(seconds: $0, preferredTimescale: 600) }
        let requested = Dictionary(zip(requests.map(\.value), times), uniquingKeysWith: { first, _ in first })
        var thumbnails: [VideoTimelineThumbnail] = []
        for await result in generator.images(for: requests) {
            guard let image = try? result.image else { continue }
            let time = requested[result.requestedTime.convertScale(600, method: .roundHalfAwayFromZero).value] ?? result.requestedTime.seconds
            thumbnails.append(VideoTimelineThumbnail(time: offset + time, image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))))
        }
        return thumbnails.sorted { $0.time < $1.time }
    }
}

/// Peak envelope of the recording's audio (all tracks mixed), in SOURCE time.
struct VideoWaveform {
    static let bucketsPerSecond = 50.0
    let peaks: [Float]
    /// At or below this, the sound counts as silence: well under speech,
    /// above the room's steady noise.
    let quiet: Float

    init(peaks: [Float]) {
        self.peaks = peaks
        let sorted = peaks.sorted()
        func percentile(_ fraction: Double) -> Float {
            sorted.isEmpty ? 0 : sorted[min(Int(Double(sorted.count) * fraction), sorted.count - 1)]
        }
        let floor = percentile(0.1)
        let loud = percentile(0.9)
        quiet = min(loud * 0.15, max(floor * 2.5, loud * 0.03, 0.001))
    }

    func peak(from start: Double, to end: Double) -> Float {
        guard !peaks.isEmpty, end > start else { return 0 }
        let a = max(Int(start * Self.bucketsPerSecond), 0)
        let b = min(Int(end * Self.bucketsPerSecond) + 1, peaks.count)
        guard a < b else { return 0 }
        var value: Float = 0
        for index in a..<b { value = max(value, peaks[index]) }
        return value
    }
}

struct VideoDemoTimelineRange: Equatable, Identifiable {
    var id: String { "\(start)-\(end)" }
    var start: Double
    var end: Double

    var normalized: VideoDemoTimelineRange {
        VideoDemoTimelineRange(start: min(start, end), end: max(start, end))
    }

    var duration: Double { max(end - start, 0) }
}

/// Changes only when something DRAWN on the timeline changes (clips,
/// zooms, annotations, clicks, captions, shortcuts, selection, zoom level)
/// — style edits like padding or backgrounds never re-render its lanes.
@MainActor
final class VideoTimelineState: ObservableObject {
    @Published private(set) var revision = 0

    func bump() { revision &+= 1 }
}

struct VideoEditorNotice: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let symbol: String
}

/// Why a video couldn't be opened, in words people can act on (the
/// system's own message is kept as the small print).
struct VideoLoadFailure: Equatable {
    enum Kind: Equatable {
        case missing
        case noVideo
        case unreadable
    }

    let kind: Kind
    let detail: String

    static func classify(_ error: Error, url: URL) -> VideoLoadFailure {
        let detail = error.localizedDescription
        if !FileManager.default.fileExists(atPath: url.path) { return VideoLoadFailure(kind: .missing, detail: detail) }
        if case VideoDemoExportError.missingVideoTrack = error { return VideoLoadFailure(kind: .noVideo, detail: detail) }
        return VideoLoadFailure(kind: .unreadable, detail: detail)
    }

    var title: String {
        switch kind {
        case .missing: return L("This video isn't there anymore")
        case .noVideo: return L("There's no video in this file")
        case .unreadable: return L("LF Studios can't open this file")
        }
    }

    var message: String {
        switch kind {
        case .missing: return L("It was moved, renamed, or deleted. Open it from where it is now.")
        case .noVideo: return L("It only has sound, or nothing at all. LF Studios edits screen recordings and other videos.")
        case .unreadable: return L("It may be damaged, still being saved, or in a format this Mac can't play. MP4 and MOV videos work best.")
        }
    }
}

@MainActor
final class VideoEditorModel: ObservableObject {
    enum Selection: Equatable {
        case none
        case zoom(UUID)
        case clip(UUID)
        case overlay(UUID)
        case click(UUID)
        case caption(UUID)
        case keystroke(UUID)
        case cameraLayout(UUID)
        /// An item on a track above the main track (1.14.0).
        case layer(UUID)
        case range(VideoDemoTimelineRange)
    }

    enum InspectorTab: String, CaseIterable, Identifiable {
        case background
        case cursor
        case zoom
        case camera
        case captions
        case audio

        var id: String { rawValue }
        var title: String {
            switch self {
            case .background: return L("Style")
            case .cursor: return L("Cursor")
            case .zoom: return L("Zoom")
            case .camera: return L("Camera")
            case .captions: return L("Captions")
            case .audio: return L("Audio")
            }
        }
        var help: String {
            switch self {
            case .background: return L("Background, padding, corners, shadow")
            case .cursor: return L("Cursor, clicks, and keyboard shortcuts")
            case .zoom: return L("Zoom moves")
            case .camera: return L("Camera bubble")
            case .captions: return L("Captions from your narration — and cut the video by editing its words")
            case .audio: return L("Sound")
            }
        }
        var symbol: String {
            switch self {
            case .background: return "photo.on.rectangle.angled"
            case .cursor: return "cursorarrow.motionlines"
            case .zoom: return "plus.magnifyingglass"
            case .camera: return "person.crop.circle"
            case .captions: return "text.quote"
            case .audio: return "speaker.wave.2.fill"
            }
        }
    }

    enum ExportPhase: Equatable {
        case idle
        /// An export that holds the editor until it ends. Exports run in the
        /// background now (`.exporting`), so nothing holds it: the editor's
        /// keys keep working — Esc hides the sheet.
        case running(progress: Double, started: Date, destination: URL, toClipboard: Bool)
        /// A background export the sheet is following.
        case exporting(progress: Double, started: Date, destination: URL, toClipboard: Bool)
        case finished(url: URL, bytes: Int64, copied: Bool)
        case failed(String)
    }

    // MARK: State

    @Published var project: VideoDemoProject {
        didSet { projectDidChange(from: oldValue) }
    }
    @Published private(set) var sourceDuration: Double = 0
    @Published private(set) var sourceFrameRate: Double = 60
    @Published private(set) var hasAudio = false
    /// The recording came with camera footage that's still on disk.
    @Published private(set) var hasWebcamFootage = false
    /// Lining up the imported camera video by sound.
    @Published var isSyncingCamera = false
    /// The camera footage being loaded after it changed.
    var cameraLoad: Task<Void, Never>?
    /// What each of the recording's audio tracks carries.
    @Published private(set) var audioKinds: [VideoAudioKind] = []
    /// Voice enhancement progress, 0…1 (nil when idle).
    @Published var voiceJob: Double?
    @Published var voiceError: String?
    var voiceTask: Task<Bool, Never>?
    @Published private(set) var isReady = false
    @Published var loadError: String?
    @Published private(set) var loadFailure: VideoLoadFailure?
    /// Closes this editor's window (set by the window controller).
    var closeEditor: (() -> Void)?
    /// A piece of an added sound file, picked on its timeline lane.
    @Published var selectedAudioPiece: VideoAudioPieceRef?
    /// The added track being synced by sound.
    @Published var isSyncingAudio: UUID?
    @Published var selection: Selection = .none {
        didSet {
            // LF Studios layout: something newly selected shows its settings.
            if selection != .none, selection != oldValue, propertiesTab == .video { propertiesTab = .clip }
            if selection != .none { selectedAudioPiece = nil }
            // Picking something on its own (even one already picked) drops
            // the others.
            if !keepsExtraSelection, !extraSelection.isEmpty { extraSelection = [] }
            guard selection != oldValue else { return }
            previewRenderer.invalidate()
            refreshTimeline()
        }
    }
    /// Picked along with `selection` (⇧- or ⌘-click on the timeline): they
    /// delete and move together.
    @Published var extraSelection: [Selection] = [] {
        didSet { refreshTimeline() }
    }
    /// Set while the lead item changes without dropping the others.
    var keepsExtraSelection = false
    /// Names the next undo step (a group move made of many small edits).
    var pendingUndoLabel: String?
    /// Where each selected item was when a group move began.
    var groupMoveOrigins: [(item: Selection, start: Double, end: Double)] = []
    @Published var inspectorTab: InspectorTab = .background {
        // LF Studios layout: a panel opened from elsewhere (⌘F, a command)
        // shows in its tab.
        didSet { if inspectorTab != oldValue { propertiesTab = inspectorTab == .captions ? .captions : .video } }
    }
    /// The right panel's tab in the LF Studios layout (1.17.0).
    @Published var propertiesTab: VideoPropertiesTab = .clip
    @Published private(set) var isPlaying = false
    /// Silences the editor's player only — never the export (M, or the
    /// speaker next to the timeline scale).
    @Published var previewMuted = false {
        didSet { playback.player.isMuted = previewMuted }
    }
    @Published var timelineZoom: Double = 1 {
        didSet { refreshTimeline() }
    }
    /// The Library panel's tab.
    @Published var libraryTab: VideoLibraryTab = .media
    /// Extract Audio is writing the sound out.
    @Published var isExtractingAudio = false
    /// The timeline's pointer: Select (A) or Split (B) (1.14.0).
    @Published var timelineTool: VideoTimelineTool = .select
    /// Bumped when a timeline switch (P, N, ~, S) changes, so the toolbar
    /// redraws (they're kept in Settings).
    @Published var switchesVersion = 0
    /// The preview axis (S): the moment under the pointer the player shows
    /// while the playhead stays put (nil: the playhead's).
    var previewAxisTime: Double?
    /// The moment under the pointer while it's over the timeline's lanes
    /// (nil: anywhere else). Not published: the pointer moves a lot.
    var timelinePointerTime: Double? {
        didSet {
            let skimming = skimmerTime != nil
            if skimming != isSkimming { isSkimming = skimming }
        }
    }
    /// The pointer's height over the lanes (which track it's on).
    var timelinePointerY: CGFloat?
    /// The skimmer is showing (redraws only when it comes or goes).
    @Published private(set) var isSkimming = false
    /// 1.21.0, the skimmer (Final Cut Pro's word for the preview axis line):
    /// with the preview axis on, the pointer over the timeline and nothing
    /// playing, zooming keeps its moment in place and ⌘B / ⇧⌘B split
    /// there. nil: they use the playhead.
    var skimmerTime: Double? {
        guard Settings.videoTimelinePreviewAxis, !isPlaying, let time = timelinePointerTime else { return nil }
        return min(max(time, 0), timelineDuration)
    }
    /// Where ⌘B and ⇧⌘B act: the skimmer, else the playhead.
    var editTime: Double { skimmerTime ?? clock.time }
    /// Items above the main track copied with ⌘C.
    var clipboardLayerItems: [VideoLayerItem] = []
    // 1.21.0 (VideoEditorBasics.swift).
    /// Loop playback (⌘L): off in every editor window to start with.
    @Published var loopsPlayback = false
    /// The clip ⌘C copied, for Paste Attributes (⇧⌘V).
    var copiedAttributes: VideoCopiedAttributes?
    @Published var isPasteAttributesPresented = false
    /// Match Frame: the clip's source, shown at a frame.
    @Published var sourceViewer: VideoSourceFrame?
    /// Reveal in Library: the file to select in Library ▸ Media.
    @Published var revealedMediaPath: String?
    /// Safe zones and grid on the player (never in the export): off in
    /// every editor window to start with.
    @Published var playerGuides: Set<VideoPlayerGuide> = []
    /// The player's sound levels while it plays.
    let meters = VideoAudioMeters()
    /// The audio meters (the levels button under the player): off to start
    /// with; listening makes Play start a moment later.
    @Published var showsMeters = Settings.videoPlayerMeters {
        didSet {
            guard showsMeters != oldValue else { return }
            Settings.videoPlayerMeters = showsMeters
            playback.setMeterStorage(showsMeters ? meters.storage : nil)
            if !showsMeters { meters.stop() } else if isPlaying { meters.start() }
        }
    }
    /// Recording a voiceover (VideoVoiceover.swift).
    @Published var voiceover: VideoVoiceoverSession?
    /// Making a reversed clip or a freeze frame (VideoGeneratedMedia.swift).
    @Published var generating: VideoGenerationJob?
    /// The player's zoom: 1 fits it, more looks closer (it scrolls).
    @Published var previewZoom: CGFloat = 1
    /// Full-screen preview: only the player shows (Esc leaves).
    @Published var isPlayerFullScreen = false
    /// Small, Medium or Large lanes: chosen (remembered on this Mac), or
    /// the start for the window's height (`fitTrackHeight`).
    @Published private(set) var timelineTrackHeight: VideoTimelineTrackHeight = Settings.videoTimelineTrackHeight ?? .medium {
        didSet {
            VideoTimelineMetrics.rowScale = timelineTrackHeight.scale
            refreshTimeline()
        }
    }

    /// Track height in the timeline's menu: remembered from now on.
    func chooseTrackHeight(_ height: VideoTimelineTrackHeight) {
        Settings.videoTimelineTrackHeight = height
        timelineTrackHeight = height
    }

    /// Until one is chosen, the track height suits the window: Small when
    /// it's short (VideoEditorLayout).
    func fitTrackHeight(windowHeight: CGFloat) {
        guard Settings.videoTimelineTrackHeight == nil, windowHeight > 0 else { return }
        let fitting = VideoEditorLayout.defaultTrackHeight(windowHeight: windowHeight)
        if fitting != timelineTrackHeight { timelineTrackHeight = fitting }
    }
    /// Width of the timeline's lanes on screen (the surface keeps it up to
    /// date) — how far it can zoom depends on it.
    var timelineViewportWidth: CGFloat = 1000
    /// Where the next timeline zoom stays put: a moment and where it sits
    /// in the visible strip (nil: the playhead, wherever it is).
    var pendingZoomAnchor: (time: Double, viewportX: CGFloat)?
    @Published var isCommandPalettePresented = false
    @Published var isExportPresented = false {
        // The export window starts from the project's settings (1.16.0).
        didSet { if isExportPresented, !oldValue { applyProjectSettingsToExport() } }
    }
    /// Project settings (VideoProjectSettings.swift): click the name.
    @Published var isProjectSettingsPresented = false
    /// Tracks with their keyframe curve lane open, and the setting each
    /// shows (LF Studios layout; this window only, not the project).
    @Published var curveLanes: [UUID: VideoKeyProperty] = [:] {
        didSet { if curveLanes != oldValue { refreshTimeline() } }
    }
    /// The compound clip open in its own timeline (VideoCompounds.swift).
    @Published var openCompound: UUID? {
        didSet { if openCompound != oldValue { refreshTimeline() } }
    }
    /// Remove ums' list, while it's open (VideoFillerReview.swift).
    @Published var fillerReview: VideoFillerReview?
    /// ▶ in that list: stops after the um.
    var fillerPreview: Task<Void, Never>?
    /// Creative Handoff's dialog, and the handoff being written.
    @Published var isHandoffPresented = false
    /// "Find private info" (VideoPrivacyPanel.swift): the dialog, and its
    /// scan, which carries on while it's closed.
    @Published var isPrivacyPresented = false
    let privacyJob = VideoPrivacyJob()
    @Published var handoffJob: VideoHandoffJob?
    /// Opened for a handoff: the dialog shows once the video has loaded.
    var handoffWhenReady = false
    @Published var isShortcutsPresented = false
    @Published var exportSettings = VideoExportSettings.fromSettings
    @Published var exportPhase: ExportPhase = .idle
    @Published private(set) var thumbnails: [VideoTimelineThumbnail] = [] {
        didSet { refreshTimeline() }
    }
    /// Each sound track of the recording on its own (1.18.0: the main
    /// track's sound rows), by track index.
    @Published var soundWaveforms: [Int: VideoWaveform] = [:] {
        didSet { refreshTimeline() }
    }
    /// The sound of videos above the main track, by file path.
    @Published var layerSoundWaveforms: [String: VideoWaveform] = [:] {
        didSet { refreshTimeline() }
    }
    @Published private(set) var waveform: VideoWaveform? {
        didSet { refreshTimeline() }
    }
    @Published var notice: VideoEditorNotice?
    /// The last message, kept for the status strip (LF Studios layout).
    @Published var lastNotice: VideoEditorNotice?
    /// Motion tracking: the box being picked, or the run (VideoMotionTracking.swift).
    @Published var motionTracking: VideoMotionTrackingState?
    /// Starred Library items (VideoLibraryItems.swift).
    @Published var libraryFavourites: [String] = Settings.videoLibraryFavourites
    /// Keyboard Shortcuts ▸ Customize: the command waiting for its new key.
    @Published var recordingShortcut: VideoEditCommand?
    /// Proxies being made, and whether the editor plays them (VideoProxies.swift).
    @Published var proxyJob: VideoProxyJob?
    /// The export window's name and folder (VideoExportDestination.swift).
    @Published var exportNameEdited: String?
    @Published var exportFolderPath = Settings.videoExportFolder
    @Published var usesProxies = Settings.videoEditWithProxies
    let proxyCancelFlag = VideoAtomicFlag()
    let trackingCancelFlag = VideoAtomicFlag()
    @Published var canUndo = false
    @Published var canRedo = false
    @Published private(set) var restoredDraft = false
    /// While a clip edge is dragged the preview shows this SOURCE moment.
    @Published var trimPeekSourceTime: Double?
    /// While trimming, the timeline keeps its scale so the edge stays under
    /// the pointer instead of the whole strip re-fitting mid-drag.
    @Published var layoutDurationLock: Double? {
        didSet { refreshTimeline() }
    }
    /// Crop mode: the preview shows the whole recording with a crop frame.
    @Published var isCropping = false
    /// The phone overlay over a vertical preview (nil: off). The preview's
    /// alone: never saved, never exported (VideoPhoneOverlay.swift).
    @Published var phoneOverlay: VideoPhoneLayout?
    var cropBeforeEditing: VideoCropRect?
    var projectBeforeCrop: VideoDemoProject?
    var undoDepthBeforeCrop = 0
    /// Bumped to put the cursor in the selected text annotation's field
    /// (double-click the text on the preview).
    @Published var textEditRequest = 0
    /// ⌘F: the transcript takes focus with its find bar open (cleared once
    /// it has).
    @Published var wantsTranscriptFind = false
    @Published var cropAspect: VideoCropAspect = .free
    /// Caption generation in progress or failed (nil when idle).
    @Published var captionJob: VideoCaptionJob?
    @Published var captionLanguage: String = Settings.videoCaptionLanguage {
        didSet { Settings.videoCaptionLanguage = captionLanguage }
    }
    @Published var captionLanguages: [VideoCaptionTranscriber.Language] = []
    var captionTask: Task<Void, Never>?
    var captionToken: UUID?
    /// Running work that quitting has to ask about (each export registers
    /// itself with the queue, VideoExportJobs.swift).
    var captionQuitToken: AppTermination.Token?
    var voiceQuitToken: AppTermination.Token?

    let clock = VideoDemoPlaybackClock()
    let timelineState = VideoTimelineState()
    private var timelineSignature: TimelineSignature?
    let playback = VideoPlaybackController()
    /// Music, click sound, added recordings… (VideoEditorMedia.swift).
    let media = VideoEditorMedia()
    lazy var previewRenderer = VideoPreviewRenderer(model: self)
    let recording: VideoDemoRecordingMetadata?
    /// The project file (`.lfs`, or an older `.lfsp`/`.lfstudios`) this edit was opened from or saved to
    /// (VideoProjectFiles.swift); nil: just the recording's own edit.
    @Published var projectFileURL: URL?
    @Published var projectMediaMode: VideoProjectDocument.MediaMode?
    /// A folder project: what made the folder. A recording's own folder is
    /// kept up to date as the edit changes; any other only on Save.
    @Published var projectFolder: VideoProjectDocument.FolderInfo?
    @Published var isSavingProject = false
    let sourceBookmark: Data?
    let artwork: VideoCursorArtwork
    private(set) var plan: VideoRenderPlan
    private(set) var segments: [VideoDemoTimelineSegment] = [] {
        didSet { segmentsBySource = segments.sorted { $0.clip.sourceStart < $1.clip.sourceStart } }
    }
    /// The clips in recording order, for binary searches ("is this moment
    /// still in the video, and where?") on long, heavily cut takes.
    private(set) var segmentsBySource: [VideoDemoTimelineSegment] = []

    var undoStack: [UndoStep] = []
    var redoStack: [UndoStep] = []
    var lastCoalesceKey: String?
    var lastMutation = Date.distantPast
    var autosaveWork: DispatchWorkItem?
    /// The last write of a recording's folder (one at a time, in order).
    var recordingFolderWrite: Task<Void, Never>?
    /// The edit as last written there: an autosave with nothing new writes nothing.
    var recordingFolderWritten: VideoDemoProject?
    var noticeWork: DispatchWorkItem?
    private var cursorTrackCache: (key: CursorTrackKey, track: VideoCursorTrack?)?
    private var cameraTrackCache: (key: CameraTrackKey, track: VideoCameraTrack)?
    private var reframeCache: (key: CameraTrackKey, fraction: CGFloat, followsZooms: Bool, reframe: VideoReframe)?
    private var transcriptCache: (captions: [VideoCaptionLine], language: String?, words: [VideoTranscriptWord])?
    /// Dropped whenever the pointer path, clicks, shortcuts, or recordings
    /// change (or an added recording's own data arrives).
    var activityCache: (key: [Int], times: [Double])?

    /// When something happens on screen (pointer moves, clicks, shortcuts,
    /// typing and scrolling when the recording saw the screen change).
    var activityTimes: [Double] {
        let screen = screenActivityOnAxis
        let key = [project.cursorSamples.count, project.clickEvents.count, project.keystrokes.count, screen?.count ?? -1]
        if let cache = activityCache, cache.key == key { return cache.times }
        let times = VideoTranscript.activityTimes(cursor: project.cursorSamples, clicks: project.clickEvents, keystrokes: project.keystrokes, screen: screen)
        activityCache = (key, times)
        return times
    }

    /// Whether the recording knows when its screen changed (older ones
    /// only have the pointer, clicks, and shortcuts to go by).
    var seesScreenChanges: Bool { recording?.screenActivity != nil }

    /// Every spoken word (from the captions), in time order.
    var transcriptWords: [VideoTranscriptWord] {
        // Transcripts from before the language was saved: the language
        // chosen for captions, else the Mac's own.
        let language = project.transcriptLanguage ?? (captionLanguage.isEmpty ? Locale.current.identifier(.bcp47) : captionLanguage)
        if let cache = transcriptCache, cache.captions == project.captions, cache.language == language { return cache.words }
        let words = VideoTranscript.words(from: project.captions, language: language)
        transcriptCache = (project.captions, language, words)
        return words
    }
    var shuttleRate: Float = 1
    private var didLoad = false
    /// A clip edge is being dragged: the player waits for the drag to end.
    var holdsPlayerRebuild = false
    /// The playhead is being dragged.
    var isScrubbing = false
    private nonisolated(unsafe) var terminationObserver: NSObjectProtocol?

    /// Everything the camera path depends on — captions, shortcuts,
    /// annotations, and most style changes leave it alone.
    /// The text cursor's path (it never changes after loading).
    private var typingTrackCache: (samples: Int, track: VideoTypingTrack?)?
    /// The bubble's face-following crop, rebuilt when its inputs change.
    var faceCropCache: (key: String, path: VideoFaceCropPath?)?
    /// "Keep face centered" analyzing: how far (0…1); nil when not.
    @Published var faceAnalysisProgress: Double?
    var faceAnalysisTask: Task<Void, Never>?
    /// "Auto adjust" reading camera frames.
    @Published var isAutoAdjustingColor = false

    private struct CameraTrackKey: Equatable {
        let regions: [VideoZoomRegion]
        let timings: [VideoPlaybackController.EditStructure.Timing]
        let speed: VideoZoomSpeed
        let stage: CGRect
        let crop: VideoCropRect
        let cursorTrack: ObjectIdentifier?
        let textCursor: Int
    }

    private struct TimelineSignature: Equatable {
        let segments: [VideoDemoTimelineSegment]
        let zooms: [VideoZoomRegion]
        let overlays: [VideoDemoOverlayEffect]
        let clicks: [VideoDemoClickEvent]
        let captions: [VideoCaptionLine]
        let keystrokes: [VideoKeystrokeEvent]
        let keystrokesVisible: Bool
        let cameraLayouts: [VideoCameraLayoutRegion]
        let selection: Selection
        let extraSelection: [Selection]
        let zoom: Double
        let lock: Double?
        let thumbnails: Int
        let waveform: Int
        let sourceSize: CGSize
        let extras: VideoTimelineExtrasSignature
        let tracks: [String: VideoTrackState]
        let recordingMuted: Bool
        let trackScale: CGFloat
        let openCompound: UUID?
        let curveLanes: [UUID: VideoKeyProperty]
        let sound: VideoTimelineSoundRows
        let soundWaves: Int
    }

    /// Bumps the timeline's revision when anything it draws changed.
    func refreshTimeline() {
        let signature = TimelineSignature(
            segments: segments,
            zooms: project.zoomRegions,
            overlays: project.overlayEffects,
            clicks: project.clickEvents,
            captions: project.captions,
            keystrokes: project.keystrokes,
            keystrokesVisible: project.keystrokeStyle.visible,
            cameraLayouts: hasWebcamFootage ? project.cameraLayouts : [],
            selection: selection,
            extraSelection: extraSelection,
            zoom: timelineZoom,
            lock: layoutDurationLock,
            thumbnails: thumbnails.count,
            waveform: waveform?.peaks.count ?? -1,
            sourceSize: project.sourceSize,
            extras: timelineExtrasSignature,
            tracks: project.trackStates,
            recordingMuted: project.audio.muted,
            trackScale: VideoTimelineMetrics.rowScale,
            openCompound: openCompound,
            curveLanes: curveLanes,
            sound: timelineSoundRows,
            soundWaves: soundWaveforms.count + layerSoundWaveforms.count
        )
        guard signature != timelineSignature else { return }
        timelineSignature = signature
        timelineState.bump()
    }

    private struct CursorTrackKey: Equatable {
        let sampleCount: Int
        let firstSample: Double
        let lastSample: Double
        let clicks: [VideoDemoClickEvent]
        let smoothing: VideoCursorSettings.Smoothing
        let hideWhenIdle: Bool
        let tidyEnding: Bool
        let crop: VideoCropRect
        let duration: Double
        var sources: [VideoProjectSource] = []
    }

    init(videoURL: URL) {
        VideoTimelineMetrics.rowScale = (Settings.videoTimelineTrackHeight ?? .medium).scale
        // Opened from where it is now: its data points here (VideoDataCleanup).
        let recording = VideoDemoSidecarStore.load(for: videoURL).map { VideoDemoSidecarStore.recordLocation(of: $0, for: videoURL) }
        self.recording = recording
        sourceBookmark = try? videoURL.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        artwork = VideoCursorArtwork(metadata: recording)
        // A new recording opens plain; a draft (loaded next) keeps its look.
        var project = VideoDemoProject.fresh(sourceURL: videoURL)
        if let recording {
            project.apply(metadata: recording)
        }
        self.project = project
        plan = VideoRenderPlan(project: project, sourceDuration: 0, artwork: artwork, pointPixelScale: recording?.pointPixelScale, cursorTrack: nil, camera: .identity)
        if showsMeters { playback.setMeterStorage(meters.storage) }

        playback.onTick = { [weak self] time in
            guard let self else { return }
            // While paused and scrubbing, the player reports each finished
            // seek — an older spot than the playhead already shows.
            guard self.isPlaying || !self.playback.isSeeking else { return }
            // The preview axis shows another moment; the playhead stays.
            guard self.isPlaying || self.previewAxisTime == nil else { return }
            if self.clock.time != time { self.clock.time = time }
            if self.isPlaying { self.previewRenderer.invalidate() }
            self.loopIfNeeded(at: time)
        }
        playback.onPlayedToEnd = { [weak self] in self?.loopAtVideoEnd() }
        playback.onPlayingChanged = { [weak self] playing in
            guard let self else { return }
            self.isPlaying = playing
            if !playing { self.shuttleRate = 1 }
            if playing, self.showsMeters { self.meters.start() } else { self.meters.stop() }
            self.updatePreviewQuality()
            self.previewRenderer.invalidate()
        }
        // Quitting skips the window's close: the last edits (autosave waits
        // a moment) are written now.
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveDraftNow() }
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    // MARK: Loading

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        do {
            let source = try await playback.load(url: project.sourceURL)
            // Edit with proxies: the picture from the proxy, when this Mac has one.
            if usesProxies { playback.replaceSource(await VideoProxies.swapping(source), original: source) }
            sourceDuration = source.duration
            sourceFrameRate = source.frameRate
            hasAudio = !source.audio.isEmpty
            audioKinds = VideoAudioKind.resolve(recorded: recording?.audioTracks, channelCounts: source.audioChannelCounts)
            playback.setAudioSources(VideoAudioSource.sources(from: source, kinds: audioKinds))

            var loaded = project
            // The store only hands back this file's own draft (moved or
            // renamed files included; copies and replaced files excluded).
            if let draft = VideoDemoDraftStore.load(for: project.sourceURL) {
                loaded = draft.project
                // The file may have moved since: this is where it is now.
                loaded.sourcePath = project.sourcePath
                // Drafts leave the (read-only) pointer path in the sidecar.
                if loaded.cursorSamples.isEmpty, let recording {
                    loaded.cursorSamples = recording.cursorSamples
                }
                restoredDraft = true
            }
            loaded.sourceWidth = Double(source.size.width)
            loaded.sourceHeight = Double(source.size.height)
            if !restoredDraft, loaded.sourceHeight > loaded.sourceWidth * 1.1,
               loaded.aspectPreset == .widescreen || loaded.aspectPreset == .classic {
                // A tall recording in a wide frame would be a sliver.
                loaded.aspectPreset = .source
            }
            // Added recordings extend the source axis past this one.
            let total = loaded.sourceAxisDuration ?? source.duration
            sourceDuration = total
            if loaded.trimEnd <= 0 || loaded.trimEnd > total {
                loaded.trimEnd = total
            }
            loaded.ensureTimeline(totalDuration: total)

            // A fresh recording opens plain: nothing is applied by itself
            // (Auto-zoom on clicks is the Zoom panel's switch).
            if restoredDraft { restoreKeptHistory(for: loaded) }
            // Imported camera footage first, else the recorded camera.
            loaded.relocateImportedCamera()
            if let webcam = loaded.activeCamera(recorded: webcamRecording), loaded.importedCamera.map({ $0.resolved() != nil }) ?? true,
               let camera = await VideoCameraSource.load(webcam) {
                playback.setCamera(camera)
                hasWebcamFootage = true
            }
            project = loaded
            if hasWebcamFootage {
                playback.cameraStore.setFindsPerson(project.webcam.needsPersonMask)
            }
            isReady = true
            if handoffWhenReady {
                handoffWhenReady = false
                showCreativeHandoff()
            }
            playback.apply(segments: segments, audio: playbackAudio, keepSourceTime: nil, extras: editExtras)
            playback.seek(to: 0, fast: false)
            saveDraftNow()
            if restoredDraft {
                showNotice(L("Picked up where you left off"), symbol: "clock.arrow.circlepath")
            }
            // A font this project uses isn't here: the built-in one stands in
            // (VideoFonts.swift); the font pickers say which.
            if let missing = missingFontFamilies.first {
                showNotice(L("“\(missing)” isn't on this Mac — using the built-in font"), symbol: "exclamationmark.triangle.fill", duration: 5)
            }
            Task { await loadThumbnails() }
            Task {
                await loadWaveform()
                await loadSoundWaveforms()
            }
            if project.audio.voiceRecipe != nil {
                enhanceVoiceChanged()
            }
            Task { await prepareMedia() }
        } catch {
            loadError = error.localizedDescription
            loadFailure = VideoLoadFailure.classify(error, url: project.sourceURL)
        }
    }

    // MARK: Project changes

    private func projectDidChange(from old: VideoDemoProject) {
        // Only Tacks (1.19.1) or the AI chat (1.20.0): saved, nothing to
        // play differently.
        if old.tacks != project.tacks || old.aiChat != project.aiChat {
            if project.keepingNotes(of: old) == old {
                if isReady { scheduleAutosave() }
                return
            }
        }
        // Only the media bin (a name, a folder, an import): nothing to
        // play differently, just saved.
        if old.mediaBin != project.mediaBin {
            var unbinned = project
            unbinned.mediaBin = old.mediaBin
            if unbinned == old {
                if isReady { scheduleAutosave() }
                return
            }
        }
        // Added recordings set the source axis's length (right away, so no
        // edit ever lays clips out against the old one).
        if let axis = project.sourceAxisDuration, abs(axis - sourceDuration) > 0.0005 {
            sourceDuration = axis
        } else if project.sources.isEmpty, !old.sources.isEmpty, let primary = playback.source?.duration {
            sourceDuration = primary
        }
        let oldSegments = segments
        segments = project.timelineSegments(totalDuration: sourceDuration)
        refreshTimeline()
        // What Shorten Pauses and Speed Up Idle read (cheap when unchanged:
        // the arrays share storage).
        if old.cursorSamples != project.cursorSamples || old.clickEvents != project.clickEvents
            || old.keystrokes != project.keystrokes || old.sources != project.sources {
            activityCache = nil
        }
        if isReady, old.audio.voiceRecipe != project.audio.voiceRecipe {
            enhanceVoiceChanged()
        }
        if isReady, hasWebcamFootage, old.webcam.needsPersonMask != project.webcam.needsPersonMask {
            if playback.cameraStore.setFindsPerson(project.webcam.needsPersonMask) {
                playback.refreshCurrentFrame()
            }
        }
        // Cropping previews the raw recording: the plan (pointer path,
        // camera) is rebuilt once the crop is done, not on every drag.
        if !isCropping { rebuildPlan() }
        validateSelection(keepingRange: true)
        mediaDidChange(from: old)
        if old.importedCamera != project.importedCamera { cameraFootageDidChange(from: old.importedCamera) }
        if isReady {
            // A clip edge being dragged rebuilds the player once, at the end
            // (the preview shows the edge from a still meanwhile).
            if !holdsPlayerRebuild {
                // Stay on the same moment of the recording — read through the
                // cut list it was on (a speed change or cut before the playhead
                // moves that moment along the timeline).
                let keepSource = VideoDemoProject.sourceTime(forTimelineTime: clock.time, segments: oldSegments.isEmpty ? segments : oldSegments)
                // The playhead follows that moment to its new place on the
                // timeline (paused, the player won't report the move).
                if let moved = playback.apply(segments: segments, audio: playbackAudio, keepSourceTime: keepSource, extras: editExtras), !isPlaying {
                    clock.time = moved
                }
            }
            scheduleAutosave()
        }
        previewRenderer.invalidate()
    }

    /// After cropping: bring the plan up to date in one go.
    func refreshPlan() {
        rebuildPlan()
        previewRenderer.invalidate()
    }

    /// Steps back to an earlier project as if the edits since `depth` undo
    /// steps never happened (a cancelled crop): no extra undo step.
    func discardEdits(restoring snapshot: VideoDemoProject, undoDepth depth: Int) {
        undoStack = Array(undoStack.prefix(depth))
        redoStack.removeAll()
        lastCoalesceKey = nil
        project = snapshot.keepingNotes(of: project)
        canUndo = !undoStack.isEmpty
        canRedo = false
    }

    var undoDepth: Int { undoStack.count }

    /// What an agent's dry run puts back (VideoAgent.swift, 1.19.0).
    struct TryingSnapshot {
        let project: VideoDemoProject
        let undo: [UndoStep]
        let redo: [UndoStep]
        let coalesce: String?
        let lastMutation: Date
        let selection: Selection
        let extra: [Selection]
        let time: Double
        let tool: VideoTimelineTool
        let notice: VideoEditorNotice?
        let lastNotice: VideoEditorNotice?
        let canUndo: Bool
        let canRedo: Bool
    }

    func snapshotForTrying() -> TryingSnapshot {
        TryingSnapshot(project: project, undo: undoStack, redo: redoStack, coalesce: lastCoalesceKey, lastMutation: lastMutation, selection: selection,
                       extra: extraSelection, time: clock.time, tool: timelineTool, notice: notice, lastNotice: lastNotice, canUndo: canUndo, canRedo: canRedo)
    }

    func restore(_ saved: TryingSnapshot) {
        if project != saved.project { project = saved.project }
        undoStack = saved.undo
        redoStack = saved.redo
        lastCoalesceKey = saved.coalesce
        lastMutation = saved.lastMutation
        if selection != saved.selection { selection = saved.selection }
        if extraSelection != saved.extra { extraSelection = saved.extra }
        if timelineTool != saved.tool { timelineTool = saved.tool }
        notice = saved.notice
        lastNotice = saved.lastNotice
        canUndo = saved.canUndo
        canRedo = saved.canRedo
        if abs(clock.time - saved.time) > 0.000_1 { seek(to: saved.time) }
    }

    /// The preview again after opening or closing a compound.
    func rebuildPlanForCompound() {
        rebuildPlan()
        refreshPlayback()
    }

    private func rebuildPlan() {
        // A compound that's gone (undone, broken apart) isn't open any more.
        if let open = openCompound, self.project.compound(open) == nil { openCompound = nil }
        // As it plays: hidden tracks left out (the timeline's headers).
        let project = self.project.forOutput()
        let key = CursorTrackKey(
            sampleCount: project.cursorSamples.count,
            firstSample: project.cursorSamples.first?.time ?? 0,
            lastSample: project.cursorSamples.last?.time ?? 0,
            clicks: project.clickEvents,
            smoothing: project.cursor.smoothing,
            hideWhenIdle: project.cursor.hideWhenIdle,
            tidyEnding: project.cursor.tidyEnding,
            crop: project.crop.normalized,
            duration: sourceDuration,
            sources: project.sources
        )
        let cursorTrack: VideoCursorTrack?
        if let cache = cursorTrackCache, cache.key == key {
            cursorTrack = cache.track
        } else {
            // Several recordings: each one's own pointer path, joined up.
            cursorTrack = VideoSourcesPointer.cursorTrack(project: project, duration: sourceDuration)
            cursorTrackCache = (key, cursorTrack)
        }
        let typingTrack: VideoTypingTrack?
        if let cache = typingTrackCache, cache.samples == project.textCursor.count {
            typingTrack = cache.track
        } else {
            typingTrack = VideoTypingTrack(samples: project.textCursor)
            typingTrackCache = (project.textCursor.count, typingTrack)
        }
        // Reframing renders the recording's own shape, then crops a moving
        // window: the camera path is built for that landscape scene.
        var layoutProject = project.reframeActive ? project.reframeScene() : project
        // An open compound shows its clips as they are (without its move,
        // size and turn), so their handles line up (1.16.0).
        if let open = openCompound { layoutProject.compounds = layoutProject.compounds?.filter { $0.id != open } }
        let canvas = layoutProject.canvasSize()
        let stage = layoutProject.stageRect(in: canvas)
        let normalizedStage = CGRect(x: stage.minX / canvas.width, y: stage.minY / canvas.height, width: stage.width / canvas.width, height: stage.height / canvas.height)
        let cameraKey = CameraTrackKey(
            regions: project.zoomRegions,
            timings: segments.map { .init(start: $0.clip.sourceStart, end: $0.clip.sourceEnd, speed: $0.clip.normalizedSpeed) },
            speed: project.zoomSpeed,
            stage: normalizedStage,
            crop: project.crop.normalized,
            cursorTrack: cursorTrack.map(ObjectIdentifier.init),
            textCursor: project.textCursor.count
        )
        let camera: VideoCameraTrack
        if let cache = cameraTrackCache, cache.key == cameraKey {
            camera = cache.track
        } else {
            camera = VideoCameraTrack.build(
                regions: project.zoomRegions,
                segments: segments,
                timelineDuration: project.outputDuration(segments: segments),
                speed: project.zoomSpeed,
                stage: normalizedStage,
                crop: project.crop.normalized,
                cursor: cursorTrack.map { track in { track.visiblePosition(at: $0) } },
                typing: typingTrack.map { track in { track.position(at: $0) } }
            )
            cameraTrackCache = (cameraKey, camera)
        }
        let outputCanvas = project.canvasSize()
        var reframe: VideoReframe?
        if project.reframeActive,
           let fraction = VideoReframe.windowFraction(outputAspect: outputCanvas.width / max(outputCanvas.height, 1), sceneAspect: canvas.width / max(canvas.height, 1)) {
            if let cache = reframeCache, cache.key == cameraKey, cache.fraction == fraction, cache.followsZooms == project.reframeFollowsZooms {
                reframe = cache.reframe
            } else {
                let built = VideoReframe.build(
                    windowFraction: fraction,
                    camera: camera,
                    cursorTrack: cursorTrack,
                    segments: segments,
                    canvas: canvas,
                    stage: stage,
                    crop: project.crop.normalized,
                    duration: project.outputDuration(segments: segments),
                    zoomSubject: project.zoomSubject(cursor: cursorTrack.map { track in { track.visiblePosition(at: $0) } }, typing: typingTrack.map { track in { track.position(at: $0) } })
                )
                reframeCache = (cameraKey, fraction, project.reframeFollowsZooms, built)
                reframe = built
            }
        }
        plan = VideoRenderPlan(
            project: layoutProject,
            sourceDuration: sourceDuration,
            artwork: planArtwork,
            pointPixelScale: recording?.pointPixelScale ?? project.sources.compactMap(\.pointPixelScale).first,
            cursorTrack: cursorTrack,
            camera: camera,
            hasWebcam: hasWebcamFootage,
            outputCanvasSize: outputCanvas,
            reframe: reframe,
            typingTrack: typingTrack,
            faceCrop: faceCropPath()
        )
        if !plan.transitions.isEmpty { prefetchHeldFrames() }
    }

    // MARK: Thumbnails & waveform

    /// Added or removed recordings change the source axis (and may bring
    /// sound or camera footage of their own).
    func applySourceDuration(_ duration: Double, hasAudio: Bool, hasCamera: Bool? = nil) {
        if abs(sourceDuration - duration) > 0.0005 {
            sourceDuration = duration
            segments = project.timelineSegments(totalDuration: duration)
            refreshTimeline()
        }
        if self.hasAudio != hasAudio { self.hasAudio = hasAudio }
        if let hasCamera, hasWebcamFootage != hasCamera {
            hasWebcamFootage = hasCamera
            // An added recording's camera gets the same background looks.
            if hasCamera { playback.cameraStore.setFindsPerson(project.webcam.needsPersonMask) }
        }
    }

    /// Filmstrip and waveform across every recording.
    func applyTimelineMedia(thumbnails: [VideoTimelineThumbnail], waveform: VideoWaveform?) {
        self.thumbnails = thumbnails
        if let waveform { self.waveform = waveform }
    }

    private func loadThumbnails() async {
        let url = project.sourceURL
        let duration = sourceDuration
        // Several recordings load their filmstrip together (VideoEditorMedia).
        guard duration > 0, !project.hasAppendedSources else { return }
        let count = min(max(Int(duration / 1.2), 12), 160)
        // Kept from last time (VideoPerformance.swift).
        if let cached = await Task.detached(priority: .userInitiated, operation: { VideoTimelineCache.thumbnails(for: url, count: count) }).value {
            thumbnails = cached
            return
        }
        let times = (0..<count).map { duration * (Double($0) + 0.5) / Double(count) }
        let images = await Task.detached(priority: .utility) { () -> [VideoTimelineThumbnail] in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 200)
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 2)
            generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
            let made = await VideoTimelineThumbnail.generate(with: generator, at: times)
            VideoTimelineCache.save(made, for: url, count: count)
            return made
        }.value
        thumbnails = images
    }

    private func loadWaveform() async {
        let url = project.sourceURL
        guard !project.hasAppendedSources else { return }
        if let cached = await Task.detached(priority: .userInitiated, operation: { VideoTimelineCache.waveform(for: url) }).value {
            waveform = VideoWaveform(peaks: cached)
            return
        }
        let peaks = await Task.detached(priority: .utility) { () -> [Float]? in
            let asset = AVURLAsset(url: url)
            guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
                  let reader = try? AVAssetReader(asset: asset) else { return nil }
            let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 8_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            guard reader.startReading() else { return nil }
            let samplesPerBucket = Int(8_000 / VideoWaveform.bucketsPerSecond)
            var peaks: [Float] = []
            var current: Float = 0
            var counted = 0
            output.forEachSampleBuffer { buffer in
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { return false }
                var length = 0
                var pointer: UnsafeMutablePointer<Int8>?
                guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                      let pointer else { return true }
                let count = length / MemoryLayout<Float>.size
                pointer.withMemoryRebound(to: Float.self, capacity: count) { floats in
                    for index in 0..<count {
                        current = max(current, abs(floats[index]))
                        counted += 1
                        if counted >= samplesPerBucket {
                            peaks.append(current)
                            current = 0
                            counted = 0
                        }
                    }
                }
                return true
            }
            if counted > 0 { peaks.append(current) }
            // Normalize so quiet recordings still read.
            let top = peaks.max() ?? 0
            guard top > 0.0001 else { return peaks }
            let gain = min(1 / top, 4)
            return peaks.map { min($0 * gain, 1) }
        }.value
        if let peaks {
            waveform = VideoWaveform(peaks: peaks)
            Task.detached(priority: .utility) { VideoTimelineCache.save(waveform: peaks, for: url) }
        }
    }

}
