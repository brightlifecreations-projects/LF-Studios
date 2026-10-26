import AVFoundation
import Foundation
import Testing
@testable import LFStudiosCore

/// Creative Handoff's planning: names, folders, lining up, missing files,
/// README.txt, and the timeline files (VideoHandoff*.swift).
@Suite("Creative Handoff", .serialized)
struct VideoHandoffTests {
    static let screen = URL(fileURLWithPath: "/tmp/handoff/Screen.mov")
    static let second = URL(fileURLWithPath: "/tmp/handoff/Second.mov")
    static let phone = URL(fileURLWithPath: "/tmp/handoff/Phone.mov")

    /// A 10 s recording with mic + Mac sound and a camera started `cameraOffset` later.
    static func input(clips: [VideoDemoTimelineClip], cameraOffset: Double = 0.7, cameraDuration: Double = 10, missingCamera: Bool = false, secondRecording: Bool = false, cutout: Bool = false) -> VideoHandoffInput {
        var project = VideoDemoProject.make(sourceURL: screen, duration: 10, sourceSize: CGSize(width: 1280, height: 720))
        project.timelineClips = clips
        project.captions = [VideoCaptionLine(start: 1, end: 2, text: "Hello")]
        var recordings = [VideoHandoffRecording(
            id: UUID(), url: screen, name: "Screen.mov", offset: 0, duration: 10, size: CGSize(width: 1280, height: 720), frameRate: 30,
            audioKinds: [.microphone, .system],
            camera: .init(url: missingCamera ? nil : phone, name: "Phone.mov", offset: cameraOffset, duration: cameraDuration, size: CGSize(width: 640, height: 480), frameRate: 30, cutout: cutout),
            metadata: nil
        )]
        if secondRecording {
            recordings.append(VideoHandoffRecording(id: UUID(), url: second, name: "Second.mov", offset: 10, duration: 5, size: CGSize(width: 1280, height: 720), frameRate: 30, audioKinds: [.mixed], camera: nil, metadata: nil))
        }
        return VideoHandoffInput(name: "Demo", project: project, recordings: recordings, exportSettings: VideoExportSettings(), recording: nil)
    }

    // MARK: Folder names

