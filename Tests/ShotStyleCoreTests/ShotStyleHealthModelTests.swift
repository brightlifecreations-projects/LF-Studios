import KeyboardShortcuts
import XCTest
@testable import ShotStyleCore

final class ShotStyleHealthModelTests: XCTestCase {
    func testRowsReportHealthyConfiguration() {
        let snapshot = ShotStyleHealthSnapshot(
            screenRecordingGranted: true,
            nativeShortcutsEnabled: false,
            updatesConfigured: true,
            autoSavePath: "/tmp",
            autoSaveWritable: true,
            configuredShortcutCount: ShotStyleShortcut.requiredShortcutCount,
            expectedShortcutCount: ShotStyleShortcut.requiredShortcutCount,
            optionalUnassignedShortcutCount: 0,
            version: "0.16.0",
            build: "25"
        )

        let rows = ShotStyleHealthModel.rows(snapshot: snapshot)

        XCTAssertEqual(Set(rows.map(\.kind)), Set(ShotStyleHealthKind.allCases))
        XCTAssertEqual(ShotStyleHealthModel.summary(snapshot: snapshot), .ok)
        XCTAssertEqual(rows.first(where: { $0.kind == .updates })?.detail, "Enabled")
        XCTAssertEqual(rows.first(where: { $0.kind == .version })?.detail, "0.16.0 (25)")
        XCTAssertEqual(rows.first(where: { $0.kind == .shortcuts })?.detail, "All configured")
    }

    func testUnassignedOptionalShortcutsAreHealthy() {
        let snapshot = ShotStyleHealthSnapshot(
            screenRecordingGranted: true,
            nativeShortcutsEnabled: false,
            updatesConfigured: true,
            autoSavePath: "/tmp",
            autoSaveWritable: true,
            configuredShortcutCount: ShotStyleShortcut.requiredShortcutCount,
            expectedShortcutCount: ShotStyleShortcut.requiredShortcutCount,
            optionalUnassignedShortcutCount: 5,
            version: "0.20.2",
            build: "51"
        )

        let rows = ShotStyleHealthModel.rows(snapshot: snapshot)
        let shortcuts = rows.first(where: { $0.kind == .shortcuts })

        XCTAssertEqual(ShotStyleHealthModel.summary(snapshot: snapshot), .ok)
        XCTAssertEqual(shortcuts?.state, .ok)
        XCTAssertNil(shortcuts?.actionTitle)
        XCTAssertEqual(shortcuts?.detail, "Ready · 5 optional off")
    }

    func testRowsReportFixableIssues() {
        let snapshot = ShotStyleHealthSnapshot(
            screenRecordingGranted: false,
            nativeShortcutsEnabled: true,
            updatesConfigured: false,
            autoSavePath: "/missing",
            autoSaveWritable: false,
            configuredShortcutCount: 5,
            expectedShortcutCount: 7,
            optionalUnassignedShortcutCount: 5,
            version: "0.16.0",
            build: "25"
        )

        let rows = ShotStyleHealthModel.rows(snapshot: snapshot)

        XCTAssertEqual(ShotStyleHealthModel.summary(snapshot: snapshot), .issue)
        XCTAssertEqual(rows.first(where: { $0.kind == .screenRecording })?.actionTitle, "Fix")
        XCTAssertEqual(rows.first(where: { $0.kind == .nativeShortcuts })?.state, .warning)
        XCTAssertEqual(rows.first(where: { $0.kind == .autoSave })?.state, .issue)
        XCTAssertEqual(rows.first(where: { $0.kind == .shortcuts })?.detail, "5/7 configured")
    }

    func testAutoSaveWritableUsesRealFolders() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotStyleHealthModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(ShotStyleHealthSnapshot.isWritableAutoSavePath(directory.path))
        XCTAssertFalse(ShotStyleHealthSnapshot.isWritableAutoSavePath(directory.appendingPathComponent("missing").path))
    }

    func testShortcutHealthCountsOnlyRequiredShortcuts() {
        let configuredNames: Set<String> = [
            KeyboardShortcuts.Name.shotstyleCaptureArea.rawValue,
            KeyboardShortcuts.Name.shotstyleCaptureWindow.rawValue,
            // Optional since 0.24 — assigned or not, it never affects health.
            KeyboardShortcuts.Name.shotstyleCaptureText.rawValue
        ]

        let required = ShotStyleShortcut.requiredConfiguredCount { name in
            configuredNames.contains(name.rawValue) ? KeyboardShortcuts.Shortcut(.a, modifiers: [.command]) : nil
        }
        let optionalOff = ShotStyleShortcut.optionalUnassignedCount { _ in nil }

        XCTAssertEqual(ShotStyleShortcut.allCases.count, 15)
        XCTAssertEqual(ShotStyleShortcut.requiredShortcutCount, 5)
        XCTAssertEqual(required, 2)
        XCTAssertEqual(optionalOff, 10)
        XCTAssertFalse(ShotStyleShortcut.captureArea.isOptional)
        XCTAssertTrue(ShotStyleShortcut.recordArea.isOptional)
        XCTAssertTrue(ShotStyleShortcut.stopRecording.isOptional)
        XCTAssertTrue(ShotStyleShortcut.pauseRecording.isOptional)
        XCTAssertTrue(ShotStyleShortcut.captureTimed.isOptional)
        XCTAssertTrue(ShotStyleShortcut.captureText.isOptional)
        XCTAssertTrue(ShotStyleShortcut.captureScrolling.isOptional)
        XCTAssertTrue(ShotStyleShortcut.captureAllDisplays.isOptional)
    }
}
