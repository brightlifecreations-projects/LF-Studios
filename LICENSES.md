# Library content: where it comes from and how it may be used

Everything in the video editor's Library (1.15.0 and later) is listed here.
LF Studios ships no stickers, sounds, fonts, looks or templates made by
anyone else. Third-party code and the one bundled outside sound are in
THIRD_PARTY_NOTICES.md.

Anything a user makes with these may be used anywhere (videos, ads,
streams), without credit.

## Stickers

- What: 28 stickers (Star, Heart, Sparkle, Burst, Speech and Thought
  bubbles, Arrow, Curved arrow, Tick, Cross, Warning, Question, Lightning,
  Sun, Cloud, Smile, Laugh, Surprised, Music note, Flame, Like, Follow, New
  badge, Circle scribble, Underline, Confetti, 100, Map pin).
- Made by: LF Studios. Drawn in code with Core Graphics
  (`Sources/LFStudiosCore/Video/VideoStickers.swift`); no image files, no SF
  Symbols, no outside artwork.
- License: part of LF Studios (MIT License, see LICENSE).
- Words on stickers (WOW!, LIKE, FOLLOW, NEW, 100) are set in fonts that
  come with macOS (see Fonts).

## Sound effects

- What: 17 sounds (Whoosh, Riser, Pop, Click, Ding, Success, Error,
  Notification, Boom, Kick drum, Clap, Camera shutter, Typing, Coin, Zap,
  Heartbeat, Clock tick).
- Made by: LF Studios. Synthesised in code from sine waves, square waves and
  noise (`Sources/LFStudiosCore/Video/VideoSoundEffects.swift`); no
  recordings or samples from anyone else. The files are made on the user's
  Mac the first time a sound is used.
- License: part of LF Studios (MIT License, see LICENSE). Equivalent to CC0
  for anything made with them.

## Filters, adjustments, effects, transitions

- What: 16 filter looks, 9 ready-made adjustments, 14 effects, 10
  transitions.
- Made by: LF Studios. Colour formulas baked into LUTs on the Mac, and Core
  Image filters that come with macOS
  (`VideoFilters.swift`, `VideoAdjust.swift`, `VideoEffects.swift`,
  `VideoTransitionLibrary.swift`). No LUT files from anyone else are
  shipped; `.cube` files a user imports stay theirs.
- License: part of LF Studios (MIT License, see LICENSE).

## Text templates and styles

- What: 16 templates and 10 styles.
- Made by: LF Studios (`VideoTextTemplates.swift`).
- License: part of LF Studios (MIT License, see LICENSE).

## Fonts

LF Studios bundles no fonts. Text clips, templates and stickers use only
these fonts, which come with every copy of macOS 13 and later and are
licensed by Apple to the Mac's user:

- Helvetica Neue
- Avenir Next
- Futura
- Gill Sans
- Optima
- Georgia
- Baskerville
- Didot
- American Typewriter
- Menlo
- Rockwell
- Impact
- Marker Felt
- Chalkboard SE
- Noteworthy
- Copperplate

The list is `VideoTextFonts.families`; a project never asks for a font a
user happens to have installed (any other name falls back to Helvetica
Neue). If OFL fonts are ever bundled, each goes here with its copyright,
the SIL Open Font License 1.1 text, and where it came from.
