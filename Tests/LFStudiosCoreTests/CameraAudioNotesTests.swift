import AppKit
import AVFoundation
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Face tracking, silence blocks, camera color, podcast mode with
/// audio-only exports, and speaker notes: off and neutral until turned on,
/// old projects as they were.
@MainActor
final class CameraAudioNotesTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        VideoTestStorage.isolate()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-cam-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func project(duration: Double = 12) -> VideoDemoProject {
        VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/camera-audio.mp4"), duration: duration, sourceSize: CGSize(width: 1600, height: 1000))
    }

    // MARK: Test audio

    /// Mono 48 kHz: "speech" (syllable-like bursts of a voiced sound) in
    /// `talking` stretches, quiet room noise elsewhere.
    static func writeSpeech(to url: URL, seconds: Double, talking: [ClosedRange<Double>], level: Float = 0.25) throws {
        let rate = 48_000.0
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let total = Int(seconds * rate)
        let chunk = 48_000
        var noise: UInt64 = 0x9E37_79B9_7F4A_7C15
        var written = 0
        while written < total {
            let count = min(chunk, total - written)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            buffer.frameLength = AVAudioFrameCount(count)
            let data = buffer.floatChannelData![0]
            for i in 0..<count {
                let t = Double(written + i) / rate
                noise = noise &* 6364136223846793005 &+ 1442695040888963407
                let hiss = (Float(noise >> 40) / Float(1 << 24) - 0.5) * 0.002
                guard talking.contains(where: { $0.contains(t) }) else {
                    data[i] = hiss
                    continue
                }
                // About four syllables a second, a voice near 140 Hz with
                // harmonics, and a little "s" now and then.
                let syllable = Float(max(sin(2 * .pi * 4 * t), 0))
                let pitch = 140 + 20 * sin(2 * .pi * 0.7 * t)
                var voice: Float = 0
                for harmonic in 1...6 { voice += Float(sin(2 * .pi * pitch * Double(harmonic) * t)) / Float(harmonic) }
                let sibilant = (Float(noise >> 41) / Float(1 << 23) - 0.5) * (sin(2 * .pi * 0.9 * t) > 0.92 ? 0.4 : 0)
                data[i] = level * syllable * voice * 0.5 + sibilant * 0.2 + hiss
            }
            try file.write(from: buffer)
            written += count
        }
    }

    /// A screen recording with that sound as its (only) audio track.
    private func recording(seconds: Double, talking: [ClosedRange<Double>], level: Float = 0.25) async throws -> URL {
        let video = folder.appendingPathComponent("picture.mp4")
        try await VideoTestSupport.writeFakeRecording(to: video, size: CGSize(width: 640, height: 400), seconds: seconds, fps: 30)
        let sound = folder.appendingPathComponent("voice.caf")
        try Self.writeSpeech(to: sound, seconds: seconds, talking: talking, level: level)
        let composition = AVMutableComposition()
        let picture = AVURLAsset(url: video)
        let audio = AVURLAsset(url: sound)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600))
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try videoTrack.insertTimeRange(range, of: try await picture.loadTracks(withMediaType: .video)[0], at: .zero)
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try audioTrack.insertTimeRange(range, of: try await audio.loadTracks(withMediaType: .audio)[0], at: .zero)
        // Picture passed through, the sound as AAC.
        let url = folder.appendingPathComponent("recording.mov")
        try await Self.mux(composition: composition, to: url)
        return url
    }

    /// The picture and the sound in one movie, both copied as they are.
    static func mux(composition: AVComposition, to url: URL) async throws {
        let session = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        session.outputURL = url
        session.outputFileType = .mov
        await session.export()
        if session.status != .completed { throw session.error ?? NSError(domain: "mux", code: 1) }
    }

    /// Integrated loudness of a sound file, as stereo.
    static func loudness(of url: URL) throws -> Double? {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
        let channels = Int(file.processingFormat.channelCount)
        let meter = VideoLoudnessMeter(channels: channels, sampleRate: file.processingFormat.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384)!
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: 16_384)
            guard buffer.frameLength > 0 else { break }
            meter.add(interleaved: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength) * channels))
        }
        return meter.integratedLoudness
    }

    // MARK: Off and neutral by default; old projects

    func testEverythingIsOffAndNeutralByDefault() {
        let fresh = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/a.mp4"))
        XCTAssertNil(fresh.faceTracking)
        XCTAssertNil(fresh.webcam.color)
        XCTAssertNil(fresh.audio.podcast)
        XCTAssertNil(fresh.audio.voiceRecipe)
        XCTAssertNil(fresh.speakerNotes)
        XCTAssertFalse(fresh.cameraLayouts.contains(where: \.isSilence))
        XCTAssertTrue(VideoCameraColor().isNeutral)
        XCTAssertFalse(VideoHandoffOptions().includeSpeakerNotes)
        XCTAssertFalse(VideoExportSettings().format.isAudioOnly)
        XCTAssertNil(KeyboardShortcutsDefault.pauseSpeakerNotes, "the notes shortcut has no default")
    }

    func testOldProjectsAndSettingsAreUnchanged() throws {
        var old = project()
        old.cameraLayouts = [VideoCameraLayoutRegion(start: 1, end: 3, layout: .hidden)]
        let json = String(data: try JSONEncoder().encode(old), encoding: .utf8)!
        for key in ["faceTracking", "speakerNotes", "\"color\"", "podcast", "isSilence"] {
            XCTAssertFalse(json.contains(key), "\(key) only once used")
        }
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, old)
        // Enhance voice keeps its old cache name (files made before still count).
        var audio = VideoAudioSettings()
        audio.enhanceVoice = true
        XCTAssertEqual(audio.voiceRecipe, .enhance)
        XCTAssertEqual(VideoVoiceRecipe.enhance.signature, "")
        // Handoff options saved before notes existed still load.
        let saved = try JSONDecoder().decode(VideoHandoffOptions.self, from: Data(#"{"clips":"full","lineUp":false,"includeFinal":true,"includeTimeline":false,"quality":"proRes422"}"#.utf8))
        XCTAssertEqual(saved.clips, .full)
        XCTAssertFalse(saved.lineUp)
        XCTAssertFalse(saved.includeSpeakerNotes)
    }

    // MARK: Color

    private func render(_ color: VideoCameraColor, _ image: CIImage) -> (r: Double, g: Double, b: Double) {
        let output = color.apply(to: image)
        let measure = VideoCameraColor.Measure.of(output)!
        return (measure.red, measure.green, measure.blue)
    }

    func testColorChangesTheCameraOnlyWhenSet() {
        let picture = CIImage(color: CIColor(red: 0.5, green: 0.45, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
        XCTAssertTrue(VideoCameraColor().apply(to: picture) === picture || VideoCameraColor().isNeutral, "neutral leaves the picture alone")
        let base = render(VideoCameraColor(), picture)
        let brighter = render(VideoCameraColor(brightness: 0.15), picture)
        XCTAssertGreaterThan(brighter.g, base.g + 0.08)
        let warmer = render(VideoCameraColor(warmth: 0.8), picture)
        XCTAssertGreaterThan(warmer.r - warmer.b, base.r - base.b + 0.03, "warmer: more red than blue")
        let cooler = render(VideoCameraColor(warmth: -0.8), picture)
        XCTAssertLessThan(cooler.r - cooler.b, base.r - base.b - 0.03)
        let grey = render(VideoCameraColor(saturation: 0), picture)
        XCTAssertEqual(grey.r, grey.b, accuracy: 0.01)
        // Every look is its own, and none is neutral.
        let looks = VideoCameraColor.Look.allCases.map(\.color)
        XCTAssertEqual(Set(looks.map { "\($0)" }).count, looks.count)
        XCTAssertTrue(looks.allSatisfy { !$0.isNeutral })
        XCTAssertEqual(VideoCameraColor.Look.warm.color.look, .warm)
    }

    func testColorIsForTheCameraNotTheScreen() {
        var project = project()
        project.background = .color(VideoRGBA(1, 1, 1))
        project.webcam.color = VideoCameraColor(saturation: 0, sharpness: 0)
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 12, recording: nil, hasWebcam: true)
        let output = CGSize(width: 960, height: 540)
        var options = VideoFrameRenderer.Options()
        options.webcamFrame = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        let screen = CIImage(color: CIColor(red: 0, green: 0.8, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        let image = VideoFrameRenderer().render(source: screen, timelineTime: 2, plan: plan, outputSize: output, options: options)
        let cg = VideoRenderContext.shared.createCGImage(image, from: CGRect(origin: .zero, size: output), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
        let bytes = TestImageBytes.rgba(cg)
        func pixel(_ point: CGPoint) -> (Int, Int, Int) {
            let i = (Int(point.y) * Int(output.width) + Int(point.x)) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }
        let bubble = VideoFrameRenderer.webcamRect(project.webcam, outputSize: output)
        let camera = pixel(CGPoint(x: bubble.midX, y: output.height - bubble.midY))
        XCTAssertEqual(camera.0, camera.1, accuracy: 8, "the red camera turned grey")
        let screenPixel = pixel(CGPoint(x: output.width / 2, y: output.height / 2))
        XCTAssertGreaterThan(screenPixel.1, 150, "the green screen stays green")
        XCTAssertLessThan(screenPixel.0, 40)
    }

    func testAutoAdjustSuggestsFromThePicture() {
        // Dark and blue: lift it and warm it up.
        let dark = VideoCameraColor.Measure(luminance: 0.25, spread: 0.1, red: 0.2, green: 0.24, blue: 0.36, chroma: 0.15)
        let suggestion = VideoCameraColor.suggestion(from: [dark, dark])
        XCTAssertGreaterThan(suggestion.brightness, 0.05)
        XCTAssertGreaterThan(suggestion.contrast, 1.1)
        XCTAssertGreaterThan(suggestion.warmth, 0.2)
        // Bright and orange: down a little, cooler.
        let bright = VideoCameraColor.Measure(luminance: 0.72, spread: 0.25, red: 0.8, green: 0.7, blue: 0.55, chroma: 0.3)
        let other = VideoCameraColor.suggestion(from: [bright])
        XCTAssertLessThan(other.brightness, 0)
        XCTAssertLessThan(other.warmth, 0)
        // A picture measured from pixels.
        let picture = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        let measured = try! XCTUnwrap(VideoCameraColor.Measure.of(picture))
        XCTAssertGreaterThan(measured.blue, measured.red + 0.1)
    }

    func testColorIsSavedInPresets() throws {
        var project = project()
        project.webcam.color = VideoCameraColor.Look.cinematic.color
        let preset = try JSONDecoder().decode(VideoStylePreset.self, from: JSONEncoder().encode(project.style))
        XCTAssertEqual(preset.webcam.color, VideoCameraColor.Look.cinematic.color)
        var other = self.project()
        other.apply(style: preset)
        XCTAssertEqual(other.webcam.color, project.webcam.color)
        var library = VideoStylePresetLibrary()
        XCTAssertTrue(library.add(name: "Film", style: preset, includesAspectRatio: false).matches(project))
        // Face tracking is the project's, not the preset's.
        project.faceTracking = VideoFaceTracking()
        XCTAssertTrue(library.presets[0].matches(project))
    }

    // MARK: Face tracking

    /// A face drifting from the left to the right between 2 and 4 s, then
    /// gone from 6 s.
    private func movingFace() -> VideoFaceAnalysis {
        var faces: [VideoFaceDetection] = []
        var times: [Double] = []
        for step in 0..<80 {
            let time = Double(step) / 8
            times.append(time)
            guard time < 6 else { continue }
            let progress = min(max((time - 2) / 2, 0), 1)
            faces.append(VideoFaceDetection(time: time, x: 0.15 + 0.5 * progress, y: 0.3, width: 0.18, height: 0.24))
        }
        return VideoFaceAnalysis(times: times, faces: faces, duration: 10)
    }

    private func center(_ crop: VideoCropRect) -> CGPoint { CGPoint(x: crop.x + crop.width / 2, y: crop.y + crop.height / 2) }

    func testTheCropFollowsTheFaceSmoothly() throws {
        let path = try XCTUnwrap(VideoFaceCropPath(analysis: movingFace(), settings: VideoFaceTracking(), pictureSize: CGSize(width: 1280, height: 720), bubbleAspect: 1, offset: 0))
        XCTAssertEqual(center(path.crop(atCameraTime: 1)).x, 0.24, accuracy: 0.03, "on the face at the start")
        let middle = center(path.crop(atCameraTime: 3)).x
        XCTAssertGreaterThan(middle, 0.3)
        XCTAssertLessThan(middle, 0.49, "following, a little behind")
        XCTAssertEqual(center(path.crop(atCameraTime: 5.5)).x, 0.74, accuracy: 0.03, "caught up")
        XCTAssertEqual(center(path.crop(atCameraTime: 9)).x, center(path.crop(atCameraTime: 5.9)).x, accuracy: 0.01, "no face: the last good framing")
        // No jumps from one frame to the next.
        var previous = center(path.crop(atCameraTime: 0)).x
        for frame in 1..<300 {
            let x = center(path.crop(atCameraTime: Double(frame) / 30)).x
            XCTAssertLessThan(abs(x - previous), 0.02)
            previous = x
        }
        // The bubble's shape: square here, on a 16:9 picture.
        let crop = path.crop(atCameraTime: 1)
        XCTAssertEqual(crop.width * 1280, crop.height * 720, accuracy: 1)
    }

    func testTightnessAndSmoothness() throws {
        var tight = VideoFaceTracking()
        tight.tightness = 1
        var loose = VideoFaceTracking()
        loose.tightness = 0
        let a = try XCTUnwrap(VideoFaceCropPath(analysis: movingFace(), settings: tight, pictureSize: CGSize(width: 1280, height: 720), bubbleAspect: 1, offset: 0))
        let b = try XCTUnwrap(VideoFaceCropPath(analysis: movingFace(), settings: loose, pictureSize: CGSize(width: 1280, height: 720), bubbleAspect: 1, offset: 0))
        XCTAssertLessThan(a.crop(atCameraTime: 1).height, b.crop(atCameraTime: 1).height * 0.7)
        var calm = VideoFaceTracking()
        calm.smoothness = 1
        var quick = VideoFaceTracking()
        quick.smoothness = 0
        let slow = try XCTUnwrap(VideoFaceCropPath(analysis: movingFace(), settings: calm, pictureSize: CGSize(width: 1280, height: 720), bubbleAspect: 1, offset: 0))
        let fast = try XCTUnwrap(VideoFaceCropPath(analysis: movingFace(), settings: quick, pictureSize: CGSize(width: 1280, height: 720), bubbleAspect: 1, offset: 0))
        XCTAssertLessThan(center(slow.crop(atCameraTime: 3)).x, center(fast.crop(atCameraTime: 3)).x, "smoother lags further behind")
        // Off: no path.
        var off = VideoFaceTracking()
        off.enabled = false
        XCTAssertNil(VideoFaceCropPath(analysis: movingFace(), settings: off, pictureSize: CGSize(width: 1280, height: 720), bubbleAspect: 1, offset: 0))
    }

    func testTheAnalysisIsCachedPerFile() async throws {
        let video = folder.appendingPathComponent("camera.mp4")
        try await VideoTestSupport.writeFakeRecording(to: video, size: CGSize(width: 320, height: 240), seconds: 1.5, fps: 15)
        XCTAssertNil(VideoFaceStore.load(for: video))
        let analysis = try await VideoFaceAnalyzer.analyze(url: video) { _ in }
        XCTAssertGreaterThan(analysis.times.count, 8, "about eight frames a second")
        XCTAssertTrue(analysis.faces.isEmpty, "a screen recording has no face")
        VideoFaceStore.save(movingFace(), for: video)
        XCTAssertEqual(VideoFaceStore.load(for: video), movingFace())
        XCTAssertTrue(FileManager.default.fileExists(atPath: VideoFaceStore.fileURL(for: video).path))
        // A changed file is a new video.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: video.path)
        XCTAssertNil(VideoFaceStore.load(for: video))
    }

    func testTheRendererUsesTheFaceCrop() throws {
        var project = project()
        project.faceTracking = VideoFaceTracking()
        let path = try XCTUnwrap(VideoFaceCropPath(analysis: movingFace(), settings: VideoFaceTracking(), pictureSize: CGSize(width: 640, height: 480), bubbleAspect: 1, offset: 0.5))
        // Source 1.5 s is camera 1 s.
        XCTAssertEqual(path.crop(atSourceTime: 1.5), path.crop(atCameraTime: 1))
        let plan = VideoRenderPlan(project: project, sourceDuration: 12, artwork: .empty, pointPixelScale: 2, cursorTrack: nil, camera: .identity, hasWebcam: true, faceCrop: path)
        XCTAssertNotNil(plan.faceCrop)
        let noCamera = VideoRenderPlan(project: project, sourceDuration: 12, artwork: .empty, pointPixelScale: 2, cursorTrack: nil, camera: .identity, hasWebcam: false, faceCrop: path)
        XCTAssertNil(noCamera.faceCrop)
    }

    // MARK: Silences

    func testSilenceBlocksFromATestAudioFile() async throws {
        let url = folder.appendingPathComponent("talk.caf")
        // Talking, 5 s of quiet, talking, 1.5 s of quiet, talking.
        try Self.writeSpeech(to: url, seconds: 14, talking: [0.5...3, 8...10, 11.5...13.5])
        let speech = await VideoVoiceActivity.speech(url: url, trackIndex: 0)
        XCTAssertFalse(speech.isEmpty)
        let long = VideoCameraSilence.silences(speech: speech, duration: 14, minimum: 3)
        XCTAssertEqual(long.count, 1)
        XCTAssertEqual(long[0].lowerBound, 3, accuracy: 0.35)
        XCTAssertEqual(long[0].upperBound, 8, accuracy: 0.35)
        let short = VideoCameraSilence.silences(speech: speech, duration: 14, minimum: 1)
        XCTAssertEqual(short.count, 2, "the 1.5 s pause counts at 1 s")

        var project = project(duration: 14)
        let own = VideoCameraLayoutRegion(start: 11.6, end: 13, layout: .fullscreen)
        project.cameraLayouts = [own]
        XCTAssertEqual(project.hideCameraDuringSilences(speech: speech, duration: 14, minimum: 1), 2, "the one under the user's block is left out — (the end) too short")
        XCTAssertTrue(project.cameraLayouts.contains(own))
        let blocks = project.cameraLayouts.filter(\.isSilence)
        XCTAssertTrue(blocks.allSatisfy { $0.layout == .hidden })
        XCTAssertGreaterThan(blocks[0].start, long[0].lowerBound, "starts just after the last word")
        // Pressing again replaces only its own blocks.
        XCTAssertEqual(project.hideCameraDuringSilences(speech: speech, duration: 14, minimum: 3), 1)
        XCTAssertEqual(project.cameraLayouts.filter(\.isSilence).count, 1)
        XCTAssertTrue(project.cameraLayouts.contains(own))
        // Saved and opened, a silence block is still one.
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded.cameraLayouts, project.cameraLayouts)
        // The minimum is kept within 1–10 s, and no speech at all is no silence.
        XCTAssertEqual(VideoCameraSilence.silences(speech: speech, duration: 14, minimum: 0.1), short)
        XCTAssertTrue(VideoCameraSilence.silences(speech: [], duration: 14, minimum: 2).isEmpty)
    }

    func testTheCameraHidesInTheSilentStretch() {
        var project = project(duration: 14)
        project.hideCameraDuringSilences(speech: [0...3, 8...14], duration: 14, minimum: 3)
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 14, recording: nil, hasWebcam: true)
        XCTAssertNil(plan.cameraLayout(at: 2))
        XCTAssertEqual(plan.cameraLayout(at: 5.5)?.layout, .hidden)
        XCTAssertEqual(plan.cameraLayout(at: 5.5)?.progress ?? 0, 1, accuracy: 0.001)
        let fading = plan.cameraLayout(at: 3.4)
        XCTAssertGreaterThan(fading?.progress ?? 0, 0)
        XCTAssertLessThan(fading?.progress ?? 1, 1, "a smooth fade")
    }

    // MARK: Podcast and audio only

    func testPodcastStepsAndRecipe() {
        var audio = VideoAudioSettings()
        audio.podcast = VideoPodcastSettings()
        let all = audio.voiceRecipe
        XCTAssertEqual(all?.isolation, true)
        XCTAssertEqual(all?.deEsser, true)
        XCTAssertEqual(all?.equalizer, .podcast)
        XCTAssertNotEqual(all?.signature, "")
        audio.podcast?.deEsser = false
        XCTAssertEqual(audio.voiceRecipe?.deEsser, false)
        XCTAssertNotEqual(audio.voiceRecipe?.signature, all?.signature, "each set of steps has its own cache")
        // Only loudness: nothing done to the voice, but the mix is evened out.
        audio.podcast = VideoPodcastSettings()
        audio.podcast?.noiseRemoval = false
        audio.podcast?.deEsser = false
        audio.podcast?.equalizer = false
        audio.podcast?.compressor = false
        audio.normalizeLoudness = false
        XCTAssertNil(audio.voiceRecipe)
        XCTAssertTrue(audio.normalizesLoudness)
        audio.podcast?.loudness = false
        XCTAssertFalse(audio.normalizesLoudness)
    }

    func testDeEsserAndGateDoTheirJob() {
        let rate = 48_000.0
        // A loud "s" (8 kHz) is turned down; a low voice (150 Hz) isn't.
        var deEsser = VideoVoiceDSP.DeEsser(sampleRate: rate)
        var hissIn: Float = 0, hissOut: Float = 0
        for i in 0..<Int(rate / 2) {
            let x = Float(0.3 * sin(2 * .pi * 8_000 * Double(i) / rate) + 0.05 * sin(2 * .pi * 150 * Double(i) / rate))
            let y = deEsser.process(x)
            if i > Int(rate / 10) { hissIn += x * x; hissOut += y * y }
        }
        XCTAssertLessThan(hissOut, hissIn * 0.6)
        var plain = VideoVoiceDSP.DeEsser(sampleRate: rate)
        var voiceIn: Float = 0, voiceOut: Float = 0
        for i in 0..<Int(rate / 2) {
            let x = Float(0.3 * sin(2 * .pi * 150 * Double(i) / rate))
            let y = plain.process(x)
            if i > Int(rate / 10) { voiceIn += x * x; voiceOut += y * y }
        }
        XCTAssertEqual(voiceOut, voiceIn, accuracy: voiceIn * 0.05)
        // The gate quiets noise below its threshold, not the voice above it.
        var gate = VideoVoiceDSP.Gate(threshold: 0.01, sampleRate: rate)
        var quiet: Float = 0
        for i in 0..<Int(rate) { quiet = gate.process(Float(0.002 * sin(Double(i)))) }
        XCTAssertLessThan(gate.gain, 0.3)
        _ = quiet
        for i in 0..<Int(rate / 5) { _ = gate.process(Float(0.3 * sin(2 * .pi * 200 * Double(i) / rate))) }
        XCTAssertGreaterThan(gate.gain, 0.95)
        // The limiter never lets a peak through.
        var limiter = VideoVoiceDSP.Limiter(ceiling: 0.5, sampleRate: rate)
        var peak: Float = 0
        for i in 0..<Int(rate / 5) { peak = max(peak, abs(limiter.process(Float(0.9 * sin(2 * .pi * 300 * Double(i) / rate))))) }
        XCTAssertLessThanOrEqual(peak, 0.5001)
    }

    func testPodcastLoudnessReachesMinus16LUFS() async throws {
        // Quiet talking (well under −16 LUFS), with pauses.
        let url = try await recording(seconds: 12, talking: [0.5...4, 5...8.5, 9.5...11.5], level: 0.05)
        var project = VideoDemoProject.make(sourceURL: url, duration: 12, sourceSize: CGSize(width: 640, height: 400))
        project.audio.normalizeLoudness = false
        let rawURL = folder.appendingPathComponent("raw.m4a")
        var settings = VideoExportSettings()
        settings.format = .m4a
        try await VideoDemoExporter.export(project: project, destinationURL: rawURL, settings: settings)
        let raw = try XCTUnwrap(try Self.loudness(of: rawURL))
        XCTAssertLessThan(raw, -24, "the test voice starts quiet (\(raw) LUFS)")

        // Podcast mode. (The voice isolation model may not know a synthetic
        // voice: these steps are the rest of the chain, ours and Apple's.)
        project.audio.podcast = VideoPodcastSettings()
        project.audio.podcast?.noiseRemoval = false
        let targets = project.voiceTargets(primaryKinds: [.mixed])
        XCTAssertEqual(targets.count, 1)
        try await VideoVoiceEnhancer.enhance(targets) { _ in }
        XCTAssertTrue(targets[0].isReady)
        for format in [VideoExportSettings.Format.m4a, .wav, .aiff] {
            settings.format = format
            let out = folder.appendingPathComponent("podcast.\(settings.fileExtension)")
            try await VideoDemoExporter.export(project: project, destinationURL: out, settings: settings)
            let loudness = try XCTUnwrap(try Self.loudness(of: out))
            XCTAssertEqual(loudness, -16, accuracy: 1, "\(format.rawValue): \(loudness) LUFS")
        }
    }

    func testAudioOnlyExportsInEveryFormat() async throws {
        let url = try await recording(seconds: 6, talking: [0.5...5.5])
        var project = VideoDemoProject.make(sourceURL: url, duration: 6, sourceSize: CGSize(width: 640, height: 400))
        // A cut: the export follows the edit.
        _ = project.deleteTimelineRange(start: 2, end: 3, totalDuration: 6)
        var settings = VideoExportSettings()
        let expected: [VideoExportSettings.Format: (AudioFormatID, UInt32)] = [.m4a: (kAudioFormatMPEG4AAC, 0), .wav: (kAudioFormatLinearPCM, 24), .aiff: (kAudioFormatLinearPCM, 24)]
        for format in VideoExportSettings.Format.audioFormats {
            settings.format = format
            let out = folder.appendingPathComponent("sound.\(settings.fileExtension)")
            try await VideoDemoExporter.export(project: project, destinationURL: out, settings: settings)
            let file = try AVAudioFile(forReading: out)
            let description = file.fileFormat.streamDescription.pointee
            XCTAssertEqual(description.mFormatID, expected[format]!.0, format.rawValue)
            if expected[format]!.1 > 0 { XCTAssertEqual(description.mBitsPerChannel, expected[format]!.1) }
            XCTAssertEqual(file.fileFormat.channelCount, 2)
            XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, 5, accuracy: 0.1, "\(format.rawValue): the edited length")
            if format == .aiff {
                XCTAssertNotEqual(description.mFormatFlags & kAudioFormatFlagIsBigEndian, 0, "AIFF is big-endian")
            }
        }
    }

    // MARK: Speaker notes

    func testTheNotesPanelIsNeverRecorded() {
        let notes = SpeakerNotes.shared
        notes.show()
        defer { notes.hide() }
        let panel = try! XCTUnwrap(notes.panel)
        XCTAssertTrue(panel.styleMask.contains(.titled), "a real, movable window…")
        XCTAssertFalse(RecordingCaptureFilter.isRealWindow(panel), "…that recordings leave out anyway")
        XCTAssertFalse(RecordingCaptureFilter.recordableOwnWindowIDs(in: [panel], front: panel).contains(CGWindowID(panel.windowNumber)))
        XCTAssertTrue(RecordingCaptureFilter.neverCapturedWindowIDs(in: [panel]).contains(CGWindowID(panel.windowNumber)))
        XCTAssertEqual(panel.sharingType, .none)
    }

    func testNotesGoWithTheRecordingOnlyWhenUsed() throws {
        let notes = SpeakerNotes.shared
        let saved = notes.text
        defer { notes.text = saved }
        notes.text = "Hello — first, the settings."
        notes.hide()
        notes.recordingStarted()
        XCTAssertNil(notes.recordingFinished(), "closed the whole time: not part of the take")
        notes.recordingStarted()
        notes.show()
        let kept = notes.recordingFinished()
        notes.hide()
        XCTAssertEqual(kept, "Hello — first, the settings.")
        notes.text = "   "
        notes.show()
        notes.recordingStarted()
        XCTAssertNil(notes.recordingFinished(), "empty notes aren't kept")
        notes.hide()

        var metadata = VideoDemoRecordingMetadata(videoURLPath: "/tmp/a.mp4", createdAt: Date(), duration: 5, sourceWidth: 100, sourceHeight: 100, fps: 30, nativeCursorVisible: false, cursorSamples: [], clickEvents: [])
        metadata.speakerNotes = kept
        var project = project()
        project.apply(metadata: metadata)
        XCTAssertEqual(project.speakerNotes, kept)
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded.speakerNotes, kept)
    }

    func testNotesScrollAndPause() async throws {
        let notes = SpeakerNotes.shared
        let saved = (notes.text, notes.speed, notes.startsWithRecording)
        defer {
            notes.stopScrolling()
            notes.hide()
            notes.text = saved.0
            notes.speed = saved.1
            notes.startsWithRecording = saved.2
        }
        notes.text = Array(repeating: "A line to read out loud while recording.", count: 80).joined(separator: "\n")
        notes.speed = 200
        notes.show()
        try await Task.sleep(nanoseconds: 300_000_000)
        let clip = try XCTUnwrap(notes.textView?.enclosingScrollView?.contentView)
        notes.rewind()
        notes.toggleScrolling()
        XCTAssertTrue(notes.isScrolling)
        XCTAssertFalse(notes.isEditing, "reading while it scrolls")
        try await Task.sleep(nanoseconds: 500_000_000)
        let moved = clip.bounds.origin.y
        XCTAssertGreaterThan(moved, 40)
        notes.toggleScrolling()
        XCTAssertFalse(notes.isScrolling)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(clip.bounds.origin.y, moved, accuracy: 0.5, "paused")
        // Starts with the recording when asked.
        notes.startsWithRecording = true
        notes.recordingStarted()
        XCTAssertTrue(notes.isScrolling)
        XCTAssertEqual(clip.bounds.origin.y, 0, accuracy: 0.5, "from the top")
        _ = notes.recordingFinished()
    }
}

/// Shortcuts that ship without keys.
@MainActor
enum KeyboardShortcutsDefault {
    static var pauseSpeakerNotes: String? {
        LFStudiosShortcut.pauseSpeakerNotes.name.defaultShortcut?.description
    }
}
