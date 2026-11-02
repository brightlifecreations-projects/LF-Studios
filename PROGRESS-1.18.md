# LF Studios 1.18.0: progress

Branch `panels`. Each part: build-app.sh, test-quick, commit. If context is
lost: re-read this file and carry on from the first unticked box.

## Decisions (from the owner)
- Compared against CapCut: audio as its own track under the video, captions
  as a track on top, a playhead with a full handle above the ruler.
- Floating panels come back when a project reopens, on the same screen and
  place (the main screen if that screen is gone).
- Every editor shortcut (Space, A/B/V, ⌘B, Q/W, ⌘Z, ⌘K…) works whichever
  panel or floating window has focus: a test.
- One audio track per added video; saved layouts per Mac.
- Both styles; default layouts exactly as 1.17.0 until something moves.
- Linked audio is derived from the video clips: old projects export
  identical (picture and sound); a new format only once audio is unlinked
  or moved.
- If floating panels aren't solid: ship docking first and say so.
- The AI agent connection is 1.19.0.

## Checklist
- [x] 1. Playhead: full handle above the ruler, draggable, line through all
      tracks; jumped-to playhead comes into view
- [x] 2. Audio on its own tracks (linked; Unlink/Link; volume/mute/fades)
- [x] 3. Captions track on top with blocks (drag, trim, double-click edit)
- [ ] 4. Panels: headers, docking with drop zones, resize, saved layouts
- [ ] 5. Floating panels (follow the project window, screens, reopen)
- [ ] 6. Shortcuts work in every panel and floating window (test)
- [ ] 7. Guide, translations, test-full, screenshots page, PR, CI, merge,
      rehearsal from 1.17.0, publish

## Notes
- Playhead: the handle is one overlay over the ruler and the lanes
  (VideoPlayheadHandle), not clipped by the ruler; the tracks' line used
  to sit 5.5 pt left of the handle (offset by the knob's half without a
  knob): fixed. Seeking while not playing brings an out-of-view playhead
  in (VideoTimelineScroller.reveal). VideoPlayheadSnapshotTests checks the
  whole handle and the line in pixels: 2 layouts × 2 looks × smallest and
  large window × 3 track heights × 2 zooms × start/middle/end.
- Linked audio: VideoLinkedAudio.swift (rows worked out from the clips;
  waveforms per sound track). Unlink = clip.audioOffset (format 5, own
  composition track). Layer videos' sound rows are linked only.
- Found and fixed a 1.17 bug: a lone setVolume point blends into the next,
  so a muted clip played half loud (and the clip before faded). Each clip
  now holds its level with a ramp ending 0.5 ms short of the next clip.
- Project117SoundTests: 1.17.0's measurements (recorded in a v1.17.0
  worktree with LF_PIXEL_RECORD=1) of 4 projects with sound; the muted
  clip is left out of them (VideoLinkedAudioTests checks it's silent).
