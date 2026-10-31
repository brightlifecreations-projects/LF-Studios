import AppKit
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import LFStudiosCore

/// Stickers and sound effects (1.15.0): our own, drawn and made in code,
/// listed in LICENSES.md; animated GIFs play; one undo step each.
@MainActor
final class VideoStickersSoundsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-stickers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    /// Share of pixels that aren't see-through.
    private func coverage(_ image: CGImage) -> Double {
        let ci = CIImage(cgImage: image)
        let average = ci.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: ci.extent)])
        var pixel = [Float](repeating: 0, count: 4)
        CIContext().render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        return Double(pixel[3])
    }

    func testEveryStickerDraws() {
        for sticker in VideoSticker.allCases {
            let image = sticker.image(pixelHeight: 120)
            XCTAssertNotNil(image, "\(sticker)")
            guard let image else { continue }
            XCTAssertEqual(Double(image.width) / Double(image.height), sticker.aspect, accuracy: 0.05)
            let covered = coverage(image)
            XCTAssertGreaterThan(covered, 0.03, "\(sticker) has something drawn")
            XCTAssertLessThan(covered, 0.98, "\(sticker) has a see-through background")
        }
    }

    func testEverySoundIsOursAudibleAndTheSameEachTime() throws {
        for effect in VideoSoundEffect.allCases {
            let samples = effect.samples()
            XCTAssertEqual(samples, effect.samples(), "\(effect) is made the same way every time")
            let peak = samples.map(abs).max() ?? 0
            XCTAssertGreaterThan(peak, 0.1, "\(effect) is audible")
            XCTAssertLessThanOrEqual(peak, 0.9, "\(effect) stays under −1 dBFS")
            XCTAssertLessThan(effect.length, 2.1)
            let url = try effect.fileURL()
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(Int(file.length), samples.count, "\(effect) file")
        }
    }

    func testLicensesListEverything() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let licenses = try String(contentsOf: root.appendingPathComponent("LICENSES.md"), encoding: .utf8)
        for name in ["Star", "Heart", "Speech", "Confetti", "Map pin", "Whoosh", "Riser", "Clock tick", "Camera shutter"] {
            XCTAssertTrue(licenses.contains(name), "\(name) is in LICENSES.md")
        }
        XCTAssertTrue(licenses.contains("\(VideoSticker.allCases.count) stickers"))
        XCTAssertTrue(licenses.contains("\(VideoSoundEffect.allCases.count) sounds"))
        for family in VideoTextFonts.families { XCTAssertTrue(licenses.contains(family), "\(family) is in LICENSES.md") }
    }

    func testAnimatedGIFsPlay() throws {
        let url = directory.appendingPathComponent("blink.gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for colour in [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1)] {
            let context = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(colour)
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let gif = try XCTUnwrap(VideoGIF.load(url.path))
        XCTAssertEqual(gif.frames.count, 2)
        XCTAssertEqual(gif.length, 1, accuracy: 0.01)
        var item = VideoLayerItem(kind: .image, path: url.path, name: "blink.gif", at: 1, length: 5, aspect: 1)
        item.width = 0.5
        let size = CGSize(width: 100, height: 100)
        let first = try XCTUnwrap(VideoLayerRenderer.image(for: item, frame: nil, outputSize: size, time: 1.2))
        let second = try XCTUnwrap(VideoLayerRenderer.image(for: item, frame: nil, outputSize: size, time: 1.7))
        let looped = try XCTUnwrap(VideoLayerRenderer.image(for: item, frame: nil, outputSize: size, time: 2.2))
        XCTAssertGreaterThan(VideoInspection.color(of: first, size: size, x: 0.5, y: 0.5).r, 0.8)
        XCTAssertGreaterThan(VideoInspection.color(of: second, size: size, x: 0.5, y: 0.5).b, 0.8)
        XCTAssertGreaterThan(VideoInspection.color(of: looped, size: size, x: 0.5, y: 0.5).r, 0.8, "it loops")
    }

    func testPlacingStickersAndSounds() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 6)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        var depth = model.undoDepth
        XCTAssertTrue(model.placeLibraryItem(VideoLibraryPayload(kind: "sticker", id: "heart"), at: 1.5, target: .layer(.automatic)))
        XCTAssertEqual(model.undoDepth, depth + 1)
        let sticker = try XCTUnwrap(model.selectedLayerItem)
        XCTAssertEqual(sticker.sticker, "heart")
        XCTAssertFalse(sticker.hasFile)
        XCTAssertTrue(model.project.needsFormat4)
        // Drawn on the video, keys and animations like any clip.
        let drawn = try XCTUnwrap(VideoLayerRenderer.image(for: sticker, frame: nil, outputSize: CGSize(width: 320, height: 180), time: 2))
        XCTAssertGreaterThan(VideoInspection.color(of: drawn, size: CGSize(width: 320, height: 180), x: 0.5, y: 0.5).r, 0.8, "a red heart in the middle")
        // A sound effect: its own sound track, one step.
        depth = model.undoDepth
        let id = await model.addSoundEffect(.whoosh, at: 2)
        XCTAssertEqual(model.undoDepth, depth + 1)
        let track = try XCTUnwrap(model.audioTrack(try XCTUnwrap(id)))
        XCTAssertEqual(track.pieces.first?.at ?? -1, 2, accuracy: 0.001)
        XCTAssertTrue(VideoAssetStore.isStored(track.path), "a copy, kept with the project")
    }
}
