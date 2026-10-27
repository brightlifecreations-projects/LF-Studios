import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import LFStudiosCore

/// Synthetic recordings, real exports, and frame checks shared by the
/// export tests in this target.
enum TestVideos {
    /// A recording of `seconds` at `size`: a dark field with moving colored
    /// bars, so the picture is never flat.
    static func writeBars(to url: URL, size: CGSize = CGSize(width: 1280, height: 720), seconds: Int = 3, fps: Int = 30) async throws {
        try await writeVideo(to: url, size: size, seconds: seconds, fps: fps) { context, frame in
            let width = Int(size.width)
            context.setFillColor(CGColor(red: 0.16, green: 0.2, blue: 0.32, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            for bar in 0..<6 {
                let hue = CGFloat(bar) / 6
                context.setFillColor(CGColor(red: 0.5 + 0.4 * cos(hue * 6.28), green: 0.5 + 0.4 * cos(hue * 6.28 + 2.1), blue: 0.5 + 0.4 * cos(hue * 6.28 + 4.2), alpha: 1))
                context.fill(CGRect(x: CGFloat((bar * width / 6 + frame * 6) % (width + 200)) - 200, y: CGFloat(bar) * size.height / 6.5 + 30, width: 200, height: size.height / 10))
            }
        }
    }

    /// A camera picture in four solid quadrants (y down): red top left,
    /// green top right, blue bottom left, yellow bottom right.
    static func writeQuadrants(to url: URL, size: CGSize = CGSize(width: 640, height: 480), seconds: Int = 3, fps: Int = 30) async throws {
        try await writeVideo(to: url, size: size, seconds: seconds, fps: fps) { context, _ in
            drawQuadrants(context, size: size)
        }
    }

    static let quadrantColors: [(r: Double, g: Double, b: Double)] = [(0.9, 0.1, 0.1), (0.1, 0.8, 0.2), (0.15, 0.25, 0.9), (0.95, 0.85, 0.1)]

    /// CGContext is y up: the top quadrants are drawn at the top.
    static func drawQuadrants(_ context: CGContext, size: CGSize) {
        let w = size.width / 2, h = size.height / 2
        let boxes = [CGRect(x: 0, y: h, width: w, height: h), CGRect(x: w, y: h, width: w, height: h), CGRect(x: 0, y: 0, width: w, height: h), CGRect(x: w, y: 0, width: w, height: h)]
        for (box, color) in zip(boxes, quadrantColors) {
            context.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1))
            context.fill(box)
        }
    }

