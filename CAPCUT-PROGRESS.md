# CapCut-style editor, Phases 2–4 → LF Studios 1.15.0

Branch `capcut-pro`. Work top to bottom; after each part `bash build-app.sh`
must succeed, then commit. Tests are written with each feature but run only
in the final pass. If context is lost: re-read this file and carry on from
the first unticked box.

## Decisions (from the owner)
- Shortcut presets: LF Studios default, Final Cut Pro style, Premiere Pro
  style; each changes only keys LF Studios has.
- Proxies: ProRes Proxy at half resolution. Show estimated disk space first.
  Stored with the app's caches, removed by Clean Up, never in Creative
  Handoff or Include media, rebuilt on another Mac when missing (the project
  opens from the originals meanwhile).
- Text templates: only fonts that come with macOS (or OFL fonts bundled and
  listed in LICENSES.md). Never fonts the user happens to have installed.
- Risky pieces move to "next update" rather than ship half done.

## Architecture notes
- Everything that draws above the main track is a `VideoLayerItem` on a
  `VideoLayerTrack` (VideoLayers.swift): media, text, sticker, effect,
  adjustment, compound. Higher tracks draw on top. Legacy annotations stay a
  pinned group drawn over the tracks (1.14 look) until "Move to track".
- Keyframes: `VideoKeyframes` (per property, item-relative seconds, easing).
- New project format: `lfstudios-project-4` (version 4, requires 4), written
  only when something new is used (`needsFormat4`).
- Every action: a `VideoEditCommand` case, one undo step, refused on locked
  tracks.

## Part A: keyframes and clip properties
- [x] A1 Keyframes (diamond buttons, marks on clips, prev/next, easing)
- [x] A2 Video: transform, opacity, blend modes; Cutout (Remove background, Chroma key); Masks
- [x] A3 Animation: In / Out / Combo presets with duration
- [x] A4 Speed: Normal 0.1×–100× (keep pitch) and Curve presets + custom curve
- [x] A5 Audio: volume keyframes, fades, normalize, Detect beats
- [x] A6 Text on its own track: font, size, B/I/U, colour, stroke, background, shadow, spacing, alignment
- [x] A7 Motion tracking (Track button, Vision object tracking)

## Part B: Library content
- [x] B8 Text tab: templates and styles, hover preview, drag onto timeline
- [x] B9 Effects tab: Core Image effects with intensity, on a clip or as an effect clip
- [x] B10 Transitions tab: dissolve, fade black/white, slide, push, wipe, zoom, blur, spin; duration; Apply to all
- [x] B11 Filters tab: own LUT looks with intensity
- [ ] B12 Adjustment tab: adjustment layer; full Adjust panel (HSL, curves, wheels, .cube import)
- [ ] B13 Stickers and sound effects (own/CC0, LICENSES.md), Import sticker (PNG/GIF)
- [ ] B14 Captions tab: auto captions, style templates, SRT import/export
- [ ] B15 Show Stickers/Effects/Filters/Adjustment tabs; favourites and search in every tab

## Part C: pro tools and export
- [ ] C16 Keyboard shortcuts editor with presets, conflicts, reset
- [ ] C17 Proxy mode (ProRes Proxy, half res, estimate first)
- [ ] C18 Compound clips: make, break apart, open in own timeline
- [ ] C19 Export window (CapCut structure)
- [ ] C20 Cover frame/image embedded in the export
- [ ] C21 Performance: background rendering, thumbnail/waveform cache, 30-min synthetic project

