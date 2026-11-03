import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// 1.22.0 changed only how the code is laid out: the editor, the recording
/// bar and Settings must look exactly as 1.21.1 drew them, in both layouts
/// and both looks. Compared with half-size pictures 1.21.1 drew
/// (Fixtures/Reference-1.21.1/screens, written by running this on 1.21.1
/// with LF_REF_RECORD=1).
@MainActor
final class Reference1211SnapshotTests: XCTestCase {
    private static let folder = Reference1211Tests.folder.appendingPathComponent("screens", isDirectory: true)
    private var recording: Bool { ProcessInfo.processInfo.environment["LF_REF_RECORD"] != nil }
    private let looks: [(String, NSAppearance.Name)] = [("dark", .darkAqua), ("light", .aqua)]
    private var suiteName: String!
    private var directory: URL!
    private var windows: [NSWindow] = []

    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
        VideoStageView.drawsStills = true
    }

    override class func tearDown() {
        VideoStageView.drawsStills = false
        super.tearDown()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        suiteName = "LFStudiosCoreTests.Reference1211Screens.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        Settings.videoShortcutsChangeSeen = true
        Settings.videoPanelTipSeen = true
        VideoEditorPanelStore.shared.reload()
        L10n.use("en")
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-ref-screens-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSApp.appearance = nil
        L10n.use(nil)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        VideoEditorPanelStore.shared.reload()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Pixels that may differ by more than a little (of all of them): text
    /// antialiasing between runs, nothing that moved or changed.
    private static let allowedChanged = 0.0002

    /// `rep` at half its size in points, saved as the reference or compared
    /// with it.
    private func check(_ rep: NSBitmapImageRep, name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let width = max(Int(rep.size.width / 2), 1), height = max(Int(rep.size.height / 2), 1)
        let small = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: small)
        context?.imageInterpolation = .high
        NSGraphicsContext.current = context
        rep.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        let url = Self.folder.appendingPathComponent("\(name).png")
        if recording {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try XCTUnwrap(small.representation(using: .png, properties: [:])).write(to: url)
            return
        }
        if let dump = ProcessInfo.processInfo.environment["LF_REF_DUMP"] {
            try small.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dump).appendingPathComponent("\(name).png"))
        }
        let ours = try Self.rgba(XCTUnwrap(small.representation(using: .png, properties: [:])))
        let theirs = try Self.rgba(Data(contentsOf: url))
        XCTAssertEqual(theirs.width, width, "\(name): same size", file: file, line: line)
        XCTAssertEqual(theirs.height, height, "\(name): same size", file: file, line: line)
        guard theirs.width == width, theirs.height == height else { return }
        var changed = 0
        for pixel in stride(from: 0, to: ours.bytes.count, by: 4) where (0..<4).contains(where: { abs(Int(ours.bytes[pixel + $0]) - Int(theirs.bytes[pixel + $0])) > 24 }) {
            changed += 1
        }
        let fraction = Double(changed) / Double(width * height)
        if ProcessInfo.processInfo.environment["LF_REF_VERBOSE"] != nil { print("REF-SCREEN \(name) changed \(changed)") }
        XCTAssertLessThanOrEqual(fraction, Self.allowedChanged, "\(name): \(changed) pixels look different", file: file, line: line)
    }

    /// A PNG's pixels as sRGB RGBA bytes, the same way for both pictures.
    private static func rgba(_ png: Data) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let image = try XCTUnwrap(NSBitmapImageRep(data: png)?.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (bytes, image.width, image.height)
    }

    private func render<Content: View>(_ content: Content, size: CGSize, look: NSAppearance.Name, name: String, wait: Double = 1) async throws {
        NSApp.appearance = NSAppearance(named: look)
        defer { NSApp.appearance = nil }
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).environment(\.colorScheme, look == .darkAqua ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: look)
        window.contentView = host
        window.orderFrontRegardless()
        windows.append(window)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        try check(rep, name: name)
    }

    func testTheEditorLooksAsIn1211() async throws {
        var options = VideoEditorTestModel.Options()
        options.seconds = 10
        options.size = CGSize(width: 1440, height: 900)
        options.audio = true
        options.keystrokes = [VideoKeystrokeEvent(time: 1.5, keys: ["⌘", "S"])]
        let model = try await VideoEditorTestModel.make(in: directory, name: "Product demo.mp4", options)
        model.mutate { $0.captions = [VideoCaptionLine(start: 0.4, end: 2.2, text: "Open the settings"), VideoCaptionLine(start: 2.6, end: 4.6, text: "and pick a theme")] }
        let picture = directory.appendingPathComponent("Shot.png")
        try VideoInspection.writePNG(to: picture, size: CGSize(width: 320, height: 180), color: .systemOrange)
        if let id = await model.addLayerItem(from: picture, at: 1) { model.setLayerItem(id) { $0.length = 2 } }
        model.seek(to: 4)
        model.perform(.split)
        model.endGesture()
        model.selection = .none
        model.seek(to: 3)
        try await forEachEditorStyle { style in
            let tag = style == .lfStudios ? "new" : "capcut"
            for (lookName, look) in looks {
                try await render(VideoEditorRootView(model: model), size: CGSize(width: 1440, height: 900), look: look, name: "editor-\(tag)-\(lookName)", wait: 1.2)
            }
        }
    }

    func testSettingsLooksAsIn1211() async throws {
        try await forEachEditorStyle { style in
            let tag = style == .lfStudios ? "new" : "capcut"
            for tab in PreferencesTab.allCases {
                let selection = PreferencesSelectionModel()
                selection.selectedTab = tab
                let height: CGFloat = tab == .screenshots || tab == .recording ? 2000 : 1100
                for (lookName, look) in looks {
                    try await render(PreferencesRootView(selection: selection), size: CGSize(width: 560, height: height), look: look, name: "settings-\(tab)-\(tag)-\(lookName)", wait: 0.3)
                }
            }
        }
    }

    /// The recording bar is always dark: one row, then with the Area popover.
    func testTheRecordingBarLooksAsIn1211() async throws {
        Settings.recordingMicrophone = true
        Settings.recordingCamera = true
        let screen = try XCTUnwrap(NSScreen.main)
        let rect = CGRect(x: screen.frame.midX - 480, y: screen.frame.midY - 270, width: 960, height: 540)
        let bar = RecordingControlsWindow(rect: rect, screen: screen, target: .area, selectedWindow: nil, startHandler: { _, _, _ in }, closeHandler: {})
        defer { bar.closeControls() }
        bar.frameStripModel = RecordingFrameStripModel(ratio: .standard, pixels: .init(width: 1920, height: 1080), sizeChoices: RecordingFrameGeometry.sizeChoices(.standard, in: .init(width: 3840, height: 2160)))
        bar.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - bar.frame.width / 2, y: screen.visibleFrame.minY + 60))
        bar.orderFrontRegardless()
        try await Task.sleep(nanoseconds: 300_000_000)
        let barView = try XCTUnwrap(bar.contentView)
        let barRep = try XCTUnwrap(barView.bitmapImageRepForCachingDisplay(in: barView.bounds))
        barView.cacheDisplay(in: barView.bounds, to: barRep)
        try check(barRep, name: "recording-bar")

        bar.showAreaPopover()
        try await Task.sleep(nanoseconds: 700_000_000)
        let content = try XCTUnwrap(bar.areaPopover.contentViewController?.view)
        content.layoutSubtreeIfNeeded()
        let popRep = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: popRep)
        try check(popRep, name: "recording-bar-area")
    }
}
