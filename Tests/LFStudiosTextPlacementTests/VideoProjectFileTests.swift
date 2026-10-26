import AppKit
import Foundation
import Testing
@testable import LFStudiosCore

/// `.lfstudios` project files (VideoProjectDocument.swift, VideoProjectFiles.swift).
@Suite("Project files", .serialized)
struct VideoProjectFileTests {
    /// A scratch folder with every kind of media a project can point at.
    struct Fixture {
        let folder: URL
        let screen: URL
        let camera: URL
        let added: URL
        let music: URL
        let picture: URL
        let background: URL

        var contents: VideoProjectContents {
            var project = VideoDemoProject.make(sourceURL: screen, duration: 1, sourceSize: CGSize(width: 320, height: 180))
            project.captions = [VideoCaptionLine(start: 0.1, end: 0.9, text: "Saved in a project")]
            project.padding = 0.13
            var source = VideoProjectSource(id: UUID(), isPrimary: false, path: added.path, bookmark: nil, name: "added", duration: 1, width: 320, height: 180, offset: 1, audioKinds: [], hasPointer: false, pointPixelScale: nil, webcam: nil)
            source.webcam = VideoWebcamRecording(path: camera.path, offset: 0, width: 160, height: 120)
            project.sources = [source]
            project.music = VideoMusicTrack(path: music.path, name: "music", duration: 1)
            var note = VideoDemoOverlayEffect(kind: .image, time: 0.2)
            note.image = VideoOverlayImage(path: picture.path, name: "logo", aspect: 1)
            project.overlayEffects = [note]
            project.background = .image(background.path)
            var recording = VideoDemoRecordingMetadata(videoURLPath: screen.path, createdAt: Date(), duration: 1, sourceWidth: 320, sourceHeight: 180, fps: 30, nativeCursorVisible: false, cursorSamples: [], clickEvents: [], pointPixelScale: 2, renderCursor: false)
            recording.webcam = VideoWebcamRecording(path: camera.path, offset: 0.1, width: 160, height: 120)
            let addedData = VideoDemoRecordingMetadata(videoURLPath: added.path, createdAt: Date(), duration: 1, sourceWidth: 320, sourceHeight: 180, fps: 30, nativeCursorVisible: false, cursorSamples: [], clickEvents: [], pointPixelScale: 2, renderCursor: false)
            return VideoProjectContents(project: project, recording: recording, sourceRecordings: [source.id.uuidString: addedData])
        }

        static func make() async throws -> Fixture {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-project-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let fixture = Fixture(folder: folder, screen: folder.appendingPathComponent("screen.mp4"), camera: folder.appendingPathComponent("camera.mp4"),
                                  added: folder.appendingPathComponent("added.mp4"), music: folder.appendingPathComponent("music.m4a"),
                                  picture: folder.appendingPathComponent("logo.png"), background: folder.appendingPathComponent("background.png"))
            try await TestVideos.writeBars(to: fixture.screen, size: CGSize(width: 320, height: 180), seconds: 1)
            try await TestVideos.writeQuadrants(to: fixture.camera, size: CGSize(width: 160, height: 120), seconds: 1)
            try await TestVideos.writeBars(to: fixture.added, size: CGSize(width: 320, height: 180), seconds: 1)
            try Data("music".utf8).write(to: fixture.music)
            try Data("logo".utf8).write(to: fixture.picture)
            try Data("background".utf8).write(to: fixture.background)
            return fixture
        }
    }

    // MARK: The manifest

