import Foundation

// MARK: - The built-in assistant (1.20.0): talking to the providers
//
// Straight to each provider over HTTPS with the user's own key, nothing in
// between. Each provider's own API for tool calling: Anthropic Messages,
// OpenAI Responses, Gemini Interactions (the ones their docs recommend),
// all streamed, all stateless (the app keeps the conversation and sends it
// each time: nothing is stored at the provider for later).

/// A tool as the providers see it: the 1.19 agent tools, converted.
struct VideoAITool {
    let name: String
    let description: String
    /// A JSON Schema object.
    let schema: VideoAgentJSON

    init(_ tool: VideoAgentTool) {
        name = tool.name
        description = tool.description
        schema = tool.schema["inputSchema"] ?? .object(["type": .string("object"), "properties": .object([:])])
    }
}

/// Tokens a reply used, as the provider reported them.
struct VideoAIUsage: Codable, Equatable {
    var input = 0
    var output = 0

    var total: Int { input + output }

    static func + (a: VideoAIUsage, b: VideoAIUsage) -> VideoAIUsage {
        VideoAIUsage(input: a.input + b.input, output: a.output + b.output)
    }
}

/// The model asked for a tool.
struct VideoAIToolCall: Equatable {
    let id: String
    let name: String
    /// nil: its arguments weren't valid JSON (the model is told so).
    let arguments: VideoAgentJSON?
}

/// One answer from the model.
struct VideoAIReply {
    enum Stop: Equatable {
        case done
        case tools
        /// The provider declined (its safety rules).
        case refused
        /// It ran out of room before finishing.
        case truncated
    }

    /// What goes back into the conversation, exactly as the provider sent
    /// it (thinking, reasoning and thought signatures included).
    var items: [VideoAgentJSON] = []
    var text = ""
    var calls: [VideoAIToolCall] = []
    var usage = VideoAIUsage()
    var stop: Stop = .done
}

/// What went wrong, said plainly.
enum VideoAIError: Error, Equatable, LocalizedError {
    case noKey
    case badKey
    case noCredit
    case rateLimited(retryAfter: Double?)
    case overloaded(retryAfter: Double?)
    case modelUnavailable(String)
    case timedOut
    case offline
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .noKey: return L("Add an API key in Settings ▸ AI first.")
        case .badKey: return L("The API key was refused. Check it in Settings ▸ AI, or make a new one.")
        case .noCredit: return L("Your account with this provider is out of credit. Add credit on its website, then try again.")
        case .rateLimited: return L("The provider is limiting how fast you can send requests. Wait a minute, then try again.")
        case .overloaded: return L("The provider is busy right now. Try again in a moment.")
        case .modelUnavailable(let model): return L("The model “\(model)” isn't available with this key. Choose another one.")
        case .timedOut: return L("The provider didn't answer in time. Try again.")
        case .offline: return L("LF Studios couldn't reach the provider. Check your internet connection.")
        case .provider(let message): return L("The provider said: \(message)")
        }
    }

    /// When the provider said to come back (seconds).
    var retryAfter: Double? {
        switch self {
        case .rateLimited(let after), .overloaded(let after): return after
        default: return nil
        }
    }
}

/// A model in the menu.
struct VideoAIModel: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    /// When the provider made it (seconds since 1970), when it says.
    var created: Double?
}

// MARK: - HTTP

enum VideoAIHTTP {
    /// Each provider's address. Tests point these at local mock servers;
    /// anything else must be HTTPS.
    nonisolated(unsafe) static var baseURLs: [VideoAIProvider: URL] = defaultBaseURLs
    static let defaultBaseURLs: [VideoAIProvider: URL] = [
        .anthropic: URL(string: "https://api.anthropic.com")!,
        .openAI: URL(string: "https://api.openai.com")!,
        .gemini: URL(string: "https://generativelanguage.googleapis.com")!,
    ]
    static let anthropicVersion = "2026-10-21"
    static let geminiRevision = "2026-05-20"
    /// Seconds without a byte before giving up, and for a whole reply.
    nonisolated(unsafe) static var idleTimeout: TimeInterval = 90
    nonisolated(unsafe) static var replyTimeout: TimeInterval = 600

