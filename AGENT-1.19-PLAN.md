# LF Studios 1.19.0: plan (unattended run)

Branch `agent` from main (1.18.0). Progress in PROGRESS-1.19.md, choices in
DECISIONS-1.19.md, final report in REPORT-1.19.md.

## Part 1: leftovers (one commit each)
1. One-time tip "Tip: drag a panel's top edge to move it", the first time
   the editor opens in 1.19.0; dismissable; 7 languages; remembered per Mac.
2. Unlink / Link Audio for videos on tracks above the main track: a layer
   item's `audioOffset` (format 5 already exists), its sound on its own
   composition track, moved; the layer sound lane gets the same menu and
   drag as the main track's.
3. Bézier tangent handles on the keyframe curve lane: a key's in/out
   tangents (optional fields; old projects unchanged), drawn as handles,
   one ⌘Z step per drag; interpolation uses them only when set.

## Part 2: AI agent connection (MCP)
- Settings ▸ Agent: "Allow AI agents to edit" (off). When on: Copy setup
  for Claude Desktop / Claude Code / Cursor / Codex, New token, the agent
  instructions file.
- Server in the app (Network.framework, HTTP on 127.0.0.1 only, random
  port written to Application Support with the token): JSON-RPC MCP over
  "streamable HTTP" (POST /mcp). Bearer token, Host/Origin checks
  (DNS rebinding), refuses non-loopback peers.
- `lfstudios-mcp` stdio bridge (a small Swift executable in the bundle,
  signed with it): reads port + token from the file each request, so its
  config never changes.
- Tools: read (project, timeline, media, transcript, captions, markers,
  keyframes, frame image) and edit (one per VideoEditCommand through
  model.perform, dry_run on each, refused on locked tracks), imports only
  from files in the project or its folder, no export.
- Sessions: begin/end_agent_session; one checkpoint per run; Keep /
  Revert all at the end with changed places marked; the user typing or
  clicking pauses the agent until Resume.
- Agent panel (a fifth movable panel): live change feed, click to jump;
  Tacks (notes/questions at a moment, follow their clip, answer/dismiss).
- Status: a dot in the menu bar and status strip with Disconnect.
- Guide pages, 7 languages, tests (a test MCP client over real HTTP),
  screenshots page, PR, CI, merge, rehearsal from 1.18.0, publish.

## Rules kept
Manual-only (off by default), L() in 7 languages, VideoEditCommand for
every edit, test-quick after each commit, test-full at the end, publish
only if test-full + CI + rehearsal pass and disk >= 6 GB free. Clean each
test run's temp files after it.
