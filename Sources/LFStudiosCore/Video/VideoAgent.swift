import AppKit
import Combine
import SwiftUI

// MARK: - AI agents (1.19.0): sessions, checkpoints, the change feed, Tacks

/// One change an agent made, in the Agent panel's feed: click to go there.
struct VideoAgentChange: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    /// What it did, in the undo menu's words.
    let title: String
    /// The tool it used.
    let tool: String
    /// Where on the timeline (seconds).
    let time: Double
    /// What it changed, to select when clicked.
    let selection: VideoEditorModel.Selection?
    /// Refused (a locked track, the user took over…): shown, nothing changed.
    var refused = false
}

/// A note or a question from the agent, pinned to a moment of a clip: it
/// follows the clip when it moves or is trimmed. The user answers or
/// dismisses it; the agent reads the answer.
struct VideoTack: Identifiable, Equatable {
    enum Anchor: Equatable {
        /// The recording's own second (main track): follows its clip.
        case source(Double)
        /// Seconds into an item on a track above.
        case layer(UUID, Double)
        /// A timeline second (nothing under it).
        case timeline(Double)
    }

    let id = UUID()
    var anchor: Anchor
    var text: String
    var isQuestion: Bool
    var answer: String?
    var dismissed = false
}

/// An agent's run on one project: what it changed since it began (its
/// checkpoint), its feed, its Tacks, and whether the user took over.
@MainActor
final class VideoAgentRun: ObservableObject {
    /// The project as it was when the run began (Revert all goes back there).
    let checkpoint: VideoDemoProject
    let undoDepth: Int
    let began = Date()
    /// What the agent says it's doing (begin_agent_session's goal).
    let goal: String
    @Published var changes: [VideoAgentChange] = []
    @Published var tacks: [VideoTack] = []
    /// The user clicked or typed in the editor: the agent's next edit waits
    /// until Resume.
    @Published var paused = false
    /// The agent said it's done (or the user asked to review): Keep or
    /// Revert all.
    @Published var reviewing = false

    init(project: VideoDemoProject, undoDepth: Int, goal: String) {
        checkpoint = project
        self.undoDepth = undoDepth
        self.goal = goal
    }

    /// Where the agent changed something (marked on the timeline in review).
    var changedTimes: [Double] { changes.filter { !$0.refused }.map(\.time) }
}

/// Everything about agents, for the whole app: the connection's switch and
/// token, who's connected, and each open project's run.
@MainActor
final class VideoAgentHub: ObservableObject {
    static let shared = VideoAgentHub()

    /// Settings ▸ Agent ▸ Allow AI agents to edit (off until turned on).
    @Published private(set) var isEnabled = Settings.videoAgentEnabled
    /// The server is up (it can fail to start: then why).
    @Published private(set) var isListening = false
    @Published private(set) var problem: String?
    /// An agent talked to LF Studios lately (the dot), and what it's called.
    @Published private(set) var connectedClient: String?
    @Published private(set) var lastActivity: Date?
    /// Each open project's run, by its editor.
    @Published private(set) var runs: [ObjectIdentifier: VideoAgentRun] = [:]

    var endpointFile = VideoAgentEndpoint.file
    private var idleCheck: Timer?

    /// Seconds without a message after which the dot goes out.
    static let idleAfter: TimeInterval = 120

    var isConnected: Bool { connectedClient != nil }

    /// At launch: listening if the switch is on.
    func startIfEnabled() {
        guard isEnabled else { return }
        Task { await listen() }
    }

