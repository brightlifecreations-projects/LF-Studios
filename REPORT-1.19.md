# LF Studios 1.19.0: report (unattended run)

Branch `agent` → main. Plan: AGENT-1.19-PLAN.md. Progress: PROGRESS-1.19.md.
Every choice made while you were away: DECISIONS-1.19.md (summarised below).

## What shipped
- **One-time tip** "Tip: drag a panel's top edge to move it": shown once from
  1.19.0, closed with OK or as soon as a panel moves. 7 languages.
- **Unlink Audio / Link Audio for videos on tracks above the main track**:
  right-click the sound under the video; drag it on its own (one ⌘Z step a
  drag). Saved as format 5 only once something is unlinked.
- **Bézier handles on the keyframe curve**: a selected clip's points get
  handles; drag one to bend the curve (one ⌘Z step), double-click to reset,
  choosing an easing clears it. Older keys are written exactly as before.
- **AI agents (MCP)**, off until the user turns it on (Settings ▸ Agent):
  - Copy setup for Claude Desktop, Claude Code, Cursor and Codex. They all
    start the `lfstudios-mcp` bridge inside the app bundle
    (Contents/Helpers, signed with the app), so the setup never changes
    across restarts, port changes or a new token. New token included.
  - Server: 127.0.0.1 only, bearer token, Host and Origin checks (DNS
    rebinding), refuses peers that aren't this Mac.
  - Read tools: project, timeline (tracks, clips, linked/unlinked sound,
    times, locks), media, transcript with word times and fillers, captions,
    markers, keyframes (with handle slopes), a frame as PNG.
  - Edit tools: the editor's commands (split, delete left/right, delete,
    marker, freeze frame, reverse, mirror, rotate, on/off, group, ungroup,
    extract audio, mark in/out, text/arrow/highlight/blur, keyframe, text
    clip, compound, break apart, zoom cut) plus edits with values (caption
    text, remove fillers, clip speed, transitions, unlink/link/move audio,
    item values, keyframes, sound fades, place media), undo/redo, seek and
    select. All go through model.perform; every edit takes `dry_run`;
    locked tracks refuse; files only from the project or its folder; no
    export, no recording, no clipboard.
  - Runs: begin/end_agent_session; one checkpoint per run; the **Agent
    panel** (a fifth movable/floatable panel, both styles) with the goal and
    a live change feed (click to go there); at the end the changed places
    are marked on the timeline and the user chooses **Keep** or **Revert
    all** (one step; ⌘Z brings the changes back). ⌘Z still works step by
    step throughout.
  - Taking over: clicking or typing in the editor (or its floating panels)
    pauses the agent's next edit until **Resume**.
  - **Tacks**: notes/questions pinned to a moment that follow their clip;
    answer or dismiss them in the Agent panel; the agent reads answers.
  - A green dot in the menu bar and in the editor (status strip, or the
    toolbar in CapCut style) shows a connected agent; Disconnect.
  - Settings ▸ Agent ▸ Save… writes an instructions file that is also a
    Claude skill (SKILL.md).
  - Guide: Connect Claude Desktop (step by step), What an agent can and
    can't do, Keep or Revert all, Tacks. All 7 languages.

## Tests
- New: VideoAgentTests (a real HTTP MCP client: connect, read, dry run,
  edit, undo, Revert all, Keep; refused without/with a wrong token, under
  another host name, from a web origin, from this Mac's network address;
  take over and Resume; imports; Tacks; frames; the stdio bridge across a
  new token and a restart), layer Unlink Audio with an export check, curve
  handles, the panel tip, Project118SoundTests (old projects' picture and
  sound against LF Studios 1.18.0's own measurements, 6 kinds of project),
  VideoEditor119SnapshotTests. No real camera or microphone anywhere.
- test-quick after every commit: green.
- test-full: green on the third run (1172 s). The first run failed three
  screen-recording tests because a macOS prompt ("Visual Studio Code is
  requesting to bypass the system private window picker…") was on screen
  over what they record; v1.18.0's code failed them the same way at that
  moment, so it was the screen, not the code. The prompt was gone by the
  second run. That run found a real test problem: the panel and agent tests
  share settings, so they now run one after another (scripts/test-groups.sh).
  The first run also found a real layout problem (six Settings tabs),
  fixed: Settings opens 640 pt wide.
- CI green on the merged commit. Update rehearsal: 1.18.0 updated itself to
  1.19.0 through Check for Updates. Published with 15–16 GB free.

## Links
- Screenshots: https://claude.ai/artifact/5yfmhmTAPM1V9tKNLobGpY
- Release: https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/tag/v1.19.0
- PR: https://github.com/brightlifecreations-projects/LF-Studios/pull/12 (merged)

## Moved to the next update
- Nothing was moved: every planned piece shipped.

## Decisions (DECISIONS-1.19.md, in short)
1. 15 GB free was enough (your answer); stop before publishing under 6 GB.
2. **A bug found and left as it is**: the sound of a video on a track above
   the main track fades from full to nearly silent across the clip (same
   cause as the muted-clip bug fixed in 1.18.0). Not fixed because old
   projects must export identical to 1.18.0. Your call; the fix is known.
3. Disconnect turns the agent connection off (an agent app would otherwise
   reconnect straight away).
4. Tacks live while the project is open; not saved in the project file.
5. Commands left out for agents: anything that opens windows, records,
   uses the clipboard or changes the editor's own switches; no export.
6. The Agent panel shows itself (under Properties) when a run begins.
7. Menu bar: a green dot beside the icon; Disconnect is in the editor's dot
   menu and Settings (the icon's click stays as it is).
8. "Project or its folder" for imports = files already in the project, or in
   the project file's folder (the recording folder for recording projects).
9. An edit without begin_agent_session starts a run on its own.
10. get_frame draws as the export does, without the camera overlay.
11. MCP streamable HTTP answered as plain JSON (no server-sent events).
12. The token lives in app settings and a 0600 file, not the Keychain.

## Please check by hand
1. Connect Claude Desktop for real (Settings ▸ Agent ▸ Copy setup, paste,
   restart Claude) and ask it to make a cut: the dot, the Agent panel, the
   feed, Keep / Revert all. Tests used a test client and the bridge, not
   Claude Desktop itself.
2. Claude Code: `claude mcp add …` from Copy setup, then a request.
3. Click and type in the editor while an agent edits: it pauses; Resume.
4. Decision 2 (the fading sound of videos above the main track).
5. Drag a curve handle on the keyframe curve (a selected clip on a track
   above, LF Studios layout).
6. Right-click the sound under a video on a track above ▸ Unlink Audio,
   drag it, Link Audio.
7. The macOS prompt about Visual Studio Code bypassing the private window
   picker: answer it if it's still pending (it's macOS's periodic check for
   apps that record the screen; the recording tests need it).
