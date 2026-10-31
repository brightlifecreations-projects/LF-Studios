import AppKit
import AVFoundation
import CoreImage
import IOKit.pwr_mgt
import ScreenCaptureKit
import XCTest
@testable import LFStudiosCore

/// Real recordings through the engine and ScreenCaptureKit: needs Screen
/// Recording permission for the test runner, skipped otherwise.
@MainActor
final class RecordingEngineIntegrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var folder: URL!
    private var engine: RecordingEngine?
    private var displayAssertion: IOPMAssertionID = 0

    override func setUp() async throws {
        try await super.setUp()
        guard CGPreflightScreenCaptureAccess() else { throw XCTSkip("needs Screen Recording permission") }
        // Displays that doze off mid-test stall ScreenCaptureKit.
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "LF Studios recording tests" as CFString, &displayAssertion)
        guard await Self.wakeDisplays() else { throw XCTSkip("no display to record (asleep or headless)") }
        _ = NSApplication.shared
        VideoTestStorage.isolate()
        suiteName = "LFStudiosCoreTests.RecordingEngine.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        Settings.defaults = defaults
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("recordings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertTrue(Settings.setAutoSaveLocation(folder.path))
        // Nothing that would ask for another permission or open windows.
        Settings.recordingMicrophone = false
        Settings.recordingSystemAudio = false
        Settings.recordingCamera = false
        Settings.recordingKeystrokes = false
        Settings.openVideoEditorAfterRecording = false
        Settings.recordingFPS = 30
    }

    override func tearDown() async throws {
        if let engine, engine.active {
            engine.discardRecording()
            try? await waitUntil(timeout: 10) { !engine.active }
        }
        engine = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
        if let suiteName { defaults?.removePersistentDomain(forName: suiteName) }
        Settings.defaults = .standard
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion) }
        try await super.tearDown()
    }

    /// Asleep displays aren't listed by ScreenCaptureKit; declaring user
    /// activity lights them (a locked Mac stays locked).
    private static func wakeDisplays() async -> Bool {
        var assertion: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity("LF Studios recording tests" as CFString, kIOPMUserActiveLocal, &assertion)
        for _ in 0..<40 {
            let content = await within(10) { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
            if content?.displays.isEmpty == false { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    /// The operation's result, or nil if it fails or doesn't answer in time
    /// (ScreenCaptureKit can stall while another process hammers it).
    private static func within<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let lock = NSLock()
            nonisolated(unsafe) var resumed = false
            let finish: @Sendable (T?) -> Void = { value in
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }
            Task { finish(try? await operation()) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                finish(nil)
            }
        }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("timed out")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// The tests that look at what's on the screen share it with whoever
    /// is using the Mac: a window opened on top, another Space, a full-
    /// screen app. `attempt` returns nil once it has checked the video, or
    /// why the screen couldn't be used (nothing asserted). That gets one
    /// more try, then a skip that says so; never a silent pass.
    private func onIdleScreen(_ what: String, _ attempt: () async throws -> String?) async throws {
        guard let busy = try await attempt() else { return }
        print("SCREEN-BUSY: \(what): \(busy); trying once more")
        try await sleep(1.5)
        if let still = try await attempt() {
            throw XCTSkip("needs an idle screen: \(what): \(still)")
        }
    }

    private func areaOnMainScreen() throws -> (CGRect, NSScreen) {
        let screen = try XCTUnwrap(NSScreen.main)
        return (CGRect(x: screen.frame.minX + 120, y: screen.frame.minY + 120, width: 640, height: 360), screen)
    }

    /// Whether the new take itself started is the machine's business (see
    /// start(_:_:)); tests that only care about the last one tidy it away.
    private func discardIfRecording(_ engine: RecordingEngine) async throws {
        guard engine.active else { return }
        engine.discardRecording()
        try await waitUntil(timeout: 10) { !engine.active }
    }

    private func startedEngine() async throws -> (RecordingEngine, () -> URL?) {
        let (engine, finished) = try await startedEngineReportingFinish()
        return (engine, { finished()?.url })
    }

    private func startedEngineReportingFinish() async throws -> (RecordingEngine, () -> FinishedRecording?) {
        let engine = RecordingEngine()
        self.engine = engine
        var finished: FinishedRecording?
        engine.recordingFinishedHandler = { finished = $0 }
        let (rect, screen) = try areaOnMainScreen()
        try await start(engine) { await engine.startRecording(rect: rect, on: screen) }
        return (engine, { finished })
    }

    /// A display that just woke can be slow to hand out its first frames;
    /// one retry covers that. A stream that won't start at all is the
    /// machine's state (asleep, or ScreenCaptureKit busy elsewhere), not a
    /// finding.
    private func start(_ engine: RecordingEngine, _ begin: () async -> Void) async throws {
        await begin()
        if engine.elapsedSeconds == nil {
            try await sleep(1)
            await begin()
        }
        guard engine.elapsedSeconds != nil else { throw XCTSkip("ScreenCaptureKit didn't start a stream") }
        // A started stream that never sends a picture (displays powered
        // down under a lock screen, a capture service busy elsewhere) is the
        // machine's state too.
        let deadline = Date().addingTimeInterval(6)
        while !engine.hasCapturedFrames, Date() < deadline {
            try await sleep(0.05)
        }
        guard engine.hasCapturedFrames else {
            engine.discardRecording()
            try await waitUntil(timeout: 10) { !engine.active }
            throw XCTSkip("the screen isn't delivering frames")
        }
    }

    func testRecordsAPlayableAreaAndCleansUpAfterwards() async throws {
        let (engine, finished) = try await startedEngine()
        // While recording: a stop shortcut, a display that stays awake, and
        // quitting that waits for the file.
        XCTAssertTrue(RecordingStopHotkey.isRegistered)
        XCTAssertTrue(engine.isPreventingDisplaySleep)
        XCTAssertTrue(AppTermination.isBusy)
        XCTAssertNotNil(RecordingRecovery.load(), "a crash would leave a note to recover from")

        try await sleep(2)
        engine.stopRecording()
        XCTAssertTrue(engine.isSaving)
        try await waitUntil(timeout: 20) { finished() != nil }
        let url = try XCTUnwrap(finished())

        XCTAssertFalse(engine.active)
        XCTAssertFalse(RecordingStopHotkey.isRegistered)
        XCTAssertFalse(engine.isPreventingDisplaySleep)
        XCTAssertFalse(AppTermination.isBusy)
        XCTAssertNil(RecordingRecovery.load())

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.35)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let scale = try XCTUnwrap(NSScreen.main).backingScaleFactor
        XCTAssertEqual(size, CGSize(width: 640 * scale, height: 360 * scale))

        let metadata = try XCTUnwrap(VideoDemoSidecarStore.load(for: url))
        XCTAssertEqual(metadata.duration, duration, accuracy: 0.2)
        XCTAssertEqual(metadata.fps, 30)
        XCTAssertNotNil(metadata.screenActivity, "activity is recorded for idle detection")
        XCTAssertTrue(metadata.screenActivity?.allSatisfy { $0 >= 0 && $0 <= duration + 0.05 } ?? false)
        // Pointer samples run on the video's clock: t=0 at the first frame
        // (a still pointer is sampled every 0.25 s), so they span the video.
        XCTAssertEqual(metadata.cursorSamples.first?.time ?? -1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(metadata.cursorSamples.last?.time ?? 0, duration - 0.35)
        XCTAssertLessThanOrEqual(metadata.cursorSamples.last?.time ?? .infinity, duration + 0.05)
    }

    func testPausedTimeIsCutFromTheRecording() async throws {
        let (engine, finished) = try await startedEngine()
        try await sleep(1)
        engine.togglePause()
        XCTAssertTrue(engine.isPaused)
        let atPause = try XCTUnwrap(engine.elapsedSeconds)
        try await sleep(1.5)
        XCTAssertEqual(try XCTUnwrap(engine.elapsedSeconds), atPause, accuracy: 0.05, "the clock stops while paused")
        engine.togglePause()
        XCTAssertFalse(engine.isPaused)
        try await sleep(1)
        engine.stopRecording()
        try await waitUntil(timeout: 20) { finished() != nil }
        let url = try XCTUnwrap(finished())
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.35, "3.5 s of wall time, 1.5 s of it paused")
        let metadata = try XCTUnwrap(VideoDemoSidecarStore.load(for: url))
        XCTAssertEqual(metadata.duration, 2, accuracy: 0.35)
        XCTAssertTrue(metadata.cursorSamples.allSatisfy { $0.time <= metadata.duration + 0.05 }, "pointer data skips the pause too")
    }

    func testDiscardLeavesNothingBehind() async throws {
        let (engine, finished) = try await startedEngine()
        try await sleep(1)
        engine.discardRecording()
        try await waitUntil(timeout: 10) { !engine.active }
        XCTAssertNil(finished())
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(leftovers, [], "the file is deleted")
        XCTAssertNil(RecordingRecovery.load())
        XCTAssertFalse(AppTermination.isBusy)
    }

    /// Quit (or logout, or an update) mid-recording: stop, save, then let go.
    func testQuittingStopsAndSavesFirst() async throws {
        let (engine, finished) = try await startedEngine()
        try await sleep(1.2)
        var quitMayProceed = false
        AppTermination.finishAll { quitMayProceed = true }
        XCTAssertFalse(quitMayProceed, "waits for the file")
        try await waitUntil(timeout: 20) { quitMayProceed }
        XCTAssertFalse(engine.active)
        XCTAssertNil(finished(), "no editor or panel on the way out")
        let saved = URL(fileURLWithPath: Settings.lastRecordingPath)
        XCTAssertEqual(saved.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        let playable = try await AVURLAsset(url: saved).load(.isPlayable)
        XCTAssertTrue(playable)
    }

    /// Stop pressed while the stream is still starting (a shortcut, the menu
    /// bar): nothing keeps running, no HUD appears, nothing is left behind.
    func testStopWhileTheStreamStartsLeavesNothingRunning() async throws {
        let engine = RecordingEngine()
        self.engine = engine
        var finished: URL?
        engine.recordingFinishedHandler = { finished = $0.url }
        let (rect, screen) = try areaOnMainScreen()
        let start = Task { await engine.startRecording(rect: rect, on: screen) }
        let deadline = Date().addingTimeInterval(10)
        while engine.elapsedSeconds == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        guard engine.elapsedSeconds != nil else { throw XCTSkip("ScreenCaptureKit didn't start a stream") }
        engine.stopRecording()
        await start.value
        try await waitUntil(timeout: 15) { !engine.active }

        XCTAssertFalse(RecordingStopHotkey.isRegistered)
        XCTAssertFalse(AppTermination.isBusy)
        XCTAssertFalse(engine.isPreventingDisplaySleep)
        XCTAssertNil(RecordingRecovery.load())
        XCTAssertFalse(NSApp.windows.contains { $0 is RecordingHUDWindow && $0.isVisible }, "no HUD for a recording that already ended")
        if let finished {
            // The stop landed just after the start: a short, playable file.
            let playable = try await AVURLAsset(url: finished).load(.isPlayable)
            XCTAssertTrue(playable)
        } else {
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            XCTAssertEqual(leftovers, [], "nothing recorded, nothing left")
        }
    }

    /// The next take started while the last one saves: the last one's editor
    /// doesn't open over it (it would be recorded and steal focus); the
    /// panel appears instead and the foreground Stop took goes back.
    func testNextTakeWaitingForTheSaveDoesntOpenTheLastOnesEditor() async throws {
        Settings.openVideoEditorAfterRecording = true
        let (engine, finished) = try await startedEngineReportingFinish()
        defer { LFStudiosEditorActivation.releaseForeground() }
        try await sleep(1)
        engine.stopRecording()
        XCTAssertTrue(LFStudiosEditorActivation.isHoldingForeground, "Stop keeps the foreground for the editor")
        let (rect, screen) = try areaOnMainScreen()
        await engine.startRecording(rect: rect, on: screen)
        let first = try XCTUnwrap(finished(), "saved before the new take started")
        XCTAssertFalse(first.opensEditor, "no editor over the new take")
        XCTAssertFalse(LFStudiosEditorActivation.isHoldingForeground, "and no Dock icon left behind")
        try await discardIfRecording(engine)
    }

    /// The same while the next take is only being set up (area selection,
    /// the recording bar, a countdown).
    func testTakeFinishingDuringTheNextOnesSetupDoesntOpenItsEditor() async throws {
        Settings.openVideoEditorAfterRecording = true
        let (engine, finished) = try await startedEngineReportingFinish()
        defer { LFStudiosEditorActivation.releaseForeground() }
        try await sleep(1)
        engine.stopRecording()
        var settingUp = true
        engine.nextTakeInProgress = { settingUp }
        try await waitUntil(timeout: 20) { finished() != nil }
        XCTAssertEqual(finished()?.opensEditor, false)
        XCTAssertFalse(LFStudiosEditorActivation.isHoldingForeground)

        // Nothing on the way: the editor opens (and ends the hold itself).
        settingUp = false
        let firstURL = finished()?.url
        let (rect, screen) = try areaOnMainScreen()
        try await start(engine) { await engine.startRecording(rect: rect, on: screen) }
        try await sleep(1)
        engine.stopRecording()
        try await waitUntil(timeout: 20) { finished()?.url != firstURL }
        XCTAssertEqual(finished()?.opensEditor, true)
    }

    /// Record pressed while the last take saves: the start runs a moment
    /// later, and a take finishing in between already counts it.
    func testTakeFinishingRightAfterRecordIsPressedDoesntOpenItsEditor() async throws {
        Settings.openVideoEditorAfterRecording = true
        let (engine, finished) = try await startedEngineReportingFinish()
        defer { LFStudiosEditorActivation.releaseForeground() }
        try await sleep(1)
        engine.stopRecording()
        engine.startWillFollow()
        try await waitUntil(timeout: 20) { finished() != nil }
        XCTAssertEqual(finished()?.opensEditor, false)
        XCTAssertFalse(LFStudiosEditorActivation.isHoldingForeground)
        let (rect, screen) = try areaOnMainScreen()
        await engine.startRecording(rect: rect, on: screen)
        try await discardIfRecording(engine)
    }

    /// Open Editor After Recording turned off during the save: no editor,
    /// and the foreground taken for it at Stop goes back.
    func testTurningTheEditorOffDuringTheSaveGivesTheForegroundBack() async throws {
        Settings.openVideoEditorAfterRecording = true
        let (engine, finished) = try await startedEngineReportingFinish()
        defer { LFStudiosEditorActivation.releaseForeground() }
        try await sleep(1)
        engine.stopRecording()
        XCTAssertTrue(LFStudiosEditorActivation.isHoldingForeground)
        Settings.openVideoEditorAfterRecording = false
        try await waitUntil(timeout: 20) { finished() != nil }
        XCTAssertEqual(finished()?.opensEditor, false)
        XCTAssertFalse(LFStudiosEditorActivation.isHoldingForeground, "no Dock icon left behind")
    }

    /// A take whose writer failed is checked for what still plays. It counts
    /// as saving until its data and recovery note are settled, and it only
    /// clears its own note (not the next take's).
    func testSalvagedTakeIsSettledBeforeTheEngineGoesIdle() async throws {
        let (engine, finished) = try await startedEngine()
        let nextTake = RecordingRecoveryNote(videoPath: folder.appendingPathComponent("next.mp4").path, cameraPath: nil, cameraOffset: nil, fps: 30, nativeCursorVisible: false, audioTracks: nil, startedAt: Date())
        defer { RecordingRecovery.clear() }
        var checked = false
        engine.salvagesNextSaveForTesting = { [unowned engine] in
            checked = true
            XCTAssertTrue(engine.active, "still saving while the file is checked")
            RecordingRecovery.save(nextTake)
        }
        try await sleep(1.5)
        engine.stopRecording()
        let deadline = Date().addingTimeInterval(20)
        while engine.active, Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(checked, "went down the salvage path")
        XCTAssertFalse(engine.active)
        // The first moment the engine looks idle, everything is done.
        let url = try XCTUnwrap(finished(), "announced before going idle")
        XCTAssertNotNil(VideoDemoSidecarStore.load(for: url), "editor data saved before going idle")
        XCTAssertEqual(RecordingRecovery.load(), nextTake, "another take's recovery note is left alone")
        let playable = try await AVURLAsset(url: url).load(.isPlayable)
        XCTAssertTrue(playable)
    }

    /// A quit while a salvaged take is checked waits for its data.
    func testQuitDuringASalvageWaitsForTheTake() async throws {
        let (engine, finished) = try await startedEngine()
        var quitMayProceed = false
        engine.salvagesNextSaveForTesting = {
            AppTermination.finishAll { quitMayProceed = true }
            XCTAssertFalse(quitMayProceed, "the quit waits for the take")
        }
        try await sleep(1.2)
        engine.stopRecording()
        try await waitUntil(timeout: 20) { quitMayProceed }
        XCTAssertFalse(engine.active)
        XCTAssertNil(finished(), "quitting: nothing opens")
        let saved = URL(fileURLWithPath: Settings.lastRecordingPath)
        XCTAssertEqual(saved.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertNotNil(VideoDemoSidecarStore.load(for: saved), "its data was written before the quit went ahead")
        XCTAssertNil(RecordingRecovery.load())
    }

    /// Recording the back one of two overlapping windows of the same app:
    /// the front one isn't painted over it.
    func testWindowRecordingLeavesTheAppsOtherWindowsOut() async throws {
        try await onIdleScreen("recording one of two overlapping windows") { try await attemptLeavingOtherWindowsOut() }
    }

    private func attemptLeavingOtherWindowsOut() async throws -> String? {
        let screen = try XCTUnwrap(NSScreen.main)
        func coloredWindow(_ title: String, _ color: NSColor, at origin: NSPoint) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: 480, height: 320)), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = title
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
            content.wantsLayer = true
            content.layer?.backgroundColor = color.cgColor
            window.contentView = content
            return window
        }
        let back = coloredWindow("Back", NSColor(srgbRed: 0, green: 0.8, blue: 0.2, alpha: 1), at: NSPoint(x: screen.frame.minX + 160, y: screen.frame.minY + 140))
        let front = coloredWindow("Front", NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1), at: NSPoint(x: screen.frame.minX + 300, y: screen.frame.minY + 200))
        back.orderFrontRegardless()
        front.orderFrontRegardless()
        defer { [back, front].forEach { $0.orderOut(nil) } }

        // Both windows listed before recording (a busy Mac can take a while).
        var listed: SCShareableContent?
        let listDeadline = Date().addingTimeInterval(8)
        while Date() < listDeadline {
            try await sleep(0.2)
            listed = await Self.within(10) { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
            let ids = Set(listed?.windows.map(\.windowID) ?? [])
            if ids.contains(CGWindowID(back.windowNumber)), ids.contains(CGWindowID(front.windowNumber)) { break }
        }
        guard let scWindow = listed?.windows.first(where: { $0.windowID == CGWindowID(back.windowNumber) }) else {
            return "the test window wasn't listed as on screen"
        }

        let engine = RecordingEngine()
        self.engine = engine
        var finished: URL?
        engine.recordingFinishedHandler = { finished = $0.url }
        try await start(engine) { await engine.startRecording(window: scWindow, on: screen) }
        try await sleep(1.2)
        engine.stopRecording()
        try await waitUntil(timeout: 20) { finished != nil }
        let url = try XCTUnwrap(finished)

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: 0.8, preferredTimescale: 600)).image
        let ci = CIImage(cgImage: image)
        // The overlap: the front window covers the back one's right half.
        let overlap = CGRect(x: ci.extent.width * 0.65, y: ci.extent.height * 0.2, width: ci.extent.width * 0.25, height: ci.extent.height * 0.4)
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(ci.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: overlap)]), toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        // Neither window's color: something else was over them.
        let green = pixel[1] > 170 && pixel[0] < 60
        let red = pixel[0] > 170 && pixel[1] < 60
        if !green && !red { return "the recording shows neither test window (\(pixel))" }
        XCTAssertGreaterThan(Int(pixel[1]), 170, "the chosen window's green shows where the other window overlaps it (\(pixel))")
        XCTAssertLessThan(Int(pixel[0]), 60, "not the other window's red (\(pixel))")
        return nil
    }

    /// A second recording set up while the first saves starts once it's ready.
    func testStartingWhileSavingWaitsForTheFile() async throws {
        let (engine, finished) = try await startedEngine()
        try await sleep(1)
        engine.stopRecording()
        let (rect, screen) = try areaOnMainScreen()
        await engine.startRecording(rect: rect, on: screen)
        XCTAssertNotNil(finished(), "the first file finished before the second began")
        XCTAssertNotNil(engine.elapsedSeconds, "and the second one is recording")
        engine.discardRecording()
        try await waitUntil(timeout: 10) { !engine.active }
    }

    /// Window recordings follow the window: moved, the crop moves with it;
    /// resized, it's scaled into the video.
    func testWindowRecordingFollowsItsWindow() async throws {
        try await onIdleScreen("recording a window that moves and resizes") { try await attemptFollowingTheWindow() }
    }

    private func attemptFollowingTheWindow() async throws -> String? {
        let screen = try XCTUnwrap(NSScreen.main)
        let window = NSWindow(contentRect: NSRect(x: screen.frame.minX + 160, y: screen.frame.minY + 160, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(srgbRed: 0, green: 0.8, blue: 0.2, alpha: 1).cgColor
        window.contentView = content
        window.level = .floating
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await sleep(0.4)

        let shareable = await Self.within(10) { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        guard let scWindow = shareable?.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            return "the test window wasn't listed as on screen"
        }

        let engine = RecordingEngine()
        self.engine = engine
        var finished: URL?
        engine.recordingFinishedHandler = { finished = $0.url }
        // Each change gets 1.5 s: a busy Mac can take most of a second to
        // apply a new crop.
        try await start(engine) { await engine.startRecording(window: scWindow, on: screen) }
        try await sleep(1)
        window.setFrameOrigin(NSPoint(x: screen.frame.minX + 520, y: screen.frame.minY + 260))
        try await sleep(1.5)
        window.setContentSize(NSSize(width: 800, height: 300))
        try await sleep(1.5)
        engine.stopRecording()
        try await waitUntil(timeout: 20) { finished != nil }
        let url = try XCTUnwrap(finished)

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        func greenFraction(at seconds: Double, rows: ClosedRange<Double>) async throws -> Double {
            let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
            let ci = CIImage(cgImage: image)
            let band = CGRect(x: 0, y: ci.extent.height * (1 - rows.upperBound), width: ci.extent.width, height: ci.extent.height * (rows.upperBound - rows.lowerBound))
            var pixel = [UInt8](repeating: 0, count: 4)
            CIContext().render(ci.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: band)]), toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return Double(pixel[1]) / 204
        }
        let before = try await greenFraction(at: 0.5, rows: 0.1...0.9)
        if before < 0.5 { return "the window's green isn't in the recording (\(Int(before * 100))%)" }
        let afterMove = try await greenFraction(at: 2.3, rows: 0.1...0.9)
        XCTAssertGreaterThan(before, 0.9, "the window fills the video")
        XCTAssertGreaterThan(afterMove, 0.9, "after moving, the crop followed it")

        // Twice as wide: scaled to fit, bars above and below.
        let resizedMiddle = try await greenFraction(at: 3.8, rows: 0.4...0.6)
        let resizedTop = try await greenFraction(at: 3.8, rows: 0.0...0.15)
        XCTAssertGreaterThan(resizedMiddle, 0.9, "the resized window is still in the video")
        XCTAssertLessThan(resizedTop, 0.2, "letterboxed, not stretched or cropped")
        return nil
    }

    // MARK: The frame bar (1.8.0)

    /// A green titled window (one of the test app's real windows, so it's
    /// recorded) around `rect`.
    private func greenWindow(around rect: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: rect.insetBy(dx: -120, dy: -90), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Green"
        let content = NSView(frame: NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(srgbRed: 0, green: 0.8, blue: 0.2, alpha: 1).cgColor
        window.contentView = content
        window.setFrame(window.frameRect(forContentRect: rect.insetBy(dx: -120, dy: -90)), display: true)
        // Record gives focus back to the app the user was in: this stays on top of it.
        window.level = .floating
        window.orderFrontRegardless()
        return window
    }

    /// Every pixel of the frame's outer ring and a grid inside it is the
    /// green underneath: no border, no dimming, no handles, no size label.
    /// Nil once checked; why not when most of it isn't the window at all
    /// (covered by something on the Mac, not a stray border or dimming).
    private func assertOnlyGreen(_ url: URL, at seconds: [Double], file: StaticString = #filePath, line: UInt = #line) async throws -> String? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for time in seconds {
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            let width = image.width, height = image.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let context = try XCTUnwrap(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var bad: [(Int, Int, [UInt8])] = []
            var checked = 0
            func check(_ x: Int, _ y: Int) {
                checked += 1
                let i = (y * width + x) * 4
                let (r, g, b) = (data[i], data[i + 1], data[i + 2])
                if !(g > 150 && r < 90 && b < 130) { bad.append((x, y, [r, g, b])) }
            }
            for x in 0..<width { for y in [0, 1, 2, 3, height - 4, height - 3, height - 2, height - 1] { check(x, y) } }
            for y in 0..<height { for x in [0, 1, 2, 3, width - 4, width - 3, width - 2, width - 1] { check(x, y) } }
            for x in stride(from: 0, to: width, by: 7) { for y in stride(from: 0, to: height, by: 7) { check(x, y) } }
            if !bad.isEmpty, let out = ProcessInfo.processInfo.environment["LF_FRAME_DEBUG_DIR"],
               let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out).appendingPathComponent("frame-\(time).png") as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
            if bad.count * 2 > checked { return "at \(time) s, \(bad.count) of \(checked) pixels aren't the test window: something covered it" }
            XCTAssertTrue(bad.isEmpty, "at \(time) s, \(bad.count) pixels aren't the window underneath, first \(bad.prefix(5))", file: file, line: line)
        }
        return nil
    }

    /// The frame, its dimming, border and handles showing the whole time
    /// (worse than the real flow, which closes them on Record): none of it
    /// is in the video, which is exactly the frame's pixels.
    func testTheFrameAndItsDimmingAreNeverRecorded() async throws {
        try await onIdleScreen("recording through the frame") { try await attemptRecordingThroughTheFrame() }
    }

    private func attemptRecordingThroughTheFrame() async throws -> String? {
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = RecordingFrameController(screen: screen)
        let scale = screen.backingScaleFactor
        frame.setPixels(RecordingFrameGeometry.Pixels(width: Int(640 * scale), height: Int(360 * scale)))
        frame.move(to: CGPoint(x: screen.frame.midX - 320 + 0.3, y: screen.frame.midY - 180 + 0.3), snapping: false)
        let green = greenWindow(around: frame.rect)
        defer { green.orderOut(nil) }
        frame.show()
        defer { frame.close() }
        try await sleep(0.5)

        let engine = RecordingEngine()
        self.engine = engine
        var finished: URL?
        engine.recordingFinishedHandler = { finished = $0.url }
        try await start(engine) { await engine.startRecording(rect: frame.rect, on: screen) }
        try await sleep(1.5)
        engine.stopRecording()
        try await waitUntil(timeout: 20) { finished != nil }
        let url = try XCTUnwrap(finished)

        let track = try await XCTUnwrapAsync(await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(Int(size.width), frame.pixels.width)
        XCTAssertEqual(Int(size.height), frame.pixels.height)
        XCTAssertEqual(Int(size.width) * 9, Int(size.height) * 16, "exactly 16:9")
        return try await assertOnlyGreen(url, at: [0.3, 1.0])
    }

    /// The real flow: New recording's frame bar, a 1:1 frame, Return. The
    /// frame, strip and bar are gone before the first frame; the video is
    /// exactly the frame.
    func testTheFrameBarRecordsExactlyTheFrame() async throws {
        try await onIdleScreen("recording from the frame bar") { try await attemptRecordingFromTheFrameBar() }
    }

    private func attemptRecordingFromTheFrameBar() async throws -> String? {
        Settings.recordingCountdownSeconds = 0
        let capture = CaptureEngine()
        var finished: URL?
        capture.recordingFinishedHandler = { finished = $0.url }
        await capture.startAreaRecording()
        let setup = try XCTUnwrap(capture.frameSetupForTesting, "New recording shows the frame bar")
        XCTAssertTrue(setup.strip.isVisible)
        XCTAssertTrue(setup.bar.childWindows?.contains(setup.strip) == true, "the strip moves with the bar")
        XCTAssertFalse(setup.frame.windows.isEmpty)
        XCTAssertTrue(RecordingStopHotkey.isRegistered, "⌃⌘Esc cancels the frame from any app")

        let frame = setup.frame
        let scale = frame.scale
        frame.setRatio(RecordingFrameRatio(1, 1))
        frame.setPixels(RecordingFrameGeometry.Pixels(width: Int(400 * scale), height: Int(400 * scale)))
        frame.move(to: CGPoint(x: frame.screen.frame.midX - 200, y: frame.screen.frame.midY - 200), snapping: false)
        let block = setup.bar.visibleBarFrame.union(setup.strip.frame)
        XCTAssertFalse(block.intersects(frame.rect), "the bars keep clear of the frame")
        let green = greenWindow(around: frame.rect)
        defer { green.orderOut(nil) }
        let pixels = frame.pixels
        try await sleep(0.4)

        // Return, as from the frame's border.
        let returnKey = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        XCTAssertTrue(frame.handleKey(returnKey))
        XCTAssertTrue(frame.windows.isEmpty, "the frame is gone before recording starts")
        XCTAssertFalse(setup.strip.isVisible)
        XCTAssertFalse(setup.bar.isVisible)
        XCTAssertNil(capture.frameSetupForTesting)

        let deadline = Date().addingTimeInterval(10)
        while !capture.isRecordingForTesting, Date() < deadline { try await sleep(0.05) }
        guard capture.isRecordingForTesting else { throw XCTSkip("ScreenCaptureKit didn't start a stream") }
        try await sleep(2)
        capture.stopRecording()
        try await waitUntil(timeout: 20) { finished != nil }
        let url = try XCTUnwrap(finished)
        let track = try await XCTUnwrapAsync(await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(Int(size.width), pixels.width)
        XCTAssertEqual(Int(size.height), pixels.height)
        return try await assertOnlyGreen(url, at: [0.5, 1.5])
    }
}
