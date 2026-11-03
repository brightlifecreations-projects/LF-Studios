# LF Studios 1.21.0: decisions

Choices made while building 1.21.0, with the reason for each. "Already
there" notes say what existed and what was fixed or finished instead of
rebuilt.

1. **"Loop playback"** is the new feature's name everywhere (menu, tooltip,
   Guide, shortcuts, 7 languages), so it isn't confused with the cursor's
   Loop switch in the Inspector (owner's change).
2. **Renamed tracks and solo are saved only when used**, under the Tacks rule
   (a newer format that older versions refuse); other projects are untouched.
   Solo is for listening: the export always has every track.
3. **Recording bar (already there: the strip and the upper row).** The
   frame strip window and the bar's upper row (microphone menu, camera
   shape / Select size / Layout, Window size) became the Area popover; the
   same controls, moved, not rebuilt. What the request called "the display
   menu" is the microphone menu (it shows names like "Studio Display
   Microphone"). Full screen shows "Full screen"; Window shows "Window ·
   <app>" (pixels in the tooltip).
4. **The skimmer (already there: the preview axis).** It now also anchors
   zooming and ⌘B / ⇧⌘B, only while the preview axis is on, the pointer is
   over the lanes and nothing plays. The zoom slider and buttons sit away
   from the timeline, so they zoom around the playhead. The menu item is
   "Split at Skimmer or Playhead"; the status strip says which it will be.
5. **Vertical scroll (already there for the lanes).** Fixed: a scroll over
   the track headers now moves the lanes (the headers follow), and a slim
   scroll bar shows whenever the tracks don't fit (the system's overlay one
   only flashed while scrolling).
6. **Box selection** selects the main track's clips and the clips above it.
   A plain click on empty space still moves the playhead; dragging there no
   longer scrubs (the ruler still does). ⇧-drag there adds to the selection
   (as asked); ⇧-drag across clips or the ruler still marks a part to cut.
7. **Gaps** exist only on tracks above the main track and on free sound
   tracks (the main track closes up by itself). A sound track synced to the
   recording follows its cuts and isn't changed.
8. **Duplicate (already there for zooms and annotations).** ⌘D now goes
   through one command for everything. **Main-track clips aren't
   duplicated**: they are the recording itself, each moment once, and about
   35 places (zooms, captions, annotations, the transcript) map recording
   time to timeline time assuming that. The editor says to copy the part to
   a track above instead.
9. **⌥-drag copies; slip moved to the Trim tool.** ⌥-drag used to slip a
   video above the main track. To give ⌥-drag to copying (as asked, and as
   Final Cut Pro does), slipping moved to the new Trim tool (T): drag =
   slide, ⌥-drag = slip, a cut = roll, an end = ripple (as before).
10. **Slide on the main track** can only use parts of the recording that
    were cut out: two clips there never share frames. Right after a split
    there's nothing to slide into, and the editor says so. Above the main
    track, sliding is free (touching neighbours give way).
11. **Paste attributes:** ⌘C remembers the lead clip; ⇧⌘V opens the sheet
    with what that clip has set already ticked. Main-track clips take Speed,
    Volume and Transform (mirror and turns); between a main-track clip and a
    clip above, Speed and mirror.
12. **Loop playback** is session-only (off in every new window), never in
    the project.
13. **Solo** lives with the track's other switches (saved, format 8); it's
    applied only to what the player hears (forListening); the export uses
    forOutput() as before. A video track and its sound row, and the main
    track and its sound rows, count as one for solo.
14. **Track names**: the user's name wins everywhere a track is named; an
    empty name, or the usual name typed back, clears it.
15. **Meters** listen through a tap on the player's audio mix only (each
    sound track, post-volume); the export never gets one. Levels in dB
    (−60…0), green to −12, yellow to −3, red above.
16. **Social overlays** are approximations of where TikTok, Reels and
    Shorts put their buttons and captions (the apps don't publish sizes),
    and only for 9:16 (or narrower) videos.
17. **Match Frame** opens a small viewer (the file at that frame, Show in
    Finder) and selects the file in the Library; Reveal in Library is ⇧F
    (it was free).
18. **Workspace ID** is stored in Settings (an ID, not a secret); it's sent
    only to Anthropic, only when set. Anthropic's exact wording when it
    needs one isn't documented here, so a 400/403 from Anthropic that
    mentions a workspace becomes the clear message.
