# Agent tools

Generated from the code by VideoAgentLimitsTests (`LF_AGENT_DOCS_RECORD=1` rewrites it). The same tools serve MCP agents and the built-in Assistant (every provider); both go through `VideoAgentProtocol.call`.

## Hard limits

Enforced in the tool layer (`VideoAgentLimits`), not by instructions: no tool does these, a tool whose name offers one is refused before it runs, and any file argument must be media already in the open project. Nothing an agent sends or reads can switch them off.

1. Never read, list, export or reveal API keys, tokens or the Workspace ID, and never change AI or agent settings or your own permissions.
2. Never record anything: no screen recording, camera, microphone, screenshots or voiceover.
3. Never delete a project, a recording folder or any file on disk. Removing clips from the timeline is fine: it's undoable.
4. Never export anything and never open or import a file: work only inside the open project, with media already in it. prepare_export only fills in the Export window; the user clicks Export.

## Tools (68)

| Tool | Reads only | What it does | Arguments |
|---|---|---|---|
| `get_project` | yes | The open project: name, length, frame size and rate, the playhead, what's selected, and whether an agent run is going. |  |
| `get_timeline` | yes | Every track top to bottom with what's on it, in timeline seconds: captions, zooms, tracks above the main track (items, their sound and whether it's linked), the main track's clips (source range, speed, muted, linked or unlinked sound), added sound and music, and which tracks are locked or hidden. |  |
| `list_media` | yes | The project's media (Library): recordings, camera, music, sounds, pictures and imported files, with their paths. Only these can be placed. |  |
| `get_transcript` | yes | What's said, word by word, with each word's timeline start and end (words cut out of the video are left out), and which words are fillers (um, uh). Word indexes are what remove_fillers takes. |  |
| `get_captions` | yes | The captions with ids, timeline start and end, and text. |  |
| `get_markers` | yes | The markers, by name and timeline time. |  |
| `get_keyframes` | yes | Keyframes of the items above the main track: for each animated setting, its keys (seconds from the item's start and on the timeline, value, easing, curve handle slopes). | `item_id` |
| `get_frame` | yes | A picture of the video at a timeline time, as it exports (640 wide). | `time`* |
| `begin_agent_session` |  | Start a run: everything you change from now on is grouped, shown to the user in the Agent panel's feed, and at the end they choose Keep or Revert all. Say what you're about to do in `goal`. | `goal` |
| `end_agent_session` |  | End the run: the user sees what changed, marked on the timeline, and chooses Keep or Revert all. Summarize what you did in `summary`. | `summary` |
| `seek` |  | Move the playhead to a timeline time (commands like split act there). | `time`* |
| `select` |  | Select something by its id from get_timeline or get_captions (kind: clip, item, caption, zoom), or nothing. | `id`, `kind`* |
| `undo` |  | Undo the last change (the user's or yours), like ⌘Z. |  |
| `redo` |  | Redo what was undone, like ⇧⌘Z. |  |
| `split` |  | Split (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `split_all_tracks` |  | Split all tracks (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `delete_left` |  | Delete left (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `delete_right` |  | Delete right (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `delete` |  | Delete (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `add_marker` |  | Add marker (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `freeze_frame` |  | Freeze frame (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `reverse` |  | Reverse (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `mirror` |  | Mirror (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `rotate` |  | Rotate (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `toggle_enabled` |  | Turn clip on or off (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `group` |  | Group (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `ungroup` |  | Ungroup (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `extract_audio` |  | Extract Audio (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `mark_in` |  | Mark in (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `mark_out` |  | Mark out (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `add_text` |  | Text (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `add_arrow` |  | Arrow (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `add_highlight` |  | Highlight (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `add_blur` |  | Blur (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `add_keyframe` |  | Add keyframe (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `add_text_clip` |  | Text clip (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `make_compound` |  | Make compound clip (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `break_apart` |  | Break apart (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `zoom_cut` |  | Zoom cut (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `duplicate` |  | Duplicate (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `delete_gaps_after_playhead` |  | Delete Gaps After Playhead (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `toggle_loop_playback` |  | Loop playback (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `reveal_in_library` |  | Reveal in Library (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `match_frame` |  | Match Frame (as in the editor). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first. | `id`, `kind`, `time` |
| `set_caption_text` |  | Change a caption's words. | `caption_id`*, `text`* |
| `remove_fillers` |  | Cut out filler words (um, uh) by their indexes from get_transcript. | `indexes`* |
| `set_clip_speed` |  | A main-track clip's speed (0.1 to 100; 1 is normal). | `clip_id`*, `speed`* |
| `set_transition` |  | A transition at the start of a main-track clip (its cut), or `everywhere` on every cut. | `clip_id`, `everywhere`, `length`, `transition`* |
| `unlink_audio` |  | Separate a video's sound from its picture so it can move on its own (a main-track clip or an item above). | `id`*, `kind`* |
| `link_audio` |  | Put unlinked sound back with its picture. | `id`*, `kind`* |
| `move_audio` |  | Move unlinked sound: seconds after its picture (negative: before). | `id`*, `kind`*, `offset`* |
| `set_item_value` |  | A setting of an item above the main track, at the playhead (a key there when it's animated): opacity, width, rotation, x, y, volume, intensity. | `item_id`*, `property`*, `time`, `value`* |
| `toggle_keyframe` |  | Add (or remove) a keyframe of an item's setting at the playhead. | `item_id`*, `property`*, `time` |
| `set_sound_fades` |  | Fade an item's sound in and out at its ends (seconds). | `fade_in`, `fade_out`, `item_id`* |
| `place_media` |  | Put a file on the timeline at a time: only media already in the project (list_media). Anything else is refused. | `path`*, `time`, `where` |
| `delete_gap` |  | Close the empty stretch at `time` on a track above the main track or an added sound track: what comes after it moves back. | `time`*, `track`* |
| `paste_attributes` |  | Copy attributes from one clip onto others (like Paste Attributes): effects, filters, adjust, speed, volume, transform, animation. Main-track clips take only speed, volume and transform. | `attributes`*, `from_id`*, `to_ids`* |
| `roll_cut` |  | Roll the cut at the end of a clip by `by` seconds (+ later, − earlier): this clip and the next one both change; the video keeps its length. Main track, or two touching clips above it. | `by`*, `clip_id`* |
| `slide_clip` |  | Slide a clip by `by` seconds between its neighbours: it keeps its frames; the clip before gets longer and the one after shorter (or the other way). | `by`*, `clip_id`* |
| `solo_track` |  | Solo a track on or off: while any track is soloed only soloed tracks are heard in the editor. The export always has every track. | `track`* |
| `rename_track` |  | Give a track its own name (an empty name goes back to the usual one). | `name`*, `track`* |
| `auto_captions` |  | Transcribe the narration on this Mac and lay it out as captions (the editor's Auto Captions). Takes a while on long videos; it answers when the captions are in. |  |
| `remove_ums` |  | Cut every filler word (um, uh) out of the video (the editor's Remove Ums). Needs a transcript: run auto_captions first. |  |
| `shorten_pauses` |  | Shorten every long pause in the video (the editor's Shorten Pauses). |  |
| `apply_my_style` |  | Apply the user's My Style preset to the video (background, frame, cursor, zoom, captions, keys and camera bubble). |  |
| `prepare_export` | yes | Fill in the Export window and open it. It doesn't export: the user checks it and clicks Export. Leave out what the user didn't ask for. | `file_name`, `format`, `fps`, `preset`, `resolution` |
| `add_tack` |  | Pin a note or a question for the user to a moment (it follows its clip). Use it to explain a choice or ask before something you're unsure of. The user answers in the Agent panel; read answers with list_tacks. | `item_id`, `question`, `text`*, `time`* |
| `list_tacks` | yes | The project's notes and questions (yours, and any left in earlier sessions: they're saved with the project), where they are now, and the user's answers (or that they dismissed them). |  |

`*` required. Every tool that changes the project also takes `dry_run`.
