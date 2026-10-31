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
- [ ] A3 Animation: In / Out / Combo presets with duration
- [ ] A4 Speed: Normal 0.1×–100× (keep pitch) and Curve presets + custom curve
- [ ] A5 Audio: volume keyframes, fades, normalize, Detect beats
- [ ] A6 Text on its own track: font, size, B/I/U, colour, stroke, background, shadow, spacing, alignment
- [ ] A7 Motion tracking (Track button, Vision object tracking)

## Part B: Library content
- [ ] B8 Text tab: templates and styles, hover preview, drag onto timeline
- [ ] B9 Effects tab: Core Image effects with intensity, on a clip or as an effect clip
- [ ] B10 Transitions tab: dissolve, fade black/white, slide, push, wipe, zoom, blur, spin; duration; Apply to all
- [ ] B11 Filters tab: own LUT looks with intensity
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
