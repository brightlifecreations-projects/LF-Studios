import AVFoundation
import XCTest
@testable import LFStudiosCore

/// Motion tracking (1.15.0): following a square that moves across a
/// synthetic video, the clip moving with it, and the commands.
@MainActor
final class VideoMotionTrackingTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!
    private let size = CGSize(width: 320, height: 180)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-tracking-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("square.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    /// A 40-pixel checked square moving from x 40 to x 240 (of 320) over
    /// two seconds, on dark grey; its top at y 70.
    private func movingSquare() async throws -> URL {
        let url = directory.appendingPathComponent("square.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            let x = 40 + 200 * Double(frame) / 59
            let top = 70.0
            for i in 0..<4 {
                for j in 0..<4 {
                    context.setFillColor((i + j) % 2 == 0 ? CGColor(red: 1, green: 0.9, blue: 0.1, alpha: 1) : CGColor(red: 0.1, green: 0.3, blue: 1, alpha: 1))
                    // CGContext: bottom-left origin.
                    context.fill(CGRect(x: x + Double(i) * 10, y: size.height - top - 40 + Double(j) * 10, width: 10, height: 10))
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    /// Where the square starts, in shares of the frame from the top left.
    private var squareAtStart: CGRect { CGRect(x: 40 / size.width, y: 70 / size.height, width: 40 / size.width, height: 40 / size.height) }

    func testOffsetsBetweenPoints() {
        var track = VideoMotionTrack(points: [.init(t: 1, dx: 0, dy: 0), .init(t: 2, dx: 0.2, dy: -0.1)])
        XCTAssertEqual(track.offset(at: 0.5), .zero, "still before it starts")
        XCTAssertEqual(track.offset(at: 1.5).dx, 0.1, accuracy: 0.0001)
        XCTAssertEqual(track.offset(at: 9).dy, -0.1, accuracy: 0.0001, "holds after the end")
        track.shift(by: -1, length: 1)
        XCTAssertEqual(track.points.map(\.t), [0, 1])
        var item = VideoLayerItem(kind: .image, path: "/tmp/a.png", name: "a", at: 10, length: 5, aspect: 1)
        item.tracking = track
        XCTAssertEqual(item.shown(at: 11).item.x, 0.7, accuracy: 0.0001, "drawn where it follows")
        XCTAssertTrue(item.needsFormat4)
    }

    func testFollowsAMovingSquare() async throws {
        let url = try await movingSquare()
        let result = try await VideoMotionTracker.track(url, region: squareAtStart)
        XCTAssertNil(result.lostAt)
        let last = try XCTUnwrap(result.points.last)
        XCTAssertEqual(last.dx, 200 / size.width, accuracy: 0.05, "followed it across")
        XCTAssertEqual(last.dy, 0, accuracy: 0.04, "and not up or down")
    }

    func testTrackCommandMovesTheClip() async throws {
        let url = try await movingSquare()
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        // The video fills the frame (no padding): the box is where the square is.
        model.project.aspectPreset = .source
        model.project.padding = 0
        model.project.cursor.visible = false
        model.seek(to: 0)
        let id = model.addTextClip(VideoTextContent(string: "Hi"), at: 0)
        model.setLayerItem(id, label: "Clip Change") { $0.length = 2 }
        model.endGesture()
        let depth = model.undoDepth
        await model.trackMotion(id, region: squareAtStart)
        XCTAssertEqual(model.undoDepth, depth + 1, "one step")
        let item = try XCTUnwrap(model.project.layerItem(id))
        let moved = item.placed(at: 1.9).x - item.x
        XCTAssertEqual(moved, 190 / size.width, accuracy: 0.07, "the text went along")
        XCTAssertNil(model.motionTracking)
        // Stop following: one step; locked: refused.
        model.selection = .layer(id)
        XCTAssertTrue(model.perform(.edit(.clearTracking)))
        XCTAssertNil(model.project.layerItem(id)?.tracking)
        model.undo()
        model.toggleTrackLocked(.layer(model.project.layerTracks[0].id))
        XCTAssertFalse(model.perform(.edit(.clearTracking)))
        XCTAssertNotNil(model.project.layerItem(id)?.tracking)
    }
}
