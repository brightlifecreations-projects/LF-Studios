import AppKit
import XCTest
@testable import LFStudiosCore

/// `.lfs` projects (1.12.0), `.lfss` styles (1.9.0), and the older names
/// that still open (`.lfsp`, `.lfstudios`, `.shotstyle`): new files get the
/// new names, users' files are never renamed.
@MainActor
final class ProjectFileTypeTests: XCTestCase {
    private var base: URL!
    private var suiteName: String!

    override func setUp() async throws {
        _ = NSApplication.shared
        VideoTestStorage.isolate()
        suiteName = "LFStudiosCoreTests.ProjectFileType.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        base = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-file-types-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
    }

    private func contents(_ video: URL) -> VideoProjectContents {
        VideoProjectContents(project: VideoDemoProject.fresh(sourceURL: video), recording: nil, sourceRecordings: [:])
    }

    private func fakeVideo(in folder: URL, named name: String = "Demo.mp4") async throws -> URL {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 320, height: 200), seconds: 2)
        return url
    }

    private func files(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    // MARK: Names

    /// Every project file name, newest first: what 1.12.0 writes and what
    /// still opens.
    static let projectExtensions = ["lfs", "lfsp", "lfstudios", "shotstyle"]

    func testNewFilesGetTheNewNames() {
        XCTAssertEqual(VideoProjectDocument.fileExtension, "lfs")
        XCTAssertEqual(VideoProjectDocument.typeIdentifier, "com.lfstudios.lfs")
        XCTAssertEqual(VideoProjectDocument.firstVersionOpeningFileExtension, "1.12.0")
        XCTAssertEqual(VideoStylePresetFile.fileExtension, "lfss", "presets keep their name")
        XCTAssertEqual(VideoStylePresetFile.typeIdentifier, "com.lfstudios.style")
        XCTAssertEqual(VideoProjectDocument.openableExtensions, Set(Self.projectExtensions))
        XCTAssertEqual(VideoStylePresetFile.openableExtensions, ["lfss", "lfstudiospresets", "shotstylepresets"])
    }

    func testSaveProjectAsAlwaysMakesALfs() {
        let video = URL(fileURLWithPath: "/Movies/Demo.mp4")
        XCTAssertEqual(VideoProjectDocument.saveAsName(current: nil, source: video), "Demo.lfs")
        XCTAssertEqual(VideoProjectDocument.saveAsName(current: URL(fileURLWithPath: "/Projects/Recent.lfsp"), source: video), "Recent.lfs")
        XCTAssertEqual(VideoProjectDocument.saveAsName(current: URL(fileURLWithPath: "/Projects/Old.lfstudios"), source: video), "Old.lfs")
        XCTAssertEqual(VideoProjectDocument.saveAsName(current: URL(fileURLWithPath: "/Projects/Older.shotstyle"), source: video), "Older.lfs")
        XCTAssertEqual(VideoProjectDocument.saveAsURL(URL(fileURLWithPath: "/Projects/New.lfs")).lastPathComponent, "New.lfs")
        XCTAssertEqual(VideoProjectDocument.saveAsURL(URL(fileURLWithPath: "/Projects/New")).lastPathComponent, "New.lfs")
        XCTAssertEqual(VideoProjectDocument.saveAsURL(URL(fileURLWithPath: "/Projects/Recent.lfsp")).lastPathComponent, "Recent.lfsp.lfs")
    }

    func testANewRecordingFolderWritesALfs() async throws {
        let video = try await fakeVideo(in: base, named: "take.mp4")
        let result = try await VideoRecordingFolderWriter.organize(video: video, into: base, name: "Product demo", root: base.appendingPathComponent("root", isDirectory: true))
        XCTAssertEqual(VideoRecordingFolder.projectFiles(in: result.folder).map(\.lastPathComponent), ["Product demo.lfs"])
        let readme = try String(contentsOf: result.folder.appendingPathComponent("README.txt"), encoding: .utf8)
        XCTAssertTrue(readme.contains("Product demo.lfs"))
        XCTAssertTrue(readme.contains("LF Studios 1.12.0 or later"))
        XCTAssertFalse(readme.contains(".lfsp"))
    }

    // MARK: Opening

    func testEveryNameOpens() async throws {
        let video = try await fakeVideo(in: base)
        for ext in Self.projectExtensions {
            let package = base.appendingPathComponent("Demo.\(ext)", isDirectory: true)
            try VideoProjectPackage.save(contents(video), to: package, mode: .linked)
            let opened = try VideoProjectPackage.open(package)
            XCTAssertEqual(opened.contents.project.sourcePath, video.path, ".\(ext) opens")
            // Double-click and drops go by these names (AppDelegate).
            XCTAssertTrue(VideoProjectDocument.openableExtensions.contains(package.pathExtension.lowercased()), ".\(ext) opens by double-click")
        }
    }

    func testTheOpenPanelTakesEveryName() {
        let types = VideoProjectOpener.openableContentTypes
        for ext in Self.projectExtensions {
            XCTAssertTrue(types.contains { $0.preferredFilenameExtension == ext || $0.tags[.filenameExtension]?.contains(ext) == true }, "Open… takes .\(ext)")
        }
        XCTAssertTrue(types.contains(.folder) && types.contains(.movie))
    }

    func testHomeFindsEveryName() async throws {
        let root = base.appendingPathComponent("root", isDirectory: true)
        let recordings = base.appendingPathComponent("Recordings", isDirectory: true)
        var saved: [URL] = []
        for ext in Self.projectExtensions {
            // A recording's own folder, found where recordings are saved.
            let folder = recordings.appendingPathComponent("Take \(ext)", isDirectory: true)
            let video = try await fakeVideo(in: folder.appendingPathComponent("01 Screen", isDirectory: true))
            try VideoProjectPackage.save(contents(video), to: folder.appendingPathComponent("Take.\(ext)", isDirectory: true), mode: .folder, folder: .init(kind: .recording))
            // And a project saved anywhere, in the recent projects.
            let project = base.appendingPathComponent("Saved.\(ext)", isDirectory: true)
            try VideoProjectPackage.save(contents(video), to: project, mode: .linked)
            VideoProjectRecents.add(project, root: root)
            saved.append(project)
        }
        let found = VideoRecordingFolders.projects(scanning: [recordings], root: root).map(\.pathExtension)
        XCTAssertEqual(Set(found), Set(Self.projectExtensions), "a recording folder of every kind")
        XCTAssertEqual(Set(VideoProjectRecents.load(root: root).map(\.pathExtension)), Set(Self.projectExtensions), "recent projects of every kind")
    }

    func testAFolderFindsAProjectOfEveryName() async throws {
        for ext in Self.projectExtensions {
            let folder = base.appendingPathComponent("Folder \(ext)", isDirectory: true)
            let video = try await fakeVideo(in: folder.appendingPathComponent("01 Screen", isDirectory: true))
            let package = folder.appendingPathComponent("Demo.\(ext)", isDirectory: true)
            try VideoProjectPackage.save(contents(video), to: package, mode: .folder, folder: .init(kind: .opened))
            guard case .project(let found) = VideoFolderReader.kind(of: folder) else { return XCTFail("a folder with a .\(ext) opens its project") }
            XCTAssertEqual(found.resolvingSymlinksInPath().path, package.resolvingSymlinksInPath().path)
            XCTAssertEqual(VideoRecordingFolder.projectFiles(in: folder).map(\.lastPathComponent), ["Demo.\(ext)"])
            XCTAssertFalse(VideoFolderReader.isFolder(package), "a .\(ext) is a file, not a folder to look into")
        }
    }

    /// An older and a newer project file in one folder: the one saved last opens.
    func testAFolderWithAnOldAndANewProjectOpensTheNewest() async throws {
        let folder = base.appendingPathComponent("Both", isDirectory: true)
        let video = try await fakeVideo(in: folder.appendingPathComponent("01 Screen", isDirectory: true))
        let older = folder.appendingPathComponent("Demo.lfsp", isDirectory: true)
        let newer = folder.appendingPathComponent("Demo.lfs", isDirectory: true)
        try VideoProjectPackage.save(contents(video), to: older, mode: .folder, folder: .init(kind: .opened))
        try VideoProjectPackage.save(contents(video), to: newer, mode: .folder, folder: .init(kind: .opened))
        func date(_ url: URL, _ seconds: TimeInterval) throws {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: seconds)], ofItemAtPath: url.path)
        }
        try date(older, -600)
        try date(newer, -60)
        guard case .project(let first) = VideoFolderReader.kind(of: folder) else { return XCTFail("opens a project") }
        XCTAssertEqual(first.lastPathComponent, "Demo.lfs", "the .lfs, saved last")
        // The older one saved again later: it's the newest now.
        try date(older, -10)
        guard case .project(let second) = VideoFolderReader.kind(of: folder) else { return XCTFail("opens a project") }
        XCTAssertEqual(second.lastPathComponent, "Demo.lfsp")
    }

    // MARK: Saving never renames

    func testSaveKeepsAnOlderProjectsNameAndExtension() async throws {
        for ext in ["lfsp", "lfstudios"] {
            try await saveKeepsTheName(ext)
        }
    }

    private func saveKeepsTheName(_ ext: String) async throws {
        let place = base.appendingPathComponent("Save \(ext)", isDirectory: true)
        let video = try await fakeVideo(in: place)
        let old = place.appendingPathComponent("Old.\(ext)", isDirectory: true)
        try VideoProjectPackage.save(contents(video), to: old, mode: .linked)
        let model = VideoEditorModel(videoURL: video)
        model.projectFileURL = old
        model.projectMediaMode = .linked
        await model.load()
        XCTAssertTrue(model.isReady)
        model.mutate(label: "Add Caption") { $0.captions = [VideoCaptionLine(start: 0, end: 1, text: "Saved again")] }

        model.saveProject()
        let deadline = Date().addingTimeInterval(20)
        while model.isSavingProject, Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(model.isSavingProject)

        XCTAssertEqual(model.projectFileURL, old, "still the .\(ext)")
        XCTAssertEqual(try VideoProjectPackage.open(old).contents.project.captions.first?.text, "Saved again")
        XCTAssertEqual(files(in: place), ["Demo.mp4", "Old.\(ext)"], "no .lfs next to it")
    }

    func testAnOlderRecordingFolderKeepsItsOwnProjectFile() async throws {
        for ext in ["lfsp", "lfstudios"] {
            try await recordingFolderKeepsItsFile(ext)
        }
    }

    private func recordingFolderKeepsItsFile(_ ext: String) async throws {
        let folder = base.appendingPathComponent("Demo \(ext)", isDirectory: true)
        let video = try await fakeVideo(in: folder.appendingPathComponent("01 Screen", isDirectory: true))
        let old = folder.appendingPathComponent("Demo.\(ext)", isDirectory: true)
        try VideoProjectPackage.save(contents(video), to: old, mode: .folder, folder: .init(kind: .recording))
        let model = VideoEditorModel(videoURL: video)
        model.projectFileURL = old
        model.projectMediaMode = .folder
        model.projectFolder = .init(kind: .recording)
        await model.load()
        XCTAssertTrue(model.isReady)
        model.mutate(label: "Add Caption") { $0.captions = [VideoCaptionLine(start: 0, end: 1, text: "Kept up to date")] }
        model.updateRecordingFolder()
        await model.recordingFolderWrite?.value

        XCTAssertEqual(try VideoProjectPackage.open(old).contents.project.captions.first?.text, "Kept up to date")
        XCTAssertFalse(files(in: folder).contains("Demo.lfs"), "the folder's project isn't renamed or doubled")
        XCTAssertTrue(files(in: folder).contains("Demo.\(ext)"))
    }

    // MARK: Double-click

    private static var plist: NSDictionary {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return NSDictionary(contentsOf: repo.appendingPathComponent("Info.plist")) ?? [:]
    }

    func testEveryNameIsRegisteredForDoubleClick() throws {
        let plist = Self.plist
        let documents = plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        let opened = Set(documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        for type in ["com.lfstudios.lfs", "com.lfstudios.lfsp", "com.lfstudios.project", "com.shotstyle.project", "com.lfstudios.style", "com.lfstudios.presets", "com.shotstyle.presets"] {
            XCTAssertTrue(opened.contains(type), "\(type) opens by double-click")
        }
        for (type, name) in [("com.lfstudios.lfs", "LF Studios Project"), ("com.lfstudios.lfsp", "LF Studios Project (1.9–1.11)")] {
            let document = try XCTUnwrap(documents.first { ($0["LSItemContentTypes"] as? [String])?.contains(type) == true })
            XCTAssertEqual(document["CFBundleTypeName"] as? String, name)
            XCTAssertEqual(document["CFBundleTypeRole"] as? String, "Editor")
            XCTAssertEqual(document["LSTypeIsPackage"] as? Bool, true, "\(type) shows as one file")
        }

        let declared = (plist["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []) + (plist["UTImportedTypeDeclarations"] as? [[String: Any]] ?? [])
        func declaration(_ identifier: String) -> (extensions: [String], conforms: [String])? {
            guard let type = declared.first(where: { $0["UTTypeIdentifier"] as? String == identifier }) else { return nil }
            let tags = type["UTTypeTagSpecification"] as? [String: Any]
            return (tags?["public.filename-extension"] as? [String] ?? [], type["UTTypeConformsTo"] as? [String] ?? [])
        }
        for (identifier, ext, conforms) in [("com.lfstudios.lfs", "lfs", "com.apple.package"), ("com.lfstudios.lfsp", "lfsp", "com.apple.package"), ("com.lfstudios.project", "lfstudios", "com.apple.package"),
                                            ("com.shotstyle.project", "shotstyle", "com.apple.package"), ("com.lfstudios.style", "lfss", "public.json"),
                                            ("com.lfstudios.presets", "lfstudiospresets", "public.json"), ("com.shotstyle.presets", "shotstylepresets", "public.json")] {
            let found = try XCTUnwrap(declaration(identifier), "\(identifier) is declared")
            XCTAssertEqual(found.extensions, [ext], identifier)
            XCTAssertTrue(found.conforms.contains(conforms), identifier)
        }
        // What Finder calls them.
        let descriptions = Dictionary(uniqueKeysWithValues: declared.compactMap { type in (type["UTTypeIdentifier"] as? String).map { ($0, type["UTTypeDescription"] as? String ?? "") } })
        XCTAssertEqual(descriptions["com.lfstudios.lfs"], "LF Studios Project")
        XCTAssertEqual(descriptions["com.lfstudios.lfsp"], "LF Studios Project (1.9–1.11)")
    }

    // MARK: Styles

    func testAStyleFileOfAnyNameImports() throws {
        let file = VideoStylePresetFile.make([VideoNamedStylePreset(name: "Look", style: .factory)])
        for ext in ["lfss", "lfstudiospresets", "shotstylepresets"] {
            let url = base.appendingPathComponent("Presets.\(ext)")
            try file.encoded().write(to: url)
            XCTAssertTrue(VideoStylePresetFile.openableExtensions.contains(url.pathExtension.lowercased()))
            XCTAssertEqual(try VideoStylePresetFile.read(Data(contentsOf: url)).presets.first?.name, "Look", ".\(ext) imports")
        }
    }
}
