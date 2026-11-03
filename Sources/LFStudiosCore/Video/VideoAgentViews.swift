import AppKit
import SwiftUI

// MARK: - AI agents (1.19.0): Settings ▸ Agent, the dot, the Agent panel

/// What to paste where, for each agent app (the bridge in this app's bundle).
enum VideoAgentSetup: String, CaseIterable, Identifiable {
    case claudeDesktop
    case claudeCode
    case cursor
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeDesktop: return "Claude Desktop" // l10n-ignore: an app's name
        case .claudeCode: return "Claude Code" // l10n-ignore: an app's name
        case .cursor: return "Cursor" // l10n-ignore: an app's name
        case .codex: return "Codex" // l10n-ignore: an app's name
        }
    }

    /// The bridge: inside LF Studios (the same path after updates).
    static var bridgePath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/lfstudios-mcp").path
    }

    /// Where it goes, in the agent app.
    var whereItGoes: String {
        switch self {
        case .claudeDesktop: return L("Claude ▸ Settings ▸ Developer ▸ Edit Config: paste it into claude_desktop_config.json, save, and restart Claude.")
        case .claudeCode: return L("Paste it into Terminal and press Return.")
        case .cursor: return L("Cursor ▸ Settings ▸ MCP ▸ Add new MCP server: paste it into mcp.json and save.")
        case .codex: return L("Paste it into ~/.codex/config.toml and save.")
        }
    }

    func snippet(bridge: String = Self.bridgePath) -> String {
        switch self {
        case .claudeDesktop, .cursor:
            return """
            {
              "mcpServers": {
                "lfstudios": {
                  "command": "\(bridge)"
                }
              }
            }
            """
        case .claudeCode:
            return "claude mcp add lfstudios -- \"\(bridge)\""
        case .codex:
            return """
            [mcp_servers.lfstudios]
            command = "\(bridge)"
            """
        }
    }
}

/// A Settings row whose detail wraps (the setup steps are long).
private struct AgentSettingsRow<Trailing: View>: View {
    let title: String
    let detail: String?
    let trailing: Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LFStudiosTheme.ink.opacity(0.88))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LFStudiosTheme.ink.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// Settings ▸ Agent.
