import Combine
import Foundation

// MARK: - The built-in assistant (1.20.0): the chat and its requests

/// A message in the Assistant's chat: what the panel shows and what the
/// project keeps (never a key: errors are scrubbed).
struct VideoAIChatMessage: Codable, Equatable, Identifiable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    /// Who answered (assistant messages).
    var provider: VideoAIProvider?
    var model: String?
    /// Tokens the reply used (all its steps), as the provider reported them.
    var usage: VideoAIUsage?
    /// What it changed, in the undo menu's words.
    var actions: [String]?
    /// It stopped with this (wrong key, out of credit, Stop…).
    var error: String?
}

/// A project's chat with the Assistant: saved in the project only when it
/// has messages (format 7).
struct VideoAIChatHistory: Codable, Equatable {
    var messages: [VideoAIChatMessage] = []

    /// Every reply's tokens, together.
    var usage: VideoAIUsage {
        messages.compactMap(\.usage).reduce(VideoAIUsage(), +)
    }
}

/// The Assistant for one editor: sends the user's request to the chosen
/// provider and model, runs the tools it asks for (the 1.19 agent tools,
/// as one run: the feed, a checkpoint, Keep or Revert all), and streams
/// its answer.
@MainActor
final class VideoAIAssistant: ObservableObject {
    private static var assistants: [ObjectIdentifier: VideoAIAssistant] = [:]

    static func of(_ model: VideoEditorModel) -> VideoAIAssistant {
        if let existing = assistants[ObjectIdentifier(model)] { return existing }
        let assistant = VideoAIAssistant(model: model)
        assistants[ObjectIdentifier(model)] = assistant
        return assistant
    }

    /// The editor closed.
    static func forget(_ model: VideoEditorModel) {
        assistants.removeValue(forKey: ObjectIdentifier(model))?.stop()
    }

    /// The user is in the Assistant panel (pointer over it, or typing in
    /// it): that isn't taking over the edit.
    static func isUserInPanel(of model: VideoEditorModel) -> Bool {
        guard let assistant = assistants[ObjectIdentifier(model)] else { return false }
        return assistant.pointerInPanel || assistant.typing
    }

    private weak var model: VideoEditorModel?
    /// A request is going.
    @Published private(set) var isWorking = false
    /// The answer so far, while it streams.
    @Published private(set) var streaming = ""
    /// What it's doing now ("Splitting…"), while it works.
    @Published private(set) var activity: String?
    var pointerInPanel = false
    var typing = false

    /// The conversation as the provider knows it (thinking, reasoning and
    /// signatures included), for the chat while it's open; rebuilt from
    /// the saved messages for another provider or model, or after reopening.
    private var native: [VideoAgentJSON] = []
    private var nativeFor: (VideoAIProvider, String)?
    private var task: Task<Void, Never>?

    /// Steps (tool rounds) one request may take: never endless.
    static let maxSteps = 30

    init(model: VideoEditorModel) {
        self.model = model
    }

    var history: VideoAIChatHistory { model?.project.aiChat ?? VideoAIChatHistory() }

    /// Ready to send: a provider chosen, its key in the Keychain, a model.
    static var isConfigured: Bool { configuration != nil }

    static var configuration: (provider: VideoAIProvider, model: String)? {
        guard let provider = Settings.videoAIProvider, VideoAIKeys.hasKey(provider),
              let model = Settings.videoAIModel(for: provider), !model.isEmpty else { return nil }
        return (provider, model)
    }

    /// The tools it offers: the agent tools, without the session tools (a
    /// request is the session) and, unless frames are on, without frames.
    static var tools: [VideoAgentTool] {
        VideoAgentProtocol.shared.tools.filter { tool in
            !["begin_agent_session", "end_agent_session"].contains(tool.name) && (Settings.videoAISendsFrames || tool.name != "get_frame")
        }
    }

    // MARK: Requests

