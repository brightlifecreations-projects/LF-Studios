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
- [x] B12 Adjustment tab: adjustment layer; full Adjust panel (HSL, curves, wheels, .cube import)
- [x] B13 Stickers and sound effects (own/CC0, LICENSES.md), Import sticker (PNG/GIF)
- [x] B14 Captions tab: auto captions, style templates, SRT import/export
- [x] B15 Show Stickers/Effects/Filters/Adjustment tabs; favourites and search in every tab

## Part C: pro tools and export
- [x] C16 Keyboard shortcuts editor with presets, conflicts, reset
- [x] C17 Proxy mode (ProRes Proxy, half res, estimate first)
- [x] C18 Compound clips: make, break apart, open in own timeline
- [x] C19 Export window (CapCut structure)
- [x] C20 Cover frame/image embedded in the export
- [x] C21 Performance: background rendering, thumbnail/waveform cache, 30-min synthetic project

## Final pass
- [ ] Work through TESTING-LATER.md
- [ ] test-quick green
- [ ] test-full green
- [ ] Old projects (.lfs, .lfsp, .lfstudios, .shotstyle) pixel-identical to 1.14.0
- [ ] Screenshots page (light/dark, en/de, 1920×1200 and 13")
- [ ] CHANGELOG (dated), merge, publish 1.15.0

## Next update (moved out, with why)
- Compound clips: "open in its own timeline". The timeline, its lanes,
  selection and every edit command work on the project's own tracks;
  showing and editing another set of tracks safely means threading a
  "which timeline" through all of them. 1.15.0 ships make, break apart,
  and move/size/turn/fade as one; to change a clip inside, break it apart
  and make it again.

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
- B12: VideoAdjustSettings (14 sliders, HSL ×8, curves RGB/R/G/B with
  monotone interpolation, wheels lift/gamma/gain/offset) on any clip above
  the main track or an adjustment clip. All colour work is baked into a 33³
  LUT cached per settings (VideoAdjustRenderer), sharpen/vignette/grain run
  after. Properties ▸ Adjust (Basic/HSL/Curves/Wheels, Reset);
  `.edit(.setAdjust)` (neutral → nil). Library ▸ Adjust: Adjustment clip +
  9 own presets (+ → on the selected clip; drop → adjustment clip). .cube
  import came with B11. Main-track clips get Adjust through an adjustment
  clip over them (+ with the clip selected).
- B13: VideoSticker ×28 drawn in Core Graphics (no symbols/art files),
  `sticker` on VideoLayerItem (no file), cached by height. Animated GIFs:
  VideoGIF (frames + delays, loops) for any .gif picture clip. Import
  sticker = PNG/GIF through placeMedia. VideoSoundEffect ×17 synthesised in
  code into SoundEffects/v1-<id>/<Title>.caf, added with addAudio (copied
  to the store), hover plays them. Audio tab: Your sounds | Sound effects.
  LICENSES.md (repo root) lists stickers, sounds, looks, templates and the
  macOS fonts; VideoStickersSoundsTests checks it stays in step.
- B14: Library ▸ Captions: Auto captions (the existing generateCaptions,
  Apple or Whisper), Import .srt/.vtt (VideoSubtitleImport → source-clock
  lines with even word timings, replaces captions and translations, one
  step "Import Captions"), Export .srt (existing), 12 caption templates
  (VideoCaptionTemplate: look + macOS font + highlight + animation + size +
  position, one step "Caption Style"), previews by the real renderer.
- B15: VideoLibraryTab in CapCut order (media, audio, text, stickers,
  effects, transitions, captions, filters, adjustment) on an adaptive grid
  (two rows when narrow). Every non-media tab is on VideoLibraryGrid
  (search + favourites); Media/Your sounds keep their search and gain a
  favourites filter + stars (payload "media/<path>"). Library snapshots need
  re-recording in the final pass.
- C16: VideoKeymap (preset + custom, JSON in Settings.videoKeymap, cached;
  .lfstudiosKeymapChanged). VideoEditCommand.command(key:) and `.keys` read
  it (undo/redo/delete stay); `standardKeys` keeps LF Studios' own. Presets
  LF Studios / Final Cut Pro style / Premiere Pro style change only
  commands LF Studios has. Conflicts: reserved (Space, ⌘Z, ⌘K, ⌘E, ⌘W, ⌘S,
  ⌘Q, ?) refuse; another command loses the key; editor keys (J K L Z M C
  1–5 ⌘D ⌘F ⇧⌘Y) are taken over with a warning. Keyboard Shortcuts sheet ▸
  Customize… (VideoShortcutsEditor; model.recordingShortcut gets the next
  key in handleKey). The Timeline menu follows the keymap.
  VideoKeymapSettingsTests is SERIAL.
- C17: VideoProxies (ProRes 422 Proxy, half size, picture only, same
  transform; LF Studios/VideoProxies/<sha of path+size+date>-half.mov).
  Player bar ▸ Proxy menu: Edit with Proxies (Settings.
  videoEditWithProxies) and Create Proxies… (estimate in an alert first;
  VideoProxyJob progress; stop). The preview swaps only the picture track
  (`VideoProxies.swapping`, playback.replaceSource/originalSource) for the
  main recording, added recordings (VideoSourceLayout.load(proxies:)) and
  videos above the main track (VideoProxies.layerFile); exports and stills
  never look. Never in a project, so never in handoff/Include media. Clean
  Up: `Plan.proxies` (all, any age), editors fall back to originals.
- C18: VideoCompoundClip (name, x, y, scale, rotation, opacity) in
  project.compounds; its clips stay on their tracks with `group` = its id
  (so moving/deleting work as for groups). The renderer, hit test and
  handles apply `compound.apply(to:canvas:)` after the clip's own look.
  Timeline: one block (VideoCompoundBlock) on the earliest clip's track,
  moved in time only. `.makeCompound` (⌥G) / `.breakApart` (⌥⇧G, bakes
  the look in). Properties ▸ Compound clip. Open in own timeline → next
  update.
- C19: export window in CapCut's order: Name, Export to (folder, Choose…;
  Settings.videoExportFolder), Video | Audio only | GIF, Resolution (to 4K),
  Bit rate (Lower/Recommended/Higher = quality web/social/studio, Custom
  Mbit/s → customBitrate), Codec (H.264, HEVC, ProRes 422/HQ/4444), Format
  (MP4/MOV container; ProRes forces MOV; `movieFileType`), Frame rate
  24/25/30/50/60; captions .srt/.vtt, chapters, end card, range, Copy and
  Creative Handoff kept; Export all ratios still in the ratio menu. Export
  no longer opens a save panel: exportDestination (Replace/Keep Both).
- C20: project.cover (VideoCover: timeline time or a stored picture;
  format 4; in assetPaths and packaging). Export window ▸ Cover: None / A
  frame (the playhead) / A picture. After a movie is written,
  VideoCoverEmbedder takes the frame from the finished file (range offset
  applied) or the picture, and adds it as artwork (iTunes cover art for
  MP4, QuickTime artwork for MOV, plus the common artwork key) with a
  pass-through AVAssetExportSession (no re-encoding). A failure is a
  warning, not a failed export.
- C21: VideoTimelineCache (filmstrip + waveform on disk, keyed by path +
  size + date; Clean Up lists them). VideoRenderWarmup makes the next 8 s
  of text/sticker images, adjust/filter LUTs, pictures and GIF frames on a
  background queue (on seek and after each edit). Budget test
  VideoLongProjectPerformanceTests (SERIAL): 30-min synthetic media, 60
  clips with dissolves, 420 clips on 4 tracks.
