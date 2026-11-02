import AppKit
import Foundation
import Network

// MARK: - AI agents (1.19.0): the connection

/// JSON as MCP sends it.
enum VideoAgentJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([VideoAgentJSON])
    case object([String: VideoAgentJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([VideoAgentJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: VideoAgentJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 { try container.encode(Int64(value)) } else { try container.encode(value) }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> VideoAgentJSON? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var array: [VideoAgentJSON]? { if case .array(let a) = self { return a }; return nil }

    /// Something Encodable as JSON.
    static func from<T: Encodable>(_ value: T) -> VideoAgentJSON {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value), let json = try? JSONDecoder().decode(VideoAgentJSON.self, from: data) else { return .null }
        return json
    }

    var data: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }

    var text: String { String(decoding: data, as: UTF8.self) }
}

/// Where the agent connection is, for the `lfstudios-mcp` bridge and the
/// setup snippets: the port and the token, readable by this user only.
struct VideoAgentEndpoint: Codable, Equatable {
    var port: UInt16
    var token: String

    static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LF Studios", isDirectory: true).appendingPathComponent("agent-endpoint.json")
    }

    /// A new random token (Settings ▸ Agent ▸ New token).
    static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func write(to url: URL = Self.file) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func read(from url: URL = Self.file) -> VideoAgentEndpoint? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    static func remove(at url: URL = Self.file) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// An HTTP request, as far as the server needs it.
struct VideoAgentHTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// Parses `data` once it holds a whole request (nil: not yet; throws:
    /// not HTTP, or too big).
    static func parse(_ data: Data, limit: Int = 8 << 20) throws -> VideoAgentHTTPRequest? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > 64 << 10 { throw VideoAgentError.badRequest }
            return nil
        }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { throw VideoAgentError.badRequest }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= limit else { throw VideoAgentError.badRequest }
        let bodyStart = end.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }
        let body = data[bodyStart..<data.index(bodyStart, offsetBy: length)]
        return VideoAgentHTTPRequest(method: String(start[0]), path: String(start[1]), headers: headers, body: Data(body))
    }
}

enum VideoAgentError: Error {
    case badRequest
}

/// Who may talk to the server: only this Mac (loopback), only with the
/// token, only addressed as 127.0.0.1 or localhost (a web page that
/// rebinds a name to 127.0.0.1 still sends its own name, and is refused).
enum VideoAgentGate {
    enum Verdict: Equatable {
        case allowed
        case refused(status: Int, reason: String)
    }

    static func isLoopback(_ endpoint: NWEndpoint?) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback || address == IPv6Address("::ffff:127.0.0.1")
        case .name(let name, _): return name == "localhost" || name == "127.0.0.1" || name == "::1"
        @unknown default: return false
        }
    }

    static func check(_ request: VideoAgentHTTPRequest, peerIsLoopback: Bool, port: UInt16, token: String) -> Verdict {
        guard peerIsLoopback else { return .refused(status: 403, reason: "Only programs on this Mac can connect.") }
        let host = (request.header("host") ?? "").lowercased()
        let allowedHosts = ["127.0.0.1:\(port)", "localhost:\(port)", "[::1]:\(port)", "127.0.0.1", "localhost"]
        guard allowedHosts.contains(host) else { return .refused(status: 403, reason: "Host not allowed.") }
        if let origin = request.header("origin")?.lowercased(), !origin.isEmpty, origin != "null" {
            let local = ["http://127.0.0.1", "http://localhost", "http://[::1]"].contains { origin == $0 || origin.hasPrefix($0 + ":") }
            guard local else { return .refused(status: 403, reason: "Origin not allowed.") }
        }
        guard let authorization = request.header("authorization"), authorization.hasPrefix("Bearer "),
              constantTimeEqual(String(authorization.dropFirst(7)), token), !token.isEmpty else {
            return .refused(status: 401, reason: "A valid token is needed: copy the setup again from LF Studios ▸ Settings ▸ Agent.")
        }
        return .allowed
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var difference: UInt8 = 0
        for i in 0..<x.count { difference |= x[i] ^ y[i] }
        return difference == 0
    }
}

