import AVFoundation
import CoreImage
import XCTest
@testable import LFStudiosCore

/// The Library's media (1.13.0): what's in it, importing, dropping on the
/// timeline and the player, folders, names, delete, replace and locate,
/// Extract Audio, and projects that keep working as before.
@MainActor
final class VideoMediaBinTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let directory {
            VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: Helpers

    private func makeModel(seconds: Double = 4) async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: seconds, fps: 30, audioSeconds: seconds)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.isReady)
        return model
    }

    private func picture(_ name: String, color: CIColor = CIColor(red: 1, green: 0, blue: 0)) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let size = CGSize(width: 200, height: 100)
        try VideoTestSupport.writePNG(CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size)), size: size, to: url)
        return url
    }

    private func sound(_ name: String, seconds: Double = 2) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for frame in 0..<Int(frames) { buffer.floatChannelData![0][frame] = Float(sin(Double(frame) / 48_000 * 2 * .pi * 440) * 0.2) }
        try file.write(from: buffer)
        return url
    }

    private func video(_ name: String, seconds: Double = 2) async throws -> URL {
        let url = directory.appendingPathComponent(name)
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 320, height: 200), seconds: seconds, fps: 30, audioSeconds: seconds)
        return url
    }

    // MARK: What's in it

    func testTheVideosOwnMediaIsInTheLibrary() async throws {
        let model = try await makeModel()
        var entries = model.mediaEntries
        XCTAssertEqual(entries.map(\.origin), [.recording])
        XCTAssertEqual(entries[0].kind, .video)
        XCTAssertTrue(entries[0].isInVideo)
        XCTAssertFalse(entries[0].canDelete, "the video's own recording stays")
        XCTAssertNil(model.project.mediaBin, "nothing saved for the Library yet")

        model.addImageOverlay(from: try picture("logo.png"), at: 0)
        await model.addAudio([try sound("voice.wav")], at: 1)
        entries = model.mediaEntries
        XCTAssertEqual(entries.map(\.kind), [.video, .audio, .image])
        XCTAssertEqual(entries[1].name, "voice.wav")
        XCTAssertEqual(entries[2].name, "logo.png")
        XCTAssertTrue(entries.allSatisfy(\.isInVideo))
        XCTAssertNil(model.project.mediaBin, "the video's own media needs nothing new in the project")
    }

    func testImportingAddsEachFileOnce() async throws {
        let model = try await makeModel()
        let logo = try picture("logo.png")
        let voice = try sound("voice.wav")
        let notes = directory.appendingPathComponent("notes.txt")
        try "hi".write(to: notes, atomically: true, encoding: .utf8)
        let items = model.importMedia([logo, voice, notes])
        XCTAssertEqual(items.map(\.kind), [.image, .audio])
        XCTAssertNotNil(model.notice, "says what wasn't added")
        XCTAssertEqual(model.importMedia([logo]).map(\.id), [items[0].id], "already there: not added twice")
        XCTAssertEqual(model.project.mediaBin?.imported.count, 2)
        let imported = model.mediaEntries.filter(\.isImported)
        XCTAssertEqual(imported.count, 2)
        XCTAssertTrue(imported.allSatisfy { !$0.isInVideo }, "imported, not in the video")
        XCTAssertEqual(imported.first?.path, logo.standardizedFileURL.resolvingSymlinksInPath().path, "linked where it is, not copied")
        // Nothing to play differently: the video is as it was.
        XCTAssertTrue(model.project.overlayEffects.isEmpty)
        XCTAssertTrue(model.project.audioTracks.isEmpty)
        // One ⌘Z takes the import back.
        model.undo()
        model.undo()
        XCTAssertNil(model.project.mediaBin)

        // A folder: its files, in a Library folder of its name.
        let shoot = directory.appendingPathComponent("Shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: logo, to: shoot.appendingPathComponent("b.png"))
        try FileManager.default.copyItem(at: voice, to: shoot.appendingPathComponent("a.wav"))
        model.importMedia([shoot])
        let folder = try XCTUnwrap(model.project.mediaBin?.folders.first)
        XCTAssertEqual(folder.name, "Shoot")
        XCTAssertEqual(model.mediaEntries.filter { $0.folder == folder.id }.map(\.name), ["a.wav", "b.png"])
    }

    // MARK: Dropping

    func testDroppedFilesLandWhereTheyAreDropped() async throws {
        let model = try await makeModel()
        let logo = try picture("logo.png")
        let voice = try sound("voice.wav")
        let clip = try await video("clip.mov")
        let before = model.timelineDuration
        // Anywhere but the main track: one after another from the drop point.
        await model.placeMedia([logo, voice], at: 1)
        let picture = try XCTUnwrap(model.project.layerItems.first?.item)
        XCTAssertEqual(picture.kind, .image)
        XCTAssertEqual(picture.at, 1, accuracy: 0.001, "the picture starts where it was dropped, on a track above the main track")
        let track = try XCTUnwrap(model.project.audioTracks.first)
        XCTAssertEqual(track.pieces.first?.at ?? -1, picture.end, accuracy: 0.001, "the sound follows it")
        XCTAssertEqual(model.timelineDuration, before, accuracy: 0.01, "nothing on the main track moved")

        // On the main track at 2 s: the clip there splits around the video.
        await model.placeMedia([clip], at: 2, target: .main)
        XCTAssertEqual(model.project.sources.filter { !$0.isPrimary }.map(\.name), ["clip.mov"])
        XCTAssertEqual(model.timelineDuration, before + 2, accuracy: 0.1)
        XCTAssertEqual(model.segments.count, 3, "before it, it, after it")
        XCTAssertEqual(model.segments[1].timelineStart, 2, accuracy: 0.05)
        XCTAssertEqual(model.segments[2].clip.sourceStart, 2, accuracy: 0.05, "the rest of the recording follows")
        model.undo()
        XCTAssertEqual(model.timelineDuration, before, accuracy: 0.01, "one ⌘Z takes the insert back")
        XCTAssertTrue(model.project.sources.filter { !$0.isPrimary }.isEmpty)
        model.redo()

        // On a given track above the main track, and on top of everything.
        await model.placeMedia([logo], at: 1, target: .layer(.newTrack(model.project.layerTracks.count)))
        XCTAssertEqual(model.project.layerTracks.count, 2)
        XCTAssertEqual(model.project.layerTracks[1].items.first?.at ?? 0, 1, accuracy: 0.001)

        // Each shows once in the Library, as the import, marked Added.
        let entries = model.mediaEntries
        XCTAssertEqual(entries.filter { $0.name == "logo.png" }.count, 1)
        XCTAssertEqual(entries.filter { $0.name == "voice.wav" }.count, 1)
        XCTAssertEqual(entries.filter { $0.name == "clip.mov" }.count, 1)
        XCTAssertTrue(entries.filter(\.isImported).allSatisfy(\.isInVideo))
    }

    func testAPictureOnTheMainTrackBecomesAStillVideo() async throws {
        let model = try await makeModel()
        let before = model.timelineDuration
        await model.placeMedia([try picture("slide.png")], at: model.timelineDuration, target: .main)
        let added = try XCTUnwrap(model.project.sources.first { !$0.isPrimary })
        XCTAssertEqual(added.name, "slide.png", "named after the picture")
        XCTAssertTrue(VideoGeneratedMedia.isGenerated(added.path), "a video LF Studios made")
        XCTAssertEqual(added.duration, VideoLayerItem.pictureLength, accuracy: 0.1)
        XCTAssertEqual(model.timelineDuration, before + VideoLayerItem.pictureLength, accuracy: 0.1, "at the end, where it was dropped")
    }

    func testDraggedFilesArriveInOrder() async throws {
        let a = try picture("a.png")
        let b = try sound("b.wav")
        let urls = await VideoMediaDrop.urls(from: [NSItemProvider(object: a as NSURL), NSItemProvider(object: b as NSURL)])
        XCTAssertEqual(urls.map(\.lastPathComponent), ["a.png", "b.wav"])
        XCTAssertEqual(VideoMediaKind.of(a), .image)
        XCTAssertEqual(VideoMediaKind.of(b), .audio)
        XCTAssertEqual(VideoMediaKind.of(URL(fileURLWithPath: "/x/clip.mov")), .video)
        XCTAssertEqual(VideoMediaKind.of(URL(fileURLWithPath: "/x/clip.mp4")), .video)
        XCTAssertNil(VideoMediaKind.of(URL(fileURLWithPath: "/x/notes.txt")))
    }

    // MARK: Finding, names, folders

    func testSortingSearchingAndFolders() {
        let folder = UUID()
        func entry(_ name: String, _ kind: VideoMediaKind, duration: Double?, added: TimeInterval?, folder: UUID? = nil) -> VideoMediaEntry {
            VideoMediaEntry(key: name, path: "/m/\(name)", name: name, ownName: name, kind: kind, origin: added == nil ? .picture : .imported(UUID()),
                            duration: duration, added: added.map { Date(timeIntervalSince1970: $0) }, isInVideo: added == nil, folder: folder, isMissing: false)
        }
        let all = [
            entry("rec.mov", .video, duration: 30, added: nil),
            entry("b roll.mov", .video, duration: 60, added: 100),
            entry("Logo.png", .image, duration: nil, added: 200),
            entry("theme.m4a", .audio, duration: 90, added: 50, folder: folder),
        ]
        func names(_ kinds: Set<VideoMediaKind> = Set(VideoMediaKind.allCases), folder: UUID? = nil, flat: Bool = false, query: String = "", sort: VideoMediaSort) -> [String] {
            VideoMediaArrangement.entries(all, kinds: kinds, folder: folder, flat: flat, query: query, sort: sort).map(\.name)
        }
        XCTAssertEqual(names(sort: .added), ["rec.mov", "Logo.png", "b roll.mov"], "the video's own first, then newest imports; not what's in a folder")
        XCTAssertEqual(names(sort: .name), ["b roll.mov", "Logo.png", "rec.mov"])
        XCTAssertEqual(names(sort: .duration), ["b roll.mov", "rec.mov", "Logo.png"])
        XCTAssertEqual(names(sort: .kind), ["b roll.mov", "rec.mov", "Logo.png"])
        XCTAssertEqual(names(folder: folder, sort: .name), ["theme.m4a"])
        XCTAssertEqual(names(query: "THEME", sort: .name), ["theme.m4a"], "searching looks in every folder")
        XCTAssertEqual(names([.audio], flat: true, sort: .name), ["theme.m4a"], "the Audio tab: sound, no folders")
    }

    func testRenamingAndFoldersAreTheLibrarysOwn() async throws {
        let model = try await makeModel()
        let logo = try picture("logo.png")
        model.addImageOverlay(from: logo, at: 0)
        model.importMedia([try sound("voice.wav")])
        var entries = model.mediaEntries
        let picture = try XCTUnwrap(entries.first { $0.kind == .image })
        let voice = try XCTUnwrap(entries.first { $0.kind == .audio })
        model.renameMedia(picture, to: "Brand mark")
        let folder = model.newMediaFolder(named: "Sound")
        model.moveMedia(voice, to: folder)
        entries = model.mediaEntries
        XCTAssertEqual(entries.first { $0.kind == .image }?.name, "Brand mark")
        XCTAssertEqual(model.project.overlayEffects.first?.image?.name, "logo.png", "the file keeps its own name")
        XCTAssertEqual(entries.first { $0.kind == .audio }?.folder, folder)
        // Back to its file's name: nothing kept.
        model.renameMedia(entries.first { $0.kind == .image }!, to: "logo.png")
        XCTAssertNil(model.project.mediaBin?.names[picture.key])
        // Deleting a folder puts its media back at the top.
        model.deleteMediaFolder(folder)
        XCTAssertNil(model.mediaEntries.first { $0.kind == .audio }?.folder)
        XCTAssertEqual(model.project.mediaBin?.folders, [])
    }

    // MARK: Delete, replace, locate

    func testDeleteFromProjectTakesItOutOfTheVideoToo() async throws {
        let model = try await makeModel()
        await model.placeMedia([try picture("logo.png"), try sound("voice.wav")], at: 0)
        XCTAssertEqual(model.project.layerItems.count, 1)
        XCTAssertEqual(model.project.audioTracks.count, 1)
        let logo = try XCTUnwrap(model.mediaEntries.first { $0.name == "logo.png" })
        model.deleteMedia(logo)
        XCTAssertTrue(model.project.layerTracks.isEmpty, "out of the video")
        XCTAssertNil(model.mediaEntries.first { $0.name == "logo.png" }, "and the Library")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("logo.png").path), "the file stays")
        model.undo()
        XCTAssertEqual(model.project.layerItems.count, 1, "⌘Z brings it back")
        XCTAssertNotNil(model.mediaEntries.first { $0.name == "logo.png" })

        // A sound in the video: its track goes.
        let added = try XCTUnwrap(model.mediaEntries.first { $0.name == "voice.wav" })
        model.deleteMedia(added)
        XCTAssertTrue(model.project.audioTracks.isEmpty)
    }

    func testReplaceAndLocate() async throws {
        let model = try await makeModel()
        let red = try picture("logo.png")
        await model.placeMedia([red], at: 0)
        // The file moves: Missing, and Locate… finds it.
        let moved = directory.appendingPathComponent("moved.png")
        try FileManager.default.moveItem(at: red, to: moved)
        var entry = try XCTUnwrap(model.mediaEntries.first(where: \.isImported))
        XCTAssertTrue(entry.isMissing)
        XCTAssertTrue(entry.canReplace)
        let found = await model.replaceMedia(entry, with: moved)
        XCTAssertTrue(found)
        entry = try XCTUnwrap(model.mediaEntries.first(where: \.isImported))
        XCTAssertFalse(entry.isMissing)
        XCTAssertEqual(entry.path, moved.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertTrue(entry.isInVideo)
        XCTAssertEqual(model.project.layerItems.first?.item.path, entry.path, "the track uses the found file")

        // Replace…: a wider picture on the same spot, same width.
        let wide = directory.appendingPathComponent("wide.png")
        try VideoTestSupport.writePNG(CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 100)), size: CGSize(width: 400, height: 100), to: wide)
        let before = try XCTUnwrap(model.project.layerItems.first?.item)
        let replaced = await model.replaceMedia(entry, with: wide)
        XCTAssertTrue(replaced)
        let after = try XCTUnwrap(model.project.layerItems.first?.item)
        XCTAssertEqual(after.name, "wide.png")
        XCTAssertEqual(after.aspect, 4, accuracy: 0.01)
        XCTAssertEqual(after.width, before.width)
        XCTAssertEqual(after.at, before.at)
        XCTAssertEqual(model.mediaEntries.filter { $0.kind == .image }.count, 1, "still one entry")
        // Another kind doesn't take its place.
        let refused = await model.replaceMedia(try XCTUnwrap(model.mediaEntries.first(where: \.isImported)), with: try sound("voice.wav"))
        XCTAssertFalse(refused)
    }

    // MARK: Extract Audio

    func testExtractAudioPutsTheSoundInTheLibrary() async throws {
        let model = try await makeModel(seconds: 3)
        let recording = try XCTUnwrap(model.mediaEntries.first { $0.origin == .recording })
        let item = try await XCTUnwrapAsync(await model.extractAudio(recording))
        XCTAssertEqual(item.kind, .audio)
        XCTAssertEqual(item.name, "rec (audio).m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
        let length = try await AVURLAsset(url: URL(fileURLWithPath: item.path)).load(.duration).seconds
        XCTAssertEqual(length, 3, accuracy: 0.2)
        let entry = try XCTUnwrap(model.mediaEntries.first { $0.isImported })
        XCTAssertFalse(entry.isInVideo, "in the Library; the video keeps its own sound")
        XCTAssertTrue(model.project.assetPaths.contains(item.path), "Clean Up keeps it")
        XCTAssertTrue(model.project.audioTracks.isEmpty)
    }

    // MARK: Projects

    func testProjectsWithoutTheLibraryStayAsTheyWere() throws {
        let project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 4, sourceSize: CGSize(width: 640, height: 400))
        let json = String(decoding: try JSONEncoder().encode(project), as: UTF8.self)
        XCTAssertFalse(json.contains("mediaBin"), "nothing new written")
        XCTAssertNil(try JSONDecoder().decode(VideoDemoProject.self, from: Data(json.utf8)).mediaBin)
        // An empty Library writes nothing either.
        var empty = project
        empty.mediaBin = VideoMediaBin()
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(empty), as: UTF8.self).contains("mediaBin"))
    }

    func testIncludeMediaCopiesImportedFiles() throws {
        let logo = try picture("logo.png")
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 4, sourceSize: CGSize(width: 640, height: 400))
        var bin = VideoMediaBin()
        let item = VideoMediaItem(path: logo.path, name: "logo.png", kind: .image, added: Date())
        bin.imported = [item]
        bin.names[VideoDemoProject.pathKey(logo.path)] = "A picture's name"
        project.mediaBin = bin
        var contents = VideoProjectContents(project: project, recording: nil, sourceRecordings: [:])
        XCTAssertTrue(contents.paths.contains(logo.path), "saved with the project's media")
        XCTAssertTrue(contents.kindedPaths.contains { $0.path == logo.path && $0.kind == .graphic })
        contents.mapPaths { path in path == logo.path ? "/copied/logo.png" : path }
        XCTAssertEqual(contents.project.mediaBin?.imported.first?.path, "/copied/logo.png")
        XCTAssertEqual(contents.project.mediaBin?.names[VideoDemoProject.pathKey("/copied/logo.png")], "A picture's name", "names follow their file")

        // Saved with Include media and opened again: the copy inside.
        let package = directory.appendingPathComponent("Demo.lfs")
        try VideoProjectPackage.save(VideoProjectContents(project: project, recording: nil, sourceRecordings: [:]), to: package, mode: .included)
        let opened = try VideoProjectPackage.open(package)
        let path = try XCTUnwrap(opened.contents.project.mediaBin?.imported.first?.path)
        XCTAssertTrue(path.hasPrefix(package.standardizedFileURL.path + "/"), path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }
}

private func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let unwrapped = try await value()
    return try XCTUnwrap(unwrapped, file: file, line: line)
}
