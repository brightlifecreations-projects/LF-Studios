import AVFoundation
import Foundation
import Testing
@testable import ShotStyleCore

/// Camera footage from elsewhere (VideoImportedCamera.swift) and lining it
/// up by sound (VideoAudioSync.swift).
@Suite("Camera video from elsewhere", .serialized)
struct VideoImportedCameraTests {
    static let beepTimes = [0.4, 1.1, 1.5, 2.6, 3.0, 3.9, 4.3, 5.6, 6.1]

    private func envelope(_ samples: [Float]) throws -> [Float] {
        try #require(VideoAudioSync.envelope(samples: samples, sampleRate: TestSounds.sampleRate))
    }

    /// The camera started `lag` seconds after the screen: its beeps come
    /// `lag` earlier in its own time.
    private func syncedOffset(lag: Double, cameraGain: Float = 0.25, cameraNoise: Float = 0.03) throws -> Result<VideoAudioSync.Match, VideoAudioSync.Failure> {
        let screen = TestSounds.beeps(at: Self.beepTimes, seconds: 7)
        let camera = TestSounds.beeps(at: Self.beepTimes.map { $0 - lag }, seconds: 7 - max(lag, 0), gain: cameraGain, noise: cameraNoise, seed: 7)
        return VideoAudioSync.match(reference: try envelope(screen), other: try envelope(camera), rate: VideoAudioSync.envelopeRate, maximumOffset: 60)
    }

    // MARK: Sync by sound

    @Test(arguments: [0.7, -1.25, 0, 2.333])
    func theSameBeepsLineUp(lag: Double) throws {
        let match = try syncedOffset(lag: lag).get()
        #expect(abs(match.offset - lag) < 0.02, "found \(match.offset) for \(lag)")
        #expect(match.correlation > VideoAudioSync.minimumCorrelation)
    }

    @Test func differentSoundsAreRefused() throws {
        let screen = TestSounds.beeps(at: Self.beepTimes, seconds: 7)
        // Evenly spaced beeps share no pattern with the screen's.
        let other = TestSounds.beeps(at: stride(from: 0.3, to: 7, by: 0.5).map { $0 }, seconds: 7, seed: 3)
        let result = VideoAudioSync.match(reference: try envelope(screen), other: try envelope(other), rate: VideoAudioSync.envelopeRate, maximumOffset: 60)
        guard case .failure(.weakMatch) = result else {
            if case .success(let match) = result { print("unrelated match", match) }
            Issue.record("unrelated sound was matched: \(result)")
            return
        }
    }

    @Test func steadyHissHasNothingToLineUp() {
        // Even loudness all the way: no envelope, so it can't sync.
        let hiss = TestSounds.beeps(at: [], seconds: 7, noise: 0.2, seed: 11)
        #expect(VideoAudioSync.envelope(samples: hiss, sampleRate: TestSounds.sampleRate) == nil)
    }

    @Test func silenceHasNoEnvelope() {
        #expect(VideoAudioSync.envelope(samples: [Float](repeating: 0, count: 44_100 * 3), sampleRate: TestSounds.sampleRate) == nil)
    }

    @Test func aVideoWithoutSoundCantSync() async throws {
        let folder = try Self.folder()
        let screen = folder.appendingPathComponent("silent.mp4")
        try await TestVideos.writeBars(to: screen, size: CGSize(width: 320, height: 180), seconds: 2)
        let result = await VideoAudioSync.match(reference: screen, other: screen)
        #expect(result == .failure(.noSound))
    }

    @Test func soundtracksInFilesLineUp() async throws {
        let folder = try Self.folder()
        let screen = folder.appendingPathComponent("screen.m4a"), camera = folder.appendingPathComponent("camera.m4a")
        try TestSounds.writeAudio(TestSounds.beeps(at: Self.beepTimes, seconds: 7), to: screen)
        try TestSounds.writeAudio(TestSounds.beeps(at: Self.beepTimes.map { $0 - 0.7 }, seconds: 6.3, gain: 0.3, noise: 0.02, seed: 5), to: camera)
        let match = try await VideoAudioSync.match(reference: screen, other: camera).get()
        #expect(abs(match.offset - 0.7) < 0.02, "found \(match.offset)")
    }