    func send(_ text: String) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !isWorking, let model else { return }
        guard let (provider, modelID) = Self.configuration, let key = VideoAIKeys.key(for: provider) else {
            append(VideoAIChatMessage(role: .user, text: words))
            append(VideoAIChatMessage(role: .assistant, text: "", error: VideoAIError.noKey.localizedDescription))
            return
        }
        let hub = VideoAgentHub.shared
        // The last request's changes, still waiting: kept, so this one gets
        // its own checkpoint.
        if let run = hub.run(for: model), run.reviewing { hub.keep(on: model) }
        // Not while an MCP agent is in the middle of a run.
        if let run = hub.run(for: model), !run.reviewing {
            append(VideoAIChatMessage(role: .user, text: words))
            append(VideoAIChatMessage(role: .assistant, text: "", error: L("Another AI agent is editing this project. Wait until it's done, then ask again.")))
            return
        }
        let earlier = history.messages
        append(VideoAIChatMessage(role: .user, text: words))
        if nativeFor.map({ $0 != provider || $1 != modelID }) ?? true {
            native = Self.rebuilt(earlier, for: provider)
            nativeFor = (provider, modelID)
        }
        native.append(VideoAIClient.userItem(provider, text: words))
        hub.begin(on: model, goal: words, byAssistant: true)
        isWorking = true
        streaming = ""
        activity = nil
        task = Task { [weak self] in
            await self?.run(provider: provider, modelID: modelID, key: key)
        }
    }

    /// Stop: the request ends now; what it changed so far waits for Keep or
    /// Revert all.
    func stop() {
        task?.cancel()
    }

    /// New chat: the conversation starts over (the old one is gone from
    /// the project).
    func newChat() {
        guard !isWorking, let model else { return }
        model.project.aiChat = nil
        native = []
        nativeFor = nil
        streaming = ""
    }

    private func run(provider: VideoAIProvider, modelID: String, key: String) async {
        guard let model else { return }
        let hub = VideoAgentHub.shared
        let tools = Self.tools
        var usage = VideoAIUsage()
        var answer = ""
        var problem: String?
        do {
            var steps = 0
            while true {
                try Task.checkCancellation()
                let request = VideoAIRequest(provider: provider, model: modelID, key: key, system: Self.system(frames: Settings.videoAISendsFrames),
                                             tools: tools.map(VideoAITool.init), items: native)
                let reply = try await VideoAIClient.send(request) { [weak self] piece in
                    Task { @MainActor in self?.streaming += piece }
                }
                native += reply.items
                usage = usage + reply.usage
                if !reply.text.isEmpty { answer += (answer.isEmpty ? "" : "\n\n") + reply.text }
                streaming = answer
                if reply.stop == .refused {
                    problem = L("The model declined this request.")
                    break
                }
                if reply.stop == .truncated, reply.calls.isEmpty {
                    problem = L("The answer was too long and was cut off.")
                    break
                }
                guard !reply.calls.isEmpty else { break }
                steps += 1
                guard steps <= Self.maxSteps else {
                    problem = L("Stopped after \(Self.maxSteps) steps. Ask again to go on.")
                    break
                }
                var results: [(VideoAIToolCall, VideoAgentToolResult)] = []
                for call in reply.calls {
                    // The user took over: the next edit waits for Resume.
                    while hub.run(for: model)?.paused == true {
                        activity = L("Paused: click Resume to go on")
                        try await Task.sleep(nanoseconds: 200_000_000)
                    }
                    try Task.checkCancellation()
                    activity = Self.activity(call.name)
                    results.append((call, await execute(call, on: model, tools: tools)))
                }
                activity = nil
                native += VideoAIClient.resultItems(provider, results)
            }
        } catch is CancellationError {
            problem = L("Stopped.")
        } catch let failure as VideoAIError {
            problem = failure.localizedDescription
        } catch {
            problem = VideoAIKeys.scrubbed(error.localizedDescription)
        }
        // What it changed waits for Keep or Revert all; nothing changed,
        // nothing to review.
        var actions: [String] = []
        if let run = hub.run(for: model) {
            actions = run.changes.filter { !$0.refused }.map(\.title)
            if actions.isEmpty { hub.drop(on: model) } else { hub.end(on: model) }
        }
        append(VideoAIChatMessage(role: .assistant, text: VideoAIKeys.scrubbed(answer), provider: provider, model: modelID, usage: usage,
                                  actions: actions.isEmpty ? nil : actions, error: problem.map(VideoAIKeys.scrubbed)))
        if problem != nil {
            // A broken exchange isn't sent again: the next request starts
            // from the saved messages.
            native = []
            nativeFor = nil
        }
        streaming = ""
        activity = nil
        isWorking = false
        task = nil
    }

    private func execute(_ call: VideoAIToolCall, on model: VideoEditorModel, tools: [VideoAgentTool]) async -> VideoAgentToolResult {
        guard let tool = tools.first(where: { $0.name == call.name }) else {
            return .error("There's no tool called \(call.name).")
        }
        guard let arguments = call.arguments else {
            return .error("The arguments weren't valid JSON. Send them again.")
        }
        return await VideoAgentProtocol.shared.call(tool, arguments, on: model)
    }

    private func append(_ message: VideoAIChatMessage) {
        guard let model else { return }
        var chat = model.project.aiChat ?? VideoAIChatHistory()
        chat.messages.append(message)
        model.project.aiChat = chat
    }

    /// The saved messages as a conversation for `provider`: plain text,
    /// alternating, starting with the user.
    static func rebuilt(_ messages: [VideoAIChatMessage], for provider: VideoAIProvider) -> [VideoAgentJSON] {
        var turns: [(VideoAIChatMessage.Role, String)] = []
        for message in messages {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let last = turns.last, last.0 == message.role {
                turns[turns.count - 1].1 += "\n\n" + text
            } else {
                turns.append((message.role, text))
            }
        }
        if turns.first?.0 == .assistant { turns.removeFirst() }
        // It must end with the model's turn (the new request follows).
        if turns.last?.0 == .user { turns.removeLast() }
        return turns.map { role, text in
            role == .user ? VideoAIClient.userItem(provider, text: text) : VideoAIClient.assistantItem(provider, text: text)
        }
    }

    static func activity(_ tool: String) -> String {
        tool.hasPrefix("get_") || tool.hasPrefix("list_") ? L("Looking at the project…") : L("Editing…")
    }

    /// What the model is told (in English: the model reads it).
    static func system(frames: Bool) -> String {
        """
        You are the Assistant inside LF Studios, a Mac video editor. You edit the project open in this window, at the user's request, with the editor's own tools. Each request is one run: everything you change is shown to the user as you go, and at the end they choose Keep or Revert all.

        - Read first: get_project, get_timeline, get_transcript, get_captions, get_markers, get_keyframes. Times are timeline seconds.
        - Make one change at a time and check it. Use dry_run: true before anything large.
        - Commands act at the playhead and on the selection: seek and select first, or pass time, kind and id.
        - auto_captions, remove_ums, shorten_pauses and apply_my_style run the app's own commands on the whole video.
        - You can't export. prepare_export fills in the Export window and opens it; the user clicks Export.
        - You can only place files already in the project or its folder. Locked tracks can't be changed.
        - If you need the user to decide something, ask in your answer, or leave a Tack (add_tack) at the moment it's about.
        - \(frames ? "get_frame shows you a frame of the video." : "You can't see the video's frames: work from the timeline, the transcript and the captions.")
        - When you're done, answer briefly: what you changed and where. Use the user's language.
        """
    }
}
