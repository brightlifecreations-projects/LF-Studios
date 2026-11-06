# Progress: 1.23.0 (one release; run restarted 2026-11-05 22:27; Mac slept 05:56; 8-hour run from 6 Nov 12:24, ends 20:24)

1.21.1 was already published (3 Nov) before this plan; 1.22.0 is not published on its own:
its work (`cleanup`) merges into main and ships in 1.23.0.
Rules: DECISIONS-1.23.md (gentle tests, load guard, memory kill-switch). Left over: NEXT-RUN.md.
(First attempt: 4 Nov 23:37; the Mac panicked at 23:44 and the run was lost.)

## 0. What crashes the Mac (22:27 → 00:27 at most)
- [x] Cause found (5 Nov 09:56): the fake-recording test helper leaked 499 pixel buffers a frame
      (`for … where Create(...)` kept calling Create); the editor screenshot test hit 7.8 GB in 2 s
- [x] Fixed the helper; regression test TestMediaMemoryTests; snapshot windows released after each picture
- [x] Kill-switch (1.5 GB / swap +500 MB) in scripts/test-groups.sh, self-tested
- [x] Rules from 5 Nov 22:27: -j 2, 1 worker, critical pressure = stop without retry, WindowServer answers its window list (22:35)
- [x] Proven: Reference1211SnapshotTests whole class 473 MB, swap +0, WindowServer answering (23:31); Appearance 551 MB, Guide 131 MB, LocalizedLayout 403 MB
- [x] Found on the way: a test reading the real Desktop hung 44 min on a privacy prompt (Desktop isolated in tests); VideoEditor115 slow (NEXT-RUN.md)
- [x] Stashed offscreen snapshot work: not used (unproven; NEXT-RUN.md)
- [x] PERFORMANCE-1.23.md before/after, AUDIT-1.23.md A0–A2 (01:30)
- [x] committed (27cdff1…adf3b34)

## 1. Finish 1.22 code
- [x] 1.21.1 fixes: shipped in 1.21.1; the sound dropout is in NEXT-RUN.md
- [x] Test scripts gentle; feature inspectors split; 18 unused items deleted (committed locally, 5 Nov)
- [x] pushed; draft PR #17 (6 Nov 12:27) so CI runs

## 2. Audit: AUDIT-1.23.md
- [x] Command × selection sweep, save/reopen, drag with a rest, 10-minute project (A3–A6)
- [x] Most-used features: timeline drags/trims/splits, recording + Area popover, captions, export, inspector, Library drag-and-drop (code read by area, 13 findings C1–R2, 13:00)
## 3. Fixes, worst first, each with a test
- [x] A5 one press = one ⌘Z step
- [x] A2 Home reads folders in the background (6 Nov 12:30)
- [x] C1–C4, T1–T5, E1–E2, R1–R2 fixed; tests for all but C4, R1, R2 (hand checks) (13:05)
- [x] Performance tests on 1080p media; the export flake measured (encoder noise, tolerance 12)
## 4. Performance quick wins: PERFORMANCE-1.23.md
- [x] A6 zoom-block drag 20 → 14 ms; timeline zoom 32 → 28.5 ms median (12:36); the rest in NEXT-RUN.md
## 5. Agent hard limits with tests
- [x] Four limits in the shared tool layer (MCP and the Assistant), tests per limit and per mock provider, AGENT-TOOLS.md from code, Guide page, Skill text
- [x] All agent tests pass with the screen unlocked (6 Nov 12:26)
- [x] Missing agent tools listed in NEXT-RUN.md
## 6. test-full, CI, merge, rehearsal, publish 1.23.0
- [x] CHANGELOG 1.23.0, Guide newVersions, 7 languages
- [x] test-full 1 (13:09–14:08, without GuideSnapshotTests and VideoEditor115SnapshotTests): only the 1.21.1 Settings pictures (save folder, date, Agent text: pinned and re-recorded) and a stale GuideTests build failed; both pass now
- [x] the two slow screenshot classes alone: Guide 15 s, VideoEditor115 5.5 min (no stall): back in test-full
- [x] test-full on 579f08d: all tests passed (16:03–17:41; two earlier runs stopped: the owner's app filled swap, then the 1080p export test's peak)
- [x] CI passed; PR #17 merged (ac5bcff, the same tree)
- [ ] publish 1.23.0: built, signed, feed written; **the update rehearsal stopped: Terminal isn't allowed under Accessibility** (it clicks Check for Updates). Nothing published; `LF Studios 1.23.0` (version + CHANGELOG date) is on main. Allow Terminal, then `bash scripts/publish-release.sh 1.23.0`.

## Log
- 4 Nov 23:37 first start; 23:44 panic (the leaking helper)
- 5 Nov 09:52–10:02 cause found and fixed (kill-switch caught it at 7.8 GB)
- 5 Nov 22:27 restart
- 6 Nov 01:30 crash part done (1 h over: slow screenshot classes); test-quick on the branch
- 6 Nov 02:00–05:41 audit A3–A6, A5 fixed, agent hard limits; screen locked from ~03:00 (playback, scroll and recording tests can't pass locked)
- 6 Nov 05:56 the Mac slept; run stopped
- 6 Nov 12:24 restart (caffeinate, unlocked): agent tests pass; pushed, PR #17; A2 and A6 fixed (12:36)
- 6 Nov 13:09 test-full 1; owner's apps (CapCut 2.2 GB) put memory at warning twice, the guard paused
- 6 Nov 14:15 Settings pictures pinned; slow screenshot classes tried alone
- 6 Nov 17:41 test-full passed; 17:43 PR #17 merged; publishing
- 6 Nov 17:45–17:52 publish: build and feed OK, rehearsal refused (Accessibility for Terminal); nothing published

- 6 Nov: 1.23.0 published after the rehearsal from 1.21.1 passed: https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/tag/v1.23.0
