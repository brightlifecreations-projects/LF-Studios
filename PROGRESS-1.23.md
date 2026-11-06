# Progress: 1.23.0 (one release; 10-hour run restarted 2026-11-05 22:27, ends 08:27)

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
- [ ] commit after test-quick

## 1. Finish 1.22 code
- [x] 1.21.1 fixes: shipped in 1.21.1; the sound dropout is in NEXT-RUN.md
- [x] Test scripts gentle; feature inspectors split; 18 unused items deleted (committed locally, 5 Nov)
- [ ] test-quick on the whole branch, push

## 2. Audit: AUDIT-1.23.md
## 3. Fixes, worst first, each with a test
## 4. Performance quick wins: PERFORMANCE-1.23.md
## 5. Agent hard limits with tests
## 6. test-full, CI, merge, rehearsal, publish 1.23.0

## Log
- 4 Nov 23:37 first start; 23:44 panic (the leaking helper)
- 5 Nov 09:52–10:02 cause found and fixed (kill-switch caught it at 7.8 GB)
- 5 Nov 22:27 restart
- 6 Nov 01:30 crash part done (1 h over: slow screenshot classes); test-quick on the branch
