import AVFoundation
import KeyboardShortcuts
import XCTest
@testable import LFStudiosCore

/// Markers: set while recording, saved with the recording and the project,
/// shown on the timeline through cuts, and exported as chapters (MP4,
/// ProRes, YouTube text) and in Creative Handoff's timelines.
@MainActor
final class VideoMarkerTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        VideoTestStorage.isolate()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-markers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func project(duration: Double = 30, markers: [VideoMarker]) -> VideoDemoProject {
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/markers.mp4"), duration: duration, sourceSize: CGSize(width: 1280, height: 720))
        project.markers = markers
        return project
    }

    // MARK: Recording

    func testRecordedMarkersAreSavedWithTheRecording() throws {
        let recorder = VideoDemoRecordingMetadataRecorder(
            videoURL: URL(fileURLWithPath: "/tmp/rec.mp4"),
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourcePixelSize: CGSize(width: 200, height: 200),
            fps: 30,
            nativeCursorVisible: true,
            renderCursor: false
        )
        XCTAssertNil(recorder.addMarker(), "nothing before the recording starts")
        recorder.start()
        XCTAssertEqual(recorder.addMarker(), 1)
        XCTAssertEqual(recorder.addMarker(), 2)
        // The first frame came later: markers set before it mark the start.
        recorder.alignStart(to: CACurrentMediaTime() + 5)
        let metadata = recorder.finish(duration: 12)
        XCTAssertEqual(metadata.markers?.count, 2)
        XCTAssertEqual(metadata.markers?.first?.time, 0)

        let decoded = try JSONDecoder().decode(VideoDemoRecordingMetadata.self, from: JSONEncoder().encode(metadata))
        XCTAssertEqual(decoded.markers, metadata.markers)
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/rec.mp4"))
        project.apply(metadata: decoded)
        XCTAssertEqual(project.markers, metadata.markers, "a new recording opens with its markers")

        // Data saved before markers existed: none.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as! [String: Any]
        json.removeValue(forKey: "markers")
        let old = try JSONDecoder().decode(VideoDemoRecordingMetadata.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.markers)
    }

    func testTheShortcutHasNoDefaultAndIsListed() {
        XCTAssertNil(KeyboardShortcuts.Name.lfstudiosAddMarker.defaultShortcut, "no default: it can't clash with anything")
        XCTAssertTrue(LFStudiosShortcut.allCases.contains(.addMarker))
        XCTAssertEqual(LFStudiosShortcut.addMarker.section, .recording)
    }

    // MARK: Projects

    func testProjectsSaveMarkersAndOldOnesHaveNone() throws {
        let marked = project(markers: [VideoMarker(time: 4, name: "Intro"), VideoMarker(time: 12)])
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(marked))
        XCTAssertEqual(decoded.markers, marked.markers)

        let plain = project(markers: [])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as! [String: Any]
        XCTAssertNil(json["markers"], "an old project saved again stays as it was")
        XCTAssertEqual(try JSONDecoder().decode(VideoDemoProject.self, from: JSONSerialization.data(withJSONObject: json)).markers, [])
    }

    func testMarkersFollowCutsAndSpeedChanges() {
        var project = project(markers: [VideoMarker(time: 3, name: "A"), VideoMarker(time: 12), VideoMarker(time: 22)])
        // 0–10 at normal speed, 10–15 cut, 15–30 at twice the speed.
        project.timelineClips = [
            VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 10),
            VideoDemoTimelineClip(sourceStart: 15, sourceEnd: 30, speed: 2),
        ]
        let placed = project.placedMarkers(segments: project.timelineSegments(totalDuration: 30))
        XCTAssertEqual(placed.map(\.title), ["A", L("Marker \(3)")], "the one in the cut hides; names count from all markers")
        XCTAssertEqual(placed[0].time, 3, accuracy: 0.001)
        XCTAssertEqual(placed[1].time, 10 + (22 - 15) / 2, accuracy: 0.001)
    }

    // MARK: Chapters

    func testChaptersStartAtZero() {
        let markers = [
            VideoPlacedMarker(marker: VideoMarker(time: 12), time: 12, title: "Setup"),
            VideoPlacedMarker(marker: VideoMarker(time: 12.05), time: 12.05, title: "Twin"),
            VideoPlacedMarker(marker: VideoMarker(time: 40), time: 40, title: "Export"),
        ]
        let chapters = VideoDemoProject.chapters(from: markers, duration: 60)
        XCTAssertEqual(chapters, [VideoChapter(start: 0, title: L("Start")), VideoChapter(start: 12, title: "Setup"), VideoChapter(start: 40, title: "Export")])
        // A marker right at the beginning is the first chapter itself.
        let atStart = VideoDemoProject.chapters(from: [VideoPlacedMarker(marker: VideoMarker(time: 0.2), time: 0.2, title: "Hello")], duration: 60)
        XCTAssertEqual(atStart, [VideoChapter(start: 0, title: "Hello")])
        XCTAssertEqual(VideoDemoProject.chapters(from: [], duration: 60), [])
    }

    func testYouTubeChapterText() {
        let chapters = [VideoChapter(start: 0, title: "Start"), VideoChapter(start: 12, title: "Setup"), VideoChapter(start: 75.6, title: "Export")]
        XCTAssertEqual(VideoChapterText.text(chapters, duration: 120), "0:00 Start\n0:12 Setup\n1:15 Export")
        XCTAssertNil(VideoChapterText.problem(chapters, duration: 120))
        XCTAssertEqual(VideoChapterText.text(chapters, duration: 4000).components(separatedBy: "\n").last, "0:01:15 Export")
        XCTAssertNotNil(VideoChapterText.problem(Array(chapters.prefix(2)), duration: 120), "fewer than 3")
        XCTAssertNotNil(VideoChapterText.problem(chapters + [VideoChapter(start: 115, title: "End")], duration: 120), "one under 10 s")
    }

    // MARK: Editing

    private func model(seconds: Double = 8, markers: [VideoMarker] = []) async throws -> VideoEditorModel {
        let url = folder.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: seconds, fps: 30, audioSeconds: seconds)
        if !markers.isEmpty {
            let metadata = VideoDemoRecordingMetadata(videoURLPath: url.path, createdAt: Date(), duration: seconds, sourceWidth: 640, sourceHeight: 400, fps: 30, nativeCursorVisible: true, cursorSamples: [], clickEvents: [], markers: markers)
            VideoDemoSidecarStore.save(metadata, for: url)
        }
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.isReady)
        return model
    }

    func testAddRenameDeleteAndSplitAreUndoable() async throws {
        let model = try await model(markers: [VideoMarker(time: 2), VideoMarker(time: 5)])
        XCTAssertEqual(model.project.markers.count, 2, "the recording's markers")
        XCTAssertEqual(model.placedMarkers.map(\.title), [L("Marker \(1)"), L("Marker \(2)")])

        model.seek(to: 6.5)
        let added = try XCTUnwrap(model.addMarker())
        XCTAssertEqual(model.undoLabel, "Add Marker")
        XCTAssertEqual(model.project.markers.first { $0.id == added }?.time ?? 0, 6.5, accuracy: 0.05)

        let first = model.placedMarkers[0]
        model.renameMarker(first.id, to: "  Intro ")
        XCTAssertEqual(model.placedMarkers[0].title, "Intro")
        XCTAssertEqual(model.undoLabel, "Rename Marker")
        model.deleteMarker(added)
        XCTAssertEqual(model.undoLabel, "Delete Marker")
        XCTAssertEqual(model.project.markers.count, 2)

        model.seek(to: 5)
        model.jump(to: model.placedMarkers[0])
        XCTAssertEqual(model.clock.time, 2, accuracy: 0.05, "click: jump there")

        model.splitAtMarkers()
        XCTAssertEqual(model.segments.count, 3, "split at both markers")
        XCTAssertEqual(model.undoLabel, "Split at Markers")
        XCTAssertNotNil(VideoEditDescription.commands(for: "Split at Markers"))
        model.undo()
        XCTAssertEqual(model.segments.count, 1, "one step")
        model.undo()
        XCTAssertEqual(model.project.markers.count, 3, "the deleted one is back")
    }

    // MARK: Exports

    private func chapterTitles(_ url: URL) async throws -> [(String, Double)] {
        let asset = AVURLAsset(url: url)
        // The chapters' language is "undetermined": for every reader.
        let locales = try await asset.load(.availableChapterLocales)
        guard let locale = locales.first else { return [] }
        let groups = try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [.commonKeyTitle])
        return groups.map { group in
            let title = group.items.first { $0.commonKey == .commonKeyTitle }?.stringValue ?? ""
            return (title, group.timeRange.start.seconds)
        }
    }

    func testMoviesCarryChaptersWhenAsked() async throws {
        let model = try await model(markers: [VideoMarker(time: 2, name: "Setup"), VideoMarker(time: 5, name: "Export")])
        for format in [VideoExportSettings.Format.mp4, .proRes422] {
            var settings = VideoExportSettings()
            settings.format = format
            settings.resolution = .p720
            settings.fps = 30
            XCTAssertFalse(settings.chapters, "off until it's switched on")
            let plain = folder.appendingPathComponent("plain-\(format.rawValue).\(settings.fileExtension)")
            try await VideoDemoExporter.export(project: model.project, recording: model.recording, destinationURL: plain, settings: settings)
            let none = try await chapterTitles(plain)
            XCTAssertTrue(none.isEmpty)

            settings.chapters = true
            let url = folder.appendingPathComponent("chapters-\(format.rawValue).\(settings.fileExtension)")
            try await VideoDemoExporter.export(project: model.project, recording: model.recording, destinationURL: url, settings: settings)
            let chapters = try await chapterTitles(url)
            print("CHAPTERS \(format.title): \(chapters)")
            XCTAssertEqual(chapters.map(\.0), [L("Start"), "Setup", "Export"], format.title)
            XCTAssertEqual(chapters.map(\.1), [0, 2, 5], accuracy: 0.05)
        }
    }

    func testHandoffTimelinesHaveTheMarkers() {
        var project = project(duration: 10, markers: [VideoMarker(time: 2, name: "Setup & go"), VideoMarker(time: 7)])
        project.timelineClips = [VideoDemoTimelineClip(sourceStart: 1, sourceEnd: 10)]
        let screen = URL(fileURLWithPath: "/tmp/handoff/Screen.mov")
        let recordings = [VideoHandoffRecording(id: UUID(), url: screen, name: "Screen.mov", offset: 0, duration: 10, size: CGSize(width: 1280, height: 720), frameRate: 30, audioKinds: [.mixed], camera: nil, metadata: nil)]
        let input = VideoHandoffInput(name: "Demo", project: project, recordings: recordings, exportSettings: VideoExportSettings(), recording: nil)
        let plan = VideoHandoffPlanner.plan(input, options: VideoHandoffOptions(), folderName: "x")
        let folder = URL(fileURLWithPath: "/tmp/handoff/x")
        let fcp = VideoHandoffTimeline.fcpxml(plan: plan, input: input, folder: folder, durations: [:])
        XCTAssertTrue(fcp.contains("<marker start=\"30/30s\""), fcp)
        XCTAssertTrue(fcp.contains("value=\"Setup &amp; go\""))
        XCTAssertTrue(fcp.contains("<marker start=\"180/30s\""))
        let premiere = VideoHandoffTimeline.premiereXML(plan: plan, input: input, folder: folder, durations: [:])
        XCTAssertTrue(premiere.contains("<marker><name>Setup &amp; go</name><comment></comment><in>30</in><out>-1</out></marker>"), premiere)
        let readme = VideoHandoffReadme.text(plan: plan, name: "Demo", appVersion: nil, markers: project.placedMarkers(segments: input.segments), timelineDuration: input.timelineDuration)
        XCTAssertTrue(readme.contains("Markers (2)"), readme)
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, message, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, message, file: file, line: line) }
}
