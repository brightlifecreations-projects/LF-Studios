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
