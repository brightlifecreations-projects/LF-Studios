import AppKit
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Library ▸ Effects (1.15.0): every effect in pixels, effect clips over
/// what's under them, effects on a clip, and placing them (one step each).
@MainActor
final class VideoEffectsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-effects-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private let context = CIContext()

    private func difference(_ a: CIImage, _ b: CIImage) -> Double {
        let diff = a.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: b])
            .applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: a.extent)])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(diff, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        return Double(pixel[0] + pixel[1] + pixel[2]) / 3
    }

    func testEveryEffectChangesThePictureAndKeepsItsSize() {
        // At 1080 high, where the effects are measured.
        let small = VideoEffectPreview.sample
        let sample = small.transformed(by: CGAffineTransform(scaleX: 1080 / small.extent.height, y: 1080 / small.extent.height))
        for kind in VideoEffectKind.allCases {
            // Strobe and glitch flash on some moments: try a few.
            let changed = [0.0, 0.05, 0.1, 0.2, 0.35, 0.5].contains { time in
                difference(VideoEffectRenderer.apply(kind, to: sample, intensity: 1, time: time), sample) > 0.004
            }
            XCTAssertTrue(changed, "\(kind) changes the picture")
            let out = VideoEffectRenderer.apply(kind, to: sample, intensity: 1, time: 0.3)
            XCTAssertEqual(out.extent, sample.extent, "\(kind) stays the frame's size")
            XCTAssertEqual(difference(VideoEffectRenderer.apply(kind, to: sample, intensity: 0, time: 0.3), sample), 0, accuracy: 0.002, "\(kind) at 0 does nothing")
            XCTAssertNotNil(VideoEffectPreview.render(kind, time: 0.3))
        }
        // The same moment looks the same every time (preview and export agree).
        XCTAssertEqual(VideoEffectRenderer.random(42, 3), VideoEffectRenderer.random(42, 3))
        XCTAssertEqual(difference(VideoEffectRenderer.apply(.glitch, to: sample, intensity: 1, time: 1.25), VideoEffectRenderer.apply(.glitch, to: sample, intensity: 1, time: 1.25)), 0, accuracy: 0.0001)
    }

    func testAnEffectClipInTheExport() async throws {
        let source = directory.appendingPathComponent("white.mp4")
        try await VideoInspection.writeColorVideo(to: source, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        var project = VideoInspection.project(for: source, seconds: 4, size: CGSize(width: 320, height: 180))
        var clip = VideoLayerItem.effectClip(.letterbox, at: 2, length: 2)
        clip.level = 1
        project.layerTracks = [VideoLayerTrack(items: [clip])]
        XCTAssertTrue(project.needsFormat4)
        let output = directory.appendingPathComponent("bars.mp4")
        try await VideoDemoExporter.export(project: project, destinationURL: output, settings: VideoInspection.mp4Settings())
        let before = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 1), x: 0.5, y: 0.03)
        let during = VideoInspection.color(of: try VideoInspection.frame(of: output, at: 3), x: 0.5, y: 0.03)
        XCTAssertGreaterThan(before.r, 0.8, "white before the effect clip")
        XCTAssertLessThan(during.r, 0.2, "a black bar while it plays")
        XCTAssertGreaterThan(VideoInspection.color(of: try VideoInspection.frame(of: output, at: 3), x: 0.5, y: 0.5).r, 0.8, "the middle stays")
    }

    func testPlacingEffects() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 6)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        // Dropped at 1 s: an effect clip there, one step.
        var depth = model.undoDepth
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "effect", id: "vhs"), at: 1, target: .layer(.automatic)))
        XCTAssertEqual(model.undoDepth, depth + 1)
        let clip = try XCTUnwrap(model.selectedLayerItem)
        XCTAssertEqual(clip.role, .effect)
        XCTAssertEqual(clip.at, 1, accuracy: 0.001)
        XCTAssertEqual(clip.effects?.first?.kind, .vhs)
        XCTAssertFalse(clip.hasFile)
        // Its strength is keyed like any other setting.
        model.seek(to: 1.5)
        model.perform(.edit(.setValue(.intensity, 0.3)))
        model.endGesture()
        XCTAssertEqual(model.selectedLayerItem?.intensity ?? 0, 0.3, accuracy: 0.001)
        // + with a text clip selected: on the clip itself, one step.
        let text = model.addTextClip(VideoTextContent(string: "Hi"), at: 0)
        depth = model.undoDepth
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "effect", id: "glow"), at: nil))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.project.layerItem(text)?.effects?.map(\.kind), [.glow])
        // Take it off: one step.
        model.perform(.edit(.setEffects([])))
        model.endGesture()
        XCTAssertNil(model.project.layerItem(text)?.effects)
        // + with a main-track clip selected: an effect clip over that clip.
        let main = try XCTUnwrap(model.segments.first)
        model.selection = .clip(main.id)
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "effect", id: "noir"), at: nil))
        let over = try XCTUnwrap(model.selectedLayerItem)
        XCTAssertEqual(over.at, main.timelineStart, accuracy: 0.001)
        XCTAssertEqual(over.end, main.timelineEnd, accuracy: 0.01)
        // Locked: refused.
        let track = try XCTUnwrap(model.project.layerTracks.first { $0.items.contains { $0.id == text } })
        model.toggleTrackLocked(.layer(track.id))
        model.selection = .layer(text)
        let before = model.project.layerTracks
        XCTAssertFalse(model.addEffect(.blur, at: nil))
        XCTAssertEqual(model.project.layerTracks, before)
    }
}
