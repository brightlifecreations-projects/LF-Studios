import AppKit
import XCTest
@testable import LFStudiosCore

/// The built-in Assistant (1.20.0), against local mock servers for all
/// three providers (never a real provider or a real key): model lists,
/// streaming, tool calls through the 1.19 tools as one run (Keep / Revert
/// all), errors without endless retries, timeouts, Stop, taking over, and
/// keys that never leave the Keychain.
@MainActor
final class VideoAIAssistantTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private typealias T = VideoEditorTestModel
    private var directory: URL!
    private var suiteName: String!
    private var server: MockAIServer!
    private var keys: VideoAIMemoryKeys!
    private let hub = VideoAgentHub.shared
    /// Made-up keys, distinctive enough to find anywhere they might leak.
    private let testKeys: [VideoAIProvider: String] = [
        .anthropic: "sk-ant-TESTKEY-anthropic-7f3a9c",
        .openAI: "sk-TESTKEY-openai-0000000000000001",
        .gemini: "AIzaTESTKEY-gemini-00000000000000",
    ]

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-ai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "LFStudiosCoreTests.AI.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        keys = VideoAIMemoryKeys()
        VideoAIKeys.store = keys
        server = try MockAIServer()
        for provider in VideoAIProvider.allCases { VideoAIHTTP.baseURLs[provider] = server.url }
        hub.reset()
        VideoEditorPanelStore.shared.reset()
    }

    override func tearDown() async throws {
        hub.reset()
        VideoEditorPanelStore.shared.reset()
        VideoAIHTTP.baseURLs = VideoAIHTTP.defaultBaseURLs
        VideoAIHTTP.idleTimeout = 90
        VideoAIKeys.store = VideoAIMemoryKeys()
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        server = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func configure(_ provider: VideoAIProvider, model: String = "test-model") throws {
        try keys.setKey(testKeys[provider]!, for: provider)
        Settings.videoAIProvider = provider
        Settings.setVideoAIModel(model, for: provider)
    }

    private func makeModel() async throws -> VideoEditorModel {
        try await T.make(in: directory, T.Options(seconds: 6, audio: true))
    }

    private func waitUntilDone(_ assistant: VideoAIAssistant, seconds: Double = 20) async throws {
        for _ in 0..<Int(seconds * 20) where assistant.isWorking { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(assistant.isWorking, "the request finished")
    }

    // MARK: Scripted answers, in each provider's own streaming format

    private func textReply(_ provider: VideoAIProvider, _ text: String, input: Int = 120, output: Int = 30) -> MockAIServer.Response {
        let pieces = text.split(separator: " ", omittingEmptySubsequences: false).enumerated().map { $0.offset == 0 ? String($0.element) : " " + $0.element }
        switch provider {
        case .anthropic:
            return .events([
                .object(["type": .string("message_start"), "message": .object(["id": .string("msg_1"), "usage": .object(["input_tokens": .number(Double(input)), "output_tokens": .number(1)])])]),
                .object(["type": .string("content_block_start"), "index": .number(0), "content_block": .object(["type": .string("text"), "text": .string("")])]),
            ] + pieces.map { .object(["type": .string("content_block_delta"), "index": .number(0), "delta": .object(["type": .string("text_delta"), "text": .string($0)])]) } + [
                .object(["type": .string("content_block_stop"), "index": .number(0)]),
                .object(["type": .string("message_delta"), "delta": .object(["stop_reason": .string("end_turn")]), "usage": .object(["output_tokens": .number(Double(output))])]),
                .object(["type": .string("message_stop")]),
            ])
        case .openAI:
            return .events(pieces.map { .object(["type": .string("response.output_text.delta"), "output_index": .number(0), "delta": .string($0)]) } + [
                .object(["type": .string("response.output_item.done"), "output_index": .number(0), "item": .object([
                    "type": .string("message"), "id": .string("msg_1"), "role": .string("assistant"),
                    "content": .array([.object(["type": .string("output_text"), "text": .string(text)])]),
                ])]),
                .object(["type": .string("response.completed"), "response": .object(["status": .string("completed"), "usage": .object(["input_tokens": .number(Double(input)), "output_tokens": .number(Double(output))])])]),
            ])
        case .gemini:
            return .events([
                .object(["event_type": .string("interaction.created"), "interaction": .object(["id": .string("v1_1"), "status": .string("in_progress")])]),
                .object(["event_type": .string("step.start"), "index": .number(0), "step": .object(["type": .string("model_output")])]),
            ] + pieces.map { .object(["event_type": .string("step.delta"), "index": .number(0), "delta": .object(["type": .string("text"), "text": .string($0)])]) } + [
                .object(["event_type": .string("step.stop"), "index": .number(0)]),
                .object(["event_type": .string("interaction.completed"), "interaction": .object(["status": .string("completed"), "usage": .object(["total_input_tokens": .number(Double(input)), "total_output_tokens": .number(Double(output))])])]),
            ])
        }
    }

    /// A tool call, after the provider's own hidden reasoning (a thinking
    /// block with a signature, an encrypted reasoning item, a thought
    /// signature) that must come back unchanged.
    private func toolReply(_ provider: VideoAIProvider, name: String, arguments: String, input: Int = 200, output: Int = 40) -> MockAIServer.Response {
        let half = arguments.index(arguments.startIndex, offsetBy: arguments.count / 2)
        let parts = [String(arguments[..<half]), String(arguments[half...])]
        switch provider {
        case .anthropic:
            return .events([
                .object(["type": .string("message_start"), "message": .object(["usage": .object(["input_tokens": .number(Double(input)), "output_tokens": .number(1)])])]),
                .object(["type": .string("content_block_start"), "index": .number(0), "content_block": .object(["type": .string("thinking"), "thinking": .string(""), "signature": .string("")])]),
                .object(["type": .string("content_block_delta"), "index": .number(0), "delta": .object(["type": .string("signature_delta"), "signature": .string("SIG-anthropic-123")])]),
                .object(["type": .string("content_block_stop"), "index": .number(0)]),
                .object(["type": .string("content_block_start"), "index": .number(1), "content_block": .object(["type": .string("tool_use"), "id": .string("toolu_1"), "name": .string(name), "input": .object([:])])]),
            ] + parts.map { .object(["type": .string("content_block_delta"), "index": .number(1), "delta": .object(["type": .string("input_json_delta"), "partial_json": .string($0)])]) } + [
                .object(["type": .string("content_block_stop"), "index": .number(1)]),
                .object(["type": .string("message_delta"), "delta": .object(["stop_reason": .string("tool_use")]), "usage": .object(["output_tokens": .number(Double(output))])]),
            ])
        case .openAI:
            return .events([
                .object(["type": .string("response.output_item.done"), "output_index": .number(0), "item": .object(["type": .string("reasoning"), "id": .string("rs_1"), "encrypted_content": .string("ENC-openai-456"), "summary": .array([])])]),
            ] + parts.map { .object(["type": .string("response.function_call_arguments.delta"), "output_index": .number(1), "delta": .string($0)]) } + [
                .object(["type": .string("response.output_item.done"), "output_index": .number(1), "item": .object([
                    "type": .string("function_call"), "id": .string("fc_1"), "call_id": .string("call_1"), "name": .string(name), "arguments": .string(arguments),
                ])]),
                .object(["type": .string("response.completed"), "response": .object(["status": .string("completed"), "usage": .object(["input_tokens": .number(Double(input)), "output_tokens": .number(Double(output))])])]),
            ])
        case .gemini:
            return .events([
                .object(["event_type": .string("step.start"), "index": .number(0), "step": .object(["type": .string("thought")])]),
                .object(["event_type": .string("step.delta"), "index": .number(0), "delta": .object(["type": .string("thought_signature"), "signature": .string("GSIG-gemini-789")])]),
                .object(["event_type": .string("step.stop"), "index": .number(0)]),
                .object(["event_type": .string("step.start"), "index": .number(1), "step": .object(["type": .string("function_call"), "id": .string("gcall_1"), "name": .string(name), "arguments": .object([:])])]),
            ] + parts.map { .object(["event_type": .string("step.delta"), "index": .number(1), "delta": .object(["type": .string("arguments_delta"), "arguments": .string($0)])]) } + [
                .object(["event_type": .string("step.stop"), "index": .number(1)]),
                .object(["event_type": .string("interaction.completed"), "interaction": .object(["status": .string("requires_action"), "usage": .object(["total_input_tokens": .number(Double(input)), "total_output_tokens": .number(Double(output))])])]),
            ])
        }
    }

    private func request(_ provider: VideoAIProvider, items: [VideoAgentJSON]? = nil) -> VideoAIRequest {
        VideoAIRequest(provider: provider, model: "test-model", key: testKeys[provider]!, system: "Be brief.", tools: VideoAIAssistant.tools.map(VideoAITool.init),
                       items: items ?? [VideoAIClient.userItem(provider, text: "Hello")])
    }

    // MARK: Model lists

    func testModelMenusListOnlyChatModelsThatCallTools() async throws {
        server.answer = { request in
            switch request.path {
            case let path where path.hasPrefix("/v1/models") && request.header("x-api-key") != nil:
                return .json(.object(["data": .array([
                    .object(["id": .string("claude-opus-5-5"), "display_name": .string("Claude Opus 5.5"), "created_at": .string("2026-09-01T00:00:00Z")]),
                    .object(["id": .string("claude-sonnet-5-5"), "display_name": .string("Claude Sonnet 5.5"), "created_at": .string("2026-09-15T00:00:00Z")]),
                    .object(["id": .string("claude-opus-5"), "display_name": .string("Claude Opus 5"), "created_at": .string("2026-05-01T00:00:00Z")]),
                ])]))
            case let path where path.hasPrefix("/v1/models"):
                return .json(.object(["data": .array(["gpt-6.1-sol", "gpt-6-luna", "gpt-6.1-mini", "gpt-image-2.5-flare", "gpt-realtime-2.1", "gpt-transcribe", "text-embedding-3-large",
                                                      "omni-moderation-latest", "tts-1", "whisper-1", "dall-e-3", "o4-mini", "gpt-live-1"].enumerated().map { index, id in
                    .object(["id": .string(id), "created": .number(Double(1_800_000_000 - index * 1000))])
                })]))
            default:
                return .json(.object(["models": .array([
                    ("gemini-3.8-pro", ["generateContent"]), ("gemini-3.8-flash", ["generateContent"]), ("gemini-3.9-pro-preview", ["generateContent"]),
                    ("gemini-3.8-flash-image", ["generateContent"]), ("gemini-embedding-002", ["embedContent"]), ("gemini-3.8-flash-tts", ["generateContent"]),
                    ("gemini-live-3.8", ["bidiGenerateContent"]), ("imagen-5", ["predict"]),
                ].map { id, methods in
                    .object(["name": .string("models/\(id)"), "displayName": .string(id), "supportedGenerationMethods": .array(methods.map { .string($0) })])
                })]))
            }
        }
        let claude = VideoAIModels.usable(.anthropic, try await VideoAIModels.fetch(.anthropic, key: testKeys[.anthropic]!))
        XCTAssertEqual(claude.map(\.id), ["claude-sonnet-5-5", "claude-opus-5-5", "claude-opus-5"], "newest first")
        XCTAssertEqual(VideoAIModels.defaultModel(.anthropic, claude)?.id, "claude-opus-5-5", "the newest Opus")

        let openAI = VideoAIModels.usable(.openAI, try await VideoAIModels.fetch(.openAI, key: testKeys[.openAI]!))
        XCTAssertEqual(Set(openAI.map(\.id)), ["gpt-6.1-sol", "gpt-6-luna", "gpt-6.1-mini", "o4-mini"], "no image, audio, realtime, transcription, embedding, moderation, speech models")
        XCTAssertEqual(VideoAIModels.defaultModel(.openAI, openAI)?.id, "gpt-6.1-sol", "the newest full GPT")

        let gemini = VideoAIModels.usable(.gemini, try await VideoAIModels.fetch(.gemini, key: testKeys[.gemini]!))
        XCTAssertEqual(Set(gemini.map(\.id)), ["gemini-3.8-pro", "gemini-3.8-flash", "gemini-3.9-pro-preview"])
        XCTAssertEqual(VideoAIModels.defaultModel(.gemini, gemini)?.id, "gemini-3.8-pro", "the newest stable Pro")

        // Each list was asked for with the provider's own key header, nothing else.
        let paths = server.requests.map(\.path)
        XCTAssertTrue(paths.contains { $0.hasPrefix("/v1/models?limit=") })
        XCTAssertTrue(paths.contains { $0.hasPrefix("/v1beta/models?pageSize=") })
        for request in server.requests {
            XCTAssertFalse(request.path.contains("TESTKEY"), "a key never goes in an address")
        }
    }

    // MARK: Streaming and tool calls

    func testEachProviderStreamsItsAnswerWithItsUsage() async throws {
        for provider in VideoAIProvider.allCases {
            server.script(textReply(provider, "Done, I split it at two seconds.", input: 321, output: 12))
            let before = server.requests.count
            var pieces: [String] = []
            let reply = try await VideoAIClient.send(request(provider)) { pieces.append($0) }
            XCTAssertEqual(reply.text, "Done, I split it at two seconds.", "\(provider)")
            XCTAssertGreaterThan(pieces.count, 3, "\(provider): streamed in pieces")
            XCTAssertEqual(reply.usage, VideoAIUsage(input: 321, output: 12), "\(provider): its usage")
            XCTAssertEqual(reply.stop, .done)
            let sent = try XCTUnwrap(server.requests.dropFirst(before).first)
            let body = try XCTUnwrap(sent.json)
            switch provider {
            case .anthropic:
                XCTAssertEqual(sent.path, "/v1/messages")
                XCTAssertEqual(sent.header("x-api-key"), testKeys[.anthropic])
                XCTAssertEqual(sent.header("anthropic-version"), "2026-10-21")
                XCTAssertNil(body["temperature"], "no sampling settings")
                XCTAssertEqual(body["tools"]?.array?.first?["eager_input_streaming"]?.bool, true)
            case .openAI:
                XCTAssertEqual(sent.path, "/v1/responses", "the Responses API")
                XCTAssertEqual(sent.header("authorization"), "Bearer \(testKeys[.openAI]!)")
                XCTAssertEqual(body["store"]?.bool, false, "nothing kept at OpenAI")
                XCTAssertEqual(body["tools"]?.array?.first?["type"]?.string, "function")
            case .gemini:
                XCTAssertEqual(sent.path, "/v1beta/interactions?alt=sse", "the Interactions API")
                XCTAssertEqual(sent.header("x-goog-api-key"), testKeys[.gemini])
                XCTAssertEqual(body["store"]?.bool, false, "nothing kept at Google")
            }
            XCTAssertEqual(body["stream"]?.bool, true)
            XCTAssertEqual(Set(body["tools"]?.array?.compactMap { $0["name"]?.string } ?? []), Set(VideoAIAssistant.tools.map(\.name)), "\(provider): one tool list, converted")
        }
    }

    func testARequestEditsThroughTheAgentToolsAsOneRun() async throws {
        for provider in VideoAIProvider.allCases {
            try configure(provider)
            let model = try await makeModel()
            let assistant = VideoAIAssistant.of(model)
            server.script(toolReply(provider, name: "split", arguments: #"{"time": 2}"#, input: 200, output: 40),
                          textReply(provider, "I split the clip at 2 seconds.", input: 260, output: 15))
            let before = server.requests.count
            let clips = model.project.timelineClips.count
            assistant.send("Split it at 2 seconds")
            XCTAssertTrue(assistant.isWorking)
            try await waitUntilDone(assistant)
            XCTAssertEqual(model.project.timelineClips.count, max(clips, 1) + 1, "\(provider): split by the agent tool")
            let run = try XCTUnwrap(hub.run(for: model), "\(provider): one run")
            XCTAssertTrue(run.reviewing, "\(provider): its changes wait for Keep or Revert all")
            XCTAssertEqual(run.goal, "Split it at 2 seconds")
            XCTAssertFalse(VideoEditorPanelStore.shared.showsAgentPanel, "\(provider): the run shows in the Assistant panel, not the Agent panel")

            // The chat: the question, the answer with what it did and its tokens.
            let messages = try XCTUnwrap(model.project.aiChat?.messages)
            XCTAssertEqual(messages.map(\.role), [.user, .assistant])
            XCTAssertEqual(messages[1].text, "I split the clip at 2 seconds.")
            XCTAssertEqual(messages[1].usage, VideoAIUsage(input: 460, output: 55), "\(provider): both steps' tokens")
            XCTAssertEqual(messages[1].actions?.count, 1)
            XCTAssertEqual(messages[1].provider, provider)
            XCTAssertNil(messages[1].error)

            // The second request carried the tool's answer, and the hidden
            // reasoning exactly as it came.
            let second = try XCTUnwrap(server.requests.dropFirst(before + 1).first?.json)
            let sent = second.text
            switch provider {
            case .anthropic:
                XCTAssertTrue(sent.contains("SIG-anthropic-123"), "the thinking block's signature")
                XCTAssertTrue(sent.contains(#""tool_use_id":"toolu_1""#))
            case .openAI:
                XCTAssertTrue(sent.contains("ENC-openai-456"), "the encrypted reasoning")
                XCTAssertTrue(sent.contains(#""call_id":"call_1""#) && sent.contains("function_call_output"))
            case .gemini:
                XCTAssertTrue(sent.contains("GSIG-gemini-789"), "the thought signature")
                XCTAssertTrue(sent.contains(#""call_id":"gcall_1""#) && sent.contains("function_result"))
            }

            // Revert all: one step back to before the request; the chat stays.
            hub.revertAll(on: model)
            XCTAssertEqual(model.project.timelineClips.count, clips)
            XCTAssertEqual(model.project.aiChat?.messages.count, 2, "\(provider): the chat isn't an edit")
            VideoAIAssistant.forget(model)
        }
    }

    func testANewRequestKeepsTheLastOnesChanges() async throws {
        try configure(.anthropic)
        let model = try await makeModel()
        let assistant = VideoAIAssistant.of(model)
        server.script(toolReply(.anthropic, name: "split", arguments: #"{"time": 2}"#), textReply(.anthropic, "Split."),
                      toolReply(.anthropic, name: "split", arguments: #"{"time": 4}"#), textReply(.anthropic, "Split again."))
        assistant.send("Split at 2")
        try await waitUntilDone(assistant)
        let first = try XCTUnwrap(hub.run(for: model))
        assistant.send("Now at 4")
        try await waitUntilDone(assistant)
        let second = try XCTUnwrap(hub.run(for: model))
        XCTAssertFalse(first === second, "its own checkpoint")
        hub.revertAll(on: model)
        XCTAssertEqual(model.project.timelineClips.count, 2, "Revert all takes back only the second request")
        VideoAIAssistant.forget(model)
    }

    // MARK: Anthropic Workspace ID (1.21.0)

    /// Settings ▸ AI ▸ Workspace ID goes out as anthropic-workspace-id
    /// (Anthropic only), and Anthropic asking for one says how to fix it.
    func testTheAnthropicWorkspaceID() async throws {
        Settings.videoAIAnthropicWorkspaceID = ""
        server.script(textReply(.anthropic, "Hi."))
        _ = try await VideoAIClient.send(request(.anthropic)) { _ in }
        XCTAssertNil(server.requests.last?.header("anthropic-workspace-id"), "nothing set: not sent")

        Settings.videoAIAnthropicWorkspaceID = " wrkspc_01TEST "
        server.script(textReply(.anthropic, "Hi."))
        _ = try await VideoAIClient.send(request(.anthropic)) { _ in }
        XCTAssertEqual(server.requests.last?.header("anthropic-workspace-id"), "wrkspc_01TEST")
        server.script(textReply(.openAI, "Hi."))
        _ = try await VideoAIClient.send(request(.openAI)) { _ in }
        XCTAssertNil(server.requests.last?.header("anthropic-workspace-id"), "only Anthropic gets it")

        Settings.videoAIAnthropicWorkspaceID = ""
        server.script(.json(.object(["type": .string("error"), "error": .object(["type": .string("invalid_request_error"), "message": .string("This key can be used in more than one workspace: set the anthropic-workspace-id header.")])]), status: 400))
        do {
            _ = try await VideoAIClient.send(request(.anthropic)) { _ in }
            XCTFail("refused")
        } catch {
            XCTAssertEqual(error as? VideoAIError, .needsWorkspace)
            XCTAssertTrue(error.localizedDescription.contains("Settings ▸ AI"), error.localizedDescription)
        }
    }

    // MARK: Errors, timeouts, Stop

    func testErrorsAreClearAndNeverRetriedEndlessly() async throws {
        for provider in VideoAIProvider.allCases {
            func failure(_ responses: MockAIServer.Response...) async -> (VideoAIError?, Int) {
                server.answer = nil
                let before = server.requests.count
                var remaining = responses
                server.answer = { _ in remaining.count > 1 ? remaining.removeFirst() : remaining[0] }
                defer { server.answer = nil }
                do {
                    _ = try await VideoAIClient.send(request(provider)) { _ in }
                    return (nil, server.requests.count - before)
                } catch {
                    return (error as? VideoAIError, server.requests.count - before)
                }
            }
            let wrongKey: MockAIServer.Response = .json(.object(["error": .object(["type": .string("authentication_error"), "message": .string("invalid x-api-key \(testKeys[provider]!)")])]), status: 401)
            var (error, count) = await failure(wrongKey)
            XCTAssertEqual(error, .badKey, "\(provider)")
            XCTAssertEqual(count, 1, "\(provider): a wrong key isn't asked again")
            XCTAssertFalse((error?.localizedDescription ?? "").contains("TESTKEY"))

            (error, count) = await failure(.json(.object(["error": .object(["message": .string("Payment required")])]), status: 402))
            XCTAssertEqual(error, .noCredit, "\(provider): out of credit")
            XCTAssertEqual(count, 1)

            let limited: MockAIServer.Response = .json(.object(["error": .object(["type": .string("rate_limit_error"), "message": .string("Slow down")])]), status: 429, headers: ["retry-after": "0.2"])
            (error, count) = await failure(limited, textReply(provider, "Fine."))
            XCTAssertNil(error, "\(provider): asked once more when it said when")
            XCTAssertEqual(count, 2)
            (error, count) = await failure(limited)
            XCTAssertEqual(error, .rateLimited(retryAfter: 0.2), "\(provider): then it says so")
            XCTAssertEqual(count, 2, "\(provider): never more than one retry")
            (error, count) = await failure(.json(.object(["error": .object(["message": .string("Slow down")])]), status: 429))
            XCTAssertEqual(count, 1, "\(provider): no retry when it doesn't say when")
            (error, count) = await failure(.json(.object(["error": .object(["message": .string("Slow down")])]), status: 429, headers: ["retry-after": "3600"]))
            XCTAssertEqual(count, 1, "\(provider): no retry an hour later")
        }
        // Each provider's own way of saying "no credit".
        var remaining: [MockAIServer.Response] = [.json(.object(["error": .object(["code": .string("insufficient_quota"), "message": .string("You exceeded your current quota")])]), status: 429)]
        server.answer = { _ in remaining[0] }
        do { _ = try await VideoAIClient.send(request(.openAI)) { _ in }; XCTFail() } catch { XCTAssertEqual(error as? VideoAIError, .noCredit, "OpenAI: insufficient_quota") }
        remaining = [.json(.object(["type": .string("error"), "error": .object(["type": .string("invalid_request_error"), "message": .string("Your credit balance is too low to access the Anthropic API.")])]), status: 400)]
        do { _ = try await VideoAIClient.send(request(.anthropic)) { _ in }; XCTFail() } catch { XCTAssertEqual(error as? VideoAIError, .noCredit, "Anthropic: credit balance") }
        remaining = [.events([.object(["type": .string("error"), "error": .object(["type": .string("overloaded_error"), "message": .string("Overloaded")])])])]
        do { _ = try await VideoAIClient.send(request(.anthropic)) { _ in }; XCTFail() } catch { XCTAssertEqual(error as? VideoAIError, .overloaded(retryAfter: nil), "an error in the stream") }
        server.answer = nil
    }

    func testARequestTimesOutCleanly() async throws {
        VideoAIHTTP.idleTimeout = 1
        server.script(MockAIServer.Response(headers: ["Content-Type": "text/event-stream"], hangs: true))
        let started = Date()
        do {
            _ = try await VideoAIClient.send(request(.gemini)) { _ in }
            XCTFail("it can't succeed")
        } catch {
            XCTAssertEqual(error as? VideoAIError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testStopEndsTheRequestNow() async throws {
        try configure(.openAI)
        let model = try await makeModel()
        let assistant = VideoAIAssistant.of(model)
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        var slow = textReply(.openAI, long)
        slow.delay = 0.1
        server.script(slow)
        assistant.send("Tell me a long story")
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(assistant.isWorking)
        XCTAssertFalse(assistant.streaming.isEmpty, "it was streaming")
        let stopped = Date()
        assistant.stop()
        try await waitUntilDone(assistant, seconds: 3)
        XCTAssertLessThan(Date().timeIntervalSince(stopped), 2)
        XCTAssertEqual(model.project.aiChat?.messages.last?.error, L("Stopped."))
        XCTAssertNil(hub.run(for: model), "nothing changed, nothing to review")
        VideoAIAssistant.forget(model)
    }

    func testAWrongKeySaysSoInTheChat() async throws {
        try configure(.gemini)
        let model = try await makeModel()
        let assistant = VideoAIAssistant.of(model)
        server.script(.json(.object(["error": .object(["code": .number(400), "message": .string("API key not valid. Please pass a valid API key."), "status": .string("INVALID_ARGUMENT")])]), status: 400))
        assistant.send("Hi")
        try await waitUntilDone(assistant)
        XCTAssertEqual(model.project.aiChat?.messages.last?.error, VideoAIError.badKey.localizedDescription)
        VideoAIAssistant.forget(model)
    }

    // MARK: The user in charge

    func testTakingOverPausesTheAssistantUntilResume() async throws {
        try configure(.anthropic)
        let model = try await makeModel()
        let assistant = VideoAIAssistant.of(model)
        var slow = toolReply(.anthropic, name: "split", arguments: #"{"time": 2}"#)
        slow.delay = 0.05
        server.script(slow, textReply(.anthropic, "Split."))
        let clips = model.project.timelineClips.count
        assistant.send("Split at 2")
        // Typing to the Assistant isn't taking over.
        assistant.typing = true
        hub.userTookOver(model)
        XCTAssertEqual(hub.run(for: model)?.paused, false, "typing in its panel")
        assistant.typing = false
        // Clicking in the editor is.
        hub.userTookOver(model)
        XCTAssertEqual(hub.run(for: model)?.paused, true)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(model.project.timelineClips.count, clips, "its edit waits")
        XCTAssertEqual(assistant.activity, L("Paused: click Resume to go on"))
        hub.resume(model)
        try await waitUntilDone(assistant)
        XCTAssertEqual(model.project.timelineClips.count, max(clips, 1) + 1, "then goes on")
        VideoAIAssistant.forget(model)
    }

    func testTheWholeVideoToolsUseTheEditorsOwnCommands() async throws {
        let model = try await makeModel()
        func call(_ name: String, _ args: [String: VideoAgentJSON] = [:]) async -> VideoAgentToolResult {
            let tool = VideoAIAssistant.tools.first { $0.name == name } ?? VideoAgentProtocol.shared.tools.first { $0.name == name }!
            return await VideoAgentProtocol.shared.call(tool, .object(args), on: model)
        }
        // Prepare an export: the window opens filled in; nothing is exported.
        XCTAssertFalse(model.isExportPresented)
        let prepared = await call("prepare_export", ["preset": .string("web"), "resolution": .number(720), "format": .string("gif"), "fps": .number(30), "file_name": .string("Product tour.mp4")])
        XCTAssertFalse(prepared.isError, prepared.json.text)
        XCTAssertTrue(model.isExportPresented, "the Export window is open")
        XCTAssertEqual(model.exportSettings.quality, .web)
        XCTAssertEqual(model.exportSettings.resolution, .p720)
        XCTAssertEqual(model.exportSettings.format, .gif)
        XCTAssertEqual(model.exportSettings.fps, 30)
        XCTAssertEqual(model.exportName, "Product tour")
        XCTAssertEqual(prepared.json["exported"]?.bool, false, "the user clicks Export")
        if case .idle = model.exportPhase {} else { XCTFail("nothing exporting") }
        let wrong = await call("prepare_export", ["format": .string("avi")])
        XCTAssertTrue(wrong.isError, "only real choices")
        model.isExportPresented = false

        // Without a transcript or a My Style, they say what's missing.
        let ums = await call("remove_ums")
        XCTAssertTrue(ums.isError)
        XCTAssertTrue(ums.json["error"]?.string?.contains("auto_captions") ?? false)
        let style = await call("apply_my_style")
        XCTAssertTrue(style.isError)
        XCTAssertTrue(style.json["error"]?.string?.contains("My Style") ?? false)
        // A dry run of Auto captions says what it would do, and does nothing.
        let captions = await call("auto_captions", ["dry_run": .bool(true)])
        XCTAssertFalse(captions.isError, captions.json.text)
        XCTAssertEqual(captions.json["would_change"]?.bool, true)
        XCTAssertNil(model.captionTask, "nothing transcribed")

        // Shorten pauses: the editor's command, one ⌘Z step.
        model.project.captions = []
        let depth = model.undoDepth
        let pauses = await call("shorten_pauses", ["dry_run": .bool(true)])
        XCTAssertEqual(model.undoDepth, depth, "a dry run changes nothing")
        if pauses.json["would_change"]?.bool == true {
            _ = await call("shorten_pauses")
            XCTAssertEqual(model.undoDepth, depth + 1)
            XCTAssertEqual(model.undoLabel, "Shorten Pauses")
        }
    }

    func testFramesAreOnlyOfferedWhenAllowed() {
        XCTAssertFalse(Settings.videoAISendsFrames, "off until turned on")
        XCTAssertFalse(VideoAIAssistant.tools.contains { $0.name == "get_frame" })
        XCTAssertFalse(VideoAIAssistant.system(frames: false).contains("get_frame shows"))
        Settings.videoAISendsFrames = true
        XCTAssertTrue(VideoAIAssistant.tools.contains { $0.name == "get_frame" })
        let names = Set(VideoAIAssistant.tools.map(\.name))
        XCTAssertFalse(names.contains("begin_agent_session"), "a request is the session")
        XCTAssertTrue(names.isSuperset(of: ["auto_captions", "remove_ums", "shorten_pauses", "apply_my_style", "prepare_export", "split", "add_tack"]))
        XCTAssertFalse(names.contains { $0.contains("export") && $0 != "prepare_export" }, "no export")
    }

    func testNothingIsOnUntilAKeyAndAProvider() throws {
        XCTAssertFalse(VideoAIAssistant.isConfigured)
        Settings.videoAIProvider = .openAI
        Settings.setVideoAIModel("gpt-6.1-sol", for: .openAI)
        XCTAssertFalse(VideoAIAssistant.isConfigured, "no key")
        try keys.setKey(testKeys[.openAI]!, for: .openAI)
        XCTAssertTrue(VideoAIAssistant.isConfigured)
        Settings.videoAIProvider = nil
        XCTAssertFalse(VideoAIAssistant.isConfigured, "no provider chosen")
    }

    // MARK: Keys go nowhere

    func testKeysNeverLeaveTheKeychain() async throws {
        let model = try await makeModel()
        for provider in VideoAIProvider.allCases {
            try configure(provider)
            let assistant = VideoAIAssistant.of(model)
            // The provider echoes the key back in an error: it's scrubbed.
            server.script(toolReply(provider, name: "add_marker", arguments: #"{"time": 1}"#),
                          .json(.object(["error": .object(["message": .string("Bad request for key \(testKeys[provider]!)")])]), status: 400))
            assistant.send("Mark 1 second")
            try await waitUntilDone(assistant)
            XCTAssertNotNil(model.project.aiChat?.messages.last?.error)
            hub.keep(on: model)
        }
        model.saveDraftNow()
        let document = try VideoProjectDocument(mediaMode: .linked, project: model.project, recording: nil).encoded()
        let package = directory.appendingPathComponent("Chat.lfs", isDirectory: true)
        try VideoProjectPackage.save(model.projectContents, to: package, mode: .linked)
        var places: [(String, Data)] = [("project file", document)]
        for file in (FileManager.default.enumerator(at: package, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? [] where !file.hasDirectoryPath {
            places.append((file.lastPathComponent, (try? Data(contentsOf: file)) ?? Data()))
        }
        let drafts = VideoStorageLocation.root
        for file in (FileManager.default.enumerator(at: drafts, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? [] where !file.hasDirectoryPath && file.pathExtension == "json" {
            places.append(("draft \(file.lastPathComponent)", (try? Data(contentsOf: file)) ?? Data()))
        }
        let defaults = UserDefaults(suiteName: suiteName)!.dictionaryRepresentation()
        places.append(("settings", (try? PropertyListSerialization.data(fromPropertyList: defaults.filter { $0.value is String || $0.value is Data || $0.value is [String: String] || $0.value is Bool }, format: .xml, options: 0)) ?? Data()))
        let export = directory.appendingPathComponent("chat.mp4")
        var settings = VideoExportSettings()
        settings.resolution = .p720
        settings.endCard = false
        try await VideoDemoExporter.export(project: model.project, recording: model.recording, destinationURL: export, settings: settings)
        places.append(("export", try Data(contentsOf: export)))
        let handoff = await VideoHandoffInput.gather(name: "Chat", project: model.project, recording: model.recording, appendedMetadata: [:], exportSettings: settings)
        places.append(("handoff project", try VideoProjectDocument(mediaMode: .linked, project: handoff.project, recording: nil).encoded()))
        places.append(("agent instructions", Data((VideoAgentInstructions.short + VideoAgentInstructions.guide).utf8)))
        XCTAssertGreaterThan(places.count, 4)
        for (name, data) in places {
            for key in testKeys.values {
                XCTAssertNil(data.range(of: Data(key.utf8)), "\(name) holds no key")
                XCTAssertNil(data.range(of: Data(String(key.dropFirst(6)).utf8)), "\(name) holds no part of a key")
            }
        }
        VideoAIAssistant.forget(model)
    }

    // MARK: Saved with the project

    func testTheChatIsSavedWithTheProjectOnlyWhenThereIsOne() async throws {
        try configure(.anthropic)
        let model = try await makeModel()
        XCTAssertLessThan(VideoProjectDocument(mediaMode: .linked, project: model.project, recording: nil).version, 7)
        XCTAssertFalse(String(decoding: try VideoProjectDocument(mediaMode: .linked, project: model.project, recording: nil).encoded(), as: UTF8.self).contains("aiChat"),
                       "no chat: written as 1.19.1 wrote it")
        let assistant = VideoAIAssistant.of(model)
        server.script(toolReply(.anthropic, name: "split", arguments: #"{"time": 2}"#), textReply(.anthropic, "Split."))
        assistant.send("Split at 2")
        try await waitUntilDone(assistant)
        let document = VideoProjectDocument(mediaMode: .linked, project: model.project, recording: nil)
        XCTAssertEqual(document.version, 7)
        XCTAssertTrue(String(decoding: try document.encoded(), as: UTF8.self).contains("\"requires\" : 7"), "1.19.1 and earlier say they need a newer version")
        XCTAssertEqual(VideoProjectDocument.firstVersionOpening(model.project), "1.20.0")
        let read = try VideoProjectDocument.decode(try document.encoded())
        XCTAssertEqual(read.project.aiChat, model.project.aiChat, "read back")

        // ⌘Z steps back through the edit, not the chat.
        model.undo()
        XCTAssertEqual(model.project.aiChat?.messages.count, 2)

        // A Creative Handoff leaves it out unless asked.
        let without = await VideoHandoffInput.gather(name: "Chat", project: model.project, recording: nil, appendedMetadata: [:], exportSettings: VideoExportSettings())
        XCTAssertNil(without.project.aiChat)
        let with = await VideoHandoffInput.gather(name: "Chat", project: model.project, recording: nil, appendedMetadata: [:], exportSettings: VideoExportSettings(), includesAIChat: true)
        XCTAssertEqual(with.project.aiChat, model.project.aiChat)
        XCTAssertFalse(VideoHandoffOptions().includeAIChat, "off by default")

        // New chat: gone, and the project goes back to the earlier format.
        hub.keep(on: model)
        assistant.newChat()
        XCTAssertNil(model.project.aiChat)
        XCTAssertLessThan(VideoProjectDocument(mediaMode: .linked, project: model.project, recording: nil).version, 7)

        // A chat continued after reopening, or with another provider, is
        // sent as plain alternating text.
        let rebuilt = VideoAIAssistant.rebuilt([
            VideoAIChatMessage(role: .assistant, text: "orphan"), VideoAIChatMessage(role: .user, text: "a"), VideoAIChatMessage(role: .user, text: "b"),
            VideoAIChatMessage(role: .assistant, text: "c"), VideoAIChatMessage(role: .assistant, text: "", error: "x"), VideoAIChatMessage(role: .user, text: "d"),
        ], for: .anthropic)
        XCTAssertEqual(rebuilt.map { $0["role"]?.string }, ["user", "assistant"], "starts with the user, ends with the model")
        VideoAIAssistant.forget(model)
    }
}
