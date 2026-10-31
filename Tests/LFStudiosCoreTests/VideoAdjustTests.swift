import AppKit
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Adjust and adjustment clips (1.15.0): each control's direction, HSL by
/// colour, curves, colour wheels, the export, and the commands.
@MainActor
final class VideoAdjustTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-adjust-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private func with(_ change: (inout VideoAdjustSettings) -> Void) -> VideoAdjustSettings {
        var s = VideoAdjustSettings()
        change(&s)
        return s
    }

    func testNeutralChangesNothing() {
        let s = VideoAdjustSettings()
        XCTAssertTrue(s.isNeutral)
        for r in stride(from: 0.0, through: 1, by: 0.25) {
            for b in stride(from: 0.0, through: 1, by: 0.5) {
                let out = s.transform(r, 0.4, b)
                XCTAssertEqual(out.0, r, accuracy: 0.000_1)
                XCTAssertEqual(out.2, b, accuracy: 0.000_1)
            }
        }
    }

    func testEachControlGoesTheRightWay() {
        let grey = (0.5, 0.5, 0.5)
        XCTAssertGreaterThan(with { $0.exposure = 0.5 }.transform(grey.0, grey.1, grey.2).0, 0.6, "exposure brightens")
        let contrast = with { $0.contrast = 0.6 }
        XCTAssertGreaterThan(contrast.transform(0.8, 0.8, 0.8).0, 0.82, "contrast: lights lighter")
        XCTAssertLessThan(contrast.transform(0.2, 0.2, 0.2).0, 0.18, "and darks darker")
        let grey2 = with { $0.saturation = -1 }.transform(0.9, 0.3, 0.2)
        XCTAssertEqual(grey2.0, grey2.2, accuracy: 0.01, "saturation −100 is grey")
        let warm = with { $0.temperature = 0.8 }.transform(0.5, 0.5, 0.5)
        XCTAssertGreaterThan(warm.0, warm.2 + 0.05, "warmer: redder than blue")
        XCTAssertGreaterThan(with { $0.shadows = 1 }.transform(0.1, 0.1, 0.1).0, 0.12, "shadows lift the dark")
        XCTAssertEqual(with { $0.shadows = 1 }.transform(0.95, 0.95, 0.95).0, 0.95, accuracy: 0.02, "not the light")
        XCTAssertLessThan(with { $0.highlights = -1 }.transform(0.9, 0.9, 0.9).0, 0.85, "highlights down")
        XCTAssertGreaterThan(with { $0.fade = 1 }.transform(0, 0, 0).0, 0.08, "fade lifts black")
        // Vibrance lifts a dull colour more than a strong one.
        let vib = with { $0.vibrance = 1 }
        let dull = vib.transform(0.55, 0.5, 0.45), strong = vib.transform(0.9, 0.1, 0.1)
        XCTAssertGreaterThan((dull.0 - dull.2) / 0.1, 1.3)
        XCTAssertLessThan((strong.0 - strong.2) / 0.8, 1.3)
    }

    func testHSLOnlyItsColour() {
        let s = with { $0.hsl = [VideoHSLColor.red.rawValue: .init(hue: 0, saturation: -1, luminance: 0)] }
        let red = s.transform(0.9, 0.1, 0.1)
        XCTAssertLessThan(red.0 - red.1, 0.2, "red loses its colour")
        let blue = s.transform(0.1, 0.2, 0.9)
        XCTAssertEqual(blue.2, 0.9, accuracy: 0.02, "blue stays")
        XCTAssertEqual(blue.0, 0.1, accuracy: 0.02)
        // Hue: red turns toward orange.
        let shifted = with { $0.hsl = [VideoHSLColor.red.rawValue: .init(hue: 1, saturation: 0, luminance: 0)] }.transform(0.9, 0.1, 0.1)
        XCTAssertGreaterThan(shifted.1, 0.3)
    }

    func testCurvesAndWheels() {
        let points = [VideoCurvePoint(x: 0, y: 0.1), VideoCurvePoint(x: 0.5, y: 0.7), VideoCurvePoint(x: 1, y: 0.9)]
        XCTAssertEqual(VideoCurve.value(points, at: 0), 0.1, accuracy: 0.000_1)
        XCTAssertEqual(VideoCurve.value(points, at: 0.5), 0.7, accuracy: 0.000_1)
        XCTAssertEqual(VideoCurve.value(points, at: 1), 0.9, accuracy: 0.000_1)
        var last = -1.0
        for x in stride(from: 0.0, through: 1, by: 0.02) {
            let y = VideoCurve.value(points, at: x)
            XCTAssertGreaterThanOrEqual(y, last - 0.000_1, "never turns back down")
            last = y
        }
        XCTAssertEqual(VideoCurve.value(VideoCurvePoint.straight, at: 0.37), 0.37, accuracy: 0.000_1)
        // A red curve lifts only red.
        let curved = with { $0.curves = .init(red: [VideoCurvePoint(x: 0, y: 0), VideoCurvePoint(x: 0.5, y: 0.8), VideoCurvePoint(x: 1, y: 1)]) }.transform(0.5, 0.5, 0.5)
        XCTAssertGreaterThan(curved.0, 0.75)
        XCTAssertEqual(curved.1, 0.5, accuracy: 0.01)
        // Lift toward blue: the shadows go blue, the highlights hardly.
        let lifted = with { var w = VideoAdjustSettings.Wheels(); w.lift = .init(x: cos(4 * .pi / 3), y: sin(4 * .pi / 3), luminance: 0); $0.wheels = w }
        let dark = lifted.transform(0.1, 0.1, 0.1), light = lifted.transform(0.95, 0.95, 0.95)
        XCTAssertGreaterThan(dark.2 - dark.0, 0.1)
        XCTAssertLessThan(abs(light.2 - light.0), 0.05)
    }

    func testAnAdjustmentClipInTheExport() async throws {
        let source = directory.appendingPathComponent("grey.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(NSColor(white: 0.35, alpha: 1), 4)])
        var project = VideoInspection.project(for: source, seconds: 4, size: CGSize(width: 320, height: 180))
        var clip = VideoLayerItem.adjustmentClip(at: 2, length: 2)
        clip.adjust = with { $0.exposure = 0.6 }
        project.layerTracks = [VideoLayerTrack(items: [clip])]
        XCTAssertTrue(project.needsFormat4)
        let output = directory.appendingPathComponent("bright.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let before = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 1), x: 0.5, y: 0.5)
        let during = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 3), x: 0.5, y: 0.5)
        XCTAssertGreaterThan(during.g, before.g + 0.15, "brighter while it plays \(before) → \(during)")
    }

    func testCommands() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 6)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        var depth = model.undoDepth
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "adjustment", id: "blank"), at: 0.5, target: .layer(.automatic)))
        XCTAssertEqual(model.undoDepth, depth + 1)
        let clip = try XCTUnwrap(model.selectedLayerItem)
        XCTAssertEqual(clip.role, .adjustment)
        XCTAssertNil(clip.adjust, "starts with nothing changed")
        // A slider drag: one step.
        depth = model.undoDepth
        for value in [0.1, 0.2, 0.3] {
            model.perform(.edit(.setAdjust(with { $0.contrast = value })))
        }
        model.endGesture()
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.selectedLayerItem?.adjust?.contrast ?? 0, 0.3, accuracy: 0.000_1)
        // Back to neutral: nothing stored.
        model.perform(.edit(.setAdjust(VideoAdjustSettings())))
        model.endGesture()
        XCTAssertNil(model.selectedLayerItem?.adjust)
        // A preset with a text clip selected: on it.
        let text = model.addTextClip(VideoTextContent(string: "Hi"), at: 0)
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "adjustment", id: "warm-up"), at: nil))
        XCTAssertEqual(model.project.layerItem(text)?.adjust?.temperature ?? 0, 0.45, accuracy: 0.001)
        // Presets all draw.
        for preset in VideoAdjustPreset.all { XCTAssertNotNil(VideoAdjustPreview.render(preset), preset.id) }
    }
}
