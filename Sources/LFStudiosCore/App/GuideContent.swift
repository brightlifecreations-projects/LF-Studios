import Foundation

// Everything the Guide says, in one place (Home ▸ Guide, Help ▸ LF Studios
// Guide). It's written for people who just installed LF Studios: plain
// words, short steps, no technical terms. Every new or changed feature
// adds or updates its page here in the same commit. Pages name the
// buttons exactly as the app labels them, and keys come from the live
// shortcuts, so a changed shortcut shows as the user set it.
//
// A page: `id` (stable; other pages link to it), an SF Symbol, the name,
// what it does, where to find it, steps, keys, tips ("Good to know"),
// "Show me" (only goes somewhere; it never turns anything on), the version
// that brought it, and related pages.

@MainActor
enum GuideContent {
    /// Pages from these versions get a New badge and fill What's new.
    nonisolated static let newVersions: [String] = ["1.5.0", "1.4.1", "1.4.0"]

    static func chapters() -> [GuideChapter] {
        let features = featureCategories()
        return [
            GuideChapter(id: .gettingStarted, title: L("Getting started"), symbol: "flag.checkered",
                         intro: L("New to LF Studios? Start here: it takes about five minutes."),
                         categories: [GuideCategory(id: "getting-started", title: L("Getting started"), symbol: "flag.checkered", entries: gettingStarted())]),
            GuideChapter(id: .howTo, title: L("How do I…?"), symbol: "questionmark.circle",
                         intro: L("Short recipes for the things people do most."),
                         categories: [GuideCategory(id: "how-to", title: L("How do I…?"), symbol: "questionmark.circle", entries: howTo())]),
            GuideChapter(id: .features, title: L("All features"), symbol: "square.grid.2x2",
                         intro: L("Everything LF Studios can do, section by section. Effects start off: each one is turned on by its own button or switch."),
                         categories: features),
            GuideChapter(id: .shortcuts, title: L("Keyboard shortcuts"), symbol: "keyboard",
                         intro: L("Every shortcut, with the keys set on this Mac right now. Shortcuts that work in any app can be changed in Settings ▸ Shortcuts.")),
            GuideChapter(id: .privacy, title: L("Privacy"), symbol: "lock.shield",
                         intro: L("What LF Studios keeps, and what it never does."),
                         categories: [GuideCategory(id: "privacy", title: L("Privacy"), symbol: "lock.shield", entries: privacy())]),
            GuideChapter(id: .troubleshooting, title: L("Troubleshooting"), symbol: "wrench.and.screwdriver",
                         intro: L("Something not working? Find the problem, then try the fixes in order."),
                         categories: [GuideCategory(id: "troubleshooting", title: L("Troubleshooting"), symbol: "wrench.and.screwdriver", entries: troubleshooting())]),
            GuideChapter(id: .whatsNew, title: L("What's new"), symbol: "sparkles",
                         intro: L("New in the latest versions. Click one to read how it works."),
                         categories: whatsNew(from: features)),
        ]
    }

    /// The newest versions' pages, newest first.
    static func whatsNew(from categories: [GuideCategory]) -> [GuideCategory] {
        let entries = categories.flatMap(\.entries)
        return newVersions.compactMap { version in
            let new = entries.filter { $0.since == version }
            guard !new.isEmpty else { return nil }
            return GuideCategory(id: "new-\(version)", title: L("New in LF Studios \(version)"), symbol: "sparkles", entries: new)
        }
    }

    /// A page's name, for links between pages.
    static func title(of id: String) -> String {
        chapters().flatMap(\.entries).first { $0.id == id }?.title ?? id
    }

    // MARK: - Getting started

