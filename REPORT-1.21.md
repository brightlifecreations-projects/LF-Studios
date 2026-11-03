# LF Studios 1.21.0: report

Branch `editor-basics` → main (PR #15). Progress: PROGRESS-1.21.md. Every
choice: DECISIONS-1.21.md (19). CHANGELOG [1.21.0].

## Links
- Release: https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/tag/v1.21.0
- Screenshots: https://claude.ai/artifact/XPkjLEHzPWj5qdzFLEJyvo
- PR: https://github.com/brightlifecreations-projects/LF-Studios/pull/15 (merged)

## Checks
- test-quick after each commit; test-full green on run 3 (1170 s). Run 1
  caught the meters' tap delaying Play (fixed: meters are a switch, off at
  first). Run 2's one miss (Project117SoundTests under load) also fails on
  1.20.0 under load: older, not this update.
- CI green. Rehearsal: 1.20.0 updated itself to 1.21.0. Cleanup: 792 MB.
  37 GB free after.

## Moved to the next update (1.21.1)
- Loop playback: pausing within the last 0.1 s of the loop range starts
  it again (found in review after publishing). Fix: restart on stop only
  at the video's real end, plus a test.
- Delete Gaps After Playhead: a possible empty undo step if pieces were
  ever stored out of order; and a few leftover lines in copyLayerItems.

## Please check by hand
1. Recording bar: Area popover with a real microphone and camera; Esc and
   a click outside close it.
2. Skimmer: ⌘B with the pointer over the timeline, and with it elsewhere.
3. ⌥-drag copy, roll at a cut, the Trim tool's slide and slip.
4. ⇧⌘V while typing in a caption field (does it steal paste-and-match-style?).
5. Meters on: levels move; Play starts a moment later only while they're on.
6. Workspace ID with a real all-workspaces Anthropic key.
