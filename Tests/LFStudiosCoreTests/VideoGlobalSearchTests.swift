import XCTest
@testable import LFStudiosCore

/// One search for everything (⌘K, 1.17.0): media, clips by name, captions by
/// their words and markers, besides the commands; choosing one selects it
/// and moves the playhead there, without playing.
@MainActor
final class VideoGlobalSearchTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("Dawn walk.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeModel() async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("Dawn walk.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 8)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        model.seek(to: 3)
        model.perform(.split)
        var content = VideoTextContent(string: "Dawn title")
        content.size = 60
        model.mutate { project in
            project.layerTracks = [VideoLayerTrack(items: [VideoLayerItem.text(content, at: 5, canvas: project.canvasSize())])]
            project.captions = VideoCaptionBuilder.lines(from: [
                VideoCaptionWord(text: "The", start: 1, end: 1.2), VideoCaptionWord(text: "dawn", start: 1.2, end: 1.6), VideoCaptionWord(text: "rises.", start: 1.6, end: 2),
            ])
        }
        model.seek(to: 6)
        model.addMarker()
        model.mutate { $0.markers = $0.markers.map { var m = $0; m.name = "Dawn chorus"; return m } }
        model.seek(to: 0)
        return model
    }

    func testEveryKindIsFound() async throws {
        let model = try await makeModel()
        let results = VideoGlobalSearch.results("dawn", in: model)
        let groups = results.map(\.group)
        XCTAssertEqual(groups, groups.sorted { VideoGlobalSearch.Group.allCases.firstIndex(of: $0)! < VideoGlobalSearch.Group.allCases.firstIndex(of: $1)! }, "in order: media, clips, captions, markers")
        XCTAssertTrue(results.contains { $0.group == .media && $0.title.contains("Dawn walk") }, "the recording")
        XCTAssertTrue(results.contains { $0.group == .clips && $0.title == "Dawn title" }, "a clip by its name")
        XCTAssertTrue(results.contains { $0.group == .captions && $0.title.contains("dawn rises") }, "a caption by its words")
        XCTAssertTrue(results.contains { $0.group == .markers && $0.title == "Dawn chorus" })
        XCTAssertTrue(VideoGlobalSearch.results("DAWN", in: model).count == results.count, "case doesn't matter")
        XCTAssertTrue(VideoGlobalSearch.results("", in: model).isEmpty)
        XCTAssertTrue(VideoGlobalSearch.results("clip 2", in: model).contains { $0.group == .clips }, "the main track's clips by their names")
    }

    func testChoosingOneShowsItWithoutPlaying() async throws {
        let model = try await makeModel()
        let before = model.project
        let title = try XCTUnwrap(VideoGlobalSearch.results("dawn title", in: model).first { $0.group == .clips })
        VideoGlobalSearch.show(title.target, in: model)
        XCTAssertEqual(model.selectedLayerItem?.name, "Dawn title")
        XCTAssertEqual(model.clock.time, 5, accuracy: 0.05)
        let caption = try XCTUnwrap(VideoGlobalSearch.results("rises", in: model).first)
        VideoGlobalSearch.show(caption.target, in: model)
        XCTAssertEqual(model.propertiesTab, .captions)
        let line = try XCTUnwrap(model.project.captions.first)
        XCTAssertEqual(model.clock.time, model.timelineTime(forSource: line.start) ?? line.start, accuracy: 0.01, "where the caption starts")
        let marker = try XCTUnwrap(VideoGlobalSearch.results("chorus", in: model).first)
        VideoGlobalSearch.show(marker.target, in: model)
        XCTAssertEqual(model.clock.time, 6, accuracy: 0.05)
        XCTAssertFalse(model.isPlaying, "never starts playing")
        XCTAssertEqual(model.project, before, "showing changes nothing")
    }
}