## Final pass
- [ ] Work through TESTING-LATER.md
- [ ] test-quick green
- [ ] test-full green
- [ ] Old projects (.lfs, .lfsp, .lfstudios, .shotstyle) pixel-identical to 1.14.0
- [ ] Screenshots page (light/dark, en/de, 1920×1200 and 13")
- [ ] CHANGELOG (dated), merge, publish 1.15.0

## Next update (moved out, with why)
(none yet)

## Notes
- A1: keyframes live on VideoLayerItem.keys; edits go through
  `setLayerAnimated` (keys at the playhead when a property is animated).
  Commands: addKeyframe (⌥K), previousKeyframe (⌥[), nextKeyframe (⌥]).
  Per-property diamonds call `toggleKeyframe` (one undo step, lock-checked).
  Keyframes apply to items above the main track (main-track clips have no
  transform to animate). Format 4 is in place (`needsFormat4`).
- A2: VideoEditCommand now has `.edit(VideoItemEdit)` for edits with values
  (setValue/toggleKeyframe/setEasing/setBlend/setRemoveBackground/
  setChromaKey/setMask; add more cases there). Blend modes, chroma key (colour
  cube), remove background (Vision person segmentation, cached per frame),
  masks (linear, mirror, circle, rectangle; feather, invert, keyed).
- A3: VideoItemAnimation (in/out presets ×10, combo ×5, lengths), applied
  by `VideoLayerItem.shown(at:)` after keyframes (renderer uses it). Text
  items (A6) must go through the same path.
- A4: main clips 0.1–100×, `keepsPitch` (separate varispeed sound tracks,
  per-input pitch algorithm), silent outside 1/32–32×. Curves are baked into
  8–40 sub-clips sharing `VideoDemoTimelineClip.curve` (group id + curve);
  transitions skip cuts inside a group. `.clip(VideoClipEdit)` commands
  (setSpeed/setKeepPitch/setSpeedCurve). Items above: 0.1–100× + keep pitch
  (curves on main-track clips only). Watch in final pass: whether the
  per-input varispeed algorithm is honoured by the export reader (test
  VideoSpeedTests.testKeepPitchInTheExport); if not, keep-pitch-off moves to
  next update.
- A5: `.audio(VideoAudioEdit)` (toggleVolumeKey/setVolume/normalize/
  detectBeats/clearBeats) for sound files and music (VideoAudioTarget);
  volume keys on sound files in file seconds; beats on sound files and music
  (ticks on lanes, snap targets). Items above: `.edit(.setSoundFades)`,
  `.edit(.normalize)`; volume keys there come from A1.
- A6: text clips are `VideoLayerItem`s with `text: VideoTextContent`
  (kind .image, empty path; `isText`). Rendered by VideoTextClipRenderer
  (cached CGImage at the drawn height) inside VideoLayerRenderer, so keys,
  animations, blend and masks all apply. Fonts: VideoTextFonts.families
  (macOS only; anything else falls back). `.addTextClip` (⌥⇧T; ⌥T stays the
  1.14 text annotation) and `.edit(.setText)`; size follows the words and
  look, keeping a hand-set scale. Media paths skip text (Library, handoff,
  project packaging, thumbnails). Guide/translations: final batch.
- A7: `VideoLayerItem.tracking: VideoMotionTrack` (offset points in item
  seconds), applied by `placed(at:)` (resolved + tracking), which `shown`,
  the handles (drag subtracts the offset) and the hit test use. Track →
  a yellow box on the player (drag; Box size slider) → Start:
  `.edit(.trackMotion(rect))` renders the edit under the clip (tracks from
  its own up left out) at 720p from the playhead to the clip's end, then
  VNTrackObjectRequest; one undo step "Track Motion"; Stop following
  (`.edit(.clearTracking)`). Ships only if VideoMotionTrackingTests pass in
  the final pass and nothing suggests drift; otherwise next update.
- B8: shared Library grid (VideoLibraryItems.swift): `VideoLibraryPayload`
  ("lfstudios-library:kind/id" as plain text) dragged onto the timeline or
  player (VideoMediaDrop takes .plainText) or added with + / double-click;
  `model.placeLibraryItem` dispatches by kind through
  `VideoEditorModel.libraryHandlers` (add a handler per tab). Search
  (`VideoLibraryTile.matching`) and favourites (Settings.
  videoLibraryFavourites; VideoLibraryFavouritesTests is SERIAL) are built
  in, so B15 only needs every tab on the grid. Text tab: 16 templates
  (own designs, macOS fonts, some with In/Out/Combo), 10 styles, Add text,
  and the 1.14 annotation tools in a row.
- B9: `VideoLayerItem.role` (.effect / .adjustment) for clips that aren't
  media or text (`hasFile` false: skipped by Library, handoff, packaging,
  thumbnails, hit test, handles). `effects: [VideoAppliedEffect]` on a
  media/text clip (drawn in VideoLayerRenderer before the mask) or one
  effect on an effect clip, whose strength is `level` (keyed .intensity),
  applied to the scene in drawOutputLayers (main track + tracks under it;
  the camera, captions and annotations draw after). 14 own CI effects
  (VideoEffectRenderer, deterministic random). + → on the selected clip, or
  an effect clip over the selected main clip, or 3 s at the playhead; a
  drop → effect clip there. `.edit(.setEffects)`. Effects tab added to
  VideoLibraryTab (B15 still has to make the tab bar fit 9 tabs).
- B10: VideoTransitionKind + fadeThroughWhite, slide, push, wipe, zoom,
  blur, spin (`usesBothSides` → the held-frame path dissolve already used;
  `isNew` → format 4 via `usesNewTransitions`). VideoTransitionRenderer.
  blend in VideoRenderer.finish. `.clip(.setTransition(kind, length))` (the
  selected clip's cut, or nearest the playhead), `.clip(.transitionEverywhere)`
  (Apply to all: clears per-cut choices), both one step, refused when the
  main track is locked. Library tab with a Length (Settings.
  videoTransitionLength) and hover previews; VideoTransitionPicker grid
  replaces the segmented control in Style and the clip inspector.
- B11: VideoFilterLook ×16 (our formulas baked into 32³ CIColorCube LUTs,
  cached), VideoAppliedFilter (look or imported .cube path + name,
  intensity). `filter` on a media/text clip, or on an adjustment clip
  (role .adjustment, VideoLayerItem.adjustmentClip) = a filter clip; the
  clip's keyed .intensity mixes the result with what's under it.
  `.edit(.setFilter)`, `addFilter` (+ → on the selected clip; drop → filter
  clip). Import .cube: VideoColorCube.parse (3D, DOMAIN_MIN/MAX), copied to
  VideoAssetStore, in assetPaths and project packaging (.data).
  VideoAdjustmentClipSection is a stub for B12's Adjust panel.
