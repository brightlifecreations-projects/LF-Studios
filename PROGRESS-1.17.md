# LF Studios 1.17.0: progress

Branch `weftcut-ui`. Each part: build-app.sh, test-quick, commit. If
context is lost: re-read this file and carry on from the first unticked box.

## Decisions (from the owner)
- Look and work like WeftCut (design reference only; it's Electron/React, so
  no code is reused; if any is, its MIT notice goes in THIRD_PARTY_NOTICES.md).
  Keep LF Studios' name, logo and icons. Never bundle FFmpeg.
- Out of 1.17.0: agent mode, MCP, Tacks, Motifs, the Changes list (the agent
  connection is 1.18.0). Bézier tangent handles: next update.
- CapCut style: exactly as 1.16, unchanged (its own code path).
- Keys: LF Studios' (A Select, B Split tool, V on/off…), from the keymap,
  so custom shortcuts show in the tool rail and status strip.
- Effect chain: existing effect order kept (pixel-identical); dragging a
  card is a VideoEditCommand, one ⌘Z step.
- Uppercase labels: German, Russian, Ukrainian must fit at 13" (wrap or
  shorten); Japanese and Chinese as they are.
- Editor UI tests run in both layouts (forEachEditorStyle / inEditorStyles),
  never pinned to CapCut style.
- Anything not solid moves to next update, and the owner is told.

## Checklist
- [x] 1. Style setting + theme tokens + labels + Layout menu
- [x] 2. New frame: top bar search, tool rail, monitor strip, status strip
- [x] 3. Right panel: At playhead + Clip / Effects / Captions / Video
- [ ] 4. Timeline: A/B naming, fixed top rows, waveform strip, curve lane
- [ ] 5. Global search ⌘K (commands, media, clips, captions, markers)
- [ ] 6. Caption cue list + Restyle all
- [ ] 7. Guide (new locations + screenshots), translations, test-full,
      screenshots page, PR, CI, merge, rehearsal from 1.16.0, publish

## Notes
- Theme: every VideoEditorTheme token is `Color.styled(…)`: CapCut values
  unchanged, LF Studios values from WeftCut's dark palette (#0c0e12 window,
  #111419 panels, #181c23 raised, #14171d lanes, #252a34/#363e4b borders,
  #e5e7eb/#9ca3af text, #2563eb primary) and a matching light set.
  `VideoEditorStyle.current` is read when colours draw; the root view has
  `.id(style)` so a switch redraws everything.
- VideoEditorRootView: `capCutEditor` is 1.16's stack moved as is;
  `newEditor` is the new frame (VideoEditorNewLayout.swift).
- Right panel (VideoPropertiesPanel.swift): AT PLAYHEAD (now playing, next
  10 s) + CLIP (selection) / EFFECTS (chain) / CAPTIONS / VIDEO (Style,
  Cursor, Zoom, Camera, Audio). `propertiesTab` follows `inspectorTab` set
  from elsewhere, and a new selection brings CLIP forward from VIDEO.
- Effect chain: effects draw in array order (unchanged for old projects);
  `VideoAppliedEffect.off` (nil = on, not written); edits moveEffect /
  setEffectOn / removeEffect, one ⌘Z step each. Adjust and Filter cards are
  fixed (they draw before the effects, as always).
- Part 4 (owner): A roll / V2 · B roll / V3 are display labels for the new
  layout only (CapCut keeps "Video clips", "Video 2"); nothing in the file.
  The curve lane reads and writes the same keys as the ◆ marks and the Clip
  tab: a test checks both directions.

