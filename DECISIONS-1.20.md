# LF Studios 1.20.0: decisions

Choices made while building the built-in Assistant, with the reason for each.

1. **OpenAI uses the Responses API.** OpenAI's function-calling guide says
   its newest models (GPT-6 Astra, GPT-6.1 Sol) require the Responses API for
   tool calling (your change 2).
2. **Gemini uses the Interactions API, not generateContent.** Google's docs
   (June 2026) call the Interactions API "our default interface" and
   generateContent "legacy". Same reasoning as OpenAI: the recommended API,
   so newer models work.
3. **Anthropic uses the Messages API with `anthropic-version: 2026-10-21`**,
   no sampling settings (that version rejects them), and
   `eager_input_streaming` on the tools (tool arguments stream as they're
   written; invalid ones go back to the model as an error).
4. **Stateless at every provider.** OpenAI and Gemini get `store: false`;
   the app keeps the conversation and sends it each time, with each
   provider's hidden reasoning (Anthropic thinking signatures, OpenAI
   encrypted reasoning, Gemini thought signatures) sent back exactly as it
   came. Nothing waits at a provider for later.
5. **A saved chat is plain text.** The project keeps what you see (messages,
   what each reply changed, tokens, errors), not the provider's raw
   transcript. A chat continued after reopening, or with another provider
   or model, is sent as plain alternating text. Keeps project files small
   and provider-neutral.
6. **"Test key" asks for the provider's model list.** It proves the key
   works without spending tokens, and fills the model menu at the same
   time.
7. **Model menus: tool-capable chat models only** (your change 1).
   Anthropic: every `claude-` model (all of them call tools). OpenAI: its
   list has only ids, so `gpt-` and `o<digit>` models, without image, audio,
   realtime, transcription, speech, embedding, moderation, search,
   computer-use, codex and older completion models. Gemini: `gemini-` models
   whose methods include generateContent, without image, speech, audio,
   live, embedding, robotics, computer-use and the like.
8. **Default model by rule, never a fixed name:** Anthropic's newest Opus;
   OpenAI's newest full GPT (not mini, nano or cyber); Gemini's newest
   stable Pro; otherwise the newest model in the list.
9. **Nothing is on until you choose.** Adding a key doesn't pick the
   provider; Settings ▸ AI ▸ Provider starts at None. Removing the chosen
   provider's key sets it back to None.
10. **Retries:** at most one, and only when the provider says when to come
    back within 20 seconds (rate limit or busy). A wrong key, no credit or
    any other error is shown at once.
11. **Limits:** a request stops after 30 tool steps (it says so, and asking
    again goes on); 90 seconds without a byte is a timeout; Stop cancels the
    request in flight.
12. **One run per request.** A new request while the last one's changes are
    still waiting keeps them, so each request has its own checkpoint. A
    request that changed nothing leaves nothing to review.
13. **The Assistant shows its run in its own panel** (changes, Keep, Revert
    All, Resume), not the Agent panel. Clicking or typing in the Assistant
    panel isn't taking over; anywhere else in the editor is.
14. **Not while an MCP agent is mid-run** on the same project: the
    Assistant says to wait, rather than mixing two agents' changes into one
    checkpoint.
15. **The new whole-video tools are shared with MCP agents** (one tool
    list): auto_captions, remove_ums, shorten_pauses, apply_my_style and
    prepare_export. prepare_export opens the Export window filled in; only
    the user clicks Export.
16. **The chat history follows the Tacks rules:** saved only when there is
    one (format 7, "requires" 7, opens in 1.20.0 or later), never a ⌘Z
    step, kept by undo and Revert all. New Chat removes it.
17. **Creative Handoff ▸ Include AI chat history** is an option next to
    "Include speaker notes", off by default, and remembered with the other
    handoff options (your change 3).
18. **Keys:** one Keychain item per provider, made by the app (no prompts
    for the same signed app). A test process never touches the login
    keychain: it always uses an in-memory store, and the real Keychain code
    is tested against a throwaway keychain file. Crash reports and error
    messages are scrubbed of anything shaped like a key.
