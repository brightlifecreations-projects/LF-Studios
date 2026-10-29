import CoreGraphics
import Foundation
import Testing
@testable import LFStudiosCore

/// Select size (1.10.0): resizing the camera by its edges and corners,
/// keeping its shape, snapping, and carrying the size and place from the
/// preview before recording into the editor (VideoCameraSetup.swift).
@Suite("Camera size")
struct VideoCameraSizeTests {
    typealias Geometry = VideoCameraPreviewGeometry
    static let start = CGRect(x: 100, y: 100, width: 160, height: 90)
    static let bounds = CGRect(x: 0, y: 0, width: 960, height: 540)

    private func ratio(_ rect: CGRect) -> CGFloat { rect.width / rect.height }

    // MARK: Resizing

    @Test(arguments: VideoCameraHandle.resizing)
    func aFixedShapeKeepsItsRatio(handle: VideoCameraHandle) {
        for delta in [CGSize(width: 40, height: 10), CGSize(width: -30, height: -50), CGSize(width: 5, height: 60)] {
            let rect = Geometry.resized(Self.start, handle: handle, by: delta, aspect: 16 / 9, minimum: 24)
            #expect(abs(ratio(rect) - 16 / 9) < 0.001, "\(handle) by \(delta): \(rect)")
        }
    }

    @Test func theOppositeCornerStaysPut() {
        let rect = Geometry.resized(Self.start, handle: .bottomRight, by: CGSize(width: 80, height: 0), aspect: 16 / 9, minimum: 24)
        #expect(rect.minX == Self.start.minX && rect.minY == Self.start.minY)
        #expect(rect.width == 240 && abs(rect.height - 135) < 0.001)
        let left = Geometry.resized(Self.start, handle: .topLeft, by: CGSize(width: -80, height: 0), aspect: 16 / 9, minimum: 24)
        #expect(left.maxX == Self.start.maxX && left.maxY == Self.start.maxY)
        // An edge keeps the middle of the other direction.
        let edge = Geometry.resized(Self.start, handle: .right, by: CGSize(width: 80, height: 0), aspect: 16 / 9, minimum: 24)
        #expect(abs(edge.midY - Self.start.midY) < 0.001 && edge.minX == Self.start.minX)
    }

    @Test func freeChangesWidthAndHeightOnTheirOwn() {
        let wider = Geometry.resized(Self.start, handle: .right, by: CGSize(width: 100, height: 0), aspect: nil, minimum: 24)
        #expect(wider.width == 260 && wider.height == 90, "only the width")
        let taller = Geometry.resized(Self.start, handle: .bottom, by: CGSize(width: 0, height: 70), aspect: nil, minimum: 24)
        #expect(taller.width == 160 && taller.height == 160, "only the height")
        let corner = Geometry.resized(Self.start, handle: .bottomRight, by: CGSize(width: 20, height: 60), aspect: nil, minimum: 24)
        #expect(corner.width == 180 && corner.height == 150)
        // ⇧ in Free: the ratio it has now.
        let shift = Geometry.resized(Self.start, handle: .bottomRight, by: CGSize(width: 20, height: 60), aspect: ratio(Self.start), minimum: 24)
        #expect(abs(ratio(shift) - ratio(Self.start)) < 0.001)
    }

    @Test func neverTooSmallAndKeptInsideTheVideo() {
        let tiny = Geometry.resized(Self.start, handle: .bottomRight, by: CGSize(width: -500, height: -500), aspect: nil, minimum: 24)
        #expect(tiny.width >= 24 && tiny.height >= 24)
        let tinyShape = Geometry.resized(Self.start, handle: .bottomRight, by: CGSize(width: -500, height: 0), aspect: 16 / 9, minimum: 24)
        #expect(tinyShape.height >= 24 - 0.001 && abs(ratio(tinyShape) - 16 / 9) < 0.001)
        let huge = Geometry.resized(Self.start, handle: .bottomRight, by: CGSize(width: 5000, height: 0), aspect: 16 / 9, minimum: 24, within: Self.bounds)
        #expect(Self.bounds.contains(huge))
        #expect(abs(ratio(huge) - 16 / 9) < 0.01, "still the shape when it hits the edge")
        let moved = Geometry.resized(Self.start, handle: .move, by: CGSize(width: 5000, height: -5000), aspect: nil, minimum: 24, within: Self.bounds)
        #expect(Self.bounds.contains(moved) && moved.size == Self.start.size)
    }

    // MARK: Snapping

    @Test func movingSnapsToCornersEdgesAndTheCenter() {
        let margin: CGFloat = 22
        let nearCorner = CGRect(x: 960 - 160 - margin + 4, y: 540 - 90 - margin - 5, width: 160, height: 90)
        let corner = Geometry.snapped(nearCorner, handle: .move, in: Self.bounds, margin: margin, threshold: 7, keepsShape: true)
        #expect(corner.maxX == 960 - margin && corner.maxY == 540 - margin, "bottom right, at the usual margin")
        let nearEdge = CGRect(x: 3, y: 200, width: 160, height: 90)
        #expect(Geometry.snapped(nearEdge, handle: .move, in: Self.bounds, margin: margin, threshold: 7, keepsShape: true).minX == 0, "the edge itself")
        let nearCenter = CGRect(x: 480 - 80 + 5, y: 270 - 45 - 6, width: 160, height: 90)
        let center = Geometry.snapped(nearCenter, handle: .move, in: Self.bounds, margin: margin, threshold: 7, keepsShape: true)
        #expect(center.midX == 480 && center.midY == 270)
        let free = CGRect(x: 300, y: 200, width: 160, height: 90)
        #expect(Geometry.snapped(free, handle: .move, in: Self.bounds, margin: margin, threshold: 7, keepsShape: true) == free, "nothing near: left alone")
    }