    /// The switch.
    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        Settings.videoAgentEnabled = on
        isEnabled = on
        if on {
            Task { await listen() }
        } else {
            disconnect(turnOff: false)
            VideoAgentServer.shared.stop(endpointFile: endpointFile)
            isListening = false
        }
    }

    /// The token in use (made the first time, kept in the endpoint file).
    var token: String {
        if let existing = VideoAgentEndpoint.read(from: endpointFile)?.token, !existing.isEmpty { return existing }
        if !VideoAgentServer.shared.token.isEmpty { return VideoAgentServer.shared.token }
        return Settings.videoAgentToken ?? {
            let fresh = VideoAgentEndpoint.newToken()
            Settings.videoAgentToken = fresh
            return fresh
        }()
    }

    /// Settings ▸ Agent ▸ New token: whatever had the old one is refused.
    func renewToken() {
        let fresh = VideoAgentEndpoint.newToken()
        Settings.videoAgentToken = fresh
        VideoAgentServer.shared.use(token: fresh, endpointFile: endpointFile)
        connectedClient = nil
        objectWillChange.send()
    }

    func listen(preferredPort: UInt16? = nil) async {
        let server = VideoAgentServer.shared
        server.respond = { message, session in await VideoAgentProtocol.shared.answer(message, session: session) }
        server.onActivity = { [weak self] _ in self?.noteActivity() }
        let token = Settings.videoAgentToken ?? {
            let fresh = VideoAgentEndpoint.newToken()
            Settings.videoAgentToken = fresh
            return fresh
        }()
        do {
            // The last port again when it's free (HTTP-direct setups keep working).
            let preferred = preferredPort ?? Settings.videoAgentPort.flatMap { UInt16(exactly: $0) }
            do {
                try await server.start(token: token, preferred: preferred, endpointFile: endpointFile)
            } catch where preferred != nil {
                try await server.start(token: token, preferred: nil, endpointFile: endpointFile)
            }
            Settings.videoAgentPort = Int(server.port)
            isListening = true
            problem = nil
        } catch {
            isListening = false
            problem = L("The agent connection couldn't start: \(error.localizedDescription)")
        }
    }

    /// Someone talked: the dot lights; it goes out after a while of quiet.
    func noteActivity(client: String? = nil) {
        lastActivity = Date()
        if let client { connectedClient = client } else if connectedClient == nil { connectedClient = L("AI agent") }
        idleCheck?.invalidate()
        idleCheck = Timer.scheduledTimer(withTimeInterval: Self.idleAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.connectedClient = nil }
        }
    }

    /// Disconnect (the dot's menu): the connection goes off; every run
    /// stops, each project shows its changes to Keep or Revert.
    func disconnect(turnOff: Bool = true) {
        connectedClient = nil
        for run in runs.values where !run.reviewing { run.reviewing = true }
        if turnOff { setEnabled(false) }
    }

    // MARK: Runs

    func run(for model: VideoEditorModel) -> VideoAgentRun? { runs[ObjectIdentifier(model)] }

    @discardableResult
    func begin(on model: VideoEditorModel, goal: String) -> VideoAgentRun {
        if let run = run(for: model), !run.reviewing { return run }
        let run = VideoAgentRun(project: model.project, undoDepth: model.undoDepth, goal: goal)
        runs[ObjectIdentifier(model)] = run
        // Its feed and Keep / Revert all, where the user can see them.
        VideoEditorPanelStore.shared.showAgentPanel()
        model.showNotice(L("An AI agent is editing. Click or type in the editor to take over."), symbol: "sparkles")
        return run
    }

    /// The agent's done: the user sees what changed and chooses.
    func end(on model: VideoEditorModel) {
        guard let run = run(for: model) else { return }
        run.reviewing = true
        run.paused = false
        objectWillChange.send()
    }

    /// Keep: the changes stay (each still undoes with ⌘Z).
    func keep(on model: VideoEditorModel) {
        runs[ObjectIdentifier(model)] = nil
        model.showNotice(L("Kept the agent's changes"), symbol: "checkmark.circle")
    }

    /// Revert all: back to where the run began, as one step (⌘Z brings
    /// the changes back).
    func revertAll(on model: VideoEditorModel) {
        guard let run = run(for: model) else { return }
        let checkpoint = run.checkpoint
        model.mutate(label: "Revert Agent Changes") { $0 = checkpoint }
        model.endGesture()
        runs[ObjectIdentifier(model)] = nil
        model.showNotice(L("Reverted the agent's changes"), symbol: "arrow.uturn.backward.circle")
    }

    /// The user clicked or typed in the editor while an agent works.
    func userTookOver(_ model: VideoEditorModel) {
        guard let run = run(for: model), !run.reviewing, !run.paused else { return }
        run.paused = true
    }

    func resume(_ model: VideoEditorModel) {
        run(for: model)?.paused = false
    }

    /// The editor closed: its run goes with it (its changes stay, as kept).
    func forget(_ model: VideoEditorModel) {
        runs[ObjectIdentifier(model)] = nil
    }

    func record(_ change: VideoAgentChange, on model: VideoEditorModel) {
        guard let run = run(for: model) else { return }
        run.changes.append(change)
    }

    /// Tests: start from nothing.
    func reset() {
        runs.removeAll()
        connectedClient = nil
        lastActivity = nil
        isEnabled = Settings.videoAgentEnabled
    }
}

extension VideoEditorModel {
    /// Runs `body`, then puts everything back as it was: what the project
    /// would become (an agent's dry run, 1.19.0). No undo step, no notice.
    func trying(_ body: () -> Void) -> VideoDemoProject {
        let saved = snapshotForTrying()
        body()
        let after = project
        restore(saved)
        return after
    }

    /// Where a tack is on the timeline now (nil: its clip is gone).
    func timelineTime(of tack: VideoTack) -> Double? {
        switch tack.anchor {
        case .source(let time): return timelineTime(forSource: time)
        case .layer(let id, let offset):
            guard let item = project.layerItem(id) else { return nil }
            return item.at + min(max(offset, 0), item.length)
        case .timeline(let time): return min(max(time, 0), timelineDuration)
        }
    }

    /// A tack at the timeline's `time`, on what's there: an item above the
    /// main track when `item` is given, else the recording.
    func tackAnchor(at time: Double, item: UUID?) -> VideoTack.Anchor {
        if let item, let found = project.layerItem(item) { return .layer(item, time - found.at) }
        if segments.contains(where: { time >= $0.timelineStart - 0.001 && time <= $0.timelineEnd + 0.001 }) {
            return .source(sourceTime(forTimeline: time))
        }
        return .timeline(time)
    }
}
