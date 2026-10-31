# Testing for 1.15.0

Every feature added on `capcut-pro`, what its automated tests cover, and
what needs a real check by the owner. Tests are run in the final pass only.

| Feature | Tests (file › what) | Needs a real check by you |
|---|---|---|
| A1 Keyframes | VideoKeyframesTests › easing curves, values between keys, editing at the playhead (key vs base), diamond toggles a group, ⌥K / ◀ ▶, keys through trim and split, keyed opacity in exported pixels, keyed volume in exported sound, format 4 | Drag an item on the player with keys on: it should add a key at the playhead and the motion should look smooth with each easing |
| A2 Blend, Cutout, Masks | VideoItemLookTests › multiply/screen pixels and only where the item is, chroma key takes green out and keeps the subject, every mask shape keeps/hides the right pixels, invert, remove background runs, each edit one undo step, everything starts off, locked track refuses | Remove background on a real person (camera clip): edge quality, and whether playback keeps up; chroma key on a real green-screen clip |