    /// No cookies, no cache, nothing on disk.
    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = idleTimeout
        configuration.timeoutIntervalForResource = replyTimeout
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    static func url(_ provider: VideoAIProvider, _ path: String, query: [URLQueryItem] = []) throws -> URL {
        let base = baseURLs[provider] ?? defaultBaseURLs[provider]!
        let local = ["127.0.0.1", "localhost"].contains(base.host ?? "")
        guard base.scheme == "https" || local else { throw VideoAIError.provider("not HTTPS") }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    static func request(_ provider: VideoAIProvider, _ path: String, key: String, query: [URLQueryItem] = [], body: VideoAgentJSON? = nil) throws -> URLRequest {
        var request = URLRequest(url: try url(provider, path, query: query))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        switch provider {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        case .openAI:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .gemini:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            request.setValue(geminiRevision, forHTTPHeaderField: "Api-Revision")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.data
        }
        return request
    }

    /// A plain request's JSON answer.
    static func json(_ request: URLRequest, provider: VideoAIProvider, model: String? = nil) async throws -> VideoAgentJSON {
        let (data, response) = try await mapped { try await session.data(for: request) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw error(status: status, response: response as? HTTPURLResponse, body: data, provider: provider, model: model) }
        guard let json = try? JSONDecoder().decode(VideoAgentJSON.self, from: data) else { throw VideoAIError.provider("an answer that wasn't JSON") }
        return json
    }

    /// A streamed answer: each server-sent event's JSON, in order.
    static func stream(_ request: URLRequest, provider: VideoAIProvider, model: String, event: (VideoAgentJSON) throws -> Void) async throws {
        let (bytes, response) = try await mapped { try await session.bytes(for: request) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 65_536 { break }
            }
            throw error(status: status, response: response as? HTTPURLResponse, body: body, provider: provider, model: model)
        }
        try await mapped {
            // Every provider sends one JSON object per `data:` line; its own
            // `type` (or `event_type`) says what it is.
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard !payload.isEmpty, payload != "[DONE]", let json = try? JSONDecoder().decode(VideoAgentJSON.self, from: Data(payload.utf8)) else { continue }
                try event(json)
            }
        }
    }

    /// Network failures in plain words; Stop stays a cancellation.
    private static func mapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw VideoAIError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: throw VideoAIError.offline
            default: throw VideoAIError.provider(VideoAIKeys.scrubbed(error.localizedDescription))
            }
        }
    }

    /// An HTTP error answer, as a VideoAIError.
    static func error(status: Int, response: HTTPURLResponse?, body: Data, provider: VideoAIProvider, model: String?) -> VideoAIError {
        let json = try? JSONDecoder().decode(VideoAgentJSON.self, from: body)
        let detail = json?["error"]
        let message = VideoAIKeys.scrubbed(detail?["message"]?.string ?? json?["message"]?.string ?? String(decoding: body.prefix(300), as: UTF8.self))
        let code = (detail?["type"]?.string ?? "") + " " + (detail?["code"]?.string ?? "") + " " + (detail?["status"]?.string ?? "")
        let after = retryAfter(response)
        let lower = message.lowercased()
        switch status {
        case 401: return .badKey
        case 402: return .noCredit
        case 429:
            if code.contains("insufficient_quota") || lower.contains("billing") || lower.contains("credit") { return .noCredit }
            return .rateLimited(retryAfter: after)
        case 404: return .modelUnavailable(model ?? "")
        case 500, 502, 503, 504, 529: return .overloaded(retryAfter: after)
        default:
            if lower.contains("credit balance") || code.contains("billing") { return .noCredit }
            if lower.contains("api key") && (lower.contains("not valid") || lower.contains("invalid")) { return .badKey }
            if status == 403, provider == .gemini, code.contains("permission") { return .badKey }
            return .provider(message.isEmpty ? "HTTP \(status)" : message)
        }
    }

    static func retryAfter(_ response: HTTPURLResponse?) -> Double? {
        if let ms = response?.value(forHTTPHeaderField: "retry-after-ms").flatMap(Double.init) { return ms / 1000 }
        return response?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
    }

    /// A streamed error event's JSON, as a VideoAIError.
    static func streamError(_ json: VideoAgentJSON) -> VideoAIError {
        let detail = json["error"] ?? json
        let kind = (detail["type"]?.string ?? detail["code"]?.string ?? "").lowercased()
        let message = VideoAIKeys.scrubbed(detail["message"]?.string ?? kind)
        if kind.contains("overloaded") || kind.contains("unavailable") || kind.contains("api_error") { return .overloaded(retryAfter: nil) }
        if kind.contains("rate_limit") || kind.contains("too_many") { return .rateLimited(retryAfter: nil) }
        if kind.contains("insufficient_quota") || kind.contains("billing") || kind.contains("payment") { return .noCredit }
        if kind.contains("authentication") || kind.contains("invalid_api_key") { return .badKey }
        if kind.contains("deadline") || kind.contains("timeout") { return .timedOut }
        return .provider(message)
    }
}

