import AppKit
import AVFoundation
import CoreImage
import Vision
import XCTest
@testable import LFStudiosCore

/// Checks on real files for Whisper captions, caption animations, Adapt to
/// this ratio and Find private info, with frames kept in
/// $LFSTUDIOS_TEST_FRAMES/captions-privacy for a look. The Whisper check
/// downloads two models (Base and Large v3 Turbo, about 775 MB) into a
/// folder of its own and deletes them after; it runs only with
/// LFSTUDIOS_WHISPER_TEST=1.
@MainActor
final class ReleaseChecksCaptionsPrivacyTests: XCTestCase {
    private var out: URL!
    private var scratch: URL!

    override func setUp() async throws {
        VideoTestStorage.isolate()
        let base = ProcessInfo.processInfo.environment["LFSTUDIOS_TEST_FRAMES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-test-frames", isDirectory: true)
        out = base.appendingPathComponent("captions-privacy", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-captions-privacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func save(_ image: CIImage, size: CGSize, _ name: String) throws {
        try VideoTestSupport.writePNG(image, size: size, to: out.appendingPathComponent("\(name).png"))
    }

    private func save(_ image: CGImage, _ name: String) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(out.appendingPathComponent("\(name).png") as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func frame(_ url: URL, at time: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    // MARK: Whisper against Apple

    nonisolated static let script = "Welcome to the quarterly update. Today we will review the new export window, then walk through the privacy settings. Finally, we will answer three questions from the community about keyboard shortcuts."

    /// Word error rate: edits to turn what was heard into the script, per
    /// script word.
    nonisolated static func wordErrorRate(_ heard: String, script: String = script) -> Double {
        func words(_ text: String) -> [String] {
            text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let a = words(script), b = words(heard)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var next = [i] + Array(repeating: 0, count: b.count)
            for j in stride(from: 1, through: b.count, by: 1) {
                next[j] = min(row[j] + 1, next[j - 1] + 1, row[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            row = next
        }
        return Double(row[b.count]) / Double(max(a.count, 1))
    }

    func testWhisperAgainstApple() async throws {
        guard ProcessInfo.processInfo.environment["LFSTUDIOS_WHISPER_TEST"] == "1" else {
            throw XCTSkip("Set LFSTUDIOS_WHISPER_TEST=1: downloads Whisper Base and Large v3 Turbo (about 775 MB), then deletes them")
        }
        let audio = scratch.appendingPathComponent("talk.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "-r", "175", "-o", audio.path, "[[slnc 800]] " + Self.script]
        try say.run()
        say.waitUntilExit()

        VideoWhisperModels.baseOverride = scratch.appendingPathComponent("Whisper", isDirectory: true)
        defer {
            // Deleted afterwards, as promised.
            for model in VideoWhisperModel.allCases { VideoWhisperModels.remove(model) }
            try? FileManager.default.removeItem(at: VideoWhisperModels.base)
            VideoWhisperModels.baseOverride = nil
        }

        var report: [String] = []
        let appleStart = Date()
        let apple = try await VideoCaptionTranscriber.transcribe(url: audio, languageIdentifier: "en-US") { _ in }
        let appleText = apple.words.map(\.text).joined(separator: " ")
        let appleWER = Self.wordErrorRate(appleText)
        report.append(String(format: "Apple: WER %.1f%% in %.1f s — %@", appleWER * 100, Date().timeIntervalSince(appleStart), appleText))

        for model in [VideoWhisperModel.base, .largeTurbo] {
            let downloadStart = Date()
            try await VideoWhisperModels.fetch(model) { _ in }
            XCTAssertTrue(VideoWhisperModels.isInstalled(model))
            let downloaded = Date().timeIntervalSince(downloadStart)
            let bytes = VideoWhisperModels.bytesOnDisk(model)
            let start = Date()
            let result = try await VideoWhisperTranscriber.transcribe(url: audio, trackIndex: nil, timeOffset: 0, languageIdentifier: "en-US", model: model) { _ in }
            let text = result.words.map(\.text).joined(separator: " ")
            let wer = Self.wordErrorRate(text)
            report.append(String(format: "Whisper %@: WER %.1f%% in %.1f s (download %.0f s, %@ on disk) — %@", model.title, wer * 100, Date().timeIntervalSince(start), downloaded, ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), text))
            XCTAssertLessThan(wer, model == .largeTurbo ? 0.12 : 0.25, model.title)
            XCTAssertTrue(zip(result.words, result.words.dropFirst()).allSatisfy { $0.start <= $1.start + 0.001 }, "in order")
            XCTAssertGreaterThan(result.words.first?.start ?? 0, 0.5, "times line up with the speech (after the pause)")
            // Into captions like Apple's words, and as an .srt.
            var project = VideoDemoProject.make(sourceURL: audio, duration: 20, sourceSize: CGSize(width: 1920, height: 1080))
            project.captions = VideoCaptionBuilder.lines(from: result.words)
            XCTAssertGreaterThanOrEqual(project.captions.count, 3)
            let srt = VideoCaptionBuilder.srt(lines: project.captions, segments: project.timelineSegments(totalDuration: 20), translation: nil)
            XCTAssertTrue(srt.contains("-->"))
            try srt.write(to: out.appendingPathComponent("whisper-\(model.rawValue).srt"), atomically: true, encoding: .utf8)
            VideoWhisperModels.remove(model)
            XCTAssertFalse(VideoWhisperModels.isInstalled(model), "deleted")
        }
        let summary = report.joined(separator: "\n")
        print("WHISPER\n" + summary)
        try summary.write(to: out.appendingPathComponent("whisper-vs-apple.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Caption animations

    func testEveryCaptionAnimationFrames() throws {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/anim.mp4"), duration: 6, sourceSize: CGSize(width: 1920, height: 1080))
        project.aspectPreset = .widescreen
        let words = ["Every", "word", "of", "your", "talk", "comes", "alive"]
        var t = 1.0
        let timed = words.map { word -> VideoCaptionWord in
            defer { t += 0.32 }
            return VideoCaptionWord(text: word, start: t, end: t + 0.26)
        }
        project.captions = [VideoCaptionLine(start: 1, end: 4, text: words.joined(separator: " "), words: timed)]
        project.captionStyle.visible = true
        project.captionStyle.size = .large
        project.captionStyle.font = VideoFontChoice(family: "Avenir Next", weight: .bold)
        let source = CIImage(cgImage: VideoTestSupport.fakeScreen(size: CGSize(width: 1920, height: 1080)))
        let output = CGSize(width: 960, height: 540)
        for animation in VideoCaptionAnimation.allCases {
            project.captionStyle.animation = animation
            let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 6, recording: nil)
            let renderer = VideoFrameRenderer()
            // Five moments side by side, the caption's strip only.
            var sheet = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: output.width, height: 150 * 5))
            for (index, time) in [1.05, 1.4, 1.75, 2.3, 3.5].enumerated() {
                let image = renderer.render(source: source, timelineTime: time, plan: plan, outputSize: output, options: VideoFrameRenderer.Options())
                let strip = image.cropped(to: CGRect(x: 0, y: 0, width: output.width, height: 150))
                sheet = strip.transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(4 - index) * 150)).composited(over: sheet)
            }
            try save(sheet, size: CGSize(width: output.width, height: 750), "animation-\(animation.rawValue)")
        }
        // In a vertical frame, at a spot of its own.
        project.aspectPreset = .vertical
        project.captionStyle.animation = .karaoke
        project.captions[0].placement = VideoTextPlacement(x: 0.5, y: 0.35)
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 6, recording: nil)
        let vertical = CGSize(width: 540, height: 960)
        try save(VideoFrameRenderer().render(source: source, timelineTime: 2, plan: plan, outputSize: vertical, options: VideoFrameRenderer.Options()), size: vertical, "animation-karaoke-vertical-placed")
    }

    // MARK: Adapt to this ratio

    func testAdaptFromSixteenNineToNineSixteen() throws {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/adapt.mp4"), duration: 12, sourceSize: CGSize(width: 1440, height: 900))
        project.aspectPreset = .widescreen
        project.padding = 0.06
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 12)
        project.cursorSamples = samples
        project.clickEvents = clicks
        project.webcam.visible = true
        project.webcam.anchor = .bottomRight
        project.webcam.size = 0.3
        // A zoom on the left of the screen, its subject shown off-center
        // (as "Fit zooms around camera" leaves it).
        var zoom = VideoZoomRegion(start: 3, end: 8, scale: 2, followsCursor: false, focusX: 0.18, focusY: 0.3)
        zoom.offsetX = -0.22
        project.zoomRegions = [zoom]
        project.captions = [VideoCaptionLine(start: 0, end: 12, text: "Captions stay in the safe area")]
        project.captionStyle.visible = true
        let camera = CIImage(color: CIColor(red: 0.95, green: 0.55, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        func render(_ project: VideoDemoProject, at time: Double, _ name: String) throws {
            let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 12, recording: nil, hasWebcam: true)
            var options = VideoFrameRenderer.Options()
            options.webcamFrame = camera
            let size = project.canvasSize().width > project.canvasSize().height ? CGSize(width: 1280, height: 720) : CGSize(width: 540, height: 960)
            let source = CIImage(cgImage: VideoTestSupport.fakeScreen(size: CGSize(width: 1440, height: 900), progress: time / 12))
            try save(VideoFrameRenderer().render(source: source, timelineTime: time, plan: plan, outputSize: size, options: options), size: size, name)
        }
        try render(project, at: 1, "ratio-1-16x9")
        try render(project, at: 5.5, "ratio-1-16x9-zoom")
        project.switchRatio(to: .vertical)
        project.reframe = true
        try render(project, at: 1, "ratio-2-9x16-before-adapt")
        try render(project, at: 5.5, "ratio-2-9x16-before-adapt-zoom")
        let report = project.adaptToCurrentRatio(hasCursor: true)
        print("ADAPT: \(report)")
        try render(project, at: 1, "ratio-3-9x16-adapted")
        try render(project, at: 5.5, "ratio-3-9x16-adapted-zoom")
        project.switchRatio(to: .widescreen)
        try render(project, at: 5.5, "ratio-4-16x9-restored-zoom")
        XCTAssertEqual(project.webcam.anchor, .bottomRight)
        XCTAssertEqual(project.zoomRegions[0].offsetX, -0.22)
    }

    // MARK: Find private info on a scrolling page

    static let page: [String] = [
        "Account settings",
        "Display name: Jordan Example",
        "Email: jane.doe@example.com",
        "Phone: +1 (415) 555-0132",
        "Billing card: 4242 4242 4242 4242",
        "OPENAI_API_KEY=sk-proj-4fG7hJ2kL9mN3pQ8rS1tV6wX",
        "Notifications are on for weekly reports",
        "Team: Acme Design (5 members)",
        "Theme: follows the system appearance",
        "Last sign-in from Lisbon, two days ago",
        "Storage used: 12.4 GB of 50 GB",
        "Help center and keyboard shortcuts",
    ]

    /// Scroll offset in points at a moment: still, scrolling up 320 points
    /// over three seconds, still again.
    static func scroll(at time: Double) -> CGFloat {
        CGFloat(min(max((time - 2) / 3, 0), 1) * 320)
    }

    private func pageVideo(seconds: Double) async throws -> URL {
        let size = CGSize(width: 1280, height: 800)
        let url = scratch.appendingPathComponent("page.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 800, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 800])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let fps = 30
        for index in 0..<Int(seconds * Double(fps)) {
            let time = Double(index) / Double(fps)
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: 1280, height: 800, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            context.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let offset = Self.scroll(at: time)
            for (row, line) in Self.page.enumerated() {
                // Top-down rows, moved up as the page scrolls.
                let y = size.height - 120 - CGFloat(row) * 64 + offset
                guard y > -40, y < size.height + 40 else { continue }
                let font = NSFont.systemFont(ofSize: row == 0 ? 34 : 26, weight: row == 0 ? .bold : .regular)
                NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: NSColor(white: 0.12, alpha: 1)]).draw(at: CGPoint(x: 120, y: y))
            }
            NSGraphicsContext.restoreGraphicsState()
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private static func readText(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    func testPrivateInfoIsFoundAndTheBlurFollowsTheScroll() async throws {
        let video = try await pageVideo(seconds: 8)
        // Kept with the frames, to try in the app (made-up details only).
        try? FileManager.default.removeItem(at: out.appendingPathComponent("private-info-page.mp4"))
        try? FileManager.default.copyItem(at: video, to: out.appendingPathComponent("private-info-page.mp4"))
        let start = Date()
        let scan = try await VideoPrivacyReader.scan(url: video) { _ in }
        let firstScan = Date().timeIntervalSince(start)
        let again = Date()
        let cached = try await VideoPrivacyReader.scan(url: video) { _ in }
        let secondScan = Date().timeIntervalSince(again)
        XCTAssertEqual(cached, scan)
        print(String(format: "PRIVACY: %d frames read in %.1f s; again from the cache in %.2f s", scan.frames.count, firstScan, secondScan))
        XCTAssertLessThan(secondScan, 1)
        XCTAssertGreaterThan(scan.frames.count, 8 * 4, "more frames while the page moves")

        let items = VideoPrivacyTracker.items(from: scan, timeOffset: 0, onCamera: false, customWords: ["Acme Design"])
        for item in items {
            print(String(format: "PRIVACY found %@ “%@” %.2f–%.2f s, %d keys, y %.3f → %.3f", item.kind.title, item.text, item.start, item.end, item.keys.count, item.keys.first?.box.y ?? 0, item.keys.last?.box.y ?? 0))
        }
        let kinds = Set(items.map(\.kind))
        for kind in [VideoPrivacyKind.email, .phone, .card, .secret, .customWord] {
            XCTAssertTrue(kinds.contains(kind), "\(kind.title) found")
        }
        let email = try XCTUnwrap(items.first { $0.kind == .email })
        XCTAssertEqual(email.text, "jane.doe@example.com")
        XCTAssertLessThan(email.start, 0.5)
        XCTAssertGreaterThan(email.end, 3.8, "followed until it scrolls off the top")
        // The key stays on the page: one item all the way, moved up 320 of 800 points.
        let key = try XCTUnwrap(items.first { $0.kind == .secret })
        XCTAssertLessThan(key.start, 0.5)
        XCTAssertGreaterThan(key.end, 7.5, "followed through the scroll as one item")
        XCTAssertEqual((key.keys.first?.box.y ?? 0) - (key.keys.last?.box.y ?? 0), 0.4, accuracy: 0.03, "it moved up with the page")

        // Blur them all, export, and read the result: nothing private left.
        var project = VideoDemoProject.make(sourceURL: video, duration: 8, sourceSize: CGSize(width: 1280, height: 800))
        project.aspectPreset = .source
        project.overlayEffects = items.enumerated().map { $1.blurEffect(crop: .full, layer: $0) }
        let exported = scratch.appendingPathComponent("blurred.mp4")
        var settings = VideoExportSettings()
        settings.fps = 30
        try await VideoDemoExporter.export(project: project, destinationURL: exported, settings: settings)
        for (name, time) in [("1-still", 1.0), ("2-scrolling", 3.0), ("3-scrolling", 3.9), ("4-scrolling", 4.6), ("5-after", 6.5)] {
            let image = try await frame(exported, at: time)
            try save(image, "privacy-\(name)")
            let text = try Self.readText(image)
            for secret in ["example.com", "555-0132", "4242 4242", "sk-proj", "Acme"] {
                XCTAssertFalse(text.contains(secret), "\(name): “\(secret)” can't be read")
            }
            XCTAssertTrue(text.contains("Notifications") || text.contains("Storage") || text.contains("Theme"), "\(name): the rest of the page still reads")
            // The plain recording at that moment, for comparison.
            try save(try await frame(video, at: time), "privacy-\(name)-original")
        }
    }
}
