import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// 1.15.0's Library tabs, Properties panels, export window and keys editor
/// in the light and the dark look, English and German, at 1920×1200 and a
/// 13" MacBook's size (printed as SNAPSHOT-117: <path>, in
/// lfstudios-editor-117/).
@MainActor
final class VideoEditor117SnapshotTests: XCTestCase {
    private var suiteName: String!
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
        suiteName = "LFStudiosCoreTests.Editor117.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        Settings.videoShortcutsChangeSeen = true
        Settings.videoPanelTipSeen = true
        VideoEditorPanelStore.shared.reload()
    }

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        L10n.use(nil)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        VideoEditorPanelStore.shared.reload()
    }

    private static let media = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-117-media", isDirectory: true)
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-editor-117", isDirectory: true)

    /// A recording with text, a sticker, an effect clip, an adjustment clip
    /// and a compound on tracks above it, cuts with transitions.
    private func demoModel() async throws -> VideoEditorModel {
        try FileManager.default.createDirectory(at: Self.media, withIntermediateDirectories: true)
        let url = Self.media.appendingPathComponent("Product demo.mp4")
        if !FileManager.default.fileExists(atPath: url.path) {
            try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 1440, height: 900), seconds: 12, fps: 30, audioSeconds: 12)
        }
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        try? await Task.sleep(nanoseconds: 500_000_000)
        model.seek(to: 4)
        model.perform(.split)
        model.seek(to: 8)
        model.perform(.split)
        model.perform(.clip(.transitionEverywhere(.push, 0.6)))
        let title = model.addTextTemplate(try XCTUnwrap(VideoTextTemplate.all.first { $0.id == "title-pop" }), at: 1)
        model.addSticker(.heart, at: 2)
        model.addEffect(.vhs, at: 5, onSelection: false)
        model.addAdjustment(try XCTUnwrap(VideoAdjustPreset.all.first { $0.id == "teal-shadows" }), at: 6, onSelection: false)
        model.selection = .layer(title)
        model.seek(to: 1.4)
        model.perform(.addKeyframe)
        model.seek(to: 2.2)
        return model
    }

    private func render<Content: View>(_ content: Content, size: CGSize, look: NSAppearance.Name, name: String) async throws {
        let dark = look == .darkAqua
        NSApp.appearance = NSAppearance(named: look)
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: look)
        window.contentView = host
        windows.append(window)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 900_000_000)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let url = Self.folder.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT-117: \(url.path)")
        NSApp.appearance = nil
    }

    private func style(_ style: VideoEditorStyle) {
        Settings.videoEditorStyle = style
        VideoEditorPanelStore.shared.reload()
    }

    /// While building: the main window in a few looks.
    func testQuickLook() async throws {
        let model = try await demoModel()
        // The title's track with its curve lane open (LF Studios layout).
        if let title = model.selectedLayerItem, let track = model.project.layerTrackIndex(of: title.id) {
            model.curveLanes[model.project.layerTracks[track].id] = .width
        }
        for (styleName, s) in [("new", VideoEditorStyle.lfStudios), ("capcut", .capCut)] {
            style(s)
            try await render(VideoEditorRootView(model: model), size: CGSize(width: 1920, height: 1200), look: .darkAqua, name: "quick-\(styleName)-dark-large")
        }
        style(.lfStudios)
        try await render(VideoEditorRootView(model: model), size: CGSize(width: 1920, height: 1200), look: .aqua, name: "quick-new-light-large")
        L10n.use("de")
        try await render(VideoEditorRootView(model: model), size: CGSize(width: 1280, height: 772), look: .darkAqua, name: "quick-new-dark-13-inch-de")
    }

    /// The new layout's labels in the longest languages at 13": each
    /// Properties tab, the curve lane, ⌘K and Captions.
    func testLongLanguagesFitAt13Inch() async throws {
        style(.lfStudios)
        let size = CGSize(width: 1280, height: 772)
        for language in ["de", "ru", "uk", "ja"] {
            L10n.use(language)
            let model = try await demoModel()
            if let title = model.selectedLayerItem, let track = model.project.layerTrackIndex(of: title.id) {
                model.curveLanes[model.project.layerTracks[track].id] = .opacity
                model.mutate { $0.layerTracks[track].items = $0.layerTracks[track].items.map { var i = $0; if i.id == title.id { i.effects = [VideoAppliedEffect(kind: .glow), VideoAppliedEffect(kind: .vhs)] }; return i } }
            }
            model.mutate { $0.captions = VideoCaptionBuilder.lines(from: [VideoCaptionWord(text: "Hello", start: 1, end: 1.5), VideoCaptionWord(text: "there.", start: 1.5, end: 2)]) }
            for tab in VideoPropertiesTab.allCases {
                model.propertiesTab = tab
                try await render(VideoEditorRootView(model: model), size: size, look: .darkAqua, name: "labels-\(tab.rawValue)-\(language)")
            }
            model.isCommandPalettePresented = true
            try await render(VideoEditorRootView(model: model), size: size, look: .darkAqua, name: "labels-search-\(language)")
            model.isCommandPalettePresented = false
        }
    }

    /// The Guide's pictures (Resources/guide-*.jpg), from the LF Studios
    /// layout in English and the dark look. Only with
    /// LFSTUDIOS_GUIDE_PICTURES=1: it writes into the source tree.
    func testGuidePictures() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LFSTUDIOS_GUIDE_PICTURES"] == "1", "Set LFSTUDIOS_GUIDE_PICTURES=1 to make the Guide's pictures")
        style(.lfStudios)
        L10n.use("en")
        let size = CGSize(width: 1512, height: 944)
        let model = try await demoModel()
        let title = try XCTUnwrap(model.selectedLayerItem)
        let track = try XCTUnwrap(model.project.layerTrackIndex(of: title.id))
        model.mutate { project in
            project.layerTracks[track].items = project.layerTracks[track].items.map { item in
                var item = item
                if item.id == title.id { item.effects = [VideoAppliedEffect(kind: .glow, intensity: 0.5), VideoAppliedEffect(kind: .vhs), VideoAppliedEffect(kind: .vignette, intensity: 0.4, off: true)] }
                return item
            }
            project.captions = VideoCaptionBuilder.lines(from: [
                VideoCaptionWord(text: "Open", start: 0.5, end: 0.8), VideoCaptionWord(text: "the", start: 0.8, end: 0.9), VideoCaptionWord(text: "settings.", start: 0.9, end: 1.4),
                VideoCaptionWord(text: "Turn", start: 3.2, end: 3.5), VideoCaptionWord(text: "on", start: 3.5, end: 3.6), VideoCaptionWord(text: "the", start: 3.6, end: 3.7), VideoCaptionWord(text: "dark", start: 3.7, end: 4), VideoCaptionWord(text: "theme.", start: 4, end: 4.5),
                VideoCaptionWord(text: "Save", start: 6.5, end: 6.8), VideoCaptionWord(text: "your", start: 6.8, end: 7), VideoCaptionWord(text: "changes.", start: 7, end: 7.6),
            ])
        }
        // Opacity keyed at 1.6 s (full) and 3 s (30 %): the curve's points.
        model.seek(to: 1.6)
        model.toggleKeyframe(title.id, .opacity)
        model.seek(to: 3)
        model.perform(.edit(.setValue(.opacity, 0.3)))
        model.endGesture()
        model.seek(to: 2.2)
        model.curveLanes[model.project.layerTracks[track].id] = .opacity

        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LFStudiosCore/Resources", isDirectory: true)
        func picture(_ content: some View, name: String, crop: CGRect?, width: CGFloat) async throws {
            try await render(content, size: size, look: .darkAqua, name: name)
            let png = Self.folder.appendingPathComponent("\(name)-dark.png")
            let source = try XCTUnwrap(NSImage(contentsOf: Self.folder.appendingPathComponent("\(name).png")))
            _ = png
            var cg = try XCTUnwrap(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
            if let crop {
                let k = CGFloat(cg.width) / size.width
                cg = try XCTUnwrap(cg.cropping(to: CGRect(x: crop.minX * k, y: crop.minY * k, width: crop.width * k, height: crop.height * k)))
            }
            let scale = min(width / CGFloat(cg.width), 1)
            let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(CGFloat(cg.width) * scale), pixelsHigh: Int(CGFloat(cg.height) * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
            NSGraphicsContext.current?.imageInterpolation = .high
            NSImage(cgImage: cg, size: .zero).draw(in: NSRect(x: 0, y: 0, width: out.pixelsWide, height: out.pixelsHigh))
            NSGraphicsContext.restoreGraphicsState()
            let jpeg = try XCTUnwrap(out.representation(using: .jpeg, properties: [.compressionFactor: 0.72]))
            try jpeg.write(to: resources.appendingPathComponent("\(name).jpg"))
            print("GUIDE-PICTURE: \(name).jpg \(jpeg.count / 1024) KB")
        }
        let properties = VideoEditorPanelLayout.standard.properties
        let timelineTop = size.height - VideoEditorLayout.timelineHeight(windowHeight: size.height, fraction: VideoEditorLayout.defaultFraction(windowHeight: size.height))
        // The whole editor.
        model.propertiesTab = .clip
        try await picture(VideoEditorRootView(model: model), name: "guide-editor-layout", crop: nil, width: 1100)
        // Properties ▸ Effects.
        model.propertiesTab = .effects
        try await picture(VideoEditorRootView(model: model), name: "guide-effect-chain", crop: CGRect(x: size.width - properties, y: 45, width: properties, height: timelineTop - 45), width: properties * 1.5)
        // Properties ▸ Captions.
        model.propertiesTab = .captions
        try await picture(VideoEditorRootView(model: model), name: "guide-caption-list", crop: CGRect(x: size.width - properties, y: 45, width: properties, height: timelineTop - 45), width: properties * 1.5)
        // The timeline with the curve lane.
        model.propertiesTab = .clip
        try await picture(VideoEditorRootView(model: model), name: "guide-curve-lane", crop: CGRect(x: 0, y: timelineTop, width: 900, height: size.height - timelineTop - 26), width: 900)
        // ⌘K with something typed.
        try await picture(ZStack { VideoEditorRootView(model: model); VideoCommandPalette(model: model, query: "clip") }, name: "guide-search", crop: CGRect(x: (size.width - 560) / 2, y: 80, width: 560, height: 470), width: 840)
    }

    /// The screenshots page: the new layout's Properties tabs and ⌘K, and
    /// CapCut style, in both looks, English and German, large and 13".
    func testEveryStateInBothLooksAndLanguagesAtTwoSizes() async throws {
        let sizes: [(String, CGSize)] = [("large", CGSize(width: 1920, height: 1200)), ("13-inch", CGSize(width: 1280, height: 772))]
        for language in ["en", "de"] {
            L10n.use(language)
            let model = try await demoModel()
            if let title = model.selectedLayerItem, let track = model.project.layerTrackIndex(of: title.id) {
                model.mutate { $0.layerTracks[track].items = $0.layerTracks[track].items.map { var i = $0; if i.id == title.id { i.effects = [VideoAppliedEffect(kind: .glow), VideoAppliedEffect(kind: .vhs)] }; return i } }
                model.curveLanes[model.project.layerTracks[track].id] = .opacity
            }
            model.mutate { $0.captions = VideoCaptionBuilder.lines(from: [VideoCaptionWord(text: "Open", start: 0.5, end: 0.9), VideoCaptionWord(text: "the settings.", start: 0.9, end: 1.6), VideoCaptionWord(text: "Save.", start: 6, end: 6.5)]) }
            for (sizeName, size) in sizes {
                for (lookName, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    let suffix = "\(language)-\(lookName)-\(sizeName)"
                    style(.lfStudios)
                    for tab in VideoPropertiesTab.allCases {
                        model.propertiesTab = tab
                        try await render(VideoEditorRootView(model: model), size: size, look: look, name: "new-\(tab.rawValue)-\(suffix)")
                    }
                    model.propertiesTab = .clip
                    try await render(ZStack { VideoEditorRootView(model: model); VideoCommandPalette(model: model, query: language == "de" ? "Clip" : "clip") }, size: size, look: look, name: "new-search-\(suffix)")
                    style(.capCut)
                    try await render(VideoEditorRootView(model: model), size: size, look: look, name: "capcut-\(suffix)")
                }
            }
        }
    }
}

