import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import ShotStyleCore

/// Synthetic recordings, real exports, and frame checks shared by the
/// export tests in this target.
enum TestVideos {
    /// A recording of `seconds` at `size`: a dark field with moving colored
    /// bars, so the picture is never flat.
    static func writeBars(to url: URL, size: CGSize = CGSize(width: 1280, height: 720), seconds: Int = 3, fps: Int = 30) async throws {
        let width = Int(size.width), height = Int(size.height)
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(fps * seconds) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let context = try #require(CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            context.setFillColor(CGColor(red: 0.16, green: 0.2, blue: 0.32, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for bar in 0..<6 {
                let hue = CGFloat(bar) / 6
                context.setFillColor(CGColor(red: 0.5 + 0.4 * cos(hue * 6.28), green: 0.5 + 0.4 * cos(hue * 6.28 + 2.1), blue: 0.5 + 0.4 * cos(hue * 6.28 + 4.2), alpha: 1))
                context.fill(CGRect(x: CGFloat((bar * width / 6 + frame * 6) % (width + 200)) - 200, y: CGFloat(bar) * size.height / 6.5 + 30, width: 200, height: size.height / 10))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    /// Editor data the exporter keeps goes to a scratch folder.
    static func isolateStorage() throws {
        guard VideoStorageLocation.overrideRoot == nil else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shotstyle-test-storage", isDirectory: true)
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

    /// Where the frames for a test go: $SHOTSTYLE_TEST_FRAMES, or a folder in
    /// the temporary directory.
    static func framesDirectory(_ name: String) throws -> URL {
        let base = ProcessInfo.processInfo.environment["SHOTSTYLE_TEST_FRAMES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("shotstyle-test-frames", isDirectory: true)
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
