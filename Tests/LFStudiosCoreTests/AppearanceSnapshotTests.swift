import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// Settings → General → Appearance. Every window renders in the light and
/// the dark look (printed as SNAPSHOT-APPEARANCE: <path>, in
/// $LFSTUDIOS_APPEARANCE_SNAPSHOTS or a temporary folder) to look through;
/// the floating overlays stay dark even when the app is light.
@MainActor
final class AppearanceSnapshotTests: XCTestCase {
    private static let looks: [(name: String, appearance: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
    private var suiteName: String!
    private var windows: [NSWindow] = []

    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        suiteName = "LFStudiosCoreTests.Appearance.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        L10n.use("en")
    }

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSApp.appearance = nil
        L10n.use(nil)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
    }

    // MARK: The setting

    func testTheSettingDefaultsToSystemAndSwitchesTheAppLive() {
        XCTAssertEqual(Settings.appearance, .system)
        AppAppearance.apply()
        XCTAssertNil(NSApp.appearance, "System: the Mac decides")
        Settings.appearance = .light
        AppAppearance.apply()
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
        Settings.appearance = .dark
        AppAppearance.apply()
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
        XCTAssertEqual(Settings.defaults.string(forKey: AppAppearance.key), "dark")
        XCTAssertEqual(AppAppearance.allCases.map(\.title), ["System", "Light Mode", "Dark Mode"])
    }

