# LF Studios 1.21.0: progress

Branch `editor-basics` from main (1.20.0). Free space at the start: 39 GB.
Choices: DECISIONS-1.21.md. New strings: Localization/translations/editor-basics.json.
The new feature is called "Loop playback" everywhere (owner's change), never
plain "Loop" (that's the cursor's Inspector switch).

- [x] A1–2 Recording bar: one row; the rows above it in the Area popover; Area shows the choice
- [x] B3 Skimmer: zoom and ⌘B / ⇧⌘B at the skimmer, else the playhead (brought into view)
- [x] B4 Vertical timeline scroll: headers with lanes, ruler fixed, smallest height reaches the last track
- [ ] C5 Box selection (⇧ adds, ⌘ toggles)
- [ ] C6 Delete gap / Delete gaps after playhead
- [ ] C7 Duplicate clips (⌥-drag, ⌘D)
- [ ] C8 Copy / paste attributes (sheet)
- [ ] C9 Roll and slide trims, trim type at the pointer
- [ ] C10 Loop playback (⌘L)
- [ ] C11 Solo
- [ ] C12 Rename tracks
- [ ] C13 Audio meters
- [ ] C14 Safe zones and grid
- [ ] C15 Reveal in Library (⇧F), Match frame
- [ ] D16 Anthropic Workspace ID
- [ ] Guide pages, shortcuts page, 7 languages
- [ ] test-full, screenshots page, PR, CI, merge, rehearsal from 1.20.0, publish, cleanup

## Notes
- A: done (commit "Recording bar: one row…"); test-quick: GuideTests found a
  duplicate page id and the 1.21.0 New badge, fixed in B3's commit.
- B3: done; test-quick: one miss in Project117SoundTests (loudness of the
  edited old project) while running in parallel; it passed twice alone on
  the same commit: load, not the change (nothing in B3 touches export).
