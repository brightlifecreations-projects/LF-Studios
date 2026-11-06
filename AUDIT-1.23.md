# Audit 1.23.0

Ratings: **works** · **wrong** (wrong result) · **confusing** · **laggy** · **stuck** · **crash**.
How: UI tests that drive the real views with mouse and key events in offscreen windows
(Audit123Tests and the existing interaction tests), both editor layouts, a short project
and a 10-minute 1080p project; each finding names its test.

## Found before the audit

| # | Where | Rating | What | Fix | Test |
|---|---|---|---|---|---|
| A0 | Test helper `writeFakeRecording` (not the app) | crash (the Mac) | Leaked 499 pixel buffers a frame; the editor screenshot test reached 7.8 GB in 2 s, swap filled, WindowServer stopped answering → kernel panic (4 Nov, 4×) | Stop at the first buffer; screenshot windows released after each picture | TestMediaMemoryTests; kill-switch log |
| A1 | Test isolation (not the app) | stuck | AppearanceSnapshotTests sat 44 min in `open()` of the real Desktop: Home scans the default save location, and a test process reading ~/Desktop waits on a macOS privacy prompt nobody answers | in a test process `Settings.defaultAutoSaveLocation` is a temporary folder (SettingsTests hung the same way) | AppearanceSnapshotTests finishes |
| A2 | Home ▸ reload (`HomeModel.reload` → `VideoRecordingFolders.projects`) | stuck (risk) | Lists every recording folder and reads each manifest's date **on the main thread**; a slow network/iCloud folder or a privacy prompt freezes Home | (Phase 3) | — |
| A3 | Every editing command × every selection (273 pairs: nothing, main clip, picture, caption, zoom, text, range) | works | Each is exactly one ⌘Z step, none leaves an empty step, ⌘Z/⇧⌘Z give back the exact project | — | Audit123Tests.testEveryCommand… |
| A4 | Save and reopen a rich project (.lfs, linked and media-included) | works | Cuts, captions, zoom, text and the picture survive | — | Audit123Tests.testARichProject… |
| A5 | A drag where the hand rests > 1.5 s before letting go (zoom/text/clip blocks, sliders) | wrong | One drag became **two ⌘Z steps**: steps merged only while edits came < 1.5 s apart | Edits from the same mouse press (AppKit's event number) always merge; separate presses stay separate | Audit123Tests.testADragWithARest… |
| A6 | 10-minute 1080p project, 60 cuts, 60 captions, 20 zooms | works / laggy | Opens in 11 ms, a cut 0.9 ms, ⌘Z 0.9 ms; but a timeline **zoom step draws in up to 48 ms** and a block drag frame in 20 ms (60 fps needs 16.7) | (Phase 4) | Audit123Tests.testATenMinute… |

The app itself didn't leak here: with the helper fixed, the same editor test peaks at ~400 MB.
