import AppKit
import AVFoundation
import SwiftUI

// The Guide: Home's help for people new to LF Studios. Its words live in
// GuideContent.swift; this file has the types they're made of, and what
// "Show me" does. "Show me" only goes somewhere: it never turns anything on.

enum GuideChapterID: String, CaseIterable {
    case gettingStarted
    case howTo
    case features
    case shortcuts
    case privacy
    case troubleshooting
    case whatsNew
}

struct GuideChapter: Identifiable {
    let id: GuideChapterID
    let title: String
    let symbol: String
    var intro: String?
    var categories: [GuideCategory] = []

    var entries: [GuideEntry] { categories.flatMap(\.entries) }
}

/// A group of pages: a feature section ("Screenshots"), or a chapter's only
/// group (Getting started).
struct GuideCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let entries: [GuideEntry]
}

/// One page of the Guide.
struct GuideEntry: Identifiable {
    let id: String
    let symbol: String
    let title: String
    /// What it does, in a sentence or two.
    let summary: String
    /// "In the video editor, open the Camera panel…"
    var location: String?
    /// A short list right under the summary (no numbers).
    var points: [String] = []
    var steps: [String] = []
    var keys: [GuideKey] = []
    /// Good to know: tips and what it needs.
    var tips: [String] = []
    var showMe: GuideDestination?
    /// The version that brought it ("1.4.0"); the newest get a New badge.
    var since: String?
    /// Other pages worth reading next.
    var related: [String] = []

    /// Everything search looks through.
    var searchText: String {
        ([title, summary, location ?? ""] + points + steps + tips + keys.map(\.label)).joined(separator: "\n")
    }

    var isNew: Bool {
        guard let since else { return false }
        return GuideContent.newVersions.contains(since)
    }
}

struct GuideKey: Hashable {
    enum Keys: Hashable {
        /// A shortcut the user can change: shows the current one.
        case global(LFStudiosShortcut)
        /// Keys that are always the same ("⌘E").
        case fixed(String)
    }

    let keys: Keys
    let label: String

    static func global(_ shortcut: LFStudiosShortcut, _ label: String? = nil) -> GuideKey {
        GuideKey(keys: .global(shortcut), label: label ?? shortcut.title)
    }

    static func fixed(_ keys: String, _ label: String) -> GuideKey {
        GuideKey(keys: .fixed(keys), label: label)
    }

    /// The keys as they are now; nil for a shortcut nobody has set.
    @MainActor
    var currentKeys: String? {
        switch keys {
        case .global(let shortcut): return shortcut.displayShortcut
        case .fixed(let text): return text
        }
    }
}

/// Where "Show me" goes.
enum GuideDestination: Hashable {
    case settings(PreferencesTab)
    case systemSettings(GuideSystemPane)
    case history
    case home(HomeSection)
    /// A tab of the video editor that's already open.
    case editor(VideoEditorModel.InspectorTab)
    /// Another page of the Guide.
    case page(String)
}

/// The System Settings pages LF Studios needs.
enum GuideSystemPane: String, CaseIterable {
    case screenRecording
    case accessibility
    case microphone
    case camera
    case speechRecognition
    case keyboard

    var url: URL? {
        switch self {
        case .screenRecording: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .accessibility: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .microphone: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .camera: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        case .speechRecognition: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .keyboard: return URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        }
    }

    /// Whether LF Studios has the permission now (nil: not a permission).
    /// Only reads it; never asks.
    var isAllowed: Bool? {
        switch self {
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .accessibility: return AXIsProcessTrusted()
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .camera: return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        case .speechRecognition, .keyboard: return nil
        }
    }
}

enum GuidePage: Hashable {
    case chapter(GuideChapterID)
    case category(String)
    case entry(String)
}

@MainActor
final class GuideModel: ObservableObject {
    @Published private(set) var page: GuidePage = .chapter(.gettingStarted)
    @Published var query = ""
    @Published private(set) var history: [GuidePage] = []

    let chapters: [GuideChapter]
    private let entriesByID: [String: GuideEntry]
    private let categoriesByID: [String: (GuideCategory, GuideChapterID)]

