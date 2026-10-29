import AppKit
import AVFoundation
import CoreText
import Foundation
import Testing
@testable import LFStudiosCore

/// A Creative Handoff opened on another Mac exports exactly the same video
/// (1.8.0): face tracking, a blur that follows a path, the camera's sync
/// offset, a font added to LF Studios, the pointer's own picture, music, a
/// picture, an added sound, a macOS wallpaper, and the cleaned-up voice.
/// "Another Mac" is a copy of the folder somewhere else, an empty
/// Application Support, the original files gone, and the added font no
/// longer installed. All synthetic video and sound.
@Suite("Opening a handoff on another Mac", .serialized)
@MainActor
struct VideoOtherMacTests {
    static let addedFamily = "LFStudiosQc"
    static let installedFamily = "LFStudiosQd"
    static let cameraOffset = 0.4

    let base: URL
    var thisMac: URL { base.appendingPathComponent("This Mac", isDirectory: true) }
    var media: URL { thisMac.appendingPathComponent("Media", isDirectory: true) }

    init() throws {
        try TestVideos.isolateStorage()
        base = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-other-mac-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("This Mac/Media", isDirectory: true), withIntermediateDirectories: true)
    }

    struct Fixture {
        var project: VideoDemoProject
        var metadata: VideoDemoRecordingMetadata
        var settings: VideoExportSettings
        var addedFont: URL
        var installedFont: URL
    }

    private func png(_ color: NSColor, size: CGSize, name: String) throws -> URL {
        let url = media.appendingPathComponent(name)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)).fill()
        NSColor.white.setFill()
        NSRect(x: size.width * 0.3, y: size.height * 0.3, width: size.width * 0.4, height: size.height * 0.1).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    /// 4 s of moving screen with a microphone, a camera started 0.4 s
    /// later, and every feature that points at a file or at this Mac.
    private func fixture() async throws -> Fixture {
        let fps = 30
        let screenSize = CGSize(width: 960, height: 540)
        let picture = media.appendingPathComponent("picture.mov")
        try await TestVideos.writeVideo(to: picture, size: screenSize, seconds: 4, fps: fps) { context, frame in
            let t = Double(frame) / Double(fps)
            context.setFillColor(CGColor(red: 0.15, green: 0.2, blue: 0.35, alpha: 1))
            context.fill(CGRect(origin: .zero, size: screenSize))
            context.setFillColor(CGColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 80 + t * 160, y: 200, width: 160, height: 120))
            context.setFillColor(CGColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1))
            context.fill(CGRect(x: 600, y: 60 + t * 60, width: 220, height: 90))
        }
        let mic = media.appendingPathComponent("mic.m4a")
        try TestSounds.writeAudio(TestSounds.beeps(at: [0.4, 1.2, 2.3, 3.1], seconds: 4, noise: 0.02), to: mic)
        let screen = media.appendingPathComponent("Demo.mov")
        try await TestSounds.mux(video: picture, audio: [mic], to: screen)

        let cameraSize = CGSize(width: 640, height: 480)
        let camera = media.appendingPathComponent("Camera.mov")
        try await TestVideos.writeVideo(to: camera, size: cameraSize, seconds: 4, fps: fps) { context, frame in
            let t = Double(frame) / Double(fps)
            context.setFillColor(CGColor(red: 0.3, green: 0.25, blue: 0.2, alpha: 1))
            context.fill(CGRect(origin: .zero, size: cameraSize))
            // A "face" that drifts right, as the made-up analysis says.
            context.setFillColor(CGColor(red: 0.95, green: 0.75, blue: 0.6, alpha: 1))
            context.fillEllipse(in: CGRect(x: 120 + t * 80, y: 160, width: 160, height: 200))
        }

        let music = media.appendingPathComponent("song.m4a")
        try TestSounds.writeStereo(TestSounds.beeps(at: [0.2, 1.6, 2.9], seconds: 4, gain: 0.3, noise: 0.03), to: music)
        let sting = media.appendingPathComponent("sting.m4a")
        try TestSounds.writeAudio(TestSounds.tone(1320, from: 0, to: 0.6, seconds: 0.6, gain: 0.3), to: sting)
        let logo = try png(.systemPink, size: CGSize(width: 96, height: 96), name: "logo.png")
        let pointer = try png(.systemTeal, size: CGSize(width: 48, height: 48), name: "pointer.png")
        // A macOS wallpaper: another Mac may not have this one.
        let wallpaper = media.appendingPathComponent("Wallpaper.png")
        let wall = NSImage(size: NSSize(width: 320, height: 180))
        wall.lockFocus()
        NSGradient(starting: .systemPurple, ending: .systemOrange)?.draw(in: NSRect(x: 0, y: 0, width: 320, height: 180), angle: 30)
        wall.unlockFocus()
        let wallTIFF = try #require(wall.tiffRepresentation)
        try #require(NSBitmapImageRep(data: wallTIFF)?.representation(using: .png, properties: [:])).write(to: wallpaper)

        // A font added to LF Studios (only this Mac has it), and one
        // "installed in Font Book" (registered for this run only).
        let fontScratch = base.appendingPathComponent("Font files", isDirectory: true)
        let addedFile = try TestFonts.makeFontFile(in: fontScratch, family: Self.addedFamily)
        _ = try VideoFonts.addFontFile(addedFile)
        let addedFont = try #require(VideoFonts.addedFontFiles(forFamily: Self.addedFamily).first)
        // Installed again if an earlier case took it away.
        CTFontManagerRegisterFontURLs([addedFont] as CFArray, .process, true, nil)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(VideoFonts.isAvailable(Self.addedFamily))
        let installedFont = try TestFonts.makeFontFile(in: fontScratch, family: Self.installedFamily)

        var metadata = VideoDemoRecordingMetadata(videoURLPath: screen.path, createdAt: Date(), duration: 4, sourceWidth: 960, sourceHeight: 540, fps: 30,
                                                  nativeCursorVisible: false, cursorSamples: [], clickEvents: [], pointPixelScale: 1, renderCursor: false)
        metadata.audioTracks = [.microphone]
        metadata.webcam = VideoWebcamRecording(path: camera.path, offset: Self.cameraOffset, width: 640, height: 480)
        var project = VideoDemoProject.make(sourceURL: screen, duration: 4, sourceSize: screenSize)
        project.apply(metadata: metadata)
        project.audio.normalizeLoudness = false
        project.timelineClips = [VideoDemoTimelineClip(sourceStart: 0, sourceEnd: 1.6), VideoDemoTimelineClip(sourceStart: 2.1, sourceEnd: 4)]
        project.webcam.visible = true
        project.background = .systemWallpaper(wallpaper.path)
        project.padding = 0.08
        project.cursorSamples = stride(from: 0.0, through: 4, by: 1.0 / 30).map { VideoDemoCursorSample(time: $0, x: 0.2 + $0 * 0.15, y: 0.4 + sin($0) * 0.1) }
        project.clickEvents = [VideoDemoClickEvent(time: 1.0, x: 0.35, y: 0.48, button: .left)]
        project.cursor.style = .custom
        project.cursor.customImage = VideoCursorImage(path: pointer.path, name: "pointer.png", hotSpotX: 0.1, hotSpotY: 0.1, aspect: 1)
        project.music = VideoMusicTrack(path: music.path, name: "song.m4a", duration: 4)
        project.audioTracks = [VideoExternalAudioTrack(path: sting.path, name: "sting.m4a", duration: 0.6, at: 2.2)]
        var picture2 = VideoDemoOverlayEffect(kind: .image, time: 0.5, duration: 3, x: 0.8, y: 0.25, width: 0.12, height: 0.2)
        picture2.image = VideoOverlayImage(path: logo.path, name: "logo.png", aspect: 1)
        // A blur that follows the yellow box across the screen.
        var blur = VideoDemoOverlayEffect(kind: .blur, time: 0, duration: 4, x: 0.17, y: 0.52, width: 0.2, height: 0.25)
        blur.motion = stride(from: 0.0, through: 4, by: 0.5).map { VideoOverlayMotionKey(time: $0, x: (160 + $0 * 160) / 960, y: 0.52, width: 0.2, height: 0.25) }
        project.overlayEffects = [picture2, blur]
        project.captions = [VideoCaptionLine(start: 0.2, end: 3.6, text: "Made with my own font")]
        project.captionStyle.font = VideoFontChoice(family: Self.addedFamily)

        // Keep face centered, from an analysis (made up: the face drifts right).
        project.faceTracking = VideoFaceTracking()
        let times = stride(from: 0.0, to: 4, by: 1 / VideoFaceAnalyzer.framesPerSecond).map { $0 }
        let faces = times.map { VideoFaceDetection(time: $0, x: (120 + $0 * 80) / 640, y: 0.25, width: 0.25, height: 0.42) }
        VideoFaceStore.save(VideoFaceAnalysis(times: times, faces: faces, duration: 4), for: camera)

        // Enhance voice: a "cleaned-up" voice that's plainly different from
        // the microphone (a 1 kHz tone), so making it again on the other Mac
        // instead of using the carried file would show.
        project.audio.enhanceVoice = true
        let recipe = try #require(project.audio.voiceRecipe)
        let cleaned = VideoVoiceEnhancer.cacheURL(for: screen, trackIndex: 0, recipe: recipe)
        try FileManager.default.createDirectory(at: cleaned.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestSounds.writeAudio(TestSounds.tone(1000, from: 0, to: 4, seconds: 4, gain: 0.35), to: cleaned)

        var settings = VideoExportSettings()
        settings.resolution = .p720
        settings.fps = 30
        settings.endCard = false
        settings.burnCaptions = true
        return Fixture(project: project, metadata: metadata, settings: settings, addedFont: addedFont, installedFont: installedFont)
    }

    private func export(_ project: VideoDemoProject, recording: VideoDemoRecordingMetadata?, settings: VideoExportSettings, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        try await VideoDemoExporter.export(project: project, recording: recording, destinationURL: url, settings: settings)
    }

    /// Every half second, the two videos' pictures are the same, and so is
    /// the sound.
    private func expectSame(_ original: URL, _ other: URL, label: String) async throws {
        let a = try await AVURLAsset(url: original).load(.duration).seconds
        let b = try await AVURLAsset(url: other).load(.duration).seconds
        #expect(abs(a - b) < 0.05, "\(label): \(a) s and \(b) s")
        let frames = try TestVideos.framesDirectory("other-mac-\(label)")
        for time in stride(from: 0.1, to: min(a, b) - 0.05, by: 0.5) {
            let first = try await TestVideos.frame(ofMovie: original, at: time)
            let second = try await TestVideos.frame(ofMovie: other, at: time)
            #expect(first.width == second.width && first.height == second.height)
            let x = TestVideos.rgba(first), y = TestVideos.rgba(second)
            var total = 0.0, worst = 0
            var blockDiffs: [Double] = []
            let block = 16
            for by in stride(from: 0, to: first.height - block, by: block) {
                for bx in stride(from: 0, to: first.width - block, by: block) {
                    var sum = 0
                    for py in by..<(by + block) {
                        for px in bx..<(bx + block) {
                            let i = (py * first.width + px) * 4
                            for c in 0..<3 { sum += abs(Int(x[i + c]) - Int(y[i + c])) }
                        }
                    }
                    let mean = Double(sum) / Double(block * block * 3) / 255
                    blockDiffs.append(mean)
                    total += mean
                    worst = max(worst, Int(mean * 255))
                }
            }
            let average = total / Double(max(blockDiffs.count, 1))
            let ok = average < 0.004 && worst < 12
            if !ok {
                try TestVideos.save(first, as: frames.appendingPathComponent(String(format: "%.1f-this-mac.png", time)))
                try TestVideos.save(second, as: frames.appendingPathComponent(String(format: "%.1f-other-mac.png", time)))
            }
            #expect(ok, "\(label) at \(time) s: the picture differs (average \(average), worst 16×16 block \(worst)/255; frames in \(frames.path))")
        }
        let soundA = try await TestSounds.readTrack(original)
        let soundB = try await TestSounds.readTrack(other)
        #expect(abs(soundA.count - soundB.count) < 4_800, "\(label): sound lengths \(soundA.count) and \(soundB.count)")
        let count = min(soundA.count, soundB.count)
        var difference = 0.0, energy = 0.0
        for i in 0..<count {
            let d = Double(soundA[i] - soundB[i])
            difference += d * d
            energy += Double(soundA[i] * soundA[i])
        }
        #expect(energy > 0)
        #expect(difference / max(energy, 1e-9) < 0.01, "\(label): the sound differs (\(difference / max(energy, 1e-9)) of its energy)")
        #expect(TestSounds.level(of: 1000, in: soundB, from: 0.5, to: 1.2) > 0.05, "\(label): the carried cleaned-up voice plays")
    }

    @Test(arguments: [VideoHandoffOptions.Clips.full, .trimmed])
    func aHandoffOpensAndExportsTheSameOnAnotherMac(clips: VideoHandoffOptions.Clips) async throws {
        let label = clips == .full ? "full" : "trimmed"
        let fixture = try await fixture()
        let original = thisMac.appendingPathComponent("Original.mp4")
        try await export(fixture.project, recording: fixture.metadata, settings: fixture.settings, to: original)
        let originalSound = try await TestSounds.readTrack(original)
        #expect(TestSounds.level(of: 1000, in: originalSound, from: 0.5, to: 1.2) > 0.05, "the cleaned-up voice plays here")

        // The handoff, on this Mac.
        let handoffs = thisMac.appendingPathComponent("Handoffs", isDirectory: true)
        try FileManager.default.createDirectory(at: handoffs, withIntermediateDirectories: true)
        let input = await VideoHandoffInput.gather(name: "Demo", project: fixture.project, recording: fixture.metadata, appendedMetadata: [:], exportSettings: fixture.settings)
        var options = VideoHandoffOptions(clips: clips)
        options.includeFinal = false
        options.includeOriginals = true
        let plan = VideoHandoffPlanner.plan(input, options: options, folderName: "Demo")
        let result = try await VideoHandoffWriter(plan: plan, input: input, parent: handoffs).run()
        #expect(FileManager.default.fileExists(atPath: result.folder.appendingPathComponent("Fonts/\(fixture.addedFont.lastPathComponent)").path), "the added font goes along")

        // Another Mac: the folder copied elsewhere, nothing of this Mac's.
        let otherMac = base.appendingPathComponent("Other Mac", isDirectory: true)
        let downloads = otherMac.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let copied = downloads.appendingPathComponent(result.folder.lastPathComponent, isDirectory: true)
        try FileManager.default.copyItem(at: result.folder, to: copied)
        try FileManager.default.moveItem(at: media, to: thisMac.appendingPathComponent("Media (gone)", isDirectory: true))
        CTFontManagerUnregisterFontURLs([fixture.addedFont] as CFArray, .process, nil)
        // The font list catches up once the main thread is free.
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(!VideoFonts.isAvailable(Self.addedFamily), "the other Mac doesn't have the font")
        let storage = otherMac.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let other = otherMac.appendingPathComponent("Other.mp4")

        defer {
            // The other Mac's copy of the font, gone again for the next case.
            let copies = VideoFonts.addedFontFiles(root: storage)
            CTFontManagerUnregisterFontURLs(copies as CFArray, .process, nil)
        }
        try await TestVideos.withStorage(storage) {
            let opened = try VideoProjectPackage.open(copied.appendingPathComponent("Demo.lfstudios"))
            let contents = opened.contents
            let inside = copied.standardizedFileURL.path + "/"
            let project = contents.project
            for path in contents.paths {
                #expect(path.hasPrefix(inside), "\(label): \(path) is in the copied folder")
                #expect(FileManager.default.fileExists(atPath: path), "\(label): \(path) is there")
            }
            if case .systemWallpaper(let path) = project.background { #expect(path.hasPrefix(inside)) } else { Issue.record("the wallpaper background is kept") }
            #expect(project.cursor.customImage?.path.hasPrefix(inside) == true)
            #expect(project.carriedVoices.count == 1)
            #expect(project.faceTracking?.analysisPath?.hasPrefix(inside) == true)
            #expect(contents.recording?.webcam?.offset == Self.cameraOffset, "the camera's sync offset")
            #expect(project.overlayEffects.first { $0.kind == .blur }?.motion == fixture.project.overlayEffects.first { $0.kind == .blur }?.motion, "the blur's path")

            let primary = try #require(VideoProjectOpener.prepare(opened))
            try await Task.sleep(nanoseconds: 500_000_000)
            #expect(VideoFonts.isAvailable(Self.addedFamily), "the font came with the folder")
            let cameraHere = try #require(VideoProjectCaches.cameraURL(project, recordedCamera: contents.recording?.webcam))
            #expect(VideoFaceStore.load(for: cameraHere) != nil, "the face tracking is back where it's looked for")
            let recipe = try #require(project.audio.voiceRecipe)
            #expect(FileManager.default.fileExists(atPath: VideoVoiceEnhancer.cacheURL(for: primary, trackIndex: 0, recipe: recipe).path), "the cleaned-up voice is back where it's looked for")
            try await export(project, recording: contents.recording, settings: fixture.settings, to: other)
        }
        try await expectSame(original, other, label: label)
    }

    @Test func includeFontsInstalledOnThisMacCarriesThem() async throws {
        var fixture = try await fixture()
        CTFontManagerRegisterFontURLs([fixture.installedFont] as CFArray, .process, true, nil)
        defer { CTFontManagerUnregisterFontURLs([fixture.installedFont] as CFArray, .process, nil) }
        var callout = VideoDemoOverlayEffect(kind: .text, time: 0.3, duration: 3, x: 0.5, y: 0.12, width: 0.4, height: 0.1, text: "Installed font")
        callout.font = VideoFontChoice(family: Self.installedFamily)
        fixture.project.overlayEffects.append(callout)
        #expect(VideoFonts.installedFontFiles(forFamily: Self.installedFamily) == [fixture.installedFont.resolvingSymlinksInPath()])
        #expect(VideoFonts.installedFontFiles(forFamily: Self.addedFamily).isEmpty, "a font added to LF Studios isn't counted twice")
        #expect(VideoFonts.installedFontFiles(forFamily: "Helvetica").isEmpty, "macOS's own fonts are on every Mac")
        let families = VideoProjectDocument.fontFamilies(of: fixture.project)
        #expect(VideoFonts.installedFamiliesLeftOut(families, includeInstalled: false) == [Self.installedFamily])
        #expect(VideoFonts.installedFamiliesLeftOut(families, includeInstalled: true).isEmpty)
        #expect(VideoHandoffOptions().includeInstalledFonts == false, "off unless turned on")

        let input = await VideoHandoffInput.gather(name: "Demo", project: fixture.project, recording: fixture.metadata, appendedMetadata: [:], exportSettings: fixture.settings)
        var options = VideoHandoffOptions(clips: .full)
        options.includeFinal = false
        // Off: left out, and README.txt says so.
        let without = VideoHandoffPlanner.plan(input, options: options, folderName: "Demo")
        #expect(!without.items.contains { $0.folder == .fonts && $0.fileName == "\(Self.installedFamily).ttf" })
        #expect(without.items.contains { $0.folder == .fonts && $0.fileName == fixture.addedFont.lastPathComponent }, "fonts added to LF Studios always go")
        #expect(without.skipped.contains { $0.contains(Self.installedFamily) && $0.contains("license") })
        let readme = VideoHandoffReadme.text(plan: without, name: "Demo", appVersion: "1.8.0", durations: [:], written: nil, markers: [], timelineDuration: 3.5)
        #expect(readme.contains(Self.installedFamily), "README.txt names the font left out")
        options.includeInstalledFonts = true
        let plan = VideoHandoffPlanner.plan(input, options: options, folderName: "Demo")
        #expect(plan.items.contains { $0.folder == .fonts && $0.fileName == "\(Self.installedFamily).ttf" })
        #expect(!plan.skipped.contains { $0.contains(Self.installedFamily) })

        // Save Project: the same switch, for project files and folders.
        let package = thisMac.appendingPathComponent("Saved/Demo.lfstudios")
        let contents = VideoProjectContents(project: fixture.project, recording: fixture.metadata, sourceRecordings: [:])
        try VideoProjectPackage.save(contents, to: package, mode: .folder, folder: .init(kind: .opened), fontFiles: { VideoFonts.carriedFontFiles(forFamily: $0, includeInstalled: false) })
        let fonts = package.deletingLastPathComponent().appendingPathComponent("Fonts")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: fonts.path))?.sorted() == ["\(Self.addedFamily).ttf"])
        try VideoProjectPackage.save(contents, to: package, mode: .folder, folder: .init(kind: .opened), fontFiles: { VideoFonts.carriedFontFiles(forFamily: $0, includeInstalled: true) })
        #expect((try? FileManager.default.contentsOfDirectory(atPath: fonts.path))?.sorted() == ["\(Self.addedFamily).ttf", "\(Self.installedFamily).ttf"])
    }

    /// Projects saved before 1.8.0 (no carried files) open as before, and
    /// a project without these features writes nothing new.
    @Test func olderProjectsAreUnchanged() throws {
        let project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 2, sourceSize: CGSize(width: 640, height: 360))
        let json = String(decoding: try JSONEncoder().encode(project), as: UTF8.self)
        #expect(!json.contains("carriedVoices"))
        var tracking = VideoFaceTracking()
        tracking.smoothness = 0.3
        let decoded = try JSONDecoder().decode(VideoFaceTracking.self, from: Data(#"{"enabled":true,"smoothness":0.3,"tightness":0.45}"#.utf8))
        #expect(decoded == tracking, "older face tracking settings load")
        let carried = VideoProjectCaches.carrying(project, recordedCamera: nil, primaryKinds: [.microphone])
        #expect(carried == project, "nothing to carry: nothing changes")
    }
}