// MARK: - Requests

/// One request to a model: the conversation so far, the tools, and where
/// streamed text goes.
struct VideoAIRequest {
    let provider: VideoAIProvider
    let model: String
    let key: String
    let system: String
    let tools: [VideoAITool]
    let items: [VideoAgentJSON]
}

enum VideoAIClient {
    /// Room for an answer (tokens; reasoning included where it counts).
    static let maxOutputTokens = 32_000

    /// One reply, streamed: `text` gets each piece as it arrives. A busy
    /// provider that says when to come back (within 20 s) is asked once
    /// more; nothing is retried beyond that.
    static func send(_ request: VideoAIRequest, text: @escaping (String) -> Void) async throws -> VideoAIReply {
        do {
            return try await sendOnce(request, text: text)
        } catch let error as VideoAIError {
            guard let after = error.retryAfter, after <= 20 else { throw error }
            try await Task.sleep(nanoseconds: UInt64(max(after, 0.2) * 1_000_000_000))
            return try await sendOnce(request, text: text)
        }
    }

    private static func sendOnce(_ request: VideoAIRequest, text: @escaping (String) -> Void) async throws -> VideoAIReply {
        switch request.provider {
        case .anthropic: return try await Anthropic.send(request, text: text)
        case .openAI: return try await OpenAI.send(request, text: text)
        case .gemini: return try await Gemini.send(request, text: text)
        }
    }

    /// The user's message (and frames, when they're sent).
    static func userItem(_ provider: VideoAIProvider, text: String, images: [Data] = []) -> VideoAgentJSON {
        switch provider {
        case .anthropic:
            var content: [VideoAgentJSON] = images.map { Anthropic.image($0) }
            content.append(.object(["type": .string("text"), "text": .string(text)]))
            return .object(["role": .string("user"), "content": .array(content)])
        case .openAI:
            var content: [VideoAgentJSON] = [.object(["type": .string("input_text"), "text": .string(text)])]
            content += images.map { OpenAI.image($0) }
            return .object(["role": .string("user"), "content": .array(content)])
        case .gemini:
            var content: [VideoAgentJSON] = [.object(["type": .string("text"), "text": .string(text)])]
            content += images.map { Gemini.image($0) }
            return .object(["type": .string("user_input"), "content": .array(content)])
        }
    }

    /// An earlier answer as plain text (a chat opened again, or moved to
    /// another provider or model).
    static func assistantItem(_ provider: VideoAIProvider, text: String) -> VideoAgentJSON {
        switch provider {
        case .anthropic:
            return .object(["role": .string("assistant"), "content": .array([.object(["type": .string("text"), "text": .string(text)])])])
        case .openAI:
            return .object(["role": .string("assistant"), "content": .array([.object(["type": .string("output_text"), "text": .string(text)])])])
        case .gemini:
            return .object(["type": .string("model_output"), "content": .array([.object(["type": .string("text"), "text": .string(text)])])])
        }
    }

