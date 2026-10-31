import XCTest
@testable import LFStudiosCore

/// Library ▸ Captions (1.15.0): .srt/.vtt import onto the recording's
/// clock, round trips with export, caption templates (macOS fonts only),
/// one undo step each.
@MainActor
final class VideoCaptionLibraryTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-captionlib-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testParsingSrtAndVtt() {
        let srt = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,500\r\nHello <i>there</i>\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\n{\\an8}Second\r\nline\r\n\r\nbroken\n00:00:09 --> nope\n"
        let cues = VideoSubtitleImport.parse(srt)
        XCTAssertEqual(cues, [.init(start: 1, end: 2.5, text: "Hello there"), .init(start: 3, end: 4, text: "Second line")])
        let vtt = "WEBVTT\n\n00:05.250 --> 00:06.000 align:start\nWeb cue\n"
        XCTAssertEqual(VideoSubtitleImport.parse(vtt), [.init(start: 5.25, end: 6, text: "Web cue")])
        XCTAssertEqual(VideoSubtitleImport.time("1:02:03.5"), 3723.5)
        XCTAssertNil(VideoSubtitleImport.time("abc"))
    }

    func testImportOntoAnEditedTimelineAndRoundTrip() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 8)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        // Cut 2–4 s out: timeline 3 s is source 5 s.
        model.project.timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 2), VideoDemoTimelineClip(sourceStart: 4, sourceEnd: 8)]
        let file = directory.appendingPathComponent("subs.srt")
        try "1\n00:00:00,500 --> 00:00:01,500\nFirst one\n\n2\n00:00:03,000 --> 00:00:04,000\nAfter the cut\n\n3\n00:00:30,000 --> 00:00:31,000\nPast the end\n".write(to: file, atomically: true, encoding: .utf8)
        let depth = model.undoDepth
        XCTAssertEqual(model.importSubtitles(from: file), 2, "the cue past the end is left out")
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.project.captions[1].start, 5, accuracy: 0.01, "on the recording's clock")
        XCTAssertEqual(model.project.captions[1].words.count, 3)
        // Exported again: the same times as imported.
        let again = VideoSubtitleImport.parse(VideoCaptionBuilder.subtitles(.srt, project: model.project, segments: model.segments))
        XCTAssertEqual(again.map(\.text), ["First one", "After the cut"])
        XCTAssertEqual(again[1].start, 3, accuracy: 0.01)
        // Undo brings the old (none) back.
        model.undo()
        XCTAssertTrue(model.project.captions.isEmpty)
        // A file with nothing in it changes nothing.
        let empty = directory.appendingPathComponent("empty.srt")
        try "hello".write(to: empty, atomically: true, encoding: .utf8)
        XCTAssertEqual(model.importSubtitles(from: empty), 0)
        XCTAssertEqual(model.undoDepth, depth)
    }

    func testTemplates() async throws {
        let templates = VideoCaptionTemplate.all
        XCTAssertEqual(Set(templates.map(\.id)).count, templates.count)
        for template in templates {
            if let font = template.font { XCTAssertTrue(VideoTextFonts.families.contains(font), "\(template.id) uses a macOS font") }
            XCTAssertNotNil(VideoCaptionTemplatePreview.image(template, spoken: 1), template.id)
        }
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 3)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let depth = model.undoDepth
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "caption", id: "karaoke"), at: nil))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.project.captionStyle.animation, .karaoke)
        XCTAssertEqual(model.project.captionStyle.font?.family, "Avenir Next")
        XCTAssertEqual(model.project.captionStyle, try XCTUnwrap(templates.first { $0.id == "karaoke" }).style)
    }
}
