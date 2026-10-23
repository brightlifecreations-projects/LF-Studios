import AppKit
import KeyboardShortcuts
import XCTest
@testable import ShotStyleCore

final class ShortcutDefaultsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ShotStyleCoreTests.Shortcuts.\(UUID().uuidString)"
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
        // 7 screenshot (incl. timed and All Displays), 3 tools, 5 recording
        // (with pause/resume).
        XCTAssertEqual(ShotStyleShortcut.allCases.count, 15)
        XCTAssertEqual(Set(ShotStyleShortcut.allCases.map(\.name.rawValue)).count, ShotStyleShortcut.allCases.count)
        XCTAssertEqual(ShotStyleShortcut.captureAllDisplays.section, .screenshots)
    }

    func testDefaultShortcutMappingMatchesLegacyHotkeys() {
        XCTAssertEqual(ShotStyleShortcut.captureArea.name.defaultShortcut, .init(.four, modifiers: [.command, .shift]))
        XCTAssertEqual(ShotStyleShortcut.captureWindow.name.defaultShortcut, .init(.five, modifiers: [.command, .shift]))
        XCTAssertEqual(ShotStyleShortcut.captureFullscreenNative.name.defaultShortcut, .init(.three, modifiers: [.command, .shift]))
        XCTAssertEqual(ShotStyleShortcut.captureFullscreenFallback.name.defaultShortcut, .init(.six, modifiers: [.command, .shift]))
        XCTAssertEqual(ShotStyleShortcut.capturePreviousArea.name.defaultShortcut, .init(.seven, modifiers: [.command, .shift]))
        // Ship unassigned — users opt in via Preferences → Shortcuts.
        XCTAssertNil(ShotStyleShortcut.captureTimed.name.defaultShortcut)
        XCTAssertNil(ShotStyleShortcut.captureAllDisplays.name.defaultShortcut)
    }

    /// ⌘⇧S / ⌘⇧O are Save As / Open in most apps: new installs must not
    /// grab them globally.
    func testToolShortcutsShipUnassigned() {
        XCTAssertNil(ShotStyleShortcut.captureText.name.defaultShortcut)
        XCTAssertNil(ShotStyleShortcut.captureScrolling.name.defaultShortcut)
        XCTAssertTrue(ShotStyleShortcut.captureText.isOptional)
        XCTAssertTrue(ShotStyleShortcut.captureScrolling.isOptional)
    }

    func testFreshInstallGetsNoLegacyToolShortcuts() {
        var written: [String: KeyboardShortcuts.Shortcut] = [:]
        ShotStyleShortcut.migrateLegacyToolShortcutsIfNeeded(
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
        ShotStyleShortcut.migrateLegacyToolShortcutsIfNeeded(
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
        ShotStyleShortcut.migrateLegacyToolShortcutsIfNeeded(
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
            ShotStyleShortcut.migrateLegacyToolShortcutsIfNeeded(
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
        XCTAssertTrue(Settings.isExistingInstall, "a stored onboarding flag means ShotStyle ran here before")
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