    func testThemeColorsFollowTheAppearance() {
        func resolved(_ color: NSColor, _ name: NSAppearance.Name) -> NSColor {
            var result = color
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                result = color.usingColorSpace(.sRGB)!
            }
            return result
        }
        let ink = NSColor.adaptive(dark: .white, light: .black)
        XCTAssertEqual(resolved(ink, .darkAqua).whiteComponentInSRGB, 1, accuracy: 0.01)
        XCTAssertEqual(resolved(ink, .aqua).whiteComponentInSRGB, 0, accuracy: 0.01)
    }

    // MARK: The video editor

    private func demoModel(camera: Bool = false) async throws -> VideoEditorModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-appearance", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(camera ? "with-camera.mp4" : "plain.mp4")
        let cameraURL = directory.appendingPathComponent("camera.mov")
        if !FileManager.default.fileExists(atPath: url.path) {
            try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 1440, height: 900), seconds: 12, fps: 30, audioSeconds: 12)
        }
        if camera, !FileManager.default.fileExists(atPath: cameraURL.path) {
            try await VideoTestSupport.writeFakeRecording(to: cameraURL, size: CGSize(width: 640, height: 480), seconds: 12, fps: 30)
        }
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: 12)
        var metadata = VideoDemoRecordingMetadata(videoURLPath: url.path, createdAt: Date(), duration: 12, sourceWidth: 1440, sourceHeight: 900, fps: 30, nativeCursorVisible: false, cursorSamples: samples, clickEvents: clicks, pointPixelScale: 2, renderCursor: true)
        if camera { metadata.webcam = VideoWebcamRecording(path: cameraURL.path, offset: 0, width: 640, height: 480) }
        VideoDemoSidecarStore.save(metadata, for: url)
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        try? await Task.sleep(nanoseconds: 600_000_000)
        return model
    }

    /// Captions, shortcuts, annotations, a title card, and a camera layout.
    private func furnish(_ model: VideoEditorModel) {
        let words: [(String, Double)] = [("Open", 1.0), ("the", 1.3), ("settings", 1.45), ("panel.", 1.9), ("Then", 3.0), ("pick", 3.3), ("a", 3.5), ("theme.", 3.6)]
        model.mutate { project in
            project.captions = VideoCaptionBuilder.lines(from: words.map { VideoCaptionWord(text: $0.0, start: $0.1, end: $0.1 + 0.3) })
            project.keystrokes = [VideoKeystrokeEvent(time: 2.0, keys: ["⌘", ","]), VideoKeystrokeEvent(time: 5.2, keys: ["⇧", "⌘", "S"])]
            project.cards.intro.enabled = true
        }
        model.seek(to: 4)
        model.addOverlay(.text)
        model.seek(to: 6)
        model.addOverlay(.highlight)
        model.seek(to: 7)
        model.splitAtPlayhead()
        model.selection = .none
        model.seek(to: 1.6)
    }

    func testRenderTheVideoEditorInBothLooks() async throws {
        let model = try await demoModel(camera: true)
        try await render(VideoEditorRootView(model: model), size: CGSize(width: 1512, height: 944), name: "editor-fresh")
        furnish(model)
        model.addCameraLayout(.sideBySide)
        model.selection = .none
        try? await Task.sleep(nanoseconds: 300_000_000)
        try await render(VideoEditorRootView(model: model), size: CGSize(width: 1512, height: 944), name: "editor-furnished")
        let height = 44 + 1 + VideoTimelineMetrics.contentHeight(model.project) + 10
        try await render(VideoTimelineView(model: model), size: CGSize(width: 1400, height: height), name: "timeline")

        for tab in VideoEditorModel.InspectorTab.allCases {
            model.selection = .none
            model.inspectorTab = tab
            try await render(VideoInspectorView(model: model), size: CGSize(width: 318, height: 1500), name: "inspector-\(tab.rawValue)")
        }
        model.selection = .zoom(model.project.zoomRegions[0].id)
        try await render(VideoInspectorView(model: model), size: CGSize(width: 318, height: 900), name: "inspector-selected-zoom")
        model.selection = .caption(model.project.captions[0].id)
        try await render(VideoInspectorView(model: model), size: CGSize(width: 318, height: 900), name: "inspector-selected-caption")
        if let text = model.project.overlayEffects.first(where: { $0.kind == .text }) {
            model.selection = .overlay(text.id)
            try await render(VideoInspectorView(model: model), size: CGSize(width: 318, height: 1100), name: "inspector-selected-text")
        }
        model.selection = .none

        model.isExportPresented = true
        try await render(VideoExportSheet(model: model), size: CGSize(width: 900, height: 760), name: "export-sheet")
        model.isExportPresented = false

        let still = NSImage(size: NSSize(width: 640, height: 480), flipped: false) { rect in
            NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: rect, angle: 30)
            return true
        }
        // A sheet: the window behind it is the system one.
        try await render(VideoCameraCropSheet(model: model, picture: still).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 560, height: 520), name: "camera-crop-sheet")

        model.beginCrop()
        try? await Task.sleep(nanoseconds: 300_000_000)
        try await render(VideoEditorRootView(model: model), size: CGSize(width: 1512, height: 944), name: "editor-cropping")
    }

    func testRenderCreativeHandoffInBothLooks() async throws {
        let model = try await demoModel(camera: true)
        furnish(model)
        model.isHandoffPresented = true
        try await render(VideoHandoffSheet(model: model), size: CGSize(width: 900, height: 820), name: "handoff-dialog")
        let job = VideoHandoffJob()
        model.handoffJob = job
        try await render(VideoHandoffSheet(model: model), size: CGSize(width: 900, height: 420), name: "handoff-preparing")
    }

    func testRenderTheEditorWithoutACameraInBothLooks() async throws {
        let model = try await demoModel()
        model.inspectorTab = .camera
        try await render(VideoInspectorView(model: model), size: CGSize(width: 318, height: 700), name: "inspector-camera-none")
    }

    // MARK: Home, Settings, the Command Center, History

    private func history() throws -> HistoryManager {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("LFStudiosCoreTests.Appearance.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let manager = HistoryManager(storageDir: storage)
        for (index, type) in [CaptureType.area, .window, .fullscreen, .scrolling].enumerated() {
            let image = NSImage(size: NSSize(width: 640, height: 400))
            image.lockFocus()
            NSGradient(starting: [.systemBlue, .systemPink, .systemGreen, .systemOrange][index], ending: .white)?.draw(in: NSRect(x: 0, y: 0, width: 640, height: 400), angle: 40)
            image.unlockFocus()
            _ = manager.add(image: image, rect: nil, type: type)
        }
        return manager
    }

    func testRenderHomeInBothLooks() async throws {
        let model = HomeModel(historyManager: try history(), actions: HomeActions(newRecording: {}, takeScreenshot: {}, scrollCapture: {}, openVideo: {}))
        model.reload()
        try? await Task.sleep(nanoseconds: 300_000_000)
        for section in HomeSection.allCases {
            model.section = section
            try await render(HomeRootView(model: model), size: CGSize(width: 1120, height: 740), name: "home-\(section.rawValue)")
        }
        let empty = HomeModel(historyManager: HistoryManager(storageDir: FileManager.default.temporaryDirectory.appendingPathComponent("LFStudiosCoreTests.Appearance.empty.\(UUID().uuidString)")), actions: HomeActions(newRecording: {}, takeScreenshot: {}, scrollCapture: {}, openVideo: {}))
        empty.section = .screenshots
        try await render(HomeRootView(model: empty), size: CGSize(width: 1120, height: 740), name: "home-empty")
    }

    func testRenderSettingsInBothLooks() async throws {
        for tab in PreferencesTab.allCases {
            let selection = PreferencesSelectionModel()
            selection.selectedTab = tab
            let height: CGFloat = tab == .screenshots || tab == .recording ? 2000 : 1100
            try await render(PreferencesRootView(selection: selection), size: CGSize(width: 560, height: height), name: "settings-\(tab)")
        }
    }

    func testRenderTheCommandCenterInBothLooks() async throws {
        let delegate = AppDelegate()
        let broken = LFStudiosHealthSnapshot(
            screenRecordingGranted: false, nativeShortcutsEnabled: true, updatesConfigured: false,
            autoSavePath: "/nonexistent", autoSaveWritable: false,
            configuredShortcutCount: 5, expectedShortcutCount: 7, optionalUnassignedShortcutCount: 3,
            version: "1.0.0", build: "1"
        )
        let view = LFStudiosCommandCenterView(
            sections: delegate.commandCenterSections(screenCount: 2),
            healthRows: LFStudiosHealthModel.rows(snapshot: broken),
            healthActions: [.screenRecording: {}, .nativeShortcuts: {}, .updates: {}, .autoSave: {}, .shortcuts: {}],
            dismiss: {}
        )
        try await render(view, size: CGSize(width: LFStudiosMenuMetrics.commandCenterWidth, height: 900), name: "command-center")
    }

    func testRenderHistoryInBothLooks() async throws {
        let manager = try history()
        for look in Self.looks {
            let content = HistoryPanelController().makeContent(historyManager: manager)
            content.frame = NSRect(x: 0, y: 0, width: 920, height: 640)
            try write(appKit: content, appearance: look.appearance, name: "history-\(look.name)")
        }
    }

    func testRenderTheScreenshotEditorToolbarInBothLooks() throws {
        for look in Self.looks {
            let stage = NSView(frame: NSRect(x: 0, y: 0, width: AnnotationToolbar.requiredWidth + 40, height: AnnotationToolbar.height + 40))
            stage.wantsLayer = true
            stage.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            let toolbar = AnnotationToolbar(frame: NSRect(x: 20, y: 20, width: AnnotationToolbar.requiredWidth, height: AnnotationToolbar.height))
            toolbar.showOptions(AnnotationToolOptions(context: .rectangle))
            stage.addSubview(toolbar)
            try write(appKit: stage, appearance: look.appearance, name: "screenshot-editor-toolbar-\(look.name)")
        }
    }

    // MARK: Overlays stay dark

    func testOverlaysStayDarkInALightApp() async throws {
        NSApp.appearance = NSAppearance(named: .aqua)
        let screen = try XCTUnwrap(NSScreen.main)
        let countdown = CountdownWindow(seconds: 3, on: screen) { _ in }
        let hud = RecordingHUDWindow()
        hud.configure(systemAudio: true, microphone: true, camera: true, keystrokes: true, fps: 60, quality: RecordingQuality.high.displayName)
        let bar = RecordingControlsWindow(rect: screen.frame, screen: screen, target: .fullscreen, selectedWindow: nil, startHandler: { _, _, _ in }, closeHandler: {})
        let manager = try history()
        let image = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let thumbnail = QuickAccessWindow(image: image, historyItem: manager.add(image: image, rect: nil, type: .area), historyManager: manager)
        defer {
            hud.closeHUD()
            bar.closeControls()
            thumbnail.closeFromCommand()
        }
        windows += [countdown]
        for (name, window) in [("countdown", countdown as NSWindow), ("recording-hud", hud), ("recording-bar", bar), ("screenshot-thumbnail", thumbnail)] {
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua, "\(name) stays dark in a light app")
            window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
            let view = try XCTUnwrap(window.contentView)
            view.layoutSubtreeIfNeeded()
            try write(appKit: view, appearance: nil, name: "overlay-\(name)-in-light-app", backdrop: NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.92, alpha: 1))
        }
    }

    // MARK: Rendering

    private static var folder: URL {
        get throws {
            let url = ProcessInfo.processInfo.environment["LFSTUDIOS_APPEARANCE_SNAPSHOTS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-appearance-snapshots", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    /// A SwiftUI view in an offscreen window, once in each look: its colors
    /// come from the window's appearance, as in the app.
    private func render<V: View>(_ view: V, size: CGSize, name: String) async throws {
        for look in Self.looks {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: look.appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 250_000_000)
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = try Self.folder.appendingPathComponent("\(name)-\(look.name).png")
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
            print("SNAPSHOT-APPEARANCE: \(url.path)")
            window.contentView = nil
        }
    }

    /// An AppKit view at 2x; nil keeps the view's own window's appearance.
    private func write(appKit view: NSView, appearance: NSAppearance.Name?, name: String, backdrop: NSColor? = nil) throws {
        var host: NSWindow?
        if let appearance {
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = view
            host = window
        }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        if let backdrop {
            backdrop.setFill()
            NSRect(origin: .zero, size: view.bounds.size).fill()
        }
        rep.draw(in: NSRect(origin: .zero, size: view.bounds.size))
        image.unlockFocus()
        let url = try Self.folder.appendingPathComponent("\(name).png")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT-APPEARANCE: \(url.path)")
        host?.contentView = nil
    }
}

private extension NSColor {
    var whiteComponentInSRGB: CGFloat {
        (redComponent + greenComponent + blueComponent) / 3
    }
}
