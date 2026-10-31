# LF Studios 1.16.0: progress

Branch `next-1.16`. Each part: build-app.sh, test-quick, commit. Tests with
synthetic audio only. If context is lost: re-read this file and carry on
from the first unticked box.

## Decisions (from the owner)
- Already there, don't rebuild: Edit by text, Remove ums, Shorten pauses,
  music ducking (under the recording's voice).
- Project settings: opened only by clicking the project name (and a Guide
  page). Never opened or offered automatically.
- Zoom cut: 120 %, 0.6 s by default. Colour space: Rec. 709 or Display P3
  only. Compound clip timeline last; moves to next update if not solid.
- Before publishing: an installed previous version must really update
  through Check for Updates (scripts/rehearse-update.sh, run by
  publish-release.sh).
- Release PRs are merged by Claude, after tests and CI pass.

## Checklist
- [x] 7. CI on main passes again (run 41226948148, by hand on 85b9b67)
- [x] Update error: found, fixed, rehearsal in publish-release.sh
- [x] 6. CHANGELOG dates from tags; publish script dates new headings
- [ ] 1. Zoom cut
- [ ] 2. Project settings window
- [ ] 3. Remove ums: review list before cutting
- [ ] 4. Ducking under voiceover and imported speech (switches, off)
- [ ] 5. Compound clip in its own timeline
- [ ] Guide pages, shortcuts page, 7 languages, CHANGELOG [1.16.0]
- [ ] test-full green, PR, CI green, merge, publish 1.16.0

## Notes
- Update error ("An error occurred while launching the installer"):
  reproduced by replacing a running app's files (build-app.sh did
  `rm -rf /Applications/LF Studios.app` + copy while it ran), then Install
  Update. A clean 1.14.0 → 1.15.0 update works (tested with the published
  zips). Fixes: build-app.sh quits LF Studios first and reopens it; the app
  notices it was replaced (AppBundleStamp) and Check for Updates asks to
  reopen instead of failing; publish-release.sh runs rehearse-update.sh.
- The rehearsal points the old version at a local feed with the launch
  argument `-SUFeedURL` (Sparkle reads it from the user defaults), and
  `-AppleLanguages (en)` so the menu and buttons have known names.
- For the CHANGELOG entry: "Check for Updates no longer fails when LF
  Studios was replaced while open: it asks to reopen."
