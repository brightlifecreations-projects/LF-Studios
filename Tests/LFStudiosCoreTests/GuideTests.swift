import AppKit
import XCTest
@testable import LFStudiosCore

/// Home ▸ Guide (App/GuideContent.swift): every page is complete, every
/// link and Show me leads somewhere, every shortcut in the app is on the
/// Keyboard shortcuts page, and Show me never changes a setting.
@MainActor
final class GuideTests: XCTestCase {
    private var suiteName: String!

    override func setUp() async throws {
        _ = NSApplication.shared
        suiteName = "LFStudiosCoreTests.Guide.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        L10n.use("en")
    }

    override func tearDown() async throws {
        L10n.use(nil)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
    }

    private var chapters: [GuideChapter] { GuideContent.chapters() }
    private var allEntries: [GuideEntry] { chapters.flatMap(\.entries) }
    private var features: [GuideEntry] { chapters.first { $0.id == .features }!.entries }

    // MARK: Pages

    func testEveryChapterIsThere() {
        XCTAssertEqual(chapters.map(\.id), GuideChapterID.allCases)
        for chapter in chapters where chapter.id != .shortcuts {
            XCTAssertFalse(chapter.entries.isEmpty, "\(chapter.id) has no pages")
        }
    }

    func testEveryFeatureHasANameADescriptionAndWhereToFindIt() {
        XCTAssertGreaterThan(features.count, 140)
        for entry in features {
            XCTAssertFalse(entry.title.isEmpty, entry.id)
            XCTAssertFalse(entry.summary.isEmpty, entry.id)
            XCTAssertFalse(entry.location?.isEmpty ?? true, "\(entry.id) doesn't say where to find it")
        }
    }

    func testEveryOtherPageHasANameADescriptionAndSomethingToDo() {
        for entry in allEntries {
            XCTAssertFalse(entry.title.isEmpty, entry.id)
            XCTAssertFalse(entry.summary.isEmpty, entry.id)
            let says = entry.location != nil || !entry.steps.isEmpty || !entry.points.isEmpty || !entry.tips.isEmpty
            XCTAssertTrue(says, "\(entry.id) only has a summary")
        }
    }

    func testPageIDsAreUniqueAndEveryLinkLeadsToAPage() {
        var ids = Set<String>()
        // What's new lists feature pages again; every other page is in one place.
        for chapter in chapters where chapter.id != .whatsNew {
            for entry in chapter.entries {
                XCTAssertTrue(ids.insert(entry.id).inserted, "\(entry.id) is there twice")
            }
        }
        for entry in allEntries {
            for link in entry.related {
                XCTAssertTrue(ids.contains(link), "\(entry.id) links to \(link), which isn't a page")
            }
            if case .page(let id) = entry.showMe {
                XCTAssertTrue(ids.contains(id), "\(entry.id) shows \(id), which isn't a page")
            }
        }
    }

