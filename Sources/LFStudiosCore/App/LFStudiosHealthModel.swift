import Foundation
import KeyboardShortcuts

enum LFStudiosHealthKind: String, CaseIterable {
    case screenRecording
    case nativeShortcuts
    case updates
    case autoSave
    case shortcuts
    case version
}

enum LFStudiosHealthState: String {
    case ok
    case warning
    case issue
    case info

    var isHealthy: Bool {
        switch self {
        case .ok, .info: return true
        case .warning, .issue: return false
        }
    }
}

struct LFStudiosHealthRow: Identifiable, Equatable {
    let kind: LFStudiosHealthKind
    let title: String
    let detail: String
    let symbolName: String
    let state: LFStudiosHealthState
    let actionTitle: String?

    var id: String { kind.rawValue }
}

struct LFStudiosHealthSnapshot: Equatable {
    let screenRecordingGranted: Bool
    let nativeShortcutsEnabled: Bool
    let updatesConfigured: Bool
    let autoSavePath: String
    let autoSaveWritable: Bool
    let configuredShortcutCount: Int
    let expectedShortcutCount: Int
    let optionalUnassignedShortcutCount: Int
    let version: String
    let build: String

    static func live(updatesConfigured: Bool = AppUpdateConfiguration.current != nil) -> LFStudiosHealthSnapshot {
        let autoSavePath = Settings.autoSaveLocation
        return LFStudiosHealthSnapshot(
            screenRecordingGranted: PermissionsManager.hasScreenRecordingPermission,
            nativeShortcutsEnabled: NativeShortcutManager.nativeShortcutsEnabled,
            updatesConfigured: updatesConfigured,
            autoSavePath: autoSavePath,
            // Both the screenshot and the recording folder.
            autoSaveWritable: isWritableAutoSavePath(autoSavePath) && isWritableAutoSavePath(Settings.recordingFolder),
            configuredShortcutCount: LFStudiosShortcut.requiredConfiguredCount(),
            expectedShortcutCount: LFStudiosShortcut.requiredShortcutCount,
            optionalUnassignedShortcutCount: LFStudiosShortcut.optionalUnassignedCount(),
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.16.0",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "25"
        )
    }

    static func isWritableAutoSavePath(_ path: String, fileManager: FileManager = .default) -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return fileManager.isWritableFile(atPath: path)
    }
}

enum LFStudiosHealthModel {
    static func rows(snapshot: LFStudiosHealthSnapshot) -> [LFStudiosHealthRow] {
        [
            screenRecordingRow(snapshot),
            nativeShortcutsRow(snapshot),
            updatesRow(snapshot),
            autoSaveRow(snapshot),
            shortcutsRow(snapshot),
            versionRow(snapshot)
        ]
    }

    static func summary(snapshot: LFStudiosHealthSnapshot) -> LFStudiosHealthState {
        let rows = rows(snapshot: snapshot).filter { $0.kind != .version }
        if rows.contains(where: { $0.state == .issue }) { return .issue }
        if rows.contains(where: { $0.state == .warning }) { return .warning }
        return .ok
    }

    private static func screenRecordingRow(_ snapshot: LFStudiosHealthSnapshot) -> LFStudiosHealthRow {
        LFStudiosHealthRow(
            kind: .screenRecording,
            title: L("Screen Recording"),
            detail: snapshot.screenRecordingGranted ? L("Ready") : L("Permission needed"),
            symbolName: snapshot.screenRecordingGranted ? "checkmark.shield" : "exclamationmark.triangle",
            state: snapshot.screenRecordingGranted ? .ok : .issue,
            actionTitle: snapshot.screenRecordingGranted ? nil : L("Fix")
        )
    }

