import AVFoundation
import CoreImage
import Vision
import XCTest
@testable import LFStudiosCore

/// Checks on real exports for face tracking, hiding the camera during
/// silences, camera color and podcast mode, kept in
/// $LFSTUDIOS_TEST_FRAMES/camera-audio for a look. The voice is macOS's
/// own speech (`say`). Face tracking runs on a real camera video, by
/// default ~/Desktop/face-test.mov ($LFSTUDIOS_FACE_VIDEO for another
/// one), and is skipped while there's none.
@MainActor
final class ReleaseChecksCameraAudioTests: XCTestCase {
    private var out: URL!
    /// Files this test made (the checks run in parallel), removed after.
    private var scratch: URL!

    override func setUp() async throws {
        VideoTestStorage.isolate()
        let base = ProcessInfo.processInfo.environment["LFSTUDIOS_TEST_FRAMES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-test-frames", isDirectory: true)
        out = base.appendingPathComponent("camera-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-camera-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // Copies of the face video included.
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: Test media

    /// Spoken phrases at their moments over quiet room noise, mono 48 kHz.
    private func voice(seconds: Double, phrases: [(at: Double, text: String)], level: Float) throws -> URL {
        let rate = 48_000.0
        var samples = [Float](repeating: 0, count: Int(seconds * rate))
        var noise: UInt64 = 0x2545_F491_4F6C_DD1D
        for i in samples.indices {
            noise = noise &* 6364136223846793005 &+ 1442695040888963407
            samples[i] = (Float(noise >> 40) / Float(1 << 24) - 0.5) * 0.003
        }
        for (index, phrase) in phrases.enumerated() {
            let clip = scratch.appendingPathComponent("say-\(index).caf")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["--file-format=caff", "--data-format=LEF32@48000", "-o", clip.path, phrase.text]
            try say.run()
            say.waitUntilExit()
            let file = try AVAudioFile(forReading: clip, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let start = Int(phrase.at * rate)
            for i in 0..<Int(buffer.frameLength) where start + i < samples.count {
                samples[start + i] += buffer.floatChannelData![0][i] * level
            }
        }
        let url = scratch.appendingPathComponent("voice-\(UUID().uuidString).caf")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
        return url
    }

    /// A screen recording with that voice as its sound.
    private func recording(seconds: Double, voice: URL?) async throws -> URL {
        let picture = scratch.appendingPathComponent("screen-\(UUID().uuidString).mp4")
        try await VideoTestSupport.writeFakeRecording(to: picture, size: CGSize(width: 1440, height: 900), seconds: seconds, fps: 30)
        guard let voice else { return picture }
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600))
        let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try video.insertTimeRange(range, of: try await AVURLAsset(url: picture).loadTracks(withMediaType: .video)[0], at: .zero)
        let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try audio.insertTimeRange(range, of: try await AVURLAsset(url: voice).loadTracks(withMediaType: .audio)[0], at: .zero)
        let url = scratch.appendingPathComponent("recording-\(UUID().uuidString).mov")
        try await CameraAudioNotesTests.mux(composition: composition, to: url)
        return url
    }

    /// A stand-in camera picture: a warm-lit person-like figure in front of
    /// colored shelves (enough color for the looks to show).
    private static func cameraPicture(size: CGSize) -> CGImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let w = size.width, h = size.height
        let wall = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [CGColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1), CGColor(red: 0.62, green: 0.6, blue: 0.56, alpha: 1)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(wall, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        let books: [CGColor] = [CGColor(red: 0.75, green: 0.2, blue: 0.18, alpha: 1), CGColor(red: 0.2, green: 0.45, blue: 0.7, alpha: 1), CGColor(red: 0.85, green: 0.7, blue: 0.2, alpha: 1), CGColor(red: 0.25, green: 0.6, blue: 0.35, alpha: 1)]
        for i in 0..<12 {
            context.setFillColor(books[i % books.count])
            context.fill(CGRect(x: w * 0.03 + CGFloat(i) * w * 0.08, y: h * 0.72, width: w * 0.06, height: h * 0.2))
        }
        context.setFillColor(CGColor(red: 0.18, green: 0.22, blue: 0.32, alpha: 1))
        context.fillEllipse(in: CGRect(x: w * 0.25, y: -h * 0.25, width: w * 0.5, height: h * 0.6))
        context.setFillColor(CGColor(red: 0.86, green: 0.66, blue: 0.53, alpha: 1))
        context.fillEllipse(in: CGRect(x: w * 0.38, y: h * 0.3, width: w * 0.24, height: h * 0.45))
        context.setFillColor(CGColor(red: 0.25, green: 0.17, blue: 0.12, alpha: 1))
        context.fillEllipse(in: CGRect(x: w * 0.37, y: h * 0.62, width: w * 0.26, height: h * 0.16))
        return context.makeImage()!
    }

    /// The stand-in camera as a video.
    private func cameraVideo(seconds: Double) async throws -> URL {
        let size = CGSize(width: 640, height: 480)
        let url = scratch.appendingPathComponent("camera-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 480])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 480])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let picture = Self.cameraPicture(size: size)
        for frame in 0..<Int(seconds * 15) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            context?.draw(picture, in: CGRect(origin: .zero, size: size))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 15))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private func camera(_ url: URL, offset: Double = 0) async throws -> VideoImportedCamera {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let natural = try await track.load(.naturalSize).applying(try await track.load(.preferredTransform))
        return VideoImportedCamera(path: url.path, bookmark: nil, offset: offset, width: abs(natural.width), height: abs(natural.height), duration: try await asset.load(.duration).seconds)
    }

    private func export(_ project: VideoDemoProject, _ name: String, format: VideoExportSettings.Format = .mp4) async throws -> URL {
        var settings = VideoExportSettings()
        settings.format = format
        if !format.isAudioOnly {
            settings.resolution = .p1080
            settings.fps = 30
        }
        let url = out.appendingPathComponent("\(name).\(settings.fileExtension)")
        try? FileManager.default.removeItem(at: url)
        try await VideoDemoExporter.export(project: project, destinationURL: url, settings: settings)
        return url
    }

    private func frame(_ url: URL, at time: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    private func save(_ image: CGImage, _ name: String) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(out.appendingPathComponent("\(name).png") as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// The camera bubble's spot in a 1920×1080 frame, y down.
    private func bubble(_ project: VideoDemoProject) -> CGRect {
        let size = CGSize(width: 1920, height: 1080)
        let rect = VideoFrameRenderer.webcamRect(project.webcam, outputSize: size)
        return CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Average color in a part of a frame.
    private func average(_ image: CGImage, in rect: CGRect) -> (r: Double, g: Double, b: Double) {
        let measure = CIImage(cgImage: image)
        let flipped = CGRect(x: rect.minX, y: CGFloat(image.height) - rect.maxY, width: rect.width, height: rect.height)
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: measure, kCIInputExtentKey: CIVector(cgRect: flipped)])!
        var pixel = [UInt8](repeating: 0, count: 4)
        VideoRenderContext.shared.render(filter.outputImage!, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    private static func loudness(of url: URL) async throws -> Double? {
        if url.pathExtension != "mp4" { return try CameraAudioNotesTests.loudness(of: url) }
        // A movie: its sound, decoded.
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try await asset.loadTracks(withMediaType: .audio)[0], outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 2, AVSampleRateKey: 48_000])
        reader.add(output)
        reader.startReading()
        let meter = VideoLoudnessMeter(channels: 2, sampleRate: 48_000)
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            pointer?.withMemoryRebound(to: Float.self, capacity: length / 4) { meter.add(interleaved: UnsafeBufferPointer(start: $0, count: length / 4)) }
        }
        return meter.integratedLoudness
    }

    // MARK: Face tracking

    func testFaceTrackingOnARealCameraVideo() async throws {
        let source = ProcessInfo.processInfo.environment["LFSTUDIOS_FACE_VIDEO"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/face-test.mov")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("Face video not provided yet: record 10–15 s of yourself moving your head and save it as ~/Desktop/face-test.mov.")
        }
        // Work on a copy (removed after), never the original.
        let copy = scratch.appendingPathComponent("face-test.mov")
        try FileManager.default.copyItem(at: source, to: copy)
        let imported = try await camera(copy)
        let seconds = min(imported.duration, 15)
        var project = VideoDemoProject.make(sourceURL: try await recording(seconds: seconds, voice: nil), duration: seconds, sourceSize: CGSize(width: 1440, height: 900))
        project.importedCamera = imported
        project.webcam.visible = true
        project.webcam.size = 0.42

        let analysis = try await VideoFaceAnalyzer.analyze(url: copy) { _ in }
        print(String(format: "FACE: a face in %d of %d frames looked at", analysis.faces.count, analysis.times.count))
        XCTAssertGreaterThan(Double(analysis.faces.count), Double(analysis.times.count) * 0.6, "a face in most frames")
        VideoFaceStore.save(analysis, for: copy)
        defer { try? FileManager.default.removeItem(at: VideoFaceStore.fileURL(for: copy)) }

        let plain = try await export(project, "face-off")
        project.faceTracking = VideoFaceTracking()
        let tracked = try await export(project, "face-centered")
        defer {
            // Frames stay for a look; the movies show the user's face, so they go.
            try? FileManager.default.removeItem(at: plain)
            try? FileManager.default.removeItem(at: tracked)
        }

        // Where the face sits in the bubble: 0 is its middle, 0.5 its edge.
        let rect = bubble(project)
        func offsets(_ url: URL, _ name: String) async throws -> [Double] {
            var found: [Double] = []
            for (index, time) in stride(from: 0.8, through: seconds - 0.6, by: (seconds - 1.4) / 7).enumerated() {
                let image = try await frame(url, at: time)
                try save(image, "\(name)-\(index + 1)")
                guard let crop = image.cropping(to: rect) else { continue }
                let request = VNDetectFaceRectanglesRequest()
                try VNImageRequestHandler(cgImage: crop).perform([request])
                guard let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width })?.boundingBox else { continue }
                found.append(hypot(face.midX - 0.5, face.midY - 0.55))
            }
            return found
        }
        let before = try await offsets(plain, "face-off")
        let after = try await offsets(tracked, "face-centered")
        let mean = { (values: [Double]) in values.isEmpty ? 1 : values.reduce(0, +) / Double(values.count) }
        print(String(format: "FACE: off center by %.3f on average without tracking (%d frames), %.3f with it (%d frames, worst %.3f)", mean(before), before.count, mean(after), after.count, after.max() ?? 1))
        XCTAssertGreaterThanOrEqual(after.count, 6, "the face is in the bubble")
        XCTAssertLessThan(mean(after), 0.12, "the face stays near the middle")
        XCTAssertLessThanOrEqual(mean(after), mean(before) + 0.02)
    }

    // MARK: Hide camera during silences

    func testTheCameraHidesDuringASilence() async throws {
        let voice = try voice(seconds: 14, phrases: [
            (0.4, "Welcome to the demo. Today I'll show you the new export window."),
            (9.0, "And here is the finished video, ready to share."),
        ], level: 0.6)
        var project = VideoDemoProject.make(sourceURL: try await recording(seconds: 14, voice: voice), duration: 14, sourceSize: CGSize(width: 1440, height: 900))
        project.importedCamera = try await camera(try await cameraVideo(seconds: 14))
        project.webcam.visible = true
        project.webcam.size = 0.3

        let speech = await VideoVoiceActivity.speech(url: project.sourceURL, trackIndex: 0)
        print("SILENCE speech: \(speech.map { String(format: "%.2f–%.2f", $0.lowerBound, $0.upperBound) })")
        XCTAssertEqual(project.hideCameraDuringSilences(speech: speech, duration: 14, minimum: 3), 1)
        let block = try XCTUnwrap(project.cameraLayouts.first(where: \.isSilence))
        print(String(format: "SILENCE block: %.2f–%.2f", block.start, block.end))
        XCTAssertLessThan(block.start, 5.5)
        XCTAssertGreaterThan(block.end, 8)

        let url = try await export(project, "silence")
        let rect = bubble(project)
        // A spot on the stand-in's face, in the bubble's middle: skin while
        // the camera shows, the screen's background while it's hidden.
        let face = CGRect(x: rect.midX - 12, y: rect.midY - 12, width: 24, height: 24)
        let skin = (r: 0.86, g: 0.66, b: 0.53)
        var seen: [(String, Double)] = []
        for (name, time) in [("1-talking", 2.0), ("2-fading-out", block.start + 0.25), ("3-hidden", (block.start + block.end) / 2), ("4-fading-in", block.end - 0.25), ("5-talking-again", 11.5)] {
            let image = try await frame(url, at: time)
            try save(image, "silence-\(name)")
            let color = average(image, in: face)
            seen.append((name, abs(color.r - skin.r) + abs(color.g - skin.g) + abs(color.b - skin.b)))
        }
        try? FileManager.default.removeItem(at: url)
        print("SILENCE how far the bubble's middle is from skin: \(seen.map { "\($0.0) \(String(format: "%.3f", $0.1))" })")
        XCTAssertLessThan(seen[0].1, 0.25, "the camera shows while talking")
        XCTAssertGreaterThan(seen[2].1, seen[0].1 + 0.2, "the camera is gone in the silence")
        XCTAssertEqual(seen[4].1, seen[0].1, accuracy: 0.03, "and back when talking resumes")
    }

    // MARK: Camera color

    func testCameraColorLooks() async throws {
        var project = VideoDemoProject.make(sourceURL: try await recording(seconds: 2, voice: nil), duration: 2, sourceSize: CGSize(width: 1440, height: 900))
        project.importedCamera = try await camera(try await cameraVideo(seconds: 2))
        project.webcam.visible = true
        project.webcam.size = 0.5
        let rect = bubble(project)
        var looks: [(String, VideoCameraColor?)] = [("neutral", nil)]
        looks += VideoCameraColor.Look.allCases.map { ("\($0)", $0.color) }
        // Auto adjust, from the camera video itself.
        let measures = await VideoEditorModel.cameraMeasures(url: project.importedCamera!.url)
        XCTAssertFalse(measures.isEmpty)
        looks.append(("auto", VideoCameraColor.suggestion(from: measures)))

        var colors: [String: (r: Double, g: Double, b: Double)] = [:]
        for (name, color) in looks {
            project.webcam.color = color
            let url = try await export(project, "color-\(name)")
            let image = try await frame(url, at: 1)
            try save(image, "color-\(name)")
            try? FileManager.default.removeItem(at: url)
            colors[name] = average(image, in: rect)
            // The screen beside it isn't touched.
            colors["\(name)-screen"] = average(image, in: CGRect(x: 120, y: 120, width: 300, height: 200))
        }
        for (name, color) in colors.sorted(by: { $0.key < $1.key }) {
            print(String(format: "COLOR %@: r %.3f g %.3f b %.3f", name, color.r, color.g, color.b))
        }
        let neutral = try XCTUnwrap(colors["neutral"])
        XCTAssertGreaterThan(colors["warm"]!.r - colors["warm"]!.b, neutral.r - neutral.b + 0.02, "Warm is warmer")
        XCTAssertGreaterThan(colors["bright"]!.g, neutral.g + 0.02, "Bright is brighter")
        for name in looks.map(\.0) where name != "neutral" {
            let screen = colors["\(name)-screen"]!, plain = colors["neutral-screen"]!
            XCTAssertEqual(screen.r, plain.r, accuracy: 0.01, "\(name) leaves the screen alone")
            XCTAssertEqual(screen.b, plain.b, accuracy: 0.01)
        }
    }

    // MARK: Podcast mode

    func testPodcastModeOnARealVoice() async throws {
        // Talking quietly (well under −16 LUFS), with pauses.
        let voice = try voice(seconds: 16, phrases: [
            (0.3, "Hi everyone, and welcome back to the show. This week we're talking about recording at home."),
            (6.5, "Start with a quiet room, and sit close to the microphone. Soft surfaces help a lot."),
            (12.0, "That's it for today. See you next time."),
        ], level: 0.12)
        var project = VideoDemoProject.make(sourceURL: try await recording(seconds: 16, voice: voice), duration: 16, sourceSize: CGSize(width: 1440, height: 900))
        project.audio.normalizeLoudness = false
        let before = try await export(project, "podcast-before", format: .wav)
        let measured = try await Self.loudness(of: before)
        let raw = try XCTUnwrap(measured)
        print(String(format: "PODCAST before: %.2f LUFS", raw))
        XCTAssertLessThan(raw, -22)

        project.audio.podcast = VideoPodcastSettings()
        let targets = project.voiceTargets(primaryKinds: [.mixed])
        XCTAssertEqual(targets.count, 1)
        try await VideoVoiceEnhancer.enhance(targets) { _ in }
        XCTAssertTrue(targets[0].isReady)
        for format in [VideoExportSettings.Format.m4a, .wav, .aiff, .mp4] {
            let url = try await export(project, "podcast-after", format: format)
            let measured = try await Self.loudness(of: url)
            let loudness = try XCTUnwrap(measured)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            print(String(format: "PODCAST %@: %.2f LUFS, %d KB", format.rawValue, loudness, size / 1024))
            XCTAssertEqual(loudness, -16, accuracy: 1, "\(format.rawValue)")
        }
    }
}
