# Performance 1.23.0

Measured on the owner's Mac (Mac16,10, 16 GB), release of each test alone, under the memory
kill-switch (scripts/test-groups.sh: test process memory = `top` MEM, window and GPU surfaces
included; swap from `vm.swapusage`).

## Test runs and the WindowServer panics

| Test | Before (4–5 Nov) | After (5–6 Nov) |
|---|---|---|
| Reference1211SnapshotTests ▸ editor | **7,828 MB in 2 s → killed** (unguarded on 4 Nov: swap 0 → 4.7 GB, WindowServer watchdog panic) | 373–399 MB, swap +0 |
| Reference1211SnapshotTests ▸ Settings | 428 MB, swap +0 | 237 MB, swap +0 |
| Reference1211SnapshotTests (whole class) | panicked the Mac | **473 MB peak, swap +0**, WindowServer 491–655 MB and answering |
| LocalizedLayoutSnapshotTests | — | 403 MB, swap +0 |
| GuideSnapshotTests | — | 131 MB, swap +0 (17 min: slow, not stuck) |
| AppearanceSnapshotTests | stuck 44 min on a Desktop privacy prompt | **passes: 551 MB peak, swap +0** (Desktop isolated in tests) |
| VideoEditor115SnapshotTests | — | memory flat, but one picture in ~25 takes ~17 min: `cacheDisplay` blurs a layer in software at ~390 % CPU (not the sheet; still slow after ending sheets first). Stopped after 53 min; NEXT-RUN.md |
| Writing a 1440×900 fake recording | ~2.5 GB leaked per frame | TestMediaMemoryTests: < 100 MB for 10 frames |

Cause: the test helper's retry loop (DECISIONS-1.23.md 7), not the app.

## Editor: 10-minute 1080p project (60 cuts, 60 captions, 20 zooms)

Audit123Tests.testATenMinuteProjectStaysQuick, debug build (tests), alone, 3 runs each; a frame is
the change plus layout and drawing of the whole editor window.

| Step | Before | After | How |
|---|---|---|---|
| Drag a zoom block, one frame | median 20.2 ms, worst 21.7 | **median 13.8 ms, worst 15.8** | The camera path walked all 36,000 samples of the 10 minutes on every change; it now jumps over the gaps between zooms (same samples, bit for bit: VideoDemoProjectTests.testCameraPathIsUnchangedByTheGapSkip). The change itself went 10.7 → 5.9 ms. |
| Timeline zoom step, one frame | median 32–33 ms, worst 46–52 | median 28.5 ms, worst 43.5–44.5 | The ruler drew every tick and label of the whole video (thousands zoomed in); now only the part on screen. Clip lengths looked the text language up (bundle + Locale) on every call; now once. |
| Open / cut / ⌘Z | 8 ms / 0.8 ms / 1.1 ms | unchanged | — |

How it was found: `sample` of the test process while the step ran alone (600–800 steps), app frames
ranked by inclusive samples: `VideoCameraTrack.build` 38 % of a drag; `VideoTimelineClipView.body`
16 % and `VideoTimelineRuler` 13 % of a zoom step. What's left of a zoom step is SwiftUI laying out
all 60 clips, captions and zoom blocks, on screen or not (NEXT-RUN.md). A release build is faster.