    static func gettingStarted() -> [GuideEntry] {
        let area = LFStudiosShortcut.captureArea.displayShortcut
        return [
            GuideEntry(
                id: "welcome", symbol: "sparkles", title: L("What LF Studios does"),
                summary: L("LF Studios takes screenshots, records your screen, and turns your recordings into polished videos. Mark up a screenshot in seconds, or record yourself with your voice and camera, then cut, zoom, add captions, and export."),
                points: [
                    L("Everything happens on your Mac. Nothing is uploaded."),
                    L("LF Studios lives in the Dock and in the menu bar. Closing this window keeps it running, so your shortcuts keep working."),
                    L("Click the LF Studios icon in the Dock to bring this window back."),
                ]
            ),
            GuideEntry(
                id: "home-window", symbol: "house", title: L("The Home window"),
                summary: L("Home is where you start something new and find everything you made."),
                points: [
                    L("The sidebar on the left: Home, Recordings, Screenshots, Settings, and this Guide."),
                    L("New recording records an area of the screen, a window, or the whole screen."),
                    L("Take screenshot captures an area. Scroll capture captures a long page, and Open video… opens a video in the editor."),
                    L("Projects shows your recordings, screenshots, and saved projects, newest first. Click one to open it. Right-click for Show in Finder, Creative Handoff…, or Delete."),
                    L("The search box finds projects by name, and screenshots by the text in them."),
                ],
                showMe: .home(.home),
                related: ["home-projects"]
            ),
            GuideEntry(
                id: "permission-screen", symbol: "rectangle.dashed.badge.record", title: L("Allow Screen Recording"),
                summary: L("Needed for every screenshot and every recording. Without it, LF Studios can only see your wallpaper."),
                steps: [
                    L("Click Open System Settings below."),
                    L("In Privacy & Security ▸ Screen & System Audio Recording, turn on LF Studios."),
                    L("If macOS asks, click Quit & Reopen, so LF Studios can use it."),
                ],
                tips: [L("macOS asks once, the first time you take a screenshot. You can also allow it here first.")],
                showMe: .systemSettings(.screenRecording),
                related: ["trouble-black"]
            ),
            GuideEntry(
                id: "permission-accessibility", symbol: "accessibility", title: L("Allow Accessibility (optional)"),
                summary: L("Lets LF Studios show the shortcuts you press in a video, follow where you type, and resize a window to an exact size. Everything else works without it."),
                steps: [
                    L("Click Open System Settings below."),
                    L("In Privacy & Security ▸ Accessibility, turn on LF Studios."),
                    L("Come back to LF Studios: the option you picked turns on by itself."),
                ],
                tips: [L("LF Studios never records what you type. See Privacy for exactly what these options save.")],
                showMe: .systemSettings(.accessibility),
                related: ["privacy-typing"]
            ),
            GuideEntry(
                id: "permission-microphone", symbol: "mic", title: L("Allow the microphone"),
                summary: L("Needed to record your voice."),
                steps: [
                    L("Turn on Microphone in the recording bar. macOS asks once: click Allow."),
                    L("Clicked Don't Allow by mistake? Click Open System Settings below and turn on LF Studios under Microphone."),
                ],
                tips: [L("LF Studios shows up in that list only after it has asked once.")],
                showMe: .systemSettings(.microphone),
                related: ["trouble-no-sound"]
            ),
            GuideEntry(
                id: "permission-camera", symbol: "camera", title: L("Allow the camera"),
                summary: L("Needed to show yourself in a bubble while you record."),
                steps: [
                    L("Turn on Camera in the recording bar. macOS asks once: click Allow."),
                    L("Clicked Don't Allow by mistake? Click Open System Settings below and turn on LF Studios under Camera."),
                ],
                tips: [L("LF Studios shows up in that list only after it has asked once.")],
                showMe: .systemSettings(.camera)
            ),
            GuideEntry(
                id: "first-screenshot", symbol: "camera.viewfinder", title: L("Your first screenshot"),
                summary: L("Capture part of your screen and mark it up."),
                steps: [
                    area.map { L("Press \($0), or click Take screenshot in Home.") } ?? L("Click Take screenshot in Home."),
                    L("Drag over the part of the screen you want, then let go."),
                    L("Your screenshot is saved in History and in Home ▸ Screenshots."),
                    L("Click it in Home to open the screenshot editor: add arrows, text, blur, and more, then click Copy or Save."),
                ],
                keys: [.global(.captureArea)],
                tips: [L("Want a preview, a copy on the clipboard, or a saved file after every shot? Turn them on in Settings ▸ General ▸ After Capture.")],
                showMe: .home(.screenshots),
                related: ["howto-area", "editor-open"]
            ),
            GuideEntry(
                id: "first-recording", symbol: "record.circle", title: L("Your first recording, edit, and export"),
                summary: L("Record a short demo, tidy it up, and save it as a video."),
                steps: [
                    L("Click New recording in Home, then drag over the area you want to record."),
                    L("In the recording bar, turn on Microphone (and Camera, if you like), then click Record or press Return."),
                    L("Do your demo. When you're done, click the red stop button or press ⌃⌘Esc."),
                    L("Click Edit Video in the “Recording saved” panel. The video editor opens."),
                    L("To cut a mistake, move the playhead to it, press S to split, click the bad part, and press ⌫."),
                    L("Click Export (or press ⌘E), choose MP4, and click Export…."),
                ],
                keys: [.fixed("⌃⌘Esc", L("Stop recording, from any app")), .fixed("⌘E", L("Export"))],
                tips: [L("A new recording opens just as you recorded it. Zooms, backgrounds, and effects stay off until you turn them on.")],
                related: ["howto-record", "howto-cut", "howto-zoom", "howto-captions"]
            ),
        ]
    }

    // MARK: - How do I…?

    static func howTo() -> [GuideEntry] {
        []
    }

    // MARK: - All features

    static func featureCategories() -> [GuideCategory] {
        []
    }

    // MARK: - Privacy

    static func privacy() -> [GuideEntry] {
        []
    }

    // MARK: - Troubleshooting

    static func troubleshooting() -> [GuideEntry] {
        []
    }

    // MARK: - Keyboard shortcuts

    static func shortcutGroups() -> [GuideShortcutGroup] {
        []
    }
}

/// One box on the Keyboard shortcuts page.
struct GuideShortcutGroup {
    let title: String
    let symbol: String
    var note: String?
    let keys: [GuideKey]
}