/// The server: HTTP on 127.0.0.1 only, one JSON-RPC request per POST to
/// /mcp (MCP's streamable HTTP, answered as plain JSON).
@MainActor
final class VideoAgentServer {
    static let shared = VideoAgentServer()

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private(set) var token = ""
    /// Answers a JSON-RPC message (nil: a notification, no answer).
    var respond: (_ message: VideoAgentJSON, _ session: String?) async -> VideoAgentJSON? = { _, _ in nil }
    /// Something reached the server (the status dot).
    var onActivity: (_ session: String?) -> Void = { _ in }

    var isRunning: Bool { listener != nil && port != 0 }

    /// Starts on a free port (or `preferred`), and writes the endpoint file.
    func start(token: String, preferred: UInt16? = nil, endpointFile: URL = VideoAgentEndpoint.file) async throws {
        stop(endpointFile: nil)
        self.token = token
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: preferred.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any)
        parameters.acceptLocalOnly = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.serve(connection) }
        }
        final class Once: @unchecked Sendable { var done = false }
        let once = Once()
        let ready: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !once.done else { return }
                    once.done = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    guard !once.done else { return }
                    once.done = true
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .main)
        }
        self.listener = listener
        port = ready
        try VideoAgentEndpoint(port: ready, token: token).write(to: endpointFile)
    }

    func stop(endpointFile: URL? = VideoAgentEndpoint.file) {
        listener?.cancel()
        listener = nil
        port = 0
        for connection in connections { connection.cancel() }
        connections.removeAll()
        if let endpointFile { VideoAgentEndpoint.remove(at: endpointFile) }
    }

    /// A new token: the old one stops working at once.
    func use(token: String, endpointFile: URL = VideoAgentEndpoint.file) {
        self.token = token
        if port != 0 { try? VideoAgentEndpoint(port: port, token: token).write(to: endpointFile) }
    }

    private var connections: [NWConnection] = []

    private func serve(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                do {
                    if let request = try VideoAgentHTTPRequest.parse(buffer) {
                        await self.handle(request, on: connection)
                        return
                    }
                } catch {
                    self.send(status: 400, body: Data("Bad request".utf8), on: connection)
                    return
                }
                if complete || error != nil { self.close(connection) } else { self.receive(connection, buffer: buffer) }
            }
        }
    }

    private func handle(_ request: VideoAgentHTTPRequest, on connection: NWConnection) async {
        let verdict = VideoAgentGate.check(request, peerIsLoopback: VideoAgentGate.isLoopback(connection.currentPath?.remoteEndpoint ?? connection.endpoint), port: port, token: token)
        if case .refused(let status, let reason) = verdict {
            send(status: status, body: Data(reason.utf8), on: connection)
            return
        }
        guard request.path == "/mcp" || request.path.hasPrefix("/mcp?") else {
            send(status: 404, body: Data("Not found".utf8), on: connection)
            return
        }
        let session = request.header("mcp-session-id")
        switch request.method {
        case "POST":
            guard let message = try? JSONDecoder().decode(VideoAgentJSON.self, from: request.body) else {
                send(status: 400, body: VideoAgentJSON.object(["jsonrpc": .string("2.0"), "id": .null, "error": .object(["code": .number(-32700), "message": .string("Parse error")])]).data, json: true, on: connection)
                return
            }
            onActivity(session)
            var extra: [String: String] = [:]
            if message["method"]?.string == "initialize" { extra["Mcp-Session-Id"] = UUID().uuidString }
            if let answer = await respond(message, session ?? extra["Mcp-Session-Id"]) {
                send(status: 200, body: answer.data, json: true, headers: extra, on: connection)
            } else {
                send(status: 202, body: Data(), on: connection)
            }
        case "DELETE":
            onActivity(nil)
            send(status: 200, body: Data(), on: connection)
        default:
            // No server-sent events: answers come with each POST.
            send(status: 405, body: Data("Method not allowed".utf8), headers: ["Allow": "POST, DELETE"], on: connection)
        }
    }

    private func send(status: Int, body: Data, json: Bool = false, headers: [String: String] = [:], on connection: NWConnection) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        default: reason = "Method Not Allowed"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        head += "Content-Type: \(json ? "application/json" : "text/plain; charset=utf-8")\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(connection) }
        })
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }
}
