import AVFoundation
import XCTest
@testable import LFStudiosCore

/// After recording, everything moves into a folder of its own
/// (VideoRecordingFolder.swift): its layout and names, moves that undo
/// themselves when they fail (or a crash stops them), paths that survive
/// renaming and moving the folder, and Home finding the folder again.
@MainActor
final class RecordingFolderTests: XCTestCase {
    private var root: URL!
    private var place: URL!
    private var suiteName: String!

    override func setUp() async throws {
        _ = NSApplication.shared
        VideoTestStorage.isolate()
        suiteName = "LFStudiosCoreTests.RecordingFolder.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-recording-folder-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Storage", isDirectory: true)
        place = base.appendingPathComponent("Saved Here", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
    }

    // MARK: A fake finished recording

    struct Take {
        var video: URL
        var camera: URL?
    }

    /// A screen recording with a microphone track, its data (pointer,
    /// clicks, markers, notes), and a camera video in LF Studios' hidden folder.
    private func take(camera: Bool = true, notes: String? = "Say hello first.", name: String = "LF Studios 2026-10-29 at 10.00.00") async throws -> Take {
        let recordings = root.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let video = recordings.appendingPathComponent("\(name).mp4")
        try await VideoTestSupport.writeFakeRecording(to: video, size: CGSize(width: 640, height: 400), seconds: 2, audioSeconds: 2)
        var cameraURL: URL?
        if camera {
            let folder = root.appendingPathComponent("LF Studios/VideoCameras", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            cameraURL = folder.appendingPathComponent("\(name)-1a2b3c4d.mov")
            try await VideoTestSupport.writeFakeRecording(to: cameraURL!, size: CGSize(width: 320, height: 240), seconds: 2)
        }
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 2)
        var metadata = VideoDemoRecordingMetadata(videoURLPath: video.path, createdAt: Date(), duration: 2, sourceWidth: 640, sourceHeight: 400, fps: 30, nativeCursorVisible: false, cursorSamples: samples, clickEvents: clicks)
        metadata.audioTracks = [.microphone]
        metadata.markers = [VideoMarker(time: 1, name: "Middle")]
        metadata.speakerNotes = notes
        if let cameraURL { metadata.webcam = VideoWebcamRecording(path: cameraURL.path, offset: 0.25, width: 320, height: 240) }
        XCTAssertTrue(VideoDemoSidecarStore.save(metadata, for: video, baseDirectory: root))
        return Take(video: video, camera: cameraURL)
    }

