import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import LFStudiosCore

/// Captions and shortcut keys moved by hand (VideoTextPlacement.swift).
@Suite("Caption and keycap placement")
struct VideoTextPlacementTests {
    static let frames: [(name: String, size: CGSize)] = [
        ("16:9", CGSize(width: 1920, height: 1080)),
        ("9:16", CGSize(width: 1080, height: 1920)),
        ("1:1", CGSize(width: 1080, height: 1080)),
    ]

    private func project(captions: Int = 2) -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/text-placement.mp4"), duration: 6, sourceSize: CGSize(width: 1280, height: 720))
        project.captions = (0..<captions).map { index in
            VideoCaptionLine(start: Double(index) * 2 + 0.2, end: Double(index) * 2 + 1.8, text: "Caption number \(index + 1)")
        }
        return project
    }

    /// Every key named "placement" in a saved project, with its path.
    private func placementKeys(in data: Data) throws -> [String] {
        var found: [String] = []
        func walk(_ value: Any, _ path: String) {
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    if key == "placement" { found.append(path + "." + key) }
                    walk(child, path + "." + key)
                }
            } else if let array = value as? [Any] {
                for (index, child) in array.enumerated() { walk(child, path + "[\(index)]") }
            }
        }
        walk(try JSONSerialization.jsonObject(with: data), "")
        return found
    }

    private func roundTrip(_ project: VideoDemoProject) throws -> VideoDemoProject {
        try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(project))
    }

    // MARK: Saving and loading

    @Test func placementsSurviveSavingAndLoading() throws {
        var project = project()
        project.placeAllCaptions(at: VideoTextPlacement(x: 0.3, y: 0.4))
        project.placeCaption(project.captions[1].id, at: VideoTextPlacement(x: 0.8, y: 0.9))
        project.placeKeystrokes(at: VideoTextPlacement(x: 0.1, y: 0.2))
        let loaded = try roundTrip(project)
        #expect(loaded.captionStyle.placement == VideoTextPlacement(x: 0.3, y: 0.4))
        #expect(loaded.captions[0].placement == nil)
        #expect(loaded.captions[1].placement == VideoTextPlacement(x: 0.8, y: 0.9))
        #expect(loaded.keystrokeStyle.placement == VideoTextPlacement(x: 0.1, y: 0.2))
        #expect(loaded == project)
    }

    @Test func oldProjectsOpenWithTheirTopOrBottomSetting() throws {
        var project = project()
        project.captionStyle.position = .top
        project.keystrokeStyle.position = .top
        // A project file from before placements: no such keys anywhere.
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        for key in ["captionStyle", "keystrokeStyle"] {
            var style = try #require(object[key] as? [String: Any])
            style.removeValue(forKey: "placement")
            object[key] = style
        }
        var lines = try #require(object["captions"] as? [[String: Any]])
        lines = lines.map { line in line.filter { $0.key != "placement" } }
        object["captions"] = lines
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(try placementKeys(in: data).isEmpty)

        let old = try JSONDecoder().decode(VideoDemoProject.self, from: data)
        #expect(old.captionStyle.position == .top)
        #expect(old.captionStyle.placement == nil)
        #expect(old.keystrokeStyle.position == .top)
        #expect(old.keystrokeStyle.placement == nil)
        #expect(old.captions.allSatisfy { $0.placement == nil })
        #expect(old.captionPlacement(for: old.captions[0].id) == nil)
    }

    @Test func nothingMovedWritesNoPlacementKeys() throws {
        let data = try JSONEncoder().encode(project())
        #expect(try placementKeys(in: data).isEmpty)
    }

    @Test func strayValuesInAFileLandInsideTheFrame() throws {
        let decoded = try JSONDecoder().decode(VideoTextPlacement.self, from: Data(#"{"x": 3.5, "y": -2}"#.utf8))
        #expect(decoded == VideoTextPlacement(x: 1, y: 0))
    }

    // MARK: One caption's own spot

    @Test func aCaptionsOwnSpotWinsOverEveryonesSpot() {
        var project = project(captions: 3)
        let ids = project.captions.map(\.id)
        #expect(project.captionPlacement(for: ids[0]) == nil, "nothing moved: the preset")

        project.placeAllCaptions(at: VideoTextPlacement(x: 0.5, y: 0.3))
        project.placeCaption(ids[1], at: VideoTextPlacement(x: 0.9, y: 0.9))
        #expect(project.captionPlacement(for: ids[0]) == VideoTextPlacement(x: 0.5, y: 0.3))
        #expect(project.captionPlacement(for: ids[1]) == VideoTextPlacement(x: 0.9, y: 0.9))
        #expect(project.captionPlacement(for: ids[2]) == VideoTextPlacement(x: 0.5, y: 0.3))
        #expect(project.hasCaptionsWithOwnPlacement)

        // Moving everyone again leaves the caption with its own spot alone.
        project.placeAllCaptions(at: VideoTextPlacement(x: 0.2, y: 0.2))
        #expect(project.captionPlacement(for: ids[1]) == VideoTextPlacement(x: 0.9, y: 0.9))
    }

    @Test func resettingOneCaptionMakesItFollowTheOthers() {
        var project = project()
        let id = project.captions[0].id
        project.placeAllCaptions(at: VideoTextPlacement(x: 0.5, y: 0.3))
        project.placeCaption(id, at: VideoTextPlacement(x: 0.1, y: 0.1))
        project.placeCaption(id, at: nil)
        #expect(project.captions[0].placement == nil)
        #expect(project.captionPlacement(for: id) == VideoTextPlacement(x: 0.5, y: 0.3))
        #expect(!project.hasCaptionsWithOwnPlacement)
    }

    @Test func resetPositionGoesBackToTheBottomPreset() {
        var project = project()
        let own = project.captions[1].id
        project.setCaptionPreset(.top)
        project.placeAllCaptions(at: VideoTextPlacement(x: 0.4, y: 0.4))
        project.placeCaption(own, at: VideoTextPlacement(x: 0.9, y: 0.1))
        project.resetCaptionPlacement()
        #expect(project.captionStyle.placement == nil)
        #expect(project.captionStyle.position == .bottom)
        #expect(project.captionPlacement(for: project.captions[0].id) == nil)
        #expect(project.captionPlacement(for: own) == VideoTextPlacement(x: 0.9, y: 0.1), "its own spot stays")
    }

    @Test func applyingOneCaptionsSpotToAll() {
        var project = project(captions: 3)
        let ids = project.captions.map(\.id)
        project.placeCaption(ids[0], at: VideoTextPlacement(x: 0.2, y: 0.2))
        project.placeCaption(ids[2], at: VideoTextPlacement(x: 0.7, y: 0.8))
        project.applyCaptionPlacementToAll(from: ids[2])
        #expect(project.captionStyle.placement == VideoTextPlacement(x: 0.7, y: 0.8))
        #expect(project.captions.allSatisfy { $0.placement == nil })
        #expect(ids.allSatisfy { project.captionPlacement(for: $0) == VideoTextPlacement(x: 0.7, y: 0.8) })
    }

    @Test func aPresetClearsEveryonesSpotButNotOwnSpots() {
        var project = project()
        project.placeAllCaptions(at: VideoTextPlacement(x: 0.4, y: 0.4))
        project.placeCaption(project.captions[0].id, at: VideoTextPlacement(x: 0.1, y: 0.9))
        project.setCaptionPreset(.top)
        #expect(project.captionStyle.position == .top)
        #expect(project.captionStyle.placement == nil)
        #expect(project.captions[0].placement == VideoTextPlacement(x: 0.1, y: 0.9))
    }

    @Test func shortcutKeysMoveResetAndTakeAPreset() {
        var project = project()
        project.placeKeystrokes(at: VideoTextPlacement(x: 0.2, y: 0.5))
        #expect(project.keystrokeStyle.placement == VideoTextPlacement(x: 0.2, y: 0.5))
        project.setKeystrokePreset(.top)
        #expect(project.keystrokeStyle.placement == nil)
        #expect(project.keystrokeStyle.position == .top)
        project.placeKeystrokes(at: VideoTextPlacement(x: 0.9, y: 0.9))
        project.resetKeystrokePlacement()
        #expect(project.keystrokeStyle.placement == nil)
        #expect(project.keystrokeStyle.position == .bottom)
    }

    @Test func aTranslatedCaptionKeepsItsOwnSpot() {
        var project = project()
        let id = project.captions[0].id
        project.placeCaption(id, at: VideoTextPlacement(x: 0.15, y: 0.15))
        project.captionTracks.translations = [VideoCaptionTranslation(language: "de", lines: [.init(id: id, text: "Untertitel eins", sourceText: project.captions[0].text)])]
        project.captionTracks.active = "de"
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 6, recording: nil)
        let shown = plan.caption(at: project.captions[0].start + 0.5)
        #expect(shown?.text == "Untertitel eins")
        #expect(shown?.placement == VideoTextPlacement(x: 0.15, y: 0.15))
    }

    // MARK: Geometry: always inside the frame

    @Test(arguments: frames.map(\.size))
    func boxesStayInsideTheSafeMargin(frame: CGSize) {
        let margin = VideoTextPlacementGeometry.margin(outputSize: frame)
        let safe = CGRect(origin: .zero, size: frame).insetBy(dx: margin, dy: margin)
        let boxes = [CGSize(width: 300, height: 80), CGSize(width: frame.width * 0.7, height: 140), CGSize(width: 40, height: 40)]
        let spots = [(0.0, 0.0), (1.0, 1.0), (0.0, 1.0), (1.0, 0.0), (0.5, 0.5), (0.02, 0.97)]
        for box in boxes {
            for spot in spots {
                let rect = VideoTextPlacementGeometry.rect(size: box, placement: VideoTextPlacement(x: spot.0, y: spot.1), outputSize: frame)
                #expect(safe.insetBy(dx: -0.001, dy: -0.001).contains(rect), "\(box) at \(spot) on \(frame): \(rect)")
            }
        }
        // A spot well inside the frame is exactly where it was put.
        let centered = VideoTextPlacementGeometry.rect(size: CGSize(width: 200, height: 60), placement: VideoTextPlacement(x: 0.5, y: 0.5), outputSize: frame)
        #expect(abs(centered.midX - frame.width / 2) < 0.001)
        #expect(abs(centered.midY - frame.height / 2) < 0.001)
    }

    @Test(arguments: frames.map(\.size))
    func aBoxWiderThanTheRoomIsCentered(frame: CGSize) {
        let box = CGSize(width: frame.width * 1.2, height: 50)
        let rect = VideoTextPlacementGeometry.rect(size: box, placement: VideoTextPlacement(x: 0, y: 0.5), outputSize: frame)
        #expect(abs(rect.midX - frame.width / 2) < 0.001)
    }

    @Test(arguments: frames.map(\.size))
    func dragsSnapToTheGuides(frame: CGSize) {
        let box = CGSize(width: 400, height: 90)
        let margin = VideoTextPlacementGeometry.margin(outputSize: frame)
        func snap(_ x: CGFloat, _ y: CGFloat) -> (placement: VideoTextPlacement, guides: Set<VideoTextSnapGuide>) {
            VideoTextPlacementGeometry.snapped(center: CGPoint(x: x, y: y), size: box, outputSize: frame, threshold: 12)
        }

        let middle = snap(frame.width / 2 + 7, frame.height / 2 - 9)
        #expect(middle.guides == [.centerX, .centerY])
        #expect(middle.placement == VideoTextPlacement(x: 0.5, y: 0.5))

        let bottom = snap(frame.width / 2 - 5, frame.height - margin - box.height / 2 + 8)
        #expect(bottom.guides == [.centerX, .bottom])
        let bottomRect = VideoTextPlacementGeometry.rect(size: box, placement: bottom.placement, outputSize: frame)
        #expect(abs(bottomRect.maxY - (frame.height - margin)) < 0.001, "sits on the bottom safe margin")

        let top = snap(frame.width * 0.3, margin + box.height / 2 - 6)
        #expect(top.guides == [.top])
        let topRect = VideoTextPlacementGeometry.rect(size: box, placement: top.placement, outputSize: frame)
        #expect(abs(topRect.minY - margin) < 0.001)

        let free = snap(frame.width * 0.3, frame.height * 0.3)
        #expect(free.guides.isEmpty)

        // Dragged past the edge: stored inside the frame.
        let outside = snap(-500, frame.height + 500)
        let outsideRect = VideoTextPlacementGeometry.rect(size: box, placement: outside.placement, outputSize: frame)
        #expect(outsideRect.minX >= margin - 0.001)
        #expect(outsideRect.maxY <= frame.height - margin + 0.001)
    }

    // MARK: The renderer (what the preview and every export draw)

    private static let aspects: [(name: String, preset: VideoDemoProject.AspectPreset)] = [("16:9", .widescreen), ("9:16", .vertical), ("1:1", .square)]

    /// Draws one frame and returns where the caption and keys went, in
    /// output pixels (top-left origin).
    private func drawnLayout(_ project: VideoDemoProject, at time: Double) -> (layout: VideoTextLayout, size: CGSize) {
        let canvas = project.canvasSize()
        let scale = 640 / max(canvas.width, canvas.height)
        let size = CGSize(width: (canvas.width * scale).rounded(), height: (canvas.height * scale).rounded())
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 6, recording: nil)
        let source = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
        var options = VideoFrameRenderer.Options()
        options.recordsTextLayout = true
        let renderer = VideoFrameRenderer()
        _ = renderer.render(source: source, timelineTime: time, plan: plan, outputSize: size, options: options)
        return (renderer.textLayout, size)
    }

    @Test(arguments: aspects.map(\.preset))
    func aMovedCaptionIsDrawnWhereItWasPutAndInsideTheFrame(preset: VideoDemoProject.AspectPreset) throws {
        var project = project()
        project.aspectPreset = preset
        project.placeAllCaptions(at: VideoTextPlacement(x: 0.5, y: 0.4))
        project.placeCaption(project.captions[1].id, at: VideoTextPlacement(x: 1, y: 1))

        let first = drawnLayout(project, at: 1)
        let box = try #require(first.layout.caption)
        #expect(box.captionID == project.captions[0].id)
        let rect = box.rect(in: first.size)
        #expect(abs(rect.midX - first.size.width * 0.5) < 1.5)
        #expect(abs(rect.midY - first.size.height * 0.4) < 1.5)

        // Its own spot, the corner: pushed in to the safe margin.
        let second = drawnLayout(project, at: 3)
        let corner = try #require(second.layout.caption).rect(in: second.size)
        let margin = VideoTextPlacementGeometry.margin(outputSize: second.size)
        #expect(abs(corner.maxX - (second.size.width - margin)) < 1.5)
        #expect(abs(corner.maxY - (second.size.height - margin)) < 1.5)
        #expect(CGRect(origin: .zero, size: second.size).contains(corner))
    }

    @Test func changingTheAspectRatioKeepsCaptionsInside() throws {
        var project = project()
        project.placeAllCaptions(at: VideoTextPlacement(x: 0.02, y: 0.03))
        for aspect in Self.aspects {
            project.aspectPreset = aspect.preset
            project.crop = VideoCropRect(x: 0.1, y: 0.1, width: 0.6, height: 0.6)
            let drawn = drawnLayout(project, at: 1)
            let rect = try #require(drawn.layout.caption).rect(in: drawn.size)
            let margin = VideoTextPlacementGeometry.margin(outputSize: drawn.size)
            let safe = CGRect(origin: .zero, size: drawn.size).insetBy(dx: margin - 1, dy: margin - 1)
            #expect(safe.contains(rect), "\(aspect.name): \(rect) in \(drawn.size)")
        }
    }

    @Test(arguments: aspects.map(\.preset))
    func presetsStillStackAtTheBottomAndTop(preset: VideoDemoProject.AspectPreset) throws {
        var project = project()
        project.aspectPreset = preset
        let bottom = drawnLayout(project, at: 1)
        let margin = VideoTextPlacementGeometry.margin(outputSize: bottom.size)
        let bottomRect = try #require(bottom.layout.caption).rect(in: bottom.size)
        #expect(abs(bottomRect.maxY - (bottom.size.height - margin)) < 1.5, "Bottom preset, as before")
        #expect(abs(bottomRect.midX - bottom.size.width / 2) < 1.5)

        project.setCaptionPreset(.top)
        let top = drawnLayout(project, at: 1)
        let topRect = try #require(top.layout.caption).rect(in: top.size)
        #expect(abs(topRect.minY - margin) < 1.5, "Top preset, as before")
    }

    @Test func movedKeysAreDrawnThere() throws {
        var project = project()
        project.keystrokes = [VideoKeystrokeEvent(time: 1, keys: ["⌘", "⇧", "4"])]
        project.placeKeystrokes(at: VideoTextPlacement(x: 0.25, y: 0.3))
        let drawn = drawnLayout(project, at: 1.4)
        let rect = try #require(drawn.layout.keys).rect(in: drawn.size)
        #expect(abs(rect.midX - drawn.size.width * 0.25) < 1.5)
        #expect(abs(rect.midY - drawn.size.height * 0.3) < 1.5)
    }
}
