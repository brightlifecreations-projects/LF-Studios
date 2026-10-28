import XCTest
@testable import LFStudiosCore

final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LFStudiosCoreTests.Settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        Settings.defaults = defaults
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsMatchFreshInstallBehavior() {
        XCTAssertEqual(Settings.overlayTimeout, 6)
        XCTAssertTrue(Settings.overlayOnLeft)
        XCTAssertTrue(Settings.playSounds)
        // Manual only: nothing happens after a capture until it's switched on.
        XCTAssertFalse(Settings.afterCaptureShowOverlay)
        XCTAssertFalse(Settings.afterCaptureCopyToClipboard)
        XCTAssertFalse(Settings.afterCaptureSaveAutomatically)
        XCTAssertEqual(Settings.screenshotFormat, "png")
        XCTAssertEqual(Settings.jpegQuality, 0.95, accuracy: 0.001)
        XCTAssertEqual(Settings.recordingFPS, 60)
        XCTAssertEqual(Settings.recordingQuality, "high")
        XCTAssertTrue(Settings.recordingShowsCursor)
        XCTAssertFalse(Settings.openVideoEditorAfterRecording)
    }

    // MARK: Screenshot folder and recording folder

    private func makeFolder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-folders-\(UUID().uuidString)/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    func testRecordingFolderStartsAsTheFolderRecordingsWentToBefore() throws {
        // A fresh install: both are the Desktop.
        XCTAssertEqual(Settings.recordingFolder, Settings.defaultAutoSaveLocation)
        XCTAssertTrue(Settings.askWhereToSaveRecordings, "asks to start with")
        // Someone who picked a save folder before it was split.
        let old = try makeFolder("Before")
        XCTAssertTrue(Settings.setAutoSaveLocation(old.path))
        XCTAssertEqual(Settings.recordingFolder, old.path)
        Settings.migrateRecordingFolderIfNeeded()
        // From now on they're separate: a new screenshot folder doesn't move recordings.
        let screenshots = try makeFolder("Screenshots")
        XCTAssertTrue(Settings.setAutoSaveLocation(screenshots.path))
        XCTAssertEqual(Settings.autoSaveLocation, screenshots.path)
        XCTAssertEqual(Settings.recordingFolder, old.path)
        let recordings = try makeFolder("Recordings")
        XCTAssertTrue(Settings.setRecordingFolder(recordings.path))
        XCTAssertEqual(Settings.recordingFolder, recordings.path)
        XCTAssertEqual(Settings.autoSaveLocation, screenshots.path)
        // Running the move again changes nothing.
        Settings.migrateRecordingFolderIfNeeded()
        XCTAssertEqual(Settings.recordingFolder, recordings.path)
    }

    func testRecordingFolderRefusesAFolderThatCantBeWritten() throws {
        XCTAssertFalse(Settings.setRecordingFolder("/nonexistent-\(UUID().uuidString)"))
        XCTAssertFalse(Settings.setRecordingFolder("relative/path"))
        XCTAssertEqual(Settings.recordingFolder, Settings.defaultAutoSaveLocation)
        // A folder deleted afterwards falls back instead of failing.
        let gone = try makeFolder("Gone")
        XCTAssertTrue(Settings.setRecordingFolder(gone.path))
        try FileManager.default.removeItem(at: gone)
        XCTAssertEqual(Settings.recordingFolder, Settings.autoSaveLocation)
    }

    func testRecordingsInTheRecordingFolderShowInHome() throws {
        let recordings = try makeFolder("Recordings")
        XCTAssertTrue(Settings.setRecordingFolder(recordings.path))
        let video = recordings.appendingPathComponent("LF Studios 2026-10-29 at 10.00.00.mp4")
        try Data([0]).write(to: video)
        XCTAssertTrue(Settings.recordingURLs.contains { $0.standardizedFileURL == video.standardizedFileURL })
    }

    func testAnnotationEditorSettingsDefaultsAndClamping() {
        XCTAssertFalse(Settings.annotationRoundedRectangles)
        XCTAssertEqual(Settings.annotationTextFontSize, 18)
        XCTAssertTrue(Settings.annotationTextBold, "text stays bold until the user turns it off")
        XCTAssertEqual(Settings.annotationRedactionStrength, 12)
        XCTAssertFalse(Settings.annotationSpotlightEllipse)

        Settings.annotationTextFontSize = 500
        Settings.annotationRedactionStrength = 1
        Settings.annotationTextBold = false
        XCTAssertEqual(Settings.annotationTextFontSize, 96)
        XCTAssertEqual(Settings.annotationRedactionStrength, 4)
        XCTAssertFalse(Settings.annotationTextBold)
    }

    func testRecordingSettingsClampInvalidValues() {
        Settings.recordingFPS = 99
        Settings.recordingQuality = "cinematic"

        XCTAssertEqual(Settings.recordingFPS, 60)
        XCTAssertEqual(Settings.recordingQuality, "high")

        // Someone who picks 30 keeps it.
        Settings.recordingFPS = 30
        Settings.recordingQuality = "max"

        XCTAssertEqual(Settings.recordingFPS, 30)
        XCTAssertEqual(Settings.recordingQuality, "max")
    }

    func testResolvedLastRecordingFallsBackToNewestLFStudiosMP4() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(Settings.setAutoSaveLocation(dir.path))
        Settings.lastRecordingPath = dir.appendingPathComponent("missing.mp4").path

        let older = dir.appendingPathComponent("LF Studios 2026-01-01 at 10.00.00 AM.mp4")
        let newer = dir.appendingPathComponent("LF Studios 2026-01-01 at 10.01.00 AM.mp4")
        let ignored = dir.appendingPathComponent("Other.mp4")
        try Data([1]).write(to: older)
        try Data([2]).write(to: newer)
        try Data([3]).write(to: ignored)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 3600)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 7200)], ofItemAtPath: newer.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 10_800)], ofItemAtPath: ignored.path)

        let resolved = try XCTUnwrap(Settings.resolvedLastRecordingURL)
        let expectedPath = newer.standardizedFileURL.path

        XCTAssertEqual(resolved.standardizedFileURL.path, expectedPath)
        XCTAssertEqual(URL(fileURLWithPath: Settings.lastRecordingPath).standardizedFileURL.path, expectedPath)
    }
}
