import AppKit
import AVFoundation
import XCTest
@testable import LFStudiosCore

/// 1.21.0's editor basics: the skimmer, box selection, gaps, duplicates,
/// pasting attributes, roll and slide, Loop playback, solo, track names,
/// meters, safe zones and Reveal in Library. Each edit is one ⌘Z step.
@MainActor
final class VideoEditorBasicsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!
    private var suiteName: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-basics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "LFStudiosCoreTests.Basics.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
    }

    /// Red for 2 s then blue for 2 s, with sound.
    private func makeModel() async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.red, 2), (.blue, 2)], toneSeconds: 4)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.isReady)
        return model
    }

    /// `action` takes exactly one ⌘Z step, which puts the project back.
    private func oneStep(_ model: VideoEditorModel, _ action: () async -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        let before = model.project
        let depth = model.undoDepth
        await action()
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step", file: file, line: line)
        XCTAssertNotEqual(model.project, before, "it changed something", file: file, line: line)
        model.undo()
        XCTAssertEqual(model.project.timelineClips, before.timelineClips, "⌘Z puts the clips back", file: file, line: line)
        model.redo()
    }

    private func cuts(_ model: VideoEditorModel) -> [Double] {
        model.segments.dropFirst().map { ($0.timelineStart * 100).rounded() / 100 }
    }

    // MARK: The skimmer

    /// ⌘B splits at the skimmer while the pointer is over the timeline, and
    /// at the playhead when it isn't (or the preview axis is off).
    func testSplitIsAtTheSkimmerElseThePlayhead() async throws {
        let model = try await makeModel()
        model.seek(to: 1)
        Settings.videoTimelinePreviewAxis = true
        model.timelinePointerTime = 3
        XCTAssertTrue(model.isSkimming)
        XCTAssertEqual(model.editTime, 3)
        await oneStep(model) { model.perform(.split) }
        XCTAssertEqual(cuts(model), [3], "at the skimmer, not the playhead")
        XCTAssertEqual(model.clock.time, 1, accuracy: 0.001, "the playhead stays put")

        // The pointer leaves the timeline: the playhead.
        model.timelinePointerTime = nil
        XCTAssertFalse(model.isSkimming)
        model.selection = .none
        model.perform(.split)
        XCTAssertEqual(cuts(model), [1, 3])

        // The preview axis off: the playhead too, wherever the pointer is.
        Settings.videoTimelinePreviewAxis = false
        model.timelinePointerTime = 2.5
        XCTAssertNil(model.skimmerTime)
        model.seek(to: 0.5)
        model.selection = .none
        model.perform(.split)
        XCTAssertEqual(cuts(model), [0.5, 1, 3])

        // ⇧⌘B at the skimmer, then the playhead.
        Settings.videoTimelinePreviewAxis = true
        model.timelinePointerTime = 2.2
        model.perform(.splitAllTracks)
        XCTAssertEqual(cuts(model), [0.5, 1, 2.2, 3])
        model.timelinePointerTime = nil
        model.seek(to: 3.5)
        model.perform(.splitAllTracks)
        XCTAssertEqual(cuts(model), [0.5, 1, 2.2, 3, 3.5])
    }
}