    /// The tools' answers, to send back.
    static func resultItems(_ provider: VideoAIProvider, _ results: [(VideoAIToolCall, VideoAgentToolResult)]) -> [VideoAgentJSON] {
        switch provider {
        case .anthropic:
            let blocks: [VideoAgentJSON] = results.map { call, result in
                var content: [VideoAgentJSON] = [.object(["type": .string("text"), "text": .string(result.json.text)])]
                if let image = result.image { content.append(Anthropic.image(image)) }
                return .object(["type": .string("tool_result"), "tool_use_id": .string(call.id), "content": .array(content), "is_error": .bool(result.isError)])
            }
            return [.object(["role": .string("user"), "content": .array(blocks)])]
        case .openAI:
            return results.map { call, result in
                let output: VideoAgentJSON
                if let image = result.image {
                    output = .array([.object(["type": .string("input_text"), "text": .string(result.json.text)]), OpenAI.image(image)])
                } else {
                    output = .string(result.json.text)
                }
                return .object(["type": .string("function_call_output"), "call_id": .string(call.id), "output": output])
            }
        case .gemini:
            return results.map { call, result in
                var content: [VideoAgentJSON] = [.object(["type": .string("text"), "text": .string(result.json.text)])]
                if let image = result.image { content.append(Gemini.image(image)) }
                return .object(["type": .string("function_result"), "name": .string(call.name), "call_id": .string(call.id), "result": .array(content)])
            }
        }
    }

