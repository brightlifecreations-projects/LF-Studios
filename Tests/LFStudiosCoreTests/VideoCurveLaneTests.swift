import SwiftUI
import XCTest
@testable import LFStudiosCore

/// The keyframe curve lane (1.17.0) and the track names of the LF Studios
/// layout. The lane, the ◆ marks on a clip and the ◆ in Properties ▸ Clip
/// always show the same keyframes: they're the clip's own keys.
@MainActor
final class VideoCurveLaneTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-curve-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    /// A sticker from 1 s to 5 s with opacity keys at 2 s (100 %) and 4 s (20 %).
    private func makeModel() async throws -> (VideoEditorModel, UUID) {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 6)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let id = model.addSticker(.star, at: 1)
        model.selection = .layer(id)
        model.seek(to: 2)
        model.toggleKeyframe(id, .opacity)
        model.seek(to: 4)
        model.perform(.edit(.setValue(.opacity, 0.2)))
        model.endGesture()
        return (model, id)
    }

    /// Bézier handles (1.19.0): drawn a third of the way along the curve,
    /// dragged into a slope that reshapes it between the keys (ends stay),
    /// one ⌘Z step a drag; an easing chosen clears it; the new format only
    /// once a handle moves.
    func testCurveHandlesShapeTheCurveInOneStep() async throws {
        let (model, id) = try await makeModel()
        var item = try XCTUnwrap(model.project.layerItem(id))
        let handles = VideoCurveLane.handles(item, .opacity)
        XCTAssertEqual(handles.count, 2, "leaving the first key, arriving at the second")
        let out = try XCTUnwrap(handles.first { $0.side == .outgoing })
        XCTAssertEqual(out.time, 1 + 1 + 2.0 / 3, accuracy: 0.001, "a third of the way")
        XCTAssertEqual(out.value, 1 - 0.8 / 3, accuracy: 0.001, "on the straight line")
        let middle = item.value(.opacity, at: 3)
        XCTAssertEqual(middle, 0.6, accuracy: 0.001, "linear before")
        XCTAssertFalse(model.project.needsFormat5)

        // A drag: many slopes, one ⌘Z step.
        let depth = model.undoDepth
        for slope in [-0.3, -0.2, -0.1, 0.0] {
            XCTAssertTrue(model.perform(.edit(.setKeySlope(.opacity, at: 1, side: .outgoing, slope: slope))))
        }
        model.endGesture()
        XCTAssertEqual(model.undoDepth, depth + 1)
        item = try XCTUnwrap(model.project.layerItem(id))
        XCTAssertEqual(item.value(.opacity, at: 2), 1, accuracy: 0.000_1, "the keys stay")
        XCTAssertEqual(item.value(.opacity, at: 4), 0.2, accuracy: 0.000_1)
        XCTAssertGreaterThan(item.value(.opacity, at: 3), middle + 0.05, "flat leaving the first key: higher in the middle")
        XCTAssertEqual(VideoCurveLane.handles(item, .opacity).first { $0.side == .outgoing }?.value ?? 0, 1, accuracy: 0.001, "the handle where it was dragged")
        XCTAssertTrue(model.project.needsFormat5, "1.18 would draw a different curve")
        let json = String(decoding: try JSONEncoder().encode(model.project), as: UTF8.self)
        XCTAssertTrue(json.contains("outSlope"))

        // An easing chosen: it shapes the curve again.
        model.seek(to: 2)
        model.perform(.edit(.setEasing(.easeInOut)))
        item = try XCTUnwrap(model.project.layerItem(id))
        XCTAssertNil(item.keys?.keys(.opacity).first?.outSlope)
        model.undo()
        model.undo()
        item = try XCTUnwrap(model.project.layerItem(id))
        XCTAssertEqual(item.value(.opacity, at: 3), middle, accuracy: 0.001, "⌘Z: straight again")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(model.project), as: UTF8.self).contains("Slope"), "older keys write nothing new")
    }

    /// What each of the three shows, in timeline seconds.
    private func lanePoints(_ model: VideoEditorModel, _ id: UUID) throws -> [Double] {
        VideoCurveLane.points(try XCTUnwrap(model.project.layerItem(id)), .opacity).map(\.time)
    }
    private func clipMarks(_ model: VideoEditorModel, _ id: UUID) throws -> [Double] {
        let item = try XCTUnwrap(model.project.layerItem(id))
        return (item.keys?.times ?? []).map { item.at + $0 }
    }
    private func clipTabDiamondLit(_ model: VideoEditorModel, _ id: UUID, at time: Double) throws -> Bool {
        let item = try XCTUnwrap(model.project.layerItem(id))
        return item.keys?.hasKey(.opacity, at: time - item.at) == true
    }

    func testTheLaneTheMarksAndTheClipTabAgree() async throws {
        let (model, id) = try await makeModel()
        XCTAssertEqual(try lanePoints(model, id), [2, 4])
        XCTAssertEqual(try clipMarks(model, id), [2, 4])

        // Dragged in the lane: the 4 s key to 3.5 s and 60 %. One ⌘Z step
        // for the whole drag, and the marks and the Clip tab follow.
        let depth = model.undoDepth
        XCTAssertTrue(model.perform(.edit(.moveKey(.opacity, from: 3, to: 2.8, value: 0.5))))
        XCTAssertTrue(model.perform(.edit(.moveKey(.opacity, from: 2.8, to: 2.5, value: 0.6))))
        model.endGesture()
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step a drag")
        XCTAssertEqual(try lanePoints(model, id), [2, 3.5])
        XCTAssertEqual(try clipMarks(model, id), [2, 3.5], "the ◆ on the clip moved too")
        model.seek(to: 3.5)
        XCTAssertTrue(try clipTabDiamondLit(model, id, at: 3.5), "◆ lit in the Clip tab at the new place")
        XCTAssertFalse(try clipTabDiamondLit(model, id, at: 4))
        XCTAssertEqual(try XCTUnwrap(model.project.layerItem(id)).value(.opacity, at: 3.5), 0.6, accuracy: 0.0001)

        // The other way: ◆ in the Clip tab adds a key the lane shows.
        model.seek(to: 4.5)
        model.toggleKeyframe(id, .opacity)
        XCTAssertEqual(try lanePoints(model, id), [2, 3.5, 4.5])
        XCTAssertEqual(try clipMarks(model, id), [2, 3.5, 4.5])
        model.toggleKeyframe(id, .opacity)
        XCTAssertEqual(try lanePoints(model, id), [2, 3.5], "and removing it there removes it here")

        model.undo()
        model.undo()
        model.undo()
        XCTAssertEqual(try lanePoints(model, id), [2, 4], "undone: back where it was")
    }

    func testAKeyStaysBetweenItsNeighboursAndPositionMovesTogether() async throws {
        let (model, id) = try await makeModel()
        // Dragged past the 2 s key: it stops just after it.
        XCTAssertTrue(model.perform(.edit(.moveKey(.opacity, from: 3, to: 0.2, value: 0.2))))
        model.endGesture()
        let times = try lanePoints(model, id)
        XCTAssertEqual(times.count, 2)
        XCTAssertGreaterThan(times[1], times[0], "still after the first")
        // Position: x and y keys move in time together.
        model.seek(to: 3)
        model.toggleKeyframe(id, .x)
        XCTAssertTrue(model.perform(.edit(.moveKey(.x, from: 2, to: 2.5, value: 0.3))))
        model.endGesture()
        let keys = try XCTUnwrap(model.project.layerItem(id)?.keys)
        XCTAssertTrue(keys.hasKey(.x, at: 2.5))
        XCTAssertTrue(keys.hasKey(.y, at: 2.5), "y went with x")
        XCTAssertFalse(keys.hasKey(.y, at: 2))
    }

    func testTheLaneIsTheWindowsNotTheProjects() async throws {
        let (model, id) = try await makeModel()
        let track = try XCTUnwrap(model.project.layerTracks.first?.id)
        let before = model.project
        model.toggleCurveLane(track)
        model.curveLanes[track] = .width
        XCTAssertEqual(model.project, before, "opening it changes nothing in the project")
        let open = VideoTimelineRowLayout(project: model.project, hasCamera: false, curves: [track])
        let closed = VideoTimelineRowLayout(project: model.project, hasCamera: false)
        XCTAssertEqual((open.row(.layer(track))?.height ?? 0) - (closed.row(.layer(track))?.height ?? 0), VideoCurveLane.gap + VideoCurveLane.height, accuracy: 0.5)
        _ = id
    }

    func testTrackNamesAreLabelsOfTheNewLayoutOnly() async throws {
        let (model, _) = try await makeModel()
        let track = try XCTUnwrap(model.project.layerTracks.first?.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try encoder.encode(model.project)
        try await forEachEditorStyle { style in
            switch style {
            case .lfStudios:
                XCTAssertEqual(VideoTimelineTrack.clips.title(in: model.project), L("A roll"))
                XCTAssertEqual(VideoTimelineTrack.layer(track).title(in: model.project), L("V2 · B roll"))
                XCTAssertEqual(model.project.timelineTracks.first, .captions, "captions on top")
            case .capCut:
                XCTAssertEqual(VideoTimelineTrack.clips.title(in: model.project), L("Video clips"))
                XCTAssertEqual(VideoTimelineTrack.layer(track).title(in: model.project), L("Video 2"))
                XCTAssertEqual(model.project.timelineTracks.first, .captions, "captions on top in both layouts (1.18.0)")
            }
            XCTAssertEqual(try encoder.encode(model.project), json, "nothing in the project file")
        }
    }
}