    @Test func theManifestSurvivesSavingAndLoading() throws {
        let project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 2, sourceSize: CGSize(width: 1280, height: 720))
        let document = VideoProjectDocument(appVersion: "1.0.0", mediaMode: .included, project: project, recording: nil)
        let decoded = try VideoProjectDocument.decode(try document.encoded())
        #expect(decoded.project == project)
        #expect(decoded.mediaMode == .included)
        #expect(decoded.version == VideoProjectDocument.currentVersion)
        #expect(!decoded.isFromNewerVersion)
    }

    @Test func otherFilesAreRefused() {
        #expect(throws: VideoProjectDocument.ReadError.notAProject) { try VideoProjectDocument.decode(Data(#"{"format": "something-else"}"#.utf8)) }
        #expect(throws: VideoProjectDocument.ReadError.damaged) { try VideoProjectDocument.decode(Data("not json".utf8)) }
        #expect(throws: VideoProjectDocument.ReadError.damaged) { try VideoProjectDocument.decode(Data(#"{"format": "lfstudios-project", "version": 1}"#.utf8)) }
    }

    @Test func aProjectFromANewerVersionStillOpens() throws {
        let project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 2, sourceSize: CGSize(width: 1280, height: 720))
        var object = try #require(try JSONSerialization.jsonObject(with: VideoProjectDocument(mediaMode: .linked, project: project, recording: nil).encoded()) as? [String: Any])
        object["version"] = VideoProjectDocument.currentVersion + 3
        object["somethingNew"] = ["a": 1]
        let decoded = try VideoProjectDocument.decode(JSONSerialization.data(withJSONObject: object))
        #expect(decoded.isFromNewerVersion)
        #expect(decoded.project.id == project.id)
    }

    @Test func everyMediaPathIsVisited() async throws {
        let fixture = try await Fixture.make()
        var contents = fixture.contents
        let before = Set(contents.paths)
        #expect(before == Set([fixture.screen, fixture.added, fixture.camera, fixture.music, fixture.picture, fixture.background].map(\.path)))
        contents.mapPaths { "X" + $0 }
        #expect(contents.project.sourcePath.hasPrefix("X/"))
        #expect(contents.project.sources[0].webcam?.path.hasPrefix("X/") == true)
        #expect(contents.recording?.webcam?.path.hasPrefix("X/") == true)
        #expect(contents.sourceRecordings.values.allSatisfy { $0.videoURLPath.hasPrefix("X/") })
        guard case .image(let path) = contents.project.background else { Issue.record("background"); return }
        #expect(path.hasPrefix("X/"))
    }

    // MARK: Include media

    @Test func includedMediaTravelsWithTheProject() async throws {
        let fixture = try await Fixture.make()
        let package = fixture.folder.appendingPathComponent("Demo.lfstudios")
        let document = try VideoProjectPackage.save(fixture.contents, to: package, mode: .included)
        #expect(document.project.sourcePath.hasPrefix(VideoProjectDocument.packagePrefix))
        let manifest = try String(contentsOf: VideoProjectPackage.manifestURL(package), encoding: .utf8)
        #expect(!manifest.contains(fixture.folder.path), "nothing in the manifest points outside the package")

        // Another Mac: the originals are gone and the package moved.
        for file in [fixture.screen, fixture.camera, fixture.added, fixture.music, fixture.picture, fixture.background] {
            try FileManager.default.removeItem(at: file)
        }
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-moved-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let moved = elsewhere.appendingPathComponent("Demo.lfstudios")
        try FileManager.default.moveItem(at: package, to: moved)

        let opened = try VideoProjectPackage.open(moved)
        for path in opened.contents.paths {
            #expect(path.hasPrefix(moved.standardizedFileURL.path + "/"), "\(path) inside the moved package")
            #expect(FileManager.default.fileExists(atPath: path), "\(path) exists")
        }
        #expect(opened.contents.project.captions.first?.text == "Saved in a project")
        #expect(opened.contents.project.padding == 0.13)
        #expect(opened.contents.recording?.webcam?.offset == 0.1)
    }

    @Test func savingAgainCopiesOnlyWhatChanged() async throws {
        let fixture = try await Fixture.make()
        let package = fixture.folder.appendingPathComponent("Again.lfstudios")
        try VideoProjectPackage.save(fixture.contents, to: package, mode: .included)
        let packagedScreen = package.appendingPathComponent("Media/screen.mp4")
        let first = try #require(try FileManager.default.attributesOfItem(atPath: packagedScreen.path)[.systemFileNumber] as? Int)

        try VideoProjectPackage.save(fixture.contents, to: package, mode: .included)
        let second = try #require(try FileManager.default.attributesOfItem(atPath: packagedScreen.path)[.systemFileNumber] as? Int)
        #expect(first == second, "an unchanged recording isn't copied again")

        // Music changed, the picture no longer used.
        try Data("new music".utf8).write(to: fixture.music)
        var contents = fixture.contents
        contents.project.overlayEffects = []
        try VideoProjectPackage.save(contents, to: package, mode: .included)
        let media = try FileManager.default.contentsOfDirectory(atPath: package.appendingPathComponent("Media").path)
        #expect(!media.contains("logo.png"), "what nothing uses is removed: \(media)")
        let musicName = try #require(media.first { $0.hasPrefix("music") })
        #expect(try String(contentsOf: package.appendingPathComponent("Media/\(musicName)"), encoding: .utf8) == "new music")
        #expect(media.filter { $0.hasPrefix("music") }.count == 1)
    }

    @Test func packagedRecordingsGetTheirOwnIdentity() async throws {
        let fixture = try await Fixture.make()
        let originalID = VideoFileIdentity.ensureID(of: fixture.screen)
        let package = fixture.folder.appendingPathComponent("Identity.lfstudios")
        try VideoProjectPackage.save(fixture.contents, to: package, mode: .included)
        let copyID = VideoFileIdentity.id(of: package.appendingPathComponent("Media/screen.mp4"))
        #expect(originalID != nil && copyID != nil)
        #expect(originalID != copyID, "the copy's auto-saved edits never mix with the original's")
    }

    @Test func fontsTheProjectUsesArePackaged() async throws {
        try TestFonts.addToLFStudios()
        let fixture = try await Fixture.make()
        var contents = fixture.contents
        contents.project.captionStyle.font = VideoFontChoice(family: TestFonts.family)
        let package = fixture.folder.appendingPathComponent("Fonts.lfstudios")
        try VideoProjectPackage.save(contents, to: package, mode: .included)
        let opened = try VideoProjectPackage.open(package)
        #expect(opened.fontFiles.contains { $0.lastPathComponent.hasPrefix(TestFonts.family) })
        try VideoProjectPackage.save(contents, to: fixture.folder.appendingPathComponent("Linked.lfstudios"), mode: .linked)
        #expect(try VideoProjectPackage.open(fixture.folder.appendingPathComponent("Linked.lfstudios")).fontFiles.isEmpty, "linked projects stay small")
    }

    // MARK: Link to media

    @Test func linkedMediaIsFoundAfterAMove() async throws {
        let fixture = try await Fixture.make()
        let package = fixture.folder.appendingPathComponent("Linked.lfstudios")
        let document = try VideoProjectPackage.save(fixture.contents, to: package, mode: .linked)
        #expect(document.project.sourcePath == fixture.screen.path)
        #expect((try FileManager.default.contentsOfDirectory(atPath: package.appendingPathComponent("Media").path)).isEmpty, "nothing copied")
        let renamed = fixture.folder.appendingPathComponent("screen renamed.mp4")
        try FileManager.default.moveItem(at: fixture.screen, to: renamed)
        let opened = try VideoProjectPackage.open(package)
        #expect(URL(fileURLWithPath: opened.contents.project.sourcePath).standardizedFileURL == renamed.standardizedFileURL)
    }

    // MARK: Opening (auto-saved edits keep working)

    private func withStorage(_ body: () async throws -> Void) async rethrows {
        let previous = VideoStorageLocation.overrideRoot
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-project-storage-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        VideoStorageLocation.overrideRoot = root
        defer { VideoStorageLocation.overrideRoot = previous }
        try await body()
    }

    @MainActor
    @Test func openingHandsTheEditTheEditorAndKeepsNewerUnsavedWork() async throws {
        try await withStorage {
            let fixture = try await Fixture.make()
            let package = fixture.folder.appendingPathComponent("Open.lfstudios")
            try VideoProjectPackage.save(fixture.contents, to: package, mode: .included)
            var opened = try VideoProjectPackage.open(package)
            let primary = try #require(VideoProjectOpener.prepare(opened, ask: { _ in Issue.record("never asked for included media"); return false }))
            #expect(primary.path.hasPrefix(package.standardizedFileURL.path))
            #expect(VideoDemoDraftStore.load(for: primary)?.project.padding == 0.13, "the edit is where the editor reads it")
            #expect(VideoDemoSidecarStore.load(for: primary)?.webcam?.offset == 0.1, "and the recording's data")

            // Edited after saving (autosave), then opened again: the unsaved
            // work wins.
            var edited = opened.contents.project
            edited.padding = 0.3
            try await Task.sleep(nanoseconds: 1_200_000_000)
            #expect(VideoDemoDraftStore.save(edited, for: primary))
            opened = try VideoProjectPackage.open(package)
            VideoProjectOpener.prepare(opened, ask: { _ in false })
            #expect(VideoDemoDraftStore.load(for: primary)?.project.padding == 0.3)
        }
    }

    @MainActor
    @Test func aLinkedProjectAsksWhenTheRecordingWasEditedSince() async throws {
        try await withStorage {
            let fixture = try await Fixture.make()
            let package = fixture.folder.appendingPathComponent("AskLinked.lfstudios")
            try VideoProjectPackage.save(fixture.contents, to: package, mode: .linked)
            var edited = fixture.contents.project
            edited.padding = 0.4
            try await Task.sleep(nanoseconds: 1_200_000_000)
            #expect(VideoDemoDraftStore.save(edited, for: fixture.screen))

            var asked = 0
            VideoProjectOpener.prepare(try VideoProjectPackage.open(package), ask: { _ in asked += 1; return false })
            #expect(asked == 1)
            #expect(VideoDemoDraftStore.load(for: fixture.screen)?.project.padding == 0.13, "the project as saved")

            try await Task.sleep(nanoseconds: 1_200_000_000)
            #expect(VideoDemoDraftStore.save(edited, for: fixture.screen))
            VideoProjectOpener.prepare(try VideoProjectPackage.open(package), ask: { _ in true })
            #expect(VideoDemoDraftStore.load(for: fixture.screen)?.project.padding == 0.4, "the newer edits")
        }
    }

    @MainActor
    @Test func aMissingRecordingDoesntOpen() async throws {
        try await withStorage {
            let fixture = try await Fixture.make()
            let package = fixture.folder.appendingPathComponent("Missing.lfstudios")
            try VideoProjectPackage.save(fixture.contents, to: package, mode: .linked)
            try FileManager.default.removeItem(at: fixture.screen)
            #expect(VideoProjectOpener.prepare(try VideoProjectPackage.open(package)) == nil)
        }
    }

    @Test func recentProjectsAreNewestFirstAndStillThere() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-recents-\(UUID().uuidString)", isDirectory: true)
        let fixture = try await Fixture.make()
        let a = fixture.folder.appendingPathComponent("A.lfstudios"), b = fixture.folder.appendingPathComponent("B.lfstudios")
        try VideoProjectPackage.save(fixture.contents, to: a, mode: .linked)
        try VideoProjectPackage.save(fixture.contents, to: b, mode: .linked)
        VideoProjectRecents.add(a, root: root)
        VideoProjectRecents.add(b, root: root)
        VideoProjectRecents.add(a, root: root)
        #expect(VideoProjectRecents.load(root: root).map(\.lastPathComponent) == ["A.lfstudios", "B.lfstudios"])
        try FileManager.default.removeItem(at: b)
        #expect(VideoProjectRecents.load(root: root).map(\.lastPathComponent) == ["A.lfstudios"])
    }
}

