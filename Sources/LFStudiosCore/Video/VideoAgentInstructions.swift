import AppKit
import UniformTypeIdentifiers

/// What an agent is told about LF Studios: a short version when it
/// connects, and a whole guide (a Claude skill) from Settings ▸ Agent.
enum VideoAgentInstructions {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.19.0"
    }

    /// Sent when an agent connects (MCP initialize's instructions).
    static let short = """
    LF Studios is a Mac video editor. You edit the project open in its front window, with the editor's own commands; the user watches every change in the Agent panel and chooses Keep or Revert all at the end. Start with begin_agent_session (say your goal), read with get_timeline / get_transcript / get_captions / get_frame, check risky edits with dry_run: true, and finish with end_agent_session. Times are timeline seconds. Commands act at the playhead and on the selection (pass time, kind and id). If the user takes over, edits are refused until they click Resume: leave a Tack (add_tack) to ask. You can't export, record, or use files outside the project and its folder.
    """

    /// The whole guide (also a Claude skill: SKILL.md with its header).
    static let guide = """
    ---
    name: lfstudios-editing
    description: Edit videos in LF Studios (a Mac video editor) through its MCP tools - read the timeline, transcript and frames, cut, trim, caption, add titles and keyframes, with dry runs and a reviewable run the user keeps or reverts.
    ---

    # Editing in LF Studios

    LF Studios edits screen recordings and other videos on the user's Mac. You
    connect through its MCP server (the `lfstudios` tools). You work on the
    project open in its front window. The user sees each change you make in
    the Agent panel and on the timeline, and decides at the end.

    ## A run
    1. `begin_agent_session` with a one-sentence `goal` the user will read.
    2. Read before you change: `get_project`, `get_timeline`, `get_transcript`
       (word times), `get_captions`, `get_markers`, `get_keyframes`, and
       `get_frame` to look at a moment.
    3. Edit. Pass `dry_run: true` first when you're not sure what a command
       will do: it says what would change and changes nothing.
    4. `end_agent_session` with a short `summary`. The user then sees every
       place you changed marked on the timeline and chooses **Keep** or
       **Revert all**. Each change also undoes on its own with ⌘Z.

    ## How commands work
    - Times are timeline seconds (after cuts), from `get_timeline`.
    - The editor's commands (`split`, `delete_left`, `delete_right`,
      `delete`, `freeze_frame`, `add_marker`, `zoom_cut`, `add_text`…) act at
      the playhead and on the selection, like the keys in the app. Pass
      `time` to move the playhead first, and `kind` + `id` to select first.
    - `seek` and `select` move the playhead and pick something without
      changing the project.
    - `undo` / `redo` step back and forward one change.
    - Locked tracks refuse changes: ask the user (a Tack) instead.

    ## Sound
    - A video's sound sits on its own track under it and stays linked: trims,
      splits, moves and deletes carry it along.
    - `unlink_audio` lets it move on its own (`move_audio`, seconds after its
      picture); `link_audio` puts it back.

    ## Captions and words
    - `get_transcript` lists every word with its time and whether it's a
      filler (um, uh). `remove_fillers` cuts fillers by index.
    - `set_caption_text` fixes a caption's words.

    ## Files
    - `list_media` shows what's in the project. `place_media` puts one of those,
      or a file in the project's folder, on the timeline. Anything else is
      refused: ask the user to add it to the Library first.
    - Exporting is the user's: never try to export.

    ## The user is in charge
    - If the user clicks or types in the editor, your next edit is refused
      until they click Resume. Keep reading, and leave a Tack if you need them.
    - `add_tack` pins a note or a question (`question: true`) to a moment; it
      follows its clip. Tacks are saved with the project, so `list_tacks`
      also shows ones left in earlier sessions, with the user's answers.

    ## Good habits
    - Make one change at a time and check it (`get_timeline`, `get_frame`).
    - Cut on word boundaries from `get_transcript`, a little after the last
      word and a little before the next, so speech isn't clipped.
    - Don't remove what the user might want without asking (a Tack).
    - Keep `goal` and `summary` short and concrete: they're what the user
      reads first.
    """

    /// Settings ▸ Agent ▸ Save…: the guide as a file (or a Claude skill).
    @MainActor
    static func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SKILL.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.message = L("Save the agent instructions. For Claude Code, save them as SKILL.md in a folder named lfstudios-editing inside ~/.claude/skills.")
        panel.prompt = L("Save")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? guide.write(to: url, atomically: true, encoding: .utf8)
    }
}
