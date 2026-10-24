import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import ShotStyleCore

/// Real exports (the exporter, the renderer, the encoder) with one caption
/// moved to the top left and another, on its own, to the bottom right: each
/// lands on its safe margins and stays fully inside the frame, in 16:9 and
/// 9:16 MP4s and in a GIF.
///
/// Each frame is found by exporting the same project twice, with and
/// without captions burned in: what differs is the caption. The frames with
/// captions are saved as PNGs in $SHOTSTYLE_PLACEMENT_FRAMES (or a folder
/// in the temporary directory, printed by the test).
@Suite("Caption placement in real exports", .serialized)
struct VideoCaptionPlacementExportTests {
    let directory: URL
    let framesDirectory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("shotstyle-placement-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Editor data the exporter keeps goes to a scratch folder, not the
        // user's own.
        if VideoStorageLocation.overrideRoot == nil {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("shotstyle-test-storage", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            VideoStorageLocation.overrideRoot = root
        }
        if let path = ProcessInfo.processInfo.environment["SHOTSTYLE_PLACEMENT_FRAMES"] {
            framesDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            framesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("shotstyle-placement-frames", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)
    }

    /// The first caption's time (moved with every caption to the top left)
    /// and the second's (moved on its own to the bottom right).
    static let topLeftTime = 0.8
    static let bottomRightTime = 2.1

    // MARK: The test video

    /// A 3-second 1280×720 recording: moving colored bars, so the picture
    /// is never flat.
    private func writeSourceVideo() async throws -> URL {
        let url = directory.appendingPathComponent("source.mp4")
        let width = 1280, height = 720, fps = 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(fps * 3) {
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
                context.fill(CGRect(x: CGFloat((bar * 230 + frame * 6) % (width + 200)) - 200, y: CGFloat(bar * 110 + 40), width: 200, height: 70))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    private func project(source: URL, aspect: VideoDemoProject.AspectPreset) -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: source, duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        project.aspectPreset = aspect
        project.captions = [
            VideoCaptionLine(start: 0.3, end: 1.3, text: "Top left caption"),
            VideoCaptionLine(start: 1.6, end: 2.6, text: "Bottom right caption"),
        ]
        project.captionStyle.visible = true
        // Every caption to the top left; the second, on its own, to the
        // bottom right (both pushed in to the safe margins).
        project.placeAllCaptions(at: VideoTextPlacement(x: 0, y: 0))
        project.placeCaption(project.captions[1].id, at: VideoTextPlacement(x: 1, y: 1))
        return project
    }

    private func export(_ project: VideoDemoProject, format: VideoExportSettings.Format, captions: Bool, name: String) async throws -> URL {
        var settings = VideoExportSettings()
        settings.format = format
        settings.resolution = .p1080
        settings.fps = 30
        settings.endCard = false
        settings.burnCaptions = captions
        let url = directory.appendingPathComponent("\(name)-\(captions ? "captions" : "plain").\(format == .gif ? "gif" : "mp4")")
        try await VideoDemoExporter.export(project: project, destinationURL: url, settings: settings)
        return url
    }

    // MARK: Frames

    private func frame(ofMovie url: URL, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func frame(ofGIF url: URL, at seconds: Double) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        var elapsed = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            if elapsed + delay > seconds { return try #require(CGImageSourceCreateImageAtIndex(source, index, nil)) }
            elapsed += delay
        }
        Issue.record("the GIF is shorter than \(seconds) s")
        throw CancellationError()
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    /// The box (top-left origin, pixels) where the frame with captions
    /// differs from the one without.
    private static func captionBox(with captioned: CGImage, without plain: CGImage, threshold: Int) -> CGRect? {
        guard captioned.width == plain.width, captioned.height == plain.height else { return nil }
        let a = rgba(captioned), b = rgba(plain)
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<captioned.height {
            for x in 0..<captioned.width {
                let i = (y * captioned.width + x) * 4
                let difference = max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])), abs(Int(a[i + 2]) - Int(b[i + 2])))
                if difference > threshold {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func save(_ image: CGImage, _ name: String) throws {
        let url = framesDirectory.appendingPathComponent("\(name).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// Both captions on their safe margins and inside the frame.
    private func verify(name: String, topLeft: (captioned: CGImage, plain: CGImage), bottomRight: (captioned: CGImage, plain: CGImage), threshold: Int, tolerance: CGFloat) throws {
        let size = CGSize(width: topLeft.captioned.width, height: topLeft.captioned.height)
        let margin = VideoTextPlacementGeometry.margin(outputSize: size)
        try save(topLeft.captioned, "\(name)-top-left")
        try save(bottomRight.captioned, "\(name)-bottom-right")

        let first = try #require(Self.captionBox(with: topLeft.captioned, without: topLeft.plain, threshold: threshold), "\(name): no caption in the top-left frame")
        let second = try #require(Self.captionBox(with: bottomRight.captioned, without: bottomRight.plain, threshold: threshold), "\(name): no caption in the bottom-right frame")
        print("\(name) \(Int(size.width))×\(Int(size.height)), margin \(Int(margin)): top-left caption \(first), bottom-right caption \(second)")

        #expect(abs(first.minX - margin) <= tolerance, "\(name): top-left caption's left edge \(first.minX), margin \(margin)")
        #expect(abs(first.minY - margin) <= tolerance, "\(name): top-left caption's top edge \(first.minY), margin \(margin)")
        #expect(abs(second.maxX - (size.width - margin)) <= tolerance, "\(name): bottom-right caption's right edge \(second.maxX)")
        #expect(abs(second.maxY - (size.height - margin)) <= tolerance, "\(name): bottom-right caption's bottom edge \(second.maxY)")
        let frame = CGRect(origin: .zero, size: size)
        #expect(frame.insetBy(dx: margin - tolerance, dy: margin - tolerance).contains(first), "\(name): top-left caption fully inside")
        #expect(frame.insetBy(dx: margin - tolerance, dy: margin - tolerance).contains(second), "\(name): bottom-right caption fully inside")
        #expect(first.width > size.width * 0.08 && first.height > size.height * 0.02, "\(name): looks like a caption, not noise: \(first)")
    }

    // MARK: Tests

    @Test(arguments: [VideoDemoProject.AspectPreset.widescreen, .vertical])
    func mp4CaptionsLandWhereTheyWerePut(aspect: VideoDemoProject.AspectPreset) async throws {
        let source = try await writeSourceVideo()
        let project = project(source: source, aspect: aspect)
        let name = "mp4-\(aspect == .vertical ? "9x16" : "16x9")"
        let captioned = try await export(project, format: .mp4, captions: true, name: name)
        let plain = try await export(project, format: .mp4, captions: false, name: name)
        let topLeft = (try await frame(ofMovie: captioned, at: Self.topLeftTime), try await frame(ofMovie: plain, at: Self.topLeftTime))
        let bottomRight = (try await frame(ofMovie: captioned, at: Self.bottomRightTime), try await frame(ofMovie: plain, at: Self.bottomRightTime))
        let size = CGSize(width: topLeft.0.width, height: topLeft.0.height)
        #expect(aspect == .vertical ? size.height > size.width : size.width > size.height, "\(name) is \(size)")
        try verify(name: name, topLeft: topLeft, bottomRight: bottomRight, threshold: 60, tolerance: max(4, size.width * 0.004))
        print("Frames saved in \(framesDirectory.path)")
    }

    @Test func gifCaptionsLandWhereTheyWerePut() async throws {
        let source = try await writeSourceVideo()
        let project = project(source: source, aspect: .widescreen)
        let captioned = try await export(project, format: .gif, captions: true, name: "gif-16x9")
        let plain = try await export(project, format: .gif, captions: false, name: "gif-16x9")
        let topLeft = (try frame(ofGIF: captioned, at: Self.topLeftTime), try frame(ofGIF: plain, at: Self.topLeftTime))
        let bottomRight = (try frame(ofGIF: captioned, at: Self.bottomRightTime), try frame(ofGIF: plain, at: Self.bottomRightTime))
        try verify(name: "gif-16x9", topLeft: topLeft, bottomRight: bottomRight, threshold: 70, tolerance: 4)
        print("Frames saved in \(framesDirectory.path)")
    }
}