    /// The quadrant picture as an image, for the renderer's camera input.
    static func quadrantImage(size: CGSize = CGSize(width: 640, height: 480)) -> CIImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        drawQuadrants(context, size: size)
        return CIImage(cgImage: context.makeImage()!)
    }

    /// An H.264 movie; `draw` paints each frame (CGContext, y up).
    ///
    /// Reliable under load: the writer's pixel-buffer pool can fail to hand
    /// out a frame (IOSurface pressure, or the encoder service dropping the
    /// writer after a long run of exports), which used to stop the test at
    /// "Expectation failed: buffer". Now a frame the pool can't give is made
    /// directly, every step is checked, and a writer that fails is retried
    /// from scratch (three tries) before the real error is reported.
    static func writeVideo(to url: URL, size: CGSize, seconds: Int, fps: Int, draw: (CGContext, Int) -> Void) async throws {
        var failures: [String] = []
        for attempt in 1...3 {
            do {
                try await writeVideoOnce(to: url, size: size, seconds: seconds, fps: fps, draw: draw)
                return
            } catch let failure as WriteFailure {
                failures.append("try \(attempt): \(failure.reason)")
                try? FileManager.default.removeItem(at: url)
                try await Task.sleep(nanoseconds: 300_000_000 * UInt64(attempt))
            }
        }
        Issue.record("Couldn't write the test video \(url.lastPathComponent): \(failures.joined(separator: "; "))")
        throw WriteFailure(reason: failures.last ?? "")
    }

    struct WriteFailure: Error { let reason: String }

    /// Tests only: make the next writes of a file fail this way (exercises
    /// the retry). Keyed by path, so suites running alongside aren't touched.
    enum InjectedFailure { case pool, append, start }
    nonisolated(unsafe) private static var injectedFailures: [String: [InjectedFailure]] = [:]
    private static let injectionLock = NSLock()
    static func inject(_ failures: [InjectedFailure], into url: URL) {
        injectionLock.lock(); defer { injectionLock.unlock() }
        injectedFailures[url.path] = failures
    }
    private static func takeInjected(for url: URL) -> InjectedFailure? {
        injectionLock.lock(); defer { injectionLock.unlock() }
        guard var queue = injectedFailures[url.path], !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        injectedFailures[url.path] = queue
        return next
    }

    private static func writeVideoOnce(to url: URL, size: CGSize, seconds: Int, fps: Int, draw: (CGContext, Int) -> Void) async throws {
        let width = Int(size.width), height = Int(size.height)
        let injected = takeInjected(for: url)
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        writer.add(input)
        guard injected != .start, writer.startWriting() else {
            throw WriteFailure(reason: "startWriting failed: \(String(describing: writer.error))")
        }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(fps * seconds) {
            // Never wait on a writer that has stopped.
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw WriteFailure(reason: "writer stopped at frame \(frame): \(String(describing: writer.error))") }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            var buffer: CVPixelBuffer?
            var status: CVReturn = kCVReturnError
            if injected != .pool, let pool = adaptor.pixelBufferPool {
                status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            }
            if buffer == nil {
                // The pool couldn't give one: make it directly.
                let direct = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
                guard direct == kCVReturnSuccess, buffer != nil else {
                    throw WriteFailure(reason: "no frame buffer at frame \(frame) (pool \(status), direct \(direct)), writer \(writer.status.rawValue): \(String(describing: writer.error))")
                }
            }
            let pixels = buffer!
            CVPixelBufferLockBaseAddress(pixels, [])
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
                CVPixelBufferUnlockBaseAddress(pixels, [])
                throw WriteFailure(reason: "no drawing context at frame \(frame)")
            }
            draw(context, frame)
            CVPixelBufferUnlockBaseAddress(pixels, [])
            guard injected != .append || frame < 3, adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))) else {
                writer.cancelWriting()
                throw WriteFailure(reason: "append failed at frame \(frame): \(String(describing: writer.error))")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw WriteFailure(reason: "finishWriting ended \(writer.status.rawValue): \(String(describing: writer.error))")
        }
    }

    /// The color (0…1) of one output pixel, top-left origin.
    static func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        let i = (y * width + x) * 4
        return (Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255)
    }

    /// Whether two colors match; the default tolerance absorbs the
    /// renderer's color management (a drawn 0.9/0.1/0.1 red comes out
    /// about 0.93/0.2/0.13) and still tells the quadrants apart.
    static func close(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double), within tolerance: Double = 0.16) -> Bool {
        abs(a.r - b.r) < tolerance && abs(a.g - b.g) < tolerance && abs(a.b - b.b) < tolerance
    }

    /// Editor data the exporter keeps goes to a scratch folder.
    static func isolateStorage() throws {
        guard VideoStorageLocation.overrideRoot == nil else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-test-storage", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        VideoStorageLocation.overrideRoot = root
    }

    static func export(_ project: VideoDemoProject, to url: URL, format: VideoExportSettings.Format = .mp4, burnCaptions: Bool = true) async throws {
        var settings = VideoExportSettings()
        settings.format = format
        settings.resolution = .p1080
        settings.fps = 30
        settings.endCard = false
        settings.burnCaptions = burnCaptions
        try? FileManager.default.removeItem(at: url)
        try await VideoDemoExporter.export(project: project, destinationURL: url, settings: settings)
    }

    static func frame(ofMovie url: URL, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    /// The average color (0…1) of a box given in fractions of the frame,
    /// top-left origin.
    static func averageColor(of image: CGImage, x: Double, y: Double, width: Double = 0.02, height: Double = 0.02) -> (r: Double, g: Double, b: Double) {
        let bytes = rgba(image)
        let x0 = Int(x * Double(image.width)), y0 = Int(y * Double(image.height))
        let x1 = max(x0 + 1, Int((x + width) * Double(image.width))), y1 = max(y0 + 1, Int((y + height) * Double(image.height)))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for py in y0..<min(y1, image.height) {
            for px in x0..<min(x1, image.width) {
                let i = (py * image.width + px) * 4
                r += Double(bytes[i]); g += Double(bytes[i + 1]); b += Double(bytes[i + 2]); n += 1
            }
        }
        return (r / n / 255, g / n / 255, b / n / 255)
    }

    /// Where the frames for a test go: $LFSTUDIOS_TEST_FRAMES, or a folder in
    /// the temporary directory.
    static func framesDirectory(_ name: String) throws -> URL {
        let base = ProcessInfo.processInfo.environment["LFSTUDIOS_TEST_FRAMES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-test-frames", isDirectory: true)
        let url = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ image: CGImage, as url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
