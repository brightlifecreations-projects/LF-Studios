import AppKit
import KeyboardShortcuts
import XCTest
@testable import LFStudiosCore

final class ShortcutDefaultsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LFStudiosCoreTests.Shortcuts.\(UUID().uuidString)"
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

    func testAllExpectedShortcutsAreRegistered() {
        // 7 screenshot (incl. timed and All Displays), 3 tools, 7 recording
        // (with pause/resume, markers and pausing speaker notes).
        XCTAssertEqual(LFStudiosShortcut.allCases.count, 17)
        XCTAssertEqual(Set(LFStudiosShortcut.allCases.map(\.name.rawValue)).count, LFStudiosShortcut.allCases.count)
        XCTAssertEqual(LFStudiosShortcut.captureAllDisplays.section, .screenshots)
    }

    func testDefaultShortcutMappingMatchesLegacyHotkeys() {
        XCTAssertEqual(LFStudiosShortcut.captureArea.name.defaultShortcut, .init(.four, modifiers: [.command, .shift]))
        XCTAssertEqual(LFStudiosShortcut.captureWindow.name.defaultShortcut, .init(.five, modifiers: [.command, .shift]))
        XCTAssertEqual(LFStudiosShortcut.captureFullscreenNative.name.defaultShortcut, .init(.three, modifiers: [.command, .shift]))
        XCTAssertEqual(LFStudiosShortcut.captureFullscreenFallback.name.defaultShortcut, .init(.six, modifiers: [.command, .shift]))
        XCTAssertEqual(LFStudiosShortcut.capturePreviousArea.name.defaultShortcut, .init(.seven, modifiers: [.command, .shift]))
        // Ship unassigned — users opt in via Preferences → Shortcuts.
        XCTAssertNil(LFStudiosShortcut.captureTimed.name.defaultShortcut)
        XCTAssertNil(LFStudiosShortcut.captureAllDisplays.name.defaultShortcut)
    }

    /// ⌘⇧S / ⌘⇧O are Save As / Open in most apps: new installs must not
    /// grab them globally.
    func testToolShortcutsShipUnassigned() {
        XCTAssertNil(LFStudiosShortcut.captureText.name.defaultShortcut)
        XCTAssertNil(LFStudiosShortcut.captureScrolling.name.defaultShortcut)
        XCTAssertTrue(LFStudiosShortcut.captureText.isOptional)
        XCTAssertTrue(LFStudiosShortcut.captureScrolling.isOptional)
    }

    func testFreshInstallGetsNoLegacyToolShortcuts() {
        var written: [String: KeyboardShortcuts.Shortcut] = [:]
        LFStudiosShortcut.migrateLegacyToolShortcutsIfNeeded(
            isExistingInstall: Settings.isExistingInstall,
            hasStoredValue: { _ in false },
            setShortcut: { written[$1.rawValue] = $0 }
        )
        XCTAssertFalse(Settings.isExistingInstall)
        XCTAssertTrue(written.isEmpty)
        XCTAssertTrue(Settings.didMigrateLegacyToolShortcuts)
    }

    func testUpgradedInstallKeepsCommandShiftSAndO() {
        Settings.hasLaunchedBefore = true
        var written: [String: KeyboardShortcuts.Shortcut] = [:]
        LFStudiosShortcut.migrateLegacyToolShortcutsIfNeeded(
            isExistingInstall: Settings.isExistingInstall,
            hasStoredValue: { _ in false },
            setShortcut: { written[$1.rawValue] = $0 }
        )
        XCTAssertEqual(written["captureScrolling"], .init(.s, modifiers: [.command, .shift]))
        XCTAssertEqual(written["captureText"], .init(.o, modifiers: [.command, .shift]))
    }

    func testUpgradeNeverOverridesAStoredChoice() {
        Settings.hasLaunchedBefore = true
        var written: [String: KeyboardShortcuts.Shortcut] = [:]
        // The user rebound (or cleared) Scrolling Capture; Capture Text still
        // has the old default stored by KeyboardShortcuts.
        LFStudiosShortcut.migrateLegacyToolShortcutsIfNeeded(
            isExistingInstall: true,
            hasStoredValue: { _ in true },
            setShortcut: { written[$1.rawValue] = $0 }
        )
        XCTAssertTrue(written.isEmpty)
    }

    func testMigrationRunsOnce() {
        Settings.hasLaunchedBefore = true
        var writes = 0
        for _ in 0..<3 {
            LFStudiosShortcut.migrateLegacyToolShortcutsIfNeeded(
                isExistingInstall: true,
                hasStoredValue: { _ in false },
                setShortcut: { _, _ in writes += 1 }
            )
        }
        XCTAssertEqual(writes, 2, "one write per legacy shortcut, on the first run only")
    }

    func testExistingInstallDetection() {
        XCTAssertFalse(Settings.isExistingInstall)
        Settings.captureCount = 3
        XCTAssertTrue(Settings.isExistingInstall)
        Settings.captureCount = 0
        Settings.onboardingCompleted = false
        XCTAssertTrue(Settings.isExistingInstall, "a stored onboarding flag means LF Studios ran here before")
    }

    // MARK: Non-Latin layouts

    func testLatinLetterFallsBackToKeyPositionOnNonLatinLayouts() throws {
        // Russian layout: the C key types "с" (Cyrillic es).
        let cyrillic = try XCTUnwrap(Self.keyEvent(characters: "с", keyCode: 8))
        XCTAssertEqual(ShortcutKeyMatching.latinLetter(for: cyrillic), "c")
        let greek = try XCTUnwrap(Self.keyEvent(characters: "σ", keyCode: 1))
        XCTAssertEqual(ShortcutKeyMatching.latinLetter(for: greek), "s")
    }

    func testLatinLayoutsKeepTheirOwnLetters() throws {
        // Dvorak: the key at QWERTY "I" types "c" — that's the user's ⌘C.
        let dvorak = try XCTUnwrap(Self.keyEvent(characters: "c", keyCode: 34))
        XCTAssertEqual(ShortcutKeyMatching.latinLetter(for: dvorak), "c")
        let upper = try XCTUnwrap(Self.keyEvent(characters: "E", keyCode: 14))
        XCTAssertEqual(ShortcutKeyMatching.latinLetter(for: upper), "e")
    }

    private static func keyEvent(characters: String, keyCode: UInt16) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
