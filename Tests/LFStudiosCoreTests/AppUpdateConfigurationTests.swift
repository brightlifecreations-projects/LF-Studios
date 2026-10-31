import XCTest
@testable import LFStudiosCore

final class AppUpdateConfigurationTests: XCTestCase {
    func testRejectsMissingOrPlaceholderConfiguration() {
        XCTAssertNil(AppUpdateConfiguration(feedURLString: nil, publicEDKey: "abc"))
        XCTAssertNil(AppUpdateConfiguration(feedURLString: "https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/latest/download/appcast.xml", publicEDKey: nil))
        XCTAssertNil(AppUpdateConfiguration(feedURLString: "https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/latest/download/appcast.xml", publicEDKey: "SET_SPARKLE_PUBLIC_ED_KEY_IN_RELEASE_BUILD"))
    }

    func testAcceptsValidConfiguration() throws {
        let configuration = try XCTUnwrap(AppUpdateConfiguration(
            feedURLString: "https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/latest/download/appcast.xml",
            publicEDKey: "abcdefghijklmnopqrstuvwxyz"
        ))

        XCTAssertEqual(configuration.feedURL.absoluteString, "https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/latest/download/appcast.xml")
        XCTAssertEqual(configuration.publicEDKey, "abcdefghijklmnopqrstuvwxyz")
    }

    /// Info.plist: the feed on the public releases repo, a check once a
    /// day, and never a download or install the user didn't click.
    func testUpdatesAreCheckedDailyAndNeverInstalledWithoutAsking() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        XCTAssertEqual(plist["SUFeedURL"] as? String, "https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/latest/download/appcast.xml")
        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(plist["SUScheduledCheckInterval"] as? Int, 86400)
        XCTAssertEqual(plist["SUAutomaticallyUpdate"] as? Bool, false, "an update must never install by itself")
        XCTAssertEqual(plist["SUAllowsAutomaticUpdates"] as? Bool, false, "the update window must not offer silent installs")
    }

    /// A copy put over the running app (as build-app.sh did) is noticed, so
    /// Check for Updates asks to reopen instead of failing in Sparkle.
    func testNoticesTheAppReplacedWhileOpen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-stamp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let program = folder.appendingPathComponent("LFStudios")
        try Data("old".utf8).write(to: program)
        let opened = try XCTUnwrap(AppBundleStamp.of(program))
        XCTAssertEqual(AppBundleStamp.of(program), opened, "untouched: the same")
        // rm -rf, then a fresh copy: a new file in the same place.
        let copy = folder.appendingPathComponent("new")
        try Data("new".utf8).write(to: copy)
        try FileManager.default.removeItem(at: program)
        try FileManager.default.moveItem(at: copy, to: program)
        XCTAssertNotEqual(AppBundleStamp.of(program), opened)
        XCTAssertNil(AppBundleStamp.of(folder.appendingPathComponent("missing")))
        // The test runner itself hasn't been replaced.
        XCTAssertFalse(AppBundleStamp.wasReplacedSinceLaunch)
    }
}
