# Changelog

## [1.5.0]

### Added
- **The Guide.** Home's sidebar has a new **Guide**, below Settings, and Help ▸ **LF Studios Guide** (⌘?) opens it. It's help for every part of LF Studios, written for people who've just installed it, in all seven languages:
  - **Getting started:** what LF Studios does, the Home window, allowing Screen Recording, Accessibility, the microphone and the camera (each with Open System Settings, and whether it's allowed yet), your first screenshot, and your first recording, edit and export.
  - **How do I…?** Nineteen short recipes, from a screenshot of a scrolling page to a vertical video for Reels or chapters for YouTube.
  - **All features:** every feature, section by section, with what it does, where to find it, steps, its keyboard shortcut, and tips. A **Show me** button opens the right place, like the right Settings page or the video editor's panel. It only goes there; it never changes a setting.
  - **Keyboard shortcuts:** every shortcut, with the keys set on your Mac right now, and a button to change them.
  - **Privacy**, **Troubleshooting**, and **What's new**, where the newest features carry a New badge.
  - A search box looks through every page's name, words, and steps.

## [1.4.2] - 2026-10-28

### Changed
- A check that updates work: 1.4.1 updates itself to this version. Nothing else changed.

## [1.4.1] - 2026-10-28

### Added
- **Updates inside the app.** LF Studios → **Check for Updates…** looks for a new version, and LF Studios also checks once a day (Settings → General → **Check for updates automatically**, on to start with). The update window shows what's new, with **Install Update**, **Remind Me Later** and **Skip This Version**. Nothing downloads or installs until you click Install Update. LF Studios then relaunches, with your projects, recordings, drafts, history, settings, presets, fonts, Whisper models and permissions as they were. Install 1.4.1 by hand once; later versions update themselves.

### Changed
- Downloads moved to [LF-Studios-Releases](https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases), which anyone with the link can open without a GitHub login.

## [1.4.0] - 2026-10-28

Everything new starts off, and is turned on with its own button or switch.

### Added
- **Zoom follows typing.** Settings → Recording (and the recording bar's options menu) has **Track where I type**, off to start with. While recording, it saves only where the text cursor is on screen, a few times a second, and never the text or the keys. In the editor, **Add typing zooms** in the Zoom panel adds zooms that follow the text cursor through each stretch of typing, one ⌘Z step. Pressing it again replaces only those zooms. Each one can be edited like any zoom: Framing has Follow cursor, Follow typing, and Aim by hand.
- **Loupe zoom.** Each zoom has **Type: Full / Loupe**, and the Zoom panel has **Add Loupe**. A loupe is a round or rounded magnifier over one spot while the rest of the frame stays in view. Its size, magnification, shape, border and border color, shadow, and how long it takes to open and close are all adjustable. New loupes take the look of the last one you changed. Style presets save the look, and applying a preset restyles the loupes (one ⌘Z step).
- **Fit zooms around camera.** Two buttons in the Zoom panel check every zoom the camera bubble would cover. **Shift the Zooms** moves each one's framing clear of the bubble, moving a loupe aside or zooming a little deeper where the frame's edge is in the way. **Move the Camera Instead** slides the bubble to a free corner while that zoom plays. It says what changed ("Adjusted 4 zooms"), and it's one ⌘Z step.
- **Cursor styles.** Cursor ▸ Appearance ▸ Style: macOS classic (the recording's own pointer, as before), White, Outlined, Touch dot, Ring, or Custom image…. Each drawn style has its own arrow, text (I-beam), and hand, all drawn in LF Studios. A custom image is a PNG you click to set where it points; it's used for every pointer shape. Styles are saved in presets and project files, and "Include media" packs a custom image into the project.
- **Speed up typing.** Settings → Recording (and the recording bar's options menu) has **Record when keys are pressed**, off to start with. It saves only the moment each key goes down, never which key. In the editor, Cursor ▸ Typing speeds every typing stretch up to 2×, 3×, 4×, 6×, or 8× as speed blocks you can change, one ⌘Z step. Pressing it again with another speed changes them. Shortcut keycaps stay on screen long enough to read. For older recordings without key timing, typing is estimated from screen changes while the pointer holds still, and LF Studios says it's an estimate.
- **Keep face centered.** The Camera panel's Face tracking has **Keep face centered**. It finds your face in the camera video with Apple's Vision face detection, with progress and Cancel, and then the bubble follows it. If no face is found for a while, the last framing holds. **Smoothness** sets how calmly it follows, and **Framing** sets how close in it is. A switch turns it off and on again. It's set per project, and each camera video is analyzed only once.
- **Hide camera during silences.** In the Camera panel, **Hide camera during silences** puts hide blocks on the Camera lane wherever you don't talk for at least the time you pick (1–10 seconds). The camera fades out and back in. The blocks can be dragged and deleted like any camera block. Pressing it again replaces only those blocks; blocks you made yourself stay. One ⌘Z step.
- **Camera color.** The Camera panel's Color section has brightness, contrast, saturation, warmth, tint, and sharpness, plus four looks (Natural, Warm, Bright, Cinematic), **Auto adjust** (it looks at a few frames of the camera video), and Reset. It changes the camera only, never the screen. It starts neutral, and style presets save it.
- **Podcast mode.** The Audio tab has **Podcast mode**: noise removal, de-essing, a warm and clear EQ, compression, and loudness to −16 LUFS (stereo), each with its own switch. It uses Apple's audio units and LF Studios' own processing, nothing from anyone else. While it's on, Enhance voice and Even out loudness give way to it.
- **Export audio only.** The export window has **Video / Audio only**. Audio only saves the edit's sound as M4A (AAC), WAV (24-bit), or AIFF (24-bit), with the same mix and loudness as the video.
- **Speaker notes.** A Notes button in the recording bar (and in the bar while recording) opens a floating teleprompter. It never shows up in a recording, or in screenshots or screen sharing. Paste or type your notes, set the text size, and scroll by hand (arrow keys) or let it scroll at the speed you choose. Space or the play button pauses and resumes. A Pause / Resume Speaker Notes shortcut can be set in Settings → Shortcuts; it has none to start with. **Start with recording** begins scrolling when the recording starts. The notes are remembered between recordings, and a take recorded with the panel open keeps them in its project (the Captions tab shows them, with Copy).
- **Speaker notes in Creative Handoff.** The Handoff dialog has **Include speaker notes**, off to start with. When it's on, the notes are added as Notes.txt.
- **Whisper captions.** The Captions tab has **Engine: Apple / Whisper** (Apple, as before, to start with) and **Transcribe with Whisper**. Whisper runs on the Mac with Core ML (WhisperKit). Pick a model, from Tiny (fastest, about 75 MB) to Large v3 Turbo (most accurate, about 630 MB). It's downloaded from Hugging Face only when you click Download, with progress and Cancel, and that download is the only time Whisper uses the network. Your recording is never uploaded. Settings → General → Whisper Models lists the models, with Download and Delete. If a model is too much for the Mac, LF Studios says so and suggests a smaller one. Whisper's words work like Apple's: editing, translation, animations, and .srt and .vtt export.
- **Caption animations.** Caption style ▸ **Animation**: None (as before, to start with), Pop-in words, One word at a time, Karaoke fill, Typewriter, Bounce, Fade up, or Highlight box. They follow the spoken words; typed and translated captions spread their words over the caption. They work with custom fonts, every caption position (one caption's own spot too) and every aspect ratio, and are saved in style presets. The preview and the export draw the same frames.
- **Adapt to this ratio.** After you switch the aspect ratio, **Adapt to this ratio** (beside the ratio menu, and in it) reframes the zooms so what they zoom on stays in frame, moves the camera bubble (to the top on 9:16), and keeps captions in the safe area. It's one ⌘Z step. From then on that ratio keeps its own zooms' framing, camera place and size, camera layouts and caption positions. Switching back brings each ratio's version back, so 16:9, 9:16 and 1:1 versions of one project live side by side. Cuts, caption text, styles and zooms themselves stay shared. **Export all ratios** exports every version in one go into a folder you choose.
- **Find private info.** **Find private info** (in the bar above the preview) scans the video in the background with Apple's Vision, with progress and Cancel. It looks for faces, email addresses, phone numbers, card numbers, API keys, tokens and passwords shown as text, and words you type (client names, for example). Long random-looking text is listed as "Possible key", since that's a guess. **Also scan the camera video** (off to start with) looks at things behind you, like a whiteboard. Each find is followed over time, also while the page scrolls. The list shows a thumbnail, the type and the time range, with a checkbox for each. Nothing is ticked, and nothing is blurred until you choose. **Blur selected** turns the ticked items into normal blur blocks that follow them, in one ⌘Z step; move, resize or delete them like any blur. A second scan of the same video is instant. Everything stays on the Mac.

### Privacy
- While a password field has focus (or macOS has secure keyboard entry on), neither typing option records anything: no text cursor positions and no key-press times. A key pressed just before the field was noticed is dropped too. Recording resumes when focus leaves the field.

## [1.3.0] - 2026-10-27

Everything new starts off, and is turned on with its own button or switch.

### Added
- **ProRes in the export window.** ProRes 422, ProRes 422 HQ, and ProRes 4444 sit next to MP4 and GIF, saved as .mov with uncompressed sound. ProRes 4444 has a **Transparent background** switch: the background drops out, and the video with its rounded corners and shadow, and a cut-out camera, sit on transparency, ready to place over anything. The size estimate knows how big ProRes gets and warns when it won't fit on the disk.
- **Window size.** In Window mode, the bar above the recording controls has Window size: 1280×720, 1920×1080, 1440×900, 1080×1080, 1080×1920, or Custom Size…. They're the recording's pixels, and each shows the window size that makes on this display (1920×1080 is a 960×540 window on a Retina screen). LF Studios resizes the window and centers it. If a size doesn't fit, it offers the largest of the same shape that does. If an app keeps a minimum size or won't be resized, it says so. **Restore size** puts the window back. Needs Accessibility access, which it asks for.
- **Markers.** A flag on the recording bar marks a moment while you record, as does an Add Marker shortcut that you can set in Settings → Shortcuts (it has none to start with). Markers are saved with the recording and show as teal flags on the editor's timeline:
  - click to jump there, double-click to rename, right-click to rename or delete,
  - Marker adds one at the playhead, and Split at Markers splits the clips at every marker (one ⌘Z),
  - they become chapters in MP4 and ProRes exports ("Add chapters from markers"),
  - Copy Chapters gives "0:00 Start" text for a YouTube description, with a note when YouTube's rules aren't met,
  - they're on Creative Handoff's Final Cut Pro, DaVinci Resolve, and Premiere Pro timelines.
- **Looping cursor.** Cursor ▸ Loop ▸ Return to start at the end glides the pointer back to where it started over the last 0.3–2 seconds, so the last frame matches the first and the video loops without a jump.
- **Advanced shadow.** Style ▸ Frame ▸ Fine-tune shadow adds angle, distance, softness, opacity, and color, plus **Inset** for a soft inner edge. It starts from the look the Shadow slider had, so nothing jumps. It's saved in style presets. Projects and presets from before keep their shadow exactly.
- **Phone overlay.** For vertical (9:16) videos, a Phone overlay button above the preview shows a generic phone app's interface over the video (top bar, side buttons, caption area) and shades the parts it would cover. There are three layouts: Side rail, Full rail, and Minimal. It's drawn from plain shapes, in the preview only, and never in an export.

## [1.2.0] - 2026-10-27

### Changed
- **Manual only.** Nothing creative happens unless you click a button or switch. A new recording opens as you recorded it, in its own frame, with the real pointer: no background or padding, no zooms, no cursor smoothing, ripple, enlarging, hiding or blur, no camera mirroring or shrinking, no word highlighting in captions, and shortcut keys recorded but hidden until you show them. The camera bubble still shows, plainly. "Even out loudness" starts off too. Your projects, drafts, and project files open exactly as they were.
- **Auto-zoom on clicks** is now its own switch in the Zoom panel, off for new recordings. Turning it on plans zooms from your clicks and switches on its options (zoom feel, motion blur, the camera shrinking while zoomed); turning it off removes those zooms and options again. Either way it's one ⌘Z step, and zooms you placed yourself stay. The "Auto-zoom new recordings" setting is gone.
- **After a capture, nothing happens on its own.** Settings → General → After Capture has four switches, all off: Copy screenshots to the clipboard, Show the preview after capture, Open the video editor after recording, and Save automatically. Settings you changed yourself are kept; ones you never touched switch to off. Every screenshot is still kept in History and Home, and a short "Saved to History" notice says so.
- The "Recording saved" panel closes by itself after a few seconds (hover to keep it), and neither it nor the notice ever blocks anything.

### Added
- **Apply my style.** A button at the top of the Style panel (⇧⌘Y) puts your own look on the video in one ⌘Z step. In the Presets menu, "Use as My Style" picks which preset it is; until you pick one, the button explains how. A preset you'd set as the default for new recordings becomes My Style, and is no longer applied by itself.

## [1.1.1] - 2026-10-27

### Added
- **Full Mix in Creative Handoff.** 03 Audio now also has "Full Mix.wav": your voice, the Mac's sound, and the music mixed exactly as the edit plays them, the music dipping under your voice included — the finished video's own mix and loudness, as an uncompressed WAV. README.txt describes it; it stays off the timeline files, which already carry each track on its own.

### Changed
- **LF Studios has its own address.** The project moved to [brightlifecreations-projects/LF-Studios](https://github.com/brightlifecreations-projects/LF-Studios): About, Report Issue, crash reports, and Check for Updates point there. Links to the old address still lead to it.

## [1.1.0] - 2026-10-26

### Added
- **Creative Handoff.** File ▸ Creative Handoff… (⇧⌘E), the export dialog, or a recording's right-click menu in Home saves every part of a video as its own file, in a new folder wherever you choose (named "<Project> – Handoff <date>"):
  - the screen clips, the camera (recorded or added), the microphone and the Mac's sound as separate WAVs, and the music,
  - pictures, captions (.srt, with the translated track), the finished video, the pointer path, clicks and keys as JSON, and the fonts the project uses,
  - a timeline for Final Cut Pro and DaVinci Resolve (.fcpxml) and for Adobe Premiere Pro (.xml),
  - and a README.txt that lists every file, its length, frame rate, and start, and whether it's an untouched original or re-encoded.
- **Line everything up** (on by default) makes every file start at the same moment and run the same length, the camera's offset included, so an editor drops them all at 0:00 and they're in sync. Pick "Trimmed to my edit" or "Full original files".
- **Quality first.** Files are copied as they are wherever they can be; only clips cut to your edit and a camera with its background removed are re-encoded, to ProRes 422 HQ (or ProRes 422 with "Smaller files"). A camera with its background removed comes as ProRes 4444 with transparency, ready to place over anything.
- The handoff checks the free space first, runs in the background with progress for each file (and how long is left on Macs that encode ProRes slowly), skips and lists anything missing, and Cancel removes the half-made folder. When it's done, Reveal in Finder opens it.

### Changed
- **ShotStyle is now LF Studios.** The app, its menus and windows, Settings, permission prompts, About, and the "Made with LF Studios" end card all carry the new name, in every language. The app is "LF Studios" in Applications.
- **Your things come along.** The first time LF Studios opens on a Mac that used ShotStyle, it copies over your settings, shortcuts, style presets, added fonts, capture history, recordings' edits and data, and recent projects, and says so once. ShotStyle's own copy stays untouched, so nothing is lost if you keep the old app for a while. Recordings named "ShotStyle …" still show up in Home.
- **Old files still open.** New projects save as ".lfstudios" and presets as ".lfstudiospresets"; ".shotstyle" projects and ".shotstylepresets" files open just as before, by double-click too.
- macOS asks once for Screen Recording (and Accessibility) for LF Studios, since it sees a new app.

## [1.0.0] - 2026-10-26

The first release of ShotStyle, based on Shotnix 0.27.2 (MIT License). Shotnix's
own history is in [docs/SHOTNIX_CHANGELOG.md](docs/SHOTNIX_CHANGELOG.md).

### Added
- **A Home window.** ShotStyle now opens a main window: start a new recording, take a screenshot, start a scrolling capture or open a video, and find every recording and screenshot again in Projects, with thumbnails, size and duration. Search by name or by the text in a screenshot, click to open it in the editor, or right-click to delete it.
- **A regular Mac app.** ShotStyle always has a Dock icon and shows up in ⌘-Tab. Closing the Home window keeps it running in the menu bar, the Dock icon brings it back, and the shortcuts keep working.
- **Put captions anywhere.** In the video editor, drag the caption on the paused preview to place it anywhere on the frame. It snaps to the middle and to the top and bottom safe margins, with guide lines while you drag. Top and Bottom stay as quick presets, and Reset position brings captions back to the bottom. The spot is kept as a share of the frame, so it holds for 16:9, vertical and square videos, and a caption never leaves the frame, even after you change the aspect ratio or crop.
- **Place one caption on its own.** Select a caption on the timeline or in the list and drag it: only that caption moves, marked Custom position. Reset to default position puts it back with the others, and Apply this position to all captions moves every caption there.
- **Style presets.** A Presets menu at the top of the Style panel saves the whole look under a name: background, padding, corners, shadow, cursor, zoom feel, captions, keys, and camera bubble. Pick one to apply it to the video at once (⌘Z undoes it). Rename, delete, update a preset with the current style, or set one as the default for new recordings. Turn on "Include aspect ratio" when saving if a preset should also set 16:9, 9:16, and so on. Export and Import share presets as a small file, custom background pictures included. The look you saved before becomes the first preset, "My Look", and new recordings keep using it.
- **Camera crop, roundness, border, and shadow.** In the Camera panel's new Look section: Crop… lets you drag a frame over the camera picture to choose what the bubble shows, a Roundness slider goes from sharp corners to a full circle (the shapes stay as quick presets), Border adds an edge in any color and thickness, and the Shadow slider goes from none to strong. All of it works with the camera layouts, mirroring, background blur and removal, and shrinking while zoomed, and it's saved in presets.
- **Custom fonts.** Captions, title cards, text annotations, and the shortcut keys each get a font picker with every font on your Mac, a weight (Auto, Regular, Bold, Black), and optional Outline and Shadow for readability. Add Font File… brings in a .ttf or .otf and keeps ShotStyle's own copy, so it keeps working if the original is deleted. If a project uses a font this Mac doesn't have, the built-in font stands in and ShotStyle says so. Exports use exactly the font and layout the preview shows, and fonts are saved in presets.
- **Project files.** File ▸ Save Project (⌘S), Save Project As… (⇧⌘S), and Open Project… (⌘O) keep a whole edit as one ".shotstyle" document: the recording, camera video, pointer, clicks, keys, audio, music, pictures, fonts, and the edit itself. "Include media" makes a project that opens on any Mac; "Link to media" keeps it small for this Mac. Saving again only copies what changed. Double-click a project in Finder to open it, and find recent ones in the Home window (which also has Open Project…). Projects carry a format version, so ones from older ShotStyle versions keep opening, and auto-saved edits work exactly as before.
- **Camera video from elsewhere.** Filmed yourself on a phone or a camera? In the Camera panel, Add camera video… puts that footage in the bubble instead of the recorded camera, lined up automatically by the sound both recorded (ShotStyle says so when their sound doesn't match clearly enough). Fine-tune it with the offset field, the nudge buttons, Sync by Sound, or by dragging the camera strip on the timeline; Replace… and Remove are there too. The video stays where it is: if it's moved, ShotStyle finds it, and if it's gone, "Camera video missing" offers Locate…. Every camera setting works with it (shapes, layouts, crop, roundness, border, shadow, mirror, background blur and removal), and it's saved in projects, copied inside with "Include media".
- **Light theme.** Settings → General → Appearance: System, Light Mode, or Dark Mode (System follows your Mac). It switches every window at once, no restart: the video editor and its timeline and panels, Home, Settings, History, the Command Center, and the screenshot editor. The capture overlay, recording bar, screenshot thumbnail, and countdown stay dark so they read over any screen, and your videos and screenshots look exactly the same either way.
- **Move the shortcut keys too.** The keycaps drag, snap and reset the same way.
- Every move can be undone, exports (MP4 and GIF) put captions and keys exactly where the preview shows them, and projects from before open with their Top or Bottom setting.

### Changed
- **New name and icon.** Shotnix is now ShotStyle, with its own icon.
- **ShotStyle's own home.** About, Report Issue, crash reports and Check for Updates point to [brightlifecreations-projects/ShotStyle](https://github.com/brightlifecreations-projects/ShotStyle).
- **Crash reports go to GitHub.** The email option is gone; a report opens a GitHub issue with the crash report ready to attach.
