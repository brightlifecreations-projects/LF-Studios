import KeyboardShortcuts
import XCTest
@testable import LFStudiosCore

final class LFStudiosHealthModelTests: XCTestCase {
    func testRowsReportHealthyConfiguration() {
        let snapshot = LFStudiosHealthSnapshot(
            screenRecordingGranted: true,
            nativeShortcutsEnabled: false,
            updatesConfigured: true,
            autoSavePath: "/tmp",
            autoSaveWritable: true,
            configuredShortcutCount: LFStudiosShortcut.requiredShortcutCount,
            expectedShortcutCount: LFStudiosShortcut.requiredShortcutCount,
            optionalUnassignedShortcutCount: 0,
            version: "0.16.0",
            build: "25"
        )

        let rows = LFStudiosHealthModel.rows(snapshot: snapshot)

        XCTAssertEqual(Set(rows.map(\.kind)), Set(LFStudiosHealthKind.allCases))
        XCTAssertEqual(LFStudiosHealthModel.summary(snapshot: snapshot), .ok)
        XCTAssertEqual(rows.first(where: { $0.kind == .updates })?.detail, "Enabled")
        XCTAssertEqual(rows.first(where: { $0.kind == .version })?.detail, "0.16.0 (25)")
        XCTAssertEqual(rows.first(where: { $0.kind == .shortcuts })?.detail, "All configured")
    }

    func testUnassignedOptionalShortcutsAreHealthy() {
        let snapshot = LFStudiosHealthSnapshot(
            screenRecordingGranted: true,
            nativeShortcutsEnabled: false,
            updatesConfigured: true,
            autoSavePath: "/tmp",
            autoSaveWritable: true,
            configuredShortcutCount: LFStudiosShortcut.requiredShortcutCount,
            expectedShortcutCount: LFStudiosShortcut.requiredShortcutCount,
            optionalUnassignedShortcutCount: 5,
            version: "0.20.2",
            build: "51"
        )

        let rows = LFStudiosHealthModel.rows(snapshot: snapshot)
        let shortcuts = rows.first(where: { $0.kind == .shortcuts })

        XCTAssertEqual(LFStudiosHealthModel.summary(snapshot: snapshot), .ok)
        XCTAssertEqual(shortcuts?.state, .ok)
        XCTAssertNil(shortcuts?.actionTitle)
        XCTAssertEqual(shortcuts?.detail, "Ready · 5 optional off")
    }

    func testRowsReportFixableIssues() {
        let snapshot = LFStudiosHealthSnapshot(
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

        let rows = LFStudiosHealthModel.rows(snapshot: snapshot)

        XCTAssertEqual(LFStudiosHealthModel.summary(snapshot: snapshot), .issue)
        XCTAssertEqual(rows.first(where: { $0.kind == .screenRecording })?.actionTitle, "Fix")
        XCTAssertEqual(rows.first(where: { $0.kind == .nativeShortcuts })?.state, .warning)
        XCTAssertEqual(rows.first(where: { $0.kind == .autoSave })?.state, .issue)
        XCTAssertEqual(rows.first(where: { $0.kind == .shortcuts })?.detail, "5/7 configured")
    }

    func testAutoSaveWritableUsesRealFolders() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LFStudiosHealthModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(LFStudiosHealthSnapshot.isWritableAutoSavePath(directory.path))
        XCTAssertFalse(LFStudiosHealthSnapshot.isWritableAutoSavePath(directory.appendingPathComponent("missing").path))
    }

    func testShortcutHealthCountsOnlyRequiredShortcuts() {
        let configuredNames: Set<String> = [
            KeyboardShortcuts.Name.lfstudiosCaptureArea.rawValue,
            KeyboardShortcuts.Name.lfstudiosCaptureWindow.rawValue,
            // Optional since 0.24 — assigned or not, it never affects health.
            KeyboardShortcuts.Name.lfstudiosCaptureText.rawValue
        ]

        let required = LFStudiosShortcut.requiredConfiguredCount { name in
            configuredNames.contains(name.rawValue) ? KeyboardShortcuts.Shortcut(.a, modifiers: [.command]) : nil
        }
        let optionalOff = LFStudiosShortcut.optionalUnassignedCount { _ in nil }

        XCTAssertEqual(LFStudiosShortcut.allCases.count, 16)
        XCTAssertEqual(LFStudiosShortcut.requiredShortcutCount, 5)
        XCTAssertEqual(required, 2)
        XCTAssertEqual(optionalOff, 11)
        XCTAssertFalse(LFStudiosShortcut.captureArea.isOptional)
        XCTAssertTrue(LFStudiosShortcut.recordArea.isOptional)
        XCTAssertTrue(LFStudiosShortcut.stopRecording.isOptional)
        XCTAssertTrue(LFStudiosShortcut.pauseRecording.isOptional)
        XCTAssertTrue(LFStudiosShortcut.addMarker.isOptional, "no default keys")
        XCTAssertTrue(LFStudiosShortcut.captureTimed.isOptional)
        XCTAssertTrue(LFStudiosShortcut.captureText.isOptional)
        XCTAssertTrue(LFStudiosShortcut.captureScrolling.isOptional)
        XCTAssertTrue(LFStudiosShortcut.captureAllDisplays.isOptional)
    }
}
