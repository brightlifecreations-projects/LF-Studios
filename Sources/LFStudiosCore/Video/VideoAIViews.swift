import AppKit
import SwiftUI

// MARK: - The built-in assistant (1.20.0): Settings ▸ AI and the Assistant panel

/// One provider's key and model, while Settings is open.
@MainActor
final class VideoAISettingsModel: ObservableObject {
    static let shared = VideoAISettingsModel()

    /// What's typed into each key field (cleared once saved).
    @Published var typed: [VideoAIProvider: String] = [:]
    /// Each provider's last check: works (how many models) or what failed.
    @Published var status: [VideoAIProvider: String] = [:]
    @Published var checking: Set<VideoAIProvider> = []
    @Published private(set) var revision = 0

    /// The saved key, as dots and its last 4 characters.
    func masked(_ provider: VideoAIProvider) -> String? {
        VideoAIKeys.key(for: provider).map(VideoAIKeys.masked)
    }

    func models(_ provider: VideoAIProvider) -> [VideoAIModel] {
        VideoAIModels.usable(provider, Settings.videoAIModelList(for: provider))
    }

    /// Save: into the Keychain (and the field empties), then checked.
    func save(_ provider: VideoAIProvider) {
        let key = (typed[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try VideoAIKeys.store.setKey(key, for: provider)
            typed[provider] = nil
            revision += 1
            test(provider)
        } catch {
            status[provider] = VideoAIKeys.scrubbed(error.localizedDescription)
        }
    }

    /// Test key: asks for the provider's model list (no tokens used), which
    /// also fills the model menu.
    func test(_ provider: VideoAIProvider) {
        guard let key = VideoAIKeys.key(for: provider), !checking.contains(provider) else { return }
        checking.insert(provider)
        status[provider] = nil
        Task {
            defer { checking.remove(provider) }
            do {
                let all = try await VideoAIModels.fetch(provider, key: key)
                let usable = VideoAIModels.usable(provider, all)
                Settings.setVideoAIModelList(usable, for: provider)
                let chosen = Settings.videoAIModel(for: provider)
                if chosen == nil || !usable.contains(where: { $0.id == chosen }) {
                    Settings.setVideoAIModel(VideoAIModels.defaultModel(provider, usable)?.id, for: provider)
                }
                status[provider] = usable.isEmpty ? L("The key works, but it has no chat models.") : L("The key works: \(usable.count) models")
            } catch let failure as VideoAIError {
                status[provider] = failure.localizedDescription
            } catch {
                status[provider] = VideoAIKeys.scrubbed(error.localizedDescription)
            }
            revision += 1
        }
    }

    func remove(_ provider: VideoAIProvider) {
        try? VideoAIKeys.store.removeKey(for: provider)
        if Settings.videoAIProvider == provider { Settings.videoAIProvider = nil }
        status[provider] = nil
        revision += 1
    }

    func choose(_ provider: VideoAIProvider?) {
        Settings.videoAIProvider = provider
        if let provider, Settings.videoAIModel(for: provider) == nil {
            Settings.setVideoAIModel(VideoAIModels.defaultModel(provider, Settings.videoAIModelList(for: provider))?.id, for: provider)
        }
        revision += 1
    }

    func chooseModel(_ model: String, for provider: VideoAIProvider) {
        Settings.setVideoAIModel(model, for: provider)
        revision += 1
    }

    /// Something changed elsewhere (the Assistant panel's picker).
    func refresh() { revision += 1 }
}

/// Settings ▸ AI.
struct AISettingsView: View {
    @ObservedObject private var settings = VideoAISettingsModel.shared
    @State private var frames = Settings.videoAISendsFrames

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Chat with an AI that edits this video with you, using your own API key. Requests go straight from this Mac to the provider."))
                    .font(.system(size: 12))
                    .foregroundStyle(LFStudiosTheme.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                PreferenceSection(L("Assistant")) {
                    AgentSettingsRow(L("Provider"), detail: VideoAIAssistant.isConfigured ? L("Open the Assistant from Layout ▸ Assistant Panel.") : L("Add a key below, then choose its provider.")) {
                        Picker("", selection: Binding(get: { Settings.videoAIProvider }, set: { settings.choose($0) })) {
                            Text(L("None")).tag(VideoAIProvider?.none)
                            ForEach(VideoAIProvider.allCases.filter(VideoAIKeys.hasKey)) { provider in
                                Text(provider.title).tag(VideoAIProvider?.some(provider))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        .accessibilityLabel(L("Provider"))
                    }
                    PreferenceDivider()
                    AgentSettingsRow(L("Send video frames to the AI"), detail: L("Off: only the timeline, the transcript and the captions are sent. On: the AI can also look at frames of the video.")) {
                        Toggle("", isOn: $frames)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: frames) { Settings.videoAISendsFrames = $0 }
                            .accessibilityLabel(L("Send video frames to the AI"))
                    }
                }
                ForEach(VideoAIProvider.allCases) { provider in
                    providerSection(provider)
                }
                Text(L("Each request is billed to your account by the provider; the Assistant shows the tokens each reply used. Keys are kept only in your Mac's Keychain."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(LFStudiosTheme.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: 560, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .id(settings.revision)
        }
    }

    @ViewBuilder
    private func providerSection(_ provider: VideoAIProvider) -> some View {
        PreferenceSection(provider.title) {
            if let masked = settings.masked(provider) {
                AgentSettingsRow(L("API key"), detail: settings.status[provider] ?? L("Saved in the Keychain")) {
                    Text(masked)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(LFStudiosTheme.ink.opacity(0.6))
                        .accessibilityLabel(L("Key ending in \(String(masked.suffix(4)))"))
                    Button(settings.checking.contains(provider) ? L("Testing…") : L("Test Key")) { settings.test(provider) }
                        .disabled(settings.checking.contains(provider))
                    Button(L("Remove Key")) { settings.remove(provider) }
                }
                PreferenceDivider()
                AgentSettingsRow(L("Model"), detail: settings.models(provider).isEmpty ? L("Click Test Key to load the models.") : nil) {
                    let models = settings.models(provider)
                    if !models.isEmpty {
                        Picker("", selection: Binding(get: { Settings.videoAIModel(for: provider) ?? "" }, set: { settings.chooseModel($0, for: provider) })) {
                            ForEach(models) { model in Text(model.name).tag(model.id) }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                        .accessibilityLabel(L("Model"))
                    }
                    Button(L("Refresh")) { settings.test(provider) }
                        .disabled(settings.checking.contains(provider))
                        .help(L("Load the provider's current models"))
                }
            } else {
                AgentSettingsRow(L("API key"), detail: settings.status[provider] ?? L("Paste a key that starts with \(provider.keyPrefix)")) {
                    SecureField(L("Paste key"), text: Binding(get: { settings.typed[provider] ?? "" }, set: { settings.typed[provider] = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .onSubmit { settings.save(provider) }
                        .accessibilityLabel(L("\(provider.title) API key"))
                    Button(L("Save")) { settings.save(provider) }
                        .disabled((settings.typed[provider] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            PreferenceDivider()
            AgentSettingsRow(L("Get a key"), detail: L("Make one on the provider's website; it bills your account there.")) {
                Button(L("Open Website")) { NSWorkspace.shared.open(provider.keyPage) }
            }
        }
    }
}

// MARK: - The Assistant panel

/// The Assistant: a chat with the chosen provider and model that edits
/// this project, each request one run (Keep or Revert all).
struct VideoAssistantPanel: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject private var hub = VideoAgentHub.shared
    @ObservedObject private var settings = VideoAISettingsModel.shared

    var body: some View {
        VideoAssistantChat(model: model, assistant: VideoAIAssistant.of(model))
            .id(settings.revision)
    }
}

private struct VideoAssistantChat: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var assistant: VideoAIAssistant
    @ObservedObject private var hub = VideoAgentHub.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            if VideoAIAssistant.isConfigured {
                messages
                if let run = hub.run(for: model) { VideoAssistantRunBar(model: model, run: run) }
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                composer
            } else {
                setup
            }
        }
        .background(VideoEditorTheme.panel)
        .onHover { assistant.pointerInPanel = $0 }
        .onChange(of: focused) { assistant.typing = $0 }
    }

    // MARK: Header: provider and model, New chat

    private var header: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(VideoAIProvider.allCases.filter(VideoAIKeys.hasKey)) { provider in
                    let models = VideoAIModels.usable(provider, Settings.videoAIModelList(for: provider))
                    Section(provider.title) {
                        ForEach(models) { choice in
                            Button {
                                VideoAISettingsModel.shared.choose(provider)
                                VideoAISettingsModel.shared.chooseModel(choice.id, for: provider)
                            } label: {
                                if Settings.videoAIProvider == provider, Settings.videoAIModel(for: provider) == choice.id {
                                    Label(choice.name, systemImage: "checkmark")
                                } else {
                                    Text(choice.name)
                                }
                            }
                        }
                    }
                }
                Divider()
                Button(L("Settings ▸ AI…")) { PreferencesWindowController.shared.show(tab: .ai) }
            } label: {
                Text(currentTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(assistant.isWorking)
            .help(L("Provider and model"))
            Spacer(minLength: 4)
            Button(L("New Chat")) { assistant.newChat() }
                .buttonStyle(VideoSecondaryButtonStyle())
                .disabled(assistant.isWorking || assistant.history.messages.isEmpty)
                .help(L("Start over: this chat is removed from the project"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var currentTitle: String {
        guard let (provider, modelID) = VideoAIAssistant.configuration else { return L("Choose a model") }
        let name = Settings.videoAIModelList(for: provider).first { $0.id == modelID }?.name ?? modelID
        return "\(provider.shortTitle) · \(name)"
    }

    // MARK: Not set up yet

    private var setup: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textTertiary)
            Text(L("Add an API key for Claude, OpenAI or Gemini in Settings ▸ AI, then choose its provider."))
                .font(.system(size: 12))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(L("Open Settings")) { PreferencesWindowController.shared.show(tab: .ai) }
                .buttonStyle(VideoSecondaryButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Messages

    private var messages: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if assistant.history.messages.isEmpty, !assistant.isWorking {
                        Text(L("Ask for an edit: “Cut the long pauses”, “Add captions and fix the typos”, “Mark where the settings open”."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(VideoEditorTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    ForEach(assistant.history.messages) { message in
                        VideoAssistantMessageRow(message: message).id(message.id)
                    }
                    if assistant.isWorking {
                        VStack(alignment: .leading, spacing: 4) {
                            if !assistant.streaming.isEmpty {
                                Text(assistant.streaming)
                                    .font(.system(size: 12))
                                    .foregroundStyle(VideoEditorTheme.textPrimary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(assistant.activity ?? L("Thinking…"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(VideoEditorTheme.textSecondary)
                            }
                        }
                        .id("working")
                    }
                    if let tacks = model.project.tacks, tacks.contains(where: { !$0.dismissed }) {
                        VideoAgentTacksList(model: model)
                    }
                }
                .padding(10)
            }
            .onAppear {
                if let last = assistant.history.messages.last { scroller.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: assistant.history.messages.count) { _ in
                if let last = assistant.history.messages.last { withAnimation { scroller.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: assistant.streaming) { _ in scroller.scrollTo("working", anchor: .bottom) }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                TextField(L("Ask the Assistant to edit…"), text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.card))
                    .onSubmit(send)
                    .disabled(assistant.isWorking)
                    .accessibilityLabel(L("Message to the Assistant"))
                if assistant.isWorking {
                    Button(L("Stop")) { assistant.stop() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                        .help(L("Stop now: what it changed so far waits for Keep or Revert All"))
                } else {
                    Button(L("Send")) { send() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            let usage = assistant.history.usage
            if usage.total > 0 {
                Text(L("This chat: \(VideoAssistantMessageRow.tokens(usage.input)) in · \(VideoAssistantMessageRow.tokens(usage.output)) out tokens"))
                    .font(.system(size: 10))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
            }
        }
        .padding(8)
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !assistant.isWorking else { return }
        draft = ""
        assistant.send(text)
    }
}

/// One message: the user's on the right, the Assistant's on the left with
/// what it changed and its tokens.
struct VideoAssistantMessageRow: View {
    let message: VideoAIChatMessage

    static func tokens(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 30) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 12))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, message.role == .user ? 9 : 0)
                        .padding(.vertical, message.role == .user ? 6 : 0)
                        .background(message.role == .user ? RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.opacity(0.18)) : nil)
                }
                if let actions = message.actions, !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                            Label(action, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(VideoEditorTheme.textSecondary)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
                if let error = message.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let usage = message.usage, usage.total > 0 {
                    Text(L("\(Self.tokens(usage.input)) in · \(Self.tokens(usage.output)) out tokens"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                }
            }
            if message.role == .assistant { Spacer(minLength: 20) }
        }
    }
}

/// Under the chat: the request's changes, Resume when the user took over,
/// and Keep or Revert All when it's done.
private struct VideoAssistantRunBar: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var run: VideoAgentRun

    var body: some View {
        let changes = run.changes.filter { !$0.refused }
        if run.paused || run.reviewing || !changes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                HStack(spacing: 6) {
                    Circle().fill(run.reviewing ? Color.orange : run.paused ? Color.yellow : Color.green).frame(width: 7, height: 7)
                    Text(run.reviewing ? L("Done: review the changes") : run.paused ? L("Paused: you took over") : L("Assistant editing"))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Spacer()
                    if run.paused, !run.reviewing {
                        Button(L("Resume")) { VideoAgentHub.shared.resume(model) }
                            .buttonStyle(VideoSecondaryButtonStyle())
                    }
                }
                ForEach(changes.suffix(4)) { change in
                    Button {
                        model.seek(to: change.time)
                        if let selection = change.selection { model.selection = selection }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Color.accentColor)
                            Text(change.title).font(.system(size: 11)).foregroundStyle(VideoEditorTheme.textPrimary).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(VideoEditorModel.timecode(change.time)).font(.system(size: 10, design: .monospaced)).foregroundStyle(VideoEditorTheme.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Go there"))
                }
                if run.reviewing {
                    HStack(spacing: 8) {
                        Text(L("\(changes.count) changes"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(VideoEditorTheme.textSecondary)
                        Spacer()
                        Button(L("Revert All")) { VideoAgentHub.shared.revertAll(on: model) }
                            .buttonStyle(VideoSecondaryButtonStyle())
                            .help(L("Back to how the project was before this request (⌘Z brings the changes back)"))
                        Button(L("Keep")) { VideoAgentHub.shared.keep(on: model) }
                            .buttonStyle(VideoSecondaryButtonStyle())
                            .help(L("Keep the changes (each still undoes with ⌘Z)"))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }
}
