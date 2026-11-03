# LF Studios 1.20.0: report

Branch `ai-chat` → main (PR #14). Plan: AI-1.20-PLAN.md. Progress:
PROGRESS-1.20.md. Every choice: DECISIONS-1.20.md.

## What shipped
- **The Assistant**: an AI chat that edits the open video with the user's
  own API key, for Anthropic (Claude), OpenAI and Google Gemini.
  - Layout ▸ Assistant Panel: a sixth movable/floatable panel in both
    layouts. Provider and model picker at the top, streaming answers, Stop,
    New Chat, what each answer changed, tokens per answer and per chat.
  - Each request is one agent run through the 1.19 tool layer: the change
    list, one checkpoint, Keep / Revert All, Tacks; clicking or typing in
    the editor pauses it until Resume (typing to the Assistant doesn't).
  - New tools (also for MCP agents): Auto captions, Remove Ums, Shorten
    Pauses, Apply My Style through their normal commands, and
    prepare_export, which fills in and opens the Export window. Only the
    user clicks Export.
  - Clear errors for a wrong key, no credit, rate limits, a busy provider
    and timeouts; at most one retry, only when the provider says when.
  - The chat is saved with the project only when there is one (format 7;
    older versions say they need a newer version). Creative Handoff leaves
    it out unless Include AI chat history is on (off).
- **Settings ▸ AI**: per provider paste a key, Test Key, Remove Key, Get a
  key, a model menu from the provider's own list (tool-capable chat models
  only, default by rule). Keys only in the Keychain, shown as dots and the
  last 4 characters. Provider starts at None; Send video frames to the AI
  is off.
- **Network**: straight from the Mac to the provider over HTTPS, using the
  API each provider's docs recommend for tool calling (Anthropic Messages,
  OpenAI Responses, Gemini Interactions), streamed and stateless.
- **Guide**: Edit with the Assistant, Add your API key, Get a Claude /
  OpenAI / Gemini API key, What the Assistant sends, What it costs. 7
  languages.
- **Settings opens 700 pt wide** so its seven tabs keep their size in
  every language.

## Tests
- New: VideoAIAssistantTests (local mock servers for all three providers:
  model lists and filtering, streaming and usage, tool calls through the
  agent tools as one run with each provider's hidden reasoning passed back,
  a new request keeping the last one's changes, wrong key, no credit, rate
  limits with and without retry-after, a stream error, timeout, Stop, taking
  over and Resume, frames only when allowed, nothing on without a key and a
  provider, keys absent from settings, project files, drafts, an export, a
  handoff and the agent instructions, chat saved as format 7 and left out of
  handoffs), VideoAIKeysTests (the real Keychain code against a throwaway
  keychain; test processes never touch the login keychain),
  VideoEditor120SnapshotTests. No real provider, no real key, no camera or
  microphone.
- test-quick after each commit. Three runs had one miss each, none from
  the change: a playback hiccup (passed when re-run), a 40-minute stall
  inside one export (stopped; passed in the next run), and two speed limits
  missed while another app (SRT Generator) used about four CPU cores; main
  missed them too at that moment. test-full waited until it was quiet.
- test-full: green on the first run (1441 s). CI green on the PR.
- Update rehearsal: 1.19.1 updated itself to 1.20.0 through Check for
  Updates and opened again. Published with 38–39 GB free; the release
  script deleted its build files (779 MB).

## Links
- Release: https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases/tag/v1.20.0
- Screenshots: https://claude.ai/artifact/CUyN7rwQWT36L6W4NXez4a
- PR: https://github.com/brightlifecreations-projects/LF-Studios/pull/14 (merged)

## Moved to the next update
- Nothing: every planned piece shipped.

## Decisions (DECISIONS-1.20.md, in short)
1. OpenAI: the Responses API (its docs say the newest models need it for tools).
2. Gemini: the Interactions API (Google's docs now call generateContent legacy).
3. Anthropic: Messages API, version 2026-10-21, no sampling settings.
4. Stateless everywhere (store: false); hidden reasoning sent back unchanged.
5. A saved chat is plain text; a continued chat is resent as text.
6. Test Key asks for the model list (no tokens spent).
7. Model menus: tool-capable chat models only (rules per provider).
8. Default model by rule: newest Opus / newest full GPT / newest stable Gemini Pro.
9. Nothing on until a key is added and a provider chosen.
10. At most one retry, only when the provider says when (≤ 20 s).
11. 30 tool steps per request at most; 90 s without a byte is a timeout.
12. One run per request; a new request keeps the last one's changes.
13. The Assistant shows its run in its own panel; typing to it isn't taking over.
14. Not while an MCP agent is mid-run on the same project.
15. The new whole-video tools are shared with MCP agents.
16. Chat history follows the Tacks rules (format 7, not ⌘Z steps).
17. Handoff ▸ Include AI chat history sits with the other handoff options, off.
18. One Keychain item per provider; tests never touch the login keychain.

## Please check by hand (with real keys; tests used mock servers only)
1. **Each provider for real**: Settings ▸ AI ▸ paste a key ▸ Save ▸ Test
   Key; check the model menu lists sensible models, then ask for a small
   edit in the Assistant. Gemini's Interactions API and OpenAI's Responses
   API were built from their current docs and tested against mocks of those
   formats, so a first real run of each matters most.
2. **No Keychain prompts**: after saving a key, quit and reopen LF Studios
   and send a request. macOS shouldn't ask for the Keychain.
3. **Frames on**: turn on Send video frames to the AI and ask "what's on
   screen at 0:05?".
4. **Auto captions through the Assistant**: the first time, macOS may ask
   for Speech Recognition, as the button does.
5. **Take over**: click in the timeline while it works; Resume.
6. **Costs**: compare the tokens the panel shows with the provider's usage
   page.
