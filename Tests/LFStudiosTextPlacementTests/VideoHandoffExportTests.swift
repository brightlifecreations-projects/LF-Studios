import AppKit
import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import LFStudiosCore

/// Creative Handoff for real: a project with a screen recording (microphone
/// and Mac sound on their own tracks), a camera started 0.7 s later, music,
/// a picture, captions, and pointer data — cut, and one clip at 2×.
@Suite("Creative Handoff in a real export", .serialized)
struct VideoHandoffExportTests {
    typealias RGB = (r: Double, g: Double, b: Double)
    static let lag = 0.7
    static let micBeeps = [0.5, 1.3, 2.2, 3.6, 4.4, 5.2]
    static let systemBeeps = [0.9, 2.8, 4.9]
    static let palette = TestVideos.quadrantColors

    /// The color both videos show at a moment of the recording.
    static func colorIndex(world: Double) -> Int { Int((world / 0.5).rounded(.down)) % palette.count }

    private static func paint(_ context: CGContext, size: CGSize, world: Double, label: String, frame: Int) {
        let color = palette[colorIndex(world: world)]
        context.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let text = NSAttributedString(string: String(format: "%@ %03d  t=%.2f", label, frame, world), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size.height / 9, weight: .bold), .foregroundColor: NSColor.white,
        ])
        let line = CTLineCreateWithAttributedString(text)
        context.textPosition = CGPoint(x: (size.width - CTLineGetBoundsWithOptions(line, []).width) / 2, y: size.height * 0.08)
        CTLineDraw(line, context)
    }

    struct Fixture {
        var folder: URL
        var input: VideoHandoffInput
    }

    /// 6 s of screen with two sound tracks, a 6 s camera started 0.7 s
    /// later, music, a logo; the edit keeps 0–2.5 s and plays 3–6 s at 2×.
    private func fixture() async throws -> Fixture {
        try TestVideos.isolateStorage()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-handoff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fps = 30
        let screenSize = CGSize(width: 1280, height: 720), cameraSize = CGSize(width: 640, height: 480)
        let screenPicture = folder.appendingPathComponent("screen-picture.mp4"), cameraURL = folder.appendingPathComponent("phone.mp4")
        try await TestVideos.writeVideo(to: screenPicture, size: screenSize, seconds: 6, fps: fps) { context, frame in
            Self.paint(context, size: screenSize, world: Double(frame) / Double(fps), label: "SCREEN", frame: frame)
        }
        try await TestVideos.writeVideo(to: cameraURL, size: cameraSize, seconds: 6, fps: fps) { context, frame in
            Self.paint(context, size: cameraSize, world: Double(frame) / Double(fps) + Self.lag, label: "CAMERA", frame: frame)
        }
        let mic = folder.appendingPathComponent("mic.m4a"), system = folder.appendingPathComponent("system.m4a")
        try TestSounds.writeAudio(TestSounds.beeps(at: Self.micBeeps, seconds: 6, noise: 0), to: mic)
        try TestSounds.writeStereo(TestSounds.beeps(at: Self.systemBeeps, seconds: 6, noise: 0), to: system)
        let screen = folder.appendingPathComponent("Demo.mov")
        try await TestSounds.mux(video: screenPicture, audio: [mic, system], to: screen)
        let music = folder.appendingPathComponent("song.m4a")
        try TestSounds.writeStereo(TestSounds.beeps(at: [0.2, 1.0, 2.0], seconds: 3, gain: 0.4, noise: 0.05), to: music)
        let logo = folder.appendingPathComponent("logo.png")
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus(); NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: 64, height: 64).fill(); image.unlockFocus()
        try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: logo)

        var metadata = VideoDemoRecordingMetadata(videoURLPath: screen.path, createdAt: Date(), duration: 6, sourceWidth: 1280, sourceHeight: 720, fps: 30,
                                                  nativeCursorVisible: false, cursorSamples: [], clickEvents: [], pointPixelScale: 2, renderCursor: false)
        metadata.audioTracks = [.microphone, .system]
        metadata.webcam = VideoWebcamRecording(path: cameraURL.path, offset: Self.lag, width: 640, height: 480)
        var project = VideoDemoProject.make(sourceURL: screen, duration: 6, sourceSize: screenSize)
        project.apply(metadata: metadata)
        project.timelineClips = [
            VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 2.5),
            VideoDemoTimelineClip(sourceStart: 3, sourceEnd: 6, speed: 2),
        ]
        project.webcam.visible = true
        project.music = VideoMusicTrack(path: music.path, name: "song.m4a", duration: 3)
        var overlay = VideoDemoOverlayEffect(kind: .image, time: 1)
        overlay.image = VideoOverlayImage(path: logo.path, name: "logo.png", aspect: 1)
        project.overlayEffects = [overlay]
        project.captions = [VideoCaptionLine(start: 0.3, end: 1.8, text: "Open the settings"), VideoCaptionLine(start: 3.2, end: 5.0, text: "Then save")]
        project.cursorSamples = stride(from: 0.0, to: 6, by: 0.5).map { VideoDemoCursorSample(time: $0, x: $0 / 6, y: 0.5) }
        project.clickEvents = [VideoDemoClickEvent(time: 1.2, x: 0.2, y: 0.5, button: .left)]
        var settings = VideoExportSettings()
        settings.resolution = .p1080
        settings.fps = 30
        settings.endCard = false
        let input = await VideoHandoffInput.gather(name: "Demo", project: project, recording: metadata, appendedMetadata: [:], exportSettings: settings)
        return Fixture(folder: folder, input: input)
    }

    private func write(_ fixture: Fixture, options: VideoHandoffOptions, into destination: URL) async throws -> VideoHandoffWriter.Result {
        let name = VideoHandoffPlanner.folderName(project: "Demo") { FileManager.default.fileExists(atPath: destination.appendingPathComponent($0).path) }
        let plan = VideoHandoffPlanner.plan(fixture.input, options: options, folderName: name)
        return try await VideoHandoffWriter(plan: plan, input: fixture.input, parent: destination).run()
    }

    private func duration(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]).load(.duration).seconds
    }

    /// The edit's moment `t` on the recording's clock.
    static func world(edit t: Double) -> Double { t < 2.5 ? t : 3 + (t - 2.5) * 2 }

    @Test func trimmedAndLinedUpEverythingIsInItsPlace() async throws {
        let fixture = try await fixture()
        let destination = fixture.folder.appendingPathComponent("Chosen location", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let result = try await write(fixture, options: VideoHandoffOptions(), into: destination)
        let folder = result.folder

        // 1. A new folder, in the chosen place, named for the project and day.
        #expect(folder.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL)
        #expect(folder.lastPathComponent.hasPrefix("Demo – Handoff 20"))
        #expect(result.skipped.isEmpty, "\(result.skipped)")

        // 2. Every file in its folder.
        let listing = try Self.listing(folder)
        print("HANDOFF LISTING\n" + listing.joined(separator: "\n"))
        let expected = ["01 Screen/Clip 01.mov", "01 Screen/Clip 02.mov", "02 Camera/Camera.mov", "03 Audio/Microphone.wav", "03 Audio/System Audio.wav",
                        "03 Audio/Music.m4a", "03 Audio/Full Mix.wav", "04 Graphics/logo.png", "05 Captions/Captions.srt", "06 Final/Demo.mp4", "07 Data/Pointer, clicks and keys.json",
                        "Timeline.fcpxml", "Timeline (Premiere).xml", "README.txt"]
        for path in expected {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path), "\(path) is there")
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Fonts").path), "no empty folders")

        // 3. All the same length: the edit's 2.5 + 1.5 s.
        for path in expected where [".mov", ".wav", ".m4a", ".mp4"].contains(where: path.hasSuffix) {
            let length = try await duration(folder.appendingPathComponent(path))
            let tolerance = path.hasSuffix(".m4a") ? 0.06 : 0.035
            #expect(abs(length - 4.0) <= tolerance, "\(path) is \(length) s")
        }

        // 4. The camera is in step with the screen, through the cut and the 2× clip.
        let frames = try TestVideos.framesDirectory("handoff")
        let camera = folder.appendingPathComponent("02 Camera/Camera.mov")
        for t in [0.9, 1.6, 2.2, 2.9, 3.6] {
            let clip = folder.appendingPathComponent(t < 2.5 ? "01 Screen/Clip 01.mov" : "01 Screen/Clip 02.mov")
            let screenFrame = try await TestVideos.frame(ofMovie: clip, at: t)
            let cameraFrame = try await TestVideos.frame(ofMovie: camera, at: t)
            let want = Self.palette[Self.colorIndex(world: Self.world(edit: t))]
            let screenColor = TestVideos.averageColor(of: screenFrame, x: 0.45, y: 0.4, width: 0.1, height: 0.1)
            let cameraColor = TestVideos.averageColor(of: cameraFrame, x: 0.45, y: 0.4, width: 0.1, height: 0.1)
            #expect(TestVideos.close(screenColor, want), "screen at \(t) s shows \(String(describing: screenColor)), wanted \(String(describing: want))")
            #expect(TestVideos.close(cameraColor, want), "camera at \(t) s shows \(String(describing: cameraColor)), wanted the screen's \(String(describing: want))")
            let name = String(format: "%.1fs", t)
            try TestVideos.save(screenFrame, as: frames.appendingPathComponent("\(name)-screen.png"))
            try TestVideos.save(cameraFrame, as: frames.appendingPathComponent("\(name)-camera.png"))
        }
        // Lined up: Clip 02 is black before its moment.
        let early = try await TestVideos.frame(ofMovie: folder.appendingPathComponent("01 Screen/Clip 02.mov"), at: 1.0)
        let black = TestVideos.averageColor(of: early, x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        #expect(black.r < 0.05 && black.g < 0.05 && black.b < 0.05, "Clip 02 is black until it plays: \(black)")
        try TestVideos.save(early, as: frames.appendingPathComponent("1.0s-clip02-padding.png"))

        // 5. The sound plays where the edit plays it (the cut away beep is gone).
        let micOnsets = TestSounds.onsets(try TestSounds.read(folder.appendingPathComponent("03 Audio/Microphone.wav")))
        let micWanted = [0.5, 1.3, 2.2, 2.8, 3.2, 3.6]
        print("microphone beeps at \(micOnsets)")
        #expect(micOnsets.count == micWanted.count, "\(micOnsets)")
        for (found, want) in zip(micOnsets, micWanted) { #expect(abs(found - want) < 0.03, "mic beep at \(found), wanted \(want)") }
        let systemOnsets = TestSounds.onsets(try TestSounds.read(folder.appendingPathComponent("03 Audio/System Audio.wav")))
        print("Mac sound beeps at \(systemOnsets)")
        #expect(systemOnsets.count == 2, "the 2.8 s beep was cut: \(systemOnsets)")
        if systemOnsets.count == 2 {
            #expect(abs(systemOnsets[0] - 0.9) < 0.03 && abs(systemOnsets[1] - 3.45) < 0.03, "\(systemOnsets)")
        }
        let music = try TestSounds.read(folder.appendingPathComponent("03 Audio/Music.m4a"))
        #expect(music.map { abs($0) }.max() ?? 0 > 0.05, "the music plays")

        // The full mix is the finished video's sound, before AAC.
        let mix = TestSounds.envelope(try TestSounds.read(folder.appendingPathComponent("03 Audio/Full Mix.wav")))
        let finished = TestSounds.envelope(try await TestSounds.readTrack(folder.appendingPathComponent("06 Final/Demo.mp4")))
        let count = min(mix.count, finished.count)
        let difference = zip(mix.prefix(count), finished.prefix(count)).map { abs($0 - $1) }.reduce(0, +) / Double(count)
        let loudest = mix.max() ?? 0
        print("full mix vs finished video: mean envelope difference \(difference), loudest \(loudest)")
        #expect(loudest > 0.05, "the full mix has sound")
        #expect(difference < loudest * 0.08, "the full mix sounds like the finished video (\(difference))")
        // The mic's beeps are in it, where the edit plays them.
        // The Mac sound beeps at 3.45 s, close to the mic beep at 3.6 s: a short gap tells them apart.
        let mixOnsets = TestSounds.onsets(try TestSounds.read(folder.appendingPathComponent("03 Audio/Full Mix.wav")), threshold: 0.15, gap: 0.05)
        for want in [0.5, 1.3, 2.2, 2.8, 3.2, 3.6] {
            #expect(mixOnsets.contains { abs($0 - want) < 0.03 }, "a beep at \(want) s in the mix: \(mixOnsets)")
        }

        // 6. Captions on the edit's clock; data; README.
        let srt = try String(contentsOf: folder.appendingPathComponent("05 Captions/Captions.srt"), encoding: .utf8)
        #expect(srt.contains("00:00:00,300 --> 00:00:01,800"), "\(srt)")
        #expect(srt.contains("00:00:02,600 --> 00:00:03,500"), "the second caption moved with the 2× clip: \(srt)")
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("07 Data/Pointer, clicks and keys.json"))) as? [String: Any]
        #expect((data?["pointer"] as? [Any])?.count == 12)
        let readme = try String(contentsOf: folder.appendingPathComponent("README.txt"), encoding: .utf8)
        print(readme)
        for path in expected where path != "README.txt" { #expect(readme.contains(path), "README lists \(path)") }
        #expect(readme.contains("re-encoded to ProRes 422 HQ"))
        #expect(readme.contains("Re-encoded to ProRes: 01 Screen/Clip 01.mov, 01 Screen/Clip 02.mov, 02 Camera/Camera.mov"))
        #expect(readme.contains("Untouched originals: 04 Graphics/logo.png"))
        #expect(readme.contains("length 0:04.00"))
        #expect(readme.contains("30 fps"))

        // 7. The timelines are valid and point at the files.
        try Self.checkFCPXML(folder.appendingPathComponent("Timeline.fcpxml"), fps: 30)
        try Self.checkPremiereXML(folder.appendingPathComponent("Timeline (Premiere).xml"))

        // 8. A second handoff on the same day gets its own folder.
        let again = try await write(fixture, options: VideoHandoffOptions(), into: destination)
        #expect(again.folder.lastPathComponent == folder.lastPathComponent + " 2")
        print("Handoff frames saved in \(frames.path)")
        print("HANDOFF FOLDER \(folder.path)")
    }

    @Test func fullOriginalsLinedUpKeepTheFramesAndTheCameraOffset() async throws {
        let fixture = try await fixture()
        let destination = fixture.folder.appendingPathComponent("Elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var options = VideoHandoffOptions()
        options.clips = .full
        options.includeFinal = false
        let result = try await write(fixture, options: options, into: destination)
        let folder = result.folder
        print("FULL HANDOFF LISTING\n" + (try Self.listing(folder)).joined(separator: "\n"))

        // The recording starts at 0:00 and fills the clock: copied untouched.
        let screen = folder.appendingPathComponent("01 Screen/Demo.mov")
        #expect(FileManager.default.contentsEqual(atPath: screen.path, andPath: fixture.input.project.sourcePath), "the original, byte for byte")
        // The camera: its own frames, 0.7 s in, on the 6 s clock.
        let camera = folder.appendingPathComponent("02 Camera/Camera.mov")
        #expect(abs(try await duration(camera) - 6) < 0.035)
        for t in [1.2, 2.6, 4.1, 5.4] {
            let frame = try await TestVideos.frame(ofMovie: camera, at: t)
            let want = Self.palette[Self.colorIndex(world: t)]
            let color = TestVideos.averageColor(of: frame, x: 0.45, y: 0.4, width: 0.1, height: 0.1)
            #expect(TestVideos.close(color, want), "camera at \(t) s of the recording shows \(color), wanted \(want)")
        }
        let micOnsets = TestSounds.onsets(try TestSounds.read(folder.appendingPathComponent("03 Audio/Microphone.wav")))
        #expect(micOnsets.count == Self.micBeeps.count, "\(micOnsets)")
        for (found, want) in zip(micOnsets, Self.micBeeps) { #expect(abs(found - want) < 0.03) }
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("03 Audio/Music.m4a").path), "the music as added")
        #expect(abs(try await duration(folder.appendingPathComponent("03 Audio/Full Mix.wav")) - 4.0) < 0.035, "the full mix follows the edit")
        let readme = try String(contentsOf: folder.appendingPathComponent("README.txt"), encoding: .utf8)
        #expect(readme.contains("01 Screen/Demo.mov") && readme.contains("untouched original"))
        #expect(readme.contains("02 Camera/Camera.mov") && readme.contains("not re-encoded"))
        try Self.checkFCPXML(folder.appendingPathComponent("Timeline.fcpxml"), fps: 30)
        try Self.checkPremiereXML(folder.appendingPathComponent("Timeline (Premiere).xml"))
    }

    /// The full mix dips the music under the voice, exactly as the edit
    /// plays it: a 220 Hz "song" under a 1 kHz "voice" from 1.5 to 3.5 s.
    @Test func theFullMixDipsTheMusicUnderTheVoice() async throws {
        try TestVideos.isolateStorage()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-fullmix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let picture = folder.appendingPathComponent("picture.mp4"), voice = folder.appendingPathComponent("voice.m4a"), screen = folder.appendingPathComponent("Talk.mov")
        try await TestVideos.writeBars(to: picture, seconds: 6)
        try TestSounds.writeAudio(TestSounds.tone(1000, from: 1.5, to: 3.5, seconds: 6, gain: 0.5), to: voice)
        try await TestSounds.mux(video: picture, audio: [voice], to: screen)
        let song = folder.appendingPathComponent("song.m4a")
        try TestSounds.writeStereo(TestSounds.tone(220, from: 0, to: 6, seconds: 6, gain: 0.8), to: song)
        var metadata = VideoDemoRecordingMetadata(videoURLPath: screen.path, createdAt: Date(), duration: 6, sourceWidth: 1280, sourceHeight: 720, fps: 30,
                                                  nativeCursorVisible: false, cursorSamples: [], clickEvents: [], pointPixelScale: 2, renderCursor: false)
        metadata.audioTracks = [.microphone]
        var project = VideoDemoProject.make(sourceURL: screen, duration: 6, sourceSize: CGSize(width: 1280, height: 720))
        project.apply(metadata: metadata)
        var music = VideoMusicTrack(path: song.path, name: "song.m4a", duration: 6)
        music.fadeIn = 0
        music.fadeOut = 0
        music.ducking = true
        project.music = music
        let input = await VideoHandoffInput.gather(name: "Talk", project: project, recording: metadata, appendedMetadata: [:], exportSettings: VideoExportSettings())
        var options = VideoHandoffOptions()
        options.includeFinal = false
        options.includeTimeline = false
        let plan = VideoHandoffPlanner.plan(input, options: options, folderName: "x")
        let out = folder.appendingPathComponent("Out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let result = try await VideoHandoffWriter(plan: plan, input: input, parent: out).run()
        let mix = try TestSounds.read(result.folder.appendingPathComponent("03 Audio/Full Mix.wav"))
        let before = TestSounds.level(of: 220, in: mix, from: 0.4, to: 1.1)
        let under = TestSounds.level(of: 220, in: mix, from: 2.2, to: 3.0)
        let after = TestSounds.level(of: 220, in: mix, from: 4.6, to: 5.4)
        let speaking = TestSounds.level(of: 1000, in: mix, from: 2.2, to: 3.0)
        print("music 220 Hz: before \(before), under the voice \(under), after \(after); voice \(speaking)")
        #expect(before > 0.02 && after > 0.02, "the music plays")
        #expect(speaking > 0.05, "the voice is in the mix")
        #expect(under < before * 0.6 && under < after * 0.6, "the music dips under the voice: \(under) vs \(before) / \(after)")
        let raw = try TestSounds.read(result.folder.appendingPathComponent("03 Audio/Music.m4a"))
        #expect(TestSounds.level(of: 220, in: raw, from: 2.2, to: 3.0) > TestSounds.level(of: 220, in: raw, from: 0.4, to: 1.1) * 0.9, "Music.m4a alone doesn't dip")
    }

    @Test func aMissingCameraIsSkippedAndListed() async throws {
        var fixture = try await fixture()
        fixture.input.recordings[0].camera?.url = nil
        let destination = fixture.folder.appendingPathComponent("Out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var options = VideoHandoffOptions()
        options.includeFinal = false
        let name = VideoHandoffPlanner.folderName(project: "Demo") { _ in false }
        let plan = VideoHandoffPlanner.plan(fixture.input, options: options, folderName: name)
        let result = try await VideoHandoffWriter(plan: plan, input: fixture.input, parent: destination).run()
        #expect(result.skipped.contains { $0.contains("phone.mp4") }, "\(result.skipped)")
        #expect(!FileManager.default.fileExists(atPath: result.folder.appendingPathComponent("02 Camera").path))
        #expect(FileManager.default.fileExists(atPath: result.folder.appendingPathComponent("01 Screen/Clip 01.mov").path), "the rest is written")
        let readme = try String(contentsOf: result.folder.appendingPathComponent("README.txt"), encoding: .utf8)
        #expect(readme.contains("NOT INCLUDED") && readme.contains("phone.mp4"))
    }

    @Test func cancellingRemovesTheFolder() async throws {
        let fixture = try await fixture()
        let destination = fixture.folder.appendingPathComponent("Cancelled", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let plan = VideoHandoffPlanner.plan(fixture.input, options: VideoHandoffOptions(), folderName: "x")
        let writer = VideoHandoffWriter(plan: plan, input: fixture.input, parent: destination)
        let stop = Box()
        writer.progress = { progress in if progress.fraction > 0.2 { stop.value = true } }
        writer.isCancelled = { stop.value }
        await #expect(throws: CancellationError.self) { try await writer.run() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty, "nothing half-made is left")
    }

    final class Box: @unchecked Sendable { var value = false }

    // MARK: Checks

    static func listing(_ folder: URL) throws -> [String] {
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])!
        var lines: [String] = []
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            let path = String(url.path.dropFirst(folder.path.count + 1))
            lines.append(values.isDirectory == true ? "\(path)/" : "\(path)  (\(ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file)))")
        }
        return lines.sorted()
    }

    /// Well-formed, every clip's asset is declared and its file exists, and
    /// every time is a whole number of frames.
    static func checkFCPXML(_ url: URL, fps: Int) throws {
        let lint = Process()
        lint.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint")
        lint.arguments = ["--noout", url.path]
        try lint.run(); lint.waitUntilExit()
        #expect(lint.terminationStatus == 0, "xmllint accepts \(url.lastPathComponent)")
        let document = try XMLDocument(contentsOf: url)
        let root = try #require(document.rootElement())
        #expect(root.name == "fcpxml" && root.attribute(forName: "version")?.stringValue == "1.10")
        let assets = try document.nodes(forXPath: "//asset").compactMap { $0 as? XMLElement }
        let ids = Set(assets.compactMap { $0.attribute(forName: "id")?.stringValue })
        for asset in assets {
            let src = try #require(try asset.nodes(forXPath: "media-rep/@src").first?.stringValue)
            let file = try #require(URL(string: src))
            #expect(FileManager.default.fileExists(atPath: file.path), "\(file.path) exists")
        }
        let clips = try document.nodes(forXPath: "//asset-clip").compactMap { $0 as? XMLElement }
        #expect(!clips.isEmpty)
        for clip in clips {
            #expect(ids.contains(clip.attribute(forName: "ref")?.stringValue ?? ""), "clip refers to a declared asset")
            for key in ["offset", "start", "duration"] {
                let value = clip.attribute(forName: key)?.stringValue ?? ""
                #expect(Self.isWholeFrames(value, fps: fps), "\(key)=\(value) is whole frames")
            }
        }
        print("FCPXML: \(assets.count) files, \(clips.count) clips")
    }

    static func isWholeFrames(_ value: String, fps: Int) -> Bool {
        guard value.hasSuffix("s") else { return false }
        let body = value.dropLast()
        if body == "0" { return true }
        let parts = body.split(separator: "/")
        guard parts.count == 2, let n = Int(parts[0]), let d = Int(parts[1]), d > 0 else { return false }
        return (n * fps) % d == 0
    }

    static func checkPremiereXML(_ url: URL) throws {
        let document = try XMLDocument(contentsOf: url)
        #expect(document.rootElement()?.name == "xmeml")
        let paths = try document.nodes(forXPath: "//pathurl").compactMap { $0.stringValue }
        #expect(!paths.isEmpty)
        for path in paths {
            #expect(FileManager.default.fileExists(atPath: try #require(URL(string: path)).path), "\(path) exists")
        }
        let items = try document.nodes(forXPath: "//clipitem")
        #expect(items.count >= 4)
        print("Premiere XML: \(paths.count) files, \(items.count) clips")
    }
}
