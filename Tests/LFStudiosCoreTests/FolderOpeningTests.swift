import AVFoundation
import XCTest
@testable import LFStudiosCore

/// Opening a whole folder (VideoFolderOpener.swift): telling the kinds
/// apart, an older Creative Handoff rebuilt from its files, any other folder
/// imported by role — and the folder left exactly as it was until Save.
@MainActor
final class FolderOpeningTests: XCTestCase {
    private var base: URL!
    private var suiteName: String!

    override func setUp() async throws {
        _ = NSApplication.shared
        VideoTestStorage.isolate()
        suiteName = "LFStudiosCoreTests.FolderOpening.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        base = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-folder-opening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
    }

    private func write(_ text: String, _ relative: String, in folder: URL) throws {
        let url = folder.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func video(_ relative: String, in folder: URL, seconds: Double = 4, sound: Bool = true) async throws -> URL {
        let url = folder.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: seconds, audioSeconds: sound ? seconds : nil)
        return url
    }

    /// A Creative Handoff as LF Studios 1.5 wrote it: full originals, lined
    /// up, no project file; the edit cut out 1–2 s and sped the rest up 2×.
    private func oldHandoff() async throws -> URL {
        let folder = base.appendingPathComponent("Demo – Handoff 2026-10-28", isDirectory: true)
        let screen = try await video("01 Screen/Demo.mp4", in: folder)
        _ = try await video("02 Camera/Camera.mov", in: folder, sound: false)
        try write("RIFF", "03 Audio/System Audio.wav", in: folder)
        try write("RIFF", "03 Audio/Full Mix.wav", in: folder)
        try write("""
        Demo — Creative Handoff
        Made with LF Studios 1.5.0 on 2026-10-28 18:46.

        Clips: the full original recordings, uncut.
        Not lined up: each file is only as long as its content; "starts at" says where it belongs.
        Times are on the recordings' clock (the first recording starts at 0:00).

        FILES

        01 Screen/Demo.mp4
          Screen recording “Demo.mp4”, uncut
          length 0:04.00 · 30 fps · starts at 0:00.00 · untouched original

        02 Camera/Camera.mov
          The camera video, uncut
          length 0:04.00 · 30 fps · starts at 0:00.40 · untouched original
        """, "README.txt", in: folder)
        let src = screen.absoluteString
        try write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10">
          <resources>
            <format id="r1" frameDuration="1/30s" width="640" height="400"/>
            <asset id="r2" name="Demo.mp4" start="0s" duration="120/30s" hasVideo="1" hasAudio="0" format="r1">
              <media-rep kind="original-media" src="file:///Somewhere/else/Demo%20%E2%80%93%20Handoff/01%20Screen/Demo.mp4"/>
            </asset>
          </resources>
          <library><event name="Demo – Handoff"><project name="Demo">
            <sequence format="r1" duration="60/30s" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
              <spine>
                <gap name="Gap" offset="0s" start="0s" duration="60/30s">
                  <asset-clip ref="r2" lane="1" offset="30/30s" name="Demo.mp4" start="60/30s" duration="30/30s">
                    <timeMap>
                      <timept time="60/30s" value="60/30s" interp="linear"/>
                      <timept time="90/30s" value="120/30s" interp="linear"/>
                    </timeMap>
                  </asset-clip>
                  <asset-clip ref="r2" lane="1" offset="0s" name="Demo.mp4" start="0s" duration="30/30s"/>
                  <marker start="45/30s" duration="1/30s" value="Second part"/>
                </gap>
              </spine>
            </sequence>
          </project></event></library>
        </fcpxml>
        """, "Timeline.fcpxml", in: folder)
        _ = src
        try write("1\n00:00:00,200 --> 00:00:00,800\nHello\n\n2\n00:00:02,500 --> 00:00:03,500\nWorld\n", "05 Captions/Captions.srt", in: folder)
        try write("1\n00:00:00,200 --> 00:00:00,800\nHola\n\n2\n00:00:02,500 --> 00:00:03,500\nMundo\n", "05 Captions/Captions.es.srt", in: folder)
        try write("""
        {"about": "", "duration": 4, "pointer": [{"time": 0, "editTime": 0, "x": 0.1, "y": 0.2}, {"time": 1, "editTime": 1, "x": 0.5, "y": 0.5}],
         "clicks": [{"time": 0.5, "editTime": 0.5, "x": 0.3, "y": 0.4, "button": "left", "pressDuration": 0.1}],
         "keys": [{"time": 2.5, "editTime": 1.25, "keys": ["⌘", "C"]}]}
        """, "07 Data/Pointer, clicks and keys.json", in: folder)
        return folder
    }

    /// Every file's size, date, and extended attributes: a folder that
    /// "didn't change" has the same.
    private func snapshot(_ folder: URL) -> [String: String] {
        var result: [String: String] = [:]
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return [:] }
        for case let item as URL in items {
            let values = try? item.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let attributes = item.withUnsafeFileSystemRepresentation { path -> String in
                guard let path else { return "" }
                var buffer = [CChar](repeating: 0, count: 4096)
                let length = listxattr(path, &buffer, buffer.count, XATTR_NOFOLLOW)
                return length > 0 ? String(cString: buffer) : ""
            }
            result[item.path] = "\(values?.fileSize ?? -1) \(values?.contentModificationDate?.timeIntervalSince1970 ?? 0) \(attributes)"
        }
        return result
    }

    /// The project a folder opens, as a real path (nil: not a project folder).
    private func kindPath(_ folder: URL) -> String? {
        if case .project(let url) = VideoFolderReader.kind(of: folder) { return url.resolvingSymlinksInPath().path }
        return nil
    }

    // MARK: Telling folders apart

    func testEachKindOfFolderIsRecognised() async throws {
        let handoff = try await oldHandoff()
        XCTAssertEqual(VideoFolderReader.kind(of: handoff), .handoff)
        let plain = base.appendingPathComponent("Some footage", isDirectory: true)
        _ = try await video("clip.mov", in: plain)
        XCTAssertEqual(VideoFolderReader.kind(of: plain), .other)
        // With a project in it, the project opens.
        let project = handoff.appendingPathComponent("Demo.lfstudios", isDirectory: true)
        let contents = VideoProjectContents(project: VideoDemoProject.fresh(sourceURL: handoff.appendingPathComponent("01 Screen/Demo.mp4")), recording: nil, sourceRecordings: [:])
        try VideoProjectPackage.save(contents, to: project, mode: .folder, folder: .init(kind: .handoff))
        XCTAssertEqual(kindPath(handoff), project.resolvingSymlinksInPath().path)
        XCTAssertTrue(VideoFolderReader.isFolder(handoff))
        XCTAssertFalse(VideoFolderReader.isFolder(project), "a project is a file, not a folder to look into")
    }

    // MARK: An older handoff, rebuilt

    func testAnOlderHandoffIsRebuiltFromItsFiles() async throws {
        let folder = try await oldHandoff()
        let (contents, summary) = try await VideoHandoffRebuilder.rebuild(folder)
        let project = contents.project
        XCTAssertEqual(project.sourceURL.lastPathComponent, "Demo.mp4")
        // The cuts and the speed-up, in edit order.
        XCTAssertEqual(project.timelineClips.count, 2)
        XCTAssertEqual(project.timelineClips[0].sourceStart, 0, accuracy: 0.01)
        XCTAssertEqual(project.timelineClips[0].sourceEnd, 1, accuracy: 0.01)
        XCTAssertEqual(project.timelineClips[1].sourceStart, 2, accuracy: 0.01)
        XCTAssertEqual(project.timelineClips[1].sourceEnd, 4, accuracy: 0.01)
        XCTAssertEqual(project.timelineClips[1].speed, 2, accuracy: 0.01)
        // The camera at its offset (README: it starts 0.4 s in).
        XCTAssertEqual(project.importedCamera?.offset ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(project.importedCamera.map { URL(fileURLWithPath: $0.path).lastPathComponent }, "Camera.mov")
        // The marker at 1.5 s of the edit is 3 s into the recording (2 s + 0.5 s × 2).
        XCTAssertEqual(project.markers.map(\.name), ["Second part"])
        XCTAssertEqual(project.markers.first?.time ?? 0, 3, accuracy: 0.05)
        // Captions on the recording's clock, with their translation.
        XCTAssertEqual(project.captions.map(\.text), ["Hello", "World"])
        XCTAssertEqual(project.captions.last?.start ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(project.captionTracks.translations.first?.language, "es")
        XCTAssertEqual(project.captionTracks.translations.first?.lines.map(\.text), ["Hola", "Mundo"])
        // Pointer, clicks, and keys.
        XCTAssertEqual(contents.recording?.cursorSamples.count, 2)
        XCTAssertEqual(project.clickEvents.count, 1)
        XCTAssertEqual(project.keystrokes.first?.keys, ["⌘", "C"])
        XCTAssertEqual(contents.recording?.shouldRenderCursor, true)
        // The screen has its own sound: the separate WAVs aren't needed, the full mix never is.
        XCTAssertFalse(summary.notLoaded.contains { $0.contains("System Audio.wav") || $0.contains("Full Mix") }, "\(summary.notLoaded)")
        XCTAssertTrue(summary.loaded.contains { $0.contains("Cuts") })
        XCTAssertTrue(summary.notLoaded.contains { $0.contains("Zooms") }, "says what older handoffs don't have")
    }

    func testReadmeAndTimelineFactsAreRead() {
        let facts = VideoHandoffReadmeFacts.parse("""
        X — Creative Handoff

        Clips: trimmed to the edit (cuts, clip order, and speed changes are in the files).
        Lined up: every video and sound file starts at 0:00 and is 1:02:03.50 long.

        FILES

        02 Camera/Camera.mov
          The camera
          length 0:04.00 · 30 fps · starts at 1:05.25 · untouched original
        """)
        XCTAssertTrue(facts.trimmed)
        XCTAssertTrue(facts.linedUp)
        XCTAssertEqual(facts.starts["02 Camera/Camera.mov"] ?? 0, 65.25, accuracy: 0.001)
        XCTAssertEqual(VideoHandoffTimelineFacts.time("1359/53s") ?? 0, 1359.0 / 53, accuracy: 0.0001)
        XCTAssertEqual(VideoHandoffTimelineFacts.time("3s"), 3)
        XCTAssertNil(VideoHandoffTimelineFacts.time("3"))
        XCTAssertEqual(VideoSubtitleReader.srt("1\r\n00:01:02,500 --> 00:01:03,000\r\nHi\r\nthere\r\n").first, .init(start: 62.5, end: 63, text: "Hi\nthere"))
    }

    // MARK: Any other folder

    func testAnyOtherFolderIsImportedByRole() async throws {
        let folder = base.appendingPathComponent("Shoot", isDirectory: true)
        let screen = try await video("Screen capture.mov", in: folder, seconds: 4)
        let camera = try await video("Phone/IMG_0001.mov", in: folder, seconds: 3, sound: false)
        try write("RIFF", "voice.wav", in: folder)
        let files = VideoFolderReader.mediaFiles(in: folder)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), ["Screen capture.mov", "IMG_0001.mov", "voice.wav"])
        var choices = VideoFolderImportChoice.suggested(files.map { ($0, $0 == screen.standardizedFileURL ? 4 : ($0 == camera.standardizedFileURL ? 3 : 10), VideoFolderReader.videoExtensions.contains($0.pathExtension.lowercased())) })
        XCTAssertEqual(choices.first { $0.url == screen.standardizedFileURL }?.role, .screen, "the longest video is the screen")
        XCTAssertEqual(choices.first { $0.url == camera.standardizedFileURL }?.role, .camera)
        XCTAssertEqual(choices.first { $0.url.lastPathComponent == "voice.wav" }?.role, .ignore)
        let index = try XCTUnwrap(choices.firstIndex { $0.role == .camera })
        choices[index].offset = 1.5
        let contents = try await VideoFolderImportChoice.build(choices)
        XCTAssertEqual(contents.project.sourceURL.standardizedFileURL, screen.standardizedFileURL)
        XCTAssertEqual(contents.project.importedCamera?.offset, 1.5)
        XCTAssertTrue(contents.project.webcam.visible)
        // Without a screen there's nothing to open.
        choices = choices.map { var choice = $0; choice.role = .ignore; return choice }
        do {
            _ = try await VideoFolderImportChoice.build(choices)
            XCTFail("opened without a screen recording")
        } catch {}
    }

    // MARK: Nothing changes until Save

    func testOpeningAFolderChangesNothingInItUntilSave() async throws {
        let folder = try await oldHandoff()
        let before = snapshot(folder)
        let (contents, _) = try await VideoHandoffRebuilder.rebuild(folder)
        VideoFileIdentity.protect(folder)
        defer { VideoFileIdentity.unprotect(folder) }
        let package = folder.appendingPathComponent("Demo – Handoff 2026-10-28.lfstudios", isDirectory: true)
        let document = VideoProjectDocument(savedAt: .distantPast, mediaMode: .folder, project: contents.project, recording: contents.recording, folder: .init(kind: .opened))
        let primary = try XCTUnwrap(VideoProjectOpener.prepare(VideoProjectPackage.Opened(document: document, contents: contents, package: package, fontFiles: [])))
        let model = VideoEditorModel(videoURL: primary)
        model.projectFileURL = package
        model.projectMediaMode = .folder
        model.projectFolder = .init(kind: .opened)
        await model.load()
        XCTAssertTrue(model.isReady)
        XCTAssertEqual(model.project.captions.count, 2, "the rebuilt edit is what opens")
        model.mutate(label: "Add Caption") { $0.captions[0].text = "Changed" }
        model.saveDraftNow()
        await model.recordingFolderWrite?.value
        XCTAssertEqual(snapshot(folder), before, "no file written, changed, or stamped")
        XCTAssertNil(VideoFileIdentity.stampedID(of: primary))

        // Save writes the project there, holding the edit.
        try VideoProjectPackage.save(model.projectContents, to: package, mode: .folder, folder: .init(kind: .opened))
        let saved = try VideoProjectPackage.open(package)
        XCTAssertEqual(saved.contents.project.captions.first?.text, "Changed")
        XCTAssertEqual(saved.contents.project.importedCamera?.path, folder.appendingPathComponent("02 Camera/Camera.mov").standardizedFileURL.path)
        XCTAssertEqual(kindPath(folder), package.resolvingSymlinksInPath().path)
    }
}
