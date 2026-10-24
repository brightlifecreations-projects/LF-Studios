# Changelog

## [1.0.0] - Unreleased

The first release of ShotStyle, based on Shotnix 0.27.2 (MIT License). Shotnix's
own history is in [docs/SHOTNIX_CHANGELOG.md](docs/SHOTNIX_CHANGELOG.md).

### Added
- **A Home window.** ShotStyle now opens a main window: start a new recording, take a screenshot, start a scrolling capture or open a video, and find every recording and screenshot again in Projects, with thumbnails, size and duration. Search by name or by the text in a screenshot, click to open it in the editor, or right-click to delete it.
- **A regular Mac app.** ShotStyle always has a Dock icon and shows up in ⌘-Tab. Closing the Home window keeps it running in the menu bar, the Dock icon brings it back, and the shortcuts keep working.
- **Put captions anywhere.** In the video editor, drag the caption on the paused preview to place it anywhere on the frame. It snaps to the middle and to the top and bottom safe margins, with guide lines while you drag. Top and Bottom stay as quick presets, and Reset position brings captions back to the bottom. The spot is kept as a share of the frame, so it holds for 16:9, vertical and square videos, and a caption never leaves the frame, even after you change the aspect ratio or crop.
- **Place one caption on its own.** Select a caption on the timeline or in the list and drag it: only that caption moves, marked Custom position. Reset to default position puts it back with the others, and Apply this position to all captions moves every caption there.
- **Style presets.** A Presets menu at the top of the Style panel saves the whole look under a name: background, padding, corners, shadow, cursor, zoom feel, captions, keys, and camera bubble. Pick one to apply it to the video at once (⌘Z undoes it). Rename, delete, update a preset with the current style, or set one as the default for new recordings. Turn on "Include aspect ratio" when saving if a preset should also set 16:9, 9:16, and so on. Export and Import share presets as a small file, custom background pictures included. The look you saved before becomes the first preset, "My Look", and new recordings keep using it.
- **Camera crop, roundness, border, and shadow.** In the Camera panel's new Look section: Crop… lets you drag a frame over the camera picture to choose what the bubble shows, a Roundness slider goes from sharp corners to a full circle (the shapes stay as quick presets), Border adds an edge in any color and thickness, and the Shadow slider goes from none to strong. All of it works with the camera layouts, mirroring, background blur and removal, and shrinking while zoomed, and it's saved in presets.
- **Move the shortcut keys too.** The keycaps drag, snap and reset the same way.
- Every move can be undone, exports (MP4 and GIF) put captions and keys exactly where the preview shows them, and projects from before open with their Top or Bottom setting.

### Changed
- **New name and icon.** Shotnix is now ShotStyle, with its own icon.
- **ShotStyle's own home.** About, Report Issue, crash reports and Check for Updates point to [brightlifecreations-projects/ShotStyle](https://github.com/brightlifecreations-projects/ShotStyle).
- **Crash reports go to GitHub.** The email option is gone; a report opens a GitHub issue with the crash report ready to attach.
