# Testing for 1.15.0

Every feature added on `capcut-pro`, what its automated tests cover, and
what needs a real check by the owner. Tests are run in the final pass only.

| Feature | Tests (file › what) | Needs a real check by you |
|---|---|---|
| A1 Keyframes | VideoKeyframesTests › easing curves, values between keys, editing at the playhead (key vs base), diamond toggles a group, ⌥K / ◀ ▶, keys through trim and split, keyed opacity in exported pixels, keyed volume in exported sound, format 4 | Drag an item on the player with keys on: it should add a key at the playhead and the motion should look smooth with each easing |
