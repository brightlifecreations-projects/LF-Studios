import AppKit
import XCTest
@testable import LFStudiosCore

/// The rename from ShotStyle: data copied over once, old files still open,
/// and scripts that cope with the space in "LF Studios.app".
final class ShotStyleMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var support: URL!

    override func setUp() {
        suiteName = "LFStudiosCoreTests.Migration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        support = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-migration-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: support)
    }

    private var oldFolder: URL { support.appendingPathComponent("ShotStyle", isDirectory: true) }
    private var newFolder: URL { support.appendingPathComponent("LF Studios", isDirectory: true) }

    /// ShotStyle's folder as it is on a Mac that used it: presets pointing
    /// at a copied picture, a draft, a camera movie, fonts, history.
    private func makeShotStyleFolder() throws {
        let fm = FileManager.default
        for sub in ["Presets/Images", "Fonts", "History", "VideoDrafts", "VideoCameras", "VideoMetadata", "Projects"] {
            try fm.createDirectory(at: oldFolder.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
        }
        let picture = oldFolder.appendingPathComponent("Presets/Images/bg.png")
        try Data([1, 2, 3]).write(to: picture)
        // JSONEncoder writes "/" as "\/".
        let escaped = picture.path.replacingOccurrences(of: "/", with: "\\/")
        try Data(#"{"presets":[{"background":{"image":"\#(escaped)"}}]}"#.utf8).write(to: oldFolder.appendingPathComponent("Presets/presets.json"))
        let camera = oldFolder.appendingPathComponent("VideoCameras/rec-1234.mov")
        try Data([9]).write(to: camera)
        try Data(#"{"webcam":{"path":"\#(camera.path)"},"videoURLPath":"/Users/someone/Desktop/ShotStyle 2026-10-01.mp4"}"#.utf8).write(to: oldFolder.appendingPathComponent("VideoMetadata/id-ABC.json"))
        try Data("font".utf8).write(to: oldFolder.appendingPathComponent("Fonts/Brand.ttf"))
        try Data("[]".utf8).write(to: oldFolder.appendingPathComponent("History/index.json"))
        try Data("{}".utf8).write(to: oldFolder.appendingPathComponent("VideoDrafts/id-ABC.json"))
        try Data("[]".utf8).write(to: oldFolder.appendingPathComponent("Projects/recent.json"))
    }

    private let oldSettings: [String: Any] = [
        "appearance": "light",
        "playSounds": false,
        "onboardingCompleted": true,
        "KeyboardShortcuts_captureArea": "{\"carbonKeyCode\":21,\"carbonModifiers\":768}",
        "crashReporterSession": "running",
    ]

    // MARK: Migration

    func testAFreshInstallMovesNothingAndSaysNothing() {
        let result = ShotStyleMigration.runIfNeeded(defaults: defaults, legacySettings: nil, applicationSupport: support)
        XCTAssertNil(result)
        XCTAssertTrue(defaults.bool(forKey: ShotStyleMigration.doneKey), "checked once")
        XCTAssertFalse(defaults.bool(forKey: ShotStyleMigration.noticeKey), "no message")
        XCTAssertFalse(FileManager.default.fileExists(atPath: newFolder.path))
    }

    func testShotStyleDataIsCopiedOverWithItsPathsPointingHere() throws {
        try makeShotStyleFolder()
        let result = try XCTUnwrap(ShotStyleMigration.runIfNeeded(defaults: defaults, legacySettings: oldSettings, applicationSupport: support))

        // Settings, except the old run's own session.
        XCTAssertEqual(result.settings, 4)
        XCTAssertEqual(defaults.string(forKey: "appearance"), "light")
        XCTAssertEqual(defaults.object(forKey: "playSounds") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "KeyboardShortcuts_captureArea"), oldSettings["KeyboardShortcuts_captureArea"] as? String)
        XCTAssertNil(defaults.object(forKey: "crashReporterSession"))

        // Every file, copied.
        XCTAssertTrue(result.copiedFolder)
        for file in ["Presets/presets.json", "Presets/Images/bg.png", "Fonts/Brand.ttf", "History/index.json", "VideoDrafts/id-ABC.json", "VideoCameras/rec-1234.mov", "VideoMetadata/id-ABC.json", "Projects/recent.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: newFolder.appendingPathComponent(file).path), file)
        }
        // Paths into ShotStyle's folder now point into LF Studios' (escaped or not);
        // the user's own recordings stay where they are.
        let presets = try String(contentsOf: newFolder.appendingPathComponent("Presets/presets.json"), encoding: .utf8)
        XCTAssertTrue(presets.contains(newFolder.appendingPathComponent("Presets/Images/bg.png").path.replacingOccurrences(of: "/", with: "\\/")), presets)
        XCTAssertFalse(presets.contains("ShotStyle\\/Presets"), presets)
        let metadata = try String(contentsOf: newFolder.appendingPathComponent("VideoMetadata/id-ABC.json"), encoding: .utf8)
        XCTAssertTrue(metadata.contains(newFolder.appendingPathComponent("VideoCameras/rec-1234.mov").path), metadata)
        XCTAssertTrue(metadata.contains("/Users/someone/Desktop/ShotStyle 2026-10-01.mp4"), "recordings themselves don't move")
        XCTAssertGreaterThanOrEqual(result.rewrittenFiles, 2)

        // Copied, not moved.
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldFolder.appendingPathComponent("Presets/presets.json").path))
        let original = try String(contentsOf: oldFolder.appendingPathComponent("Presets/presets.json"), encoding: .utf8)
        XCTAssertTrue(original.contains("ShotStyle\\/Presets"), "ShotStyle's own copy is untouched")

        // The one-time message.
        XCTAssertTrue(defaults.bool(forKey: ShotStyleMigration.noticeKey))
    }

    func testItHappensOnlyOnce() throws {
        try makeShotStyleFolder()
        XCTAssertNotNil(ShotStyleMigration.runIfNeeded(defaults: defaults, legacySettings: oldSettings, applicationSupport: support))
        defaults.removeObject(forKey: ShotStyleMigration.noticeKey)
        defaults.set("dark", forKey: "appearance")
        try Data("changed later".utf8).write(to: oldFolder.appendingPathComponent("Fonts/Brand.ttf"))

        XCTAssertNil(ShotStyleMigration.runIfNeeded(defaults: defaults, legacySettings: oldSettings, applicationSupport: support), "already migrated")
        XCTAssertEqual(defaults.string(forKey: "appearance"), "dark", "a choice made in LF Studios stays")
        XCTAssertEqual(try String(contentsOf: newFolder.appendingPathComponent("Fonts/Brand.ttf"), encoding: .utf8), "font")
        XCTAssertFalse(defaults.bool(forKey: ShotStyleMigration.noticeKey), "no second message")
    }

    func testLFStudiosOwnDataIsNeverOverwritten() throws {
        try makeShotStyleFolder()
        try FileManager.default.createDirectory(at: newFolder.appendingPathComponent("Presets", isDirectory: true), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: newFolder.appendingPathComponent("Presets/presets.json"))
        XCTAssertNil(ShotStyleMigration.runIfNeeded(defaults: defaults, legacySettings: oldSettings, applicationSupport: support))
        XCTAssertEqual(try String(contentsOf: newFolder.appendingPathComponent("Presets/presets.json"), encoding: .utf8), "mine")
        XCTAssertNil(defaults.object(forKey: "appearance"))
    }

    func testTheMessageShowsOnceAndIsTranslated() {
        XCTAssertNotEqual(L10n.bundle.localizedString(forKey: "Your ShotStyle settings were moved to LF Studios", value: nil, table: nil), "")
        for language in L10n.translations {
            L10n.use(language)
            XCTAssertNotEqual(L("Your ShotStyle settings were moved to LF Studios"), "Your ShotStyle settings were moved to LF Studios", "\(language) translated")
        }
        L10n.use(nil)
    }

    // MARK: Files from ShotStyle

    func testAShotStyleProjectStillOpens() throws {
        VideoTestStorage.isolate()
        let video = support.appendingPathComponent("screen.mp4")
        try Data([0]).write(to: video)
        let project = VideoDemoProject.make(sourceURL: video, duration: 1, sourceSize: CGSize(width: 320, height: 180))
        let package = support.appendingPathComponent("Old.\(VideoProjectDocument.legacyFileExtension)")
        try VideoProjectPackage.save(VideoProjectContents(project: project, recording: nil, sourceRecordings: [:]), to: package, mode: .linked)
        // As ShotStyle wrote it.
        let manifest = VideoProjectPackage.manifestURL(package)
        let text = try String(contentsOf: manifest, encoding: .utf8).replacingOccurrences(of: "\"\(VideoProjectDocument.format)\"", with: "\"shotstyle-project\"")
        XCTAssertTrue(text.contains("shotstyle-project"))
        try text.write(to: manifest, atomically: true, encoding: .utf8)

        let opened = try VideoProjectPackage.open(package)
        XCTAssertEqual(opened.contents.project.sourcePath, video.path)
        XCTAssertTrue(VideoProjectDocument.openableExtensions.contains("shotstyle"))
        XCTAssertTrue(VideoProjectDocument.openableExtensions.contains("lfstudios"))
        XCTAssertEqual(VideoProjectDocument.fileExtension, "lfsp", "new projects save as .lfsp")
    }

    func testShotStylePresetsStillImportWithTheirPictures() throws {
        let picture = support.appendingPathComponent("bg.png")
        try Data([7, 7, 7]).write(to: picture)
        var style = VideoStylePreset.factory
        style.background = .image(picture.path)
        let file = VideoStylePresetFile.make([VideoNamedStylePreset(name: "Old look", style: style)])
        // As ShotStyle wrote it.
        let text = try XCTUnwrap(String(data: try file.encoded(), encoding: .utf8))
            .replacingOccurrences(of: VideoStylePresetFile.kind, with: VideoStylePresetFile.legacyKind)
            .replacingOccurrences(of: VideoStylePresetFile.embeddedPrefix, with: VideoStylePresetFile.legacyEmbeddedPrefix)
        XCTAssertTrue(text.contains("shotstyle-style-presets") && text.contains("shotstyle-embedded:"))

        let read = try VideoStylePresetFile.read(Data(text.utf8))
        let unpacked = read.unpacked(imagesDirectory: support.appendingPathComponent("Images", isDirectory: true))
        XCTAssertEqual(unpacked.first?.name, "Old look")
        guard case .image(let path) = unpacked.first?.style.background else { return XCTFail("the picture came along") }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data([7, 7, 7]))
        XCTAssertEqual(VideoStylePresetFile.fileExtension, "lfss")
        XCTAssertTrue(VideoStylePresetFile.openableExtensions.contains("lfstudiospresets"))
        XCTAssertTrue(VideoStylePresetFile.openableExtensions.contains("shotstylepresets"))
    }

    func testExistingRecordingsKeepTheirIDAttribute() {
        XCTAssertEqual(VideoFileIdentity.attribute, "com.shotstyle.recording-id", "stamped on every recording made so far")
    }

    func testRecordingsNamedShotStyleAreStillFound() throws {
        let folder = support.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["ShotStyle 2026-10-01 at 10.00.00.mp4", "LF Studios 2026-10-28 at 10.00.00.mp4", "holiday.mp4"] {
            try Data([0]).write(to: folder.appendingPathComponent(name))
        }
        let previous = Settings.defaults
        Settings.defaults = defaults
        defer { Settings.defaults = previous }
        Settings.autoSaveLocation = folder.path
        let found = Set(Settings.recordingURLs.map(\.lastPathComponent))
        XCTAssertTrue(found.contains("ShotStyle 2026-10-01 at 10.00.00.mp4"))
        XCTAssertTrue(found.contains("LF Studios 2026-10-28 at 10.00.00.mp4"))
        XCTAssertFalse(found.contains("holiday.mp4"))
    }

    // MARK: The app's name has a space

    private static var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every "LF Studios.app" path in the scripts sits inside quotes, so the
    /// space never splits it in two.
    func testScriptsQuoteThePathsWithASpace() throws {
        let scripts = ["build-app.sh", "scripts/publish-release.sh", "make-dmg.sh", ".github/workflows/release.yml", "scripts/setup-signing.sh"]
        for script in scripts {
            let text = try String(contentsOf: Self.repo.appendingPathComponent(script), encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("#"), let range = code.range(of: "LF Studios.app") else { continue }
                let before = code[..<range.lowerBound]
                let quotes = before.filter { $0 == "\"" }.count
                XCTAssertTrue(quotes % 2 == 1, "\(script):\(number + 1) has an unquoted path: \(code)")
            }
        }
    }

    func testTheBuildScriptsAgreeOnTheNames() throws {
        let build = try String(contentsOf: Self.repo.appendingPathComponent("build-app.sh"), encoding: .utf8)
        XCTAssertTrue(build.contains(#"APP_NAME="LF Studios""#))
        XCTAssertTrue(build.contains(#"PRODUCT="LFStudios""#))
        let plist = try XCTUnwrap(NSDictionary(contentsOf: Self.repo.appendingPathComponent("Info.plist")))
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "LFStudios")
        XCTAssertEqual(plist["CFBundleName"] as? String, "LF Studios")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.lfstudios.app")
        let types = (plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []).flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        for type in ["com.lfstudios.lfsp", "com.lfstudios.project", "com.shotstyle.project", "com.lfstudios.style", "com.lfstudios.presets", "com.shotstyle.presets"] {
            XCTAssertTrue(types.contains(type), "\(type) opens")
        }
        for script in ["scripts/publish-release.sh", ".github/workflows/release.yml"] {
            let text = try String(contentsOf: Self.repo.appendingPathComponent(script), encoding: .utf8)
            XCTAssertTrue(text.contains("LF-Studios.zip"), script)
            XCTAssertTrue(text.contains("MacOS/LFStudios"), "\(script) checks the real executable")
        }
        for script in ["build-app.sh", "scripts/publish-release.sh", "make-dmg.sh", "scripts/setup-signing.sh"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-n", Self.repo.appendingPathComponent(script).path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "\(script) parses")
        }
    }
}
