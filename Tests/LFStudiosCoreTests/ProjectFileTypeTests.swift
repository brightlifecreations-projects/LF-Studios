import AppKit
import XCTest
@testable import LFStudiosCore

/// `.lfsp` projects and `.lfss` styles (1.9.0), and the older names that
/// still open: new files get the new names, users' files are never renamed.
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

    func testNewFilesGetTheNewNames() {
        XCTAssertEqual(VideoProjectDocument.fileExtension, "lfsp")
        XCTAssertEqual(VideoProjectDocument.typeIdentifier, "com.lfstudios.lfsp")
        XCTAssertEqual(VideoStylePresetFile.fileExtension, "lfss")
        XCTAssertEqual(VideoStylePresetFile.typeIdentifier, "com.lfstudios.style")
        XCTAssertEqual(VideoProjectDocument.openableExtensions, ["lfsp", "lfstudios", "shotstyle"])
        XCTAssertEqual(VideoStylePresetFile.openableExtensions, ["lfss", "lfstudiospresets", "shotstylepresets"])
    }

    func testSaveProjectAsAlwaysMakesALfsp() {
        let video = URL(fileURLWithPath: "/Movies/Demo.mp4")
        XCTAssertEqual(VideoProjectDocument.saveAsName(current: nil, source: video), "Demo.lfsp")
        XCTAssertEqual(VideoProjectDocument.saveAsName(current: URL(fileURLWithPath: "/Projects/Old.lfstudios"), source: video), "Old.lfsp")
        XCTAssertEqual(VideoProjectDocument.saveAsName(current: URL(fileURLWithPath: "/Projects/Older.shotstyle"), source: video), "Older.lfsp")
        XCTAssertEqual(VideoProjectDocument.saveAsURL(URL(fileURLWithPath: "/Projects/New.lfsp")).lastPathComponent, "New.lfsp")
        XCTAssertEqual(VideoProjectDocument.saveAsURL(URL(fileURLWithPath: "/Projects/New")).lastPathComponent, "New.lfsp")
        XCTAssertEqual(VideoProjectDocument.saveAsURL(URL(fileURLWithPath: "/Projects/Old.lfstudios")).lastPathComponent, "Old.lfstudios.lfsp")
    }

    // MARK: Opening

    func testOldAndNewProjectsOpen() async throws {
        let video = try await fakeVideo(in: base)
        for ext in ["lfsp", "lfstudios", "shotstyle"] {
            let package = base.appendingPathComponent("Demo.\(ext)", isDirectory: true)
            try VideoProjectPackage.save(contents(video), to: package, mode: .linked)
            let opened = try VideoProjectPackage.open(package)
            XCTAssertEqual(opened.contents.project.sourcePath, video.path, ".\(ext) opens")
        }
    }

    func testAFolderFindsAProjectOfEitherName() async throws {
        for ext in ["lfsp", "lfstudios", "shotstyle"] {
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

    // MARK: Saving never renames

    func testSaveKeepsAnOlderProjectsNameAndExtension() async throws {
        let video = try await fakeVideo(in: base)
        let old = base.appendingPathComponent("Old.lfstudios", isDirectory: true)
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

        XCTAssertEqual(model.projectFileURL, old, "still the .lfstudios")
        XCTAssertEqual(try VideoProjectPackage.open(old).contents.project.captions.first?.text, "Saved again")
        XCTAssertEqual(files(in: base), ["Demo.mp4", "Old.lfstudios"], "no .lfsp next to it")
    }

    func testAnOlderRecordingFolderKeepsItsLfstudios() async throws {
        let folder = base.appendingPathComponent("Demo", isDirectory: true)
        let video = try await fakeVideo(in: folder.appendingPathComponent("01 Screen", isDirectory: true))
        let old = folder.appendingPathComponent("Demo.lfstudios", isDirectory: true)
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
        XCTAssertFalse(files(in: folder).contains("Demo.lfsp"), "the folder's project isn't renamed or doubled")
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
        for type in ["com.lfstudios.lfsp", "com.lfstudios.project", "com.shotstyle.project", "com.lfstudios.style", "com.lfstudios.presets", "com.shotstyle.presets"] {
            XCTAssertTrue(opened.contains(type), "\(type) opens by double-click")
        }
        let lfsp = try XCTUnwrap(documents.first { ($0["LSItemContentTypes"] as? [String])?.contains("com.lfstudios.lfsp") == true })
        XCTAssertEqual(lfsp["CFBundleTypeRole"] as? String, "Editor")
        XCTAssertEqual(lfsp["LSTypeIsPackage"] as? Bool, true, "a .lfsp shows as one file")

        let declared = (plist["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []) + (plist["UTImportedTypeDeclarations"] as? [[String: Any]] ?? [])
        func declaration(_ identifier: String) -> (extensions: [String], conforms: [String])? {
            guard let type = declared.first(where: { $0["UTTypeIdentifier"] as? String == identifier }) else { return nil }
            let tags = type["UTTypeTagSpecification"] as? [String: Any]
            return (tags?["public.filename-extension"] as? [String] ?? [], type["UTTypeConformsTo"] as? [String] ?? [])
        }
        for (identifier, ext, conforms) in [("com.lfstudios.lfsp", "lfsp", "com.apple.package"), ("com.lfstudios.project", "lfstudios", "com.apple.package"),
                                            ("com.shotstyle.project", "shotstyle", "com.apple.package"), ("com.lfstudios.style", "lfss", "public.json"),
                                            ("com.lfstudios.presets", "lfstudiospresets", "public.json"), ("com.shotstyle.presets", "shotstylepresets", "public.json")] {
            let found = try XCTUnwrap(declaration(identifier), "\(identifier) is declared")
            XCTAssertEqual(found.extensions, [ext], identifier)
            XCTAssertTrue(found.conforms.contains(conforms), identifier)
        }
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