    private func organize(_ take: Take, name: String = "Product demo", mover: VideoFileMoving = VideoSafeFileMover()) async throws -> VideoRecordingFolderWriter.Result {
        try await VideoRecordingFolderWriter.organize(video: take.video, into: place, name: name, mover: mover, root: root)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: Layout and names

    func testEverythingGoesIntoOneFolderLaidOutLikeAHandoff() async throws {
        let take = try await take()
        let id = VideoFileIdentity.ensureID(of: take.video)
        let result = try await organize(take)
        let folder = place.appendingPathComponent("Product demo", isDirectory: true)
        XCTAssertEqual(result.folder.standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(result.video.lastPathComponent, "Product demo.mp4")
        XCTAssertTrue(exists(folder.appendingPathComponent("01 Screen/Product demo.mp4")))
        XCTAssertTrue(exists(folder.appendingPathComponent("02 Camera/Camera.mov")))
        XCTAssertTrue(exists(folder.appendingPathComponent("03 Audio/Microphone.wav")))
        XCTAssertFalse(exists(folder.appendingPathComponent("03 Audio/System Audio.wav")), "no system audio was recorded")
        XCTAssertTrue(exists(folder.appendingPathComponent("07 Data/Recording data.json")))
        XCTAssertTrue(exists(folder.appendingPathComponent("Speaker notes.txt")))
        XCTAssertTrue(exists(folder.appendingPathComponent("README.txt")))
        XCTAssertTrue(exists(folder.appendingPathComponent("Product demo.lfstudios/project.json")))
        XCTAssertFalse(exists(folder.appendingPathComponent("05 Captions")), "no captions yet: no empty folder")
        XCTAssertFalse(exists(folder.appendingPathComponent("04 Graphics")))
        // Moved, not copied: nothing is left behind in the hidden folder.
        XCTAssertFalse(exists(take.video))
        XCTAssertFalse(exists(take.camera!))
        XCTAssertEqual(VideoFileIdentity.stampedID(of: result.video), id, "the recording keeps its identity, so its edits follow")

        // The WAV is the recording's own track, as long as the recording.
        let wav = AVURLAsset(url: folder.appendingPathComponent("03 Audio/Microphone.wav"))
        let length = try await wav.load(.duration).seconds
        XCTAssertEqual(length, 2, accuracy: 0.1)
        let tracks = try await wav.loadTracks(withMediaType: .audio)
        let channels = try await tracks.first?.load(.formatDescriptions).first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
        XCTAssertEqual(channels, 1)

        // The data file names the files relative to the folder.
        let data = try String(contentsOf: folder.appendingPathComponent("07 Data/Recording data.json"), encoding: .utf8)
        XCTAssertTrue(data.contains("01 Screen\\/Product demo.mp4") || data.contains("01 Screen/Product demo.mp4"))
        XCTAssertTrue(data.contains("Middle"), "markers")
        XCTAssertFalse(data.contains(root.path), "no paths into LF Studios' hidden folder")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("Speaker notes.txt"), encoding: .utf8), "Say hello first.")

        // The project file opens the whole thing.
        let opened = try VideoProjectPackage.open(result.project)
        XCTAssertEqual(opened.document.mediaMode, .folder)
        XCTAssertEqual(opened.document.folder?.kind, .recording)
        XCTAssertEqual(opened.document.version, 2)
        XCTAssertEqual(opened.contents.project.sourceURL.standardizedFileURL, result.video.standardizedFileURL)
        XCTAssertEqual(opened.contents.recording?.webcam?.path, folder.appendingPathComponent("02 Camera/Camera.mov").standardizedFileURL.path)
        XCTAssertEqual(opened.contents.recording?.webcam?.offset, 0.25)
        XCTAssertEqual(opened.contents.project.markers.map(\.name), ["Middle"])
        let manifest = try String(contentsOf: VideoProjectPackage.manifestURL(result.project), encoding: .utf8)
        XCTAssertTrue(manifest.contains("@folder\\/01 Screen") || manifest.contains("@folder/01 Screen"))
        XCTAssertFalse(manifest.contains(place.path), "paths are relative to the folder")

        // The editor's data for it points into the folder too.
        let sidecar = VideoDemoSidecarStore.load(for: result.video, baseDirectory: root)
        XCTAssertEqual(sidecar?.webcam?.path, folder.appendingPathComponent("02 Camera/Camera.mov").path)
        XCTAssertEqual(VideoRecordingFolder.project(ofVideo: result.video)?.standardizedFileURL, result.project.standardizedFileURL)
    }

    func testATakenNameGetsANumberAndOddCharactersAreReplaced() async throws {
        try FileManager.default.createDirectory(at: place.appendingPathComponent("Product demo"), withIntermediateDirectories: true)
        let first = try await organize(try await take(name: "A"))
        XCTAssertEqual(first.folder.lastPathComponent, "Product demo 2")
        XCTAssertEqual(first.video.lastPathComponent, "Product demo 2.mp4")
        let second = try await organize(try await take(name: "B"))
        XCTAssertEqual(second.folder.lastPathComponent, "Product demo 3")
        XCTAssertEqual(VideoRecordingFolder.safeName("a/b:c"), "a-b-c")
        XCTAssertEqual(VideoRecordingFolder.safeName("  "), "Recording")
        XCTAssertEqual(VideoRecordingFolder.safeName(".hidden"), "hidden")
    }

    func testWithoutCameraOrNotesThoseAreLeftOut() async throws {
        let result = try await organize(try await take(camera: false, notes: nil))
        XCTAssertFalse(exists(result.folder.appendingPathComponent("02 Camera")))
        XCTAssertFalse(exists(result.folder.appendingPathComponent("Speaker notes.txt")))
        let readme = try String(contentsOf: result.folder.appendingPathComponent("README.txt"), encoding: .utf8)
        XCTAssertFalse(readme.contains("02 Camera"))
        XCTAssertTrue(readme.contains("01 Screen/Product demo.mp4"))
    }

    // MARK: Moving safely

    /// Moves like the real one, but fails on the named file.
    struct FailingMover: VideoFileMoving {
        var failsOn: String

