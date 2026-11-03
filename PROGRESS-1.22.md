# Progress: 1.21.1 (fixes), then 1.22.0 (clean-up)

## 1.21.1 — branch `fix-1.21.1`
- [x] 1. Loop playback: a pause in the loop's last 0.1 s pauses (restart only on the player's played-to-end)
- [x] 2. Delete Gaps After Playhead: no empty ⌘Z step (test: items out of order, no gap)
- [x] 3. ⌥-drag copy: leftover if/else folded into one call
- [~] 4. Old-project sound export test: real cause found (see Notes); the fix moves to a later update
- [x] 5. ⇧⌘V while typing pastes into the text field (AppDelegate.pasteIntoText)
- [x] 6. graphify-out/ in .gitignore
- [x] CHANGELOG [1.21.1]
- [x] test-quick, test-full, CI, merge (PR #16; screen tests needed Blip's floating window closed)
- [x] Published 1.21.1: https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/tag/v1.21.1 (rehearsal 1.21.0→1.21.1 passed, 792 MB cleaned, 31 GB free)

## 1.22.0 — branch `cleanup` (from main after 1.21.1)
- [x] Before numbers: /graphify (Sources, code only, as before), audit done (see Notes)
- [x] Reference copies of 1.21.1 in Tests/LFStudiosCoreTests/Fixtures/Reference-1.21.1 (3.4 MB): Reference1211Tests + Reference1211SnapshotTests
- [ ] Split VideoEditorModel (extensions by job, one commit each, test-quick after each)
- [ ] Split the large inspector/panel views
- [ ] Delete proven-unused code
- [ ] CHANGELOG [1.22.0] "Faster, cleaner internals; nothing changes for you"
- [ ] test-full, CI, merge, publish (rehearsal from 1.21.1)
- [ ] /graphify . again; REPORT-1.22.md and chat report

## Notes
- Project117 sound (item 4): Apple's AVAssetReaderAudioMixOutput sometimes renders ~0.1–0.17 s of
  near-silence right after a sped-up clip (the "edited" project, 2× clip then a 1× clip, at 0.8–1.0 s).
  Measured: 1 in ~10 exports, busy or not; also with no audio mix, with .timeDomain pitch, and with a
  reader of its own for the sound. So it's a real (rare) dropout in exports, not a loose test.
  A sped-up clip's sound on its own composition track: 0 dropouts in 42, but the join still varies and
  differs from 1.17.0's reference at 0.6–0.8 s, so old projects would export differently. Not solid
  for a fix release; the probe test is kept in the scratchpad (probe117/Probe117Tests.swift).

- Reference copies (1.22.0): commands/keys/AI tools/menus/global shortcuts exact (interface.json);
  saved projects' manifest SHA-256 with date, ids and file bookmarks normalised (projects.json);
  older projects' exports: sound recipe SHA-256 (tracks, pieces, speeds, level every 10 ms) and
  64×36 frame thumbnails, ≤4/255 (run-to-run noise measured at ≤2; decoded sound and exact frames
  vary between runs of the same code, so they can't be checksummed); screens at half size, ≤0.02%
  pixels changed (noise ≤20 px on Settings ▸ Screenshots, 0 elsewhere). Proven: a changed key fails it.
- Audit (ponytail-audit, background agent): ~18 unused items (~110 lines), near-duplicates
  (microphone level ×2, showProblem/problem, drawGlow ×2), split plans: VideoEditorModel by MARK into
  +Undo/+Transport/+Clips/+Zooms/+Overlays/+Style/+Saving/+Thumbnails (stored props stay; isScrubbing
  moves up into State); VideoInspectorView → VideoStyleInspectors (137-686) + VideoSelectionInspector
  (687-); VideoEditorView → toolbar/keyboard/palette/sheets files; VideoTimelineView → toolbar,
  clip view, ruler, roll handle files; VideoFeatureInspectors at its MARKs (VideoPlacementRow internal).

## Before (1.21.1, 919a875)

## Largest files (lines)
    3935 Sources/LFStudiosCore/Capture/CaptureEngine.swift
    3716 Sources/LFStudiosCore/App/GuideContent.swift
    2569 Sources/LFStudiosCore/Video/VideoEditorModel.swift
    2275 Sources/LFStudiosCore/Video/VideoRenderer.swift
    2023 Sources/LFStudiosCore/Annotation/AnnotationCanvas.swift
    1933 Sources/LFStudiosCore/Capture/RecordingEngine.swift
    1879 Sources/LFStudiosCore/Video/VideoDemoProject.swift
    1701 Sources/LFStudiosCore/Video/VideoEditorView.swift
    1688 Sources/LFStudiosCore/Video/VideoTimelineView.swift
    1579 Sources/LFStudiosCore/App/PreferencesWindowController.swift
    1487 Sources/LFStudiosCore/History/HistoryPanelController.swift
    1307 Sources/LFStudiosCore/Capture/AreaSelectionWindow.swift
    1284 Sources/LFStudiosCore/Video/VideoInspectorView.swift
    1276 Sources/LFStudiosCore/Annotation/AnnotationToolbar.swift
    1221 Sources/LFStudiosCore/Video/VideoExporter.swift

## Totals
Swift files: 236
Lines: 106782
VideoEditorModel.swift lines:     2569
VideoEditorModel links (graph degree): 1093
Graph: 10794 nodes, 31484 edges, 366 communities
Cohesion: Editor Model & Features 0.014, Video Inspector Panels 0.042, Editor Model Actions 0.038, Editor Timeline State 0.038
