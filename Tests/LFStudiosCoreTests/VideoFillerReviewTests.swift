import XCTest
@testable import LFStudiosCore

/// Remove ums (1.16.0): the list of ums found comes first, and only the
/// ticked ones are cut, in one undo step.
@MainActor
final class VideoFillerReviewTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-fillers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    /// "So, um, open the settings. Then, uh, save." (synthetic sound, no microphone)
    private func makeModel() async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: 8, fps: 30, audioSeconds: 8)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let spoken: [(String, Double, Double)] = [
            ("So,", 0.5, 0.8), ("um,", 0.9, 1.3), ("open", 1.4, 1.7), ("the", 1.7, 1.85), ("settings.", 1.85, 2.4),
            ("Then,", 5.4, 5.8), ("uh,", 5.9, 6.2), ("save.", 6.3, 6.8),
        ]
        model.mutate { $0.captions = VideoCaptionBuilder.lines(from: spoken.map { VideoCaptionWord(text: $0.0, start: $0.1, end: $0.2) }) }
        return model
    }

    func testTheListComesFirstWithTheWordsAround() async throws {
        let model = try await makeModel()
        let durationBefore = model.timelineDuration
        let depth = model.undoDepth
        XCTAssertTrue(model.perform(.reviewFillers))
        let review = try XCTUnwrap(model.fillerReview, "the list opens")
        XCTAssertEqual(model.timelineDuration, durationBefore, "nothing is cut yet")
        XCTAssertEqual(model.undoDepth, depth)
        XCTAssertEqual(review.candidates.map(\.filler), ["um,", "uh,"])
        XCTAssertEqual(review.ticked, Set(review.candidates.map(\.id)), "all ticked to start")
        XCTAssertEqual(review.candidates[0].before, "So,")
        XCTAssertEqual(review.candidates[0].after, "open the settings.")
        XCTAssertEqual(review.candidates[1].before, "the settings. Then,")
    }

    func testOnlyTheTickedOnesAreCut() async throws {
        let model = try await makeModel()
        model.perform(.reviewFillers)
        var review = try XCTUnwrap(model.fillerReview)
        let uh = try XCTUnwrap(review.candidates.last)
        review.ticked.remove(uh.id)
        model.fillerReview = nil
        let depth = model.undoDepth
        XCTAssertTrue(model.perform(.removeFillers(review.ticked.sorted())))
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step")
        let words = model.transcriptWords
        XCTAssertFalse(model.isIncluded(words[1]), "um, ticked: gone")
        XCTAssertTrue(model.isIncluded(words[6]), "uh, unticked: kept")
        XCTAssertEqual(model.fillerCount, 1)
        model.undo()
        XCTAssertEqual(model.fillerCount, 2)
        // None ticked: nothing to do.
        XCTAssertFalse(model.perform(.removeFillers([])))
    }

    func testPlayingOneDoesNotCut() async throws {
        let model = try await makeModel()
        model.perform(.reviewFillers)
        let um = try XCTUnwrap(model.fillerReview?.candidates.first)
        let before = model.project
        model.playFiller(um)
        XCTAssertEqual(model.clock.time, 0, accuracy: 0.05, "a second before the um (it starts at 0.9 s)")
        model.fillerPreview?.cancel()
        model.pause()
        XCTAssertEqual(model.project, before)
    }

    func testLockedClipsRefuse() async throws {
        let model = try await makeModel()
        model.toggleTrackLocked(.clips)
        let before = model.project.timelineClips
        XCTAssertFalse(model.perform(.removeFillers([1, 6])))
        XCTAssertEqual(model.project.timelineClips, before)
    }

    func testNoTranscriptNoList() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: 2, fps: 30, audioSeconds: 2)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertFalse(model.perform(.reviewFillers))
        XCTAssertNil(model.fillerReview)
    }
}