    /// Parses a tool call's arguments (nil: not valid JSON; empty: {}).
    static func arguments(_ text: String) -> VideoAgentJSON? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .object([:]) }
        guard let json = try? JSONDecoder().decode(VideoAgentJSON.self, from: Data(trimmed.utf8)), case .object = json else { return nil }
        return json
    }

    // MARK: Anthropic (Messages API)

    enum Anthropic {
        static func image(_ png: Data) -> VideoAgentJSON {
            .object(["type": .string("image"), "source": .object(["type": .string("base64"), "media_type": .string("image/png"), "data": .string(png.base64EncodedString())])])
        }

        static func body(_ request: VideoAIRequest) -> VideoAgentJSON {
            .object([
                "model": .string(request.model),
                "max_tokens": .number(Double(maxOutputTokens)),
                "system": .string(request.system),
                "messages": .array(request.items),
                "tools": .array(request.tools.map { tool in
                    .object(["name": .string(tool.name), "description": .string(tool.description), "input_schema": tool.schema, "eager_input_streaming": .bool(true)])
                }),
                "stream": .bool(true),
            ])
        }

        static func send(_ request: VideoAIRequest, text: @escaping (String) -> Void) async throws -> VideoAIReply {
            let http = try VideoAIHTTP.request(.anthropic, "v1/messages", key: request.key, body: body(request))
            var blocks: [Int: [String: VideoAgentJSON]] = [:]
            var partial: [Int: String] = [:]
            var reply = VideoAIReply()
            var stopReason = ""
            var invalid: Set<Int> = []
            try await VideoAIHTTP.stream(http, provider: .anthropic, model: request.model) { event in
                switch event["type"]?.string {
                case "message_start":
                    let usage = event["message"]?["usage"]
                    reply.usage.input = Int((usage?["input_tokens"]?.double ?? 0) + (usage?["cache_creation_input_tokens"]?.double ?? 0) + (usage?["cache_read_input_tokens"]?.double ?? 0))
                    reply.usage.output = Int(usage?["output_tokens"]?.double ?? 0)
                case "content_block_start":
                    guard let index = event["index"]?.double.map(Int.init), case .object(let block)? = event["content_block"] else { return }
                    blocks[index] = block
                case "content_block_delta":
                    guard let index = event["index"]?.double.map(Int.init), let delta = event["delta"] else { return }
                    switch delta["type"]?.string {
                    case "text_delta":
                        let piece = delta["text"]?.string ?? ""
                        let joined = (blocks[index]?["text"]?.string ?? "") + piece
                        blocks[index]?["text"] = .string(joined)
                        reply.text += piece
                        text(piece)
                    case "input_json_delta":
                        partial[index, default: ""] += delta["partial_json"]?.string ?? ""
                    case "thinking_delta":
                        let joined = (blocks[index]?["thinking"]?.string ?? "") + (delta["thinking"]?.string ?? "")
                        blocks[index]?["thinking"] = .string(joined)
                    case "signature_delta":
                        let joined = (blocks[index]?["signature"]?.string ?? "") + (delta["signature"]?.string ?? "")
                        blocks[index]?["signature"] = .string(joined)
                    default:
                        break
                    }
                case "content_block_stop":
                    guard let index = event["index"]?.double.map(Int.init), blocks[index]?["type"]?.string == "tool_use" else { return }
                    if let parsed = arguments(partial[index] ?? "") {
                        blocks[index]?["input"] = parsed
                    } else {
                        // Sent back as it can be, answered with an error.
                        blocks[index]?["input"] = .object([:])
                        invalid.insert(index)
                    }
                case "message_delta":
                    stopReason = event["delta"]?["stop_reason"]?.string ?? stopReason
                    if let output = event["usage"]?["output_tokens"]?.double { reply.usage.output = Int(output) }
                    if let input = event["usage"]?["input_tokens"]?.double, input > 0 {
                        reply.usage.input = Int(input + (event["usage"]?["cache_creation_input_tokens"]?.double ?? 0) + (event["usage"]?["cache_read_input_tokens"]?.double ?? 0))
                    }
                case "error":
                    throw VideoAIHTTP.streamError(event)
                default:
                    break
                }
            }
            let ordered = blocks.keys.sorted().compactMap { blocks[$0] }
            reply.items = [.object(["role": .string("assistant"), "content": .array(ordered.map { .object($0) })])]
            for index in blocks.keys.sorted() {
                guard let block = blocks[index], block["type"]?.string == "tool_use", let id = block["id"]?.string, let name = block["name"]?.string else { continue }
                reply.calls.append(VideoAIToolCall(id: id, name: name, arguments: invalid.contains(index) ? nil : block["input"]))
            }
            switch stopReason {
            case "refusal": reply.stop = .refused
            case "max_tokens": reply.stop = .truncated
            default: reply.stop = reply.calls.isEmpty ? .done : .tools
            }
            return reply
        }

        static func models(key: String) async throws -> [VideoAIModel] {
            let json = try await VideoAIHTTP.json(try VideoAIHTTP.request(.anthropic, "v1/models", key: key, query: [URLQueryItem(name: "limit", value: "1000")]), provider: .anthropic)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            return (json["data"]?.array ?? []).compactMap { model in
                guard let id = model["id"]?.string else { return nil }
                let date = model["created_at"]?.string.flatMap { formatter.date(from: $0) ?? plain.date(from: $0) }
                return VideoAIModel(id: id, name: model["display_name"]?.string ?? id, created: date?.timeIntervalSince1970)
            }
        }
    }

    // MARK: OpenAI (Responses API)

    enum OpenAI {
        static func image(_ png: Data) -> VideoAgentJSON {
            .object(["type": .string("input_image"), "image_url": .string("data:image/png;base64,\(png.base64EncodedString())")])
        }

        static func body(_ request: VideoAIRequest) -> VideoAgentJSON {
            .object([
                "model": .string(request.model),
                "instructions": .string(request.system),
                "input": .array(request.items),
                "tools": .array(request.tools.map { tool in
                    .object(["type": .string("function"), "name": .string(tool.name), "description": .string(tool.description), "parameters": tool.schema, "strict": .bool(false)])
                }),
                "max_output_tokens": .number(Double(maxOutputTokens)),
                "stream": .bool(true),
                // Nothing kept at OpenAI: the app sends the conversation,
                // reasoning included (encrypted), each time.
                "store": .bool(false),
            ])
        }

        static func send(_ request: VideoAIRequest, text: @escaping (String) -> Void) async throws -> VideoAIReply {
            let http = try VideoAIHTTP.request(.openAI, "v1/responses", key: request.key, body: body(request))
            var items: [Int: VideoAgentJSON] = [:]
            var reply = VideoAIReply()
            var status = ""
            var incomplete = ""
            try await VideoAIHTTP.stream(http, provider: .openAI, model: request.model) { event in
                switch event["type"]?.string {
                case "response.output_text.delta":
                    let piece = event["delta"]?.string ?? ""
                    reply.text += piece
                    text(piece)
                case "response.output_item.done":
                    guard let index = event["output_index"]?.double.map(Int.init), let item = event["item"] else { return }
                    items[index] = item
                case "response.completed", "response.incomplete":
                    let response = event["response"]
                    status = response?["status"]?.string ?? (event["type"]?.string == "response.completed" ? "completed" : "incomplete")
                    incomplete = response?["incomplete_details"]?["reason"]?.string ?? ""
                    if let usage = response?["usage"] {
                        reply.usage = VideoAIUsage(input: Int(usage["input_tokens"]?.double ?? 0), output: Int(usage["output_tokens"]?.double ?? 0))
                    }
                case "response.failed":
                    throw VideoAIHTTP.streamError(event["response"]?["error"].map { .object(["error": $0]) } ?? event)
                case "error":
                    throw VideoAIHTTP.streamError(event)
                default:
                    break
                }
            }
            reply.items = items.keys.sorted().compactMap { items[$0] }
            var refused = false
            for item in reply.items {
                if item["type"]?.string == "function_call", let id = item["call_id"]?.string, let name = item["name"]?.string {
                    reply.calls.append(VideoAIToolCall(id: id, name: name, arguments: arguments(item["arguments"]?.string ?? "")))
                }
                if item["type"]?.string == "message", (item["content"]?.array ?? []).contains(where: { $0["type"]?.string == "refusal" }) { refused = true }
            }
            if refused, reply.calls.isEmpty {
                reply.stop = .refused
            } else if status == "incomplete", incomplete == "max_output_tokens" {
                reply.stop = .truncated
            } else if status == "incomplete", incomplete == "content_filter" {
                reply.stop = .refused
            } else {
                reply.stop = reply.calls.isEmpty ? .done : .tools
            }
            return reply
        }

        static func models(key: String) async throws -> [VideoAIModel] {
            let json = try await VideoAIHTTP.json(try VideoAIHTTP.request(.openAI, "v1/models", key: key), provider: .openAI)
            return (json["data"]?.array ?? []).compactMap { model in
                guard let id = model["id"]?.string else { return nil }
                return VideoAIModel(id: id, name: id, created: model["created"]?.double)
            }
        }
    }

    // MARK: Gemini (Interactions API)

    enum Gemini {
        static func image(_ png: Data) -> VideoAgentJSON {
            .object(["type": .string("image"), "mime_type": .string("image/png"), "data": .string(png.base64EncodedString())])
        }

        static func body(_ request: VideoAIRequest) -> VideoAgentJSON {
            .object([
                "model": .string(request.model),
                "system_instruction": .string(request.system),
                "input": .array(request.items),
                "tools": .array(request.tools.map { tool in
                    .object(["type": .string("function"), "name": .string(tool.name), "description": .string(tool.description), "parameters": tool.schema])
                }),
                "stream": .bool(true),
                // Nothing kept at Google: every step (thought signatures
                // included) is sent back as it came.
                "store": .bool(false),
            ])
        }

        static func send(_ request: VideoAIRequest, text: @escaping (String) -> Void) async throws -> VideoAIReply {
            let http = try VideoAIHTTP.request(.gemini, "v1beta/interactions", key: request.key, query: [URLQueryItem(name: "alt", value: "sse")], body: body(request))
            var steps: [Int: [String: VideoAgentJSON]] = [:]
            var partial: [Int: String] = [:]
            var reply = VideoAIReply()
            var status = ""
            try await VideoAIHTTP.stream(http, provider: .gemini, model: request.model) { event in
                switch event["event_type"]?.string {
                case "step.start":
                    guard let index = event["index"]?.double.map(Int.init), case .object(let step)? = event["step"] else { return }
                    steps[index] = step
                    if step["type"]?.string == "model_output", let start = step["content"]?.array?.first?["text"]?.string, !start.isEmpty {
                        reply.text += start
                        text(start)
                    }
                case "step.delta":
                    guard let index = event["index"]?.double.map(Int.init), let delta = event["delta"] else { return }
                    switch delta["type"]?.string {
                    case "text":
                        let piece = delta["text"]?.string ?? ""
                        var content = steps[index]?["content"]?.array ?? []
                        if let last = content.last, last["type"]?.string == "text" {
                            content[content.count - 1] = .object(["type": .string("text"), "text": .string((last["text"]?.string ?? "") + piece)])
                        } else {
                            content.append(.object(["type": .string("text"), "text": .string(piece)]))
                        }
                        steps[index]?["content"] = .array(content)
                        reply.text += piece
                        text(piece)
                    case "thought_signature":
                        let joined = (steps[index]?["signature"]?.string ?? "") + (delta["signature"]?.string ?? "")
                        steps[index]?["signature"] = .string(joined)
                    case "thought_summary":
                        if let content = delta["content"] {
                            let joined = (steps[index]?["summary"]?.array ?? []) + [content]
                            steps[index]?["summary"] = .array(joined)
                        }
                    case "arguments_delta":
                        partial[index, default: ""] += delta["arguments"]?.string ?? ""
                    default:
                        break
                    }
                case "step.stop":
                    guard let index = event["index"]?.double.map(Int.init), steps[index]?["type"]?.string == "function_call", let text = partial[index] else { return }
                    steps[index]?["arguments"] = arguments(text) ?? .object([:])
                    if arguments(text) == nil { steps[index]?["_invalid"] = .bool(true) }
                case "interaction.completed", "interaction.status_update":
                    let interaction = event["interaction"]
                    status = interaction?["status"]?.string ?? event["status"]?.string ?? status
                    if let usage = interaction?["usage"] {
                        reply.usage = VideoAIUsage(input: Int(usage["total_input_tokens"]?.double ?? 0),
                                                   output: Int((usage["total_output_tokens"]?.double ?? 0) + (usage["total_thought_tokens"]?.double ?? 0)))
                    }
                case "error":
                    throw VideoAIHTTP.streamError(event)
                default:
                    break
                }
            }
            for index in steps.keys.sorted() {
                guard var step = steps[index] else { continue }
                let invalid = step.removeValue(forKey: "_invalid") != nil
                reply.items.append(.object(step))
                if step["type"]?.string == "function_call", let id = step["id"]?.string, let name = step["name"]?.string {
                    reply.calls.append(VideoAIToolCall(id: id, name: name, arguments: invalid ? nil : step["arguments"] ?? .object([:])))
                }
            }
            switch status {
            case "incomplete": reply.stop = .truncated
            case "failed": throw VideoAIError.provider(L("the request failed"))
            default: reply.stop = reply.calls.isEmpty ? .done : .tools
            }
            return reply
        }

        static func models(key: String) async throws -> [VideoAIModel] {
            var found: [VideoAIModel] = []
            var page: String?
            for _ in 0..<5 {
                var query = [URLQueryItem(name: "pageSize", value: "1000")]
                if let page { query.append(URLQueryItem(name: "pageToken", value: page)) }
                let json = try await VideoAIHTTP.json(try VideoAIHTTP.request(.gemini, "v1beta/models", key: key, query: query), provider: .gemini)
                for model in json["models"]?.array ?? [] {
                    guard let name = model["name"]?.string else { continue }
                    let methods = (model["supportedGenerationMethods"]?.array ?? model["supportedActions"]?.array ?? []).compactMap(\.string)
                    // Only what can hold a conversation with tools.
                    guard methods.contains("generateContent") else { continue }
                    let id = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
                    found.append(VideoAIModel(id: id, name: model["displayName"]?.string ?? id, created: nil))
                }
                page = json["nextPageToken"]?.string
                if page?.isEmpty ?? true { break }
            }
            return found
        }
    }
}

