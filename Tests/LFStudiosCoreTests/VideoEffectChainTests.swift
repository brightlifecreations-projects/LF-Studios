import XCTest
@testable import LFStudiosCore

/// The effect chain (1.17.0): effects draw in their order; a card dragged
/// to a new place is one ⌘Z step; one switched off is kept but not drawn;
/// older files keep their order and bytes.
@MainActor
final class VideoEffectChainTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-chain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private func sample() -> CIImage {
        CIImage(color: CIColor(red: 0.8, green: 0.3, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 192, height: 108))
            .composited(over: CIImage(color: CIColor(red: 0.1, green: 0.5, blue: 0.9)).cropped(to: CGRect(x: 0, y: 0, width: 384, height: 216)))
    }

    private func pixels(_ image: CIImage) -> [UInt8] {
        let rect = CGRect(x: 0, y: 0, width: 384, height: 216)
        var data = [UInt8](repeating: 0, count: Int(rect.width * rect.height) * 4)
        VideoRenderContext.shared.render(image.cropped(to: rect), toBitmap: &data, rowBytes: Int(rect.width) * 4, bounds: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return data
    }

    func testOrderAndSwitchedOffEffects() {
        let blackWhite = VideoAppliedEffect(kind: .noir, intensity: 1)
        let vignette = VideoAppliedEffect(kind: .vignette, intensity: 1)
        let image = sample()
        let a = pixels(VideoEffectRenderer.apply([blackWhite, vignette], to: image, time: 0))
        let b = pixels(VideoEffectRenderer.apply([blackWhite, vignette], to: image, time: 0))
        XCTAssertEqual(a, b, "the same chain draws the same")
        var off = vignette
        off.off = true
        XCTAssertEqual(pixels(VideoEffectRenderer.apply([blackWhite, off], to: image, time: 0)),
                       pixels(VideoEffectRenderer.apply([blackWhite], to: image, time: 0)), "switched off: as if it weren't there")
    }

    func testOlderFilesKeepTheirBytes() throws {
        let effect = VideoAppliedEffect(kind: .glow, intensity: 0.6)
        let json = String(decoding: try JSONEncoder().encode(effect), as: UTF8.self)
        XCTAssertFalse(json.contains("off"), "on: nothing new in the file")
        var off = effect
        off.off = true
        let decoded = try JSONDecoder().decode(VideoAppliedEffect.self, from: try JSONEncoder().encode(off))
        XCTAssertFalse(decoded.isOn)
    }

    func testDraggingACardIsOneStep() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 4)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let id = model.addSticker(.star, at: 0)
        model.selection = .layer(id)
        let effects = [VideoAppliedEffect(kind: .glow), VideoAppliedEffect(kind: .vhs), VideoAppliedEffect(kind: .vignette)]
        XCTAssertTrue(model.perform(.edit(.setEffects(effects))))
        model.endGesture()

        var depth = model.undoDepth
        XCTAssertTrue(model.perform(.edit(.moveEffect(effects[2].id, 0))))
        XCTAssertEqual(model.undoDepth, depth + 1, "one ⌘Z step")
        XCTAssertEqual(model.selectedLayerItem?.effects?.map(\.kind), [.vignette, .glow, .vhs])
        XCTAssertFalse(model.perform(.edit(.moveEffect(effects[2].id, 0))), "already there: nothing")
        model.undo()
        XCTAssertEqual(model.selectedLayerItem?.effects?.map(\.kind), [.glow, .vhs, .vignette])

        depth = model.undoDepth
        XCTAssertTrue(model.perform(.edit(.setEffectOn(effects[1].id, false))))
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(model.selectedLayerItem?.effects?[1].isOn, false)
        XCTAssertTrue(model.perform(.edit(.removeEffect(effects[0].id))))
        XCTAssertEqual(model.selectedLayerItem?.effects?.map(\.kind), [.vhs, .vignette])

        // Locked: refused.
        let track = try XCTUnwrap(model.project.layerTrackIndex(of: id))
        model.toggleTrackLocked(.layer(model.project.layerTracks[track].id))
        XCTAssertFalse(model.perform(.edit(.moveEffect(effects[2].id, 0))))
    }
}
