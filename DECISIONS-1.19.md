# LF Studios 1.19.0: decisions made while the owner was away

Each one: the choice, and why (the safer, simpler option within the rules).

1. **15 GB free is enough** (owner's answer in the preflight). Stop before
   publishing if it drops under 6 GB.

2. **A found bug left as it is: the sound of a video on a track above the
   main track fades from full to nearly silent across the clip** (measured:
   0.31 RMS at its start, 0.06 at its end). Same cause as the muted-clip bug
   fixed in 1.18.0 (a lone volume point blends into the next one). Not fixed
   here because the rules say old projects must export identical to 1.18.0;
   fixing it changes the sound of every project with such a video. Unlinked
   sound (new in 1.19.0) uses the same mix, so linked and unlinked sound the
   same. **Owner to decide**: the fix is the 1.18.0 one (hold each item's
   level with a ramp over its length), in VideoLayerInput.apply.

3. **Disconnect turns the agent connection off** (the Settings switch goes
   off). Safer than only dropping the session: an agent app reconnects on
   its own, so a "disconnect" that lets it straight back in isn't one.
4. **Tacks live while the project is open; they aren't saved in the project
   file.** They're a conversation with the agent, not part of the edit, and
   keeping them out of the file keeps old/new project files identical.
5. **Commands an agent can't use:** the ones that open windows or sheets
   (crop, project settings, review fillers, compound open/close, shortcuts),
   record (voiceover: never the microphone), use the clipboard (copy/paste),
   or change the editor's own switches (magnet, snapping, linkage, preview
   axis, zoom to fit, tools). Export isn't a tool.
6. **The Agent panel is a fifth movable panel, shown (docked under
   Properties) when an agent run begins**, hidden by its × or Layout ▸ Agent
   Panel. Showing it changes the arrangement, so the editor then draws
   panels with headers. Only happens after the user turned agents on.
7. **The menu-bar dot is a green dot beside the icon; Disconnect is in the
   editor's dot menu and Settings ▸ Agent.** The menu-bar icon opens the
   command center today; adding a menu there would change that.
8. **"The project or its folder" for imports** = files already in the
   project (the Library and timeline), or inside the folder of the project
   file (or of the recording, for a recording folder). Nothing else.
9. **An edit without begin_agent_session starts a run on its own**, so every
   change is in the feed and Keep / Revert all always has a checkpoint.
10. **get_frame draws the frame as the export does, without the camera** (the
    camera needs its own video reader; out of scope for a still).
11. **Transport: MCP streamable HTTP answered as plain JSON (no server-sent
    events).** Simplest that every client and the bridge handle.
12. **The token is kept in the app's settings and a 0600 file, not the
    Keychain**: no Keychain prompts, and the bridge can read it without one.
