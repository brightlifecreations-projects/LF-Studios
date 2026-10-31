import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import LFStudiosCore

/// Split screen (1.10.0): its geometry in landscape and vertical videos,
/// the divider, export frames for each layout, zooms and captions in a
/// split, Adapt to this ratio, transparency, the handoff's layout, and the
/// project round trip (VideoSplitScreen.swift, VideoRenderer.swift).
@Suite("Split screen")
struct VideoSplitScreenTests {
    typealias RGB = (r: Double, g: Double, b: Double)
    typealias Split = VideoWebcamSettings.Split
    static let magenta: RGB = (0.9, 0.1, 0.8)
    static let white: RGB = (1, 1, 1)
    static let red = TestVideos.quadrantColors[0], green = TestVideos.quadrantColors[1], blue = TestVideos.quadrantColors[2], yellow = TestVideos.quadrantColors[3]

    // MARK: Geometry

    @Test func landscapeVideosSplitSideBySide() {
        let size = CGSize(width: 1920, height: 1080)
        #expect(VideoSplitLayout.isSideBySide(size))
        let right = VideoSplitLayout.parts(Split(), in: size)
        #expect(right.screen == CGRect(x: 0, y: 0, width: 960, height: 1080))
        #expect(right.camera == CGRect(x: 960, y: 0, width: 960, height: 1080))
        let left = VideoSplitLayout.parts(Split(cameraSide: .first), in: size)
        #expect(left.camera.minX == 0 && left.screen.minX == 960)
        for size in [CGSize(width: 1440, height: 1080), CGSize(width: 2520, height: 1080), CGSize(width: 1728, height: 1080)] {
            #expect(VideoSplitLayout.isSideBySide(size), "4:3, 21:9, 16:10 are side by side")
        }
    }

    @Test func verticalAndSquareVideosSplitOneAboveTheOther() {
        for size in [CGSize(width: 1080, height: 1920), CGSize(width: 1080, height: 1350), CGSize(width: 1080, height: 1080)] {
            #expect(!VideoSplitLayout.isSideBySide(size))
            let bottom = VideoSplitLayout.parts(Split(cameraSide: .second), in: size)
            #expect(bottom.camera.minY == 0, "second is the bottom (y up)")
            #expect(bottom.screen.maxY == size.height)
            #expect(bottom.camera.width == size.width && bottom.screen.width == size.width)
            let top = VideoSplitLayout.parts(Split(cameraSide: .first), in: size)
            #expect(top.camera.maxY == size.height, "first is the top")
        }
    }

    @Test(arguments: [0.3, 0.4, 0.5, 0.6, 0.7])
    func theSplitSizeAndTheGap(share: Double) {
        let size = CGSize(width: 1920, height: 1080)
        let parts = VideoSplitLayout.parts(Split(cameraShare: share, gap: 0.02), in: size)
        let gap = (1080 * 0.02).rounded()
        #expect(parts.camera.width + parts.screen.width + gap == 1920)
        #expect(abs(parts.camera.width - ((1920 - gap) * share).rounded()) < 0.5)
        #expect(abs(parts.camera.minX - parts.screen.maxX - CGFloat(gap)) < 0.001, "the gap between them: \(parts)")
        // Kept between 30/70 and 70/30.
        #expect(VideoSplitLayout.parts(Split(cameraShare: 0.95), in: size).camera.width == VideoSplitLayout.parts(Split(cameraShare: 0.7), in: size).camera.width)
    }

