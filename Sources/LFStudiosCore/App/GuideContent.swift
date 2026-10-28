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
        let area = LFStudiosShortcut.captureArea.displayShortcut
        let window = LFStudiosShortcut.captureWindow.displayShortcut
        return [
            GuideEntry(
                id: "howto-area", symbol: "rectangle.dashed", title: L("Take a screenshot of an area"),
                summary: L("Capture just the part of the screen you need."),
                steps: [
                    area.map { L("Press \($0), or click Take screenshot in Home.") } ?? L("Click Take screenshot in Home."),
                    L("Drag over the area you want, then let go."),
                    L("Want to fine-tune it first? Hold ⇧ as you let go, adjust the edges, then press Return."),
                    L("Find the screenshot in Home ▸ Screenshots or in History."),
                ],
                keys: [.global(.captureArea)],
                related: ["shot-area", "shot-selecting", "editor-open"]
            ),
            GuideEntry(
                id: "howto-window", symbol: "macwindow", title: L("Take a screenshot of a window"),
                summary: L("Capture one window on its own, with a soft shadow."),
                steps: [
                    window.map { L("Press \($0), or open the LF Studios menu in the menu bar and choose Capture Window.") } ?? L("Open the LF Studios menu in the menu bar and choose Capture Window."),
                    L("Move the pointer over the window you want: it lights up."),
                    L("Click it."),
                ],
                keys: [.global(.captureWindow)],
                tips: [L("Windows in front of it don't get in the way: only the window you click is captured.")],
                related: ["shot-window"]
            ),
            GuideEntry(
                id: "howto-scrolling", symbol: "scroll", title: L("Capture a whole scrolling page"),
                summary: L("Capture a long web page or document in one tall picture."),
                steps: [
                    L("Click Scroll capture in Home, or choose Scrolling Capture in the LF Studios menu."),
                    L("Drag over the part of the window that scrolls."),
                    L("Scroll down slowly. LF Studios stitches the page together as you go."),
                    L("Click Done, or press Esc, when you reach the end."),
                ],
                keys: [.global(.captureScrolling)],
                tips: [L("If it says you scrolled too fast, scroll back up a little and carry on more slowly.")],
                related: ["shot-scrolling"]
            ),
            GuideEntry(
                id: "howto-copy-text", symbol: "text.viewfinder", title: L("Copy text from the screen"),
                summary: L("Copy text you can see but can't select, like text in a picture or a video."),
                steps: [
                    L("Open the LF Studios menu in the menu bar and choose Capture Text."),
                    L("Drag over the text."),
                    L("The text is now on the clipboard: paste it anywhere with ⌘V."),
                    L("If it found links or a table, click the notice to open them, or to copy the table for a spreadsheet."),
                ],
                keys: [.global(.captureText)],
                related: ["text-capture", "text-window"]
            ),
            GuideEntry(
                id: "howto-record", symbol: "person.wave.2", title: L("Record my screen with my voice and camera"),
                summary: L("Record a demo with your voice and your face in a bubble."),
                steps: [
                    L("Click New recording in Home and drag over the area to record. For a window or the whole screen, use Record Window or Record Fullscreen in the LF Studios menu."),
                    L("In the recording bar, turn on Microphone. To pick a different microphone, use the menu that appears above the bar."),
                    L("Turn on Camera. A bubble with your face appears; it's recorded separately, so you can move and restyle it later."),
                    L("Click Record, or press Return."),
                    L("When you're done, click the red stop button or press ⌃⌘Esc."),
                ],
                keys: [.fixed("↩", L("Start recording")), .fixed("⌃⌘Esc", L("Stop recording, from any app"))],
                tips: [L("The first time, macOS asks to allow the microphone and the camera.")],
                related: ["rec-mic", "rec-camera", "camera-bubble"]
            ),
            GuideEntry(
                id: "howto-cut", symbol: "scissors", title: L("Cut out mistakes"),
                summary: L("Remove the parts you don't want."),
                steps: [
                    L("In the video editor, move the playhead to where the mistake starts and press S to split the clip there."),
                    L("Move to where it ends and press S again."),
                    L("Click the part in between and press ⌫."),
                    L("Or hold ⇧ and drag across the timeline to select a part, then click Cut this part."),
                ],
                keys: [.fixed("S", L("Split at the playhead")), .fixed("⌫", L("Delete the selection")), .fixed("⌘Z", L("Undo"))],
                tips: [
                    L("Changed your mind? Click the yellow marker on the timeline to bring a cut part back."),
                    L("With a transcript, you can also cut by deleting words: Captions ▸ Edit by text."),
                ],
                related: ["video-clips", "video-cut-part", "captions-edit-text"]
            ),
            GuideEntry(
                id: "howto-zoom", symbol: "plus.magnifyingglass", title: L("Add zooms"),
                summary: L("Zoom in so viewers can see the details."),
                steps: [
                    L("In the video editor, move the playhead to where the zoom should start."),
                    L("Press Z, or click Zoom above the preview."),
                    L("On the timeline's zoom lane, drag the zoom's edges to set how long it lasts."),
                    L("In the panel on the right, set the Zoom level and choose Follow cursor or Aim by hand."),
                ],
                keys: [.fixed("Z", L("Add a zoom at the playhead")), .fixed("1 – 5", L("Zoom level of the selected zoom"))],
                tips: [L("For a zoom on every click, turn on Auto-zoom on clicks in the Zoom panel.")],
                showMe: .editor(.zoom),
                related: ["zoom-add", "zoom-edit", "zoom-auto"]
            ),
            GuideEntry(
                id: "howto-captions", symbol: "captions.bubble", title: L("Add captions"),
                summary: L("Turn what you say into captions, right on your Mac."),
                steps: [
                    L("In the video editor, open the Captions panel and click Transcribe."),
                    L("Keep editing while it listens. The captions appear when it's done."),
                    L("Fix any word in the list of lines."),
                    L("Choose a style under Look."),
                    L("When you export, keep Burn captions into the video on, or save a subtitles file."),
                ],
                showMe: .editor(.captions),
                related: ["captions-transcribe", "captions-look", "export-captions"]
            ),
            GuideEntry(
                id: "howto-vertical", symbol: "iphone", title: L("Make a vertical video for Reels or TikTok"),
                summary: L("Turn a wide recording into a 9:16 video for phones."),
                steps: [
                    L("In the video editor, open the aspect ratio menu in the toolbar and choose 9:16 — Reels, TikTok, Shorts."),
                    L("Click Adapt to this ratio: zooms, the camera bubble, and captions move to fit."),
                    L("Click Phone overlay above the preview to see what a phone app would cover."),
                    L("Export as usual."),
                ],
                tips: [L("Your wide version is kept: switch back to 16:9 at any time.")],
                related: ["size-ratio", "size-adapt", "size-phone"]
            ),
            GuideEntry(
                id: "howto-private", symbol: "eye.slash", title: L("Hide private info"),
                summary: L("Blur faces, email addresses, passwords, and anything else private."),
                steps: [
                    L("In the video editor, click Find private info above the preview."),
                    L("Optional: type words to look for too, like a client's name."),
                    L("Click Find Private Info. You can keep editing while it looks."),
                    L("Tick what to hide, then click Blur Selected."),
                ],
                keys: [.fixed("B", L("Add a blur at the playhead"))],
                tips: [L("To blur something yourself, press B and drag the blur over it.")],
                related: ["privacy-find", "privacy-blur", "editor-highlight-blur"]
            ),
            GuideEntry(
                id: "howto-music", symbol: "music.note", title: L("Add music"),
                summary: L("Play a song quietly under your video."),
                steps: [
                    L("In the video editor, open the Audio panel."),
                    L("Under Music, click Add Music… and choose a song."),
                    L("Set the Volume. Keep Lower under your voice on, so the music gets quieter while you talk."),
                ],
                tips: [L("Use music you have the rights to.")],
                showMe: .editor(.audio),
                related: ["audio-music"]
            ),
            GuideEntry(
                id: "howto-my-style", symbol: "paintbrush", title: L("Make my videos look the same every time"),
                summary: L("Save your look once, then put it on any video in one click."),
                steps: [
                    L("Style a video the way you like it: background, frame, cursor, captions, camera."),
                    L("In the Style panel, open Presets and choose Save as Preset…."),
                    L("Open Presets ▸ Edit Presets, pick your preset, and choose Use as My Style."),
                    L("In your next video, click Apply my style (⇧⌘Y)."),
                ],
                keys: [.fixed("⇧⌘Y", L("Apply my style"))],
                tips: [L("My Style is never applied by itself: new recordings open plain until you click the button.")],
                showMe: .editor(.background),
                related: ["style-presets", "style-my-style"]
            ),
            GuideEntry(
                id: "howto-handoff", symbol: "shippingbox", title: L("Send everything to a video editor"),
                summary: L("Give another editor, or an app like Final Cut Pro, every part of your video as separate files."),
                steps: [
                    L("In the video editor, choose File ▸ Creative Handoff… (⇧⌘E). Or right-click a recording in Home."),
                    L("Choose what to include, then click Choose Location…."),
                    L("Click Create Handoff. When it's done, click Reveal in Finder."),
                    L("Open Timeline.fcpxml in Final Cut Pro or DaVinci Resolve, or “Timeline (Premiere).xml” in Premiere Pro."),
                ],
                keys: [.fixed("⇧⌘E", L("Creative Handoff"))],
                related: ["export-handoff"]
            ),
            GuideEntry(
                id: "howto-gif-audio", symbol: "photo.stack", title: L("Export a GIF or audio only"),
                summary: L("Save a small looping GIF, or just the sound."),
                steps: [
                    L("In the video editor, click Export (⌘E)."),
                    L("For a GIF: choose GIF, then a Size and a Frame rate."),
                    L("For sound only: choose Audio only at the top, then M4A, WAV, or AIFF."),
                    L("Click Export…."),
                ],
                keys: [.fixed("⌘E", L("Export"))],
                tips: [L("GIFs get big quickly: keep them short and choose a smaller size.")],
                related: ["export-gif", "export-audio"]
            ),
            GuideEntry(
                id: "howto-window-size", symbol: "aspectratio", title: L("Record a window at an exact size"),
                summary: L("Make your recording exactly 1920 × 1080 (or another size) without guessing."),
                steps: [
                    L("Open the LF Studios menu in the menu bar and choose Record Window, then pick the window."),
                    L("In the row above the recording bar, open Window size and choose a size."),
                    L("LF Studios resizes and centers the window. Click Record."),
                    L("Afterwards, click Restore size to put the window back."),
                ],
                tips: [L("Needs Accessibility. LF Studios asks for it the first time.")],
                related: ["rec-window-size", "permission-accessibility"]
            ),
            GuideEntry(
                id: "howto-notes", symbol: "text.alignleft", title: L("Read from notes while I record"),
                summary: L("Keep a script on screen that viewers never see."),
                steps: [
                    L("In the recording bar, click Speaker notes."),
                    L("Paste or type your notes, then click Read."),
                    L("Set the scrolling speed and text size. Tick Start with recording if you like."),
                    L("Click Record. Press Space to pause and resume the scrolling."),
                ],
                keys: [.fixed(L("Space"), L("Pause or resume scrolling")), .global(.pauseSpeakerNotes)],
                tips: [L("The notes never appear in a recording, a screenshot, or screen sharing.")],
                related: ["rec-notes", "captions-notes"]
            ),
            GuideEntry(
                id: "howto-translate", symbol: "globe", title: L("Translate my captions"),
                summary: L("Add captions in another language."),
                steps: [
                    L("Add captions first (Captions panel ▸ Transcribe)."),
                    L("Under Languages, choose a language and click Translate."),
                    L("Use Show to switch between the original and the translation."),
                    L("Export with the captions burned in, or save the translation as a subtitles file."),
                ],
                tips: [L("Needs macOS 15 or later. macOS downloads each language once.")],
                showMe: .editor(.captions),
                related: ["captions-translate"]
            ),
            GuideEntry(
                id: "howto-chapters", symbol: "list.bullet.rectangle", title: L("Add chapters for YouTube"),
                summary: L("Turn markers into chapters, and copy them for your video's description."),
                steps: [
                    L("While recording, click the flag in the recording bar at each new topic. Or, in the editor, click Marker on the timeline."),
                    L("Double-click a marker to give it a name."),
                    L("In the export window, turn on Add chapters from markers."),
                    L("Click Copy Chapters and paste them into your YouTube description."),
                ],
                tips: [L("YouTube needs at least three chapters, each at least 10 seconds long. LF Studios tells you if yours don't fit.")],
                related: ["rec-markers", "video-markers", "export-chapters"]
            ),
            GuideEntry(
                id: "howto-pin", symbol: "pin", title: L("Pin a screenshot on screen"),
                summary: L("Keep a screenshot floating above your windows, as a reference."),
                steps: [
                    L("Open History from the LF Studios menu, right-click a screenshot, and choose Pin to Screen."),
                    L("Or, with the preview after capture on, click Pin on the thumbnail."),
                    L("Drag the pin to move it; drag an edge to resize it."),
                    L("Press Esc to close it."),
                ],
                related: ["history-pin", "shot-preview"]
            ),
        ]
    }

    // MARK: - All features

    static func featureCategories() -> [GuideCategory] {
        [
            GuideCategory(id: "screenshots", title: L("Screenshots"), symbol: "camera.viewfinder", entries: screenshotFeatures()),
            GuideCategory(id: "screenshot-editor", title: L("Screenshot editor"), symbol: "pencil.and.outline", entries: screenshotEditorFeatures()),
            GuideCategory(id: "text-qr", title: L("Copy text & QR codes"), symbol: "text.viewfinder", entries: textFeatures()),
            GuideCategory(id: "history", title: L("History & pins"), symbol: "clock.arrow.circlepath", entries: historyFeatures()),
            GuideCategory(id: "recording", title: L("Recording"), symbol: "record.circle", entries: recordingFeatures()),
            GuideCategory(id: "video-editor", title: L("Video editor"), symbol: "film", entries: videoEditorFeatures()),
            GuideCategory(id: "zoom", title: L("Zoom"), symbol: "plus.magnifyingglass", entries: zoomFeatures()),
            GuideCategory(id: "cursor", title: L("Cursor"), symbol: "cursorarrow.motionlines", entries: cursorFeatures()),
            GuideCategory(id: "camera", title: L("Camera"), symbol: "person.crop.circle", entries: cameraFeatures()),
            GuideCategory(id: "captions", title: L("Captions"), symbol: "captions.bubble", entries: captionFeatures()),
            GuideCategory(id: "audio", title: L("Audio"), symbol: "speaker.wave.2", entries: audioFeatures()),
            GuideCategory(id: "style", title: L("Style & presets"), symbol: "paintbrush", entries: styleFeatures()),
            GuideCategory(id: "sizes", title: L("Video sizes"), symbol: "aspectratio", entries: sizeFeatures()),
            GuideCategory(id: "privacy-features", title: L("Privacy"), symbol: "eye.slash", entries: privacyFeatures()),
            GuideCategory(id: "export", title: L("Export"), symbol: "square.and.arrow.up", entries: exportFeatures()),
            GuideCategory(id: "projects", title: L("Projects"), symbol: "folder", entries: projectFeatures()),
            GuideCategory(id: "settings", title: L("Settings"), symbol: "gearshape", entries: settingsFeatures()),
        ].filter { !$0.entries.isEmpty }
    }

    // MARK: Screenshots

    static func screenshotFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "shot-area", symbol: "rectangle.dashed", title: L("Capture Area"),
                summary: L("Drag over any part of the screen to capture it."),
                location: L("Home ▸ Take screenshot, or the LF Studios menu in the menu bar ▸ Capture Area."),
                steps: [
                    L("Press the shortcut, or click Take screenshot."),
                    L("Drag over the area you want."),
                    L("Let go to capture it."),
                ],
                keys: [.global(.captureArea), .fixed("Esc", L("Cancel"))],
                tips: [L("Every screenshot is kept in History and in Home ▸ Screenshots.")],
                related: ["shot-selecting", "shot-after-capture"]
            ),
            GuideEntry(
                id: "shot-window", symbol: "macwindow", title: L("Capture Window"),
                summary: L("Capture one window on its own, even if other windows are in front of it."),
                location: L("The LF Studios menu in the menu bar ▸ Capture Window."),
                steps: [
                    L("Press the shortcut, or choose Capture Window."),
                    L("Move the pointer over a window: it lights up."),
                    L("Click to capture it."),
                ],
                keys: [.global(.captureWindow), .fixed("Esc", L("Cancel"))],
                tips: [
                    L("Settings ▸ Screenshots ▸ Window Capture adds a soft shadow and some transparent space around the window. It's on to start with."),
                    L("On macOS 13, a window is captured as you see it on screen, including anything in front of it."),
                ],
                showMe: .settings(.screenshots)
            ),
            GuideEntry(
                id: "shot-fullscreen", symbol: "display", title: L("Capture Fullscreen"),
                summary: L("Capture the whole screen the pointer is on, right away."),
                location: L("The LF Studios menu in the menu bar ▸ Capture Fullscreen."),
                keys: [.global(.captureFullscreenNative), .global(.captureFullscreenFallback)],
                tips: [L("⇧⌘3 is also Apple's own screenshot shortcut. LF Studios offers to turn Apple's off, so its own works.")],
                related: ["shot-all-displays", "trouble-apple-screenshot"]
            ),
            GuideEntry(
                id: "shot-all-displays", symbol: "rectangle.on.rectangle", title: L("Capture All Displays"),
                summary: L("Capture every screen at once, one picture per screen."),
                location: L("The LF Studios menu in the menu bar ▸ Capture All Displays. It's there only while more than one screen is connected."),
                keys: [.global(.captureAllDisplays)]
            ),
            GuideEntry(
                id: "shot-previous", symbol: "arrow.counterclockwise", title: L("Capture Previous Area"),
                summary: L("Capture the same area as last time, without selecting it again."),
                location: L("The LF Studios menu in the menu bar ▸ Capture Previous Area."),
                keys: [.global(.capturePreviousArea)],
                tips: [L("LF Studios remembers the area until it quits. With no area yet, you select one as usual.")]
            ),
            GuideEntry(
                id: "shot-timed", symbol: "timer", title: L("Timed Capture"),
                summary: L("Select an area, then wait a few seconds before the shot: time to open a menu or hover over something."),
                location: L("The LF Studios menu in the menu bar ▸ Timed Capture."),
                steps: [
                    L("Choose Timed Capture and drag over the area."),
                    L("Get things ready while the countdown runs."),
                    L("The screenshot is taken when it reaches zero."),
                ],
                keys: [.global(.captureTimed), .fixed("Esc", L("Cancel the countdown"))],
                tips: [L("Choose 3, 5, or 10 seconds in Settings ▸ Screenshots ▸ Timed Capture.")],
                showMe: .settings(.screenshots)
            ),
            GuideEntry(
                id: "shot-scrolling", symbol: "scroll", title: L("Scrolling Capture"),
                summary: L("Capture a page that's longer than the screen, by scrolling through it."),
                location: L("Home ▸ Scroll capture, or the LF Studios menu in the menu bar ▸ Scrolling Capture."),
                steps: [
                    L("Drag over the part of the window that scrolls."),
                    L("Scroll down slowly."),
                    L("Click Done or press Esc to finish."),
                ],
                keys: [.global(.captureScrolling, L("Start, and press again to finish")), .fixed("Esc", L("Finish"))],
                tips: [
                    L("Headers and sidebars that stay in place show only once."),
                    L("Up to 30,000 pixels tall. It stops by itself after 10 minutes."),
                ],
                related: ["howto-scrolling"]
            ),
            GuideEntry(
                id: "shot-selecting", symbol: "selection.pin.in.out", title: L("Selecting an area"),
                summary: L("Get the area exactly right: a magnifier, the size as you drag, and keys to fine-tune."),
                location: L("Whenever you capture or record an area."),
                points: [
                    L("The magnifier shows the pixels under the pointer, with their color."),
                    L("The size shows while you drag."),
                    L("Hold Space while dragging to move the area instead of resizing it."),
                    L("Hold ⇧ as you let go to adjust the area before capturing. Then drag its edges, or use the arrow keys, and press Return."),
                ],
                keys: [
                    .fixed(L("Space"), L("Move the area while dragging")),
                    .fixed("⇧", L("Hold as you let go to adjust first")),
                    .fixed("← → ↑ ↓", L("Nudge the area (with ⇧: 10 points)")),
                    .fixed("⌥ ← → ↑ ↓", L("Make the area bigger or smaller")),
                    .fixed("↩", L("Capture")),
                    .fixed("Esc", L("Cancel")),
                ],
                tips: [L("Prefer to adjust every time? Turn off Capture immediately after selecting in Settings ▸ Screenshots.")],
                showMe: .settings(.screenshots)
            ),
            GuideEntry(
                id: "shot-desktop-icons", symbol: "menubar.dock.rectangle", title: L("Hide desktop icons"),
                summary: L("Keep files on your desktop out of your screenshots."),
                location: L("Settings ▸ General ▸ Menu Bar ▸ Hide desktop icons while capturing. Or the LF Studios menu ▸ Hide Desktop Icons, which hides them until you show them again."),
                tips: [L("While capturing, the icons are covered with your wallpaper for a moment. Nothing on the desktop is moved.")],
                showMe: .settings(.general)
            ),
            GuideEntry(
                id: "shot-sound", symbol: "speaker.wave.1", title: L("Capture sound"),
                summary: L("A camera shutter sound plays when a screenshot is taken."),
                location: L("Settings ▸ General ▸ Sounds ▸ Play capture sound."),
                showMe: .settings(.general)
            ),
            GuideEntry(
                id: "shot-preview", symbol: "rectangle.inset.bottomleft.filled", title: L("Preview after capture"),
                summary: L("A small thumbnail of each screenshot, with buttons to edit, copy, save, or pin it."),
                location: L("Turn it on in Settings ▸ General ▸ After Capture ▸ Show the preview after capture."),
                points: [
                    L("Hover over the thumbnail for Edit, Close, Delete, Pin, Copy, Save, and Text (copies the text in it)."),
                    L("Double-click it to edit; drag it into another app to drop the picture there."),
                    L("Swipe it sideways to dismiss it."),
                ],
                keys: [.fixed("⌘C", L("Copy")), .fixed("⌘S", L("Save")), .fixed("⌘E", L("Edit")), .fixed("Esc", L("Close"))],
                tips: [L("Choose the corner (Left or Right) and how long it stays in the same settings section. Hovering keeps it open.")],
                showMe: .settings(.general)
            ),
            GuideEntry(
                id: "shot-after-capture", symbol: "checklist", title: L("After capture"),
                summary: L("Choose what happens after each screenshot or recording."),
                location: L("Settings ▸ General ▸ After Capture."),
                points: [
                    L("Copy screenshots to the clipboard."),
                    L("Show the preview after capture."),
                    L("Open the video editor after recording."),
                    L("Save automatically, to the folder chosen in Settings ▸ Screenshots."),
                ],
                tips: [L("All of these start off. Every screenshot is still kept in History and Home, and a short notice says so.")],
                showMe: .settings(.general),
                related: ["app-files"]
            ),
        ]
    }

    static func screenshotEditorFeatures() -> [GuideEntry] { [] } // STUB
    static func textFeatures() -> [GuideEntry] { [] } // STUB
    static func historyFeatures() -> [GuideEntry] { [] } // STUB
    static func recordingFeatures() -> [GuideEntry] { [] } // STUB
    static func videoEditorFeatures() -> [GuideEntry] { [] } // STUB
    static func zoomFeatures() -> [GuideEntry] { [] } // STUB
    static func cursorFeatures() -> [GuideEntry] { [] } // STUB
    static func cameraFeatures() -> [GuideEntry] { [] } // STUB
    static func captionFeatures() -> [GuideEntry] { [] } // STUB
    static func audioFeatures() -> [GuideEntry] { [] } // STUB
    static func styleFeatures() -> [GuideEntry] { [] } // STUB
    static func sizeFeatures() -> [GuideEntry] { [] } // STUB
    static func privacyFeatures() -> [GuideEntry] { [] } // STUB
    static func exportFeatures() -> [GuideEntry] { [] } // STUB
    static func projectFeatures() -> [GuideEntry] { [] } // STUB
    static func settingsFeatures() -> [GuideEntry] { [] } // STUB

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
