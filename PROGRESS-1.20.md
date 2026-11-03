# LF Studios 1.20.0: progress

- [x] Branch `ai-chat` from main (1.19.1); plan in AI-1.20-PLAN.md. Free
      space at the start: 36 GB.
- [x] 1. Keys in the Keychain (76f00cd). test-quick: one failure in
      VideoFloatingPanelTests (Space didn't play/pause); it passed on main
      and on this commit when run again: a playback hiccup on this Mac, not
      the change. Watched in later runs.
- [x] 2. Providers, the assistant's engine, the new tools, chat history in
      the project, the handoff option (19d0104).
- [x] 3. Settings ▸ AI and the Assistant panel (d026629). Settings opens
      700 pt wide (seven tabs). Its test-quick stalled for 40 minutes inside
      one export in Project118SoundTests (no CPU, waiting on AVAssetWriter);
      it had passed in every run before. Stopped; covered by the next run.
- [x] 4. Guide pages (AI Assistant category: Edit with the Assistant, Add
      your API key, a page per provider's key, What the Assistant sends, What
      it costs), the 1.20.0 CHANGELOG, the new tools in the MCP instructions,
      7 languages.
- [ ] test-full, screenshots page, PR, CI, merge, rehearsal from 1.19.1,
      publish.
