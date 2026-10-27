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
        guard VideoStorageLocation.overrideRoot == nil else { return }
        let root = parent.appendingPathComponent("process-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        // A process from an earlier run may have had this number: start empty.
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        VideoStorageLocation.overrideRoot = root
    }
}
