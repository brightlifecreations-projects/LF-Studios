import Foundation
@testable import LFStudiosCore

/// Points video drafts, recording metadata, and the export index at a
/// throwaway folder, so tests never write into the real Application Support.
/// Each test process gets its own (tests run in parallel, one process each),
/// so presets, drafts, and the list of exports in progress never mix.
enum VideoTestStorage {
    /// Every process's folder sits in here; the test scripts empty it first.
    static let parent = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-test-storage", isDirectory: true)

    static func isolate() {
        VideoStorageLocation.useRootIfUnset {
            let root = parent.appendingPathComponent("process-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            // A process from an earlier run may have had this number: start empty.
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }
    }
}

/// Editor UI tests run in both layouts (1.17.0): LF Studios (new), the
/// default, and CapCut style. `body` gets each in turn; the Mac's choice is
/// put back afterwards.
@MainActor
func forEachEditorStyle(_ body: (VideoEditorStyle) async throws -> Void) async rethrows {
    let before = Settings.videoEditorStyle
    let wasLooping = EditorStyleLoop.active
    EditorStyleLoop.active = true
    defer {
        EditorStyleLoop.active = wasLooping
        Settings.videoEditorStyle = before
        VideoEditorPanelStore.shared.reload()
    }
    for style in VideoEditorStyle.allCases {
        Settings.videoEditorStyle = style
        VideoEditorPanelStore.shared.reload()
        try await body(style)
    }
}

/// For a screenshot helper: `shot` once per layout (the file name gets
/// "-capcut" for CapCut style), returning the LF Studios (new) one. Inside
/// `forEachEditorStyle` it runs once, in the layout being tested.
@MainActor
func inEditorStyles<T>(_ shot: (_ suffix: String) async throws -> T) async rethrows -> T {
    if EditorStyleLoop.active {
        return try await shot(EditorStyleLoop.suffix(Settings.videoEditorStyle))
    }
    var first: T?
    try await forEachEditorStyle { style in
        let result = try await shot(EditorStyleLoop.suffix(style))
        if first == nil { first = result }
    }
    return first!
}

enum EditorStyleLoop {
    @MainActor static var active = false
    static func suffix(_ style: VideoEditorStyle) -> String { style == .capCut ? "-capcut" : "" }
}
