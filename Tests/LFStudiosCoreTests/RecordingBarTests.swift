import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// The recording bar before Record: usable from the keyboard and VoiceOver,
/// Return records, and pressing Record changes no settings.
@MainActor
final class RecordingBarTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suiteName = "LFStudiosCoreTests.RecordingBar.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        Settings.defaults = defaults
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        super.tearDown()
    }

    private func makeBar(target: RecordingTargetKind = .area, onRecord: @escaping () -> Void = {}) throws -> RecordingControlsWindow {
        let screen = try XCTUnwrap(NSScreen.main)
        let rect = CGRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100, width: 800, height: 450)
        let bar = RecordingControlsWindow(rect: rect, screen: screen, target: target, selectedWindow: nil, startHandler: { _, _, _ in onRecord() }, closeHandler: {})
        bar.setFrameOrigin(RecordingUITestSupport.offscreen)
        bar.orderFrontRegardless()
        return bar
    }

    private func toggles(in bar: NSWindow) throws -> [NSButton] {
        let root = try XCTUnwrap(bar.contentView)
        return RecordingUITestSupport.allSubviews(of: root)
            .compactMap { $0 as? NSButton }
            .filter { $0.accessibilityRole() == .checkBox }
    }

    func testTogglesWorkFromKeyboardVoiceOverAndMouse() throws {
        let bar = try makeBar()
        defer { bar.closeControls() }
        let all = try toggles(in: bar)
        XCTAssertEqual(Set(all.compactMap { $0.accessibilityLabel() }), ["System audio", "Microphone", "Cursor", "Camera", "Show keyboard shortcuts", "Speaker notes"])
        let systemAudio = try XCTUnwrap(all.first { $0.accessibilityLabel() == "System audio" })
        XCTAssertEqual(systemAudio.accessibilityValue() as? NSNumber, 0)

        // Space with keyboard focus goes through performClick.
        systemAudio.performClick(nil)
        XCTAssertEqual(systemAudio.accessibilityValue() as? NSNumber, 1)
        XCTAssertTrue(Settings.recordingSystemAudio)

        // VoiceOver presses the button.
        XCTAssertTrue(systemAudio.accessibilityPerformPress())
        XCTAssertEqual(systemAudio.accessibilityValue() as? NSNumber, 0)
        XCTAssertFalse(Settings.recordingSystemAudio)

        // A mouse click toggles exactly once.
        RecordingUITestSupport.click(systemAudio, in: bar)
        XCTAssertTrue(Settings.recordingSystemAudio)
        XCTAssertEqual(systemAudio.accessibilityValue() as? NSNumber, 1)
    }

    func testReturnRecordsAndRecordingStoresNothing() throws {
        var recorded = 0
        let bar = try makeBar { recorded += 1 }
        let before = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("recording") }
        let returnKey = try XCTUnwrap(RecordingUITestSupport.keyDown("\r", keyCode: 36, in: bar))
        XCTAssertTrue(bar.performKeyEquivalent(with: returnKey))
        XCTAssertEqual(recorded, 1)
        // Saving the menus' values on Record is what kept most people on the
        // old 30 fps default.
        let after = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("recording") }
        XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after))
        XCTAssertNil(defaults.object(forKey: "recordingFPS"))
        XCTAssertNil(defaults.object(forKey: "recordingQuality"))
    }

    func testChosenKeycapSettingSurvivesRecord() throws {
        // Asked for shortcuts; whether or not access has arrived yet, Record keeps the choice.
        Settings.recordingKeystrokes = true
        let bar = try makeBar()
        let record = try XCTUnwrap(RecordingUITestSupport.button(labelled: "Record", in: bar))
        record.performClick(nil)
        XCTAssertTrue(Settings.recordingKeystrokes)
    }

    func testSizesAreInPixelsWithAnEstimate() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let bar = try makeBar()
        defer { bar.closeControls() }
        let labels = RecordingUITestSupport.allSubviews(of: try XCTUnwrap(bar.contentView)).compactMap { ($0 as? NSTextField)?.stringValue }
        let scale = screen.backingScaleFactor
        let pixels = "\(Int(800 * scale)) × \(Int(450 * scale))"
        XCTAssertTrue(labels.contains { $0 == "Area · \(pixels)" }, "\(labels)")
        XCTAssertTrue(labels.contains { $0.hasPrefix("up to ") && $0.hasSuffix("MB/min") }, "\(labels)")
    }

    // MARK: One row, the rest in the Area popover (1.21.0)

    private func controls(in view: NSView) -> [String] {
        RecordingUITestSupport.allSubviews(of: view).compactMap { ($0 as? NSControl)?.accessibilityLabel() }
    }

    /// Before Record, the bar is one row: the frame's shape and size, the
    /// other ways to record, Window size, the microphone menu and the
    /// camera's shape, size and layout all open from the Area button.
    func testTheBarIsOneRowWithEverythingInTheAreaPopover() throws {
        Settings.recordingMicrophone = true
        Settings.recordingCamera = true
        let bar = try makeBar(target: .window)
        defer { bar.closeControls() }
        let screen = try XCTUnwrap(NSScreen.main)
        bar.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - bar.frame.width / 2, y: screen.visibleFrame.minY + 40))
        bar.frameStripModel = RecordingFrameStripModel(ratio: .standard, pixels: .init(width: 1920, height: 1080), sizeChoices: [])
        XCTAssertEqual(bar.visibleBarFrame.height, 56, "one row, with the microphone and the camera on")
        let onBar = controls(in: try XCTUnwrap(bar.contentView))
        for label in ["Camera shape", "Layout", "Window size"] {
            XCTAssertFalse(onBar.contains(label), "\(label) isn't on the bar: \(onBar)")
        }
        XCTAssertEqual(onBar.filter { $0 == "Microphone" }.count, 1, "only the microphone switch: \(onBar)")
        XCTAssertFalse(bar.areaPopover.isShown)

        bar.showAreaPopover()
        XCTAssertTrue(bar.areaPopover.isShown)
        XCTAssertEqual(bar.areaPopoverSections, ["frame", "windowSize", "microphone", "camera"])
        let content = try XCTUnwrap(bar.areaPopover.contentViewController?.view)
        let inPopover = controls(in: content)
        for label in ["Microphone", "Camera shape", "Layout", "Window size"] {
            XCTAssertTrue(inPopover.contains(label), "\(label) is in the popover: \(inPopover)")
        }
        XCTAssertTrue(RecordingUITestSupport.allSubviews(of: content).contains { $0 is NSHostingView<RecordingFrameStripView> }, "the frame's shapes, size and other ways to record")
        RecordingUITestSupport.spinRunLoop(0.5)
        try RecordingUITestSupport.writeSnapshot(of: try XCTUnwrap(content.window), name: "area-popover")

        // Esc closes the popover, not the bar.
        let esc = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: bar.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(esc)
        RecordingUITestSupport.spinRunLoop(0.1)
        XCTAssertFalse(bar.areaPopover.isShown, "Esc closes the popover")
        XCTAssertTrue(bar.isVisible, "and only the popover")
    }

    /// The bar says what's being recorded.
    func testTheAreaButtonShowsTheChoice() throws {
        let full = try makeBar(target: .fullscreen)
        defer { full.closeControls() }
        let fullLabels = RecordingUITestSupport.allSubviews(of: try XCTUnwrap(full.contentView)).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(fullLabels.contains("Full screen"), "\(fullLabels)")
        XCTAssertEqual(try XCTUnwrap(RecordingUITestSupport.button(labelled: "Full screen", in: full)).toolTip?.contains("Click for the area"), true)
    }

    func testOptionsAreReachable() throws {
        let bar = try makeBar()
        defer { bar.closeControls() }
        let options = try XCTUnwrap(RecordingUITestSupport.button(labelled: "More recording options", in: bar))
        XCTAssertFalse(options.isHidden)
        XCTAssertEqual(try XCTUnwrap(RecordingUITestSupport.button(labelled: "Record", in: bar)).keyEquivalent, "\r")
    }

    func testRendersTheBar() throws {
        Settings.recordingMicrophone = true
        Settings.recordingSystemAudio = true
        let bar = try makeBar()
        defer { bar.closeControls() }
        try RecordingUITestSupport.writeSnapshot(of: bar, name: "recording-bar")
    }

    func testRendersTheRecordingSettings() throws {
        Settings.recordingCountdownSeconds = 3
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 1100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
        // The Preferences window draws a dark stage behind the panes.
        let stage = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 1100))
        stage.wantsLayer = true
        stage.layer?.backgroundColor = LFStudiosColors.editorStageTop.cgColor
        let hosting = NSHostingView(rootView: RecordingSettingsView())
        hosting.frame = stage.bounds
        stage.addSubview(hosting)
        window.contentView = stage
        window.setFrameOrigin(RecordingUITestSupport.offscreen)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RecordingUITestSupport.spinRunLoop(0.2)
        try RecordingUITestSupport.writeSnapshot(of: window, name: "recording-settings")
    }

    /// The countdown before a recording can be called off (Esc, a click, or
    /// the Stop Recording shortcut, which cancels setup).
    func testRecordingCountdownCanBeCancelled() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        var outcome: Bool?
        let countdown = CountdownWindow(seconds: 3, on: screen) { finished in outcome = finished }
        countdown.start()
        countdown.cancel()
        RecordingUITestSupport.spinRunLoop(0.2)
        XCTAssertEqual(outcome, false)
        XCTAssertFalse(countdown.isVisible)
        countdown.cancel()
        RecordingUITestSupport.spinRunLoop(0.1)
        XCTAssertEqual(outcome, false, "reported once")
    }

    // MARK: Post-recording panel

    func testPostRecordingPanelClosesWithoutATimeout() throws {
        Settings.overlayTimeout = -1 // "Never"
        let url = URL(fileURLWithPath: "/tmp/LF Studios Demo.mp4")
        let screen = try XCTUnwrap(NSScreen.screens.last)
        VideoDemoPostRecordingPanel.show(videoURL: url, on: screen, openHandler: {})
        let panel = try XCTUnwrap(VideoDemoPostRecordingPanel.visiblePanel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(screen.visibleFrame.contains(panel.frame), "on the screen the recording was made on")
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        try RecordingUITestSupport.writeSnapshot(of: panel, name: "post-recording-panel")

        let close = try XCTUnwrap(RecordingUITestSupport.button(labelled: "Close", in: panel))
        RecordingUITestSupport.click(close, in: panel)
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(VideoDemoPostRecordingPanel.visiblePanel)

        // Esc, once it has been clicked (key).
        VideoDemoPostRecordingPanel.show(videoURL: url, on: screen, openHandler: {})
        let again = try XCTUnwrap(VideoDemoPostRecordingPanel.visiblePanel)
        again.cancelOperation(nil)
        XCTAssertFalse(again.isVisible)
        XCTAssertNil(VideoDemoPostRecordingPanel.visiblePanel)
    }

    func testEditVideoOpensAndCloses() throws {
        var opened = 0
        VideoDemoPostRecordingPanel.show(videoURL: URL(fileURLWithPath: "/tmp/x.mp4"), on: NSScreen.main, openHandler: { opened += 1 })
        let panel = try XCTUnwrap(VideoDemoPostRecordingPanel.visiblePanel)
        let edit = try XCTUnwrap(RecordingUITestSupport.allSubviews(of: try XCTUnwrap(panel.contentView)).compactMap { $0 as? NSButton }.first { $0.title == "Edit Video" })
        edit.performClick(nil)
        XCTAssertEqual(opened, 1)
        XCTAssertFalse(panel.isVisible)
    }
}