struct AgentSettingsView: View {
    @ObservedObject private var hub = VideoAgentHub.shared
    @State private var copied: VideoAgentSetup?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PreferenceSection(L("AI agents")) {
                    AgentSettingsRow(L("Allow AI agents to edit"), detail: L("Off until you turn it on. Only apps on this Mac can connect.")) {
                        Toggle("", isOn: Binding(get: { hub.isEnabled }, set: { hub.setEnabled($0) }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(L("Allow AI agents to edit"))
                    }
                    if hub.isEnabled {
                        PreferenceDivider()
                        AgentSettingsRow(L("Status"), detail: status) {
                            if hub.isConnected {
                                Button(L("Disconnect")) { hub.disconnect() }
                            }
                        }
                    }
                }
                if hub.isEnabled {
                    PreferenceSection(L("Connect an agent")) {
                        ForEach(VideoAgentSetup.allCases) { setup in
                            AgentSettingsRow(setup.title, detail: setup.whereItGoes) {
                                Button(copied == setup ? L("Copied") : L("Copy setup")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(setup.snippet(), forType: .string)
                                    copied = setup
                                }
                            }
                            if setup != VideoAgentSetup.allCases.last { PreferenceDivider() }
                        }
                    }
                    PreferenceSection(L("Instructions for the agent")) {
                        AgentSettingsRow(L("How to edit in LF Studios"), detail: L("Tools, habits and limits, as a file the agent can read (also a Claude skill).")) {
                            Button(L("Save…")) { VideoAgentInstructions.save() }
                        }
                    }
                    PreferenceSection(L("Token")) {
                        AgentSettingsRow(L("New token"), detail: L("Apps that connect directly need the new one; the setups above keep working.")) {
                            Button(L("New Token")) { hub.renewToken() }
                        }
                    }
                }
                Text(L("An agent can read the open project and edit it with the editor's own commands, each one ⌘Z step. It can't export, record, or open files outside the project and its folder. You see every change in the Agent panel and choose Keep or Revert all at the end."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(LFStudiosTheme.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if let problem = hub.problem {
                    Text(problem)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
            .padding(22)
            .frame(maxWidth: 560, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var status: String {
        if !hub.isListening { return L("Starting…") }
        if let client = hub.connectedClient { return L("Connected: \(client)") }
        return L("Waiting for an agent")
    }
}

/// The dot: an agent is connected (click: Disconnect). In the status
/// strip (LF Studios layout) and the toolbar (CapCut style).
struct VideoAgentDot: View {
    @ObservedObject private var hub = VideoAgentHub.shared

    var body: some View {
        if hub.isEnabled, let client = hub.connectedClient {
            // The dot outside the menu: a menu's label is drawn in one colour.
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Menu {
                    Text(L("Connected: \(client)"))
                    Button(L("Disconnect")) { hub.disconnect() }
                } label: {
                    Text(L("Agent"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .help(L("An AI agent is connected: click to disconnect it"))
            .accessibilityLabel(L("AI agent connected"))
        }
    }
}

/// The Agent panel: the run's goal, Resume when the user took over, the
/// live feed (click: go there), Tacks to answer, Keep or Revert all.
struct VideoAgentPanel: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject private var hub = VideoAgentHub.shared

    var body: some View {
        Group {
            if let run = hub.run(for: model) {
                VideoAgentRunView(model: model, run: run)
            } else if model.project.tacks?.contains(where: { !$0.dismissed }) == true {
                // Tacks from an earlier session, saved with the project.
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hub.isEnabled ? L("No agent is editing this project.") : L("AI agents are off: Settings ▸ Agent."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(VideoEditorTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                        VideoAgentTacksList(model: model)
                    }
                    .padding(.bottom, 8)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                    Text(hub.isEnabled ? L("No agent is editing this project.") : L("AI agents are off: Settings ▸ Agent."))
                        .font(.system(size: 12))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    if !hub.isEnabled {
                        Button(L("Open Settings")) { PreferencesWindowController.shared.show(tab: .agent) }
                            .buttonStyle(VideoSecondaryButtonStyle())
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(VideoEditorTheme.panel)
    }
}

private struct VideoAgentRunView: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var run: VideoAgentRun

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(run.reviewing ? Color.orange : run.paused ? Color.yellow : Color.green).frame(width: 7, height: 7)
                    Text(run.reviewing ? L("Done: review the changes") : run.paused ? L("Paused: you took over") : L("Agent editing"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Spacer()
                    if run.paused, !run.reviewing {
                        Button(L("Resume")) { VideoAgentHub.shared.resume(model) }
                            .buttonStyle(VideoSecondaryButtonStyle())
                    }
                }
                if !run.goal.isEmpty {
                    Text(run.goal)
                        .font(.system(size: 11.5))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        VideoAgentTacksList(model: model)
                        Text(L("Changes"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(VideoEditorTheme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        if run.changes.isEmpty {
                            Text(L("Nothing changed yet."))
                                .font(.system(size: 11.5))
                                .foregroundStyle(VideoEditorTheme.textTertiary)
                                .padding(.horizontal, 12)
                        }
                        ForEach(run.changes) { change in
                            Button {
                                model.seek(to: change.time)
                                if let selection = change.selection { model.selection = selection }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: change.refused ? "circle.dashed" : "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(change.refused ? VideoEditorTheme.textTertiary : Color.accentColor)
                                    Text(change.title)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(change.refused ? VideoEditorTheme.textSecondary : VideoEditorTheme.textPrimary)
                                        .lineLimit(2)
                                    Spacer(minLength: 4)
                                    Text(VideoEditorModel.timecode(change.time))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(VideoEditorTheme.textTertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(change.id)
                            .help(L("Go there"))
                        }
                    }
                    .padding(.bottom, 8)
                }
                .onChange(of: run.changes.count) { _ in
                    if let last = run.changes.last { scroller.scrollTo(last.id, anchor: .bottom) }
                }
            }
            if run.reviewing || !run.changes.isEmpty {
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                HStack(spacing: 8) {
                    Text(L("\(run.changes.filter { !$0.refused }.count) changes"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                    Spacer()
                    Button(L("Revert All")) { VideoAgentHub.shared.revertAll(on: model) }
                        .buttonStyle(VideoSecondaryButtonStyle())
                        .help(L("Back to how the project was before the agent started (⌘Z brings the changes back)"))
                    Button(L("Keep")) { VideoAgentHub.shared.keep(on: model) }
                        .buttonStyle(VideoSecondaryButtonStyle())
                        .help(L("Keep the agent's changes (each still undoes with ⌘Z)"))
                }
                .padding(10)
            }
        }
    }
}

/// The project's open Tacks (saved with it, 1.19.1): answer a question,
/// dismiss one, click its time to go there.
struct VideoAgentTacksList: View {
    @ObservedObject var model: VideoEditorModel
    @State private var answers: [UUID: String] = [:]

    var body: some View {
        let open = (model.project.tacks ?? []).filter { !$0.dismissed }
        if !open.isEmpty {
            Text(L("Tacks"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            ForEach(open) { tack in tackRow(tack) }
        }
    }

    private func tackRow(_ tack: VideoTack) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: tack.isQuestion ? "questionmark.bubble.fill" : "pin.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.orange)
                Text(tack.text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let time = model.timelineTime(of: tack) {
                    Button(VideoEditorModel.timecode(time)) { model.seek(to: time) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }
            }
            if let answer = tack.answer {
                Text(L("You answered: \(answer)"))
                    .font(.system(size: 11))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
            } else {
                HStack(spacing: 6) {
                    if tack.isQuestion {
                        TextField(L("Answer"), text: Binding(get: { answers[tack.id] ?? "" }, set: { answers[tack.id] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                            .onSubmit { answer(tack) }
                        Button(L("Send")) { answer(tack) }
                            .buttonStyle(VideoSecondaryButtonStyle())
                            .disabled((answers[tack.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Spacer(minLength: 0)
                    Button(L("Dismiss")) { set(tack) { $0.dismissed = true } }
                        .buttonStyle(VideoSecondaryButtonStyle())
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VideoEditorTheme.card))
        .padding(.horizontal, 8)
    }

    private func answer(_ tack: VideoTack) {
        let words = (answers[tack.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        set(tack) { $0.answer = words }
        answers[tack.id] = nil
    }

    private func set(_ tack: VideoTack, _ change: (inout VideoTack) -> Void) {
        model.changeTacks { tacks in
            guard let i = tacks.firstIndex(where: { $0.id == tack.id }) else { return }
            change(&tacks[i])
        }
    }
}

/// On the timeline's ruler: where the agent changed something (in review)
/// and its Tacks (pins; click: go there).
struct VideoAgentTimelineMarks: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var offsets: VideoTimelineScrollOffsets
    @ObservedObject private var hub = VideoAgentHub.shared
    let x: (Double) -> CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let run = hub.run(for: model) {
                VideoAgentRunMarks(model: model, run: run, x: { x($0) - offsets.x })
            }
            VideoAgentTackPins(model: model, x: { x($0) - offsets.x })
        }
    }
}

private struct VideoAgentRunMarks: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var run: VideoAgentRun
    let x: (Double) -> CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if run.reviewing {
                ForEach(Array(Set(run.changedTimes.map { ($0 * 10).rounded() / 10 })).sorted(), id: \.self) { time in
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 3, height: 8)
                        .offset(x: x(time) - 1.5, y: 0)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// The project's open Tacks, as pins on the ruler (click: go there).
private struct VideoAgentTackPins: View {
    @ObservedObject var model: VideoEditorModel
    let x: (Double) -> CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach((model.project.tacks ?? []).filter { !$0.dismissed }) { tack in
                if let time = model.timelineTime(of: tack) {
                    Button { model.seek(to: time) } label: {
                        Image(systemName: tack.isQuestion ? "questionmark.bubble.fill" : "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }
                    .buttonStyle(.plain)
                    .offset(x: x(time) - 6, y: 9)
                    .help(tack.text)
                    .accessibilityLabel(L("Tack: \(tack.text)"))
                }
            }
        }
    }
}
