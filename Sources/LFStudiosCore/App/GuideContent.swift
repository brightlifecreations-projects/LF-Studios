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

    // MARK: Screenshot editor

    /// A tool's name and its key, as the editor's toolbar shows them.
    private static func tool(_ tool: AnnotationTool) -> GuideKey {
        .fixed(tool.shortcutLabel, tool.name)
    }

    static func screenshotEditorFeatures() -> [GuideEntry] {
        let place = L("Open a screenshot from Home, History, or the preview after capture. The tools are in the toolbar at the top.")
        return [
            GuideEntry(
                id: "editor-arrows-shapes", symbol: "arrow.up.right", title: L("Arrows, shapes & lines"),
                summary: L("Point at things and frame them: arrows, rectangles, ellipses, lines, and freehand drawing."),
                location: place,
                steps: [
                    L("Pick a tool in the toolbar, or press its key."),
                    L("Drag on the screenshot to draw."),
                    L("To bend an arrow, select it and drag the dot in its middle."),
                ],
                keys: [
                    tool(.arrow), tool(.rectangle), tool(.filledRectangle), .fixed("⌥R", L("Rounded corners")),
                    tool(.ellipse), tool(.line), tool(.freehand),
                    .fixed(L("⇧-drag"), L("Square, circle, or straight 45° lines")),
                    .fixed(L("⌥-drag"), L("Draw from the center")),
                ]
            ),
            GuideEntry(
                id: "editor-text", symbol: "textformat", title: L("Text, callouts & numbered steps"),
                summary: L("Add labels, speech-bubble callouts, and numbered circles for step-by-step guides."),
                location: place,
                steps: [
                    L("Text: click where the text goes and type. Press ⌘Return, Esc, or click elsewhere to finish."),
                    L("Callout: press on the thing to point at, drag the bubble out, then type."),
                    L("Numbered steps: click once for each step. The numbers count up by themselves."),
                    L("Double-click any text to change it."),
                ],
                keys: [tool(.text), tool(.callout), tool(.numberedStep), .fixed("⌘↩", L("Finish typing"))],
                tips: [L("Set the text size and Bold in the toolbar. Drag a corner of the text to make it bigger or smaller.")]
            ),
            GuideEntry(
                id: "editor-highlight-blur", symbol: "highlighter", title: L("Highlight, blur, pixelate & spotlight"),
                summary: L("Draw attention to something, or hide it."),
                location: place,
                points: [
                    L("Highlighter: a see-through marker, in a straight line or freehand."),
                    L("Blur and Pixelate: hide passwords, names, and other private details. Strength sets how much."),
                    L("Spotlight: darkens everything except the area you draw. Choose Rectangle or Ellipse."),
                ],
                keys: [tool(.highlighter), tool(.freehandHighlighter), tool(.blur), tool(.pixelate), tool(.spotlight)],
                tips: [L("For private information, use a high Strength: a light blur can sometimes still be read.")]
            ),
            GuideEntry(
                id: "editor-crop", symbol: "crop", title: L("Crop"),
                summary: L("Trim the screenshot to just the part that matters."),
                location: place,
                steps: [
                    L("Choose Crop, or press C."),
                    L("Drag a frame. Drag inside it to move it, or drag its edges to resize it."),
                    L("Click Apply, or press Return."),
                ],
                keys: [tool(.crop), .fixed("↩", L("Apply the crop")), .fixed("Esc", L("Cancel"))],
                tips: [L("Your marks stay editable. Reset shows the whole screenshot again, and ⌘Z undoes a crop.")]
            ),
            GuideEntry(
                id: "editor-style", symbol: "paintpalette", title: L("Colors, sizes & bold"),
                summary: L("Change how a mark looks, before or after you draw it."),
                location: place,
                steps: [
                    L("Pick the Select tool (V) and click a mark to change it, or set things before you draw."),
                    L("Click Color for eight quick colors, or Custom… for any color."),
                    L("Use Size for line thickness, and Text size and Bold for text."),
                ],
                keys: [
                    tool(.select),
                    .fixed("⌫", L("Delete the selected mark")),
                    .fixed("← → ↑ ↓", L("Nudge the selected mark (with ⇧: 10 points)")),
                    .fixed("Esc", L("Deselect")),
                ],
                tips: [L("LF Studios remembers your last tool, color, and sizes for next time.")]
            ),
            GuideEntry(
                id: "editor-background", symbol: "photo.artframe", title: L("Background & frame"),
                summary: L("Put your screenshot on a gradient, a color, or a picture, with rounded corners and a shadow: ready to share."),
                location: L("In the screenshot editor, click Background in the toolbar."),
                steps: [
                    L("Click Background."),
                    L("Choose Gradient, Solid Color, or Image, then a preset. Upload Custom Image uses your own picture."),
                    L("Set Padding, Radius (rounded corners), and Shadow."),
                ],
                tips: [L("To remove it again, untick Apply background to this image.")]
            ),
            GuideEntry(
                id: "editor-open", symbol: "square.and.arrow.down", title: L("Opening, saving, copying & undo"),
                summary: L("Open a screenshot to mark it up, then copy or save the result."),
                location: L("Click a screenshot in Home, or choose Edit in History or on the preview after capture. The LF Studios menu ▸ Annotate Last Screenshot opens the newest one."),
                steps: [
                    L("Mark up the screenshot."),
                    L("Click Copy to paste it into another app, or Save to keep it as a file."),
                    L("Close the window when you're done. If you haven't saved, LF Studios asks first."),
                ],
                keys: [
                    .fixed("⌘C", L("Copy")), .fixed("⌘S", L("Save")),
                    .fixed("⌘Z", L("Undo")), .fixed("⇧⌘Z", L("Redo")),
                    .fixed("⌘=  ⌘−", L("Zoom in / out")), .fixed("⌘0", L("Actual size")),
                    .fixed("⌘W", L("Close")),
                ],
                tips: [L("Your edits replace the screenshot in History; the original is kept too.")]
            ),
        ]
    }
    // MARK: Copy text & QR codes

    static func textFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "text-capture", symbol: "text.viewfinder", title: L("Capture Text"),
                summary: L("Copy any text you can see on screen, even in pictures, videos, and apps that don't let you select it."),
                location: L("The LF Studios menu in the menu bar ▸ Capture Text."),
                steps: [
                    L("Choose Capture Text, or press its shortcut."),
                    L("Drag over the text."),
                    L("Paste it anywhere with ⌘V."),
                ],
                keys: [.global(.captureText)],
                tips: [
                    L("Columns, tables, and right-to-left languages come out in reading order."),
                    L("The picture is saved in History too, so you can search for its text later."),
                ],
                related: ["text-window", "text-settings"]
            ),
            GuideEntry(
                id: "text-window", symbol: "doc.text.magnifyingglass", title: L("Recognized text, links & tables"),
                summary: L("When the text has links, email addresses, or a table, LF Studios offers more ways to use it."),
                location: L("Click the notice that appears after Capture Text (“click for options”)."),
                points: [
                    L("Open or copy each link and email address."),
                    L("Copy as Table puts the table on the clipboard, ready to paste into a spreadsheet."),
                    L("Copy Text copies all of it again."),
                ],
                keys: [.fixed("Esc", L("Close"))]
            ),
            GuideEntry(
                id: "text-thumbnail", symbol: "text.below.photo", title: L("Copy text from a screenshot"),
                summary: L("Copy the text in a screenshot you just took."),
                location: L("On the preview after capture, click Text, or right-click and choose Copy Text."),
                tips: [L("The preview shows only when Show the preview after capture is on in Settings ▸ General.")],
                showMe: .settings(.general)
            ),
            GuideEntry(
                id: "text-qr", symbol: "qrcode.viewfinder", title: L("Scan QR Code"),
                summary: L("Read a QR code or barcode on your screen: open its link, write the email, or see the Wi-Fi password."),
                location: L("The LF Studios menu in the menu bar ▸ Scan QR Code."),
                steps: [
                    L("Choose Scan QR Code."),
                    L("Drag over the code."),
                    L("Click Copy, or the button for what's in it, like Open Link."),
                ],
                tips: [L("Reads QR codes and most barcodes, like the ones on products and tickets.")]
            ),
            GuideEntry(
                id: "text-settings", symbol: "character.magnify", title: L("Text recognition settings"),
                summary: L("Choose between accurate and fast, and which languages to read."),
                location: L("Settings ▸ Screenshots ▸ Text Recognition."),
                points: [
                    L("Accuracy: Accurate reads more carefully; Fast is quicker but knows fewer languages."),
                    L("Languages: Automatic finds the language itself, or pick the ones you use."),
                ],
                tips: [L("These settings are used by Capture Text, Copy Text, and History search.")],
                showMe: .settings(.screenshots)
            ),
        ]
    }

    // MARK: History & pins

    static func historyFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "history-panel", symbol: "clock.arrow.circlepath", title: L("History"),
                summary: L("Every screenshot you take, in one place, grouped by day."),
                location: L("The LF Studios menu in the menu bar ▸ Open History. Screenshots also show in Home ▸ Screenshots."),
                points: [
                    L("Click Copy or Edit on a screenshot, or double-click it to edit it."),
                    L("Right-click for Save As…, Pin to Screen, and Delete."),
                ],
                keys: [.fixed("↩", L("Edit the selected screenshot")), .fixed("⌘C", L("Copy")), .fixed("⌫", L("Delete")), .fixed("⌘Z", L("Undo a delete"))],
                showMe: .history
            ),
            GuideEntry(
                id: "history-search", symbol: "magnifyingglass", title: L("Search screenshots by their text"),
                summary: L("Find a screenshot by any word in it."),
                location: L("The search box at the top of History, or the search box in Home."),
                steps: [
                    L("Open History and just start typing: the search box fills in."),
                    L("Screenshots with those words show up."),
                ],
                keys: [.fixed("⌘F", L("Search")), .fixed("Esc", L("Clear the search"))],
                tips: [L("LF Studios reads the text in every screenshot in the background, on your Mac.")],
                showMe: .history
            ),
            GuideEntry(
                id: "history-manage", symbol: "checkmark.circle", title: L("Filter, select & delete"),
                summary: L("Show one kind of capture, select several at once, and undo a delete."),
                location: L("In History: the All Captures menu at the top, and the screenshots themselves."),
                points: [
                    L("All Captures: show only Area, Window, Fullscreen, Scrolling, or Text captures."),
                    L("⌘-click or ⇧-click to select several; the arrow keys move the selection."),
                    L("Deleted screenshots stay in LF Studios' trash for 7 days, and ⌘Z brings them back."),
                    L("Clear All deletes every capture."),
                ],
                keys: [.fixed(L("⇧/⌘-click"), L("Select several items")), .fixed("⌫", L("Delete")), .fixed("⌘Z", L("Undo a delete"))],
                showMe: .history
            ),
            GuideEntry(
                id: "history-drag", symbol: "hand.draw", title: L("Drag screenshots into other apps"),
                summary: L("Drop a screenshot straight into an email, a chat, a document, or Finder."),
                location: L("In History, or from the preview after capture."),
                steps: [L("Drag a screenshot out of History and drop it where you want it.")],
                tips: [L("Select several to drag them all at once.")],
                showMe: .history
            ),
            GuideEntry(
                id: "history-pin", symbol: "pin", title: L("Pin to Screen"),
                summary: L("Float a screenshot above all your windows, as a reference while you work."),
                location: L("History ▸ right-click a screenshot ▸ Pin to Screen, or Pin on the preview after capture."),
                steps: [
                    L("Pin a screenshot."),
                    L("Drag it to move it; drag an edge to resize it."),
                    L("Right-click it for Copy, Save As…, Edit, Close Pin, or Close All Pins."),
                ],
                keys: [.fixed("Esc", L("Close the pin")), .fixed("⌘C", L("Copy"))],
                showMe: .history
            ),
            GuideEntry(
                id: "history-keep", symbol: "archivebox", title: L("Keep captures & clean up"),
                summary: L("Choose how long History keeps screenshots, and free up space."),
                location: L("Settings ▸ Screenshots ▸ History."),
                points: [
                    L("Keep captures: Forever, 7, 30, or 90 days, or the last 100, 500, or 1,000."),
                    L("Clean Up… empties History's trash and removes leftover files."),
                ],
                tips: [L("If a new limit would delete screenshots, LF Studios asks first.")],
                showMe: .settings(.screenshots)
            ),
        ]
    }
    // MARK: Recording

    static func recordingFeatures() -> [GuideEntry] {
        let bar = L("In the recording bar, which appears after you choose what to record.")
        return [
            GuideEntry(
                id: "rec-area", symbol: "rectangle.dashed.badge.record", title: L("Record an area"),
                summary: L("Record just part of the screen."),
                location: L("Home ▸ New recording, or the LF Studios menu in the menu bar ▸ Record Area."),
                steps: [
                    L("Drag over the area to record."),
                    L("Choose your options in the recording bar."),
                    L("Click Record, or press Return."),
                ],
                keys: [.global(.recordArea), .fixed("↩", L("Start recording")), .fixed("Esc", L("Cancel"))],
                tips: [L("A thin outline shows what's being recorded. It never appears in the video.")],
                related: ["rec-bar", "rec-stop"]
            ),
            GuideEntry(
                id: "rec-window", symbol: "macwindow.badge.plus", title: L("Record a window"),
                summary: L("Record one window. The recording follows it if you move it, even to another screen."),
                location: L("The LF Studios menu in the menu bar ▸ Record Window."),
                steps: [
                    L("Choose Record Window."),
                    L("Click Choose under the window you want."),
                    L("Click Record."),
                ],
                keys: [.global(.recordWindow)],
                tips: [
                    L("That app's other windows stay out of the video, but its menus and dialogs show."),
                    L("If the window closes, the recording keeps going until you stop it."),
                ],
                related: ["rec-window-size"]
            ),
            GuideEntry(
                id: "rec-screen", symbol: "display", title: L("Record the full screen"),
                summary: L("Record everything on one screen."),
                location: L("The LF Studios menu in the menu bar ▸ Record Fullscreen."),
                steps: [
                    L("Choose Record Fullscreen."),
                    L("With more than one screen, click Record next to the one you want."),
                    L("Click Record in the recording bar."),
                ],
                keys: [.global(.recordFullscreen)]
            ),
            GuideEntry(
                id: "rec-bar", symbol: "slider.horizontal.3", title: L("The recording bar"),
                summary: L("Everything for the recording, before you start: sound, camera, cursor, quality, and more."),
                location: bar,
                points: [
                    L("System audio, Microphone, Cursor, Camera, Show keyboard shortcuts, and Speaker notes: click to turn each on or off."),
                    L("Quality: Balanced, High, or Max. Frame rate: 30 or 60 fps. The estimate under them shows how much space a minute takes."),
                    L("⋯ More recording options: the camera, Editable Cursor, Countdown, and the typing options."),
                ],
                keys: [.fixed("↩", L("Start recording")), .fixed("Esc", L("Cancel"))],
                tips: [
                    L("Drag the bar by its handle to move it."),
                    L("Your choices are remembered for next time, and match Settings ▸ Recording."),
                ],
                showMe: .settings(.recording)
            ),
            GuideEntry(
                id: "rec-system-audio", symbol: "speaker.wave.2", title: L("System audio"),
                summary: L("Record the sound your Mac plays, like a video or an app's sounds."),
                location: L("Click System audio in the recording bar, or Settings ▸ Recording ▸ Audio ▸ Record system audio."),
                tips: [L("It's saved separately from your voice, so you can set each one's volume in the editor. LF Studios' own sounds are left out.")],
                showMe: .settings(.recording)
            ),
            GuideEntry(
                id: "rec-mic", symbol: "mic", title: L("Microphone"),
                summary: L("Record your voice."),
                location: L("Click Microphone in the recording bar. A menu above the bar picks which microphone."),
                steps: [
                    L("Turn on Microphone."),
                    L("Choose your microphone in the menu above the bar."),
                    L("Speak and watch the level meter move."),
                ],
                tips: [
                    L("If the microphone is unplugged while recording, LF Studios switches to another one and keeps going."),
                    L("The first time, macOS asks to allow the microphone."),
                ],
                showMe: .settings(.recording),
                related: ["permission-microphone", "trouble-no-sound"]
            ),
            GuideEntry(
                id: "rec-camera", symbol: "web.camera", title: L("Camera"),
                summary: L("Show yourself in a bubble while you record."),
                location: L("Click Camera in the recording bar. Choose the camera in ⋯ More recording options."),
                steps: [
                    L("Turn on Camera. A round bubble appears; drag it where you like."),
                    L("Record as usual."),
                ],
                tips: [
                    L("The camera is saved separately, so in the editor you can move it, resize it, restyle it, or hide it."),
                    L("The bubble you see while recording never shows up in the screen recording itself."),
                ],
                showMe: .settings(.recording),
                related: ["camera-bubble", "permission-camera"]
            ),
            GuideEntry(
                id: "rec-cursor", symbol: "cursorarrow", title: L("Cursor & editable cursor"),
                summary: L("Show the pointer in your recording, and keep it sharp and adjustable in the editor."),
                location: L("Cursor in the recording bar, and ⋯ More recording options ▸ Editable Cursor. Also in Settings ▸ Recording ▸ Video."),
                points: [
                    L("Cursor: shows the pointer in the video."),
                    L("Editable Cursor: saves the pointer separately, so the editor can smooth it, enlarge it, change its style, and keep it crisp when zoomed."),
                ],
                tips: [L("Both are on to start with.")],
                showMe: .settings(.recording),
                related: ["cursor-show"]
            ),
            GuideEntry(
                id: "rec-shortcuts", symbol: "command", title: L("Show keyboard shortcuts"),
                summary: L("Remember the shortcuts you press, like ⌘C, so the video can show them on screen."),
                location: L("Click Show keyboard shortcuts (⌘) in the recording bar, or Settings ▸ Recording ▸ Show keyboard shortcuts."),
                tips: [
                    L("Only shortcuts with ⌘ or ⌃ (and a few keys like Esc) are saved, never ordinary typing."),
                    L("Needs Accessibility. In the editor, show them with Cursor ▸ Keys on screen."),
                ],
                showMe: .settings(.recording),
                related: ["cursor-keys", "permission-accessibility"]
            ),
            GuideEntry(
                id: "rec-typing", symbol: "character.cursor.ibeam", title: L("Track where I type"),
                summary: L("Remembers where the text cursor is on screen, so the editor can zoom in on your typing."),
                location: L("⋯ More recording options ▸ Track Where I Type, or Settings ▸ Recording ▸ Track where I type."),
                tips: [
                    L("Saves positions only: never the text, never the keys, and nothing while a password field is in use."),
                    L("Off to start with. Needs Accessibility."),
                ],
                showMe: .settings(.recording),
                since: "1.4.0",
                related: ["zoom-typing", "privacy-typing"]
            ),
            GuideEntry(
                id: "rec-keys-pressed", symbol: "keyboard.badge.ellipsis", title: L("Record when keys are pressed"),
                summary: L("Remembers when you type, so the editor can speed up the typing parts."),
                location: L("⋯ More recording options ▸ Record When Keys Are Pressed, or Settings ▸ Recording."),
                tips: [
                    L("Saves the moment of each key press only: never which key, and nothing while a password field is in use."),
                    L("Off to start with. Needs Accessibility."),
                ],
                showMe: .settings(.recording),
                since: "1.4.0",
                related: ["cursor-typing-speed", "privacy-typing"]
            ),
            GuideEntry(
                id: "rec-countdown", symbol: "timer", title: L("Countdown"),
                summary: L("A few seconds to get ready before recording starts."),
                location: L("⋯ More recording options ▸ Countdown, or Settings ▸ Recording ▸ Countdown."),
                keys: [.fixed("Esc", L("Cancel the countdown"))],
                tips: [L("Choose Off, 3, 5, or 10 seconds. Click the countdown to cancel it.")],
                showMe: .settings(.recording)
            ),
            GuideEntry(
                id: "rec-window-size", symbol: "aspectratio", title: L("Window size"),
                summary: L("Resize a window so the recording comes out at an exact size, like 1920 × 1080."),
                location: L("When recording a window: the Window size menu in the row above the recording bar."),
                steps: [
                    L("Choose a size, or Custom Size… for your own."),
                    L("LF Studios resizes the window and centers it."),
                    L("After recording, click Restore size to put it back."),
                ],
                tips: [
                    L("If a size doesn't fit on the screen, LF Studios offers the biggest one of the same shape that does."),
                    L("Needs Accessibility. Some apps don't let their windows be resized; LF Studios says so."),
                ],
                related: ["howto-window-size"]
            ),
            GuideEntry(
                id: "rec-notes", symbol: "text.alignleft", title: L("Speaker notes"),
                summary: L("A teleprompter for your script. It never shows up in a recording, a screenshot, or screen sharing."),
                location: L("Click Speaker notes in the recording bar, or in the bar while recording."),
                steps: [
                    L("Paste or type your notes, then click Read."),
                    L("Set the scrolling speed and text size."),
                    L("Click play, press Space, or tick Start with recording."),
                ],
                keys: [.fixed(L("Space"), L("Pause or resume scrolling")), .fixed("↑ ↓", L("Scroll by a line")), .global(.pauseSpeakerNotes)],
                tips: [L("Your notes are remembered. A recording made with them open keeps a copy, shown in the editor's Captions panel.")],
                since: "1.4.0",
                related: ["captions-notes", "howto-notes"]
            ),
            GuideEntry(
                id: "rec-pause", symbol: "pause.circle", title: L("Pause & resume"),
                summary: L("Take a break in the middle of a recording. The pause is left out of the video."),
                location: L("The pause button in the bar while recording."),
                keys: [.global(.pauseRecording)],
                tips: [L("While paused, the outline around the area turns yellow.")]
            ),
            GuideEntry(
                id: "rec-markers", symbol: "flag", title: L("Add markers while recording"),
                summary: L("Mark important moments while you record. They show as flags in the editor and can become chapters."),
                location: L("The flag button in the bar while recording."),
                keys: [.global(.addMarker)],
                related: ["video-markers", "export-chapters"]
            ),
            GuideEntry(
                id: "rec-discard", symbol: "trash", title: L("Discard a take"),
                summary: L("Throw away a recording that went wrong and start again."),
                location: L("The trash button in the bar while recording."),
                steps: [L("Click the trash button, then Discard.")],
                tips: [L("If you don't answer within a few seconds, the recording is kept, just in case.")]
            ),
            GuideEntry(
                id: "rec-stop", symbol: "stop.circle", title: L("Stop recording"),
                summary: L("Finish the recording and save it."),
                location: L("The red stop button in the bar while recording, or the red timer in the menu bar."),
                keys: [
                    .fixed("⌃⌘Esc", L("Stop recording, from any app")),
                    .global(.stopRecording),
                    .fixed("Esc", L("Stop, while LF Studios is the app in front")),
                ],
                tips: [L("Plain Esc belongs to the app you're recording, so it stops only when LF Studios is in front. ⌃⌘Esc works everywhere.")]
            ),
            GuideEntry(
                id: "rec-saved", symbol: "checkmark.rectangle", title: L("After recording"),
                summary: L("The “Recording saved” panel lets you edit the video, show it in Finder, or copy where it is."),
                location: L("The panel appears at the top right of the screen after you stop."),
                points: [
                    L("Edit Video opens the video editor."),
                    L("Reveal shows the file in Finder; Copy Path copies where it is."),
                    L("The panel closes by itself after a few seconds; hover over it to keep it."),
                ],
                tips: [L("To skip the panel and go straight to the editor, turn on Open the video editor after recording in Settings ▸ General.")],
                showMe: .settings(.general)
            ),
            GuideEntry(
                id: "rec-recovery", symbol: "lifepreserver", title: L("Recovering an interrupted recording"),
                summary: L("If your Mac crashes or loses power while recording, LF Studios saves what it can."),
                location: L("Happens by itself the next time LF Studios opens."),
                tips: [L("Click the notice to open the recovered video. Pointer, click, and marker details from that take can't be recovered.")]
            ),
            GuideEntry(
                id: "rec-problems", symbol: "exclamationmark.triangle", title: L("If something goes wrong while recording"),
                summary: L("LF Studios keeps your recording safe when things change in the middle of it."),
                points: [
                    L("Microphone unplugged: it switches to another one, or carries on without sound until one is plugged in."),
                    L("Camera unplugged: the screen recording keeps going without it."),
                    L("Disk almost full: it warns you, then stops and saves the recording before the disk is full."),
                    L("“Skipping frames”: your Mac can't keep up. Try Balanced quality or 30 fps."),
                ]
            ),
        ]
    }
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