        func move(_ source: URL, to destination: URL) async throws {
            if source.lastPathComponent.contains(failsOn) { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    func testAMoveThatFailsPutsEverythingBack() async throws {
        let take = try await take()
        do {
            _ = try await organize(take, mover: FailingMover(failsOn: "1a2b3c4d"))
            XCTFail("should have failed on the camera")
        } catch let failure as VideoRecordingFolderWriter.Failure {
            guard case .couldNotMove(let file, _) = failure else { return XCTFail("\(failure)") }
            XCTAssertEqual(file, take.camera!.lastPathComponent)
        }
        // The screen recording had moved already: it's back where it was.
        XCTAssertTrue(exists(take.video))
        XCTAssertTrue(exists(take.camera!))
        XCTAssertFalse(exists(place.appendingPathComponent("Product demo")), "the half-made folder is gone")
        XCTAssertTrue(VideoRecordingMoveLog.all(root: root).isEmpty)
        // And it still opens as before.
        XCTAssertEqual(VideoDemoSidecarStore.load(for: take.video, baseDirectory: root)?.webcam?.path, take.camera!.path)
    }

    func testAMoveACrashStoppedIsUndoneAndDoneAgainAtLaunch() async throws {
        let take = try await take()
        // A crash right after the screen recording moved.
        let folder = place.appendingPathComponent("Product demo", isDirectory: true)
        let moved = folder.appendingPathComponent("01 Screen/Product demo.mp4")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: take.video, to: moved)
        var log = VideoRecordingMoveLog(video: take.video.path, parent: place.path, name: "Product demo", folder: folder.path)
        log.moves = [.init(from: take.video.path, to: moved.path), .init(from: take.camera!.path, to: folder.appendingPathComponent("02 Camera/Camera.mov").path)]
        log.save(root: root)

        let results = await VideoRecordingFolderWriter.finishInterrupted(root: root)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.folder.lastPathComponent, "Product demo")
        XCTAssertTrue(exists(folder.appendingPathComponent("01 Screen/Product demo.mp4")))
        XCTAssertTrue(exists(folder.appendingPathComponent("02 Camera/Camera.mov")))
        XCTAssertFalse(exists(take.video))
        XCTAssertTrue(VideoRecordingMoveLog.all(root: root).isEmpty)
    }

    func testAHalfCopyIsNeverTakenForTheRecording() async throws {
        let take = try await take()
        let copy = place.appendingPathComponent("copy.mp4")
        try FileManager.default.copyItem(at: take.video, to: copy)
        try await VideoSafeFileMover.verify(copy: copy, of: take.video)
        // Cut short, like a copy to a full drive.
        let bytes = try Data(contentsOf: copy)
        try bytes.prefix(bytes.count / 2).write(to: copy)
        do {
            try await VideoSafeFileMover.verify(copy: copy, of: take.video)
            XCTFail("a half copy passed")
        } catch {}
    }

