# LF Studios 1.19.1: report

Branch `fix-1.19.1` → main. The owner's two decisions from DECISIONS-1.19.md.

## What changed
1. **Videos above the main track keep their sound's level** (decision 2 of
   1.19.0). A lone volume point blended into the next one, so the sound
   faded from full to nearly silent across the item (0.3 → 0.03 RMS in the
   test). Each level is now held with a ramp, like the main track's clips
   since 1.18.0, also before the first and after the last volume keyframe.
   Fades, volume keyframes, unlinked sound and mutes work as before.
   - Intended: projects with such a video sound different from 1.18.0 and
     1.19.0 there (noted in the CHANGELOG). The 1.18.0 check still compares
     all six kinds of project with 1.18.0's measurements: everything but
     the layered project's video sound must match exactly; that sound is
     checked to stay level instead.
2. **Tacks are saved with the project** (decision 4 of 1.19.0).
   - `VideoDemoProject.tacks`, written only when there are some. Such a
     project is format 6 (`"requires" : 6`); everything else is written as
     1.19.0 wrote it, and removing the last Tack goes back.
   - Checked with 1.19.0's own code (a v1.19.0 worktree): a project with a
     Tack → "needs a newer version"; one without opens.
   - A Tack is a note, not an edit: changing one saves the draft but is
     never a ⌘Z step; undo, redo, Revert all and a cancelled crop keep
     them. The Agent panel and the ruler pins show them with no agent
     connected; `list_tacks` returns them in a new session.
   - Guide page "Tacks" updated (new again in What's new), and the agent's
     instructions; all 7 languages.
3. **Found and fixed on the way:** in 1.19.0 an agent couldn't leave a Tack
   while the user had taken over, though the error message and its
   instructions tell it to. `add_tack` now goes through (the run stays
   paused for edits). Tested.
4. **publish-release.sh cleans up after itself** (your request): after a
   successful publish it deletes the release's zip, feed, notes, universal
   app and release products. A failed publish keeps them.

## Disk
- Before starting: 14 GB free → 22 GB after cleaning ($TMPDIR/lfstudios-*,
  Xcode DerivedData, the repo's old build products; the 1.19.0 zip was
  kept). Each test run's temporary files deleted after it.

## Tests
- New: VideoLinkedAudioTests.testAVideoAboveTheMainTrackKeepsItsLevel
  (plain, fades, volume keys, unlinked, a muted neighbour, a muted track;
  it fails on 1.19.0's mix code), VideoAgentTests.testTacksAreSavedWithTheProject
  (format 6, ⌘Z/Revert all keep them, saved and reopened in a new editor,
  back to the old format without them), add_tack while taken over.
- test-quick after each code commit: green. test-full: green on the first
  run (1382 s).
- CI green on PR #13; merged.

## Not published: disk space
- The publish was stopped by the 6 GB rule. After test-full and the merge,
  free space was 8.4 GB (from 18 GB); I deleted the repo's index and
  localization build folders (→ 10 GB) and ran publish-release.sh under a
  watcher. During the Intel half of the universal build it fell to 5 GB,
  so the watcher stopped it **before the rehearsal and before anything was
  published**. No v1.19.1 release exists; the feed still offers 1.19.0.
- What the script had already done: committed and pushed "LF Studios
  1.19.1" to main (Info.plist version, CHANGELOG dated 2026-11-03). That's
  fine to leave: running it again finds nothing to commit and goes on.
- The partial release files were deleted. Free space is now 5.6 GB; the
  repo's own build files are about 2 GB. The rest went outside the repo
  (another project's temp folder, /private/tmp/claude-501/-Users-aman-
  srt-generator-update, alone is 3 GB). I didn't touch anything outside
  the repo.
- To publish: free some space (about 10 GB free is comfortable), then
  `bash scripts/publish-release.sh 1.19.1` on main. It rehearses from
  1.19.0, publishes, and now deletes its own build files after (including
  the release-only intermediates, added after this run showed where they
  go).
