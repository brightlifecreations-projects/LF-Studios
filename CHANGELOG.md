# Changelog

## [1.1.1] - Unreleased

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
