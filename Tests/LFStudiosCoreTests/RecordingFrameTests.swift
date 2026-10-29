import AppKit
import XCTest
@testable import LFStudiosCore

/// The frame bar (1.8.0): ratios and sizes on every kind of display, exact
/// pixel sizes, resizing that keeps the ratio, snapping, Custom… input,
/// memory per display, clicks passing through, keys, and Fit a window.
@MainActor
final class RecordingFrameTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var controllers: [RecordingFrameController] = []
    private var windows: [NSWindow] = []
    private var bars: [RecordingControlsWindow] = []

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suiteName = "LFStudiosCoreTests.RecordingFrame.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        Settings.defaults = defaults
    }

    override func tearDown() {
        controllers.forEach { $0.close() }
        controllers = []
        windows.forEach { $0.orderOut(nil) }
        windows = []
        bars.forEach { $0.closeControls() }
        bars = []
        defaults.removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        super.tearDown()
    }

    private typealias Pixels = RecordingFrameGeometry.Pixels

    /// Displays of every shape: (points, scale).
    private let displays: [(name: String, frame: CGRect, scale: CGFloat)] = [
        ("MacBook Pro 14", CGRect(x: 0, y: 0, width: 1512, height: 982), 2),
        ("MacBook Air 13", CGRect(x: 0, y: 0, width: 1470, height: 956), 2),
        ("1080p monitor", CGRect(x: 1512, y: 0, width: 1920, height: 1080), 1),
        ("4K at 2x", CGRect(x: -1920, y: 200, width: 1920, height: 1080), 2),
        ("5K", CGRect(x: 0, y: 982, width: 2560, height: 1440), 2),
        ("Portrait 1080p", CGRect(x: 3432, y: -400, width: 1080, height: 1920), 1),
        ("Old 1440x900", CGRect(x: 0, y: 0, width: 1440, height: 900), 1),
        ("Ultrawide", CGRect(x: 0, y: 0, width: 3440, height: 1440), 1),
    ]

    private func exactShape(_ pixels: Pixels, _ ratio: RecordingFrameRatio, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pixels.width * ratio.height, pixels.height * ratio.width, "\(pixels) is exactly \(ratio.text)", file: file, line: line)
        XCTAssertTrue(pixels.width.isMultiple(of: 2) && pixels.height.isMultiple(of: 2), "\(pixels): even sides, as video wants", file: file, line: line)
    }

    // MARK: Ratios

    func testPresetsTheirNamesAndPurposes() {
        XCTAssertEqual(RecordingFrameRatio.presets.map(\.label), ["16:9", "9:16", "1:1", "4:5", "4:3", "16:10", "21:9"])
        XCTAssertEqual(RecordingFrameRatio.presets.map(\.purpose), ["YouTube", "Reels / TikTok / Shorts", "Square posts", "Instagram feed", "Slides / iPad", "Mac screen", "Cinematic"])
        XCTAssertEqual(RecordingFrameRatio(16, 10), RecordingFrameRatio(8, 5), "kept in lowest terms")
        XCTAssertEqual(RecordingFrameRatio(16, 10).label, "16:10", "but labelled the way people know it")
        XCTAssertEqual(RecordingFrameRatio(3, 2).label, "3:2")
        XCTAssertEqual(RecordingFrameRatio.standard, RecordingFrameRatio(16, 9))
    }

    func testCustomRatioInput() {
        XCTAssertEqual(RecordingFrameRatio.parse("3:2"), RecordingFrameRatio(3, 2))
        XCTAssertEqual(RecordingFrameRatio.parse(" 3 : 2 "), RecordingFrameRatio(3, 2))
        XCTAssertEqual(RecordingFrameRatio.parse("3x2"), RecordingFrameRatio(3, 2))
        XCTAssertEqual(RecordingFrameRatio.parse("3 × 2"), RecordingFrameRatio(3, 2))
        XCTAssertEqual(RecordingFrameRatio.parse("3/2"), RecordingFrameRatio(3, 2))
        XCTAssertEqual(RecordingFrameRatio.parse("6:4"), RecordingFrameRatio(3, 2))
        XCTAssertEqual(RecordingFrameRatio.parse("2.39:1"), RecordingFrameRatio(239, 100))
        XCTAssertEqual(RecordingFrameRatio.parse("1,85:1"), RecordingFrameRatio(37, 20), "a decimal comma works too")
        XCTAssertEqual(RecordingFrameRatio.parse("1920:1080"), RecordingFrameRatio(16, 9))
        for bad in ["", "abc", "3:", ":2", "3", "0:1", "1:0", "-3:2", "3:2:1", "9:1", "1:9", "401:3", "2.395:1", "3e2:1"] {
            XCTAssertNil(RecordingFrameRatio.parse(bad), "“\(bad)” isn't a usable shape")
        }
    }

    // MARK: Sizes

    func testSizePresetsForEveryRatio() {
        let expected: [String: [Int]] = [
            "16:9": [1280, 720, 1920, 1080, 2560, 1440],
            "9:16": [720, 1280, 1080, 1920, 1440, 2560],
            "1:1": [720, 720, 1080, 1080, 1440, 1440],
            "4:5": [720, 900, 1080, 1350, 1440, 1800],
            "4:3": [960, 720, 1440, 1080, 1920, 1440],
            "16:10": [1152, 720, 1728, 1080, 2304, 1440],
            "21:9": [1680, 720, 2520, 1080, 3360, 1440],
        ]
        for preset in RecordingFrameRatio.presets {
            let sizes = [720, 1080, 1440].map { RecordingFrameGeometry.pixels(preset.ratio, shortSide: $0) }
            XCTAssertEqual(sizes.flatMap { [$0.width, $0.height] }, expected[preset.label], preset.label)
            sizes.forEach { exactShape($0, preset.ratio) }
        }
        // A custom shape: as near as its steps allow, still exact.
        let wide = RecordingFrameRatio(239, 100)
        let size = RecordingFrameGeometry.pixels(wide, shortSide: 1080)
        exactShape(size, wide)
        XCTAssertEqual(size.height, 1000, "the nearest exact 2.39:1 to 1080 high")
    }

    func testSizeMenuOnEveryDisplay() {
        let ratios = RecordingFrameRatio.presets.map(\.ratio) + [RecordingFrameRatio(3, 2), RecordingFrameRatio(239, 100)]
        for display in displays {
            let available = RecordingFrameGeometry.available(screenFrame: display.frame, scale: display.scale)
            for ratio in ratios {
                let choices = RecordingFrameGeometry.sizeChoices(ratio, in: available)
                XCTAssertFalse(choices.isEmpty, "\(display.name) \(ratio.text)")
                for choice in choices {
                    XCTAssertTrue(RecordingFrameGeometry.fits(choice.pixels, in: available), "\(display.name) \(ratio.text): \(choice.name) fits")
                    exactShape(choice.pixels, ratio)
                }
                XCTAssertEqual(Set(choices.map(\.pixels)).count, choices.count, "no size twice")
                // The last is the largest that fits: one step more doesn't.
                let largest = try? XCTUnwrap(choices.last)
                let step = RecordingFrameGeometry.step(ratio)
                if let largest {
                    let bigger = Pixels(width: largest.pixels.width + step.width, height: largest.pixels.height + step.height)
                    XCTAssertFalse(RecordingFrameGeometry.fits(bigger, in: available), "\(display.name) \(ratio.text): \(largest.pixels) is the largest")
                }
                // 720p, 1080p and 1440p are offered exactly where they fit.
                for (name, short) in [("720p", 720), ("1080p", 1080), ("1440p", 1440)] {
                    let size = RecordingFrameGeometry.pixels(ratio, shortSide: short)
                    XCTAssertEqual(choices.contains { $0.name == name }, RecordingFrameGeometry.fits(size, in: available), "\(display.name) \(ratio.text) \(name)")
                }
            }
        }
        // Concretely: a 14" MacBook Pro.
        let macBook = RecordingFrameGeometry.available(screenFrame: displays[0].frame, scale: 2)
        XCTAssertEqual(macBook, Pixels(width: 3024, height: 1964))
        XCTAssertEqual(RecordingFrameGeometry.sizeChoices(.standard, in: macBook).map(\.name), ["720p", "1080p", "1440p", "Largest"])
        XCTAssertEqual(RecordingFrameGeometry.sizeChoices(.standard, in: macBook).last?.pixels, Pixels(width: 3008, height: 1692))
        XCTAssertEqual(RecordingFrameGeometry.sizeChoices(RecordingFrameRatio(9, 16), in: macBook).map(\.name), ["720p", "1080p", "Largest"], "1440 wide is 2560 tall: too tall")
        // A 1440×900 display at 1x: no 1080p in 16:9.
        let old = RecordingFrameGeometry.available(screenFrame: displays[6].frame, scale: 1)
        XCTAssertEqual(RecordingFrameGeometry.sizeChoices(.standard, in: old).map(\.name), ["720p", "Largest"])
        XCTAssertEqual(RecordingFrameGeometry.defaultPixels(.standard, in: old), Pixels(width: 1440, height: 810), "1080p doesn't fit: the largest does")
        XCTAssertEqual(RecordingFrameGeometry.defaultPixels(.standard, in: macBook), Pixels(width: 1920, height: 1080))
    }

    /// The frame in points records exactly its pixels: RecordingEngine's own
    /// geometry (even sides, the pixel grid) changes nothing.
    func testFrameRecordsExactlyItsPixels() {
        for display in displays {
            let available = RecordingFrameGeometry.available(screenFrame: display.frame, scale: display.scale)
            for preset in RecordingFrameRatio.presets {
                for choice in RecordingFrameGeometry.sizeChoices(preset.ratio, in: available) {
                    for origin in [CGPoint(x: display.frame.minX + 13.3, y: display.frame.minY + 7.77), CGPoint(x: display.frame.maxX, y: display.frame.maxY), CGPoint(x: display.frame.minX - 50, y: display.frame.midY)] {
                        let rect = RecordingFrameGeometry.rect(choice.pixels, origin: origin, screenFrame: display.frame, scale: display.scale)
                        XCTAssertTrue(display.frame.contains(rect), "\(display.name): on the display")
                        let geometry = RecordingEngine.captureGeometry(rect: rect, screenFrame: display.frame, scale: display.scale)
                        XCTAssertEqual(geometry.pixelWidth, choice.pixels.width, "\(display.name) \(preset.label) \(choice.name)")
                        XCTAssertEqual(geometry.pixelHeight, choice.pixels.height, "\(display.name) \(preset.label) \(choice.name)")
                        XCTAssertEqual(geometry.capturedRect, rect, "what's recorded is exactly the frame shown")
                        XCTAssertEqual(RecordingFrameGeometry.pixels(of: rect, scale: display.scale), choice.pixels)
                    }
                }
            }
        }
        // And the encoder keeps that size (Apple silicon's HEVC above 4K).
        let format = RecordingVideoFormat.plan(width: 3360, height: 1440, fps: 60, hevcAvailable: true)
        XCTAssertEqual([format.width, format.height], [3360, 1440])
        let fivek = RecordingVideoFormat.plan(width: 5120, height: 2194, fps: 30, hevcAvailable: true)
        XCTAssertEqual([fivek.width, fivek.height], [5120, 2194])
    }

    // MARK: Resizing and snapping

    func testResizingFromEachCornerKeepsTheRatio() {
        for display in [displays[0], displays[2], displays[5]] {
            for ratio in RecordingFrameRatio.presets.map(\.ratio) + [RecordingFrameRatio(3, 2)] {
                let available = RecordingFrameGeometry.available(screenFrame: display.frame, scale: display.scale)
                let size = RecordingFrameGeometry.nearest(ratio, to: RecordingFrameGeometry.pixels(ratio, shortSide: 720), in: available)
                let start = RecordingFrameGeometry.centered(size, screenFrame: display.frame, scale: display.scale)
                for corner in RecordingFrameGeometry.Corner.allCases {
                    for drag in [CGVector(dx: 37, dy: -11), CGVector(dx: -120, dy: 200), CGVector(dx: 4000, dy: 4000), CGVector(dx: -4000, dy: -4000), CGVector(dx: 0.4, dy: 0)] {
                        let corners: [RecordingFrameGeometry.Corner: CGPoint] = [
                            .bottomLeft: CGPoint(x: start.minX, y: start.minY), .bottomRight: CGPoint(x: start.maxX, y: start.minY),
                            .topLeft: CGPoint(x: start.minX, y: start.maxY), .topRight: CGPoint(x: start.maxX, y: start.maxY),
                        ]
                        let point = corners[corner]!.applying(CGAffineTransform(translationX: drag.dx, y: drag.dy))
                        let resized = RecordingFrameGeometry.resized(start, corner: corner, to: point, ratio: ratio, screenFrame: display.frame, scale: display.scale)
                        let pixels = RecordingFrameGeometry.pixels(of: resized, scale: display.scale)
                        exactShape(pixels, ratio)
                        XCTAssertTrue(display.frame.insetBy(dx: -0.01, dy: -0.01).contains(resized), "\(display.name) \(ratio.text) \(corner) \(drag): stays on the display")
                        XCTAssertGreaterThanOrEqual(min(pixels.width, pixels.height), 64, "never too small to see")
                        // The opposite corner stays put.
                        switch corner {
                        case .bottomLeft: XCTAssertEqual(resized.maxX, start.maxX, accuracy: 0.01); XCTAssertEqual(resized.maxY, start.maxY, accuracy: 0.01)
                        case .bottomRight: XCTAssertEqual(resized.minX, start.minX, accuracy: 0.01); XCTAssertEqual(resized.maxY, start.maxY, accuracy: 0.01)
                        case .topLeft: XCTAssertEqual(resized.maxX, start.maxX, accuracy: 0.01); XCTAssertEqual(resized.minY, start.minY, accuracy: 0.01)
                        case .topRight: XCTAssertEqual(resized.minX, start.minX, accuracy: 0.01); XCTAssertEqual(resized.minY, start.minY, accuracy: 0.01)
                        }
                    }
                }
            }
        }
        // A small drag outward grows it; inward shrinks it.
        let screen = displays[2].frame
        let start = RecordingFrameGeometry.centered(Pixels(width: 1280, height: 720), screenFrame: screen, scale: 1)
        let bigger = RecordingFrameGeometry.resized(start, corner: .topRight, to: CGPoint(x: start.maxX + 160, y: start.maxY + 90), ratio: .standard, screenFrame: screen, scale: 1)
        XCTAssertEqual(bigger.size, CGSize(width: 1440, height: 810))
        let smaller = RecordingFrameGeometry.resized(start, corner: .topRight, to: CGPoint(x: start.maxX - 320, y: start.maxY - 180), ratio: .standard, screenFrame: screen, scale: 1)
        XCTAssertEqual(smaller.size, CGSize(width: 960, height: 540))
    }

    func testSnapsToTheCenterAndEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 875)
        let size = Pixels(width: 1920, height: 1080)
        let centered = RecordingFrameGeometry.centered(size, screenFrame: screen, scale: 2)
        // A few points off center: snaps back to it.
        let near = RecordingFrameGeometry.rect(size, origin: CGPoint(x: centered.minX + 5, y: centered.minY - 6), screenFrame: screen, scale: 2)
        let snapped = RecordingFrameGeometry.snapped(near, screenFrame: screen, visibleFrame: visible, scale: 2)
        XCTAssertEqual(snapped.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(snapped.midY, screen.midY, accuracy: 0.5)
        XCTAssertEqual(RecordingFrameGeometry.pixels(of: snapped, scale: 2), size, "snapping never changes the size")
        // Near the left edge and the menu bar: onto them.
        let corner = RecordingFrameGeometry.rect(size, origin: CGPoint(x: 6, y: screen.maxY - 540 - 4), screenFrame: screen, scale: 2)
        let onEdges = RecordingFrameGeometry.snapped(corner, screenFrame: screen, visibleFrame: visible, scale: 2)
        XCTAssertEqual(onEdges.minX, 0)
        XCTAssertEqual(onEdges.maxY, screen.maxY)
        let underMenuBar = RecordingFrameGeometry.rect(size, origin: CGPoint(x: 300, y: visible.maxY - 540 + 3), screenFrame: screen, scale: 2)
        XCTAssertEqual(RecordingFrameGeometry.snapped(underMenuBar, screenFrame: screen, visibleFrame: visible, scale: 2).maxY, visible.maxY, "just under the menu bar")
        // Far from everything: left where it is.
        let free = RecordingFrameGeometry.rect(size, origin: CGPoint(x: 200, y: 150), screenFrame: screen, scale: 2)
        XCTAssertEqual(RecordingFrameGeometry.snapped(free, screenFrame: screen, visibleFrame: visible, scale: 2), free)
    }

    // MARK: Memory

    func testRemembersEachDisplaysFrame() throws {
        let entryA = RecordingFrameMemory.Entry(ratio: RecordingFrameRatio(9, 16), pixels: Pixels(width: 1080, height: 1920), offset: CGPoint(x: 40, y: 12))
        let entryB = RecordingFrameMemory.Entry(ratio: RecordingFrameRatio(21, 9), pixels: Pixels(width: 2520, height: 1080), offset: CGPoint(x: 0, y: 300))
        RecordingFrameMemory.save(entryA, display: "A")
        RecordingFrameMemory.save(entryB, display: "B")
        XCTAssertEqual(RecordingFrameMemory.load(display: "A"), entryA)
        XCTAssertEqual(RecordingFrameMemory.load(display: "B"), entryB)
        XCTAssertNil(RecordingFrameMemory.load(display: "C"))
        XCTAssertFalse(RecordingFrameMemory.key.hasPrefix("recording"), "not one of the recording bar's settings")

        // The controller: a new frame is 16:9 at 1080p (or the largest),
        // centered; a changed one comes back the same on that display.
        let screen = try XCTUnwrap(NSScreen.main)
        let first = RecordingFrameController(screen: screen)
        XCTAssertEqual(first.ratio, .standard)
        XCTAssertEqual(first.pixels, RecordingFrameGeometry.defaultPixels(.standard, in: first.available))
        XCTAssertEqual(first.rect.midX, screen.frame.midX, accuracy: 1)
        XCTAssertEqual(first.rect.midY, screen.frame.midY, accuracy: 1)
        XCTAssertNil(RecordingFrameMemory.load(display: RecordingFrameMemory.displayKey(screen)), "opening it stores nothing")
        first.setRatio(RecordingFrameRatio(1, 1))
        first.nudge(dx: -10, dy: 1)
        let remembered = first.rect

        let second = RecordingFrameController(screen: screen)
        XCTAssertEqual(second.ratio, RecordingFrameRatio(1, 1))
        XCTAssertEqual(second.rect, remembered)
        XCTAssertEqual(RecordingFrameMemory.displayKey(screen), RecordingFrameMemory.displayKey(screen), "a lasting name")
    }

    func testChangingTheRatioKeepsTheSizeAndCenter() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = RecordingFrameController(screen: screen)
        frame.setPixels(RecordingFrameGeometry.pixels(.standard, shortSide: 720))
        let center = CGPoint(x: frame.rect.midX, y: frame.rect.midY)
        var changes: [CGRect] = []
        frame.changeHandler = { rect, _ in changes.append(rect) }
        for preset in RecordingFrameRatio.presets {
            frame.setRatio(preset.ratio)
            exactShape(frame.pixels, preset.ratio)
            XCTAssertEqual(min(frame.pixels.width, frame.pixels.height), 720, "\(preset.label): the same short side")
            XCTAssertEqual(frame.rect.midX, center.x, accuracy: 1)
            XCTAssertTrue(screen.frame.contains(frame.rect))
        }
        XCTAssertEqual(changes.count, RecordingFrameRatio.presets.count, "the recording bar hears every change")
        XCTAssertEqual(changes.last, frame.rect)
        // Too big for the display in the new shape: the largest that fits.
        frame.setRatio(.standard)
        frame.setPixels(try XCTUnwrap(frame.sizeChoices.last).pixels)
        frame.setRatio(RecordingFrameRatio(9, 16))
        XCTAssertTrue(RecordingFrameGeometry.fits(frame.pixels, in: frame.available))
        XCTAssertEqual(frame.pixels, frame.sizeChoices.last?.pixels)
    }

    // MARK: On screen

    private func shownFrame() throws -> (RecordingFrameController, NSScreen) {
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = RecordingFrameController(screen: screen)
        controllers.append(frame)
        frame.setPixels(RecordingFrameGeometry.pixels(.standard, shortSide: 720))
        frame.show()
        RecordingUITestSupport.spinRunLoop(0.2)
        return (frame, screen)
    }

    func testOnlyTheBorderAndHandlesTakeTheMouse() throws {
        let (frame, _) = try shownFrame()
        XCTAssertEqual(frame.windows.count, 9, "the dimming, four border pieces and four corners")
        for window in frame.windows {
            XCTAssertEqual(window.sharingType, .none, "never in a recording or screenshot")
            XCTAssertTrue(window.isVisible)
        }
        let dim = try XCTUnwrap(frame.windows.first as? RecordingFrameDimWindow)
        XCTAssertTrue(dim.ignoresMouseEvents, "the dimming lets every click and scroll through")
        XCTAssertFalse(dim.canBecomeKey)
        XCTAssertEqual(dim.drawnFrame.offsetBy(dx: dim.frame.minX, dy: dim.frame.minY), frame.rect)
        let middle = frame.rect.insetBy(dx: RecordingFrameController.cornerSize, dy: RecordingFrameController.cornerSize)
        for handle in frame.windows.dropFirst() {
            XCTAssertFalse(handle.ignoresMouseEvents)
            XCTAssertFalse(handle.frame.intersects(middle), "\(handle.frame): nothing over the frame's middle")
            XCTAssertTrue(handle.frame.intersects(frame.rect.insetBy(dx: -1, dy: -1)) , "on the border")
            XCTAssertTrue(handle.canBecomeKey, "a click on the border lets Esc and the arrows work")
            XCTAssertTrue(handle.styleMask.contains(.nonactivatingPanel), "without taking over from the app being recorded")
        }
        // Moving or resizing the frame moves its handles along.
        frame.nudge(dx: 10, dy: 0)
        for handle in frame.windows.dropFirst() {
            guard let handle = handle as? RecordingFrameHandleWindow else { continue }
            XCTAssertEqual(handle.frame, RecordingFrameController.handleFrame(handle.role, around: frame.rect))
        }
    }

    /// The window server's own hit test: a click inside the frame or on the
    /// dimming reaches the window underneath; on the border, the frame.
    func testClicksPassThroughToTheAppUnderneath() throws {
        let (frame, screen) = try shownFrame()
        let under = NSWindow(contentRect: screen.frame.insetBy(dx: 40, dy: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        under.isReleasedWhenClosed = false
        under.backgroundColor = .systemGreen
        under.level = .normal
        windows.append(under)
        under.orderFrontRegardless()
        frame.windows.forEach { $0.orderFrontRegardless() }
        RecordingUITestSupport.spinRunLoop(0.3)

        func hit(_ point: CGPoint) -> Int { NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) }
        let inside = [CGPoint(x: frame.rect.midX, y: frame.rect.midY), CGPoint(x: frame.rect.minX + 30, y: frame.rect.maxY - 30)]
        for point in inside {
            XCTAssertEqual(hit(point), under.windowNumber, "a click inside the frame reaches the app")
        }
        let dimmed = CGPoint(x: frame.rect.minX - 40, y: frame.rect.midY)
        if under.frame.contains(dimmed) {
            XCTAssertEqual(hit(dimmed), under.windowNumber, "a click on the dimming reaches the app")
        }
        let handleNumbers = Set(frame.windows.dropFirst().map(\.windowNumber))
        XCTAssertTrue(handleNumbers.contains(hit(CGPoint(x: frame.rect.midX, y: frame.rect.maxY))), "the top border is the frame's")
        XCTAssertTrue(handleNumbers.contains(hit(CGPoint(x: frame.rect.maxX, y: frame.rect.minY))), "the corner is the frame's")
    }

    func testKeysMoveCancelAndRecord() throws {
        let (frame, _) = try shownFrame()
        var events: [String] = []
        frame.cancelHandler = { events.append("cancel") }
        frame.recordHandler = { events.append("record") }
        let start = frame.rect
        func key(_ code: UInt16, shift: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: code)!
        }
        XCTAssertTrue(frame.handleKey(key(124)))
        XCTAssertEqual(frame.rect.minX, start.minX + 1, accuracy: 0.01, "→ one point")
        XCTAssertTrue(frame.handleKey(key(126, shift: true)))
        XCTAssertEqual(frame.rect.minY, start.minY + 10, accuracy: 0.01, "⇧↑ ten points")
        XCTAssertTrue(frame.handleKey(key(123, shift: true)))
        XCTAssertTrue(frame.handleKey(key(125)))
        XCTAssertEqual(frame.rect.origin.x, start.origin.x - 9, accuracy: 0.01)
        XCTAssertEqual(frame.rect.origin.y, start.origin.y + 9, accuracy: 0.01)
        XCTAssertEqual(frame.rect.size, start.size, "nudging never resizes")
        XCTAssertTrue(frame.handleKey(key(36)))
        XCTAssertTrue(frame.handleKey(key(53)))
        XCTAssertEqual(events, ["record", "cancel"])
        XCTAssertFalse(frame.handleKey(key(0)), "other keys aren't the frame's")

        // A key on a focused border piece goes to the frame.
        let handle = try XCTUnwrap(frame.windows.last as? RecordingFrameHandleWindow)
        handle.keyDown(with: key(53))
        XCTAssertEqual(events, ["record", "cancel", "cancel"])

        // ⌃⌘Esc cancels from any app while the frame shows, and is free again after.
        frame.close()
        XCTAssertFalse(RecordingStopHotkey.isRegistered)
        XCTAssertTrue(frame.windows.isEmpty)
    }

    func testFitAWindowToTheFrame() {
        final class FakeWindow: RecordingResizableWindow {
            var frame: CGRect?
            var isResizable = true
            var minimum = CGSize.zero
            init(frame: CGRect) { self.frame = frame }
            func setFrame(_ frame: CGRect) {
                self.frame = CGRect(x: frame.minX, y: frame.minY, width: max(frame.width, minimum.width), height: max(frame.height, minimum.height))
            }
        }
        let target = CGRect(x: 276, y: 221, width: 960, height: 540)
        let window = FakeWindow(frame: CGRect(x: 10, y: 10, width: 300, height: 200))
        XCTAssertEqual(RecordingWindowSize.fit(window, to: target, scale: 2), .resized(.init(width: 1920, height: 1080)))
        XCTAssertEqual(window.frame, target, "exactly the frame's place and size")

        let stubborn = FakeWindow(frame: .zero)
        stubborn.minimum = CGSize(width: 1100, height: 600)
        let outcome = RecordingWindowSize.fit(stubborn, to: target, scale: 2)
        XCTAssertEqual(outcome, .limited(asked: .init(width: 1920, height: 1080), got: .init(width: 2200, height: 1200)))
        XCTAssertEqual(outcome.message(appName: "Notes"), "“Notes” keeps this window at least 2200 × 1200 pixels, so it can't be made 1920 × 1080.")
        XCTAssertEqual(stubborn.frame?.midX ?? 0, target.midX, accuracy: 0.5, "centered on the frame")

        let fixed = FakeWindow(frame: .zero)
        fixed.isResizable = false
        XCTAssertEqual(RecordingWindowSize.fit(fixed, to: target, scale: 2), .notResizable)
        XCTAssertEqual(fixed.frame, .zero, "left alone")
    }

    // MARK: The recording bar with a frame

    private func barWithFrame() throws -> (RecordingControlsWindow, NSScreen) {
        let screen = try XCTUnwrap(NSScreen.main)
        let rect = RecordingFrameGeometry.centered(RecordingFrameGeometry.pixels(.standard, shortSide: 720), screenFrame: screen.frame, scale: screen.backingScaleFactor)
        let bar = RecordingControlsWindow(rect: rect, screen: screen, target: .area, selectedWindow: nil, startHandler: { _, _, _ in }, closeHandler: {})
        bar.avoidsCaptureRect = true
        bar.reservedAbove = RecordingFrameStripWindow.height + RecordingFrameStripWindow.gap
        bars.append(bar)
        bar.show()
        bar.updateCaptureRect(rect, on: screen)
        return (bar, screen)
    }

    func testTheBarsNeverCoverTheFrame() throws {
        let (bar, screen) = try barWithFrame()
        let visible = screen.visibleFrame
        let sizes = [Pixels(width: 1280, height: 720), Pixels(width: 1080, height: 1080), Pixels(width: 720, height: 1280)]
        let scale = screen.backingScaleFactor
        for size in sizes {
            for spot in [CGPoint(x: visible.midX, y: visible.minY), CGPoint(x: visible.midX, y: visible.maxY), CGPoint(x: visible.minX, y: visible.midY), CGPoint(x: visible.midX, y: visible.midY)] {
                let points = CGSize(width: CGFloat(size.width) / scale, height: CGFloat(size.height) / scale)
                let rect = RecordingFrameGeometry.rect(size, origin: CGPoint(x: spot.x - points.width / 2, y: spot.y - points.height / 2), screenFrame: screen.frame, scale: scale)
                bar.updateCaptureRect(rect, on: screen)
                let block = bar.visibleBarFrame.union(bar.visibleBarFrame.offsetBy(dx: 0, dy: bar.reservedAbove))
                // When there's room above or below, the bar and strip use it.
                let room = rect.minY - visible.minY >= block.height + 22 || visible.maxY - rect.maxY >= block.height + 22
                if room {
                    XCTAssertFalse(block.intersects(rect), "\(size) at \(spot): the bars keep clear of the frame")
                }
                XCTAssertTrue(visible.insetBy(dx: -1, dy: -1).contains(block), "\(size) at \(spot): the bars stay on the screen")
            }
        }
        // The size shown follows the frame.
        let labels = RecordingUITestSupport.allSubviews(of: try XCTUnwrap(bar.contentView)).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains { $0.contains("720 × 1280") }, "\(labels)")
    }

    func testABarDraggedByHandStaysPutUnlessTheFrameComesUnderIt() throws {
        let (bar, screen) = try barWithFrame()
        RecordingUITestSupport.spinRunLoop(0.1)
        XCTAssertFalse(bar.movedByUser)
        let visible = screen.visibleFrame
        // The user drags it to the top-left corner.
        bar.setFrameOrigin(NSPoint(x: visible.minX + 20, y: visible.maxY - bar.frame.height - bar.reservedAbove - 20))
        RecordingUITestSupport.spinRunLoop(0.1)
        XCTAssertTrue(bar.movedByUser)
        let dragged = bar.frame.origin
        // The frame moves elsewhere: the bar stays where it was put.
        let scale = screen.backingScaleFactor
        let size = Pixels(width: 640, height: 360)
        let low = RecordingFrameGeometry.rect(size, origin: CGPoint(x: visible.maxX - 400, y: visible.minY + 20), screenFrame: screen.frame, scale: scale)
        bar.updateCaptureRect(low, on: screen)
        XCTAssertEqual(bar.frame.origin, dragged)
        // The frame comes under it: it moves out of the way.
        let underBar = RecordingFrameGeometry.rect(size, origin: CGPoint(x: bar.visibleBarFrame.minX, y: bar.visibleBarFrame.minY - 40), screenFrame: screen.frame, scale: scale)
        bar.updateCaptureRect(underBar, on: screen)
        let block = bar.visibleBarFrame.union(bar.visibleBarFrame.offsetBy(dx: 0, dy: bar.reservedAbove))
        XCTAssertFalse(block.intersects(underBar))
    }

    func testStripControlsChangeTheFrame() throws {
        let (frame, _) = try shownFrame()
        let model = RecordingFrameStripModel(ratio: frame.ratio, pixels: frame.pixels, sizeChoices: frame.sizeChoices)
        model.chooseRatio = { frame.setRatio($0) }
        model.chooseSize = { frame.setPixels($0) }
        let strip = RecordingFrameStripWindow(model: model, width: 900)
        windows.append(strip)
        XCTAssertEqual(strip.sharingType, .none)
        XCTAssertTrue(strip.canBecomeKey)
        model.chooseRatio(RecordingFrameRatio(4, 5))
        XCTAssertEqual(frame.ratio, RecordingFrameRatio(4, 5))
        XCTAssertEqual(frame.pixels, Pixels(width: 720, height: 900))
        model.chooseSize(Pixels(width: 1080, height: 1350))
        XCTAssertEqual(frame.pixels, Pixels(width: 1080, height: 1350))
        strip.setFrameOrigin(RecordingUITestSupport.offscreen)
        strip.orderFrontRegardless()
        RecordingUITestSupport.spinRunLoop(0.2)
        try RecordingUITestSupport.writeSnapshot(of: strip, name: "frame-strip")
        var keys = 0
        strip.keyHandler = { _ in keys += 1; return true }
        strip.keyDown(with: try XCTUnwrap(RecordingUITestSupport.keyDown("\u{1b}", keyCode: 53, in: strip)))
        XCTAssertEqual(keys, 1, "Esc and the arrows work after clicking the strip")
    }

    // MARK: Split screen (1.10.0)

    /// With Layout ▸ Split screen, the frame is the whole video and what's
    /// recorded is the screen's part: 8:9 for a 16:9 video split 50/50.
    func testSplitScreenRecordsTheScreensPartOfTheFrame() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = RecordingFrameController(screen: screen)
        controllers.append(frame)
        frame.setPixels(RecordingFrameGeometry.pixels(.standard, shortSide: 720))
        XCTAssertEqual(frame.recordedRect, frame.rect, "not split: the frame is what's recorded")
        XCTAssertNil(frame.cameraPartRect)

        var recorded: [CGRect] = []
        frame.changeHandler = { rect, _ in recorded.append(rect) }
        frame.split = VideoWebcamSettings.Split()
        XCTAssertEqual(recorded.last, frame.recordedRect, "the bar is told what's recorded")
        XCTAssertEqual(frame.recordedPixels, Pixels(width: 640, height: 720), "8:9: half of 1280 × 720")
        XCTAssertEqual(frame.recordedRect.minX, frame.rect.minX, accuracy: 0.01, "the screen on the left")
        let camera = try XCTUnwrap(frame.cameraPartRect)
        XCTAssertEqual(camera.minX, frame.recordedRect.maxX, accuracy: 0.51)
        XCTAssertEqual(camera.maxX, frame.rect.maxX, accuracy: 0.51)
        XCTAssertTrue(frame.label.contains("Screen part of a 16:9 split video"), frame.label)
        XCTAssertTrue(frame.label.hasPrefix("640 × 720"), frame.label)

        // Each ratio, side and size: even pixels inside the frame.
        for preset in RecordingFrameRatio.presets {
            frame.setRatio(preset.ratio)
            for split in [VideoWebcamSettings.Split(), VideoWebcamSettings.Split(cameraSide: .first, cameraShare: 0.3), VideoWebcamSettings.Split(cameraShare: 0.7, gap: 0.02)] {
                frame.split = split
                let pixels = frame.recordedPixels
                XCTAssertEqual(pixels.width % 2, 0, "\(preset.label)")
                XCTAssertEqual(pixels.height % 2, 0, "\(preset.label)")
                XCTAssertTrue(frame.rect.insetBy(dx: -0.01, dy: -0.01).contains(frame.recordedRect), "\(preset.label)")
                let expected = VideoSplitLayout.screenPixels(split, video: CGSize(width: frame.pixels.width, height: frame.pixels.height))
                XCTAssertEqual(pixels, Pixels(width: Int(expected.width), height: Int(expected.height)), "\(preset.label)")
                let sideBySide = preset.ratio.width > preset.ratio.height
                if sideBySide {
                    XCTAssertEqual(pixels.height, frame.pixels.height, "\(preset.label): full height, part of the width")
                } else {
                    XCTAssertEqual(pixels.width, frame.pixels.width, "\(preset.label): full width, part of the height")
                }
            }
        }
        frame.split = nil
        XCTAssertEqual(frame.recordedRect, frame.rect, "back to the whole frame")
    }
}
