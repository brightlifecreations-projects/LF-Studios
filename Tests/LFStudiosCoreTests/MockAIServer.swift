import Foundation
import Network
@testable import LFStudiosCore

/// A stand-in for an AI provider on 127.0.0.1 (1.20.0 tests): it records
/// each request and answers from a script. No real provider, no real key.
final class MockAIServer: @unchecked Sendable {
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data

        var json: VideoAgentJSON? { try? JSONDecoder().decode(VideoAgentJSON.self, from: body) }
        func header(_ name: String) -> String? { headers[name.lowercased()] }
    }

    struct Response {
        var status = 200
        var headers: [String: String] = [:]
        /// Sent one after another, `delay` seconds apart.
        var chunks: [Data] = []
        var delay: TimeInterval = 0
        /// Headers, then nothing (a provider that stops answering).
        var hangs = false

        static func json(_ json: VideoAgentJSON, status: Int = 200, headers: [String: String] = [:]) -> Response {
            Response(status: status, headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a }, chunks: [json.data])
        }

        /// Server-sent events, one `data:` line each (with `event:` lines
        /// when `named`).
        static func events(_ events: [VideoAgentJSON], named: Bool = true, delay: TimeInterval = 0) -> Response {
            let chunks = events.map { event -> Data in
                let name = event["type"]?.string ?? event["event_type"]?.string
                return Data(((named && name != nil ? "event: \(name!)\n" : "") + "data: \(event.text)\n\n").utf8)
            }
            return Response(headers: ["Content-Type": "text/event-stream"], chunks: chunks, delay: delay)
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "MockAIServer")
    private let lock = NSLock()
    private var recorded: [Request] = []
    private var script: [Response] = []
    /// Answers in order; the last one repeats.
    var answer: ((Request) -> Response)?

    var requests: [Request] { lock.withLock { recorded } }
    var url: URL { URL(string: "http://127.0.0.1:\(listener.port?.rawValue ?? 0)")! }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
    }

    deinit { listener.cancel() }

    /// The answers, in order (the last one repeats).
    func script(_ responses: Response...) {
        lock.withLock { script = responses }
    }

    private func next(for request: Request) -> Response {
        if let answer { return answer(request) }
        return lock.withLock {
            guard !script.isEmpty else { return Response(status: 500, chunks: [Data("no script".utf8)]) }
            return script.count > 1 ? script.removeFirst() : script[0]
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                lock.withLock { self.recorded.append(request) }
                respond(connection, next(for: request))
            } else if done || error != nil {
                connection.cancel()
            } else {
                read(connection, buffer: buffer)
            }
        }
    }

    private static func parse(_ buffer: Data) -> Request? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = head.first?.split(separator: " ") ?? []
        var headers: [String: String] = [:]
        for line in head.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = buffer[end.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: first.first.map(String.init) ?? "", path: first.count > 1 ? String(first[1]) : "", headers: headers, body: Data(body.prefix(length)))
    }

    private func respond(_ connection: NWConnection, _ response: Response) {
        var head = "HTTP/1.1 \(response.status) Status\r\nConnection: close\r\n"
        for (name, value) in response.headers { head += "\(name): \(value)\r\n" }
        if !response.hangs, response.delay == 0 {
            head += "Content-Length: \(response.chunks.reduce(0) { $0 + $1.count })\r\n"
        }
        head += "\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        guard !response.hangs else { return }
        send(response.chunks[...], delay: response.delay, on: connection)
    }

    private func send(_ chunks: ArraySlice<Data>, delay: TimeInterval, on connection: NWConnection) {
        guard let chunk = chunks.first else {
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            if delay > 0 {
                queue.asyncAfter(deadline: .now() + delay) { self.send(chunks.dropFirst(), delay: delay, on: connection) }
            } else {
                send(chunks.dropFirst(), delay: delay, on: connection)
            }
        })
    }
}
