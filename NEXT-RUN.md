# Next run (paste into the next session)

- Branch `cleanup` holds the 1.22 clean-up plus the 1.23 work; nothing of 1.22/1.23 is published.
- Old-project sound: Apple's audio mix renders ~0.1–0.17 s of near-silence after a sped-up clip in ~1 export in 10 (PROGRESS-1.22.md Notes). A fix changes old exports; needs its own release note.
- `git stash@{0}`: offscreen screenshot helpers (unproven against the 1.21.1 pictures). Try one class at a time under the kill-switch; drop if pictures change.
- Screenshot classes are slow: GuideSnapshotTests 17 min; VideoEditor115SnapshotTests stalls ~17 min on about one picture in 25 (`cacheDisplay` blurring a layer on the CPU at ~390 %, memory flat). Find which layer (sample during a stall: the stack under `_renderLayerInContext`) and render it without that cost, or split the class. test-full runs screenshot classes one at a time, last.
- Home scans recording folders on the main thread (AUDIT A2).