    private static func nativeShortcutsRow(_ snapshot: LFStudiosHealthSnapshot) -> LFStudiosHealthRow {
        LFStudiosHealthRow(
            kind: .nativeShortcuts,
            title: L("Apple Shortcuts"),
            detail: snapshot.nativeShortcutsEnabled ? L("Conflict detected") : L("No conflict"),
            symbolName: snapshot.nativeShortcutsEnabled ? "keyboard.badge.exclamationmark" : "keyboard",
            state: snapshot.nativeShortcutsEnabled ? .warning : .ok,
            actionTitle: snapshot.nativeShortcutsEnabled ? L("Fix") : nil
        )
    }

    private static func updatesRow(_ snapshot: LFStudiosHealthSnapshot) -> LFStudiosHealthRow {
        LFStudiosHealthRow(
            kind: .updates,
            title: L("Updates"),
            detail: snapshot.updatesConfigured ? L("Enabled") : L("Disabled"),
            symbolName: snapshot.updatesConfigured ? "arrow.triangle.2.circlepath.circle" : "arrow.triangle.2.circlepath.circle.fill",
            state: snapshot.updatesConfigured ? .ok : .warning,
            actionTitle: snapshot.updatesConfigured ? L("Check") : nil
        )
    }

    private static func autoSaveRow(_ snapshot: LFStudiosHealthSnapshot) -> LFStudiosHealthRow {
        LFStudiosHealthRow(
            kind: .autoSave,
            title: L("Save Folder"),
            detail: snapshot.autoSaveWritable ? L("Writable") : L("Choose folder"),
            symbolName: snapshot.autoSaveWritable ? "folder.badge.gearshape" : "folder.badge.questionmark",
            state: snapshot.autoSaveWritable ? .ok : .issue,
            actionTitle: snapshot.autoSaveWritable ? nil : L("Fix")
        )
    }

    private static func shortcutsRow(_ snapshot: LFStudiosHealthSnapshot) -> LFStudiosHealthRow {
        // Only shortcuts that ship WITH a default count toward health.
        // Optional ones (timed capture, recording) are opt-in by design —
        // leaving them unassigned is a valid choice, never a yellow warning.
        let ready = snapshot.configuredShortcutCount == snapshot.expectedShortcutCount
        let detail: String
        if ready {
            detail = snapshot.optionalUnassignedShortcutCount > 0
                ? L("Ready · \(snapshot.optionalUnassignedShortcutCount) optional off")
                : L("All configured")
        } else {
            detail = L("\(snapshot.configuredShortcutCount)/\(snapshot.expectedShortcutCount) configured")
        }
        return LFStudiosHealthRow(
            kind: .shortcuts,
            title: L("Shortcuts"),
            detail: detail,
            symbolName: ready ? "command.circle" : "command.circle.fill",
            state: ready ? .ok : .warning,
            actionTitle: ready ? nil : L("Fix")
        )
    }

    private static func versionRow(_ snapshot: LFStudiosHealthSnapshot) -> LFStudiosHealthRow {
        LFStudiosHealthRow(
            kind: .version,
            title: L("Version"),
            detail: "\(snapshot.version) (\(snapshot.build))",
            symbolName: "info.circle",
            state: .info,
            actionTitle: nil
        )
    }
}

extension LFStudiosShortcut {
    /// Optional shortcuts ship without a factory default (timed capture and
    /// the recording set) — the user opts in via Preferences → Shortcuts.
    var isOptional: Bool { name.defaultShortcut == nil }

    static var requiredShortcutCount: Int {
        allCases.filter { !$0.isOptional }.count
    }

    static func requiredConfiguredCount(getShortcut: (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut) -> Int {
        allCases.filter { !$0.isOptional }.reduce(0) { count, shortcut in
            getShortcut(shortcut.name) == nil ? count : count + 1
        }
    }

    static func optionalUnassignedCount(getShortcut: (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut) -> Int {
        allCases.filter(\.isOptional).reduce(0) { count, shortcut in
            getShortcut(shortcut.name) == nil ? count + 1 : count
        }
    }
}
