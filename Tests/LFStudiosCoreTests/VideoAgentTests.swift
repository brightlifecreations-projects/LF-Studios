import AppKit
import Darwin
import XCTest
@testable import LFStudiosCore

/// AI agents (1.19.0): a test MCP client over real HTTP connects, reads,
/// dry-runs, edits, undoes and reverts a run; it's refused without the
/// token, under another name and from another address; the user takes
/// over; files outside the project are refused; Tacks follow their clip;
/// and the stdio bridge carries all of it.
@MainActor
final class VideoAgentTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private typealias T = VideoEditorTestModel
    private var directory: URL!
    private var model: VideoEditorModel!
    private let hub = VideoAgentHub.shared
    private var session: String?
    private var nextID = 1

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        hub.endpointFile = directory.appendingPathComponent("agent-endpoint.json")
        Settings.videoAgentEnabled = false
        Settings.videoAgentToken = nil
        Settings.videoAgentPort = nil
        hub.reset()
        VideoEditorPanelStore.shared.reset()
        model = try await T.make(in: directory, T.Options(seconds: 6, audio: true))
        VideoAgentProtocol.shared.target = { [weak self] in self?.model }
    }

    override func tearDown() async throws {
        hub.setEnabled(false)
        hub.reset()
        VideoEditorPanelStore.shared.reset()
        VideoAgentProtocol.shared.target = { VideoDemoEditorWindowController.agentModel }
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    private func turnOn() async throws {
        hub.setEnabled(true)
        for _ in 0..<100 where !hub.isListening { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(hub.isListening)
    }

    private var port: UInt16 { VideoAgentServer.shared.port }

    /// One HTTP request to the server.
    private func http(_ body: Data, token: String? = nil, host: String? = nil, origin: String? = nil, address: String = "127.0.0.1") async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: URL(string: "http://\(address):\(port)/mcp")!, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let host { request.setValue(host, forHTTPHeaderField: "Host") }
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        if let session { request.setValue(session, forHTTPHeaderField: "Mcp-Session-Id") }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        if let id = http.value(forHTTPHeaderField: "Mcp-Session-Id") { session = id }
        return (http.statusCode, data)
    }

    /// A JSON-RPC call, answered.
    @discardableResult
    private func rpc(_ method: String, _ params: VideoAgentJSON = .object([:])) async throws -> VideoAgentJSON {
        nextID += 1
        let message = VideoAgentJSON.object(["jsonrpc": .string("2.0"), "id": .number(Double(nextID)), "method": .string(method), "params": params])
        let (status, data) = try await http(message.data, token: hub.token)
        XCTAssertEqual(status, 200, String(decoding: data, as: UTF8.self))
        let answer = try JSONDecoder().decode(VideoAgentJSON.self, from: data)
        XCTAssertNil(answer["error"], "\(method): \(answer.text)")
        return answer["result"] ?? .null
    }

    /// A tool called; its structured answer (and whether it's an error).
    private func tool(_ name: String, _ args: [String: VideoAgentJSON] = [:]) async throws -> (json: VideoAgentJSON, isError: Bool, result: VideoAgentJSON) {
        let result = try await rpc("tools/call", .object(["name": .string(name), "arguments": .object(args)]))
        return (result["structuredContent"] ?? .null, result["isError"]?.bool ?? false, result)
    }

    private func initialize() async throws {
        let result = try await rpc("initialize", .object(["protocolVersion": .string("2025-06-18"), "clientInfo": .object(["name": .string("Test client")]), "capabilities": .object([:])]))
        XCTAssertEqual(result["serverInfo"]?["name"]?.string, "LF Studios")
        XCTAssertNotNil(session, "a session id")
    }

    // MARK: Off, and who may connect

    func testOffUntilTurnedOnAndOnlyThisMacWithTheToken() async throws {
        XCTAssertFalse(Settings.videoAgentEnabled, "off until the user turns it on")
        XCTAssertFalse(hub.isListening)
        XCTAssertNil(VideoAgentEndpoint.read(from: hub.endpointFile), "nothing to connect to")
        try await turnOn()
        let endpoint = try XCTUnwrap(VideoAgentEndpoint.read(from: hub.endpointFile))
        XCTAssertEqual(endpoint.port, port)
        XCTAssertEqual(endpoint.token, hub.token)
        let attributes = try FileManager.default.attributesOfItem(atPath: hub.endpointFile.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600, "readable by this user only")

        let ping = VideoAgentJSON.object(["jsonrpc": .string("2.0"), "id": .number(1), "method": .string("ping")]).data
        var answer = try await http(ping)
        XCTAssertEqual(answer.status, 401, "no token")
        answer = try await http(ping, token: "not-the-token")
        XCTAssertEqual(answer.status, 401, "a wrong token")
        answer = try await http(ping, token: hub.token, host: "evil.example:\(port)")
        XCTAssertEqual(answer.status, 403, "another name (DNS rebinding)")
        answer = try await http(ping, token: hub.token, origin: "https://evil.example")
        XCTAssertEqual(answer.status, 403, "a web page's request")
        answer = try await http(ping, token: hub.token)
        XCTAssertEqual(answer.status, 200)

        // From another address: this Mac's own network address isn't served.
        if let address = Self.nonLoopbackAddress() {
            do {
                let refused = try await http(ping, token: hub.token, address: address)
                XCTFail("served on \(address): \(refused.status)")
            } catch {
                // Connection refused: it listens on 127.0.0.1 only.
            }
        }
        XCTAssertEqual(VideoAgentGate.check(VideoAgentHTTPRequest(method: "POST", path: "/mcp", headers: ["host": "127.0.0.1:\(port)", "authorization": "Bearer \(hub.token)"], body: Data()), peerIsLoopback: false, port: port, token: hub.token),
                       .refused(status: 403, reason: "Only programs on this Mac can connect."), "a peer that isn't this Mac")

        // A new token: the old one is refused at once.
        let old = hub.token
        hub.renewToken()
        XCTAssertNotEqual(hub.token, old)
        answer = try await http(ping, token: old)
        XCTAssertEqual(answer.status, 401)
        XCTAssertEqual(VideoAgentEndpoint.read(from: hub.endpointFile)?.token, hub.token, "the bridge reads the new one")

        // Off again: nothing listens, nothing to find.
        hub.setEnabled(false)
        XCTAssertNil(VideoAgentEndpoint.read(from: hub.endpointFile))
    }

    static func nonLoopbackAddress() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let text = String(cString: host)
            if !text.hasPrefix("127.") { return text }
        }
        return nil
    }

    // MARK: A run

    func testAClientReadsDryRunsEditsUndoesAndRevertsARun() async throws {
        try await turnOn()
        try await initialize()
        let list = try await rpc("tools/list")
        let names = (list["tools"]?.array ?? []).compactMap { $0["name"]?.string }
        for name in ["get_project", "get_timeline", "list_media", "get_transcript", "get_captions", "get_markers", "get_keyframes", "get_frame",
                     "begin_agent_session", "end_agent_session", "split", "delete_left", "delete", "add_marker", "undo", "place_media", "add_tack", "list_tacks"] {
            XCTAssertTrue(names.contains(name), name)
        }
        XCTAssertFalse(names.contains { $0.contains("export") }, "export is the user's")
        XCTAssertFalse(names.contains("record_voiceover"), "never the microphone")
        // Every edit tool takes dry_run.
        for tool in list["tools"]?.array ?? [] where tool["annotations"]?["readOnlyHint"]?.bool == false {
            XCTAssertNotNil(tool["inputSchema"]?["properties"]?["dry_run"], tool["name"]?.string ?? "")
        }

        var timeline = try await tool("get_timeline").json
        func clips(_ timeline: VideoAgentJSON) -> [VideoAgentJSON] {
            (timeline["tracks"]?.array ?? []).first { $0["track"]?.string == "main" }?["clips"]?.array ?? []
        }
        XCTAssertEqual(clips(timeline).count, 1)

        let begun = try await tool("begin_agent_session", ["goal": .string("Tighten the intro")])
        XCTAssertFalse(begun.isError)
        let run = try XCTUnwrap(hub.run(for: model))
        XCTAssertEqual(run.goal, "Tighten the intro")
        XCTAssertTrue(VideoEditorPanelStore.shared.showsAgentPanel, "the Agent panel shows")

        // A dry run: what would change, nothing changes.
        let before = model.project
        let depth = model.undoDepth
        let dry = try await tool("split", ["time": .number(2), "dry_run": .bool(true)])
        XCTAssertEqual(dry.json["would_change"]?.bool, true)
        XCTAssertFalse(dry.json["description"]?.string?.isEmpty ?? true)
        XCTAssertEqual(model.project, before, "a dry run changes nothing")
        XCTAssertEqual(model.undoDepth, depth, "and leaves no undo step")
        XCTAssertTrue(run.changes.isEmpty, "nor a change in the feed")

        // For real: one ⌘Z step, in the feed.
        let split = try await tool("split", ["time": .number(2)])
        XCTAssertFalse(split.isError, split.result.text)
        XCTAssertEqual(model.project.timelineClips.count, 2)
        XCTAssertEqual(model.undoDepth, depth + 1)
        XCTAssertEqual(run.changes.count, 1)
        XCTAssertEqual(run.changes.first?.time ?? 0, 2, accuracy: 0.05, "where it happened")
        timeline = try await tool("get_timeline").json
        XCTAssertEqual(clips(timeline).count, 2)

        // Undo through the agent, then again.
        _ = try await tool("undo")
        XCTAssertEqual(model.project.timelineClips.count, 1)
        _ = try await tool("split", ["time": .number(2)])
        _ = try await tool("delete_left", ["time": .number(1)])
        XCTAssertLessThan(model.timelineDuration, 5.5)

        // The end: the user reviews, then Revert all: one step back to the
        // checkpoint; ⌘Z brings the changes back.
        _ = try await tool("end_agent_session", ["summary": .string("Split at 2 s and cut the first second")])
        XCTAssertTrue(run.reviewing)
        XCTAssertFalse(run.changedTimes.isEmpty, "marked on the timeline")
        let refusedAfterEnd = try await tool("split", ["time": .number(3)])
        XCTAssertTrue(refusedAfterEnd.isError, "the run is over")
        let beginAgain = try await tool("begin_agent_session", ["goal": .string("More")])
        XCTAssertTrue(beginAgain.isError, "the user chooses Keep or Revert all first")
        XCTAssertTrue(run.reviewing)
        hub.revertAll(on: model)
        XCTAssertEqual(model.project, before, "Revert all")
        XCTAssertNil(hub.run(for: model))
        model.undo()
        XCTAssertNotEqual(model.project, before, "⌘Z: the changes again")
        XCTAssertEqual(model.project.timelineClips.count, 2)
    }

    func testKeepEndsTheRunAndReadToolsAnswer() async throws {
        try await turnOn()
        try await initialize()
        _ = try await tool("begin_agent_session", ["goal": .string("Captions")])
        model.mutate { $0.captions = [VideoCaptionLine(start: 1, end: 2, text: "Helo")] }
        let captions = try await tool("get_captions").json
        let id = try XCTUnwrap(captions["captions"]?.array?.first?["id"]?.string)
        let fixed = try await tool("set_caption_text", ["caption_id": .string(id), "text": .string("Hello")])
        XCTAssertFalse(fixed.isError, fixed.result.text)
        XCTAssertEqual(model.project.captions.first?.text, "Hello")
        let project = try await tool("get_project").json
        XCTAssertEqual(project["duration"]?.double ?? 0, model.timelineDuration, accuracy: 0.01)
        _ = try await tool("get_transcript")
        _ = try await tool("get_markers")
        _ = try await tool("list_media")
        _ = try await tool("get_keyframes")
        // A frame: a picture comes back.
        let frame = try await tool("get_frame", ["time": .number(1)])
        let content = frame.result["content"]?.array ?? []
        XCTAssertTrue(content.contains { $0["type"]?.string == "image" && ($0["data"]?.string?.count ?? 0) > 1000 }, "a PNG")
        hub.end(on: model)
        hub.keep(on: model)
        XCTAssertNil(hub.run(for: model))
        XCTAssertEqual(model.project.captions.first?.text, "Hello", "kept")
    }

    // MARK: The user stays in charge

    func testLockedTracksAndTakingOverStopTheAgent() async throws {
        try await turnOn()
        try await initialize()
        _ = try await tool("begin_agent_session", ["goal": .string("Cuts")])
        model.toggleTrackLocked(.clips)
        let locked = try await tool("split", ["time": .number(2)])
        XCTAssertTrue(locked.isError, "a locked track")
        XCTAssertEqual(model.project.timelineClips.count, 1)
        let dryLocked = try await tool("split", ["time": .number(2), "dry_run": .bool(true)])
        XCTAssertTrue(dryLocked.isError, "a dry run says so too")
        model.toggleTrackLocked(.clips)

        // The user clicks or types: the next edit waits.
        hub.userTookOver(model)
        let paused = try await tool("split", ["time": .number(2)])
        XCTAssertTrue(paused.isError)
        XCTAssertTrue(paused.json["error"]?.string?.contains("took over") ?? false)
        XCTAssertEqual(model.project.timelineClips.count, 1)
        _ = try await tool("get_timeline")  // reading still works
        let asked = try await tool("add_tack", ["time": .number(2), "text": .string("Shall I split here?"), "question": .bool(true)])
        XCTAssertFalse(asked.isError, "a Tack can still be left")
        XCTAssertEqual(model.project.tacks?.count, 1)
        XCTAssertTrue(hub.run(for: model)?.paused ?? false, "and the run stays paused")
        hub.resume(model)
        let resumed = try await tool("split", ["time": .number(2)])
        XCTAssertFalse(resumed.isError)
        XCTAssertEqual(model.project.timelineClips.count, 2)

        // Through the editor's key handling too (any key while it edits).
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                     characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        _ = VideoKeyboardBridge.route(event, editor: window, isKey: true, model: model)
        XCTAssertTrue(hub.run(for: model)?.paused ?? false, "typing takes over")
    }

    func testOnlyTheProjectsFilesCanBePlaced() async throws {
        try await turnOn()
        try await initialize()
        let outside = directory.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let picture = outside.appendingPathComponent("logo.png")
        try VideoInspection.writePNG(to: picture, size: CGSize(width: 80, height: 40), color: .systemTeal)
        let refused = try await tool("place_media", ["path": .string(picture.path), "time": .number(1)])
        XCTAssertTrue(refused.isError)
        XCTAssertTrue(refused.json["error"]?.string?.contains("isn't in this project") ?? false)
        XCTAssertTrue(model.project.layerTracks.isEmpty)
        let dryRefused = try await tool("place_media", ["path": .string(picture.path), "dry_run": .bool(true)])
        XCTAssertTrue(dryRefused.isError, "a dry run refuses too")

        // In the Library (the user added it): placed.
        model.importMedia([picture])
        let placed = try await tool("place_media", ["path": .string(picture.path), "time": .number(1)])
        XCTAssertFalse(placed.isError, placed.result.text)
        XCTAssertEqual(model.project.layerTracks.first?.items.count, 1)
    }

    func testTacksFollowTheirClipAndCarryTheAnswer() async throws {
        try await turnOn()
        try await initialize()
        let added = try await tool("add_tack", ["time": .number(3), "text": .string("Cut this pause?"), "question": .bool(true)])
        XCTAssertFalse(added.isError)
        var tacks = try await tool("list_tacks").json["tacks"]?.array ?? []
        XCTAssertEqual(tacks.first?["time"]?.double ?? 0, 3, accuracy: 0.01)
        // The user cuts the first second: the tack follows its moment.
        model.seek(to: 1)
        model.perform(.deleteLeft)
        tacks = try await tool("list_tacks").json["tacks"]?.array ?? []
        XCTAssertEqual(tacks.first?["time"]?.double ?? 0, 2, accuracy: 0.05, "with its clip")
        // The user answers.
        model.changeTacks { $0[0].answer = "Yes" }
        tacks = try await tool("list_tacks").json["tacks"]?.array ?? []
        XCTAssertEqual(tacks.first?["answer"]?.string, "Yes")
    }

    /// Tacks are saved with the project (1.19.1): they come back when it
    /// opens again, and ⌘Z and Revert all leave them be. Only a project
    /// with Tacks is written as format 6, which 1.19.0 (format 5) refuses
    /// as "needs a newer version"; without them it's written as before.
    func testTacksAreSavedWithTheProject() async throws {
        try await turnOn()
        try await initialize()
        XCTAssertFalse(model.project.needsFormat6)
        let plain = VideoProjectDocument(mediaMode: .linked, project: model.project, recording: nil)
        XCTAssertLessThan(plain.version, 6)
        XCTAssertFalse(String(decoding: try plain.encoded(), as: UTF8.self).contains("\"tacks\""), "no Tacks: written as 1.19.0 wrote it")

        let before = model.project.timelineClips
        _ = try await tool("begin_agent_session", ["goal": .string("Tighten it")])
        _ = try await tool("split", ["time": .number(2)])
        XCTAssertNotEqual(model.project.timelineClips, before)
        let depth = model.undoDepth
        _ = try await tool("add_tack", ["time": .number(3), "text": .string("Cut this pause?"), "question": .bool(true)])
        _ = try await tool("add_tack", ["time": .number(1), "text": .string("I split at 2 s.")])
        XCTAssertEqual(model.project.tacks?.count, 2)
        // The user answers one and dismisses the other: notes, not ⌘Z steps.
        model.changeTacks { tacks in
            tacks[0].answer = "Yes"
            tacks[1].dismissed = true
        }
        XCTAssertEqual(model.undoDepth, depth, "a Tack is never a ⌘Z step")
        model.undo()
        XCTAssertEqual(model.project.timelineClips, before, "⌘Z takes back the split")
        XCTAssertEqual(model.project.tacks?.count, 2, "and leaves the Tacks")
        model.redo()
        XCTAssertEqual(model.project.tacks?.first?.answer, "Yes")
        hub.revertAll(on: model)
        XCTAssertEqual(model.project.timelineClips, before, "Revert all takes back the split")
        XCTAssertEqual(model.project.tacks?.first?.answer, "Yes", "and keeps the answer")
        XCTAssertEqual(model.project.tacks?.last?.dismissed, true)

        // The file: format 6, which 1.19.0 and earlier refuse.
        XCTAssertTrue(model.project.needsFormat6)
        let document = VideoProjectDocument(mediaMode: .linked, project: model.project, recording: nil)
        XCTAssertEqual(document.version, 6)
        XCTAssertEqual(document.format, VideoProjectDocument.format4)
        XCTAssertTrue(String(decoding: try document.encoded(), as: UTF8.self).contains("\"requires\" : 6"))
        XCTAssertEqual(VideoProjectDocument.firstVersionOpening(model.project), "1.19.1")

        // Saved, then opened in an editor of its own.
        let package = directory.appendingPathComponent("Tacked.lfs", isDirectory: true)
        try VideoProjectPackage.save(model.projectContents, to: package, mode: .linked)
        let opened = try VideoProjectPackage.open(package)
        XCTAssertEqual(opened.contents.project.tacks, model.project.tacks)
        hub.forget(model)
        let primary = try XCTUnwrap(VideoProjectOpener.prepare(opened, ask: { _ in false }))
        let reopened = VideoEditorModel(videoURL: primary)
        reopened.projectFileURL = package
        reopened.projectMediaMode = .linked
        await reopened.load()
        model = reopened
        XCTAssertNil(hub.run(for: reopened), "no agent working")
        let listed = try await tool("list_tacks").json["tacks"]?.array ?? []
        XCTAssertEqual(listed.count, 2, "the agent reads them in a new session")
        XCTAssertEqual(listed.first?["answer"]?.string, "Yes")
        XCTAssertEqual(listed.first?["time"]?.double ?? 0, 3, accuracy: 0.05)
        XCTAssertEqual(listed.last?["dismissed"]?.bool, true)

        // Without its last Tack, a project goes back to the earlier format.
        reopened.changeTacks { $0.removeAll() }
        XCTAssertNil(reopened.project.tacks)
        XCTAssertLessThan(VideoProjectDocument(mediaMode: .linked, project: reopened.project, recording: nil).version, 6)
    }

    // MARK: The bridge

    func testTheBridgeCarriesMessagesWhateverThePortOrToken() async throws {
        let bridge = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("lfstudios-mcp")
        guard FileManager.default.isExecutableFile(atPath: bridge.path) else { throw XCTSkip("lfstudios-mcp isn't built next to the tests") }
        try await turnOn()
        func ask(_ lines: [VideoAgentJSON]) async throws -> [VideoAgentJSON] {
            let process = Process()
            process.executableURL = bridge
            process.environment = ["LFSTUDIOS_AGENT_ENDPOINT": hub.endpointFile.path, "PATH": "/usr/bin:/bin"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            for line in lines { input.fileHandleForWriting.write(line.data + Data("\n".utf8)) }
            input.fileHandleForWriting.closeFile()
            // The server answers on the main queue: let it run while waiting.
            while process.isRunning { try await Task.sleep(nanoseconds: 20_000_000) }
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(VideoAgentJSON.self, from: Data($0.utf8)) }
        }
        let initialize = VideoAgentJSON.object(["jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"), "params": .object(["protocolVersion": .string("2025-06-18"), "clientInfo": .object(["name": .string("Bridge test")])])])
        let initialized = VideoAgentJSON.object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")])
        let timeline = VideoAgentJSON.object(["jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"), "params": .object(["name": .string("get_timeline"), "arguments": .object([:])])])
        var answers = try await ask([initialize, initialized, timeline])
        XCTAssertEqual(answers.count, 2, "a notification gets no answer")
        XCTAssertEqual(answers.first?["result"]?["serverInfo"]?["name"]?.string, "LF Studios")
        XCTAssertNotNil(answers.last?["result"]?["structuredContent"]?["tracks"])
        // A new token and a restart on another port: the same setup works.
        hub.renewToken()
        hub.setEnabled(false)
        hub.setEnabled(true)
        for _ in 0..<100 where !hub.isListening { try await Task.sleep(nanoseconds: 20_000_000) }
        answers = try await ask([initialize, timeline])
        XCTAssertEqual(answers.count, 2)
        XCTAssertNil(answers.last?["error"], answers.last?.text ?? "")
        // Off: it says so, clearly.
        hub.setEnabled(false)
        answers = try await ask([timeline])
        XCTAssertTrue(answers.first?["error"]?["message"]?.string?.contains("Settings ▸ Agent") ?? false)
    }
}