// MARK: - Models

/// The model menus: each provider's own list, only chat models that can
/// call tools, with a default chosen by a rule (never a fixed name).
enum VideoAIModels {
    /// Words in the names of models that can't hold a conversation with
    /// tools (pictures, sound, speech, embeddings, moderation…).
    static let excluded: [VideoAIProvider: [String]] = [
        .anthropic: [],
        .openAI: ["image", "dall-e", "realtime", "live", "audio", "transcribe", "tts", "whisper", "speech", "embedding", "moderation", "search",
                  "computer-use", "codex", "instruct", "davinci", "babbage", "translate", "gpt-3.5", "sora"],
        .gemini: ["image", "imagen", "veo", "lyria", "tts", "audio", "speech", "embedding", "live", "native", "robotics", "computer-use", "aqa",
                  "nano-banana", "learnlm", "gemma", "deep-research", "antigravity"],
    ]

    static func usable(_ provider: VideoAIProvider, _ models: [VideoAIModel]) -> [VideoAIModel] {
        let words = excluded[provider] ?? []
        var seen: Set<String> = []
        let kept = models.filter { model in
            let id = model.id.lowercased()
            guard seen.insert(id).inserted, !words.contains(where: { id.contains($0) }) else { return false }
            switch provider {
            case .anthropic: return id.hasPrefix("claude-")
            case .openAI: return id.hasPrefix("gpt-") || id.range(of: #"^o\d"#, options: .regularExpression) != nil
            case .gemini: return id.hasPrefix("gemini-")
            }
        }
        return kept.sorted { a, b in
            if let x = a.created, let y = b.created, x != y { return x > y }
            let (va, vb) = (version(a.id), version(b.id))
            if va != vb { return va > vb }
            return a.id < b.id
        }
    }

    /// The default: Anthropic's newest Opus, OpenAI's newest full GPT,
    /// Gemini's newest stable Pro, else the newest there is.
    static func defaultModel(_ provider: VideoAIProvider, _ models: [VideoAIModel]) -> VideoAIModel? {
        let usable = usable(provider, models)
        let preferred: (VideoAIModel) -> Bool
        switch provider {
        case .anthropic:
            preferred = { $0.id.contains("opus") }
        case .openAI:
            preferred = { m in m.id.hasPrefix("gpt-") && !["mini", "nano", "cyber"].contains { m.id.contains($0) } }
        case .gemini:
            preferred = { m in m.id.contains("-pro") && !m.id.contains("preview") && !m.id.contains("exp") }
        }
        return usable.first(where: preferred) ?? usable.first
    }

    /// "gemini-3.8-flash" → 3.8; "claude-opus-5-5" → 5.5; 0 when none.
    static func version(_ id: String) -> Double {
        guard let range = id.range(of: #"\d+([.-]\d+)?"#, options: .regularExpression) else { return 0 }
        return Double(id[range].replacingOccurrences(of: "-", with: ".")) ?? 0
    }

    /// Each provider's list (all of it; `usable` filters).
    static func fetch(_ provider: VideoAIProvider, key: String) async throws -> [VideoAIModel] {
        switch provider {
        case .anthropic: return try await VideoAIClient.Anthropic.models(key: key)
        case .openAI: return try await VideoAIClient.OpenAI.models(key: key)
        case .gemini: return try await VideoAIClient.Gemini.models(key: key)
        }
    }
}
