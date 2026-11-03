# Progress: 1.21.1 (fixes), then 1.22.0 (clean-up)

## 1.21.1 — branch `fix-1.21.1`
- [x] 1. Loop playback: a pause in the loop's last 0.1 s pauses (restart only on the player's played-to-end)
- [x] 2. Delete Gaps After Playhead: no empty ⌘Z step (test: items out of order, no gap)
- [x] 3. ⌥-drag copy: leftover if/else folded into one call
- [ ] 4. Old-project sound export test: real cause found and fixed
- [x] 5. ⇧⌘V while typing pastes into the text field (AppDelegate.pasteIntoText)
- [x] 6. graphify-out/ in .gitignore
- [ ] CHANGELOG [1.21.1]
- [ ] test-quick, test-full, CI, merge
- [ ] Publish 1.21.1 (rehearsal from 1.21.0; ≥10 GB free)

## 1.22.0 — branch `cleanup` (from main after 1.21.1)
- [ ] Before numbers: /graphify ., /ponytail-audit, largest files, VideoEditorModel lines + links
- [ ] Reference copies of 1.21.1 under Tests/…/Fixtures/Reference-1.21.1 (checksums, small screenshots)
- [ ] Split VideoEditorModel (extensions by job, one commit each, test-quick after each)
- [ ] Split the large inspector/panel views
- [ ] Delete proven-unused code
- [ ] CHANGELOG [1.22.0] "Faster, cleaner internals; nothing changes for you"
- [ ] test-full, CI, merge, publish (rehearsal from 1.21.1)
- [ ] /graphify . again; REPORT-1.22.md and chat report

## Notes
