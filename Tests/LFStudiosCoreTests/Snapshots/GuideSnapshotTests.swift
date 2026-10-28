import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// Home ▸ Guide in English and German (the longest), light and dark, at the
/// Home window's size and its smallest size. Printed as SNAPSHOT-GUIDE:
/// <path> (in $LFSTUDIOS_GUIDE_SNAPSHOTS or a temporary folder) to look
/// through.
@MainActor
final class GuideSnapshotTests: XCTestCase {
    private static let looks: [(name: String, appearance: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
    private var suiteName: String!

    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        suiteName = "LFStudiosCoreTests.GuideSnapshots.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        L10n.use(nil)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
    }

    private static var folder: URL {
        get throws {
            let path = ProcessInfo.processInfo.environment["LFSTUDIOS_GUIDE_SNAPSHOTS"]
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-guide-snapshots").path
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    /// The pages worth looking at: one of each kind.
    private static let pages: [(name: String, page: GuidePage)] = [
        ("getting-started", .chapter(.gettingStarted)),
        ("recipe", .entry("howto-captions")),
        ("feature", .entry("camera-face")),
        ("features", .chapter(.features)),
        ("category", .category("recording")),
        ("shortcuts", .chapter(.shortcuts)),
        ("privacy", .chapter(.privacy)),
        ("troubleshooting", .chapter(.troubleshooting)),
        ("trouble", .entry("trouble-black")),
        ("whats-new", .chapter(.whatsNew)),
    ]

    func testRenderTheGuide() async throws {
        for language in ["en", "de"] {
            L10n.use(language)
            for (name, page) in Self.pages {
                let model = home()
                model.section = .guide
                model.guide.open(page)
                try await render(HomeRootView(model: model), size: CGSize(width: 1120, height: 740), name: "guide-\(language)-\(name)")
            }
            let small = home()
            small.section = .guide
            small.guide.open(.entry("rec-window-size"))
            try await render(HomeRootView(model: small), size: CGSize(width: 880, height: 580), name: "guide-\(language)-smallest")
            let search = home()
            search.section = .guide
            search.guide.query = language == "de" ? "Kamera" : "camera"
            try await render(HomeRootView(model: search), size: CGSize(width: 1120, height: 740), name: "guide-\(language)-search")
        }
    }

    /// Every page in English and German, full length, light only: to read
    /// through for cut-off or overlapping text.
    func testRenderEveryPageFullLength() async throws {
        guard ProcessInfo.processInfo.environment["LFSTUDIOS_GUIDE_ALL_PAGES"] == "1" else { return }
        for language in ["en", "de"] {
            L10n.use(language)
            let ids = GuideModel().chapters.flatMap(\.entries).map(\.id)
            for id in Set(ids).sorted() {
                let model = GuideModel()
                model.open(.entry(id))
                let page = GuidePageProbe(model: model).frame(width: 700)
                let host = NSHostingView(rootView: page)
                let height = max(200, host.fittingSize.height)
                try await render(page, size: CGSize(width: 700, height: height), name: "page-\(language)-\(id)", looks: [Self.looks[0]])
            }
        }
    }

    private func home() -> HomeModel {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("LFStudiosCoreTests.GuideSnapshots.\(UUID().uuidString)", isDirectory: true)
        return HomeModel(historyManager: HistoryManager(storageDir: storage), actions: HomeActions(newRecording: {}, takeScreenshot: {}, scrollCapture: {}, openVideo: {}))
    }

    private func render<V: View>(_ view: V, size: CGSize, name: String, looks: [(name: String, appearance: NSAppearance.Name)] = looks) async throws {
        for look in looks {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: look.appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 200_000_000)
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = try Self.folder.appendingPathComponent("\(name)-\(look.name).png")
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
            print("SNAPSHOT-GUIDE: \(url.path)")
            window.contentView = nil
        }
    }
}
