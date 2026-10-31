import AppKit
import AVFoundation
import CoreImage
import XCTest
@testable import LFStudiosCore

/// The tracks above the main track (1.14.0): in the exported pixels and
/// sound, their order, turned and mirrored main clips, the project format,
/// and moving, trimming and splitting items.
final class VideoLayersTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!
    private let size = CGSize(width: 640, height: 360)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-layers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A white recording, raw (no margin), 3 seconds.
    private func whiteProject() async throws -> VideoDemoProject {
        let source = directory.appendingPathComponent("white.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: size, colors: [(.white, 3)])
        var project = VideoInspection.project(for: source, seconds: 3, size: size)
        project.padding = 0
        return project
    }

    private func item(_ kind: VideoMediaKind, _ url: URL, at: Double, length: Double, fileDuration: Double = 0, width: Double, x: Double = 0.5, y: Double = 0.5) -> VideoLayerItem {
        var item = VideoLayerItem(kind: kind, path: url.path, name: url.lastPathComponent, at: at, length: length, fileDuration: fileDuration, aspect: 16.0 / 9)
        item.width = width
        item.x = x
        item.y = y
        return item
    }

    // MARK: In the export

    func testAVideoAboveTheMainTrackPlaysAtItsTimeAndPlace() async throws {
        var project = try await whiteProject()
        let red = directory.appendingPathComponent("red.mov")
        try await VideoInspection.writeColorVideo(to: red, size: CGSize(width: 320, height: 180), colors: [(.red, 1), (.blue, 1)], toneSeconds: 2, toneFrequency: 880)
        // Left half of the frame, from 1 s to 3 s.
        project.layerTracks = [VideoLayerTrack(items: [item(.video, red, at: 1, length: 2, fileDuration: 2, width: 0.5, x: 0.25)])]
        XCTAssertTrue(project.needsLayerFormat)

        let output = directory.appendingPathComponent("layers.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let before = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 0.5), x: 0.25, y: 0.5)
        XCTAssertGreaterThan(before.g, 0.85, "white before it starts: \(before)")
        let first = try VideoInspection.frame(of: output, at: 1.5)
        let red1 = VideoInspection.color(of: first, x: 0.25, y: 0.5)
        XCTAssertGreaterThan(red1.r, 0.8, "its first second is red: \(red1)")
        XCTAssertLessThan(red1.g, 0.25, "\(red1)")
        let right = VideoInspection.color(of: first, x: 0.75, y: 0.5)
        XCTAssertGreaterThan(right.g, 0.85, "only on the left half: \(right)")
        let second = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 2.5), x: 0.25, y: 0.5)
        XCTAssertGreaterThan(second.b, 0.8, "then its second second (blue): \(second)")
        // Its sound is in the mix while it plays.
        let samples = try VideoInspection.audio(of: output)
        XCTAssertGreaterThan(VideoInspection.toneLevel(samples, frequency: 880, from: 1.2, to: 2.8), VideoInspection.toneLevel(samples, frequency: 880, from: 0.1, to: 0.9) * 4, "its tone plays from 1 s")
    }

    func testHigherTracksDrawOverLowerOnesAndPicturesWork() async throws {
        var project = try await whiteProject()
        let green = directory.appendingPathComponent("green.png")
        let blue = directory.appendingPathComponent("blue.png")
        try VideoInspection.writePNG(to: green, size: CGSize(width: 160, height: 90), color: .green)
        try VideoInspection.writePNG(to: blue, size: CGSize(width: 160, height: 90), color: .blue)
        project.layerTracks = [
            VideoLayerTrack(items: [item(.image, green, at: 0, length: 3, width: 0.6)]),
            VideoLayerTrack(items: [item(.image, blue, at: 1, length: 1, width: 0.2)]),
        ]
        let output = directory.appendingPathComponent("order.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let early = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 0.5), x: 0.5, y: 0.5)
        XCTAssertGreaterThan(early.g, 0.6, "the lower picture alone: \(early)")
        XCTAssertLessThan(early.b, 0.3, "\(early)")
        let both = try VideoInspection.frame(of: output, at: 1.5)
        let middle = VideoInspection.color(of: both, x: 0.5, y: 0.5)
        XCTAssertGreaterThan(middle.b, 0.7, "the higher track on top: \(middle)")
        let side = VideoInspection.color(of: both, x: 0.33, y: 0.5)
        XCTAssertGreaterThan(side.g, 0.6, "the lower one around it: \(side)")
        // A hidden track isn't drawn.
        project.setTrackState(.layer(project.layerTracks[1].id)) { $0.hidden = true }
        let hidden = directory.appendingPathComponent("hidden.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: hidden, settings: VideoInspection.mp4Settings())
        let shown = VideoInspection.color(of: try VideoInspection.frame(of: hidden, at: 1.5), x: 0.5, y: 0.5)
        XCTAssertLessThan(shown.b, 0.3, "hidden: \(shown)")
    }

    func testMainClipsTurnMirrorAndSwitchOff() async throws {
        // Red on the left, blue on the right.
        let source = directory.appendingPathComponent("halves.mp4")
        try await VideoInspection.writeSplitVideo(to: source, size: size, left: .red, right: .blue, seconds: 3)
        var project = VideoInspection.project(for: source, seconds: 3, size: size)
        project.padding = 0
        project.timelineClips = [
            VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 1),
            VideoDemoTimelineClip(sourceStart: 1, sourceEnd: 2),
            VideoDemoTimelineClip(sourceStart: 2, sourceEnd: 3),
        ]
        project.timelineClips[1].mirrored = true
        project.timelineClips[2].disabled = true
        let output = directory.appendingPathComponent("looks.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let plain = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 0.5), x: 0.2, y: 0.5)
        XCTAssertGreaterThan(plain.r, 0.8, "as recorded: red on the left \(plain)")
        let mirrored = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 1.5), x: 0.2, y: 0.5)
        XCTAssertGreaterThan(mirrored.b, 0.8, "mirrored: blue on the left \(mirrored)")
        let off = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 2.5), x: 0.2, y: 0.5)
        XCTAssertLessThan(max(off.r, off.b), 0.3, "off: not shown \(off)")
        let length = try await AVURLAsset(url: output).load(.duration).seconds
        XCTAssertEqual(length, 3, accuracy: 0.1, "an off clip keeps its length")

        // A quarter turn: what was on the left is on top.
        let turned = VideoFrameRenderer.turned(CIImage(cgImage: try VideoInspection.frame(of: source, at: 0.5)), mirrored: false, turns: 1)
        let top = VideoInspection.color(of: turned, size: size, x: 0.5, y: 0.1)
        XCTAssertGreaterThan(top.r, 0.8, "turned clockwise: red on top \(top)")
        let sides = VideoInspection.color(of: turned, size: size, x: 0.05, y: 0.5)
        XCTAssertLessThan(max(sides.r, sides.g, sides.b), 0.1, "fitted inside, black beside it \(sides)")
    }

    func testTextAndTheCameraTurn() async throws {
        var project = try await whiteProject()
        // A wide, short text in the middle; turned a quarter, it stands up.
        var text = VideoDemoOverlayEffect(kind: .text, time: 0, duration: 3, x: 0.5, y: 0.5, width: 0.8, height: 0.12, text: "TURNED TEXT")
        text.color = VideoRGBA(0.1, 0.1, 0.9)
        project.overlayEffects = [text]
        let flat = directory.appendingPathComponent("flat.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: flat, settings: VideoInspection.mp4Settings())
        project.overlayEffects[0].rotation = 90
        XCTAssertTrue(project.needsLayerFormat, "only 1.14 shows it turned")
        let turned = directory.appendingPathComponent("turned.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: turned, settings: VideoInspection.mp4Settings())
        // Above the middle: white before, the text's blue once it's turned.
        let above = (x: 0.5, y: 0.38)
        let before = VideoInspection.color(of: try VideoInspection.frame(of: flat, at: 1), x: above.x, y: above.y)
        let after = VideoInspection.color(of: try VideoInspection.frame(of: turned, at: 1), x: above.x, y: above.y)
        XCTAssertGreaterThan(before.r, 0.85, "upright: nothing above it \(before)")
        XCTAssertGreaterThan(after.b, after.r + 0.3, "turned: its box reaches up \(after)")

        // The camera's turn: saved only when set.
        var camera = VideoWebcamSettings()
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(camera), as: UTF8.self).contains("rotation"))
        camera.rotation = -20
        let read = try JSONDecoder().decode(VideoWebcamSettings.self, from: try JSONEncoder().encode(camera))
        XCTAssertEqual(read.rotation, -20)
        var withCamera = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 4, sourceSize: size)
        XCTAssertFalse(withCamera.needsLayerFormat)
        withCamera.webcam.rotation = 15
        XCTAssertTrue(withCamera.needsLayerFormat)
    }

    // MARK: The project

    func testProjectsWithTracksAreFormat3AndOthersAreUnchanged() throws {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 4, sourceSize: size)
        let plain = VideoProjectDocument(mediaMode: .linked, project: project, recording: nil)
        XCTAssertEqual(plain.format, VideoProjectDocument.format)
        XCTAssertEqual(plain.version, 1)
        let plainJSON = String(decoding: try plain.encoded(), as: UTF8.self)
        XCTAssertFalse(plainJSON.contains("requires"))
        XCTAssertFalse(plainJSON.contains("layerTracks"))
        XCTAssertFalse(plainJSON.contains("mirrored"))

        project.layerTracks = [VideoLayerTrack(items: [item(.image, URL(fileURLWithPath: "/tmp/logo.png"), at: 1, length: 2, width: 0.3)])]
        let layered = VideoProjectDocument(mediaMode: .linked, project: project, recording: nil)
        XCTAssertEqual(layered.format, "lfstudios-project-3", "1.12 refuses the name; 1.13 says it needs a newer version")
        XCTAssertEqual(layered.version, 3)
        let data = try layered.encoded()
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"requires\" : 3"))
        let read = try VideoProjectDocument.decode(data)
        XCTAssertEqual(read.project.layerTracks, project.layerTracks, "this version reads it back")
        // Not a layer but only shown by 1.14: a mirrored clip.
        var mirrored = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 4, sourceSize: size)
        mirrored.timelineClips[0].mirrored = true
        XCTAssertEqual(VideoProjectDocument(mediaMode: .linked, project: mirrored, recording: nil).format, VideoProjectDocument.layersFormat)
        // A later one still asks for a newer version.
        let later = try JSONSerialization.data(withJSONObject: ["format": "lfstudios-project-4", "version": 4])
        XCTAssertThrowsError(try VideoProjectDocument.decode(later)) { XCTAssertEqual($0 as? VideoProjectDocument.ReadError, .needsNewerVersion) }
    }

    func testHandoffAndTimelinesCarryTheTracks() throws {
        let clip = directory.appendingPathComponent("b-roll.mov")
        let logo = directory.appendingPathComponent("logo.png")
        try Data("video".utf8).write(to: clip)
        try VideoInspection.writePNG(to: logo, size: CGSize(width: 100, height: 100), color: .green)
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/handoff/Screen.mov"), duration: 10, sourceSize: CGSize(width: 1280, height: 720))
        var video = item(.video, clip, at: 2, length: 3, fileDuration: 8, width: 0.5, x: 0.25)
        video.fileStart = 1
        var picture = item(.image, logo, at: 4, length: 2, width: 0.2)
        picture.rotation = 15
        project.layerTracks = [VideoLayerTrack(items: [video]), VideoLayerTrack(items: [picture])]
        let screen = URL(fileURLWithPath: "/tmp/handoff/Screen.mov")
        let recordings = [VideoHandoffRecording(id: UUID(), url: screen, name: "Screen.mov", offset: 0, duration: 10, size: CGSize(width: 1280, height: 720), frameRate: 30, audioKinds: [.mixed], camera: nil, metadata: nil)]
        let input = VideoHandoffInput(name: "Demo", project: project, recordings: recordings, exportSettings: VideoExportSettings(), recording: nil)
        let plan = VideoHandoffPlanner.plan(input, options: VideoHandoffOptions(), folderName: "x")
        // The files, as they are, where they belong, saying where they play.
        let videoItem = try XCTUnwrap(plan.items.first { $0.relativePath == "01 Screen/b-roll.mov" })
        XCTAssertEqual(videoItem.work, .copy(clip))
        XCTAssertTrue(videoItem.description.contains("Video 2 from 0:02"), videoItem.description)
        let pictureItem = try XCTUnwrap(plan.items.first { $0.relativePath == "04 Graphics/logo.png" })
        XCTAssertTrue(pictureItem.description.contains("Video 3"), pictureItem.description)
        XCTAssertTrue(pictureItem.description.contains("turned 15°"), pictureItem.description)
        // The handoff's own project points at the copies, and says 1.14.0.
        let projectItem = try XCTUnwrap(plan.items.first { if case .project = $0.work { return true } else { return false } })
        if case .project(let mapping) = projectItem.work {
            XCTAssertEqual(mapping[clip.standardizedFileURL.path], "01 Screen/b-roll.mov")
        }
        XCTAssertTrue(projectItem.description.contains("1.14.0"), projectItem.description)

        // On lanes above the screen in Final Cut and Premiere.
        let folder = URL(fileURLWithPath: "/tmp/handoff/x")
        let clips = VideoHandoffTimeline.clips(plan: plan, input: input)
        let lanes = clips.filter { $0.file == "01 Screen/b-roll.mov" || $0.file == "04 Graphics/logo.png" }
        XCTAssertEqual(lanes.count, 2)
        XCTAssertTrue(lanes.allSatisfy { $0.lane >= 2 })
        XCTAssertGreaterThan(lanes.first { $0.kind == .picture }?.lane ?? 0, lanes.first { $0.kind == .screen }?.lane ?? 0, "Video 3 above Video 2")
        XCTAssertEqual(lanes.first { $0.kind == .screen }?.start ?? 0, 1, accuracy: 0.001, "from a second into it")
        let fcp = VideoHandoffTimeline.fcpxml(plan: plan, input: input, folder: folder, durations: [:])
        XCTAssertTrue(fcp.contains("name=\"b-roll.mov\" start=\"30/30s\" duration=\"90/30s\""), fcp)
        XCTAssertTrue(fcp.contains("<video ref="), "the picture as a still")
        let premiere = VideoHandoffTimeline.premiereXML(plan: plan, input: input, folder: folder, durations: [:])
        XCTAssertTrue(premiere.contains("<name>b-roll.mov</name>"))
        XCTAssertTrue(premiere.contains("<name>logo.png</name>"))
    }

    // MARK: Editing

    func testMovingTrimmingAndSplitting() {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/rec.mov"), duration: 20, sourceSize: size)
        let a = item(.video, URL(fileURLWithPath: "/tmp/a.mov"), at: 1, length: 4, fileDuration: 6, width: 0.5)
        let b = item(.image, URL(fileURLWithPath: "/tmp/b.png"), at: 6, length: 3, width: 0.5)
        project.insertLayerItem(a, place: .automatic)
        project.insertLayerItem(b, place: .automatic)
        XCTAssertEqual(project.layerTracks.count, 1, "room for both on one track")
        // Onto the other: no room, so a new track above.
        project.moveLayerItems([b.id], by: -4, fromTrack: 0, toTrack: 0, newTrack: false)
        XCTAssertEqual(project.layerTracks.count, 2)
        XCTAssertEqual(project.layerTrackIndex(of: b.id), 1)
        XCTAssertEqual(project.layerItem(b.id)?.at, 2)
        // Back down where there's room again: the empty track goes.
        project.moveLayerItems([b.id], by: 6, fromTrack: 1, toTrack: 0, newTrack: false)
        XCTAssertEqual(project.layerTracks.count, 1)
        XCTAssertEqual(project.layerItem(b.id)?.at, 8)

        // A video can't start before its first frame or end after its last.
        project.trimLayerItem(a.id, leading: true, to: 0)
        XCTAssertEqual(project.layerItem(a.id)?.at, 1, "already at its first frame")
        project.trimLayerItem(a.id, leading: false, to: 30)
        XCTAssertEqual(project.layerItem(a.id)?.end ?? 0, 7, accuracy: 0.001, "its 6 seconds")
        project.trimLayerItem(a.id, leading: true, to: 3)
        XCTAssertEqual(project.layerItem(a.id)?.fileStart ?? 0, 2, accuracy: 0.001, "the start moved two seconds into the video")
        // A picture can be any length.
        project.trimLayerItem(b.id, leading: false, to: 30)
        XCTAssertEqual(project.layerItem(b.id)?.end ?? 0, 30, accuracy: 0.001)
        // …but not into the next item.
        project.trimLayerItem(a.id, leading: false, to: 9)
        XCTAssertEqual(project.layerItem(a.id)?.end ?? 0, 7, accuracy: 0.001)
    }

    @MainActor
    func testSplittingAnItemAndUndo() async throws {
        let recording = directory.appendingPathComponent("rec.mp4")
        try await VideoTestSupport.writeFakeRecording(to: recording, size: size, seconds: 6, fps: 30)
        VideoDemoDraftStore.delete(for: recording)
        let model = VideoEditorModel(videoURL: recording)
        await model.load()
        defer { VideoDemoDraftStore.delete(for: recording) }
        let clip = directory.appendingPathComponent("clip.mov")
        try await VideoInspection.writeColorVideo(to: clip, size: CGSize(width: 320, height: 180), colors: [(.red, 3)])
        let added = await model.addLayerItem(from: clip, at: 1)
        let id = try XCTUnwrap(added)
        XCTAssertEqual(model.selection, .layer(id))
        XCTAssertEqual(model.project.layerItem(id)?.length ?? 0, 3, accuracy: 0.05, "the whole video")
        let second = try XCTUnwrap(model.splitLayerItem(id, at: 2))
        XCTAssertEqual(model.project.layerItem(second)?.fileStart ?? 0, 1, accuracy: 0.001, "the second half starts a second in")
        XCTAssertEqual(model.project.layerItem(id)?.end ?? 0, 2, accuracy: 0.001)
        model.undo()
        XCTAssertNil(model.project.layerItem(second), "one ⌘Z joins them again")
        model.deleteLayerItem(id)
        XCTAssertTrue(model.project.layerTracks.isEmpty, "the empty track goes too")
        XCTAssertEqual(model.selection, .none)
    }
}
