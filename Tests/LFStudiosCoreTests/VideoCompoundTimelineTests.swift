import XCTest
@testable import LFStudiosCore

/// A compound clip in its own timeline (1.16.0): open it, change one of its
/// clips on its own, nothing else changes while it's open, Esc goes back.
@MainActor
final class VideoCompoundTimelineTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-compoundtl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    /// A star (0–4 s) and a heart (1–5 s) made into a compound, moved and
    /// shrunk; a text clip outside it.
    private func makeModel() async throws -> (VideoEditorModel, compound: UUID, star: UUID, heart: UUID, outside: UUID) {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 6)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let star = model.addSticker(.star, at: 0)
        let heart = model.addSticker(.heart, at: 1)
        model.seek(to: 0.5)
        model.perform(.addTextClip)
        let outside = try XCTUnwrap(model.selectedLayerItem?.id)
        model.selection = .layer(star)
        model.extraSelection = [.layer(heart)]
        XCTAssertTrue(model.perform(.makeCompound))
        let compound = try XCTUnwrap(model.project.compounds?.first)
        model.setCompound(compound.id) { $0.x = 0.7; $0.scale = 0.5 }
        model.endGesture()
        model.selection = .layer(star)
        return (model, compound.id, star, heart, outside)
    }

    func testOpenAndGoBack() async throws {
        let (model, compound, star, heart, _) = try await makeModel()
        XCTAssertEqual(model.groupMates(of: star), [star, heart], "closed: its clips go together")
        XCTAssertNotNil(model.plan.compounds[compound])

        XCTAssertTrue(model.perform(.openCompound))
        XCTAssertEqual(model.openCompound, compound)
        XCTAssertEqual(model.groupMates(of: star), [star], "open: one by one")
        XCTAssertNil(model.plan.compounds[compound], "its clips show as they are, so their handles line up")
        XCTAssertNil(model.shownCompound(of: try XCTUnwrap(model.project.layerItem(star))))

        XCTAssertTrue(model.perform(.closeCompound))
        XCTAssertNil(model.openCompound)
        XCTAssertNotNil(model.plan.compounds[compound], "the whole video again, with the compound's look")
        XCTAssertEqual(model.selection, .layer(star))

        // Nothing selected (or not a compound): it doesn't open.
        model.selection = .none
        XCTAssertFalse(model.perform(.openCompound))
        XCTAssertNil(model.openCompound)
    }

    func testOneClipChangesOnItsOwnInside() async throws {
        let (model, _, star, heart, _) = try await makeModel()
        model.perform(.openCompound)
        let heartBefore = try XCTUnwrap(model.project.layerItem(heart))
        let depth = model.undoDepth
        model.moveLayerItem(star, to: 0.5, track: try XCTUnwrap(model.project.layerTrackIndex(of: star)))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(try XCTUnwrap(model.project.layerItem(star)).at, 0.5, accuracy: 0.001, "the star moved")
        XCTAssertEqual(model.project.layerItem(heart), heartBefore, "the heart stayed")
        model.setLayerItem(heart, label: "Clip Change") { $0.opacity = 0.5 }
        XCTAssertEqual(try XCTUnwrap(model.project.layerItem(heart)).opacity, 0.5, accuracy: 0.001)
        model.undo()
        model.undo()
        XCTAssertEqual(model.project.layerItem(heart), heartBefore)
        XCTAssertEqual(try XCTUnwrap(model.project.layerItem(star)).at, 0, accuracy: 0.001)
    }

    func testNothingElseChangesWhileOpen() async throws {
        let (model, compound, star, _, outside) = try await makeModel()
        model.perform(.openCompound)
        let before = model.project
        // The main track, a clip outside, the compound itself: refused.
        model.seek(to: 2)
        model.selection = .none
        model.perform(.split)
        model.setLayerItem(outside, label: "Clip Change") { $0.opacity = 0.2 }
        model.setCompound(compound) { $0.scale = 2 }
        XCTAssertFalse(model.perform(.breakApart))
        XCTAssertEqual(model.project, before, "only its clips change inside")
        // Something added inside joins it.
        model.seek(to: 1)
        model.selection = .layer(star)
        model.perform(.addTextClip)
        let added = try XCTUnwrap(model.selectedLayerItem)
        XCTAssertEqual(added.group, compound)
        XCTAssertEqual(model.project.compoundMembers(compound).count, 3)
    }

    func testGoneMeansClosed() async throws {
        let (model, compound, _, _, _) = try await makeModel()
        model.perform(.openCompound)
        XCTAssertEqual(model.openCompound, compound)
        // Undoing back to before it was made: it isn't open any more.
        model.undo()
        model.undo()
        XCTAssertNil(model.project.compound(compound))
        XCTAssertNil(model.openCompound)
    }
}