    @Test func theDividerAndTheSplitSizeAgree() {
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920)] {
            for side in Split.Side.allCases {
                for share in [0.3, 0.45, 0.5, 0.62, 0.7] {
                    let split = Split(cameraSide: side, cameraShare: share, gap: 0.03)
                    let position = VideoSplitLayout.dividerPosition(split, in: size)
                    #expect(abs(VideoSplitLayout.share(forDivider: position, split, in: size) - share) < 0.002, "\(size) \(side) \(share)")
                }
                // Dragged past the ends: kept at 30/70.
                let split = Split(cameraSide: side)
                let shares = [VideoSplitLayout.share(forDivider: 0, split, in: size), VideoSplitLayout.share(forDivider: 1, split, in: size)]
                #expect(shares.allSatisfy { (0.3...0.7).contains($0) })
                #expect(Set(shares) == [0.3, 0.7])
            }
        }
        // Side by side, the camera on the right: dragging left gives it more.
        let size = CGSize(width: 1920, height: 1080)
        #expect(VideoSplitLayout.share(forDivider: 0.4, Split(), in: size) > 0.5)
    }

    // MARK: The frame bar's screen part

    @Test func theScreenPartIsEvenAndBesideTheCamera() {
        for ratio in RecordingFrameRatio.presets.map(\.ratio) {
            for short in [720, 1080, 1440] {
                let pixels = RecordingFrameGeometry.pixels(ratio, shortSide: short)
                let video = CGSize(width: pixels.width, height: pixels.height)
                for split in [Split(), Split(cameraSide: .first, cameraShare: 0.4), Split(cameraShare: 0.7, gap: 0.02)] {
                    let screen = VideoSplitLayout.screenPixels(split, video: video)
                    let camera = VideoSplitLayout.parts(split, in: video).camera
                    #expect(Int(screen.width) % 2 == 0 && Int(screen.height) % 2 == 0, "\(ratio.text) \(short): even sides")
                    #expect(CGRect(origin: .zero, size: video).contains(screen))
                    #expect(!screen.intersects(camera.insetBy(dx: 0.5, dy: 0.5)), "never over the camera's part")
                    let full = VideoSplitLayout.parts(split, in: video).screen
                    #expect(full.width - screen.width < 2 && full.height - screen.height < 2, "at most a pixel off for evenness")
                }
            }
        }
        // 16:9 split 50/50: 8:9, exactly half.
        let half = VideoSplitLayout.screenPixels(Split(), video: CGSize(width: 1920, height: 1080))
        #expect(half == CGRect(x: 0, y: 0, width: 960, height: 1080))
        #expect(VideoSplitLayout.ratioText(half.size) == "8:9")
    }

    // MARK: Export frames

    private func project(_ layout: VideoRecordingCameraSetup.LayoutChoice, aspect: VideoDemoProject.AspectPreset = .widescreen, source: CGSize = CGSize(width: 1280, height: 720), split: Split = Split(), change: (inout VideoDemoProject) -> Void = { _ in }) -> VideoDemoProject {
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/split.mp4"), duration: 4, sourceSize: source)
        project.aspectPreset = aspect
        project.background = .color(VideoRGBA(1, 1, 1))
        project.webcam = layout.applied(to: project.webcam)
        project.webcam.split = split
        change(&project)
        return project
    }

    private struct Frame {
        let bytes: [UInt8]
        let size: CGSize
        func color(_ x: CGFloat, _ y: CGFloat) -> RGB { TestVideos.pixel(bytes, width: Int(size.width), x: Int(x), y: Int(y)) }
        func alpha(_ x: CGFloat, _ y: CGFloat) -> UInt8 { bytes[(Int(y) * Int(size.width) + Int(x)) * 4 + 3] }
    }

    private func render(_ project: VideoDemoProject, size: CGSize, at time: Double = 2, zoom: VideoCameraState? = nil, transparent: Bool = false) throws -> Frame {
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 4, recording: nil, hasWebcam: true)
        var options = VideoFrameRenderer.Options(frameRate: 30)
        options.webcamFrame = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.8)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        options.cameraOverride = zoom
        options.transparentBackground = transparent
        let screen = TestVideos.quadrantImage(size: project.sourceSize)
        let image = VideoFrameRenderer().render(source: screen, timelineTime: time, plan: plan, outputSize: size, options: options)
        let cgImage = try #require(CIContext().createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
        return Frame(bytes: TestVideos.rgba(cgImage), size: size)
    }

    private func isCamera(_ c: RGB) -> Bool { TestVideos.close(c, Self.magenta, within: 0.12) }
    private func isScreen(_ c: RGB) -> Bool { TestVideos.quadrantColors.contains { TestVideos.close(c, $0, within: 0.12) } }

    @Test func landscapeSplitFillsBothParts() throws {
        let frame = try render(project(.split), size: CGSize(width: 960, height: 540))
        // Screen on the left half, its top-left and bottom-right corners
        // reaching the part's edges (filled: no bars).
        #expect(isScreen(frame.color(4, 4)) && isScreen(frame.color(475, 535)))
        #expect(TestVideos.close(frame.color(4, 4), Self.red, within: 0.15), "the screen's left edge stays at the part's left")
        // Camera on the right half, edge to edge.
        for (x, y) in [(484.0, 4.0), (956.0, 535.0), (720.0, 270.0)] {
            #expect(isCamera(frame.color(CGFloat(x), CGFloat(y))), "camera at \(x), \(y)")
        }
    }

    @Test func verticalSplitIsScreenAboveCamera() throws {
        let frame = try render(project(.split, aspect: .vertical), size: CGSize(width: 540, height: 960))
        // (The test picture's colors meet in its middle: sampled off it.)
        #expect(isScreen(frame.color(130, 100)) && isScreen(frame.color(4, 4)) && isScreen(frame.color(535, 475)))
        #expect(isCamera(frame.color(270, 700)) && isCamera(frame.color(4, 956)) && isCamera(frame.color(535, 484)))
        let top = try render(project(.split, aspect: .vertical, split: Split(cameraSide: .first)), size: CGSize(width: 540, height: 960))
        #expect(isCamera(top.color(130, 100)) && isScreen(top.color(130, 700)))
    }

    @Test(arguments: [0.3, 0.5, 0.7])
    func theDividerIsWhereTheSplitSizeSays(share: Double) throws {
        let frame = try render(project(.split, split: Split(cameraShare: share)), size: CGSize(width: 960, height: 540))
        let boundary = 960 * (1 - share)
        #expect(isScreen(frame.color(CGFloat(boundary - 6), 270)))
        #expect(isCamera(frame.color(CGFloat(boundary + 6), 270)))
    }

    @Test func theGapShowsTheBackground() throws {
        let frame = try render(project(.split, split: Split(gap: 0.05)), size: CGSize(width: 960, height: 540))
        let parts = VideoSplitLayout.parts(Split(gap: 0.05), in: CGSize(width: 960, height: 540))
        let middle = (parts.screen.maxX + parts.camera.minX) / 2
        #expect(TestVideos.close(frame.color(middle, 270), Self.white, within: 0.1), "the background between the parts")
        // Exported with transparency: the gap is see-through.
        let clear = try render(project(.split, split: Split(gap: 0.05)), size: CGSize(width: 960, height: 540), transparent: true)
        #expect(clear.alpha(middle, 270) < 10)
        #expect(clear.alpha(parts.screen.midX, 270) > 245 && clear.alpha(parts.camera.midX, 270) > 245, "the parts themselves are solid")
    }

    @Test func eachLayoutExportsWhatItSays() throws {
        let size = CGSize(width: 960, height: 540)
        let bubble = try render(project(.bubble), size: size)
        #expect(isScreen(bubble.color(240, 135)), "Bubble: the screen fills the video")
        let rect = VideoFrameRenderer.webcamRect(project(.bubble).webcam, outputSize: size)
        #expect(isCamera(bubble.color(rect.midX, size.height - rect.midY)), "and the camera is in its bubble")
        let screenOnly = try render(project(.screenOnly), size: size)
        #expect(isScreen(screenOnly.color(rect.midX, size.height - rect.midY)), "Screen only: no camera")
        let cameraOnly = try render(project(.cameraOnly), size: size)
        for (x, y) in [(4.0, 4.0), (480.0, 270.0), (956.0, 535.0)] {
            #expect(isCamera(cameraOnly.color(CGFloat(x), CGFloat(y))), "Camera only fills the video")
        }
    }

    @Test func aRecordingOfTheScreenPartFillsItExactly() throws {
        // Recorded with the frame bar: 960 × 1080, the whole video 16:9.
        var setup = VideoRecordingCameraSetup(shape: .circle)
        setup.layout = .split
        setup.videoAspect = 16.0 / 9
        var metadata = VideoDemoRecordingMetadata(videoURLPath: "/tmp/split.mp4", createdAt: Date(), duration: 4, sourceWidth: 960, sourceHeight: 1080, fps: 30, nativeCursorVisible: true, cursorSamples: [], clickEvents: [])
        metadata.webcam = VideoWebcamRecording(path: "/tmp/split-camera.mov", offset: 0, width: 1280, height: 720)
        metadata.cameraSetup = setup
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/split.mp4"), duration: 4, sourceSize: CGSize(width: 960, height: 1080))
        project.apply(metadata: metadata)
        #expect(project.aspectPreset == .source && project.splitVideoAspect == 16.0 / 9)
        #expect(project.canvasSize() == CGSize(width: 1920, height: 1080), "Auto is the whole video")
        #expect(project.webcam.effectiveLayout == .split)

        let frame = try render(project, size: CGSize(width: 960, height: 540))
        // The recording's four corners at the screen part's four corners.
        #expect(TestVideos.close(frame.color(3, 3), Self.red, within: 0.15))
        #expect(TestVideos.close(frame.color(476, 3), Self.green, within: 0.15))
        #expect(TestVideos.close(frame.color(3, 536), Self.blue, within: 0.15))
        #expect(TestVideos.close(frame.color(476, 536), Self.yellow, within: 0.15))
        #expect(isCamera(frame.color(484, 270)))
        // Back to a bubble: Auto is the recording again.
        project.webcam.layout = nil
        #expect(project.canvasSize().width < project.canvasSize().height)
    }

    // MARK: Zooms, captions, transitions

    @Test func aZoomHappensInsideTheScreensPart() throws {
        // Zoomed into the recording's top left: the whole screen part is red.
        let frame = try render(project(.split), size: CGSize(width: 960, height: 540), zoom: VideoCameraState(scale: 2.4, centerX: 0.22, centerY: 0.22))
        for (x, y) in [(10.0, 10.0), (470.0, 10.0), (10.0, 530.0), (470.0, 530.0)] {
            #expect(TestVideos.close(frame.color(CGFloat(x), CGFloat(y)), Self.red, within: 0.15), "zoomed in at \(x), \(y)")
        }
        #expect(isCamera(frame.color(720, 270)), "the camera stays as it is")
    }

    @Test func captionsGoOverTheWholeVideo() throws {
        let plain = try render(project(.split), size: CGSize(width: 960, height: 540))
        let captioned = try render(project(.split) { $0.captions = [VideoCaptionLine(start: 0, end: 4, text: "Across both parts of the video")] }, size: CGSize(width: 960, height: 540))
        func changed(_ xs: ClosedRange<Int>) -> Bool {
            for x in stride(from: xs.lowerBound, through: xs.upperBound, by: 4) {
                for y in stride(from: 380, through: 530, by: 4) where !TestVideos.close(plain.color(CGFloat(x), CGFloat(y)), captioned.color(CGFloat(x), CGFloat(y)), within: 0.05) { return true }
            }
            return false
        }
        #expect(changed(380...476), "over the screen's part")
        #expect(changed(484...580), "and the camera's: centered on the whole video")
    }

    @Test func layoutsOnTheCameraLaneStillWorkOnASplitVideo() throws {
        let full = project(.split) { $0.cameraLayouts = [VideoCameraLayoutRegion(start: 1, end: 3, layout: .fullscreen)] }
        let middle = try render(full, size: CGSize(width: 960, height: 540), at: 2)
        #expect(isCamera(middle.color(10, 270)), "Full camera covers the screen's part too")
        // On its way in: the camera already reaches past its own part.
        let easing = try render(full, size: CGSize(width: 960, height: 540), at: 1.3)
        #expect(isCamera(easing.color(470, 270)))
        let bubble = project(.split) { $0.cameraLayouts = [VideoCameraLayoutRegion(start: 1, end: 3, layout: .bubble)] }
        let inBubble = try render(bubble, size: CGSize(width: 960, height: 540), at: 2)
        #expect(isScreen(inBubble.color(720, 100)), "a Bubble stretch gives the screen the whole video")
        let hidden = project(.split) { $0.cameraLayouts = [VideoCameraLayoutRegion(start: 1, end: 3, layout: .hidden)] }
        #expect(isScreen(try render(hidden, size: CGSize(width: 960, height: 540), at: 2).color(720, 270)), "hidden: the screen alone")
        #expect(isCamera(try render(hidden, size: CGSize(width: 960, height: 540), at: 0.2).color(720, 270)), "split before it")
    }

    @Test func sideBySideOnTheLaneUsesTheSplitOnNewProjectsAndTheOldLookOnOldOnes() throws {
        let region = [VideoCameraLayoutRegion(start: 1, end: 3, layout: .sideBySide)]
        let new = try render(project(.bubble) { $0.cameraLayouts = region }, size: CGSize(width: 960, height: 540))
        #expect(isScreen(new.color(3, 3)), "1.10.0: the screen fills its half, edge to edge")
        #expect(isCamera(new.color(956, 536)))
        let old = try render(project(.bubble) { $0.cameraLayouts = region; $0.webcam.split = nil }, size: CGSize(width: 960, height: 540))
        #expect(TestVideos.close(old.color(3, 3), Self.white, within: 0.1), "before 1.10.0: margins around the panels, as it was")
    }

    // MARK: Adapt to this ratio

    @Test func adaptToThisRatioTurnsSideBySideIntoAboveAndBelow() throws {
        var project = project(.split, split: Split(cameraSide: .second))
        project.aspectPreset = .vertical
        _ = project.adaptToCurrentRatio(hasCursor: false)
        #expect(!VideoSplitLayout.isSideBySide(project.canvasSize()))
        let vertical = try render(project, size: CGSize(width: 540, height: 960))
        #expect(isScreen(vertical.color(130, 120)) && isCamera(vertical.color(130, 760)), "right became bottom")
        project.aspectPreset = .widescreen
        let wide = try render(project, size: CGSize(width: 960, height: 540))
        #expect(isScreen(wide.color(120, 130)) && isCamera(wide.color(760, 130)), "and back: bottom is right")
    }

    // MARK: Projects and handoffs

    @Test func theSplitTravelsInTheProjectFile() throws {
        var project = project(.split, split: Split(cameraSide: .first, cameraShare: 0.4, gap: 0.03))
        project.splitVideoAspect = 16.0 / 9
        project.webcam.placement = VideoWebcamSettings.Placement(x: 0.7, y: 0.7, width: 0.2)
        project.cameraLayouts = [VideoCameraLayoutRegion(start: 1, end: 2, layout: .bubble)]
        let back = try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(project))
        #expect(back.webcam == project.webcam)
        #expect(back.splitVideoAspect == 16.0 / 9)
        #expect(back.cameraLayouts == project.cameraLayouts)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("split-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let package = folder.appendingPathComponent("Split.lfs")
        try VideoProjectPackage.save(VideoProjectContents(project: project, recording: nil, sourceRecordings: [:]), to: package, mode: .linked)
        let opened = try VideoProjectPackage.open(package)
        #expect(opened.contents.project.webcam == project.webcam)
        #expect(opened.contents.project.splitVideoAspect == project.splitVideoAspect)
    }

    @Test func olderProjectsHaveNoSplit() throws {
        let object: [String: Any] = ["visible": true, "size": 0.3, "shape": "rectangle"]
        let webcam = try JSONDecoder().decode(VideoWebcamSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(webcam.layout == nil && webcam.split == nil && webcam.effectiveLayout == .bubble)
        #expect(VideoRecordingCameraSetup.LayoutChoice.of(webcam) == .bubble)
    }

    @Test func theHandoffSpellsOutTheSplit() throws {
        var project = project(.split)
        project.splitVideoAspect = 16.0 / 9
        project.aspectPreset = .source
        let split = try #require(VideoHandoffSplit.make(project: project, recordingSize: CGSize(width: 960, height: 1080)))
        #expect(split.video == CGSize(width: 1920, height: 1080))
        #expect(split.screen == CGRect(x: 0, y: 0, width: 960, height: 1080))
        #expect(split.camera == CGRect(x: 960, y: 0, width: 960, height: 1080))
        let text = split.readme.joined(separator: "\n")
        #expect(text.contains("SPLIT SCREEN") && text.contains("the screen on the left, the camera on the right"))
        #expect(text.contains("Screen: 960 × 1080 at x 0, y 0") && text.contains("Camera: 960 × 1080 at x 960, y 0"))

        var vertical = self.project(.split, aspect: .vertical, split: Split(cameraSide: .first))
        vertical.splitVideoAspect = nil
        let tall = try #require(VideoHandoffSplit.make(project: vertical, recordingSize: CGSize(width: 1080, height: 1920)))
        #expect(!tall.sideBySide && tall.camera.minY == 0 && tall.screen.minY == tall.camera.maxY, "camera on top, measured from the top")
        #expect(VideoHandoffSplit.make(project: self.project(.bubble), recordingSize: CGSize(width: 1920, height: 1080)) == nil)
    }

    // MARK: Chosen before recording

    @Test func eachLayoutChosenBeforeRecordingOpensThatWay() {
        for choice in VideoRecordingCameraSetup.LayoutChoice.allCases {
            var setup = VideoRecordingCameraSetup(shape: .circle)
            setup.layout = choice
            setup.split = Split(cameraSide: .first, cameraShare: 0.6)
            var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/split.mp4"))
            project.apply(cameraSetup: setup)
            #expect(VideoRecordingCameraSetup.LayoutChoice.of(project.webcam) == choice, "\(choice)")
            if choice == .split { #expect(project.webcam.split == setup.split) }
        }
    }
}
