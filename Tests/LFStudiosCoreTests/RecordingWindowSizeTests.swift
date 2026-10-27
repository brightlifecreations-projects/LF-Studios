import AppKit
import XCTest
@testable import LFStudiosCore

/// Window mode's "Window size": pixels to points, fitting on the display,
/// centering, apps that keep a minimum size or can't be resized, and
/// Restore size.
@MainActor
final class RecordingWindowSizeTests: XCTestCase {
    /// A window like another app's: it may keep a minimum or maximum size,
    /// or refuse to be resized.
    private final class FakeWindow: RecordingResizableWindow {
        var frame: CGRect?
        var isResizable = true
        var minimum = CGSize.zero
        var maximum = CGSize(width: 100_000, height: 100_000)
        private(set) var moves = 0

        init(frame: CGRect) { self.frame = frame }

        func setFrame(_ frame: CGRect) {
            moves += 1
            let width = min(max(frame.width, minimum.width), maximum.width)
            let height = min(max(frame.height, minimum.height), maximum.height)
            self.frame = CGRect(x: frame.minX, y: frame.minY, width: width, height: height)
        }
    }

    private let visible = CGRect(x: 0, y: 40, width: 1512, height: 920)

    func testPresetsAndPoints() {
        XCTAssertEqual(RecordingWindowSize.presets.map { "\($0.width)×\($0.height)" }, ["1280×720", "1920×1080", "1440×900", "1080×1080", "1080×1920"])
        XCTAssertEqual(RecordingWindowSize.points(width: 1920, height: 1080, scale: 2), CGSize(width: 960, height: 540), "Retina: half the pixels")
        XCTAssertEqual(RecordingWindowSize.points(width: 1920, height: 1080, scale: 1), CGSize(width: 1920, height: 1080))
    }

    func testWhatFitsAndTheLargestThatDoes() {
        XCTAssertTrue(RecordingWindowSize.fits(width: 1920, height: 1080, scale: 2, in: visible))
        XCTAssertFalse(RecordingWindowSize.fits(width: 1080, height: 1920, scale: 2, in: visible), "960 points tall on a 920-point screen")
        let fitting = RecordingWindowSize.largestFitting(width: 1080, height: 1920, scale: 2, in: visible)
        XCTAssertTrue(RecordingWindowSize.fits(width: fitting.width, height: fitting.height, scale: 2, in: visible))
        XCTAssertEqual(Double(fitting.width) / Double(fitting.height), 1080.0 / 1920, accuracy: 0.01, "the same shape")
        XCTAssertEqual(fitting.height, 1840)
        XCTAssertTrue(fitting.width.isMultiple(of: 2) && fitting.height.isMultiple(of: 2), "even pixels, as video wants")
        // Already fits: unchanged.
        XCTAssertEqual(RecordingWindowSize.largestFitting(width: 1280, height: 720, scale: 2, in: visible), .init(width: 1280, height: 720))
    }

    func testResizesAndCenters() {
        let window = FakeWindow(frame: CGRect(x: 100, y: 100, width: 700, height: 500))
        let outcome = RecordingWindowSize.resize(window, toPixels: .init(width: 1920, height: 1080), scale: 2, in: visible)
        XCTAssertEqual(outcome, .resized(.init(width: 1920, height: 1080)))
        XCTAssertNil(outcome.message(appName: "Notes"))
        let frame = try? XCTUnwrap(window.frame)
        XCTAssertEqual(frame?.size, CGSize(width: 960, height: 540))
        XCTAssertEqual(frame?.midX ?? 0, visible.midX, accuracy: 1)
        XCTAssertEqual(frame?.midY ?? 0, visible.midY, accuracy: 1)
    }

    func testAppsWithAMinimumSizeOrNoResizing() {
        let window = FakeWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 800))
        window.minimum = CGSize(width: 1024, height: 700)
        let outcome = RecordingWindowSize.resize(window, toPixels: .init(width: 1280, height: 720), scale: 2, in: visible)
        XCTAssertEqual(outcome, .limited(asked: .init(width: 1280, height: 720), got: .init(width: 2048, height: 1400)))
        let message = outcome.message(appName: "Safari") ?? ""
        XCTAssertTrue(message.contains("Safari") && message.contains("2048 × 1400"), message)
        XCTAssertEqual(window.frame?.midX ?? 0, visible.midX, accuracy: 1, "centered at the size it kept")

        let capped = FakeWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        capped.maximum = CGSize(width: 400, height: 400)
        let small = RecordingWindowSize.resize(capped, toPixels: .init(width: 1080, height: 1080), scale: 2, in: visible)
        XCTAssertEqual(small, .limited(asked: .init(width: 1080, height: 1080), got: .init(width: 800, height: 800)))
        XCTAssertTrue(small.message(appName: "Tool")?.contains("at most") ?? false)

        let fixed = FakeWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        fixed.isResizable = false
        XCTAssertEqual(RecordingWindowSize.resize(fixed, toPixels: .init(width: 1280, height: 720), scale: 2, in: visible), .notResizable)
        XCTAssertEqual(fixed.moves, 0, "left alone")
        XCTAssertNotNil(RecordingWindowSize.Outcome.notResizable.message(appName: "Calculator"))
    }

    func testRestoreSizeRemembersTheFirstFrame() {
        let id: CGWindowID = 987_654
        RecordingWindowSizeMemory.forget(id)
        XCTAssertNil(RecordingWindowSizeMemory.previous(for: id))
        let original = CGRect(x: 10, y: 20, width: 800, height: 600)
        RecordingWindowSizeMemory.remember(original, for: id)
        RecordingWindowSizeMemory.remember(CGRect(x: 0, y: 0, width: 960, height: 540), for: id)
        XCTAssertEqual(RecordingWindowSizeMemory.previous(for: id), original, "two resizes later, Restore goes back to the start")
        let window = FakeWindow(frame: CGRect(x: 0, y: 0, width: 960, height: 540))
        window.setFrame(original)
        XCTAssertEqual(window.frame, original)
        RecordingWindowSizeMemory.forget(id)
        XCTAssertNil(RecordingWindowSizeMemory.previous(for: id))
    }
}
