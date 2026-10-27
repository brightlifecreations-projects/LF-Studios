import XCTest
@testable import LFStudiosCore

/// "Track where I type" and "Record when keys are pressed": off until
/// switched on, they save positions and moments only — never text, never
/// which keys — and nothing at all while a password field has focus.
@MainActor
final class RecordingTypingPrivacyTests: XCTestCase {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/LFStudiosCore")

    /// A tracker on a plain clock (host seconds = video seconds) and a 1000×500
    /// capture area at the origin.
    private func tracker(typing: Bool = true, keys: Bool = true, secureInput: @escaping () -> Bool = { false }) -> RecordingTypingTracker {
        RecordingTypingTracker(
            tracksTyping: typing,
            recordsKeyTiming: keys,
            probe: NoProbe(),
            secureInput: secureInput,
            time: { $0 },
            map: { box in CGRect(x: box.minX / 1000, y: 1 - box.maxY / 500, width: box.width / 1000, height: box.height / 500) }
        )
    }

    private struct NoProbe: RecordingFocusProbing {
        func read() -> RecordingFocusReading { .none }
    }

    private func caret(_ x: CGFloat) -> RecordingFocusReading {
        .caret(CGRect(x: x, y: 240, width: 2, height: 18))
    }

    // MARK: Off by default

