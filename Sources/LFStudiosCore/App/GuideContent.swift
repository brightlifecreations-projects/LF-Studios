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
    nonisolated static let newVersions: [String] = ["1.11.1", "1.11.0", "1.10.0", "1.9.0", "1.8.0", "1.7.0"]

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
                    L("No question appeared, and LF Studios isn't in that list? Open Terminal, run tccutil reset Microphone com.lfstudios.app, then quit and reopen LF Studios and turn on Microphone again."),
                ],
                tips: [L("LF Studios shows up under Microphone only after it has asked once. There's no + button to add it yourself: turning on Microphone in the recording bar is what asks.")],
                showMe: .systemSettings(.microphone),
                related: ["trouble-no-sound"]
            ),
            GuideEntry(
                id: "permission-camera", symbol: "camera", title: L("Allow the camera"),
                summary: L("Needed to show yourself in a bubble while you record."),
                steps: [
                    L("Turn on Camera in the recording bar. macOS asks once: click Allow."),
                    L("Clicked Don't Allow by mistake? Click Open System Settings below and turn on LF Studios under Camera."),
                    L("No question appeared, and LF Studios isn't in that list? Open Terminal, run tccutil reset Camera com.lfstudios.app, then quit and reopen LF Studios and turn on Camera again."),
                ],
                tips: [L("LF Studios shows up under Camera only after it has asked once. There's no + button to add it yourself: turning on Camera in the recording bar is what asks.")],
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
                    L("Click New recording in Home. A frame appears: choose a shape above the recording bar, like 16:9, and drag the frame's border to what you want to record."),
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
                    L("Click New recording in Home. Choose a shape for the frame (16:9 for YouTube, 9:16 for Reels) and drag its border into place. For a window or the whole screen, click Window or Full screen above the recording bar."),
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
                id: "howto-frame", symbol: "rectangle.portrait", title: L("Record for YouTube, Reels, or Instagram"),
                summary: L("Record in exactly the shape the site wants, so nothing gets cut off or stretched."),
                steps: [
                    L("Click New recording in Home."),
                    L("Above the recording bar, choose 16:9 for YouTube, 9:16 for Reels, TikTok, and Shorts, or 4:5 for the Instagram feed."),
                    L("Choose 1080p in the size menu."),
                    L("Drag the frame over what you want to show. To fill it with one app, click Fit a window to the frame… and choose its window."),
                    L("Click Record."),
                ],
                tips: [L("The video has exactly the shape you chose, like 1080 × 1920 for 9:16.")],
                since: "1.8.0",
                related: ["rec-frame", "rec-area"]
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
                summary: L("Record just part of the screen, in the exact shape and size you choose."),
                location: L("Home ▸ New recording, or the LF Studios menu in the menu bar ▸ Record Area."),
                steps: [
                    L("A frame appears in the middle of the screen. Choose its shape above the recording bar, like 16:9."),
                    L("Drag the frame's border to move it, or a corner to make it bigger or smaller."),
                    L("Choose your options in the recording bar."),
                    L("Click Record, or press Return."),
                ],
                keys: [.global(.recordArea), .fixed("↩", L("Start recording")), .fixed("Esc", L("Cancel"))],
                tips: [
                    L("To drag out any area yourself, click Select area manually above the recording bar."),
                    L("A thin outline shows what's being recorded. It never appears in the video."),
                ],
                since: "1.8.0",
                related: ["rec-frame", "rec-bar", "rec-stop"]
            ),
            GuideEntry(
                id: "rec-frame", symbol: "aspectratio", title: L("The frame bar"),
                summary: L("A frame of an exact shape and size, so your video comes out ready for YouTube, Reels, or Instagram."),
                location: L("The strip above the recording bar, after Home ▸ New recording."),
                points: [
                    L("Shapes: 16:9 for YouTube, 9:16 for Reels, TikTok, and Shorts, 1:1 for square posts, 4:5 for the Instagram feed, 4:3 for slides and iPad, 16:10 for a Mac screen, 21:9 for a cinematic look. Point at one to see what it's for."),
                    L("Custom…: type any shape, like 3:2 or 2.39:1."),
                    L("The size menu: 720p, 1080p, 1440p (where they fit your screen) and Largest. The size above the frame, like 1920 × 1080, is the video's size in pixels."),
                    L("Fit a window to the frame…: choose a window of another app, and it takes exactly the frame's place and size."),
                    L("Window, Full screen, and Select area manually: record another way instead."),
                ],
                steps: [
                    L("Choose a shape, then a size."),
                    L("Drag the frame's border to move it. It snaps to the middle and the edges of the screen."),
                    L("Drag a corner to resize it. The shape stays the same."),
                    L("Click Record, or press Return."),
                ],
                keys: [
                    .fixed("← → ↑ ↓", L("Move the frame (with ⇧: 10 points)")),
                    .fixed("↩", L("Start recording")),
                    .fixed("Esc", L("Cancel")),
                    .fixed("⌃⌘Esc", L("Cancel the frame, from any app")),
                ],
                tips: [
                    L("Clicks and scrolling inside the frame and on the dimmed screen go to your apps, so you can set things up first. Only the frame's border and corners, and the bars, take clicks."),
                    L("Esc and the arrow keys work after you click the frame's border or the bars."),
                    L("The frame, the dimming, and the bars are never in the video. Nothing is recorded until you click Record."),
                    L("The bars move out of the frame's way. Drag them anywhere by the handle on the left."),
                    L("LF Studios remembers the last shape, size, and place on each screen."),
                    L("Fit a window to the frame needs Accessibility. LF Studios asks for it the first time."),
                    L("With Camera on and Layout ▸ Split screen, the frame is the screen's part of the video, and the camera's part shows beside it."),
                ],
                since: "1.8.0",
                related: ["howto-frame", "rec-area", "permission-accessibility", "camera-split"]
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
                    L("Turn on Camera. A preview of your camera appears, in the Camera shape chosen above the bar."),
                    L("Drag the preview where you want the camera in the video: what it covers of the recording frame is where the camera goes."),
                    L("Record as usual. The video opens in the editor with the camera there, in that shape and size."),
                ],
                tips: [
                    L("To get the preview out of the way, drag it outside the frame: the label says “Not in video”, and the editor puts the camera in its usual corner."),
                    L("The camera is saved separately and whole, so in the editor you can move it, resize it, restyle it, or hide it."),
                    L("The preview you see while recording never shows up in the screen recording itself."),
                    L("Click Camera again to turn the camera off completely."),
                ],
                showMe: .settings(.recording),
                since: "1.10.0",
                related: ["camera-shape", "camera-bubble", "permission-camera"]
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
                id: "rec-folder", symbol: "folder.badge.plus", title: L("Each recording in its own folder"),
                summary: L("After you stop, LF Studios asks where to save the recording, then puts everything from it in one new folder: the video, the camera, the sound, and the project that opens it all."),
                location: L("The save window appears after each recording. Settings ▸ Recording ▸ Saving has Ask where to save after each recording and the Recording folder."),
                points: [
                    L("01 Screen: the screen recording. 02 Camera: the camera video, if you recorded one."),
                    L("03 Audio: your microphone and the Mac's sound as separate files. 05 Captions: your captions, once you make them."),
                    L("07 Data: the pointer, clicks, and keys. And README.txt, which says what each file is."),
                    L("The project file opens everything again, exactly as you left it. LF Studios keeps it up to date as you edit."),
                ],
                tips: [
                    L("Click Cancel, or turn off asking, and it goes in the Recording folder, laid out the same way. Nothing is ever lost."),
                    L("Move or rename the folder in Finder as you like, or copy it to another Mac: it still opens."),
                    L("Files move only once the recording is finished and checked. If something goes wrong, the recording stays where it was."),
                ],
                showMe: .settings(.recording),
                since: "1.6.0",
                related: ["project-folder", "app-files"]
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
                location: L("It happens by itself. The bar while recording shows a short note, and a notice explains it."),
                points: [
                    L("Microphone unplugged: it switches to another one, or carries on without sound until one is plugged in."),
                    L("Camera unplugged: the screen recording keeps going without it."),
                    L("Disk almost full: it warns you, then stops and saves the recording before the disk is full."),
                    L("“Skipping frames”: your Mac can't keep up. Try Balanced quality or 30 fps."),
                ]
            ),
        ]
    }
    // MARK: Video editor

    static func videoEditorFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "video-open", symbol: "film", title: L("Opening a video"),
                summary: L("Open a recording, or any MP4 or MOV video, in the video editor."),
                location: L("Click a recording in Home, click Edit Video after recording, or click Open video… in Home. The LF Studios menu ▸ Edit Last Recording opens the newest one."),
                tips: [
                    L("You can also drop a video file on the LF Studios icon in the Dock."),
                    L("The editor has six panels on the right: Style, Cursor, Zoom, Camera, Captions, and Audio."),
                ],
                showMe: .home(.recordings)
            ),
            GuideEntry(
                id: "video-play", symbol: "play.circle", title: L("Playing & moving around"),
                summary: L("Play the video and move the playhead (the line that shows where you are) to any moment."),
                location: L("The timeline at the bottom of the video editor."),
                steps: [
                    L("Press Space to play and pause."),
                    L("Click or drag anywhere on the timeline to jump there."),
                    L("Pinch, or ⌘-scroll, on the timeline to see more detail."),
                ],
                keys: [
                    .fixed(L("Space"), L("Play / pause")),
                    .fixed("J  K  L", L("Back · pause · faster")),
                    .fixed("← →", L("Previous / next frame")),
                    .fixed("⇧← ⇧→", L("Jump one second")),
                    .fixed("⌘← ⌘→", L("Start / end")),
                ],
                related: ["video-timeline"]
            ),
            GuideEntry(
                id: "video-timeline", symbol: "rectangle.split.1x2", title: L("The timeline and its tracks"),
                summary: L("Every part of the video on its own track, top to bottom: Zooms, Video clips, Camera, Captions, Keys, Text & annotations, Music, and each sound you added."),
                location: L("The bottom of the video editor."),
                points: [
                    L("Drag the line above the timeline to make it taller or shorter; double-click it for the usual size. LF Studios remembers it."),
                    L("Track height (above the track names): Small, Medium, or Large. A window shorter than about 1000 points starts with Small tracks and a taller timeline, until you choose."),
                    L("Each track's eye hides it and its speaker mutes it, in the preview and the export. The lock keeps everything on it from changing."),
                    L("A track with nothing on it is a thin row that says how to add something. The arrow next to a name folds a track away."),
                ],
                steps: [
                    L("Scroll up and down when the tracks don't all fit; the ruler and the track names stay put."),
                    L("Pinch, ⌘-scroll, ⌘+ and ⌘−, or the slider on the right, to see more or less of the video."),
                ],
                tips: [L("Hiding or muting a track never deletes anything: turn it back on, and it's all there.")],
                since: "1.11.0",
                related: ["video-play", "video-clips"]
            ),
            GuideEntry(
                id: "video-clips", symbol: "scissors", title: L("Split, trim & reorder clips"),
                summary: L("Cut the recording into clips, shorten them, and change their order."),
                location: L("The clips lane on the timeline, and the Timeline menu."),
                steps: [
                    L("Move the playhead and press S to split the clip there."),
                    L("Drag a clip's edge to trim it, or press I or O to make it start or end at the playhead."),
                    L("Drag a clip by its name to move it. Click a clip and press ⌫ to delete it."),
                ],
                keys: [
                    .fixed("S", L("Split at the playhead")),
                    .fixed("I  O", L("Clip starts / ends here")),
                    .fixed("⌫", L("Delete the selection")),
                ],
                tips: [L("Right-click a clip for Speed, Mute Clip, Move Earlier, and Move Later.")]
            ),
            GuideEntry(
                id: "video-cut-part", symbol: "rectangle.badge.minus", title: L("Cut out a part"),
                summary: L("Select any stretch of the video and remove it, even across several clips."),
                location: L("Hold ⇧ and drag on the timeline."),
                steps: [
                    L("Hold ⇧ and drag across the part you don't want."),
                    L("Click Cut this part in the panel on the right."),
                ],
                keys: [.fixed(L("⇧-drag"), L("Select a range to cut"))],
                tips: [L("A yellow marker shows where something was cut. Click it to bring the part back.")],
                related: ["howto-cut"]
            ),
            GuideEntry(
                id: "video-speed", symbol: "gauge.with.dots.needle.67percent", title: L("Speed"),
                summary: L("Speed up slow parts, or slow down fast ones."),
                location: L("Select a clip, or ⇧-drag a part, and choose its Speed in the panel on the right."),
                points: [
                    L("Speeds from 0.5× to 16×."),
                    L("Speed Up Idle on the timeline fast-forwards the moments when nothing happens."),
                ],
                related: ["cursor-typing-speed"]
            ),
            GuideEntry(
                id: "video-transitions", symbol: "rectangle.portrait.on.rectangle.portrait.angled", title: L("Transitions & fades"),
                summary: L("Blend from one clip into the next, and fade in and out of black."),
                location: L("Style panel ▸ Transitions, or click the + between two clips on the timeline."),
                points: [
                    L("Between clips: Hard cut, Dissolve, or Dip to black, with a Length."),
                    L("Fade in from black and Fade out to black for the start and end."),
                ],
                showMe: .editor(.background)
            ),
            GuideEntry(
                id: "video-cards", symbol: "rectangle.and.text.magnifyingglass", title: L("Intro & outro cards"),
                summary: L("Add a title card before the video and a closing card after it."),
                location: L("Style panel ▸ Intro & outro."),
                steps: [
                    L("Turn on Intro card or Outro card."),
                    L("Type a Title and Subtitle, and set the Length."),
                ],
                tips: [L("The cards use the same background as your video. Pick their font with the font menu.")],
                showMe: .editor(.background)
            ),
            GuideEntry(
                id: "video-annotations", symbol: "arrow.up.right.square", title: L("Text, arrows & highlights"),
                summary: L("Add text, arrows, highlights, and spotlights on top of the video."),
                location: L("The tool buttons above the preview: Text, Arrow, Highlight, Blur, Spotlight, and Image."),
                steps: [
                    L("Move the playhead to where it should appear."),
                    L("Click a tool, or press its key."),
                    L("Drag it on the preview to place it; drag a corner to resize it."),
                    L("On the timeline, drag its edges to set how long it shows."),
                ],
                keys: [
                    .fixed("T", L("Text")), .fixed("A", L("Arrow")), .fixed("H", L("Highlight")), .fixed("B", L("Blur")),
                    .fixed("⌘D", L("Duplicate zoom or annotation")),
                ],
                tips: [L("Double-click text on the preview to change it. New ones keep the last color and size you used.")]
            ),
            GuideEntry(
                id: "video-images", symbol: "photo", title: L("Images & logos"),
                summary: L("Put a logo, a watermark, or a picture on the video."),
                location: L("Click Image above the preview."),
                steps: [
                    L("Choose a picture."),
                    L("Drag it into place, or pick a corner under Position."),
                    L("Set Size and Opacity. Turn on Show for the whole video for a watermark."),
                ]
            ),
            GuideEntry(
                id: "video-crop", symbol: "crop", title: L("Crop the recording"),
                summary: L("Trim toolbars, the menu bar, or empty space off the edges of the recording."),
                location: L("Click Crop in the editor's toolbar."),
                steps: [
                    L("Click Crop."),
                    L("Drag the frame's edges, or pick a shape like 16:9."),
                    L("Click Done, or press Return."),
                ],
                keys: [.fixed("↩", L("Done")), .fixed("Esc", L("Cancel"))],
                tips: [L("The cursor, zooms, and clicks follow the crop.")]
            ),
            GuideEntry(
                id: "video-undo", symbol: "arrow.uturn.backward", title: L("Undo, redo & start over"),
                summary: L("Every change can be undone, step by step."),
                location: L("The Undo and Redo buttons in the editor's toolbar."),
                keys: [.fixed("⌘Z", L("Undo")), .fixed("⇧⌘Z", L("Redo"))],
                tips: [
                    L("Hover over Undo to see what it will undo."),
                    L("To begin again, open the commands (⌘K) and choose Start Over from the Original Recording…. It asks first, and can be undone too."),
                ]
            ),
            GuideEntry(
                id: "video-commands", symbol: "command.square", title: L("Commands & shortcuts list"),
                summary: L("Find any action by typing its name, and see every key the editor knows."),
                location: L("The ⌘ and ? buttons in the editor's toolbar."),
                keys: [.fixed("⌘K", L("All commands")), .fixed("?", L("Keyboard Shortcuts"))],
            ),
            GuideEntry(
                id: "video-markers", symbol: "flag", title: L("Markers"),
                summary: L("Flags on the timeline for important moments. They can split the video and become chapters."),
                location: L("Click Marker on the timeline's toolbar. Markers added while recording are there too."),
                points: [
                    L("Click a marker to jump there; double-click to rename it; right-click to delete it."),
                    L("Split at Markers splits the clips at every marker."),
                ],
                related: ["export-chapters", "rec-markers"]
            ),
            GuideEntry(
                id: "video-append", symbol: "film.stack", title: L("Append Video"),
                summary: L("Add another recording to the end of this one, to make one video."),
                location: L("Style panel ▸ Recordings ▸ Append Video…."),
                tips: [L("Change the order with Move earlier and Move later, or remove one with Remove from this video.")],
                showMe: .editor(.background)
            ),
            GuideEntry(
                id: "video-copy-frame", symbol: "photo.on.rectangle", title: L("Copy the current frame"),
                summary: L("Copy the picture at the playhead, to paste it anywhere."),
                location: L("Press ⌘C in the video editor, or choose Copy Current Frame in the commands (⌘K)."),
                keys: [.fixed("⌘C", L("Copy current frame"))]
            ),
            GuideEntry(
                id: "video-select", symbol: "checkmark.rectangle.stack", title: L("Selecting things"),
                summary: L("Click anything on the timeline or the preview to change it in the panel on the right."),
                location: L("The “Selected” panel appears at the top right when something is selected."),
                keys: [
                    .fixed(L("⇧/⌘-click"), L("Select several items")),
                    .fixed("⌥← ⌥→", L("Select previous / next item")),
                    .fixed("Esc", L("Deselect / close")),
                ]
            ),
            GuideEntry(
                id: "video-tips", symbol: "lightbulb", title: L("Editor tips"),
                summary: L("Short tips under the preview while you learn the editor."),
                location: L("Under the video preview. Hide them with ×; bring them back from the shortcuts list (?)."),
            ),
        ]
    }

    // MARK: Zoom

    static func zoomFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "zoom-add", symbol: "plus.magnifyingglass", title: L("Add a zoom"),
                summary: L("Zoom in on part of the video so details are easy to see."),
                location: L("Click Zoom above the preview, or click the zoom lane on the timeline."),
                steps: [
                    L("Move the playhead to where the zoom should start."),
                    L("Press Z, or click Zoom."),
                    L("Drag the zoom's edges on the timeline to set its length."),
                ],
                keys: [.fixed("Z", L("Add a zoom at the playhead")), .fixed("⌘D", L("Duplicate zoom or annotation"))],
                showMe: .editor(.zoom),
                related: ["zoom-edit"]
            ),
            GuideEntry(
                id: "zoom-edit", symbol: "slider.horizontal.below.square.filled.and.square", title: L("Change a zoom"),
                summary: L("Choose how far a zoom goes in and where it looks."),
                location: L("Click a zoom on the timeline; its settings appear in the panel on the right."),
                points: [
                    L("Zoom level: how close it goes. Use this level for every zoom applies it to all."),
                    L("Framing: Follow cursor follows the pointer; Aim by hand lets you drag the frame on the preview; Follow typing follows your typing."),
                    L("Right-click a zoom on the timeline for quick changes."),
                ],
                keys: [.fixed("1 – 5", L("Zoom level of the selected zoom"))],
                showMe: .editor(.zoom),
                related: ["camera-follows-cursor"]
            ),
            GuideEntry(
                id: "zoom-auto", symbol: "cursorarrow.click.2", title: L("Auto-zoom on clicks"),
                summary: L("Adds a zoom wherever you clicked while recording."),
                location: L("Zoom panel ▸ Auto-zoom on clicks."),
                steps: [
                    L("Turn on Auto-zoom on clicks."),
                    L("Watch the result, then change or delete any zoom."),
                ],
                tips: [
                    L("Turning it off removes its zooms again; zooms you added yourself stay."),
                    L("Needs clicks recorded by LF Studios."),
                ],
                showMe: .editor(.zoom)
            ),
            GuideEntry(
                id: "zoom-motion", symbol: "wind", title: L("Zoom motion"),
                summary: L("Choose how quickly and smoothly zooms move."),
                location: L("Zoom panel ▸ Motion: Slow, Smooth, Quick, or Instant, plus Motion blur."),
                tips: [L("These, and New zooms, are for auto-zoom; turn on Auto-zoom on clicks to use them.")],
                showMe: .editor(.zoom)
            ),
            GuideEntry(
                id: "zoom-loupe", symbol: "magnifyingglass.circle", title: L("Loupe"),
                summary: L("A round magnifier over one spot, while the rest of the video stays in view."),
                location: L("Zoom panel ▸ Add Loupe. Or select a zoom and choose Type ▸ Loupe."),
                steps: [
                    L("Click Add Loupe."),
                    L("Drag it over what you want to show."),
                    L("Set its size, shape, border, and shadow under Loupe."),
                ],
                tips: [L("New loupes take the look of the last one you changed.")],
                showMe: .editor(.zoom),
                since: "1.4.0"
            ),
            GuideEntry(
                id: "zoom-typing", symbol: "character.cursor.ibeam", title: L("Typing zooms"),
                summary: L("Zooms that follow your text cursor while you type, so viewers can read along."),
                location: L("Zoom panel ▸ Add typing zooms."),
                steps: [
                    L("Before recording, turn on Track where I type."),
                    L("In the editor, click Add typing zooms."),
                ],
                tips: [L("Clicking it again replaces only those zooms. Each can be changed like any zoom.")],
                showMe: .editor(.zoom),
                since: "1.4.0",
                related: ["rec-typing"]
            ),
            GuideEntry(
                id: "zoom-camera-fit", symbol: "person.crop.rectangle", title: L("Fit zooms around the camera"),
                summary: L("Keeps the camera bubble from covering what a zoom shows."),
                location: L("Zoom panel ▸ Fit zooms around camera."),
                points: [
                    L("Shift the Zooms: moves each zoom clear of the bubble."),
                    L("Move the Camera Instead: slides the bubble to a free corner during that zoom."),
                ],
                tips: [L("It tells you how many zooms it changed, and one ⌘Z undoes it.")],
                showMe: .editor(.zoom),
                since: "1.4.0"
            ),
        ]
    }
    // MARK: Cursor

    static func cursorFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "cursor-show", symbol: "cursorarrow", title: L("Show & size the cursor"),
                summary: L("Show or hide the pointer, and make it bigger so viewers can follow it."),
                location: L("Cursor panel ▸ Cursor: Show cursor and Size."),
                tips: [L("Needs Editable Cursor on while recording (it's on to start with). Otherwise the pointer is part of the picture and can't be changed.")],
                showMe: .editor(.cursor),
                related: ["rec-cursor"]
            ),
            GuideEntry(
                id: "cursor-smooth", symbol: "scribble", title: L("Smooth cursor movement"),
                summary: L("Turn shaky mouse moves into calm, smooth glides."),
                location: L("Cursor panel ▸ Movement."),
                points: [
                    L("Off, Light, Smooth, or Silky."),
                    L("Motion blur adds a soft trail when the pointer moves fast."),
                    L("Hide when idle hides the pointer while it rests; Hide the move to Stop hides the trip to the stop button at the end."),
                ],
                showMe: .editor(.cursor)
            ),
            GuideEntry(
                id: "cursor-clicks", symbol: "cursorarrow.click", title: L("Click effects"),
                summary: L("Show each click, so viewers see what you pressed."),
                location: L("Cursor panel ▸ Clicks: None, Press, or Ripple."),
                tips: [L("For a click sound too, see Click sounds in the Audio panel.")],
                showMe: .editor(.cursor),
                related: ["audio-clicks"]
            ),
            GuideEntry(
                id: "cursor-styles", symbol: "cursorarrow.rays", title: L("Cursor styles"),
                summary: L("Change how the pointer looks: macOS classic, White, Outlined, Touch dot, Ring, or your own picture."),
                location: L("Cursor panel ▸ Appearance ▸ Style."),
                steps: [
                    L("Choose a style."),
                    L("For Custom image…, choose a PNG, then click the spot in it that points."),
                ],
                tips: [L("Styles are saved in presets and project files.")],
                showMe: .editor(.cursor),
                since: "1.4.0"
            ),
            GuideEntry(
                id: "cursor-loop", symbol: "repeat", title: L("Looping cursor"),
                summary: L("The pointer glides back to where it started at the end, so the video loops without a jump."),
                location: L("Cursor panel ▸ Loop ▸ Return to start at the end."),
                tips: [L("Glide time sets how long the trip back takes. Great for GIFs.")],
                showMe: .editor(.cursor)
            ),
            GuideEntry(
                id: "cursor-keys", symbol: "command", title: L("Keys on screen"),
                summary: L("Show the keyboard shortcuts you pressed, like ⌘C, as keys on the video."),
                location: L("Cursor panel ▸ Keys on screen ▸ Show shortcuts."),
                steps: [
                    L("Turn on Show shortcuts."),
                    L("Choose a Size, a font, and Top or Bottom. Or drag the keys on the preview."),
                    L("To hide one, click it on the timeline and press ⌫."),
                ],
                tips: [L("Needs Show keyboard shortcuts on while recording.")],
                showMe: .editor(.cursor),
                related: ["rec-shortcuts"]
            ),
            GuideEntry(
                id: "cursor-typing-speed", symbol: "hare", title: L("Speed up typing"),
                summary: L("Speed through the parts where you type, so viewers don't wait."),
                location: L("Cursor panel ▸ Typing ▸ Speed up typing to 2×, 3×, 4×, 6×, or 8×."),
                steps: [
                    L("Choose a speed. The typing parts become speed blocks on the timeline."),
                    L("Choose again with another speed to change them."),
                ],
                tips: [L("Works best with Record when keys are pressed on while recording. For older recordings, LF Studios guesses from the screen and says so.")],
                showMe: .editor(.cursor),
                since: "1.4.0",
                related: ["rec-keys-pressed"]
            ),
        ]
    }

    // MARK: Camera

    static func cameraFeatures() -> [GuideEntry] {
        let needsCamera = L("Needs a recording made with the camera on, or a camera video you added.")
        return [
            GuideEntry(
                id: "camera-bubble", symbol: "person.crop.circle", title: L("The camera bubble"),
                summary: L("Your face in a bubble over the video. Move it, resize it, and choose its shape."),
                location: L("Camera panel ▸ Camera, Position, and Behavior. Click the bubble on the preview to open it."),
                points: [
                    L("Camera shape: Circle, Rounded rectangle, Square, Landscape, Portrait, 4:3, 3:4, Free, or Cutout (just you, without the background)."),
                    L("Position and Size: drag the camera on the preview, drag its edges and corners to resize it, or pick one of eight spots."),
                    L("Mirror flips it like a mirror."),
                ],
                tips: [needsCamera],
                showMe: .editor(.camera),
                related: ["rec-camera"]
            ),
            GuideEntry(
                id: "camera-shape", symbol: "rectangle.on.rectangle", title: L("Camera shape"),
                summary: L("Choose the camera's shape and ratio before you record, and change it any time in the editor."),
                location: L("Before recording: turn on Camera, then Camera shape above the recording bar. In the editor: Camera panel ▸ Camera ▸ Camera shape."),
                points: [
                    L("Circle, Rounded rectangle, Square (1:1), Landscape (16:9), Portrait (9:16), 4:3, 3:4, or Free (any width and height)."),
                    L("Roundness, in the same menu: from sharp corners to round."),
                ],
                steps: [
                    L("Turn on Camera in the recording bar."),
                    L("Choose Camera shape. The camera preview takes that shape right away, so you can frame yourself."),
                    L("Record. The video opens in the editor with the camera in that shape."),
                ],
                tips: [
                    L("The camera is always recorded whole: the shape is only a setting, so you can change it later, and Creative Handoff gets the whole camera picture."),
                    L("LF Studios remembers your last shape for the next recording."),
                ],
                showMe: .editor(.camera),
                since: "1.10.0",
                related: ["rec-camera", "camera-bubble", "camera-look"]
            ),
            GuideEntry(
                id: "camera-size", symbol: "arrow.up.left.and.arrow.down.right", title: L("Select size"),
                summary: L("Resize and place the camera by dragging, before you record and in the editor."),
                location: L("Before recording: Select size above the recording bar, with Camera on. In the editor: drag the camera on the preview."),
                steps: [
                    L("Click Select size. Handles appear on the camera preview."),
                    L("Drag an edge or a corner to resize it, the middle to move it."),
                    L("The label under it says how wide the camera is and where it goes in the video. The editor opens with exactly that."),
                ],
                tips: [
                    L("A fixed shape (Circle, 1:1, 16:9…) keeps its shape as you resize. With Free, width and height change on their own; hold ⇧ to keep the shape."),
                    L("In the editor, the camera snaps to the corners, the edges and the center. Each drag is one ⌘Z. Reset size in Camera ▸ Position goes back to the usual size."),
                ],
                showMe: .editor(.camera),
                since: "1.10.0",
                related: ["camera-shape", "rec-camera", "camera-bubble"]
            ),
            GuideEntry(
                id: "camera-split", symbol: "rectangle.split.2x1", title: L("Split screen"),
                summary: L("The screen and your camera each fill one part of the video: side by side, or one above the other."),
                location: L("Before recording: turn on Camera, then Layout ▸ Split screen above the recording bar. In the editor: Camera panel ▸ Layout."),
                points: [
                    L("Direction: Side by side (left and right) or Stacked (top and bottom), on a video of any shape. Until you choose, landscape videos go side by side and square and vertical ones stacked."),
                    L("Camera side, Split size (from 30/70 to 70/30, 50/50 to start), and Gap, with the video's background in between."),
                ],
                steps: [
                    L("Choose Layout ▸ Split screen, and a Direction. The frame becomes the screen's part, like 8:9 for a 16:9 video split side by side, or 32:9 stacked, and the camera preview fills the camera's part."),
                    L("Arrange what you'll show inside the frame: it fills the screen's part exactly, without stretching or black bars."),
                    L("Record. The video opens in the editor already split."),
                ],
                tips: [
                    L("In the editor, drag the divider on the video to change the split. Zooms happen inside the screen's part; captions go over the whole video."),
                    L("Adapt to this ratio keeps the Direction you chose. If you never chose one, it follows the new shape: left becomes top, right becomes bottom."),
                    L("Layout also has Screen only and Camera only. The screen and the camera are always both recorded, so you can change your mind later."),
                    L("Creative Handoff's README.txt says where each part goes, in pixels, for your editing app."),
                ],
                showMe: .editor(.camera),
                since: "1.11.0",
                related: ["camera-layouts", "rec-frame", "camera-shape"]
            ),
            GuideEntry(
                id: "camera-behind", symbol: "person.and.background.dotted", title: L("Blur or remove your background"),
                summary: L("Blur what's behind you, or remove it completely."),
                location: L("Camera panel ▸ Camera ▸ Behind you: Original, Blur, or Remove."),
                tips: [L("LF Studios finds your outline on this Mac. Choose the Cutout shape to show just you, floating over the video.")],
                showMe: .editor(.camera)
            ),
            GuideEntry(
                id: "camera-look", symbol: "circle.dashed.rectangle", title: L("Camera crop, roundness, border & shadow"),
                summary: L("Choose what the bubble shows and give it a finished look."),
                location: L("Camera panel ▸ Look."),
                points: [
                    L("Crop…: drag a frame over the camera picture to choose what the bubble shows."),
                    L("Roundness: from sharp corners to a full circle."),
                    L("Border, in any color and thickness, and Shadow."),
                ],
                showMe: .editor(.camera)
            ),
            GuideEntry(
                id: "camera-layouts", symbol: "rectangle.on.rectangle.angled", title: L("Camera layouts"),
                summary: L("Show the camera full screen, side by side with the screen, or hide it, for any part of the video."),
                location: L("Camera panel ▸ Layouts."),
                steps: [
                    L("Move the playhead and click Full camera, Side by side, or Hidden (on a split video, also Bubble)."),
                    L("A block appears on the Camera lane: drag it to move it, drag its edges to change its length."),
                ],
                tips: [
                    L("Full camera for intro & outro starts and ends the video with you full screen."),
                    L("Side by side uses Split screen's options (Camera panel ▸ Layout): the camera's side, the split size, and the gap. Each change eases in and out."),
                ],
                showMe: .editor(.camera),
                since: "1.10.0",
                related: ["camera-split"]
            ),
            GuideEntry(
                id: "camera-face", symbol: "face.dashed", title: L("Keep face centered"),
                summary: L("The bubble follows your face, so you stay in the middle even when you move."),
                location: L("Camera panel ▸ Face tracking ▸ Keep face centered."),
                steps: [
                    L("Turn on Keep face centered. LF Studios looks for your face once, with progress and Cancel."),
                    L("Set Smoothness (how calmly it follows) and Framing (how close it is)."),
                ],
                tips: [L("It works on your Mac with Apple's face detection. If your face isn't found for a while, the last framing holds.")],
                showMe: .editor(.camera),
                since: "1.4.0"
            ),
            GuideEntry(
                id: "camera-silences", symbol: "person.crop.circle.badge.moon", title: L("Hide camera during silences"),
                summary: L("Hide the camera whenever you're not talking, and bring it back when you speak."),
                location: L("Camera panel ▸ Silences ▸ Hide camera during silences."),
                steps: [
                    L("Set the Minimum silence (1 to 10 seconds)."),
                    L("Click Hide camera during silences. Hide blocks appear on the Camera lane."),
                ],
                tips: [L("Clicking it again replaces only those blocks; ones you made yourself stay. Needs a recording with your voice.")],
                showMe: .editor(.camera),
                since: "1.4.0"
            ),
            GuideEntry(
                id: "camera-color", symbol: "camera.filters", title: L("Camera color"),
                summary: L("Make your camera look its best: brighter, warmer, or more cinematic."),
                location: L("Camera panel ▸ Color."),
                points: [
                    L("Looks: Natural, Warm, Bright, or Cinematic."),
                    L("Brightness, Contrast, Saturation, Warmth, Tint, and Sharpness."),
                    L("Auto adjust picks settings for you; Reset goes back."),
                ],
                tips: [L("Changes only the camera, never your screen.")],
                showMe: .editor(.camera),
                since: "1.4.0"
            ),
            GuideEntry(
                id: "camera-import", symbol: "iphone.and.arrow.forward", title: L("Add a camera video from a phone"),
                summary: L("Filmed yourself with a phone or a camera? Put that video in the bubble instead."),
                location: L("Camera panel ▸ Camera video ▸ Add camera video…."),
                steps: [
                    L("Click Add camera video… and choose the video."),
                    L("LF Studios lines it up with your recording by its sound."),
                    L("If it's slightly off, use Offset, Sync by Sound, or drag the camera strip on the timeline."),
                ],
                tips: [L("The video stays where it is. If you move or delete it, LF Studios offers Locate….")],
                showMe: .editor(.camera)
            ),
            GuideEntry(
                id: "camera-shrink", symbol: "arrow.down.right.and.arrow.up.left", title: L("Shrink while zoomed"),
                summary: L("Makes the bubble smaller during zooms, so it covers less."),
                location: L("Camera panel ▸ Behavior ▸ Shrink while zoomed."),
                tips: [L("Works with Auto-zoom on clicks.")],
                showMe: .editor(.camera)
            ),
            GuideEntry(
                id: "camera-follows-cursor", symbol: "cursorarrow.motionlines", title: L("Camera follows your cursor"),
                summary: L("During a zoom, the view moves with your pointer, so what you point at stays in the picture. The preview says “Camera follows your cursor” while it does."),
                location: L("Click a zoom on the timeline, then choose Framing ▸ Follow cursor."),
                tips: [
                    L("Here “camera” means the view of your screen, not your camera bubble."),
                    L("For a vertical video, Fill the Frame, Follow the Cursor in the aspect ratio menu does the same for the whole video."),
                ],
                showMe: .editor(.zoom),
                related: ["zoom-edit", "size-reframe"]
            ),
        ]
    }
    // MARK: Captions

    static func captionFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "captions-transcribe", symbol: "waveform.and.mic", title: L("Transcribe"),
                summary: L("LF Studios listens to your recording and writes down what you say, on your Mac. That gives you captions, and lets you edit the video by its words."),
                location: L("Captions panel ▸ Transcribe."),
                steps: [
                    L("Choose the Language you speak in the recording."),
                    L("Click Transcribe. Keep editing while it listens."),
                ],
                tips: [
                    L("Nothing is uploaded. The first time, macOS may download the language, which needs the internet once."),
                    L("On macOS 15 and earlier, it needs Speech Recognition allowed, and Dictation set up for that language."),
                ],
                showMe: .editor(.captions),
                related: ["captions-whisper", "trouble-transcribe"]
            ),
            GuideEntry(
                id: "captions-whisper", symbol: "waveform.badge.magnifyingglass", title: L("Whisper"),
                summary: L("A second way to transcribe that's often more accurate, especially with accents or noise."),
                location: L("Captions panel ▸ Engine ▸ Whisper."),
                steps: [
                    L("Choose Whisper, then a Model."),
                    L("Click Download the first time. Models range from Tiny (about 75 MB, fastest) to Large v3 Turbo (about 630 MB, most accurate)."),
                    L("Click Transcribe with Whisper."),
                ],
                tips: [
                    L("The model downloads once from Hugging Face. After that, Whisper works offline, and your recording is never uploaded."),
                    L("If a model is too much for this Mac, LF Studios says so and suggests a smaller one. Manage models in Settings ▸ General ▸ Whisper Models."),
                ],
                showMe: .editor(.captions),
                since: "1.4.0",
                related: ["app-whisper"]
            ),
            GuideEntry(
                id: "captions-edit-text", symbol: "text.word.spacing", title: L("Edit by text"),
                summary: L("Edit your video like a document: delete words, and that part of the video goes."),
                location: L("Captions panel ▸ Edit by text (after transcribing)."),
                steps: [
                    L("Select words and press ⌫ to cut them from the video."),
                    L("Press ⌫ again on crossed-out words to bring them back."),
                    L("Click a word to jump there."),
                ],
                keys: [.fixed("⌫", L("Cut the selected words")), .fixed("⌘F", L("Find in the transcript"))],
                showMe: .editor(.captions)
            ),
            GuideEntry(
                id: "captions-cleanup", symbol: "wand.and.stars", title: L("Remove ums & shorten pauses"),
                summary: L("Cut filler words like “um” and “uh”, and long pauses, in one click each."),
                location: L("Captions panel ▸ Edit by text ▸ Remove ums and Shorten pauses."),
                tips: [L("Pauses longer than a second become short ones, except where you're clicking, typing, or moving the pointer. ⌘Z undoes either one.")],
                showMe: .editor(.captions)
            ),
            GuideEntry(
                id: "captions-look", symbol: "textformat.size", title: L("Caption style"),
                summary: L("Choose how captions look: style, color, font, size, and place."),
                location: L("Captions panel ▸ Look."),
                points: [
                    L("Styles: Classic, Bold outline, Minimal, or Highlight."),
                    L("Highlight words lights up each word as it's spoken."),
                    L("Font, Size (S, M, L), and Position (Bottom or Top)."),
                ],
                showMe: .editor(.captions),
                related: ["style-fonts"]
            ),
            GuideEntry(
                id: "captions-animation", symbol: "text.badge.star", title: L("Caption animations"),
                summary: L("Bring captions to life: words that pop in, a karaoke fill, a typewriter, and more."),
                location: L("Captions panel ▸ Look ▸ Animation."),
                points: [L("None, Pop-in words, One word at a time, Karaoke fill, Typewriter, Bounce, Fade up, or Highlight box.")],
                tips: [L("They follow your spoken words, and look the same in the preview and the export.")],
                showMe: .editor(.captions),
                since: "1.4.0"
            ),
            GuideEntry(
                id: "captions-place", symbol: "arrow.up.and.down.and.arrow.left.and.right", title: L("Place captions anywhere"),
                summary: L("Drag captions to any spot on the video, or move one caption on its own."),
                location: L("Pause the video and drag the caption on the preview."),
                points: [
                    L("It snaps to the middle and to the safe edges, with guide lines."),
                    L("Select one caption first to move only that one. Apply this position to all captions moves the rest there too."),
                    L("Reset position puts captions back at the bottom."),
                ],
                showMe: .editor(.captions)
            ),
            GuideEntry(
                id: "captions-lines", symbol: "list.bullet", title: L("Edit caption lines"),
                summary: L("Fix words, change timing, and add captions by hand."),
                location: L("Captions panel ▸ Lines."),
                points: [
                    L("Click a line to edit its words; click its time to jump there; × removes it."),
                    L("+ adds a caption at the playhead. No transcript? Use Or type one at the playhead."),
                    L("Select a caption on the timeline to change when it starts and ends."),
                ],
                showMe: .editor(.captions)
            ),
            GuideEntry(
                id: "captions-translate", symbol: "globe", title: L("Translate captions"),
                summary: L("Add a second set of captions in another language."),
                location: L("Captions panel ▸ Languages."),
                steps: [
                    L("Choose a language and click Translate."),
                    L("Use Show to pick which captions the video shows."),
                ],
                tips: [L("Needs macOS 15 or later. Translated on your Mac; macOS downloads each language once.")],
                showMe: .editor(.captions)
            ),
            GuideEntry(
                id: "captions-subtitles", symbol: "doc.plaintext", title: L("Save subtitles"),
                summary: L("Save captions as a subtitles file for YouTube, Vimeo, or a video player."),
                location: L("Captions panel ▸ Save Subtitles, or File ▸ Save Subtitles (.srt)…."),
                tips: [L("Choose .srt or .vtt. The file follows your cuts and speed changes.")],
                showMe: .editor(.captions),
                related: ["export-captions"]
            ),
            GuideEntry(
                id: "captions-notes", symbol: "note.text", title: L("Speaker notes in the editor"),
                summary: L("The notes you read from while recording, kept with the video."),
                location: L("At the top of the Captions panel, for recordings made with Speaker notes open."),
                tips: [L("Click Copy notes to use them elsewhere.")],
                showMe: .editor(.captions),
                since: "1.4.0",
                related: ["rec-notes"]
            ),
        ]
    }

    // MARK: Audio

    static func audioFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "audio-levels", symbol: "slider.vertical.3", title: L("Volume & mute"),
                summary: L("Set how loud your voice and your Mac's sound are, or mute the video."),
                location: L("Audio panel ▸ Sound."),
                points: [
                    L("Voice and Computer sound each have their own slider."),
                    L("Mute video exports it without sound."),
                ],
                keys: [.fixed("M", L("Mute the preview (or the selected clip)"))],
                tips: [L("M only quiets the preview; the export keeps its sound.")],
                showMe: .editor(.audio)
            ),
            GuideEntry(
                id: "audio-enhance", symbol: "waveform.badge.plus", title: L("Enhance voice"),
                summary: L("Removes background noise and hum, and evens out your voice."),
                location: L("Audio panel ▸ Voice ▸ Enhance voice."),
                tips: [L("Processed on your Mac.")],
                showMe: .editor(.audio)
            ),
            GuideEntry(
                id: "audio-podcast", symbol: "mic.circle", title: L("Podcast mode"),
                summary: L("Make your voice sound like a podcast: clean, warm, and clear."),
                location: L("Audio panel ▸ Podcast ▸ Podcast mode."),
                points: [L("Noise removal, De-esser (softens “s” sounds), Warm and clear EQ, Compression, and Podcast loudness: each with its own switch.")],
                tips: [L("While it's on, it takes the place of Enhance voice and Even out loudness.")],
                showMe: .editor(.audio),
                since: "1.4.0"
            ),
            GuideEntry(
                id: "audio-loudness", symbol: "speaker.wave.3", title: L("Even out loudness"),
                summary: L("Exports at the loudness video sites expect, without distortion."),
                location: L("Audio panel ▸ Export ▸ Even out loudness."),
                showMe: .editor(.audio)
            ),
            GuideEntry(
                id: "audio-music", symbol: "music.note", title: L("Music"),
                summary: L("Play a song under your video. It loops, fades in and out, and gets quieter while you talk."),
                location: L("Audio panel ▸ Music ▸ Add Music…."),
                points: [
                    L("Volume, and Lower under your voice."),
                    L("Fade in, Fade out, Loop to fill, and Start the song at."),
                ],
                tips: [L("Use music you have the rights to. Click the music lane on the timeline to get back here.")],
                showMe: .editor(.audio),
                related: ["howto-music"]
            ),
            GuideEntry(
                id: "audio-added", symbol: "waveform.badge.plus", title: L("Add sound files"),
                summary: L("Add a voiceover, a separate microphone, or a sound effect. Each file is its own track on the timeline."),
                location: L("Audio panel ▸ Added sound ▸ Add audio…, or drop sound files on the timeline."),
                steps: [
                    L("Click Add audio… and choose one or more files: MP3, WAV, M4A, AAC, AIFF, FLAC, or CAF."),
                    L("Drag the track on the timeline to move it; drag an edge to trim it; click it and press S to split it, or ⌫ to delete a piece."),
                    L("Set its Volume, Fade in, and Fade out, or Mute it, in the Audio panel."),
                    L("Recorded at the same time as the video? Click Sync by sound: it lines up with the recording and follows your cuts from then on."),
                ],
                keys: [.fixed("S", L("Split at the playhead")), .fixed("⌫", L("Delete the selection"))],
                tips: [
                    L("A new track sits on the edit's timeline, where you put it. After Sync by sound it follows the recording instead."),
                    L("Added sound is in the export, Full Mix, Creative Handoff, and the timeline files, and saved in a recording's folder (03 Audio)."),
                ],
                showMe: .editor(.audio),
                since: "1.7.0",
                related: ["audio-voice", "audio-music"]
            ),
            GuideEntry(
                id: "audio-voice", symbol: "mic.badge.plus", title: L("Use a sound file as your voice"),
                summary: L("Recorded your voice separately, or re-recorded it? Use that file in place of the recording's microphone."),
                location: L("Audio panel ▸ Added sound ▸ the track ▸ Use as my voice."),
                points: [
                    L("Use as my voice: the recording's microphone goes quiet and this track is the voice. Enhance voice and Podcast mode clean it up, and the music dips under it."),
                    L("Dip under voice: an added track (like background sound) gets quieter while you talk. It's off until you turn it on."),
                ],
                tips: [L("Sync it by sound first, so captions made from it line up with the video.")],
                showMe: .editor(.audio),
                since: "1.7.0",
                related: ["audio-added", "audio-enhance", "audio-podcast"]
            ),
            GuideEntry(
                id: "audio-clicks", symbol: "hand.tap", title: L("Click sounds"),
                summary: L("Play a soft click sound on every mouse click in the video."),
                location: L("Audio panel ▸ Click sounds ▸ Play a click on each click."),
                tips: [L("Needs clicks recorded by LF Studios. Set the Click volume.")],
                showMe: .editor(.audio)
            ),
            GuideEntry(
                id: "audio-clip", symbol: "speaker.slash", title: L("Mute or fade one part"),
                summary: L("Silence one clip or part, or fade its sound in and out."),
                location: L("Select a clip for Mute this clip, Fade in, and Fade out. Or ⇧-drag a part and choose Mute this part."),
                keys: [.fixed("M", L("Mute the preview (or the selected clip)"))]
            ),
        ]
    }
    // MARK: Style & presets

    static func styleFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "style-background", symbol: "photo.on.rectangle.angled", title: L("Background"),
                summary: L("Put your recording on a wallpaper, a gradient, a color, or your own picture."),
                location: L("Style panel ▸ Background."),
                points: [
                    L("Wallpaper, Gradient, Color, or Image. Wallpaper includes the ones on your Mac."),
                    L("The dice button picks one at random."),
                    L("Background blur softens a wallpaper or picture."),
                ],
                showMe: .editor(.background)
            ),
            GuideEntry(
                id: "style-frame", symbol: "square.on.square.dashed", title: L("Frame: padding, corners & shadow"),
                summary: L("Give the video space around it, rounded corners, and a shadow."),
                location: L("Style panel ▸ Frame."),
                points: [
                    L("Padding, Roundness, and Shadow."),
                    L("Fine-tune shadow adds angle, distance, softness, opacity, color, and Inset."),
                    L("Full frame (no background) shows the video edge to edge again."),
                ],
                showMe: .editor(.background)
            ),
            GuideEntry(
                id: "style-presets", symbol: "square.stack.3d.up", title: L("Style presets"),
                summary: L("Save a whole look under a name, and put it on any video in one click."),
                location: L("Style panel ▸ Presets."),
                steps: [
                    L("Style a video, then choose Presets ▸ Save as Preset…."),
                    L("Pick a preset from the menu to apply it. ⌘Z undoes it."),
                    L("Edit Presets renames, updates, or deletes them."),
                ],
                tips: [
                    L("A preset saves the background, frame, cursor, zooms, captions, keys, and camera. Tick Include aspect ratio to save the shape too."),
                    L("Export Presets… and Import Presets… share them as a small .lfss file (LF Studios Style). Older .lfstudiospresets and .shotstylepresets files import too."),
                ],
                showMe: .editor(.background),
                since: "1.9.0",
                related: ["style-my-style"]
            ),
            GuideEntry(
                id: "style-my-style", symbol: "paintbrush.pointed", title: L("My Style"),
                summary: L("Your own look, one click away."),
                location: L("Style panel ▸ Apply my style. Choose which preset it is with Presets ▸ Edit Presets ▸ Use as My Style."),
                keys: [.fixed("⇧⌘Y", L("Apply my style"))],
                tips: [L("It's never applied by itself: only when you click it.")],
                showMe: .editor(.background),
                related: ["howto-my-style"]
            ),
            GuideEntry(
                id: "style-fonts", symbol: "textformat", title: L("Fonts"),
                summary: L("Use any font on your Mac for captions, title cards, text, and keys, or add your own."),
                location: L("The font menu next to captions, text, title cards, and Keys on screen."),
                points: [
                    L("Pick a font and a weight; add Outline or Shadow to make it easier to read."),
                    L("Add Font File… brings in a .ttf or .otf file. LF Studios keeps its own copy."),
                ],
                tips: [L("If a project uses a font this Mac doesn't have, LF Studios uses its own font instead and says so.")]
            ),
        ]
    }

    // MARK: Video sizes

    static func sizeFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "size-ratio", symbol: "aspectratio", title: L("Aspect ratio"),
                summary: L("Choose the video's shape for where it's going."),
                location: L("The aspect ratio menu in the video editor's toolbar."),
                points: [
                    L("Auto (like the recording), 16:9 for YouTube, 9:16 for Reels, TikTok, and Shorts, 1:1, 4:5 for Instagram, 4:3, 16:10 like a Mac screen, or 21:9 for a cinematic look."),
                    L("Custom… for any other shape: type it like 3:2 or 2.39:1. Choose Custom… again to change it."),
                ],
                tips: [L("Every ratio works with Adapt to this ratio, Export all ratios, and presets saved with Include aspect ratio.")],
                since: "1.11.0",
                related: ["size-adapt", "howto-vertical"]
            ),
            GuideEntry(
                id: "size-reframe", symbol: "viewfinder", title: L("Fill the frame, follow the cursor"),
                summary: L("For a narrow video from a wide recording: the picture fills the frame and follows your pointer."),
                location: L("Aspect ratio menu ▸ Fill the Frame, Follow the Cursor."),
                tips: [L("Needs the cursor recorded by LF Studios. Without it, the video is shown with bars instead.")]
            ),
            GuideEntry(
                id: "size-adapt", symbol: "rectangle.portrait.arrowtriangle.2.outward", title: L("Adapt to this ratio"),
                summary: L("After changing the shape, move zooms, the camera, and captions so everything fits."),
                location: L("Adapt to this ratio, next to the aspect ratio menu after you change it."),
                tips: [
                    L("Each shape keeps its own version: switch back and forth without losing anything. Cuts, words, and styles stay shared."),
                    L("One ⌘Z undoes it."),
                ],
                since: "1.4.0"
            ),
            GuideEntry(
                id: "size-export-all", symbol: "square.stack", title: L("Export all ratios"),
                summary: L("Export every shape you made, like 16:9 and 9:16, in one go."),
                location: L("Export all ratios, next to the aspect ratio menu, once you've adapted more than one shape."),
                steps: [
                    L("Click Export all ratios."),
                    L("Choose a folder and click Export Here."),
                ],
                since: "1.4.0"
            ),
            GuideEntry(
                id: "size-phone", symbol: "iphone", title: L("Phone overlay"),
                summary: L("See where a phone app's buttons and captions would cover your vertical video."),
                location: L("Phone overlay, above the preview, for 9:16 videos."),
                points: [L("Side rail, Full rail, or Minimal. It shows only in the preview, never in the export.")]
            ),
        ]
    }

    // MARK: Privacy (features)

    static func privacyFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "privacy-find", symbol: "eye.trianglebadge.exclamationmark", title: L("Find private info"),
                summary: L("Looks through your video for faces, email addresses, phone and card numbers, passwords, and words you choose, so you can blur them."),
                location: L("Find private info, above the preview in the video editor."),
                steps: [
                    L("Optional: type words to look for, and turn on Also scan the camera video."),
                    L("Click Find Private Info. You can keep editing meanwhile."),
                    L("Tick what to hide and click Blur Selected."),
                ],
                tips: [
                    L("Nothing is ticked or blurred until you choose. Everything stays on your Mac."),
                    L("“Possible key” is a guess: long, random-looking text that might be a password."),
                ],
                since: "1.4.0",
                related: ["privacy-blur", "howto-private"]
            ),
            GuideEntry(
                id: "privacy-blur", symbol: "drop.halffull", title: L("Blur"),
                summary: L("Blur any part of the video."),
                location: L("Click Blur above the preview, or press B."),
                steps: [
                    L("Drag the blur over what you want to hide."),
                    L("Set its Strength in the panel on the right."),
                    L("On the timeline, drag its edges to set how long it lasts."),
                ],
                keys: [.fixed("B", L("Add a blur at the playhead"))]
            ),
        ]
    }

    // MARK: Export

    static func exportFeatures() -> [GuideEntry] {
        let sheet = L("Click Export in the video editor's toolbar (⌘E).")
        return [
            GuideEntry(
                id: "export-mp4", symbol: "square.and.arrow.up", title: L("Export a video (MP4)"),
                summary: L("Save your edit as a video that plays everywhere."),
                location: sheet,
                steps: [
                    L("Choose MP4."),
                    L("Pick a Resolution (720p to 4K), a Frame rate, and a Quality: Web, Social, or Studio."),
                    L("Click Export…."),
                ],
                keys: [.fixed("⌘E", L("Export"))],
                tips: [
                    L("H.264 plays everywhere. HEVC makes smaller files, but some browsers and Windows PCs can't play it."),
                    L("The size estimate tells you how big the file will be, and warns when the disk is too full."),
                ]
            ),
            GuideEntry(
                id: "export-prores", symbol: "film.circle", title: L("ProRes & a transparent background"),
                summary: L("High-quality files for video editing apps. ProRes 4444 can drop the background, ready to place over anything."),
                location: L("In the export window, choose ProRes 422, ProRes 422 HQ, or ProRes 4444."),
                tips: [L("ProRes files are big. Turn on Transparent background with ProRes 4444.")]
            ),
            GuideEntry(
                id: "export-gif", symbol: "photo.stack", title: L("GIF"),
                summary: L("A small looping animation for chats, docs, and bug reports."),
                location: L("In the export window, choose GIF."),
                points: [L("Size: Small, Medium, or Large. Frame rate: 10 to 24 fps.")],
                tips: [L("Keep GIFs short. LF Studios suggests how to make a big one lighter.")]
            ),
            GuideEntry(
                id: "export-audio", symbol: "waveform", title: L("Audio only"),
                summary: L("Save just the sound, with the same mix and loudness as the video."),
                location: L("In the export window, choose Audio only at the top."),
                points: [L("M4A (small), WAV, or AIFF (both full quality).")],
                since: "1.4.0"
            ),
            GuideEntry(
                id: "export-range", symbol: "timeline.selection", title: L("Export part of the video"),
                summary: L("Export only a selection, or the part between in and out points."),
                location: L("In the export window ▸ Range: Whole video, Selection, or In & out."),
                tips: [L("For Selection, ⇧-drag on the timeline first.")]
            ),
            GuideEntry(
                id: "export-captions", symbol: "captions.bubble", title: L("Captions in the export"),
                summary: L("Burn captions into the picture, and save a subtitles file next to the video."),
                location: L("In the export window ▸ Captions."),
                points: [
                    L("Burn captions into the video: they're always visible."),
                    L("Subtitles file: .srt or .vtt, for players that can turn captions on and off."),
                ]
            ),
            GuideEntry(
                id: "export-chapters", symbol: "list.bullet.rectangle", title: L("Chapters"),
                summary: L("Turn your markers into chapters, in the video and for YouTube."),
                location: L("In the export window ▸ Chapters."),
                points: [
                    L("Add chapters from markers puts chapters in MP4 and ProRes files."),
                    L("Copy Chapters copies them as text for a YouTube description."),
                ],
                tips: [L("YouTube needs at least three chapters, each at least 10 seconds long.")],
                related: ["video-markers", "howto-chapters"]
            ),
            GuideEntry(
                id: "export-end-card", symbol: "rectangle.on.rectangle.angled", title: L("End card"),
                summary: L("An optional 2-second “Made with LF Studios” card at the end."),
                location: L("In the export window ▸ End card.")
            ),
            GuideEntry(
                id: "export-background", symbol: "arrow.down.circle", title: L("Exports keep going while you edit"),
                summary: L("Exports run in the background. When one is done, share it, show it, copy it, or play it."),
                location: L("The export progress in the editor's toolbar; past exports in File ▸ Recent Exports."),
                points: [
                    L("Keep Editing closes the export window; the export carries on."),
                    L("Share sends it with Mail, Messages, AirDrop, and more."),
                    L("Copy, in the export window, puts the video on the clipboard."),
                ]
            ),
            GuideEntry(
                id: "export-handoff", symbol: "shippingbox", title: L("Creative Handoff"),
                summary: L("Every part of your video as its own file, in one folder, for another editor or app."),
                location: L("File ▸ Creative Handoff… (⇧⌘E), the button in the export window, or right-click a recording in Home."),
                points: [
                    L("Screen clips, camera, voice, computer sound, music, pictures, captions, and fonts."),
                    L("A timeline for Final Cut Pro, DaVinci Resolve, and Adobe Premiere Pro."),
                    L("Line everything up makes every file start at the same moment."),
                    L("A README lists every file. Include speaker notes adds your notes."),
                    L("An LF Studios project: open the folder in LF Studios to edit the video again. With clips cut to your edit, Include originals so it reopens in LF Studios adds the untouched recordings it needs."),
                ],
                keys: [.fixed("⇧⌘E", L("Creative Handoff"))],
                tips: [
                    L("It checks the free space first, and shows how much the originals add. Cancel removes the half-made folder."),
                    L("Fonts you added to LF Studios always go along. Fonts installed on this Mac (in Font Book) go only with Include fonts installed on this Mac turned on: check that the font's license lets you share it first. Without them, README.txt lists the fonts left out."),
                    L("Opened on another Mac, the project looks and sounds the same: the cleaned-up voice, Keep face centered, the pointer's own picture, and a macOS wallpaper background travel in the folder."),
                ],
                since: "1.8.0",
                related: ["howto-handoff", "project-folder"]
            ),
        ]
    }
    // MARK: Projects

    static func projectFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "home-projects", symbol: "square.grid.2x2", title: L("Home & your projects"),
                summary: L("Every recording, screenshot, and saved project in one place."),
                location: L("Home ▸ Projects. Recordings and Screenshots in the sidebar show just one kind."),
                points: [
                    L("Click a project to open it."),
                    L("Right-click for Open, Show in Finder, Creative Handoff…, or Delete (moves it to the Trash; for a recording's folder, the whole folder, after asking)."),
                    L("The search box finds projects by name, and screenshots by their text."),
                ],
                showMe: .home(.home)
            ),
            GuideEntry(
                id: "project-save", symbol: "doc.badge.plus", title: L("Save a project"),
                summary: L("Keep a whole edit as one file: the recording, camera, sound, music, pictures, fonts, and every change."),
                location: L("In the video editor: File ▸ Save Project (⌘S) or Save Project As… (⇧⌘S)."),
                points: [
                    L("Include media: the project opens on any Mac."),
                    L("Link to media: smaller, for this Mac only."),
                    L("Include fonts installed on this Mac: fonts from Font Book go along too. Check that a font's license lets you share it first. Fonts you added to LF Studios always go."),
                    L("New projects are saved as .lfsp files. Save Project (⌘S) keeps an older .lfstudios project's name; Save Project As… (⇧⌘S) makes a .lfsp."),
                ],
                keys: [.fixed("⌘S", L("Save Project")), .fixed("⇧⌘S", L("Save Project As…"))],
                since: "1.9.0"
            ),
            GuideEntry(
                id: "project-open", symbol: "folder", title: L("Open a project"),
                summary: L("Open a saved .lfsp project, a recording's folder, or a video."),
                location: L("Open… in Home, File ▸ Open… (⌘O), or double-click the project in Finder."),
                keys: [.fixed("⌘O", L("Open…"))],
                tips: [L("Older projects open too: .lfstudios from LF Studios 1.8 and earlier, and .shotstyle from ShotStyle. LF Studios never renames them.")],
                since: "1.9.0",
                related: ["project-folder"]
            ),
            GuideEntry(
                id: "project-folder", symbol: "folder.badge.questionmark", title: L("Open a whole folder"),
                summary: L("Open a folder of files as one project: a recording's folder, a Creative Handoff, or any folder with videos in it."),
                location: L("Open… in Home or File ▸ Open… (⌘O), and choose the folder. Or drop the folder on the Home window or the LF Studios icon in the Dock."),
                points: [
                    L("A folder with an LF Studios project in it opens that project, exactly as it was saved."),
                    L("An older Creative Handoff is put back together from its files: the screen, the cuts, the camera at its place, captions, markers, and the pointer. A summary says what came back."),
                    L("Any other folder: Import Folder lists the videos and sound files. Choose which is the screen recording, which the camera, and which sound to add as tracks, and when each starts."),
                ],
                keys: [.fixed("⌘O", L("Open…"))],
                tips: [L("Nothing in the folder changes until you save (⌘S). Saving writes the project into the folder.")],
                since: "1.6.0",
                related: ["rec-folder", "export-handoff"]
            ),
            GuideEntry(
                id: "project-drafts", symbol: "clock.badge.checkmark", title: L("Your edits are kept"),
                summary: L("Every change is saved as you go. Close the editor and open the recording again: your edit is still there."),
                location: L("Happens by itself, for every recording."),
                tips: [L("Renaming or moving the recording in Finder doesn't lose the edit.")]
            ),
            GuideEntry(
                id: "project-cleanup", symbol: "externaldrive.badge.minus", title: L("Clean up video data"),
                summary: L("Free up space taken by data for recordings that are gone, unused camera videos, and old copies."),
                location: L("Settings ▸ Recording ▸ Storage ▸ Clean Up…."),
                tips: [L("It shows what it would remove and asks first.")],
                showMe: .settings(.recording)
            ),
        ]
    }

    // MARK: Settings

    static func settingsFeatures() -> [GuideEntry] {
        [
            GuideEntry(
                id: "app-guide", symbol: "book", title: L("This Guide"),
                summary: L("Help for every part of LF Studios, with search, steps, and a Show me button that takes you there."),
                location: L("Home ▸ Guide, or Help ▸ LF Studios Guide."),
                keys: [.fixed("⌘?", L("LF Studios Guide"))],
                tips: [L("Show me only opens the right place; it never changes a setting or turns anything on.")],
                since: "1.5.0"
            ),
            GuideEntry(
                id: "app-command-center", symbol: "menubar.rectangle", title: L("The LF Studios menu (Command Center)"),
                summary: L("Every capture, recording, and tool, from the LF Studios icon in the menu bar."),
                location: L("Click the LF Studios icon in the menu bar."),
                points: [
                    L("Capture, Recording, Tools, and Utility sections, each with its current shortcut."),
                    L("Health shows whether everything is ready, and offers a Fix when something isn't."),
                    L("While recording, the icon becomes a red timer: click it to stop."),
                ],
                keys: [.global(.openCommandCenter)]
            ),
            GuideEntry(
                id: "app-shortcuts", symbol: "keyboard", title: L("Change keyboard shortcuts"),
                summary: L("Set your own keys for captures and recordings. They work in every app."),
                location: L("Settings ▸ Shortcuts."),
                steps: [
                    L("Click the field next to a command."),
                    L("Press the keys you want. To remove one, click the ×."),
                ],
                tips: [
                    L("Recording shortcuts start unset. Reset Defaults brings back the original keys."),
                    L("Restore Apple Shortcuts turns Apple's own ⇧⌘3, ⇧⌘4, and ⇧⌘5 back on."),
                ],
                showMe: .settings(.shortcuts),
                related: ["trouble-shortcuts"]
            ),
            GuideEntry(
                id: "app-appearance", symbol: "circle.lefthalf.filled", title: L("Light & dark appearance"),
                summary: L("Choose light or dark windows, or follow your Mac."),
                location: L("Settings ▸ General ▸ Appearance: System, Light Mode, or Dark Mode."),
                tips: [L("Your screenshots and videos look the same either way.")],
                showMe: .settings(.general)
            ),
            GuideEntry(
                id: "app-language", symbol: "globe", title: L("Language"),
                summary: L("Use LF Studios in English, German, French, Chinese, Russian, Ukrainian, or Japanese."),
                location: L("Settings ▸ General ▸ Language."),
                tips: [L("LF Studios restarts to switch languages.")],
                showMe: .settings(.general)
            ),
            GuideEntry(
                id: "app-login", symbol: "power", title: L("Open at login"),
                summary: L("Start LF Studios when you log in, so your shortcuts are always ready."),
                location: L("Settings ▸ General ▸ Startup ▸ Launch LF Studios at login."),
                showMe: .settings(.general)
            ),
            GuideEntry(
                id: "app-menu-icon", symbol: "menubar.arrow.up.rectangle", title: L("Menu bar icon"),
                summary: L("Show or hide the LF Studios icon in the menu bar."),
                location: L("Settings ▸ General ▸ Menu Bar ▸ Show menu bar icon."),
                tips: [L("If the menu bar is too full, macOS may hide the icon. Set an Open Command Center shortcut to reach the menu anyway.")],
                showMe: .settings(.general),
                related: ["trouble-menu-icon"]
            ),
            GuideEntry(
                id: "app-updates", symbol: "arrow.triangle.2.circlepath", title: L("Updates"),
                summary: L("LF Studios checks for a new version once a day. It shows what's new, and installs only when you click Install Update."),
                location: L("LF Studios ▸ Check for Updates…, and Settings ▸ General ▸ Updates ▸ Check for updates automatically."),
                points: [
                    L("Install Update: downloads it, installs it, and reopens LF Studios."),
                    L("Remind Me Later or Skip This Version: nothing changes."),
                ],
                tips: [L("Your projects, recordings, settings, and permissions stay as they are.")],
                showMe: .settings(.general),
                since: "1.4.1",
                related: ["trouble-updates"]
            ),
            GuideEntry(
                id: "app-files", symbol: "folder.badge.gearshape", title: L("Save folders, file names & format"),
                summary: L("Choose where screenshots and recordings are saved, what they're called, and the picture format."),
                location: L("Settings ▸ Screenshots, and Settings ▸ Recording ▸ Saving."),
                points: [
                    L("Screenshot folder (Settings ▸ Screenshots): where screenshots are saved. Recording folder (Settings ▸ Recording): where recordings go when you don't choose. Both start as the folder you used before, or the Desktop."),
                    L("File Name: a template with the date and time; Preview shows the result."),
                    L("Export Format: PNG, JPEG (with a quality slider), or WebP."),
                ],
                showMe: .settings(.screenshots)
            ),
            GuideEntry(
                id: "app-whisper", symbol: "arrow.down.circle", title: L("Whisper models"),
                summary: L("Download or delete the models Whisper uses for captions."),
                location: L("Settings ▸ General ▸ Whisper Models."),
                tips: [L("Models are downloaded only when you click Download, and can be deleted to free up space.")],
                showMe: .settings(.general),
                since: "1.4.0",
                related: ["captions-whisper"]
            ),
            GuideEntry(
                id: "app-welcome", symbol: "hand.wave", title: L("Welcome checklist"),
                summary: L("Three quick steps the first time you open LF Studios: allow Screen Recording, free up shortcuts, and take a test screenshot."),
                location: L("Shows at launch until your first screenshot, or until you click Skip Setup.")
            ),
            GuideEntry(
                id: "app-crash", symbol: "ladybug", title: L("Report a problem"),
                summary: L("If LF Studios quit unexpectedly, it offers to report it next time it opens."),
                location: L("The message after a crash ▸ Report on GitHub. Or Settings ▸ About ▸ Report Issue."),
                tips: [L("You see the report before anything is sent, and you send it yourself.")],
                showMe: .settings(.about)
            ),
        ]
    }

    // MARK: - Privacy

    static func privacy() -> [GuideEntry] {
        [
            GuideEntry(
                id: "privacy-on-mac", symbol: "laptopcomputer", title: L("Everything stays on your Mac"),
                summary: L("Your screenshots, recordings, and edits are yours. LF Studios has no account, and sends nothing about you or your work anywhere."),
                points: [
                    L("Text recognition, captions, Whisper, Find private info, face tracking, background removal, and voice cleanup all run on your Mac."),
                    L("Your recordings are never uploaded."),
                ]
            ),
            GuideEntry(
                id: "privacy-internet", symbol: "network", title: L("When LF Studios uses the internet"),
                summary: L("Only for these, and never to send your work:"),
                points: [
                    L("Downloading a Whisper model, and only when you click Download."),
                    L("Checking for updates: once a day, or when you choose Check for Updates…. You can turn the daily check off in Settings ▸ General."),
                    L("macOS itself may download a language the first time you transcribe or translate captions in it."),
                    L("Links you click, like Report Issue or a link in a QR code, open in your web browser."),
                ],
                showMe: .settings(.general)
            ),
            GuideEntry(
                id: "privacy-typing", symbol: "keyboard", title: L("Typing options: what they save"),
                summary: L("Three recording options look at your keyboard. None of them ever saves what you type."),
                points: [
                    L("Track where I type: only where the text cursor is on screen, a few times a second. Never the text, never the keys."),
                    L("Record when keys are pressed: only the moment each key goes down. Never which key."),
                    L("Show keyboard shortcuts: only shortcuts with ⌘ or ⌃ (like ⌘C), and keys like Esc. Never ordinary typing."),
                    L("While a password field is in use, the typing options save nothing at all, not even the moments just before."),
                ],
                tips: [L("All three are off until you turn them on, and they need Accessibility.")],
                showMe: .settings(.recording)
            ),
            GuideEntry(
                id: "privacy-saved", symbol: "doc.text", title: L("What a recording keeps"),
                summary: L("Next to the video, LF Studios keeps the details the editor needs, on your Mac."),
                points: [
                    L("The video, in your save folder, and the camera video, if the camera was on."),
                    L("Where the pointer went, and where you clicked."),
                    L("Only if you turned them on: shortcuts, typing positions and times, and your speaker notes."),
                    L("Markers you added."),
                ]
            ),
            GuideEntry(
                id: "privacy-never-recorded", symbol: "eye.slash", title: L("Never in your recordings"),
                summary: L("LF Studios' own floating windows stay out of your screen recordings and screenshots."),
                points: [
                    L("The recording bar, the camera bubble preview, Speaker notes, the countdown, and notices."),
                    L("Speaker notes are hidden from screen sharing too."),
                ]
            ),
            GuideEntry(
                id: "privacy-delete", symbol: "trash", title: L("Deleting your things"),
                summary: L("Remove anything, any time."),
                points: [
                    L("Right-click a project in Home ▸ Delete: it goes to the Trash."),
                    L("History ▸ Clear All deletes every screenshot (it can be undone for 7 days)."),
                    L("Settings ▸ Recording ▸ Storage ▸ Clean Up… removes leftover video data."),
                    L("Settings ▸ General ▸ Whisper Models deletes downloaded models."),
                ]
            ),
        ]
    }

    // MARK: - Troubleshooting

    static func troubleshooting() -> [GuideEntry] {
        [
            GuideEntry(
                id: "trouble-black", symbol: "rectangle.slash", title: L("My recording is black, or shows only the wallpaper"),
                summary: L("LF Studios doesn't have Screen Recording permission yet."),
                steps: [
                    L("Click Open System Settings below."),
                    L("In Screen & System Audio Recording, make sure LF Studios is on. If it already is, turn it off and on again."),
                    L("Quit LF Studios and open it again."),
                    L("Check the LF Studios menu: Health should say Everything is ready."),
                ],
                showMe: .systemSettings(.screenRecording)
            ),
            GuideEntry(
                id: "trouble-no-sound", symbol: "speaker.slash", title: L("No sound was recorded"),
                summary: L("The microphone was off, muted, or not allowed."),
                steps: [
                    L("Before recording, turn on Microphone in the recording bar and check that its level meter moves when you speak."),
                    L("Pick the right microphone in the menu above the bar."),
                    L("Make sure LF Studios is allowed under Microphone in System Settings. It appears there only after it has asked once, and there's no + button: turn on Microphone in the recording bar and click Allow."),
                    L("No question appeared? Open Terminal, run tccutil reset Microphone com.lfstudios.app, then quit and reopen LF Studios and try again."),
                    L("For your Mac's own sound, turn on System audio too."),
                    L("In the editor, check that Mute video is off in the Audio panel, and that the preview isn't muted (press M)."),
                ],
                showMe: .systemSettings(.microphone),
                related: ["rec-mic", "audio-levels"]
            ),
            GuideEntry(
                id: "trouble-shortcuts", symbol: "exclamationmark.bubble", title: L("My shortcuts don't work"),
                summary: L("A shortcut isn't set, or another app uses the same keys."),
                steps: [
                    L("Open Settings ▸ Shortcuts and check that the shortcut has keys. Recording shortcuts start unset."),
                    L("Another app may use the same keys: choose different ones."),
                    L("LF Studios must be running. Turn on Launch LF Studios at login so it always is."),
                ],
                showMe: .settings(.shortcuts),
                related: ["trouble-apple-screenshot"]
            ),
            GuideEntry(
                id: "trouble-apple-screenshot", symbol: "camera.badge.ellipsis", title: L("⇧⌘4 opens Apple's screenshot tool"),
                summary: L("macOS has its own screenshot shortcuts with the same keys."),
                steps: [
                    L("Open the LF Studios menu and, under Health, click Fix next to Apple Shortcuts."),
                    L("Or turn off Apple's screenshot shortcuts yourself: System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Screenshots."),
                ],
                tips: [L("Want Apple's back? Settings ▸ Shortcuts ▸ Restore Apple Shortcuts.")],
                showMe: .systemSettings(.keyboard)
            ),
            GuideEntry(
                id: "trouble-cant-open", symbol: "xmark.shield", title: L("macOS says LF Studios can't be opened"),
                summary: L("macOS is careful with apps downloaded from the internet. This only happens the first time."),
                steps: [
                    L("Try to open LF Studios once, and close the message."),
                    L("Open System Settings ▸ Privacy & Security, scroll down, and click Open Anyway next to LF Studios."),
                    L("Still stuck, or does it say the app is damaged? Open Terminal and paste this line, then press Return: xattr -dr com.apple.quarantine \"/Applications/LF Studios.app\""),
                ],
                tips: [L("Updates installed from inside LF Studios never need this again.")]
            ),
            GuideEntry(
                id: "trouble-updates", symbol: "arrow.triangle.2.circlepath", title: L("LF Studios doesn't find updates"),
                summary: L("Updates need version 1.4.1 or later, and the internet."),
                steps: [
                    L("Choose LF Studios ▸ Check for Updates…."),
                    L("Older than 1.4.1? Download the latest version once by hand from the LF Studios releases page. After that, it updates itself."),
                    L("Check that your Mac is online."),
                ],
                showMe: .settings(.general),
                related: ["app-updates"]
            ),
            GuideEntry(
                id: "trouble-missing-media", symbol: "questionmark.folder", title: L("A camera video or a font is missing"),
                summary: L("A file the project uses was moved, deleted, or is on another Mac."),
                steps: [
                    L("Camera video missing: in the Camera panel, click Locate… and find the file."),
                    L("Font missing: install the font on this Mac, or add it with Add Font File… in the font menu."),
                    L("Moving a project to another Mac? Save it with Include media, so everything comes along."),
                ],
                related: ["camera-import", "style-fonts", "project-save"]
            ),
            GuideEntry(
                id: "trouble-export", symbol: "externaldrive.badge.exclamationmark", title: L("Export is slow, or the disk is full"),
                summary: L("Big, sharp videos take longer and need more space."),
                steps: [
                    L("Keep editing: exports run in the background."),
                    L("For a faster, smaller file, choose 1080p, 30 fps, and MP4."),
                    L("Free up space: Settings ▸ Recording ▸ Storage ▸ Clean Up…, History's Clean Up…, and empty the Trash."),
                ],
                tips: [L("The export window warns you before a file won't fit.")],
                showMe: .settings(.recording)
            ),
            GuideEntry(
                id: "trouble-menu-icon", symbol: "menubar.rectangle", title: L("The menu bar icon is missing"),
                summary: L("It's turned off, or the menu bar is too full and macOS hid it."),
                steps: [
                    L("Check Settings ▸ General ▸ Show menu bar icon."),
                    L("Too many icons? Remove some, or set an Open Command Center shortcut in Settings ▸ Shortcuts."),
                    L("Everything is in the Home window too."),
                ],
                showMe: .settings(.general)
            ),
            GuideEntry(
                id: "trouble-transcribe", symbol: "waveform.slash", title: L("Transcribe doesn't work"),
                summary: L("The recording has no voice, the language isn't ready, or a permission is off."),
                steps: [
                    L("Check that the recording has sound, and that the Language matches what you speak."),
                    L("On macOS 15 and earlier: allow LF Studios under Speech Recognition, and turn on Dictation for that language in System Settings ▸ Keyboard."),
                    L("Or try the Whisper engine instead."),
                ],
                showMe: .systemSettings(.speechRecognition),
                related: ["captions-transcribe", "captions-whisper"]
            ),
            GuideEntry(
                id: "trouble-slow-analysis", symbol: "hourglass", title: L("Find private info or face tracking takes a while"),
                summary: L("They look through the whole video on your Mac, which takes longer for long or 4K videos."),
                steps: [
                    L("Keep editing: they carry on even when you close their panel."),
                    L("Plug in your laptop: Macs work faster on power."),
                ],
                tips: [L("Each video is looked through only once: the second time is instant.")]
            ),
        ]
    }

    // MARK: - Keyboard shortcuts

    static func shortcutGroups() -> [GuideShortcutGroup] {
        [
            GuideShortcutGroup(
                title: L("In any app"), symbol: "globe",
                note: L("These work everywhere while LF Studios is running. “Not set” means no keys yet: add your own in Settings ▸ Shortcuts."),
                keys: LFStudiosShortcut.allCases.map { GuideKey.global($0) } + [.fixed("⌃⌘Esc", L("Stop recording, from any app"))]
            ),
            GuideShortcutGroup(title: L("Menus"), symbol: "menubar.rectangle", keys: menuKeys()),
            GuideShortcutGroup(
                title: L("Video editor"), symbol: "film",
                note: L("Press ? in the editor to see this list there."),
                keys: VideoShortcutsSheet.groups.flatMap { $0.1.map { GuideKey.fixed($0.0, $0.1) } }
            ),
            GuideShortcutGroup(
                title: L("Screenshot editor"), symbol: "pencil.and.outline",
                keys: AnnotationTool.allCases.map { tool($0) } + [
                    .fixed("⌥R", L("Rounded corners")),
                    .fixed(L("⇧-drag"), L("Square, circle, or straight 45° lines")),
                    .fixed(L("⌥-drag"), L("Draw from the center")),
                    .fixed("⌘↩", L("Finish typing")),
                    .fixed("⌫", L("Delete the selected mark")),
                    .fixed("← → ↑ ↓", L("Nudge the selected mark (with ⇧: 10 points)")),
                    .fixed("↩", L("Apply the crop")),
                    .fixed("Esc", L("Deselect")),
                    .fixed("⌘Z", L("Undo")), .fixed("⇧⌘Z", L("Redo")),
                    .fixed("⌘C", L("Copy")), .fixed("⌘S", L("Save")),
                    .fixed("⌘=  ⌘−", L("Zoom in / out")), .fixed("⌘0", L("Actual size")),
                    .fixed("⌘W", L("Close")),
                ]
            ),
            GuideShortcutGroup(
                title: L("Selecting an area"), symbol: "selection.pin.in.out",
                keys: [
                    .fixed(L("Space"), L("Move the area while dragging")),
                    .fixed("⇧", L("Hold as you let go to adjust first")),
                    .fixed("← → ↑ ↓", L("Nudge the area (with ⇧: 10 points)")),
                    .fixed("⌥ ← → ↑ ↓", L("Make the area bigger or smaller")),
                    .fixed("↩", L("Capture")),
                    .fixed("Esc", L("Cancel")),
                ]
            ),
            GuideShortcutGroup(
                title: L("The frame bar"), symbol: "aspectratio",
                note: L("After clicking the frame's border or the bars."),
                keys: [
                    .fixed("← → ↑ ↓", L("Move the frame (with ⇧: 10 points)")),
                    .fixed("↩", L("Start recording")),
                    .fixed("Esc", L("Cancel")),
                    .fixed("⌃⌘Esc", L("Cancel the frame, from any app")),
                ]
            ),
            GuideShortcutGroup(
                title: L("Recording"), symbol: "record.circle",
                keys: [
                    .fixed("↩", L("Start recording")),
                    .fixed("Esc", L("Cancel")),
                    .fixed("⌃⌘Esc", L("Stop recording, from any app")),
                    .fixed("Esc", L("Stop, while LF Studios is the app in front")),
                ]
            ),
            GuideShortcutGroup(
                title: L("Speaker notes"), symbol: "text.alignleft",
                keys: [.fixed(L("Space"), L("Pause or resume scrolling")), .fixed("↑ ↓", L("Scroll by a line"))]
            ),
            GuideShortcutGroup(
                title: L("Scrolling Capture"), symbol: "scroll",
                keys: [.fixed("Esc", L("Finish"))]
            ),
            GuideShortcutGroup(
                title: L("Preview after capture"), symbol: "rectangle.inset.bottomleft.filled",
                note: L("While the pointer is over the thumbnail."),
                keys: [.fixed("⌘C", L("Copy")), .fixed("⌘S", L("Save")), .fixed("⌘E", L("Edit")), .fixed("Esc", L("Close"))]
            ),
            GuideShortcutGroup(
                title: L("History"), symbol: "clock.arrow.circlepath",
                keys: [
                    .fixed("⌘F", L("Search")),
                    .fixed("↩", L("Edit the selected screenshot")),
                    .fixed("⌘C", L("Copy")),
                    .fixed("⌫", L("Delete")),
                    .fixed("⌘Z", L("Undo a delete")),
                    .fixed("Esc", L("Clear the search")),
                ]
            ),
            GuideShortcutGroup(
                title: L("Pinned screenshots"), symbol: "pin",
                keys: [.fixed("Esc", L("Close the pin")), .fixed("⌘C", L("Copy")), .fixed("⌘W", L("Close"))]
            ),
            GuideShortcutGroup(
                title: L("Edit by text"), symbol: "text.word.spacing",
                keys: [
                    .fixed("⌫", L("Cut the selected words")),
                    .fixed("⌦", L("Cut the word after the cursor")),
                    .fixed("⌘F", L("Find in the transcript")),
                    .fixed("⌘G", L("Find the next one")),
                ]
            ),
        ]
    }

    /// The menu bar's keys (AppDelegate.setupMainMenu).
    static func menuKeys() -> [GuideKey] {
        [
            .fixed("⌘0", L("LF Studios Home")),
            .fixed("⌘?", L("LF Studios Guide")),
            .fixed("⌘,", L("Settings…")),
            .fixed("⌘Q", L("Quit LF Studios")),
            .fixed("⌘W", L("Close Window")),
            .fixed("⌘O", L("Open…")),
            .fixed("⌘S", L("Save Project")),
            .fixed("⇧⌘S", L("Save Project As…")),
            .fixed("⌘E", L("Export Video…")),
            .fixed("⇧⌘E", L("Creative Handoff…")),
            .fixed("⌘Z", L("Undo")),
            .fixed("⇧⌘Z", L("Redo")),
            .fixed("⌘X", L("Cut")),
            .fixed("⌘C", L("Copy")),
            .fixed("⌘V", L("Paste")),
            .fixed("⌘A", L("Select All")),
            .fixed("S", L("Split at Playhead")),
            .fixed("⌫", L("Delete Selection")),
            .fixed("I", L("Set In to Playhead")),
            .fixed("O", L("Set Out to Playhead")),
            .fixed("M", L("Mute Clip")),
            .fixed("⌘M", L("Minimize")),
        ]
    }
}

/// One box on the Keyboard shortcuts page.
struct GuideShortcutGroup {
    let title: String
    let symbol: String
    var note: String?
    let keys: [GuideKey]
}
