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
| A2 | Home ▸ reload (`HomeModel.reload` → `VideoRecordingFolders.projects`) | stuck (risk) | Lists every recording folder and reads each manifest's date **on the main thread** (each time Home becomes key); a slow network/iCloud folder or a privacy prompt freezes Home | **Fixed**: folders are read in the background, the newest scan wins | Audit123Tests.testHomeReadsFoldersOffTheMainThread |
| A3 | Every editing command × every selection (273 pairs: nothing, main clip, picture, caption, zoom, text, range) | works | Each is exactly one ⌘Z step, none leaves an empty step, ⌘Z/⇧⌘Z give back the exact project | — | Audit123Tests.testEveryCommand… |
| A4 | Save and reopen a rich project (.lfs, linked and media-included) | works | Cuts, captions, zoom, text and the picture survive | — | Audit123Tests.testARichProject… |
| A5 | A drag where the hand rests > 1.5 s before letting go (zoom/text/clip blocks, sliders) | wrong | One drag became **two ⌘Z steps**: steps merged only while edits came < 1.5 s apart | Edits from the same mouse press (AppKit's event number) always merge; separate presses stay separate | Audit123Tests.testADragWithARest… |
| A6 | 10-minute 1080p project, 60 cuts, 60 captions, 20 zooms | works / laggy | Opens in 11 ms, a cut 0.9 ms, ⌘Z 0.9 ms; but a timeline **zoom step draws in up to 48 ms** and a block drag frame in 20 ms (60 fps needs 16.7) | **Drag fixed** (14 ms): the zoom camera path skips the gaps between zooms. **Zoom better** (median 32 → 28.5 ms): the ruler draws only what's on screen, number formatting looks the language up once. The rest is SwiftUI laying out every clip, on screen or not: NEXT-RUN.md | Audit123Tests.testATenMinute…; VideoDemoProjectTests.testCameraPathIsUnchangedByTheGapSkip | Audit123Tests.testATenMinute… |

The app itself didn't leak here: with the helper fixed, the same editor test peaks at ~400 MB.

## Most-used features (6 Nov, code read by area, every finding checked against its callers)

| # | Where | Rating | What | Fix | Test |
|---|---|---|---|---|---|
| C1 | Caption ▸ Start at the playhead | wrong | The start was held before the old end: a 1–3 s caption moved to 5 s became 2.8–5.5 s; a moved line could sit out of order in Lines | New end first, then the start; lines kept in time order | Audit123Tests.testCaptionEditsFromTheInspector |
| C2 | Caption text field (⌘A, Delete, type) | wrong | The empty moment dropped the voice's word timings for good: no word highlight, cutting by text stopped working on that line | An empty line keeps its word timings for what's typed next | same |
| C3 | Locked Captions track ▸ inspector text, timing, × | wrong | Changed and deleted captions on a locked track | Refused with the lock notice, like the timeline | same |
| C4 | Inspector text field while switching captions | wrong (risk) | A focused field could write caption A's text into caption B | One field per caption (`.id`) | hand check |
| T1 | Library ▸ drag a text template, sticker, effect onto a locked track above the main track | wrong | It landed on the locked track | A locked track takes nothing new; a new track goes above it | Audit123Tests.testLockedTracksStay… |
| T2 | Drag an item up/down onto a locked track | wrong | Moved onto it | Refused | same |
| T3 | Box-select / Select Left/Right / ⌘-click, then ⌫ or drag | wrong | Items on locked tracks were picked and deleted or moved | Locked tracks' items aren't picked; locking drops them from the selection; ⌫ checks every picked item | same |
| T4 | Range (I/O) on a locked main track ▸ Cut this part / speed / mute | wrong | Changed the locked track | Refused | same |
| T5 | Drop a PDF or a folder on the timeline or player | confusing | Nothing happened, nothing said | "Some files weren't added…" | same |
| E1 | Export twice with the same name while the first runs | wrong (data loss) | No Replace/Keep Both question; the second silently replaced the first, and the sheet showed both jobs' progress | A name a running export will write counts as taken | Audit123Tests.testExportNamesAndWide4KH264 |
| E2 | Export H.264 at 4K of a wide (21:9) video | wrong | 5040×2160 is past H.264's 4096 limit: the export failed with a confusing message | H.264 shrinks to fit (HEVC keeps the full size) | same |
| R1 | Recording frame dragged onto another display | wrong | 1080p on Retina became 960×540 on a 1× display: the size was read at the new display's scale | Read before switching displays | hand check (needs two displays) |
| R2 | Record Window ▸ size preset, then Record or Esc at once | wrong (race) | The recording bar could come back during the countdown or after Esc | Only the bar still on show comes back | hand check (timing) |

Checked and fine: undo for slider drags, SRT/VTT import and export, clip reorder and trim bounds, split
minimum length, drop time and track, recording size math, a second recording refused, export cancel cleans
its partial file, export errors shown.
