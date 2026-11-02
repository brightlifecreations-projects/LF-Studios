import XCTest
@testable import LFStudiosCore

/// Properties ▸ Captions (1.17.0): every caption editable in a list, and
/// one restyle for all of them, each one ⌘Z step.
@MainActor
final class VideoCaptionsPanelTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-cues-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeModel() async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 6)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        model.mutate { project in
            project.captions = [
                VideoCaptionLine(start: 1, end: 2, text: "First line"),
                VideoCaptionLine(start: 3, end: 4, text: "Second line", placement: VideoTextPlacement(x: 0.2, y: 0.3)),
            ]
        }
        return model
    }

    func testEditingACaptionIsOneStep() async throws {
        let model = try await makeModel()
        let first = try XCTUnwrap(model.project.captions.first)
        let depth = model.undoDepth
        XCTAssertTrue(model.perform(.setCaptionText(first.id, "First words")))
        model.endGesture()
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.project.captions.first?.text, "First words")
        XCTAssertFalse(model.perform(.setCaptionText(first.id, "First words")), "the same words: nothing")
        model.undo()
        XCTAssertEqual(model.project.captions.first?.text, "First line")
    }

    func testRestyleAllIsOneStep() async throws {
        let model = try await makeModel()
        let template = try XCTUnwrap(VideoCaptionTemplate.all.last)
        let before = model.project
        let depth = model.undoDepth
        XCTAssertTrue(model.perform(.restyleCaptions(template: template.id, size: .large, position: .top)))
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step")
        var expected = before.captionStyle
        template.apply(to: &expected)
        XCTAssertEqual(model.project.captionStyle.preset, expected.preset)
        XCTAssertEqual(model.project.captionStyle.size, .large)
        XCTAssertEqual(model.project.captionStyle.position, .top)
        XCTAssertTrue(model.project.captions.allSatisfy { $0.placement == nil }, "no caption keeps a place of its own")
        XCTAssertEqual(model.project.captions.map(\.text), before.captions.map(\.text), "the words stay")
        model.undo()
        XCTAssertEqual(model.project, before, "⌘Z puts every caption back")

        // Locked captions: refused.
        model.toggleTrackLocked(.captions)
        XCTAssertFalse(model.perform(.restyleCaptions(template: nil, size: .small, position: .bottom)))
        XCTAssertFalse(model.perform(.setCaptionText(try XCTUnwrap(model.project.captions.first?.id), "Nope")))
    }
}