    /// Where Show me's other places are; Home hands it in.
    var navigate: (GuideDestination) -> Void = { _ in }

    init(chapters: [GuideChapter]? = nil) {
        let chapters = chapters ?? GuideContent.chapters()
        self.chapters = chapters
        var entries: [String: GuideEntry] = [:]
        var categories: [String: (GuideCategory, GuideChapterID)] = [:]
        for chapter in chapters {
            for category in chapter.categories {
                categories[category.id] = (category, chapter.id)
                for entry in category.entries where entries[entry.id] == nil {
                    entries[entry.id] = entry
                }
            }
        }
        entriesByID = entries
        categoriesByID = categories
    }

    func chapter(_ id: GuideChapterID) -> GuideChapter? {
        chapters.first { $0.id == id }
    }

    func entry(_ id: String) -> GuideEntry? {
        entriesByID[id]
    }

    func category(_ id: String) -> GuideCategory? {
        categoriesByID[id]?.0
    }

    /// The feature section a page belongs to (for its back button).
    func category(containing entryID: String) -> GuideCategory? {
        chapters.lazy.flatMap(\.categories).first { $0.entries.contains { $0.id == entryID } }
    }

    /// The chapter the outline marks for the page showing.
    var selectedChapter: GuideChapterID {
        switch page {
        case .chapter(let id): return id
        case .category(let id): return categoriesByID[id]?.1 ?? .features
        case .entry(let id):
            if let back = history.last, case .chapter(let chapter) = back { return chapter }
            return chapters.first { $0.entries.contains { $0.id == id } }?.id ?? .features
        }
    }

    var selectedCategory: String? {
        switch page {
        case .category(let id): return id
        case .entry(let id): return category(containing: id)?.id
        case .chapter: return nil
        }
    }

    func open(_ page: GuidePage) {
        guard page != self.page else { query = ""; return }
        history.append(self.page)
        self.page = page
        query = ""
    }

    /// From the outline: a fresh start, no back steps.
    func jump(to page: GuidePage) {
        history = []
        self.page = page
        query = ""
    }

    func back() {
        guard let previous = history.popLast() else { return }
        page = previous
    }

    /// Pages whose name, words, steps, or tips hold every word typed.
    func search(_ text: String) -> [GuideEntry] {
        let terms = text.split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        var seen = Set<String>()
        var titleHits: [GuideEntry] = []
        var otherHits: [GuideEntry] = []
        for entry in chapters.flatMap(\.entries) where seen.insert(entry.id).inserted {
            let haystack = entry.searchText
            guard terms.allSatisfy({ haystack.localizedStandardContains($0) }) else { continue }
            if terms.allSatisfy({ entry.title.localizedStandardContains($0) }) {
                titleHits.append(entry)
            } else {
                otherHits.append(entry)
            }
        }
        return titleHits + otherHits
    }

    func show(_ destination: GuideDestination) {
        if case .page(let id) = destination {
            open(.entry(id))
        } else {
            navigate(destination)
        }
    }

    /// Whether "Show me" can go there now: an editor tab needs an open editor.
    static func isAvailable(_ destination: GuideDestination) -> Bool {
        if case .editor = destination { return VideoDemoEditorWindowController.hasOpenEditors }
        return true
    }
}

/// What "Show me" does outside the Guide. Each case only brings a window
/// forward or opens a page; nothing is switched on or changed.
@MainActor
enum GuideNavigator {
    static func go(to destination: GuideDestination, home: HomeModel) {
        switch destination {
        case .settings(let tab):
            home.preferencesSelection.selectedTab = tab
            home.section = .settings
        case .systemSettings(let pane):
            if let url = pane.url { NSWorkspace.shared.open(url) }
        case .history:
            home.actions.openHistory()
        case .home(let section):
            home.section = section
        case .editor(let tab):
            VideoDemoEditorWindowController.showOpenEditor(on: tab)
        case .page(let id):
            home.section = .guide
            home.guide.open(.entry(id))
        }
    }
}