    func testARecordingFinishedWhileQuittingGetsItsFolderInTheRecordingFolder() async throws {
        let recordings = place.appendingPathComponent("Recording folder", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        XCTAssertTrue(Settings.setRecordingFolder(recordings.path))
        let take = try await take(name: "LF Studios 2026-10-29 at 11.00.00")
        VideoRecordingFolders.addPending(take.video, root: root)
        let results = await VideoRecordingFolderWriter.finishInterrupted(root: root)
        XCTAssertEqual(results.first?.folder.deletingLastPathComponent().standardizedFileURL, recordings.standardizedFileURL)
        XCTAssertEqual(results.first?.folder.lastPathComponent, "LF Studios 2026-10-29 at 11.00.00")
        XCTAssertTrue(VideoRecordingFolders.takePending(root: root).isEmpty, "done once")
    }

    func testCancelOrNotAskingSavesToTheRecordingFolder() throws {
        let recordings = place.appendingPathComponent("Recording folder", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        XCTAssertTrue(Settings.setRecordingFolder(recordings.path))
        let video = URL(fileURLWithPath: "/tmp/LF Studios 2026-10-29 at 12.00.00.mp4")
        let cancelled = VideoRecordingSaveFlow.destination(for: video, chosen: nil)
        XCTAssertEqual(cancelled.parent.standardizedFileURL, recordings.standardizedFileURL)
        XCTAssertEqual(cancelled.name, "LF Studios 2026-10-29 at 12.00.00")
        let chosen = VideoRecordingSaveFlow.destination(for: video, chosen: place.appendingPathComponent("Launch video"))
        XCTAssertEqual(chosen.parent.standardizedFileURL, place.standardizedFileURL)
        XCTAssertEqual(chosen.name, "Launch video")
    }

    // MARK: Moving and renaming the folder

    func testTheFolderCanBeRenamedOrMovedAndStillOpens() async throws {
        let result = try await organize(try await take())
        let renamed = place.appendingPathComponent("Renamed in Finder", isDirectory: true)
        try FileManager.default.moveItem(at: result.folder, to: renamed)
        var opened = try VideoProjectPackage.open(renamed.appendingPathComponent("Product demo.lfstudios"))
        XCTAssertEqual(opened.contents.project.sourceURL.standardizedFileURL.path, renamed.appendingPathComponent("01 Screen/Product demo.mp4").standardizedFileURL.path)
        XCTAssertTrue(exists(opened.contents.project.sourceURL))
        XCTAssertTrue(exists(URL(fileURLWithPath: opened.contents.recording!.webcam!.path)))

        let elsewhere = root.deletingLastPathComponent().appendingPathComponent("Another drive folder/Inside", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: renamed, to: elsewhere)
        opened = try VideoProjectPackage.open(elsewhere.appendingPathComponent("Product demo.lfstudios"))
        XCTAssertTrue(exists(opened.contents.project.sourceURL))
        XCTAssertTrue(exists(URL(fileURLWithPath: opened.contents.recording!.webcam!.path)))
    }

    func testHomeFindsTheFolderWhereverItWasSavedAndAfterAMove() async throws {
        let result = try await organize(try await take())
        XCTAssertEqual(VideoRecordingFolders.projects(scanning: [], root: root).map(\.lastPathComponent), ["Product demo.lfstudios"])
        let moved = root.deletingLastPathComponent().appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.moveItem(at: result.folder, to: moved)
        XCTAssertEqual(VideoRecordingFolders.projects(scanning: [], root: root).first?.deletingLastPathComponent().standardizedFileURL, moved.standardizedFileURL)
        // One it never saved, found by looking in the Recording folder.
        VideoRecordingFolders.remove(moved, root: root)
        XCTAssertTrue(VideoRecordingFolders.projects(scanning: [], root: root).isEmpty)
        XCTAssertEqual(VideoRecordingFolders.projects(scanning: [root.deletingLastPathComponent()], root: root).count, 1)
    }

    // MARK: Kept up to date

    func testTheEditorKeepsTheFoldersProjectAndCaptionsUpToDate() async throws {
        let result = try await organize(try await take(camera: false))
        let opened = try VideoProjectPackage.open(result.project)
        XCTAssertNotNil(VideoProjectOpener.prepare(opened))
        let model = VideoEditorModel(videoURL: result.video)
        model.projectFileURL = result.project
        model.projectMediaMode = .folder
        model.projectFolder = opened.document.folder
        await model.load()
        XCTAssertTrue(model.isReady)
        model.mutate(label: "Add Caption") {
            $0.captions = [VideoCaptionLine(id: UUID(), start: 0.2, end: 1.2, text: "Hello there", words: [])]
        }
        model.saveDraftNow()
        await model.recordingFolderWrite?.value
        let srt = result.folder.appendingPathComponent("05 Captions/Product demo.srt")
        XCTAssertTrue(try String(contentsOf: srt, encoding: .utf8).contains("Hello there"))
        let saved = try VideoProjectPackage.open(result.project)
        XCTAssertEqual(saved.contents.project.captions.map(\.text), ["Hello there"], "the project file holds the edit")
        XCTAssertEqual(saved.document.folder?.kind, .recording)

        // A folder someone opened themselves changes only on Save.
        let before = try Data(contentsOf: VideoProjectPackage.manifestURL(result.project))
        model.projectFolder = .init(kind: .opened)
        model.mutate(label: "Add Caption") { $0.captions[0].text = "Changed" }
        model.saveDraftNow()
        await model.recordingFolderWrite?.value
        XCTAssertEqual(try Data(contentsOf: VideoProjectPackage.manifestURL(result.project)), before)
        XCTAssertTrue(try String(contentsOf: srt, encoding: .utf8).contains("Hello there"))
    }

    /// Another Mac: the folder alone, none of LF Studios' hidden data
    /// (drafts, the recording's data) — the edit is all there.
    func testTheFolderOpensWithTheWholeEditOnAnotherMac() async throws {
        let result = try await organize(try await take())
        let opened = try VideoProjectPackage.open(result.project)
        XCTAssertNotNil(VideoProjectOpener.prepare(opened))
        let model = VideoEditorModel(videoURL: result.video)
        model.projectFileURL = result.project
        model.projectMediaMode = .folder
        model.projectFolder = opened.document.folder
        await model.load()
        model.mutate(label: "Add Caption") {
            $0.captions = [VideoCaptionLine(id: UUID(), start: 0.2, end: 1.2, text: "Made on this Mac", words: [])]
            $0.timelineClips = [VideoDemoTimelineClip(sourceStart: 0.5, sourceEnd: 1.8, speed: 1)]
        }
        model.saveDraftNow()
        await model.recordingFolderWrite?.value

        // Copied to another Mac: a different place, and no hidden data at all.
        let otherMac = root.deletingLastPathComponent().appendingPathComponent("Other Mac/Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: otherMac, withIntermediateDirectories: true)
        let copied = otherMac.appendingPathComponent(result.folder.lastPathComponent, isDirectory: true)
        try FileManager.default.copyItem(at: result.folder, to: copied)
        let otherStorage = root.deletingLastPathComponent().appendingPathComponent("Other Mac/Storage", isDirectory: true)
        try FileManager.default.createDirectory(at: otherStorage, withIntermediateDirectories: true)
        try await VideoStorageLocation.$scopedRoot.withValue(otherStorage) {
            let project = try XCTUnwrap(VideoRecordingFolder.projectFiles(in: copied).first)
            let there = try VideoProjectPackage.open(project)
            XCTAssertEqual(there.contents.project.captions.map(\.text), ["Made on this Mac"])
            XCTAssertEqual(there.contents.project.timelineClips.first?.sourceStart ?? 0, 0.5, accuracy: 0.001)
            XCTAssertTrue(FileManager.default.fileExists(atPath: there.contents.project.sourcePath))
            XCTAssertTrue(FileManager.default.fileExists(atPath: there.contents.recording?.webcam?.path ?? "/missing"))
            XCTAssertEqual(there.contents.recording?.webcam?.offset, 0.25)
            XCTAssertEqual(there.contents.recording?.cursorSamples.isEmpty, false, "the pointer data travels inside the project")
            let primary = try XCTUnwrap(VideoProjectOpener.prepare(there))
            let editor = VideoEditorModel(videoURL: primary)
            await editor.load()
            XCTAssertTrue(editor.isReady)
            XCTAssertEqual(editor.project.captions.map(\.text), ["Made on this Mac"])
            XCTAssertTrue(editor.hasWebcamFootage, "the camera is found in the copied folder")
        }
    }

    func testCaptionsFilesFollowTheCaptions() throws {
        let folder = place.appendingPathComponent("Demo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Demo.lfstudios"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("Demo.lfstudios/project.json"))
        VideoRecordingFolder.writeCaptions(["Demo.srt": "1\n00:00:00,000 --> 00:00:01,000\nHi\n", "Demo.es.srt": "1\n00:00:00,000 --> 00:00:01,000\nHola\n"], in: folder)
        let captions = folder.appendingPathComponent("05 Captions", isDirectory: true)
        XCTAssertEqual(try String(contentsOf: captions.appendingPathComponent("Demo.srt"), encoding: .utf8).contains("Hi"), true)
        // Someone's own file there stays.
        try "mine".write(to: captions.appendingPathComponent("Notes.srt"), atomically: true, encoding: .utf8)
        VideoRecordingFolder.writeCaptions(["Demo.srt": "1\n00:00:00,000 --> 00:00:01,000\nHello\n"], in: folder)
        XCTAssertTrue(try String(contentsOf: captions.appendingPathComponent("Demo.srt"), encoding: .utf8).contains("Hello"))
        XCTAssertFalse(exists(captions.appendingPathComponent("Demo.es.srt")), "the translation was removed")
        XCTAssertTrue(exists(captions.appendingPathComponent("Notes.srt")))
        VideoRecordingFolder.writeCaptions([:], in: folder)
        XCTAssertFalse(exists(captions.appendingPathComponent("Demo.srt")))
        XCTAssertTrue(exists(captions.appendingPathComponent("Notes.srt")))
    }

    func testProjectsThatArentFolderProjectsStillSaveAsVersionOne() throws {
        let video = place.appendingPathComponent("plain.mp4")
        try Data([0]).write(to: video)
        let contents = VideoProjectContents(project: VideoDemoProject.fresh(sourceURL: video), recording: nil, sourceRecordings: [:])
        let package = place.appendingPathComponent("Plain.lfstudios")
        let document = try VideoProjectPackage.save(contents, to: package, mode: .linked)
        XCTAssertEqual(document.version, 1, "older LF Studios versions open it without a warning")
        XCTAssertNil(document.folder)
        XCTAssertNil(VideoRecordingFolder.folderInfo(of: package))
    }
}
