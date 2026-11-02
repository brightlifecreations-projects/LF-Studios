import Foundation

// lfstudios-mcp: the bridge an AI agent's app starts (stdio MCP). It passes
// each JSON-RPC message, one per line, to LF Studios' agent connection on
// this Mac and writes the answer back. Where the connection is (its port
// and token) is read from LF Studios' endpoint file on every message, so
// the agent's setup never changes when LF Studios restarts or the token is
// renewed.

// (LFSTUDIOS_AGENT_ENDPOINT: another file, for LF Studios' own tests.)
let endpointFile = ProcessInfo.processInfo.environment["LFSTUDIOS_AGENT_ENDPOINT"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("LF Studios", isDirectory: true)
    .appendingPathComponent("agent-endpoint.json")

struct Endpoint: Decodable {
    let port: UInt16
    let token: String
}

var session: String?
let output = FileHandle.standardOutput

func write(_ data: Data) {
    var line = data
    line.append(0x0A)
    output.write(line)
}

/// A JSON-RPC error for `id` (the message couldn't reach LF Studios).
func failure(id: Any?, _ message: String) -> Data {
    var object: [String: Any] = ["jsonrpc": "2.0", "error": ["code": -32000, "message": message]]
    object["id"] = id ?? NSNull()
    return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

func forward(_ line: Data) {
    let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    let id = message?["id"]
    let isNotification = message != nil && id == nil
    guard let data = try? Data(contentsOf: endpointFile), let endpoint = try? JSONDecoder().decode(Endpoint.self, from: data),
          let url = URL(string: "http://127.0.0.1:\(endpoint.port)/mcp") else {
        if !isNotification { write(failure(id: id, "LF Studios isn't open, or AI agents are off. Open LF Studios and turn on Settings ▸ Agent ▸ Allow AI agents to edit.")) }
        return
    }
    var request = URLRequest(url: url, timeoutInterval: 300)
    request.httpMethod = "POST"
    request.httpBody = line
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
    if let session { request.setValue(session, forHTTPHeaderField: "Mcp-Session-Id") }
    let done = DispatchSemaphore(value: 0)
    var answer: Data?
    var problem: String?
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { done.signal() }
        guard let http = response as? HTTPURLResponse else {
            problem = "LF Studios isn't answering (\(error?.localizedDescription ?? "no connection")). Is it open, with AI agents allowed?"
            return
        }
        if let id = http.value(forHTTPHeaderField: "Mcp-Session-Id") { session = id }
        if http.statusCode == 200 { answer = data } else if http.statusCode != 202 {
            problem = String(decoding: data ?? Data(), as: UTF8.self)
            if problem?.isEmpty ?? true { problem = "LF Studios refused the message (\(http.statusCode))." }
        }
    }.resume()
    done.wait()
    if let answer { write(answer) } else if let problem, !isNotification { write(failure(id: id, problem)) }
}

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { continue }
    forward(Data(trimmed.utf8))
}
