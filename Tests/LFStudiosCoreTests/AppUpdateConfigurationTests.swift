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
}