    func testBothOptionsAreOffByDefault() {
        let suite = "LFStudiosCoreTests.Typing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        Settings.defaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            Settings.defaults = .standard
        }
        XCTAssertFalse(Settings.recordingTracksTyping)
        XCTAssertFalse(Settings.recordingKeyTiming)
    }

    func testARecordingWithBothOffSavesNoTypingData() {
        let recorder = VideoDemoRecordingMetadataRecorder(
            videoURL: URL(fileURLWithPath: "/tmp/typing-off.mp4"),
            captureRect: CGRect(x: 0, y: 0, width: 1000, height: 500),
            sourcePixelSize: CGSize(width: 2000, height: 1000),
            fps: 30,
            nativeCursorVisible: false,
            renderCursor: true
        )
        recorder.start()
        let metadata = recorder.finish(duration: 1)
        XCTAssertNil(metadata.textCursor)
        XCTAssertNil(metadata.keyPresses)
        let json = String(data: try! JSONEncoder().encode(metadata), encoding: .utf8)!
        XCTAssertFalse(json.contains("textCursor"))
        XCTAssertFalse(json.contains("keyPresses"))
    }

    // MARK: Nothing typed is stored

    func testTheSavedDataHasNoPlaceForTextOrKeys() throws {
        // A text cursor sample is a time and a box: five numbers.
        let sample = VideoTextCursorSample(time: 1, x: 0.1, y: 0.2, width: 0.01, height: 0.03)
        let labels = Mirror(reflecting: sample).children.compactMap(\.label)
        XCTAssertEqual(labels, ["time", "x", "y", "width", "height"])
        XCTAssertTrue(Mirror(reflecting: sample).children.allSatisfy { $0.value is Double })

        // Key timing is a list of numbers.
        var metadata = VideoDemoRecordingMetadata(videoURLPath: "/tmp/a.mp4", createdAt: Date(timeIntervalSince1970: 0), duration: 5, sourceWidth: 100, sourceHeight: 100, fps: 30, nativeCursorVisible: false, cursorSamples: [], clickEvents: [])
        metadata.textCursor = [sample]
        metadata.keyPresses = [1.0, 1.2, 1.4]
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as! [String: Any]
        let saved = try XCTUnwrap(object["textCursor"] as? [[String: Any]])
        XCTAssertEqual(Set(saved[0].keys), ["time", "x", "y", "width", "height"])
        XCTAssertTrue(saved[0].values.allSatisfy { $0 is NSNumber })
        XCTAssertTrue((object["keyPresses"] as? [Any])?.allSatisfy { $0 is NSNumber } ?? false)

        // The project carries the same, and nothing more.
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 5)
        project.apply(metadata: metadata)
        XCTAssertEqual(project.textCursor, [sample])
        XCTAssertEqual(project.keyPresses, [1.0, 1.2, 1.4])
    }

    /// The tracker never asks for a field's text, nor a key event's key.
    func testTheTrackerNeverReadsTextOrKeys() throws {
        let code = try String(contentsOf: Self.sources.appendingPathComponent("Capture/RecordingTypingTracker.swift"))
        let lines = code.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }.joined(separator: "\n")
        for forbidden in ["kAXValueAttribute", "kAXSelectedTextAttribute", "kAXStringForRange", "AXStringForRange", "kAXAttributedStringForRange",
                          ".characters", "charactersIgnoringModifiers", ".keyCode", "VideoKeystrokeFormatter.keys"] {
            XCTAssertFalse(lines.contains(forbidden), "RecordingTypingTracker must not use \(forbidden)")
        }
    }

    func testPositionsAndMomentsAreAllThatIsKept() {
        let tracker = tracker()
        tracker.handle(caret(100), at: 1)
        tracker.keyDown(at: 1.1)
        tracker.handle(caret(110), at: 1.25)
        // A still text cursor adds nothing.
        tracker.handle(caret(110), at: 1.375)
        tracker.keyDown(at: 1.3)
        let result = tracker.finish(duration: 10)
        XCTAssertEqual(result.samples.map(\.time), [1, 1.25])
        XCTAssertEqual(result.samples[0].x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result.samples[0].y, 1 - 258.0 / 500, accuracy: 0.0001)
        XCTAssertEqual(result.keyPresses, [1.1, 1.3])
    }

    func testEachOptionRecordsOnlyItsOwnData() {
        let positions = tracker(typing: true, keys: false)
        positions.handle(caret(100), at: 1)
        positions.keyDown(at: 1.1)
        XCTAssertEqual(positions.finish(duration: 5).keyPresses, [])

        let timing = tracker(typing: false, keys: true)
        timing.handle(caret(100), at: 1)
        timing.keyDown(at: 1.1)
        let result = timing.finish(duration: 5)
        XCTAssertEqual(result.samples, [])
        XCTAssertEqual(result.keyPresses, [1.1])
    }

    // MARK: Password fields

    func testPasswordFieldsAreRecognized() {
        XCTAssertTrue(RecordingAccessibilityFocusProbe.isSecure(role: "AXTextField", subrole: "AXSecureTextField"))
        XCTAssertTrue(RecordingAccessibilityFocusProbe.isSecure(role: "AXSecureTextField", subrole: nil))
        XCTAssertFalse(RecordingAccessibilityFocusProbe.isSecure(role: "AXTextField", subrole: nil))
        XCTAssertFalse(RecordingAccessibilityFocusProbe.isSecure(role: "AXTextArea", subrole: "AXSearchField"))
    }

    func testNothingIsRecordedWhileAPasswordFieldHasFocus() {
        let tracker = tracker()
        // Typing a user name…
        tracker.handle(caret(100), at: 1.0)
        tracker.keyDown(at: 1.05)
        tracker.handle(caret(108), at: 1.125)
        // …Tab to the password: a key or two land before the next reading.
        tracker.keyDown(at: 1.2)
        tracker.handle(.secure, at: 1.25)
        XCTAssertTrue(tracker.isSecure)
        for step in 0..<12 {
            let t = 1.3 + Double(step) * 0.1
            tracker.keyDown(at: t)
            tracker.handle(.secure, at: t + 0.05)
        }
        // Focus leaves the field: recording picks up again.
        tracker.handle(caret(300), at: 2.5)
        XCTAssertFalse(tracker.isSecure)
        tracker.keyDown(at: 2.55)
        tracker.handle(caret(308), at: 2.625)
        let result = tracker.finish(duration: 10)

        XCTAssertEqual(result.samples.map(\.time), [1.0, 1.125, 2.5, 2.625])
        XCTAssertEqual(result.keyPresses, [1.05, 2.55], "the press after the last safe reading (1.2) is dropped too")
        XCTAssertFalse(result.samples.contains { $0.time > 1.125 && $0.time < 2.5 })
        XCTAssertFalse(result.keyPresses.contains { $0 > 1.125 && $0 < 2.5 })
    }

    func testSecureKeyboardEntryStopsBothFeatures() {
        var secure = false
        let tracker = tracker(secureInput: { secure })
        tracker.handle(caret(100), at: 1)
        tracker.keyDown(at: 1.05)
        // Another app turned on secure keyboard entry (a password prompt
        // whose field Accessibility can't see).
        secure = true
        tracker.keyDown(at: 1.1)
        tracker.handle(caret(110), at: 1.125)
        tracker.keyDown(at: 1.2)
        secure = false
        tracker.handle(caret(140), at: 2)
        tracker.keyDown(at: 2.05)
        let result = tracker.finish(duration: 10)
        XCTAssertEqual(result.samples.map(\.time), [1, 2])
        // 1.05 came after the last reading known to be safe: dropped too.
        XCTAssertEqual(result.keyPresses, [2.05])
    }

    func testAPasswordFieldFirstThingDropsEverythingBeforeIt() {
        let tracker = tracker()
        tracker.keyDown(at: 0.1)
        tracker.handle(.secure, at: 0.125)
        tracker.keyDown(at: 0.2)
        let result = tracker.finish(duration: 5)
        XCTAssertEqual(result.keyPresses, [])
        XCTAssertEqual(result.samples, [])
    }

    func testFirstFrameShiftAndStopShortcut() {
        let tracker = tracker()
        tracker.handle(caret(100), at: 0.2)
        tracker.handle(caret(110), at: 1.0)
        tracker.keyDown(at: 0.25)
        tracker.keyDown(at: 1.1)
        tracker.keyDown(at: 3.98)
        tracker.shift(by: 0.5)
        let result = tracker.finish(duration: 3.5)
        XCTAssertEqual(result.samples.map(\.time), [0.5])
        XCTAssertEqual(result.keyPresses.map { ($0 * 1000).rounded() / 1000 }, [0.6], "before the first frame and the stop shortcut are gone")
    }
}