    // MARK: The project

    private static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shotstyle-imported-camera-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func camera(at url: URL, offset: Double = 0.5, duration: Double = 1) -> VideoImportedCamera {
        VideoImportedCamera(path: url.path, bookmark: VideoSourceLocator.bookmark(for: url), offset: offset, width: 640, height: 480, duration: duration)
    }

    @Test func importedFootageTakesTheRecordedCamerasPlace() {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/screen.mp4"), duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        let recorded = VideoWebcamRecording(path: "/tmp/recorded-camera.mov", offset: 0.05, width: 1280, height: 720)
        #expect(project.activeCamera(recorded: recorded) == recorded)
        project.importedCamera = VideoImportedCamera(path: "/tmp/phone.mov", bookmark: nil, offset: 0.7, width: 1080, height: 1920, duration: 10)
        #expect(project.activeCamera(recorded: recorded) == VideoWebcamRecording(path: "/tmp/phone.mov", offset: 0.7, width: 1080, height: 1920))
        #expect(project.activeCamera(recorded: nil)?.path == "/tmp/phone.mov")
    }

    @Test func itIsSavedWithTheEditAndOlderEditsStillOpen() throws {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/screen.mp4"), duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        let plain = try JSONEncoder().encode(project)
        #expect(!String(decoding: plain, as: UTF8.self).contains("importedCamera"))
        #expect(try JSONDecoder().decode(VideoDemoProject.self, from: plain).importedCamera == nil)
        project.importedCamera = VideoImportedCamera(path: "/tmp/phone.mov", bookmark: Data([1, 2, 3]), offset: -1.25, width: 1080, height: 1920, duration: 10)
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: try JSONEncoder().encode(project))
        #expect(decoded.importedCamera == project.importedCamera)
        #expect(decoded == project)
    }

    @Test func aMovedFileIsFoundByItsBookmarkAndAMissingOneIsReported() async throws {
        let folder = try Self.folder()
        let original = folder.appendingPathComponent("phone.mp4")
        try await TestVideos.writeQuadrants(to: original, size: CGSize(width: 160, height: 120), seconds: 1)
        var project = VideoDemoProject.make(sourceURL: folder.appendingPathComponent("screen.mp4"), duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        project.importedCamera = camera(at: original)
        let moved = folder.appendingPathComponent("renamed.mp4")
        try FileManager.default.moveItem(at: original, to: moved)
        #expect(project.importedCamera?.resolved()?.standardizedFileURL.resolvingSymlinksInPath().path == moved.standardizedFileURL.resolvingSymlinksInPath().path)
        project.relocateImportedCamera()
        #expect(FileManager.default.fileExists(atPath: project.importedCamera!.path))
        try FileManager.default.removeItem(at: moved)
        #expect(project.importedCamera?.resolved() == nil)
    }

    @Test func readingAVideoGetsItsUprightSizeAndLength() async throws {
        let folder = try Self.folder()
        let url = folder.appendingPathComponent("phone.mp4")
        try await TestVideos.writeQuadrants(to: url, size: CGSize(width: 320, height: 240), seconds: 2)
        let camera = try #require(await VideoImportedCamera.read(url, offset: 0.4))
        #expect(camera.width == 320 && camera.height == 240)
        #expect(abs(camera.duration - 2) < 0.05)
        #expect(camera.offset == 0.4)
        #expect(camera.bookmark != nil)
        #expect(await VideoImportedCamera.read(folder.appendingPathComponent("nothing.mp4")) == nil)
    }

    @Test func theBubbleShowsOnlyWhileTheFootageRuns() async throws {
        let folder = try Self.folder()
        let url = folder.appendingPathComponent("phone.mp4")
        try await TestVideos.writeQuadrants(to: url, size: CGSize(width: 160, height: 120), seconds: 1)
        var project = VideoDemoProject.make(sourceURL: folder.appendingPathComponent("screen.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        project.webcam.visible = true
        project.importedCamera = camera(at: url, offset: 1, duration: 1.5)
        let plan = VideoRenderPlan(project: project, sourceDuration: 4, artwork: VideoCursorArtwork(metadata: nil), pointPixelScale: 2, cursorTrack: nil, camera: .identity, hasWebcam: true)
        #expect(!plan.hasCameraFootage(at: 0.5))
        #expect(plan.hasCameraFootage(at: 1.5))
        #expect(plan.hasCameraFootage(at: 2.4))
        #expect(!plan.hasCameraFootage(at: 3))
        // Before the recording: what's left of it shows from the start.
        project.importedCamera?.offset = -0.5
        let early = VideoRenderPlan(project: project, sourceDuration: 4, artwork: VideoCursorArtwork(metadata: nil), pointPixelScale: 2, cursorTrack: nil, camera: .identity, hasWebcam: true)
        #expect(early.hasCameraFootage(at: 0.2))
        #expect(!early.hasCameraFootage(at: 1.5))
        // Gone from disk: no bubble.
        try FileManager.default.removeItem(at: url)
        project.importedCamera?.bookmark = nil
        let missing = VideoRenderPlan(project: project, sourceDuration: 4, artwork: VideoCursorArtwork(metadata: nil), pointPixelScale: 2, cursorTrack: nil, camera: .identity, hasWebcam: true)
        #expect(!missing.hasCameraFootage(at: 0.2))
    }

    @Test func undoNamesTheChange() {
        let base = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/screen.mp4"), duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        var added = base
        added.importedCamera = VideoImportedCamera(path: "/tmp/a.mov", bookmark: nil, offset: 0, width: 1, height: 1, duration: 1)
        var nudged = added
        nudged.importedCamera?.offset = 0.1
        var replaced = added
        replaced.importedCamera?.path = "/tmp/b.mov"
        #expect(VideoEditDescription.describe(from: base, to: added) == "Add Camera Video")
        #expect(VideoEditDescription.describe(from: added, to: nudged) == "Camera Offset")
        #expect(VideoEditDescription.describe(from: added, to: replaced) == "Replace Camera Video")
        #expect(VideoEditDescription.describe(from: added, to: base) == "Remove Camera Video")
        for name in ["Add Camera Video", "Replace Camera Video", "Remove Camera Video", "Camera Offset"] {
            #expect(VideoEditDescription.commands(for: name) != nil, "\(name) has undo and redo titles")
        }
    }

    // MARK: Project files

    @Test func projectFilesCarryTheFootage() async throws {
        try TestVideos.isolateStorage()
        let folder = try Self.folder()
        let screen = folder.appendingPathComponent("screen.mp4"), phone = folder.appendingPathComponent("phone.mp4")
        try await TestVideos.writeBars(to: screen, size: CGSize(width: 320, height: 180), seconds: 1)
        try await TestVideos.writeQuadrants(to: phone, size: CGSize(width: 160, height: 120), seconds: 1)
        var project = VideoDemoProject.make(sourceURL: screen, duration: 1, sourceSize: CGSize(width: 320, height: 180))
        project.importedCamera = camera(at: phone, offset: 0.7)
        let contents = VideoProjectContents(project: project, recording: nil, sourceRecordings: [:])
        #expect(contents.paths.contains(phone.path))

        // Include media: a copy inside, the link to the original dropped.
        let included = folder.appendingPathComponent("Included.shotstyle")
        try VideoProjectPackage.save(contents, to: included, mode: .included)
        try FileManager.default.removeItem(at: phone)
        let opened = try VideoProjectPackage.open(included)
        let inside = try #require(opened.contents.project.importedCamera)
        #expect(inside.path.hasPrefix(included.standardizedFileURL.path))
        #expect(FileManager.default.fileExists(atPath: inside.path))
        #expect(inside.offset == 0.7)
        #expect(inside.bookmark == nil)

        // Link to media: the path stays, and a missing file stays missing.
        let linked = folder.appendingPathComponent("Linked.shotstyle")
        try VideoProjectPackage.save(contents, to: linked, mode: .linked)
        let reopened = try VideoProjectPackage.open(linked)
        #expect(reopened.contents.project.importedCamera?.path == phone.path)
        #expect(reopened.contents.project.importedCamera?.resolved() == nil)
    }
}