    @Test func theFolderIsNamedForTheProjectAndTheDay() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-27T10:00:00Z"))
        #expect(VideoHandoffPlanner.folderName(project: "Demo", date: date) { _ in false } == "Demo – Handoff 2026-10-27")
        let taken: Set<String> = ["Demo – Handoff 2026-10-27", "Demo – Handoff 2026-10-27 2"]
        #expect(VideoHandoffPlanner.folderName(project: "Demo", date: date) { taken.contains($0) } == "Demo – Handoff 2026-10-27 3")
        #expect(VideoHandoffPlanner.folderName(project: "A/B: test", date: date) { _ in false } == "A-B- test – Handoff 2026-10-27", "no slashes or colons in a folder name")
    }

    // MARK: Layout

    @Test func trimmedHandoffsHaveEachClipAndOnlyFoldersWithFiles() {
        let input = Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 4), VideoDemoTimelineClip(sourceStart: 6, sourceEnd: 10)])
        let plan = VideoHandoffPlanner.plan(input, options: VideoHandoffOptions(), folderName: "x")
        let paths = plan.items.map(\.relativePath)
        #expect(paths.contains("01 Screen/Clip 01.mov") && paths.contains("01 Screen/Clip 02.mov"))
        #expect(paths.contains("02 Camera/Camera.mov"))
        #expect(paths.contains("03 Audio/Microphone.wav") && paths.contains("03 Audio/System Audio.wav"))
        #expect(paths.contains("05 Captions/Captions.srt"))
        #expect(paths.contains { $0.hasPrefix("06 Final/") })
        #expect(paths.contains("Timeline.fcpxml") && paths.contains("Timeline (Premiere).xml") && paths.contains("README.txt"))
        #expect(!paths.contains { $0.hasPrefix("04 Graphics") || $0.hasPrefix("Fonts") || $0.hasPrefix("07 Data") }, "nothing to put there: no folder")
        #expect(plan.clockDuration == 8)
    }

    @Test func optionsLeaveOutTheFinishedVideoAndTheTimelines() {
        var options = VideoHandoffOptions()
        options.includeFinal = false
        options.includeTimeline = false
        let plan = VideoHandoffPlanner.plan(Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 10)]), options: options, folderName: "x")
        #expect(!plan.items.contains { $0.folder == .final })
        #expect(!plan.items.contains { $0.fileName.hasPrefix("Timeline") })
    }

    @Test func aMixedTrackIsOneFileAndSaysSo() {
        let input = Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 15)], secondRecording: true)
        let plan = VideoHandoffPlanner.plan(input, options: VideoHandoffOptions(), folderName: "x")
        let mixed = plan.items.first { $0.fileName == "Audio (mixed).wav" }
        #expect(mixed?.description.contains("microphone and Mac sound in one track") == true)
    }

    // MARK: Lining up

    @Test func trimmedClipsSitAtTheirPlaceInTheEdit() throws {
        // 0–4 s at 1×, then 6–10 s at 2× (2 s long): 6 s of edit.
        let input = Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 4), VideoDemoTimelineClip(sourceStart: 6, sourceEnd: 10, speed: 2)])
        let plan = VideoHandoffPlanner.plan(input, options: VideoHandoffOptions(), folderName: "x")
        guard case .reencode(let second, let duration, _, _, _, _) = try #require(plan.items.first { $0.fileName == "Clip 02.mov" }).work else { Issue.record("re-encoded"); return }
        #expect(duration == 6, "lined up: as long as the edit")
        #expect(second == [VideoHandoffPiece(url: Self.screen, sourceStart: 6, sourceDuration: 4, at: 4, speed: 2)])
        #expect(second[0].end == 6)
    }

    @Test func theCameraFollowsItsOffsetThroughTheCuts() throws {
        let input = Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 4), VideoDemoTimelineClip(sourceStart: 6, sourceEnd: 10, speed: 2)], cameraOffset: 0.7)
        let recording = input.recordings[0]
        let pieces = VideoHandoffPlanner.cameraPieces(recording, camera: recording.camera!, url: Self.phone, segments: input.segments)
        // Clip 1: the camera starts 0.7 s in, so its first frame plays at 0.7 s.
        #expect(abs(pieces[0].sourceStart - 0) < 1e-9 && abs(pieces[0].at - 0.7) < 1e-9 && abs(pieces[0].sourceDuration - 3.3) < 1e-9)
        // Clip 2: recording 6–10 s is camera 5.3–9.3 s, at 2×, from 4 s.
        #expect(abs(pieces[1].sourceStart - 5.3) < 1e-9 && abs(pieces[1].at - 4) < 1e-9 && abs(pieces[1].sourceDuration - 4) < 1e-9 && pieces[1].speed == 2)
        // A camera started before the recording is cut at the front.
        let early = Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 10)], cameraOffset: -1.5)
        let whole = VideoHandoffPlanner.cameraPieces(early.recordings[0], camera: early.recordings[0].camera!, url: Self.phone, segments: nil)
        #expect(whole == [VideoHandoffPiece(url: Self.phone, sourceStart: 1.5, sourceDuration: 8.5, at: 0)])
    }

    @Test func notLinedUpFilesStartAtTheirContentAndSayWhere() throws {
        var options = VideoHandoffOptions()
        options.lineUp = false
        let input = Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 4), VideoDemoTimelineClip(sourceStart: 6, sourceEnd: 10)], cameraOffset: 0.7)
        let plan = VideoHandoffPlanner.plan(input, options: options, folderName: "x")
        let clip = try #require(plan.items.first { $0.fileName == "Clip 02.mov" })
        #expect(clip.duration == 4 && clip.startOffset == 4)
        let camera = try #require(plan.items.first { $0.folder == .camera })
        #expect(camera.startOffset == 0.7)
        #expect(abs((camera.duration ?? 0) - 7.3) < 1e-9, "from 0.7 s to the edit's end at 8 s")
    }

    @Test func fullOriginalsAreCopiedOrPlacedWithoutReencoding() throws {
        var options = VideoHandoffOptions()
        options.clips = .full
        let plan = VideoHandoffPlanner.plan(Self.input(clips: [VideoDemoTimelineClip(sourceStart: 2, sourceEnd: 8)], secondRecording: true), options: options, folderName: "x")
        // Both recordings fill a 15 s axis: the first plays 0–10, the second 10–15.
        let first = try #require(plan.items.first { $0.fileName == "Screen.mov" })
        guard case .passthrough(let pieces, let duration) = first.work else { Issue.record("placed without re-encoding"); return }
        #expect(duration == 15 && pieces.first?.at == 0)
        let second = try #require(plan.items.first { $0.fileName == "Second.mov" })
        guard case .passthrough(let more, _) = second.work else { Issue.record("placed"); return }
        #expect(more.first?.at == 10)
        #expect(first.treatment == .originalWithEditList)
        #expect(!plan.reencodes, "nothing re-encoded")
        // The camera: its own frames, 0.7 s in.
        let camera = try #require(plan.items.first { $0.folder == .camera })
        guard case .passthrough(let cameraPieces, _) = camera.work else { Issue.record("placed"); return }
        #expect(cameraPieces.first?.at == 0.7)
    }

    @Test func aCutOutCameraIsProRes4444WithTransparency() throws {
        let plan = VideoHandoffPlanner.plan(Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 10)], cutout: true), options: VideoHandoffOptions(), folderName: "x")
        let camera = try #require(plan.items.first { $0.folder == .camera })
        guard case .reencode(_, _, let codec, let alpha, _, _) = camera.work else { Issue.record("re-encoded"); return }
        #expect(codec == .proRes4444 && alpha)
        #expect(camera.treatment == .proRes("ProRes 4444 with transparency"))
    }

    @Test func smallerFilesUseProRes422AndTheEstimateShrinks() throws {
        let input = Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 10)])
        var options = VideoHandoffOptions()
        let best = VideoHandoffPlanner.plan(input, options: options, folderName: "x")
        options.quality = .proRes422
        let smaller = VideoHandoffPlanner.plan(input, options: options, folderName: "x")
        guard case .reencode(_, _, let codec, _, _, _) = try #require(smaller.items.first { $0.folder == .screen }).work else { Issue.record("re-encoded"); return }
        #expect(codec == .proRes422)
        #expect(smaller.estimatedBytes < best.estimatedBytes)
        // 10 s of 1280×720 at 30 fps in ProRes 422 HQ is about 120 MB.
        let clip = try #require(best.items.first { $0.folder == .screen })
        #expect((100_000_000...140_000_000).contains(clip.estimatedBytes), "\(clip.estimatedBytes)")
    }

    // MARK: Missing files

    @Test func aMissingCameraIsLeftOutAndListed() {
        let plan = VideoHandoffPlanner.plan(Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 10)], missingCamera: true), options: VideoHandoffOptions(), folderName: "x")
        #expect(!plan.items.contains { $0.folder == .camera })
        #expect(plan.skipped == [L("Camera video “Phone.mov” — the file is missing")])
        let readme = VideoHandoffReadme.text(plan: plan, name: "Demo", appVersion: nil)
        #expect(readme.contains("NOT INCLUDED") && readme.contains("Phone.mov"))
    }

    // MARK: README

    @Test func theReadmeDescribesEveryFile() {
        let plan = VideoHandoffPlanner.plan(Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 4), VideoDemoTimelineClip(sourceStart: 6, sourceEnd: 10)]), options: VideoHandoffOptions(), folderName: "x")
        let readme = VideoHandoffReadme.text(plan: plan, name: "Demo", appVersion: "1.1.0", durations: ["01 Screen/Clip 01.mov": 8.0])
        for item in plan.items { #expect(readme.contains(item.relativePath), "\(item.relativePath)") }
        #expect(readme.contains("Made with LF Studios 1.1.0"))
        #expect(readme.contains("every video and sound file starts at 0:00 and is 0:08.00 long"))
        #expect(readme.contains("length 0:08.00 · 30 fps · starts at 0:00.00 · re-encoded to ProRes 422 HQ"))
        #expect(readme.contains("Re-encoded to ProRes: 01 Screen/Clip 01.mov, 01 Screen/Clip 02.mov, 02 Camera/Camera.mov"))
        #expect(readme.contains("They can't carry LF Studios' effects: zooms"))
    }

    // MARK: Timelines

    @Test func ntscRatesGetExactFrameDurations() {
        #expect(VideoHandoffTimebase(fps: 29.97).frameDuration == "1001/30000s")
        #expect(VideoHandoffTimebase(fps: 60).frameDuration == "1/60s")
        #expect(VideoHandoffTimebase(fps: 30).fcp(1.5) == "45/30s")
        #expect(VideoHandoffTimebase(fps: 29.97).fcp(1) == "30030/30000s")
        #expect(VideoHandoffTimebase(fps: 30).fcp(0) == "0s")
    }

    @Test func theTimelinesAreWellFormedXML() throws {
        let input = Self.input(clips: [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 4), VideoDemoTimelineClip(sourceStart: 6, sourceEnd: 10, speed: 2)])
        for clips in VideoHandoffOptions.Clips.allCases {
            var options = VideoHandoffOptions()
            options.clips = clips
            let plan = VideoHandoffPlanner.plan(input, options: options, folderName: "x")
            let folder = URL(fileURLWithPath: "/tmp/Demo – Handoff", isDirectory: true)
            let fcpxml = VideoHandoffTimeline.fcpxml(plan: plan, input: input, folder: folder, durations: [:])
            let document = try XMLDocument(xmlString: fcpxml)
            #expect(document.rootElement()?.attribute(forName: "version")?.stringValue == "1.10")
            let clipCount = try document.nodes(forXPath: "//asset-clip").count
            #expect(clipCount >= 4, "\(clips): \(clipCount) clips")
            #expect(fcpxml.contains("file:///tmp/Demo%20%E2%80%93%20Handoff/"), "files point into the handoff folder")
            if clips == .full { #expect(fcpxml.contains("<timeMap>"), "the 2× clip keeps its speed") }
            let premiere = VideoHandoffTimeline.premiereXML(plan: plan, input: input, folder: folder, durations: [:])
            let xmeml = try XMLDocument(xmlString: premiere)
            #expect(xmeml.rootElement()?.name == "xmeml")
            if clips == .full { #expect(premiere.contains("<value>200.00</value>"), "speed 200% in Premiere") }
        }
    }

    // MARK: Options

    @Test func theLastChoicesAreRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "LFStudiosTests.Handoff.\(UUID().uuidString)"))
        var options = VideoHandoffOptions()
        options.clips = .full
        options.lineUp = false
        options.quality = .proRes422
        options.save(defaults)
        #expect(VideoHandoffOptions.load(defaults) == options)
        let folder = FileManager.default.temporaryDirectory
        VideoHandoffOptions.remember(location: folder, defaults)
        #expect(VideoHandoffOptions.lastLocation(defaults)?.standardizedFileURL.resolvingSymlinksInPath() == folder.standardizedFileURL.resolvingSymlinksInPath())
        #expect(VideoHandoffOptions() == VideoHandoffOptions(clips: .trimmed, lineUp: true, includeFinal: true, includeTimeline: true, quality: .proRes422HQ), "defaults: trimmed, lined up, final and timeline on, best quality")
    }

    // MARK: Transparency, for real

    @Test func aCutOutCameraFileReallyHasTransparency() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-alpha-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let camera = folder.appendingPathComponent("camera.mp4")
        try await TestVideos.writeQuadrants(to: camera, size: CGSize(width: 320, height: 240), seconds: 1)
        let writerFolder = folder.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: writerFolder, withIntermediateDirectories: true)
        var plan = VideoHandoffPlan(folderName: "x", items: [], skipped: [], clockDuration: 1, options: VideoHandoffOptions())
        plan.items = [VideoHandoffItem(folder: .camera, fileName: "Camera.mov", description: "", work: .reencode([VideoHandoffPiece(url: camera, sourceStart: 0, sourceDuration: 1, at: 0)], duration: 1, codec: .proRes4444, alpha: true, size: CGSize(width: 320, height: 240), frameRate: 30), treatment: .proRes("ProRes 4444"), duration: 1, frameRate: 30, startOffset: 0, estimatedBytes: 1000)]
        var options = plan.options
        options.includeTimeline = false
        plan.options = options
        let result = try await VideoHandoffWriter(plan: plan, input: Self.input(clips: []), parent: writerFolder).run()
        let file = result.folder.appendingPathComponent("02 Camera/Camera.mov")
        let asset = AVURLAsset(url: file)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let description = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_AppleProRes4444)
        // No person in the colored squares: everything is see-through.
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        #expect(reader.startReading())
        let sample = try #require(output.copyNextSampleBuffer())
        let pixels = try #require(CMSampleBufferGetImageBuffer(sample))
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let base = try #require(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(pixels)
        let alpha = base[(120 * row) + 160 * 4 + 3]
        #expect(alpha < 10, "transparent where no one is: alpha \(alpha)")
    }
}
