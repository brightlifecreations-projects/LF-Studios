import AppKit
import SwiftUI
import CoreImage
import XCTest
@testable import LFStudiosCore

/// Whisper captions, caption animations, per-ratio versions and finding
/// private info: off until turned on, old projects as they were, and
/// nothing blurred until the user approves.
@MainActor
final class CaptionsRatiosPrivacyTests: XCTestCase {
    override func setUp() async throws {
        VideoTestStorage.isolate()
    }

    private func project(duration: Double = 12) -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/captions-ratios.mp4"), duration: duration, sourceSize: CGSize(width: 1920, height: 1080))
        project.aspectPreset = .widescreen
        return project
    }

    private func json(_ project: VideoDemoProject) throws -> String {
        String(decoding: try JSONEncoder().encode(project), as: UTF8.self)
    }

    // MARK: Off by default, old projects unchanged

    func testEverythingIsOffByDefault() {
        let fresh = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/new.mp4"), duration: 10, sourceSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(fresh.captionStyle.animation, .none)
        XCTAssertTrue(fresh.ratioVersions.isEmpty)
        XCTAssertNil(fresh.ratioShared)
        XCTAssertFalse(fresh.reframeFollowsZooms)
        XCTAssertEqual(VideoCaptionStyle().animation, .none)
        // Apple's recognizer unless Whisper is picked; the camera isn't scanned.
        if UserDefaults.standard.string(forKey: "captionEngine") == nil {
            XCTAssertEqual(VideoWhisperModels.shared.engine, .apple)
        }
        let job = VideoPrivacyJob()
        if UserDefaults.standard.object(forKey: "privacyScanCamera") == nil { XCTAssertFalse(job.scanCamera) }
        XCTAssertTrue(job.checked.isEmpty)
        XCTAssertEqual(job.state, .idle)
        let blur = VideoDemoOverlayEffect(kind: .blur, time: 1)
        XCTAssertNil(blur.motion)
        XCTAssertNil(blur.onCamera)
    }

    func testOldProjectsAreUnchanged() throws {
        var old = project()
        old.captions = [VideoCaptionLine(start: 1, end: 3, text: "Hello there")]
        old.overlayEffects = [VideoDemoOverlayEffect(kind: .blur, time: 2)]
        old.zoomRegions = [VideoZoomRegion(start: 2, end: 5)]
        let encoder = JSONEncoder()
        // Dictionaries come out in any order: sorted, the bytes compare.
        encoder.outputFormatting = .sortedKeys
        let saved = try encoder.encode(old)
        let text = String(decoding: saved, as: UTF8.self)
        for key in ["animation", "ratioVersions", "ratioShared", "ratioBase", "previousRatio", "reframeFollowsZooms", "motion", "onCamera"] {
            XCTAssertFalse(text.contains("\"\(key)\""), "\(key) isn't written until used")
        }
        let reopened = try JSONDecoder().decode(VideoDemoProject.self, from: saved)
        XCTAssertEqual(reopened, old)
        XCTAssertEqual(try encoder.encode(reopened), saved, "saved again byte for byte")

        // A caption style from before animations decodes as None.
        let style = try JSONDecoder().decode(VideoCaptionStyle.self, from: Data(#"{"visible":true,"size":"medium","position":"bottom","highlightWords":true,"preset":"classic"}"#.utf8))
        XCTAssertEqual(style.animation, .none)
    }

    // MARK: Caption animations

    private let timings = [VideoCaptionAnimator.Timing(start: 1, end: 1.4), .init(start: 1.5, end: 2.1), .init(start: 2.2, end: 2.6)]

    func testPopInAndFadeUpTiming() {
        let before = VideoCaptionAnimator.frame(.popIn, timings: timings, letters: [5, 5, 5], at: 0.9)
        XCTAssertEqual(before.words.map(\.opacity), [0, 0, 0], "nothing before its word")
        let popping = VideoCaptionAnimator.frame(.popIn, timings: timings, letters: [5, 5, 5], at: 1.5 + 0.08)
        XCTAssertEqual(popping.words[0], VideoCaptionWordState(), "the first word has settled")
        XCTAssertGreaterThan(popping.words[1].opacity, 0)
        XCTAssertLessThan(popping.words[1].scale, 1.2)
        XCTAssertEqual(popping.words[2].opacity, 0)
        let settled = VideoCaptionAnimator.frame(.popIn, timings: timings, letters: [5, 5, 5], at: 3)
        XCTAssertEqual(settled.words, Array(repeating: VideoCaptionWordState(), count: 3))

        let rising = VideoCaptionAnimator.frame(.fadeUp, timings: timings, letters: [5, 5, 5], at: 1.1)
        XCTAssertLessThan(rising.words[0].lift, 0, "starts below and rises")
        XCTAssertGreaterThan(rising.words[0].opacity, 0)
        XCTAssertLessThan(rising.words[0].opacity, 1)
        XCTAssertEqual(VideoCaptionAnimator.frame(.fadeUp, timings: timings, letters: [5, 5, 5], at: 1.4).words[0].lift, 0)
    }

    func testKaraokeTypewriterBounceOneWordAndBox() {
        let karaoke = VideoCaptionAnimator.frame(.karaoke, timings: timings, letters: [5, 5, 5], at: 1.8)
        XCTAssertEqual(karaoke.words.map(\.fill), [1, 0.5, 0], "filled up to where the voice is")

        var shown: [Int] = []
        for t in stride(from: 1.45, through: 2.3, by: 0.05) {
            shown.append(VideoCaptionAnimator.frame(.typewriter, timings: timings, letters: [5, 8, 4], at: t).words[1].letters ?? -1)
        }
        XCTAssertEqual(shown.first, 0)
        XCTAssertEqual(shown.last, 8, "the whole word in the end")
        XCTAssertEqual(shown, shown.sorted(), "letters only ever appear")

        let bounce = VideoCaptionAnimator.frame(.bounce, timings: timings, letters: [5, 5, 5], at: 1.1)
        XCTAssertGreaterThan(bounce.words[0].lift, 0)
        XCTAssertEqual(bounce.words[1].opacity, 1, "every word shows while others bounce")
        XCTAssertEqual(VideoCaptionAnimator.frame(.bounce, timings: timings, letters: [5, 5, 5], at: 1.5).words[0].lift, 0)

        XCTAssertEqual(VideoCaptionAnimator.frame(.oneWord, timings: timings, letters: [5, 5, 5], at: 1.2).single, 0)
        XCTAssertEqual(VideoCaptionAnimator.frame(.oneWord, timings: timings, letters: [5, 5, 5], at: 2.3).single, 2)

        let gliding = VideoCaptionAnimator.frame(.highlightBox, timings: timings, letters: [5, 5, 5], at: 1.5 + VideoCaptionAnimator.glideDuration / 2)
        XCTAssertGreaterThan(gliding.box ?? 0, 0)
        XCTAssertLessThan(gliding.box ?? 1, 1)
        XCTAssertEqual(VideoCaptionAnimator.frame(.highlightBox, timings: timings, letters: [5, 5, 5], at: 2).box, 1)
        XCTAssertNil(VideoCaptionAnimator.frame(.highlightBox, timings: timings, letters: [5, 5, 5], at: 0.5).box)
    }

    func testTypedCaptionsSpreadTheirWords() {
        let words = VideoCaptionAnimator.words(of: "Click Export to finish")
        XCTAssertEqual(words.count, 4)
        let spread = VideoCaptionAnimator.evenTimings(for: words, start: 2, end: 4)
        XCTAssertEqual(spread.first?.start, 2)
        XCTAssertEqual(spread.last?.end ?? 0, 4, accuracy: 0.0001)
        XCTAssertEqual(zip(spread, spread.dropFirst()).allSatisfy { $0.end <= $1.start + 0.0001 }, true)
        XCTAssertEqual(VideoCaptionAnimator.words(of: "字幕を表示します").count, 8, "written without spaces: letter by letter")
    }

    func testAnimatedCaptionsDrawTheSameEveryTime() throws {
        var style = VideoCaptionStyle()
        style.font = VideoFontChoice(family: "Georgia", weight: .bold, outline: true)
        let words = ["Pick", "a", "font", "you", "like"]
        for animation in VideoCaptionAnimation.allCases where animation != .none && animation != .oneWord {
            style.animation = animation
            var sizes: Set<String> = []
            for t in stride(from: 0.0, through: 2.5, by: 0.25) {
                let frame = VideoCaptionAnimator.frame(animation, timings: VideoCaptionAnimator.evenTimings(for: words, start: 0, end: 2), letters: words.map(\.count), at: t)
                let image = try XCTUnwrap(VideoCaptionDrawing.image(text: words.joined(separator: " "), words: words, spoken: nil, style: style, fontSize: 40, maxWidth: 800, animation: frame), "\(animation)")
                sizes.insert("\(image.width)x\(image.height)")
            }
            XCTAssertEqual(sizes.count, 1, "\(animation): the caption keeps its size and place while it animates")
        }
    }

    func testPreviewAndExportDrawTheSameAnimatedFrame() throws {
        var project = project()
        project.captions = [VideoCaptionLine(start: 1, end: 4, text: "Every word pops in", placement: VideoTextPlacement(x: 0.3, y: 0.2))]
        project.captionStyle.visible = true
        project.captionStyle.animation = .popIn
        project.aspectPreset = .vertical
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 12, recording: nil)
        let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let output = CGSize(width: 540, height: 960)
        func render(_ renderer: VideoFrameRenderer) -> Data {
            var options = VideoFrameRenderer.Options()
            options.recordsTextLayout = true
            let image = renderer.render(source: source, timelineTime: 2.1, plan: plan, outputSize: output, options: options)
            var pixels = Data(count: Int(output.width * output.height) * 4)
            pixels.withUnsafeMutableBytes { VideoRenderContext.shared.render(image, toBitmap: $0.baseAddress!, rowBytes: Int(output.width) * 4, bounds: CGRect(origin: .zero, size: output), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) }
            return pixels
        }
        let preview = VideoFrameRenderer(), exporter = VideoFrameRenderer()
        XCTAssertEqual(render(preview), render(exporter), "one renderer, one result: the export matches the preview")
        let box = try XCTUnwrap(preview.textLayout.caption?.rect)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(box), "inside the vertical frame at its own spot")
    }

    func testOneWordAtATimeShowsEachWord() throws {
        var project = project()
        let words = ["Every", "word", "counts"].enumerated().map { VideoCaptionWord(text: $1, start: 1 + Double($0) * 0.5, end: 1.4 + Double($0) * 0.5) }
        project.captions = [VideoCaptionLine(start: 1, end: 3, text: "Every word counts", words: words)]
        project.captionStyle.visible = true
        project.captionStyle.animation = .oneWord
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 12, recording: nil)
        let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let renderer = VideoFrameRenderer()
        var widths: [CGFloat] = []
        for time in [1.3, 1.8, 2.7] {
            var options = VideoFrameRenderer.Options()
            options.recordsTextLayout = true
            _ = renderer.render(source: source, timelineTime: time, plan: plan, outputSize: CGSize(width: 960, height: 540), options: options)
            widths.append(try XCTUnwrap(renderer.textLayout.caption?.rect.width))
        }
        // "Every", "word", "counts": three different boxes from one renderer.
        XCTAssertEqual(Set(widths.map { Int($0 * 1000) }).count, 3, "each moment draws its own word: \(widths)")
    }

    func testAnimationIsSavedInPresets() throws {
        var project = project()
        project.captionStyle.animation = .karaoke
        let preset = project.style
        let data = try JSONEncoder().encode(preset)
        XCTAssertEqual(try JSONDecoder().decode(VideoStylePreset.self, from: data).captionStyle.animation, .karaoke)
        var other = self.project()
        other.apply(style: preset)
        XCTAssertEqual(other.captionStyle.animation, .karaoke)
    }

    // MARK: Adapt to this ratio

    private func wide() -> VideoDemoProject {
        var project = project()
        project.webcam.anchor = .bottomRight
        project.webcam.size = 0.26
        var zoom = VideoZoomRegion(start: 2, end: 5, followsCursor: false, focusX: 0.12, focusY: 0.4)
        zoom.offsetX = 0.3
        zoom.cameraCorner = .topLeft
        project.zoomRegions = [zoom]
        project.captions = [VideoCaptionLine(start: 1, end: 3, text: "One"), VideoCaptionLine(start: 4, end: 6, text: "Two", placement: VideoTextPlacement(x: 0.9, y: 0.95))]
        return project
    }

    func testEachRatioKeepsItsOwnVersion() throws {
        var project = wide()
        project.switchRatio(to: .vertical)
        XCTAssertNil(project.ratioShared, "switching alone changes nothing")
        XCTAssertEqual(project.webcam.anchor, .bottomRight)

        let report = project.adaptToCurrentRatio(hasCursor: false)
        XCTAssertEqual(report.zooms, 1)
        XCTAssertTrue(report.movedCamera)
        XCTAssertEqual(project.webcam.anchor, .topRight, "the bottom of a vertical frame is for captions")
        XCTAssertEqual(project.zoomRegions[0].offsetX, 0)
        XCTAssertNil(project.zoomRegions[0].cameraCorner)
        let placed = try XCTUnwrap(project.captions[1].placement)
        XCTAssertTrue((0.16...0.74).contains(placed.y) && (0.4...0.6).contains(placed.x), "captions in the safe area")
        XCTAssertNotNil(project.captionStyle.placement)
        XCTAssertEqual(project.ratiosToExport, [.widescreen, .vertical])

        // 9:16 edited a bit more, then back to 16:9: as it was.
        project.webcam.size = 0.3
        project.switchRatio(to: .widescreen)
        XCTAssertEqual(project.webcam.anchor, .bottomRight)
        XCTAssertEqual(project.webcam.size, 0.26)
        XCTAssertEqual(project.zoomRegions[0].offsetX, 0.3)
        XCTAssertEqual(project.zoomRegions[0].cameraCorner, .topLeft)
        XCTAssertEqual(project.captions[1].placement, VideoTextPlacement(x: 0.9, y: 0.95))
        XCTAssertNil(project.captionStyle.placement)

        // And 9:16 comes back with its own.
        project.switchRatio(to: .vertical)
        XCTAssertEqual(project.webcam.anchor, .topRight)
        XCTAssertEqual(project.webcam.size, 0.3)
        XCTAssertEqual(project.zoomRegions[0].offsetX, 0)

        // A ratio never adapted uses the shared values; 16:9 edits stay shared.
        project.switchRatio(to: .square)
        XCTAssertEqual(project.webcam.anchor, .bottomRight)
        XCTAssertEqual(project.version(for: .vertical).webcam.anchor, .topRight)

        // Saved and reopened, every version is still there.
        let reopened = try JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(reopened, project)
        var back = reopened
        back.switchRatio(to: .vertical)
        XCTAssertEqual(back.webcam.size, 0.3)
    }

    func testSharedPartsStayShared() {
        var project = wide()
        project.switchRatio(to: .vertical)
        project.adaptToCurrentRatio(hasCursor: false)
        // Cuts, caption text and new zooms are the same in every ratio.
        project.captions[0].text = "Changed in 9:16"
        project.zoomRegions.append(VideoZoomRegion(start: 7, end: 9))
        project.switchRatio(to: .widescreen)
        XCTAssertEqual(project.captions[0].text, "Changed in 9:16")
        XCTAssertEqual(project.zoomRegions.count, 2)
    }

    func testTheNarrowFrameKeepsTheZoomTargetInView() {
        var project = wide()
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 12)
        // The pointer stays on the right; the zoom looks at the far left.
        project.cursorSamples = samples.map { var s = $0; s.x = 0.85; s.y = 0.5; return s }
        project.clickEvents = clicks
        project.switchRatio(to: .vertical)
        project.reframe = true
        /// The reframing window, and where the zoom's subject is in the
        /// scene it pans across.
        func look(_ project: VideoDemoProject, at time: Double) -> (window: ClosedRange<Double>, subject: Double) {
            let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 12, recording: nil)
            let reframe = plan.reframe!
            let center = Double(reframe.center(at: time))
            let state = plan.camera.state(at: time)
            let canvasX = Double(plan.stageRect.minX + plan.stageRect.width * 0.12) / Double(plan.canvasSize.width)
            let subject = (canvasX - state.centerX) * state.scale + 0.5
            return ((center - Double(reframe.windowFraction) / 2)...(center + Double(reframe.windowFraction) / 2), subject)
        }
        let before = look(project, at: 4)
        XCTAssertFalse(before.window.contains(before.subject), "before adapting, the window stays on the pointer")
        project.adaptToCurrentRatio(hasCursor: true)
        XCTAssertTrue(project.reframeFollowsZooms)
        let after = look(project, at: 4)
        XCTAssertTrue(after.window.contains(after.subject), "the zoom's target is in frame: \(after)")
    }

    // MARK: Private info: patterns

    func testPrivateInfoIsFoundInSampleText() {
        func kinds(_ text: String, words: [String] = []) -> [VideoPrivacyKind] { VideoPrivacyPatterns.matches(in: text, customWords: words).map(\.kind) }
        XCTAssertEqual(kinds("Write to jane.doe@example.com today"), [.email])
        XCTAssertEqual(kinds("Call +1 (415) 555-0132 now"), [.phone])
        XCTAssertEqual(kinds("Phone: 020 7946 0958"), [.phone])
        XCTAssertEqual(kinds("Card 4111 1111 1111 1111 exp 12/29"), [.card])
        XCTAssertEqual(kinds("OPENAI_API_KEY=sk-proj-4fG7hJ2kL9mN3pQ8rS1tV6wX"), [.secret])
        XCTAssertEqual(kinds("aws AKIAIOSFODNN7EXAMPLE"), [.secret])
        XCTAssertEqual(kinds("token ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"), [.secret])
        XCTAssertEqual(kinds("password: hunter2!"), [.secret])
        let labeled = VideoPrivacyPatterns.matches(in: "password: hunter2!").first
        XCTAssertEqual(labeled?.text, "hunter2!", "the value, not the label")
        XCTAssertEqual(kinds("id Zx81Qp0Lm2Nb7Vc4Xs9Wq3Ek5Rt6Yu"), [.possibleKey])
        XCTAssertEqual(kinds("Meeting with Acme Corp about acme corp's launch", words: ["Acme Corp"]), [.customWord, .customWord])
        XCTAssertEqual(kinds("Acmefoo isn't the word", words: ["Acme"]), [], "whole words only")
    }

    func testOrdinaryTextIsNotPrivate() {
        for text in [
            "Released 2026-10-28 as version 1.4.0",
            "Total $1,299.00 for 3 items",
            "Order 12345 shipped",
            "Card 4111 1111 1111 1112 fails its checksum",
            "Read the documentation thoroughly before installing",
            "https://github.com/brightlifecreations-projects/LF-Studios",
            "00000000000",
        ] {
            XCTAssertEqual(VideoPrivacyPatterns.matches(in: text).map(\.kind), [], text)
        }
    }

    // MARK: Private info: following it, and blurring only what's approved

    /// A page scrolling up: the email line moves from 0.8 to 0.2 of the
    /// frame's height over 3 seconds.
    private func scrollingScan() -> VideoPrivacyFileScan {
        let line = "Contact jane.doe@example.com for access"
        let emailStart = line.utf16.distance(from: line.startIndex, to: line.range(of: "jane")!.lowerBound)
        var frames: [VideoPrivacyFrame] = []
        for step in 0...12 {
            let time = 2 + Double(step) * 0.25
            let y = 0.8 - Double(step) * 0.05
            let words = [
                VideoPrivacyFrame.Word(start: 0, length: 7, box: VideoPrivacyBox(x: 0.1, y: y, width: 0.08, height: 0.03)),
                VideoPrivacyFrame.Word(start: emailStart, length: 20, box: VideoPrivacyBox(x: 0.19, y: y, width: 0.22, height: 0.03)),
            ]
            frames.append(VideoPrivacyFrame(time: time, lines: [.init(text: line, words: words)], faces: step < 6 ? [VideoPrivacyBox(x: 0.7, y: 0.1, width: 0.1, height: 0.15)] : []))
        }
        return VideoPrivacyFileScan(frames: frames)
    }

    func testTheBlurFollowsAScrollingPage() throws {
        let items = VideoPrivacyTracker.items(from: scrollingScan(), timeOffset: 0, onCamera: false, customWords: [])
        let email = try XCTUnwrap(items.first { $0.kind == .email })
        XCTAssertEqual(items.filter { $0.kind == .email }.count, 1, "one item, followed")
        XCTAssertEqual(email.keys.count, 13)
        XCTAssertEqual(email.text, "jane.doe@example.com")
        XCTAssertEqual(items.filter { $0.kind == .face }.count, 1)

        let effect = email.blurEffect(crop: .full, layer: 0)
        XCTAssertEqual(effect.kind, .blur)
        let motion = try XCTUnwrap(effect.motion, "a moving blur")
        XCTAssertEqual(motion.count, 13)
        // Between two frames it's between their places.
        let mid = effect.placed(atSource: 2.125)
        XCTAssertEqual(mid.y, (motion[0].y + motion[1].y) / 2, accuracy: 0.0001)
        XCTAssertEqual(effect.placed(atSource: 5).y, motion.last!.y, accuracy: 0.0001)
        // It covers the email, not the whole line.
        XCTAssertLessThan(effect.width, 0.3)
        XCTAssertEqual(effect.x, 0.19 + 0.11, accuracy: 0.02)
        // A gap of a missed read is bridged; the same email elsewhere at once is another item.
        var scan = scrollingScan()
        scan.frames.remove(at: 5)
        var twice = scan.frames[3]
        twice.lines[0].words[1].box.y = 0.05
        twice.time += 0.01
        scan.frames.insert(twice, at: 4)
        let again = VideoPrivacyTracker.items(from: scan, timeOffset: 0, onCamera: false, customWords: [])
        XCTAssertEqual(again.filter { $0.kind == .email && $0.keys.count > 5 }.count, 1)
    }

    func testCropMapsTheBlurIntoTheCroppedFrame() {
        let item = VideoPrivacyItem(id: UUID(), kind: .email, text: "a@b.co", keys: [.init(time: 1, box: VideoPrivacyBox(x: 0.5, y: 0.5, width: 0.1, height: 0.04)), .init(time: 1.25, box: VideoPrivacyBox(x: 0.5, y: 0.5, width: 0.1, height: 0.04))], onCamera: false)
        let crop = VideoCropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let effect = item.blurEffect(crop: crop, layer: 0)
        XCTAssertNil(effect.motion, "still: one box")
        XCTAssertEqual(effect.x, 0.6, accuracy: 0.01)
        XCTAssertEqual(effect.y, 0.54, accuracy: 0.01)
        XCTAssertGreaterThan(effect.width, 0.2)
    }

    func testNothingIsBlurredWithoutApproval() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-\(UUID().uuidString).mp4")
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 640, height: 400), seconds: 6, fps: 15)
        defer { try? FileManager.default.removeItem(at: url); VideoDemoDraftStore.delete(for: url) }
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        let before = model.project.overlayEffects
        let items = VideoPrivacyTracker.items(from: scrollingScan(), timeOffset: 0, onCamera: false, customWords: [])
        model.privacyJob.present(items)
        XCTAssertTrue(model.privacyJob.checked.isEmpty, "nothing ticked")
        model.blurSelectedPrivateInfo()
        XCTAssertEqual(model.project.overlayEffects, before, "nothing blurred")

        let email = try XCTUnwrap(items.first { $0.kind == .email })
        model.privacyJob.checked = [email.id]
        model.blurSelectedPrivateInfo()
        XCTAssertEqual(model.project.overlayEffects.count, before.count + 1)
        XCTAssertNotNil(model.project.overlayEffects.last?.motion)
        XCTAssertTrue(model.privacyJob.blurred.contains(email.id))
        XCTAssertEqual(model.undoLabel, "Blur Private Info")
        model.undo()
        XCTAssertEqual(model.project.overlayEffects, before, "one ⌘Z")
    }

    func testMovingATrackedBlurMovesItsPath() {
        var effect = VideoDemoOverlayEffect(kind: .blur, time: 2, duration: 2, x: 0.3, y: 0.8, width: 0.2, height: 0.05)
        effect.motion = [.init(time: 2, x: 0.3, y: 0.8, width: 0.2, height: 0.05), .init(time: 4, x: 0.3, y: 0.2, width: 0.2, height: 0.05)]
        let old = effect
        effect.x += 0.1
        effect.time += 1
        effect.width = 0.4
        effect.followMove(from: old)
        XCTAssertEqual(effect.motion?[1].x ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(effect.motion?[1].time, 5)
        XCTAssertEqual(effect.motion?[1].width ?? 0, 0.4, accuracy: 0.0001)
    }

    // MARK: Whisper

    func testWhisperWordsAndLanguages() {
        XCTAssertEqual(VideoWhisperTranscriber.languageCode("en-US"), "en")
        XCTAssertEqual(VideoWhisperTranscriber.languageCode("de"), "de")
        XCTAssertNil(VideoWhisperTranscriber.languageCode(""))
        XCTAssertNil(VideoWhisperTranscriber.languageCode(nil))
        let timed: [VideoWhisperTranscriber.TimedWord] = [
            .init(text: "<|startoftranscript|>", start: 0, end: 0),
            .init(text: " Hello", start: 0.5, end: 0.9),
            .init(text: ",", start: 0.9, end: 0.95),
            .init(text: " world", start: 1.0, end: 1.4),
        ]
        let words = VideoWhisperTranscriber.words(from: timed, offset: 2)
        XCTAssertEqual(words.map(\.text), ["Hello,", "world"])
        XCTAssertEqual(words[0].start, 2.5, accuracy: 0.001)
        XCTAssertEqual(words[0].end, 2.95, accuracy: 0.001)
    }

    func testModelsAreOnlyThereOnceDownloaded() {
        VideoWhisperModels.baseOverride = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-\(UUID().uuidString)")
        defer { VideoWhisperModels.baseOverride = nil }
        for model in VideoWhisperModel.allCases {
            XCTAssertFalse(VideoWhisperModels.isInstalled(model))
            XCTAssertGreaterThan(model.approximateBytes, 0)
        }
        XCTAssertEqual(VideoWhisperModel.allCases.map(\.approximateBytes), VideoWhisperModel.allCases.map(\.approximateBytes).sorted(), "small/fast to large/accurate")
    }

    func testSettingsListsTheModelsWithDownloadAndDelete() async throws {
        VideoWhisperModels.baseOverride = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-\(UUID().uuidString)")
        defer { VideoWhisperModels.baseOverride = nil; VideoWhisperModels.shared.refresh() }
        VideoWhisperModels.shared.refresh()
        XCTAssertTrue(VideoWhisperModels.shared.installed.isEmpty, "nothing downloaded: a Download button for each")
        let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 10) { WhisperModelsSettingsSection() }
            .padding(20).frame(width: 560).background(Color(white: 0.12)).environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        XCTAssertGreaterThan(host.fittingSize.height, 200, "four models listed")
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = LFStudiosColors.editorStageTop
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        host.layoutSubtreeIfNeeded()
        if let frames = ProcessInfo.processInfo.environment["LFSTUDIOS_TEST_FRAMES"] {
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: frames).appendingPathComponent("captions-privacy/settings-whisper-models.png"))
        }
        window.contentView = nil
    }

    func testATooSlowMacGetsASmallerModel() {
        let supported = [VideoWhisperModel.tiny.variant, VideoWhisperModel.base.variant, VideoWhisperModel.small.variant]
        XCTAssertNil(VideoWhisperModels.unsuitability(of: .small, supported: supported))
        let large = VideoWhisperModels.unsuitability(of: .largeTurbo, supported: supported)
        XCTAssertEqual(large?.suggestion, .small)
        let none = VideoWhisperModels.unsuitability(of: .tiny, supported: [])
        XCTAssertNotNil(none)
        XCTAssertNil(none?.suggestion)
    }
}