    @Test func resizingSnapsOnlyFreeEdges() {
        let rect = CGRect(x: 300, y: 200, width: 160, height: 90)
        let nearRight = CGRect(x: 300, y: 200, width: 960 - 300 - 3, height: 90)
        #expect(Geometry.snapped(nearRight, handle: .right, in: Self.bounds, margin: 22, threshold: 7, keepsShape: false).maxX == 960)
        #expect(Geometry.snapped(nearRight, handle: .right, in: Self.bounds, margin: 22, threshold: 7, keepsShape: true) == nearRight, "a kept shape follows its edge")
        #expect(Geometry.snapped(rect, handle: .left, in: Self.bounds, margin: 22, threshold: 7, keepsShape: false) == rect)
    }

    // MARK: From before recording into the editor

    @Test(arguments: [VideoWebcamSettings.Shape.circle, .landscape, .portrait, .free])
    func aResizedPreviewIsTheEditorsCameraExactly(shape: VideoWebcamSettings.Shape) throws {
        let frame = CGRect(x: 200, y: 120, width: 960, height: 540)
        var setup = VideoRecordingCameraSetup(shape: shape)
        if shape == .free { setup.freeAspect = 1 }
        // The preview, resized by its corner and moved, in screen points
        // (y up): worked out y down like the window does.
        let preview = Geometry.rect(setup, in: frame)
        let flipped = CGRect(x: preview.minX, y: -preview.maxY, width: preview.width, height: preview.height)
        let aspect: CGFloat? = shape == .free ? nil : setup.webcam.effectiveAspect
        var resized = Geometry.resized(flipped, handle: .topLeft, by: CGSize(width: -120, height: -40), aspect: aspect, minimum: Geometry.minimumSide)
        resized = Geometry.resized(resized, handle: .move, by: CGSize(width: -300, height: -100), aspect: nil, minimum: Geometry.minimumSide)
        let onScreen = CGRect(x: resized.minX, y: -resized.maxY, width: resized.width, height: resized.height)
        if shape == .free { setup.freeAspect = Double(onScreen.width / onScreen.height) }
        let saved = Geometry.setup(setup, preview: onScreen, frame: frame)
        let placement = try #require(saved.placement, "moved inside the frame: carried over")

        // The editor at the recording's own pixels (2× points) draws it there.
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/size.mp4"), duration: 4, sourceSize: CGSize(width: 1920, height: 1080))
        var metadata = VideoDemoRecordingMetadata(videoURLPath: "/tmp/size.mp4", createdAt: Date(), duration: 4, sourceWidth: 1920, sourceHeight: 1080, fps: 30, nativeCursorVisible: true, cursorSamples: [], clickEvents: [])
        metadata.webcam = VideoWebcamRecording(path: "/tmp/size-camera.mov", offset: 0, width: 1280, height: 720)
        metadata.cameraSetup = saved
        project.apply(metadata: metadata)
        #expect(project.webcam.placement == placement)
        let canvas = project.canvasSize()
        let drawn = VideoFrameRenderer.webcamRect(project.webcam, outputSize: canvas)
        let scale = canvas.width / frame.width
        let expected = CGRect(x: (onScreen.minX - frame.minX) * scale, y: (onScreen.minY - frame.minY) * scale, width: onScreen.width * scale, height: onScreen.height * scale)
        for (a, b) in [(drawn.minX, expected.minX), (drawn.minY, expected.minY), (drawn.width, expected.width), (drawn.height, expected.height)] {
            #expect(abs(a - b) <= 2, "\(shape): drawn \(drawn), preview \(expected)")
        }
    }

    // MARK: In the editor

    @MainActor @Test func aHandPlacementIsOneUndo() {
        let model = VideoEditorModel(videoURL: URL(fileURLWithPath: "/tmp/size-undo.mp4"))
        let before = model.project.webcam
        // A drag ends in one change (VideoPreviewView.swift).
        model.setStyle {
            $0.webcam.placement = VideoWebcamSettings.Placement(x: 0.3, y: 0.4, width: 0.2)
            $0.webcam.freeAspect = 1.5
        }
        #expect(model.project.webcam.placement != nil)
        model.undo()
        #expect(model.project.webcam == before, "one ⌘Z undoes the whole drag")
    }

    @Test func eachRatioKeepsItsOwnPlacementAndAdaptFindsTheNearestSpot() {
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/size.mp4"), duration: 4, sourceSize: CGSize(width: 1920, height: 1080))
        project.webcam.placement = VideoWebcamSettings.Placement(x: 0.85, y: 0.8, width: 0.2)
        let snapshot = project.ratioSnapshot()
        #expect(snapshot.webcamPlacement == project.webcam.placement)
        project.webcam.placement = nil
        project.restore(snapshot)
        #expect(project.webcam.placement?.width == 0.2, "restored with its ratio")

        project.aspectPreset = .vertical
        let report = project.adaptToCurrentRatio(hasCursor: false)
        #expect(report.movedCamera)
        #expect(project.webcam.placement == nil)
        #expect(project.webcam.anchor == .topRight, "bottom right, moved up top on a vertical video")
        // An older version (no placement) still reads.
        let data = try? JSONEncoder().encode(snapshot)
        var object = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
        object.removeValue(forKey: "webcamPlacement")
        let old = try? JSONDecoder().decode(VideoRatioVersion.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old != nil && old?.webcamPlacement == nil)
    }
}
