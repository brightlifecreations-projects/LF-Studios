import AppKit
import XCTest
@testable import LFStudiosCore

/// The bigger timeline (1.11.0): the divider's sizes and minimums, a row
/// per kind of content, track heights, Hide / Mute / Lock, and projects
/// from before (VideoTimelineTracks.swift, VideoTimelineHeaders.swift).
@MainActor
final class VideoTimelineTracksTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!
    private var suiteName: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-tracks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "LFStudiosCoreTests.Tracks.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        VideoTimelineMetrics.rowScale = VideoTimelineTrackHeight.medium.scale
    }

    override func tearDown() async throws {
        if let directory {
            VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
            try? FileManager.default.removeItem(at: directory)
        }
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        VideoTimelineMetrics.rowScale = VideoTimelineTrackHeight.medium.scale
    }

    private func makeModel(seconds: Double = 10) async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: seconds, fps: 30, audioSeconds: seconds)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.isReady, model.loadError ?? "not ready")
        return model
    }

    // MARK: The divider

    func testTheTimelineStartsAtAThirdAndKeepsBothSidesUsable() {
        typealias Layout = VideoEditorLayout
        // A large window, a 13" MacBook's (1280 × 800 and 1440 × 900
        // screens, minus the title bar), and the editor's smallest.
        for height: CGFloat in [1200, 900 - 28, 800 - 28, 700] {
            let available = height - Layout.toolbarHeight
            let fraction = Layout.defaultFraction(windowHeight: height)
            let start = Layout.timelineHeight(windowHeight: height, fraction: fraction)
            XCTAssertGreaterThanOrEqual(start, Layout.minimumTimeline, "\(height)")
            XCTAssertGreaterThanOrEqual(available - start, Layout.minimumPreview, "\(height): the preview keeps room")
            if available * CGFloat(fraction) >= Layout.minimumTimeline, available - available * CGFloat(fraction) >= Layout.minimumPreview {
                XCTAssertEqual(start / available, CGFloat(fraction), accuracy: 0.01, "\(height): a third, or 40% when short")
            }
            // Dragged all the way up and all the way down: kept usable.
            let tallest = Layout.timelineHeight(windowHeight: height, fraction: 0.99)
            let shortest = Layout.timelineHeight(windowHeight: height, fraction: 0.01)
            XCTAssertEqual(tallest, max(available - Layout.minimumPreview, Layout.minimumTimeline), "\(height)")
            XCTAssertEqual(shortest, Layout.minimumTimeline, "\(height)")
            // A drag lands where the pointer put it, within those limits.
            let wanted: CGFloat = 260
            let dragged = Layout.fraction(forTimelineHeight: wanted, windowHeight: height)
            XCTAssertEqual(Layout.timelineHeight(windowHeight: height, fraction: dragged), min(max(wanted, Layout.minimumTimeline), tallest), accuracy: 1)
        }
        // On a 13" window the preview gets most of it, the timeline 40%.
        let thirteen = Layout.timelineHeight(windowHeight: 772, fraction: Layout.defaultFraction(windowHeight: 772))
        XCTAssertEqual(thirteen, (772 - Layout.toolbarHeight) * 0.40, accuracy: 1)
        XCTAssertGreaterThanOrEqual(772 - Layout.toolbarHeight - thirteen, 420)
    }

    func testTheDividerAndTrackHeightAreRememberedOnThisMac() async throws {
        XCTAssertNil(Settings.videoTimelineFraction, "not chosen: it follows the window")
        XCTAssertNil(Settings.videoTimelineTrackHeight)
        Settings.videoTimelineFraction = 0.5
        XCTAssertEqual(Settings.videoTimelineFraction, 0.5)
        let model = try await makeModel()
        model.chooseTrackHeight(.large)
        XCTAssertEqual(Settings.videoTimelineTrackHeight, .large)
        XCTAssertEqual(VideoTimelineMetrics.rowScale, VideoTimelineTrackHeight.large.scale)
        XCTAssertEqual(VideoEditorModel(videoURL: model.project.sourceURL).timelineTrackHeight, .large, "the next editor too")
        // Chosen wins over the window's height.
        model.fitTrackHeight(windowHeight: 700)
        XCTAssertEqual(model.timelineTrackHeight, .large)
        XCTAssertEqual(VideoEditorLayout.fraction(chosen: Settings.videoTimelineFraction, windowHeight: 700), 0.5)
        // The divider's double-click forgets it: back to the window's start.
        Settings.videoTimelineFraction = nil
        XCTAssertEqual(VideoEditorLayout.fraction(chosen: Settings.videoTimelineFraction, windowHeight: 700), VideoEditorLayout.compactTimelineFraction)
    }

    // MARK: Shorter windows

    func testShortWindowsStartWithSmallTracksAndForty() async throws {
        typealias Layout = VideoEditorLayout
        for height: CGFloat in [700, 772, 872, 999] {
            XCTAssertEqual(Layout.defaultTrackHeight(windowHeight: height), .small, "\(height)")
            XCTAssertEqual(Layout.defaultFraction(windowHeight: height), 0.40, "\(height)")
        }
        for height: CGFloat in [1000, 1117, 1440] {
            XCTAssertEqual(Layout.defaultTrackHeight(windowHeight: height), .medium, "\(height): today's start")
            XCTAssertEqual(Layout.defaultFraction(windowHeight: height), Layout.defaultTimelineFraction, "\(height)")
        }
        let model = try await makeModel()
        XCTAssertEqual(model.timelineTrackHeight, .medium)
        model.fitTrackHeight(windowHeight: 772)
        XCTAssertEqual(model.timelineTrackHeight, .small, "a 13\" window")
        XCTAssertNil(Settings.videoTimelineTrackHeight, "only a start, not remembered")
        model.fitTrackHeight(windowHeight: 1200)
        XCTAssertEqual(model.timelineTrackHeight, .medium, "made taller: back to Medium")
    }

    /// On a short window, Zooms, Video clips (with click marks), Camera and
    /// Captions show without scrolling, all of them with something on.
    func testShortWindowsShowTheFirstFourTracksWithoutScrolling() async throws {
        let model = try await makeModel()
        model.mutate { project in
            project.zoomRegions = [VideoZoomRegion(start: 1, end: 3, scale: 2, followsCursor: false)]
            project.clickEvents = [VideoDemoClickEvent(time: 1, x: 0.5, y: 0.5, button: .left)]
            project.cameraLayouts = [VideoCameraLayoutRegion(start: 2, end: 4, layout: .fullscreen)]
            project.captions = [VideoCaptionLine(start: 1, end: 2, text: "Hi")]
            project.keystrokes = [VideoKeystrokeEvent(time: 2, keys: ["⌘", "S"])]
        }
        // 740 pt and up: a 13" MacBook's window and any short one.
        for height: CGFloat in [740, 772, 800, 872, 950, 999] {
            model.fitTrackHeight(windowHeight: height)
            let timeline = VideoEditorLayout.timelineHeight(windowHeight: height, fraction: VideoEditorLayout.defaultFraction(windowHeight: height))
            // Under the timeline's toolbar and the ruler.
            let lanes = timeline - 44 - 1 - VideoTimelineMetrics.rulerHeight - 1
            let rows = VideoTimelineRowLayout(project: model.project, hasCamera: true)
            let captions = try XCTUnwrap(rows.row(.captions))
            XCTAssertFalse(captions.isEmpty)
            XCTAssertLessThanOrEqual(captions.top + captions.height, lanes, "\(height): Captions ends at \(captions.top + captions.height), the lanes show \(lanes)")
            XCTAssertGreaterThanOrEqual(height - VideoEditorLayout.toolbarHeight - timeline, VideoEditorLayout.minimumPreview, "\(height): the preview keeps room")
        }
    }

    // MARK: Rows

    func testEveryKindOfContentHasItsRowInOrder() async throws {
        let model = try await makeModel()
        var layout = VideoTimelineRowLayout(project: model.project, hasCamera: true)
        XCTAssertEqual(layout.rows.map(\.track), [.zooms, .clips, .camera, .captions, .keys, .annotations, .music])
        // Empty: thin rows with a hint; zooms and clips are always open.
        for row in layout.rows where row.track != .zooms && row.track != .clips {
            XCTAssertTrue(row.isEmpty, "\(row.track)")
            XCTAssertEqual(row.height, VideoTimelineRowLayout.thinHeight)
            XCTAssertFalse(VideoTimelineRowLayout.hint(row.track).isEmpty, "\(row.track) says how to add something")
        }
        XCTAssertFalse(try XCTUnwrap(layout.row(.zooms)).isEmpty)
        XCTAssertFalse(try XCTUnwrap(layout.row(.clips)).isEmpty)

        // Something of every kind.
        let sound = VideoExternalAudioTrack(path: directory.appendingPathComponent("a.wav").path, name: "Voiceover", duration: 2, at: 1)
        model.mutate { project in
            project.zoomRegions = [VideoZoomRegion(start: 1, end: 3, scale: 2, followsCursor: false)]
            project.captions = [VideoCaptionLine(start: 1, end: 2, text: "Hi")]
            project.keystrokes = [VideoKeystrokeEvent(time: 2, keys: ["⌘", "S"])]
            project.overlayEffects = [VideoDemoOverlayEffect(kind: .text, time: 1, duration: 2, text: "Note"), VideoDemoOverlayEffect(kind: .arrow, time: 1.5, duration: 2, layer: 1)]
            project.cameraLayouts = [VideoCameraLayoutRegion(start: 2, end: 4, layout: .fullscreen)]
            project.music = VideoMusicTrack(path: self.directory.appendingPathComponent("song.m4a").path, name: "Song", duration: 30)
            project.audioTracks = [sound]
        }
        layout = VideoTimelineRowLayout(project: model.project, hasCamera: true)
        XCTAssertEqual(layout.rows.map(\.track), [.zooms, .clips, .camera, .captions, .keys, .annotations, .music, .sound(sound.id)])
        for row in layout.rows {
            XCTAssertFalse(row.isEmpty, "\(row.track) shows its lanes")
            XCTAssertNotNil(layout.contentTop(row.track))
        }
        XCTAssertEqual(try XCTUnwrap(layout.row(.annotations)).height, 2 * VideoTimelineMetrics.overlayLaneHeight + VideoTimelineMetrics.overlayLaneGap + 2 * VideoTimelineRowLayout.padding, "a lane per layer")
        // Rows follow each other without overlapping.
        for (a, b) in zip(layout.rows, layout.rows.dropFirst()) {
            XCTAssertEqual(b.top, a.top + a.height + VideoTimelineRowLayout.separator, accuracy: 0.001)
        }
        XCTAssertEqual(model.project.timelineTracks.last?.title(in: model.project), "Voiceover")
    }

    func testTrackHeightScalesTheRowsAndCollapsingFoldsOne() async throws {
        let model = try await makeModel()
        model.mutate { $0.captions = [VideoCaptionLine(start: 1, end: 2, text: "Hi")] }
        var heights: [VideoTimelineTrackHeight: CGFloat] = [:]
        for size in VideoTimelineTrackHeight.allCases {
            VideoTimelineMetrics.rowScale = size.scale
            heights[size] = try XCTUnwrap(VideoTimelineRowLayout(project: model.project, hasCamera: true).row(.clips)).height
        }
        XCTAssertEqual(heights[.small], 66 + 2 * VideoTimelineRowLayout.padding, "Small is today's clip track")
        XCTAssertLessThan(heights[.small]!, heights[.medium]!)
        XCTAssertLessThan(heights[.medium]!, heights[.large]!)

        VideoTimelineMetrics.rowScale = VideoTimelineTrackHeight.medium.scale
        model.toggleTrackCollapsed(.captions)
        let collapsed = try XCTUnwrap(VideoTimelineRowLayout(project: model.project, hasCamera: true).row(.captions))
        XCTAssertTrue(collapsed.collapsed && !collapsed.showsContent)
        XCTAssertEqual(collapsed.height, VideoTimelineRowLayout.thinHeight)
        XCTAssertEqual(model.project.captions.count, 1, "folding a track changes nothing on it")
        model.undo()
        XCTAssertTrue(try XCTUnwrap(VideoTimelineRowLayout(project: model.project, hasCamera: true).row(.captions)).showsContent)
    }

    /// A new track height redraws the clips too (their height comes from
    /// the metrics; 1.11.0 kept the old height until something else changed).
    func testTheClipsRedrawForANewTrackHeight() async throws {
        let model = try await makeModel()
        let segment = try XCTUnwrap(model.segments.first)
        func clip(_ height: VideoTimelineTrackHeight) -> VideoTimelineClipView {
            VideoTimelineMetrics.rowScale = height.scale
            return VideoTimelineClipView(model: model, segment: segment, index: 0, pointsPerSecond: 100, selected: false, thumbnails: [], waveform: nil, sourceAspect: 1.6, hover: VideoTimelineHover())
        }
        XCTAssertTrue(clip(.small) == clip(.small))
        XCTAssertFalse(clip(.medium) == clip(.small), "a new track height is a change")
    }

    // MARK: Hide, Mute, Lock

    func testHideAndMuteChangeOnlyWhatPlaysAndExports() async throws {
        let model = try await makeModel()
        model.mutate { project in
            project.zoomRegions = [VideoZoomRegion(start: 1, end: 3, scale: 2, followsCursor: false)]
            project.captions = [VideoCaptionLine(start: 1, end: 2, text: "Hi")]
            project.overlayEffects = [VideoDemoOverlayEffect(kind: .text, time: 1, duration: 2, text: "Note")]
            project.music = VideoMusicTrack(path: self.directory.appendingPathComponent("song.m4a").path, name: "Song", duration: 30)
        }
        XCTAssertEqual(model.project.forOutput(), model.project, "nothing hidden: plays as it is")

        for track in [VideoTimelineTrack.zooms, .captions, .annotations, .clips, .camera] { model.toggleTrackHidden(track) }
        model.toggleTrackMuted(.music)
        model.toggleTrackMuted(.clips)
        let output = model.project.forOutput()
        XCTAssertTrue(output.zoomRegions.isEmpty)
        XCTAssertFalse(output.captionStyle.visible)
        XCTAssertTrue(output.overlayEffects.isEmpty)
        XCTAssertNil(output.music)
        XCTAssertFalse(output.webcam.visible)
        XCTAssertTrue(output.audio.muted, "the recording's own sound")
        XCTAssertTrue(output.hidesScreen)
        // The timeline keeps everything.
        XCTAssertEqual(model.project.zoomRegions.count, 1)
        XCTAssertEqual(model.project.captions.count, 1)
        XCTAssertEqual(model.project.overlayEffects.count, 1)
        XCTAssertNotNil(model.project.music)
        // The preview plays it that way too.
        XCTAssertTrue(model.plan.hidesScreen)
        XCTAssertTrue(model.plan.overlays.isEmpty)
        XCTAssertTrue(model.plan.camera.isStatic, "no zoom motion")

        // Keys' eye is Keys ▸ Show keys; a sound's speaker is its Mute.
        model.mutate { $0.keystrokeStyle.visible = true }
        model.toggleTrackHidden(.keys)
        XCTAssertFalse(model.project.keystrokeStyle.visible)
        XCTAssertNil(model.project.trackStates["keys"], "one switch, not two")

        // The export starts from the same project.
        let prepared = try await VideoDemoExporter.prepareEdit(project: model.project, recording: model.recording, settings: model.exportSettings)
        XCTAssertNil(prepared.project.music)
        XCTAssertTrue(prepared.project.zoomRegions.isEmpty)
        XCTAssertTrue(prepared.project.overlayEffects.isEmpty)
        XCTAssertTrue(prepared.project.hidesScreen)

        // Shown again: back as it was.
        for track in [VideoTimelineTrack.zooms, .captions, .annotations, .clips, .camera] { model.toggleTrackHidden(track) }
        model.toggleTrackMuted(.music)
        model.toggleTrackMuted(.clips)
        XCTAssertTrue(model.project.trackStates.isEmpty)
        XCTAssertFalse(model.plan.hidesScreen)
    }

    func testHidingTheCameraKeepsASplitRecordingsShape() {
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/split.mp4"), duration: 4, sourceSize: CGSize(width: 960, height: 1080))
        project.webcam = VideoRecordingCameraSetup.LayoutChoice.split.applied(to: project.webcam)
        project.splitVideoAspect = 16.0 / 9
        XCTAssertEqual(project.canvasSize(), CGSize(width: 1920, height: 1080))
        project.setTrackState(.camera) { $0.hidden = true }
        XCTAssertEqual(project.forOutput().canvasSize(), CGSize(width: 1920, height: 1080), "still a 16:9 video")
        XCTAssertFalse(project.forOutput().webcam.visible)
    }

    func testALockedTrackRefusesChangesUntilUnlocked() async throws {
        let model = try await makeModel()
        model.mutate { $0.captions = [VideoCaptionLine(start: 1, end: 2, text: "Hi")] }
        model.toggleTrackLocked(.clips)
        model.toggleTrackLocked(.zooms)
        model.toggleTrackLocked(.captions)
        model.toggleTrackLocked(.annotations)
        XCTAssertEqual(model.undoLabel, "Lock Track")
        let before = model.project

        model.seek(to: 4)
        model.splitAtPlayhead()
        XCTAssertEqual(model.project.timelineClips.count, before.timelineClips.count, "no split on locked clips")
        XCTAssertNil(model.addZoom(at: 5))
        model.addCaptionAtPlayhead()
        model.addOverlay(.text)
        model.selection = .caption(model.project.captions[0].id)
        model.deleteSelection()
        XCTAssertEqual(model.project.captions.count, 1, "a locked caption stays")
        XCTAssertTrue(model.project.overlayEffects.isEmpty && model.project.zoomRegions.isEmpty)
        XCTAssertEqual(model.project.captions, before.captions)
        XCTAssertEqual(model.undoLabel, "Lock Track", "nothing else became an undo step")
        XCTAssertEqual(model.notice?.message.contains("is locked"), true, "and it says why")

        model.toggleTrackLocked(.clips)
        model.splitAtPlayhead()
        XCTAssertEqual(model.project.timelineClips.count, before.timelineClips.count + 1, "unlocked: it splits")
        model.toggleTrackLocked(.captions)
        model.selection = .caption(model.project.captions[0].id)
        model.deleteSelection()
        XCTAssertTrue(model.project.captions.isEmpty)
    }

    // MARK: Projects from before

    func testOlderProjectsHaveNoTrackStatesAndWriteNone() throws {
        let project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/old.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        let data = try JSONEncoder().encode(project)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("trackStates"))
        let back = try JSONDecoder().decode(VideoDemoProject.self, from: data)
        XCTAssertTrue(back.trackStates.isEmpty)
        XCTAssertEqual(back.forOutput(), back)

        var changed = project
        changed.setTrackState(.zooms) { $0.locked = true }
        changed.setTrackState(.music) { $0.muted = true; $0.collapsed = true }
        let reopened = try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(changed))
        XCTAssertTrue(reopened.isTrackLocked(.zooms))
        XCTAssertTrue(reopened.trackState(.music).muted && reopened.trackState(.music).collapsed)
    }
}
