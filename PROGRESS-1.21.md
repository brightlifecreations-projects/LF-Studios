# LF Studios 1.21.0: progress

Branch `editor-basics` from main (1.20.0). Free space at the start: 39 GB.
Choices: DECISIONS-1.21.md. New strings: Localization/translations/editor-basics.json.
The new feature is called "Loop playback" everywhere (owner's change), never
plain "Loop" (that's the cursor's Inspector switch).

- [x] A1–2 Recording bar: one row; the rows above it in the Area popover; Area shows the choice
- [x] B3 Skimmer: zoom and ⌘B / ⇧⌘B at the skimmer, else the playhead (brought into view)
- [x] B4 Vertical timeline scroll: headers with lanes, ruler fixed, smallest height reaches the last track
- [x] C5 Box selection (⇧ adds, ⌘ toggles)
- [x] C6 Delete gap / Delete gaps after playhead
- [x] C7 Duplicate clips (⌥-drag, ⌘D)
- [x] C8 Copy / paste attributes (sheet)
- [x] C9 Roll and slide trims, trim type at the pointer
- [x] C10 Loop playback (⌘L)
- [x] C11 Solo
- [x] C12 Rename tracks
- [x] C13 Audio meters
- [x] C14 Safe zones and grid
- [x] C15 Reveal in Library (⇧F), Match frame
- [x] D16 Anthropic Workspace ID
- [x] Guide pages, shortcuts page, 7 languages (6 languages translated by helpers in parallel: editor-basics.<lang>.json)
- [ ] test-full, screenshots page, PR, CI, merge, rehearsal from 1.20.0, publish, cleanup

## Notes
- A: done (commit "Recording bar: one row…"); test-quick: GuideTests found a
  duplicate page id and the 1.21.0 New badge, fixed in B3's commit.
- B3: done; test-quick: one miss in Project117SoundTests (loudness of the
  edited old project) while running in parallel; it passed twice alone on
  the same commit: load, not the change (nothing in B3 touches export).
- B4: done; test-quick green.
- C + D: one commit. Notes: main-track clips aren't duplicated; slide on
  the main track needs cut-out parts of the recording (DECISIONS 8–10).
  VideoEditorBasicsTests and VideoLongTimelineTests (playback timing, the
  window's scroll) run alone (scripts/test-groups.sh).
- test-full #1: two misses, Project117SoundTests (passes alone, same
  numbers as during B3, before any audio change) and VideoEditorModelTests'
  playback start. The second was real: the meters' tap made Play start
  0.1–0.15 s later (measured). Fixed by making the meters a switch, off to
  start with (DECISIONS 19).
- test-full #2: one miss, Project117SoundTests ("edited": loudness at
  2.2 s), at a different moment than before. Stressed with 10 busy cores:
  main (1.20.0) failed it too (1 run in 4), the branch didn't (0 in 4).
  An older weakness of exports under heavy load, not this update; told
  the owner. test-full #3 next.
