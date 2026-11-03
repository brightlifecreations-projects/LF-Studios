# LF Studios 1.20.0: plan (built-in AI assistant)

Branch `ai-chat` from main (1.19.1). Progress in PROGRESS-1.20.md, choices in
DECISIONS-1.20.md, final report in REPORT-1.20.md.

## Owner's changes to the first plan
1. Model menus and the default list only chat models that support tool
   calling (no image, audio, embedding, moderation… models).
2. OpenAI: the API OpenAI's current docs recommend for tool calling
   (Responses API if that's it), so newer models work.
3. Creative Handoff leaves chat history out by default: an "Include AI chat
   history" switch (off). Tacks stay as they are.

## Commits (test-quick after each)
1. Keys in the Keychain: one item per provider; never in UserDefaults,
   project files, logs, crash reports, handoffs, screenshots or agent
   instructions; errors scrubbed. Tests use a temporary keychain or a
   stand-in store, never the login keychain.
2. Providers: Anthropic Messages, OpenAI (recommended tool-calling API),
   Gemini generateContent; streaming; each one's own tool calling from one
   shared tool list; timeouts and Stop; clear errors (wrong key, no credit,
   rate limit), at most one retry and only when the provider says when;
   model lists from each provider's list API (tool-capable chat models only),
   cached, refreshable, default chosen by a rule; Test key.
3. Settings ▸ AI (next to Agent): per provider paste key, Test key, Remove
   key, Get a key link, model menu; key shown as •••• + last 4; "Send video
   frames to the AI" (off); nothing on until a key and a provider are chosen.
4. Assistant panel (sixth movable/floatable panel, both styles): provider and
   model picker, streaming replies, Stop, New chat, tokens per reply and chat.
5. Edits through the 1.19 MCP tool layer: a request is an agent session
   (feed, checkpoint, Keep / Revert all, Tacks, taking over pauses it);
   frames only when the switch is on. New tools: Auto captions, Remove ums,
   Shorten pauses, Apply My Style (their normal commands); prepare an export
   (preset, size, format, file name, Export window filled in; the user
   clicks Export).
6. Chat history saved in the project only when there is some (new format
   version, like Tacks); keys never in history. Creative Handoff leaves it
   out unless "Include AI chat history" is on (off).
7. Guide pages (getting a key per provider, adding it, what gets sent,
   costs, Keep / Revert all), 7 languages.

## Tests
Local mock servers for all three providers (streaming, tool calls, wrong key,
no credit, rate limit, timeout, Stop, model lists); no real calls or keys.
Keys never in UserDefaults, project files, drafts, logs, exports, handoffs.
Old projects export identical to 1.19.1; no history → written as before.
No real camera or microphone.

## Release
test-full, screenshots page, PR, CI, merge, rehearsal from 1.19.1, publish
only if all pass; stop before publishing under 10 GB free; the release
script cleans up after itself.