    func testEverySymbolExists() {
        var symbols = chapters.map(\.symbol) + chapters.flatMap(\.categories).map(\.symbol) + allEntries.map(\.symbol)
        symbols += GuideContent.shortcutGroups().map(\.symbol)
        for symbol in Set(symbols) {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "No SF Symbol named \(symbol)")
        }
    }

    func testEveryStepAndTipIsShort() {
        // Short paragraphs, no walls of text.
        for entry in allEntries {
            for text in [entry.summary] + entry.points + entry.steps + entry.tips {
                XCTAssertLessThan(text.count, 300, "\(entry.id): “\(text.prefix(40))…” is too long")
            }
        }
    }

    // MARK: What's new

    func testWhatsNewListsTheNewestFeaturesWithANewBadge() throws {
        let whatsNew = try XCTUnwrap(chapters.first { $0.id == .whatsNew })
        let listed = Set(whatsNew.entries.map(\.id))
        XCTAssertEqual(GuideContent.newVersions.first, "1.6.0", "the newest version first")
        XCTAssertTrue(listed.contains("rec-folder"))
        XCTAssertTrue(listed.contains("project-folder"))
        XCTAssertTrue(listed.contains("app-guide"))
        XCTAssertFalse(listed.contains("camera-face"), "older versions' pages leave What's new")
        for entry in features {
            XCTAssertEqual(entry.isNew, listed.contains(entry.id), entry.id)
        }
        XCTAssertFalse(try XCTUnwrap(features.first { $0.id == "shot-area" }).isNew)
    }

    // MARK: Search

    func testSearchLooksThroughNamesDescriptionsAndSteps() {
        let model = GuideModel()
        XCTAssertEqual(model.search("keep face centered").first?.id, "camera-face")
        // A word only in a step.
        XCTAssertTrue(model.search("Restore size").contains { $0.id == "rec-window-size" })
        // Every word must match, in any order.
        XCTAssertTrue(model.search("blur strength").contains { $0.id == "privacy-blur" })
        XCTAssertTrue(model.search("zzqx nothing").isEmpty)
        XCTAssertTrue(model.search("  ").isEmpty)
    }

    func testOpeningAPageFromSearchAndGoingBack() {
        let model = GuideModel()
        model.query = "loupe"
        model.open(.entry("zoom-loupe"))
        XCTAssertEqual(model.page, .entry("zoom-loupe"))
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.selectedCategory, "zoom")
        model.back()
        XCTAssertEqual(model.page, .chapter(.gettingStarted))
        model.jump(to: .category("camera"))
        XCTAssertTrue(model.history.isEmpty)
    }

    // MARK: Keyboard shortcuts

    private var shortcutsPage: [GuideKey] { GuideContent.shortcutGroups().flatMap(\.keys) }

    private var fixedKeysOnThePage: Set<String> {
        Set(shortcutsPage.compactMap { key in
            if case .fixed(let text) = key.keys { return text }
            return nil
        })
    }

    func testEveryShortcutThatWorksInAnyAppIsOnTheShortcutsPage() {
        let listed = Set(shortcutsPage.compactMap { key -> LFStudiosShortcut? in
            if case .global(let shortcut) = key.keys { return shortcut }
            return nil
        })
        XCTAssertEqual(listed, Set(LFStudiosShortcut.allCases))
        XCTAssertTrue(fixedKeysOnThePage.contains(RecordingStopHotkey.displayText))
    }

    func testTheShortcutsPageShowsTheKeysSetNowOrNotSet() {
        // The live binding, as Settings ▸ Shortcuts shows it (nil: not set).
        for shortcut in LFStudiosShortcut.allCases {
            XCTAssertEqual(GuideKey.global(shortcut).currentKeys, shortcut.displayShortcut)
        }
        XCTAssertEqual(GuideKey.fixed("⌘E", "Export").currentKeys, "⌘E")
    }

    /// The app's menu bar, built once: its File menu shares one Recent
    /// Exports submenu, which can't go into two menus.
    private static var builtMenu: (main: NSMenu, help: NSMenu?)?

    private func appMenu() throws -> (main: NSMenu, help: NSMenu?) {
        if let builtMenu = Self.builtMenu { return builtMenu }
        let previous = NSApp.mainMenu
        defer { NSApp.mainMenu = previous }
        AppDelegate().setupMainMenu()
        let built = (main: try XCTUnwrap(NSApp.mainMenu), help: NSApp.helpMenu)
        Self.builtMenu = built
        return built
    }

    func testEveryMenuShortcutIsOnTheShortcutsPage() throws {
        let menu = try appMenu().main
        var missing: [String] = []
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { walk(submenu) }
                guard !item.keyEquivalent.isEmpty else { continue }
                let keys = Self.display(item.keyEquivalent, item.keyEquivalentModifierMask)
                if !fixedKeysOnThePage.contains(keys) { missing.append("\(item.title) \(keys)") }
            }
        }
        walk(menu)
        XCTAssertEqual(missing, [], "Menu shortcuts missing from the Guide")
        XCTAssertTrue(fixedKeysOnThePage.contains("⌘?"))
    }

    func testTheHelpMenuOpensTheGuideWithCommandQuestionMark() throws {
        let help = try XCTUnwrap(try appMenu().help)
        let item = try XCTUnwrap(help.items.first)
        XCTAssertEqual(item.title, "LF Studios Guide")
        XCTAssertEqual(item.keyEquivalent, "?")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
    }

    func testEveryEditorShortcutIsOnTheShortcutsPage() {
        for (_, keys) in VideoShortcutsSheet.groups {
            for (key, _) in keys {
                XCTAssertTrue(fixedKeysOnThePage.contains(key), "Video editor key \(key) is missing")
            }
        }
        for tool in AnnotationTool.allCases {
            XCTAssertTrue(fixedKeysOnThePage.contains(tool.shortcutLabel), "Screenshot editor key \(tool.shortcutLabel) is missing")
        }
    }

    /// A menu item's keys as the Guide writes them ("⇧⌘S", "⌫", "S").
    private static func display(_ key: String, _ modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch key {
        case "\u{8}", "\u{7F}": text += "⌫"
        case "\r": text += "↩"
        default: text += key.uppercased()
        }
        return text
    }

    // MARK: Show me

    private func home() -> HomeModel {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("LFStudiosCoreTests.Guide.\(UUID().uuidString)", isDirectory: true)
        return HomeModel(historyManager: HistoryManager(storageDir: storage), actions: HomeActions(newRecording: {}, takeScreenshot: {}, scrollCapture: {}, openVideo: {}))
    }

    func testEveryShowMeLeadsSomewhereThatExists() {
        let destinations = allEntries.compactMap(\.showMe)
        XCTAssertGreaterThan(destinations.count, 60)
        for destination in destinations {
            switch destination {
            case .settings(let tab):
                XCTAssertTrue(PreferencesTab.allCases.contains(tab))
            case .systemSettings(let pane):
                let url = pane.url
                XCTAssertNotNil(url, "\(pane)")
                XCTAssertEqual(url?.scheme, "x-apple.systempreferences")
                XCTAssertNotNil(url.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }, "Nothing opens \(pane)")
            case .home(let section):
                XCTAssertTrue(HomeSection.allCases.contains(section))
            case .editor(let tab):
                XCTAssertTrue(VideoEditorModel.InspectorTab.allCases.contains(tab))
            case .page(let id):
                XCTAssertNotNil(GuideModel().entry(id))
            case .history:
                break
            }
        }
    }

    func testShowMeGoesToTheRightPlaceInHome() {
        let model = home()
        model.section = .guide
        GuideNavigator.go(to: .settings(.recording), home: model)
        XCTAssertEqual(model.section, .settings)
        XCTAssertEqual(model.preferencesSelection.selectedTab, .recording)
        GuideNavigator.go(to: .home(.screenshots), home: model)
        XCTAssertEqual(model.section, .screenshots)
        GuideNavigator.go(to: .page("camera-face"), home: model)
        XCTAssertEqual(model.section, .guide)
        XCTAssertEqual(model.guide.page, .entry("camera-face"))
        var openedHistory = false
        let withHistory = HomeModel(historyManager: model.historyManager, actions: HomeActions(newRecording: {}, takeScreenshot: {}, scrollCapture: {}, openVideo: {}, openHistory: { openedHistory = true }))
        GuideNavigator.go(to: .history, home: withHistory)
        XCTAssertTrue(openedHistory)
    }

    func testShowMeNeverChangesASetting() {
        let model = home()
        Settings.defaults.set(true, forKey: "guide-test-marker")
        let before = Settings.defaults.dictionaryRepresentation() as NSDictionary
        for entry in allEntries {
            guard let destination = entry.showMe else { continue }
            switch destination {
            case .systemSettings, .history: continue // other apps and windows
            case .editor:
                // No editor is open: Show me is off, and does nothing.
                XCTAssertFalse(GuideModel.isAvailable(destination))
            default: break
            }
            GuideNavigator.go(to: destination, home: model)
        }
        XCTAssertEqual(Settings.defaults.dictionaryRepresentation() as NSDictionary, before)
    }

    func testTheGuideIsInTheSidebarBelowSettings() {
        XCTAssertEqual(HomeSection.allCases.suffix(2), [.settings, .guide])
        XCTAssertEqual(HomeSection.guide.title, "Guide")
    }
}
