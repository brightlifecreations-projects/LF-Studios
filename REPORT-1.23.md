# Report: 1.23.0 run (5–6 Nov 2026)

## Result
- **Published: 1.23.0** (6 Nov 2026): https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/tag/v1.23.0 (record copy: https://github.com/brightlifecreations-projects/LF-Studios/releases/tag/v1.23.0).
- Every check passed first: test-full on the release code (every class, screenshots included, 0 failures), CI, PR #17 merged, then the update rehearsal: 1.21.1 updated itself to 1.23.0 through Check for Updates and opened again. The live update feed offers 1.23.0, and the release's build files were cleaned up (797 MB).
- The first publish try stopped at the rehearsal because Terminal lacked Accessibility. Nothing went out then; it passed once the owner turned that on.

## What crashed the Mac (fixed, proven)
- A test helper leaked 499 pixel buffers a frame. The editor screenshot test reached 7.8 GB in 2 s, swap filled, and WindowServer stopped answering, which caused the kernel panics. The app wasn't the cause.
- Fixed in the helper, with a regression test. Each screenshot class now peaks at 0.12–0.66 GB with no swap growth (PERFORMANCE-1.23.md).
- The test scripts now:
  - run 1 worker and `-j 2`;
  - stop a test process at 1.5 GB, or when swap grows by 500 MB;
  - watch WindowServer and catch stuck tests;
  - never rerun anything automatically;
  - pause at warning pressure;
  - clean up after every run.

## Done
- **Agent hard limits.** All four are enforced in the shared tool layer, for MCP agents and the Assistant alike, with a test per limit and per mock provider. AGENT-TOOLS.md is generated from the code, and the Guide page is updated.
- **Audit** (AUDIT-1.23.md), with these fixes:
  - one drag is one ⌘Z step;
  - Home reads folders in the background;
  - locked tracks can't be changed by any route (5 ways were open);
  - captions: Start at the playhead, word timings, lock, field identity;
  - export: a second export with the same name no longer silently replaces the first; wide 4K H.264 fits;
  - recording: the frame keeps its pixel size on another display; the bar stays gone after Record or Esc;
  - unusable dropped files are now reported.
- **Performance:** on a 10-minute project, a zoom-block drag frame went from 20 to 14 ms. A timeline zoom step went from 32 to 28.5 ms; the rest is in NEXT-RUN.md.
- **Flaky tests fixed at their cause:**
  - the export picture check (encoder noise, measured);
  - Settings pictures (folder and date pinned);
  - the Extract Audio undo count;
  - test media at 1080p.

## Hand checks (no automatic test)
- C4: type in a caption's Text field in the inspector, then click another caption's time in Lines. The second caption must keep its own text.
- R1: on a Retina Mac, pick 1080p for the recording frame and drag it to a non-Retina display. The label must still say 1920 × 1080.
- R2: Record Window, pick a Window size, then press Record or Esc at once. The recording bar must not come back.

## Machine notes from this run
- The owner's SRT Generator app reached 10 GB and pushed swap to 8.9 GB at 15:45. The kill-switch stopped two screenshot classes whose own memory was 22–25 MB. That run was ended and restarted once memory was calm.
- Memory pressure went to warning several times (CapCut, SRT Generator, Codex). The guard paused each time and carried on.

Next steps: NEXT-RUN.md. Decisions: DECISIONS-1.23.md.
