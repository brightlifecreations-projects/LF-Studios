# LF Studios 1.19.0: progress

Branch `agent`. If context is lost: re-read this file, AGENT-1.19-PLAN.md
and DECISIONS-1.19.md, and continue from the first unticked box. The owner
is away: never ask, decide (DECISIONS-1.19.md) and continue. Publish only
if test-full, CI and the rehearsal pass and >= 6 GB is free. After each
test run delete that run's temp files ($TMPDIR/lfstudios-*).

## Checklist
- [x] 1. One-time panel tip
- [x] 2. Unlink/Link Audio for videos above the main track
- [x] 3. Bézier tangent handles on the curve lane
- [x] 4. MCP server (loopback, token, rebinding) + Settings ▸ Agent + token
- [x] 5. Read tools
- [x] 6. Edit tools + dry_run + locked tracks + imports rule
- [x] 7. Sessions, checkpoints, Keep / Revert all, take over / Resume
- [x] 8. Agent panel (change feed) + Tacks + status dot / Disconnect
- [x] 9. lfstudios-mcp stdio bridge in the bundle + Copy setup + instructions file
- [ ] 10. Guide, translations, CHANGELOG, test-full, screenshots, PR, CI,
      merge, rehearsal, publish, REPORT-1.19.md

## Notes
- 1.2: VideoLayerItem.audioOffset (format 5), own composition track, lane menu + drag. Found: layer video sound fades across its clip (DECISIONS 2), not fixed.
- 1.3: VideoKey inSlope/outSlope (Hermite between keys; nil = from the easing); handles shown for the selected clip; setEasing clears the out slope; format 5 when any is set.
- Agent: VideoAgentServer (NWListener 127.0.0.1, gate: token/Host/Origin/peer), VideoAgentProtocol + VideoAgentTools, VideoAgentHub (runs, checkpoints, take over, tacks), VideoAgentViews (Settings ▸ Agent, dot, panel, timeline marks), VideoAgentInstructions, Sources/lfstudios-mcp (bridge, Contents/Helpers, signed in build-app.sh). VideoAgentTests: 7 tests over real HTTP + the bridge.
- Still to do in 10: Project118 identity test (1.18.0 refs from a worktree), screenshots, test-full, PR, CI, merge, publish.
- Project118SoundTests: 1.18.0's measurements (worktree, LF_PIXEL_RECORD=1) of 6 projects incl. a muted clip and a video above with keys: identical 3/3. VideoEditor119SnapshotTests renders the agent screens.
- test-full green (1172 s) after moving the panel/agent tests to SERIAL; CI green on PR #12. First test-full: a macOS screen-capture prompt covered the recording tests (1.18.0 failed them too then).
