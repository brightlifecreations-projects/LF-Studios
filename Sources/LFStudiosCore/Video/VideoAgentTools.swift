import AppKit
import AVFoundation
import CoreImage
import Foundation

// MARK: - AI agents (1.19.0): MCP and the tools

/// A tool an agent can call.
struct VideoAgentTool {
    let name: String
    let description: String
    /// Its arguments (JSON Schema properties; `required` names).
    let properties: [String: VideoAgentJSON]
    var required: [String] = []
    /// Reads only (no dry_run, never paused).
    var readOnly = false
    let run: @MainActor (_ model: VideoEditorModel, _ args: VideoAgentJSON, _ dryRun: Bool) async throws -> VideoAgentToolResult

    var schema: VideoAgentJSON {
        var properties = self.properties
        if !readOnly {
            properties["dry_run"] = .object(["type": .string("boolean"), "description": .string("Check what it would do without changing anything.")])
        }
        var tool: [String: VideoAgentJSON] = [
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map { .string($0) })]),
        ]
        tool["annotations"] = .object(["readOnlyHint": .bool(readOnly), "destructiveHint": .bool(!readOnly), "openWorldHint": .bool(false)])
        return .object(tool)
    }
}

/// What a tool answers: JSON (as text and structured), maybe a picture.
struct VideoAgentToolResult {
    var json: VideoAgentJSON
    var isError = false
    var image: Data?

    static func error(_ message: String) -> VideoAgentToolResult {
        VideoAgentToolResult(json: .object(["ok": .bool(false), "error": .string(message)]), isError: true)
    }

    var mcp: VideoAgentJSON {
        var content: [VideoAgentJSON] = [.object(["type": .string("text"), "text": .string(json.text)])]
        if let image { content.append(.object(["type": .string("image"), "data": .string(image.base64EncodedString()), "mimeType": .string("image/png")])) }
        var result: [String: VideoAgentJSON] = ["content": .array(content), "isError": .bool(isError)]
        if case .object = json { result["structuredContent"] = json }
        return .object(result)
    }
}

enum VideoAgentToolError: Error {
    /// A message for the agent (in English: the agent reads it).
    case forAgent(String)
}

/// The four hard limits, for MCP agents and the built-in Assistant alike
/// (AGENT-TOOLS.md). No tool does any of these; this is the wall behind that,
/// in `VideoAgentProtocol.call`, which every tool call passes: a tool whose
/// name offers one is refused, and so is any file argument that isn't media
/// already in the open project. Nothing an agent sends or reads (an argument,
/// a project, a transcript, a caption) can switch it off.
enum VideoAgentLimits {
    static let rules = [
        "Never read, list, export or reveal API keys, tokens or the Workspace ID, and never change AI or agent settings or your own permissions.",
        "Never record anything: no screen recording, camera, microphone, screenshots or voiceover.",
        "Never delete a project, a recording folder or any file on disk. Removing clips from the timeline is fine: it's undoable.",
        "Never export anything and never open or import a file: work only inside the open project, with media already in it. prepare_export only fills in the Export window; the user clicks Export.",
    ]

    /// Words a tool's name may not carry (split at "_").
    static let forbiddenWords: Set<String> = [
        "export", "record", "recording", "screenshot", "screen", "capture", "camera", "microphone", "mic", "voiceover",
        "open", "import", "file", "files", "folder", "disk", "trash",
        "key", "keys", "token", "tokens", "workspace", "secret", "password", "setting", "settings", "permission", "permissions",
    ]
    /// Pairs that may not stand side by side ("delete_project").
    static let forbiddenPairs: Set<String> = ["delete project", "remove project", "delete recording", "remove recording"]
    /// Fills in the Export window only: it never exports.
    static let exceptions: Set<String> = ["prepare_export"]

    static func allows(tool name: String) -> Bool {
        if exceptions.contains(name) { return true }
        let words = name.lowercased().split(separator: "_").map(String.init)
        if words.contains(where: forbiddenWords.contains) { return false }
        return !zip(words, words.dropFirst()).contains { forbiddenPairs.contains("\($0) \($1)") }
    }

    /// Arguments that name a file or a place on disk.
    static func isFileArgument(_ key: String) -> Bool {
        let key = key.lowercased()
        return ["path", "file", "url", "folder", "directory", "destination", "output"].contains(key)
            || ["_path", "_url", "_folder", "_directory"].contains { key.hasSuffix($0) }
    }

    /// Why this call is refused, or nil.
    @MainActor
    static func refusal(_ tool: String, _ args: VideoAgentJSON, on model: VideoEditorModel) -> String? {
        guard allows(tool: tool) else {
            return "Refused: agents can't do that. They never touch keys or settings, record, delete files, export, or open or import files."
        }
        guard case .object(let fields) = args else { return nil }
        for (key, value) in fields where isFileArgument(key) {
            guard let path = value.string, model.agentMayPlace(URL(fileURLWithPath: path)) else {
                let name = value.string.map { URL(fileURLWithPath: $0).lastPathComponent } ?? key
                return "Refused: \(name) isn't in this project. Agents only use media already in it (list_media); they never open, import or write other files."
            }
        }
        return nil
    }

    /// A file name with no folders in it, or nil when nothing is left.
    static func fileName(_ raw: String) -> String? {
        let name = raw.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return name?.isEmpty == false ? name : nil
    }
}

/// JSON-RPC for MCP: initialize, tools/list, tools/call, ping.
@MainActor
final class VideoAgentProtocol {
    static let shared = VideoAgentProtocol()
    static let protocolVersion = "2025-06-18"

    /// The project the agent works on: the front editor (nil: none open).
    var target: () -> VideoEditorModel? = { VideoDemoEditorWindowController.agentModel }

    lazy var tools: [VideoAgentTool] = VideoAgentTools.all.filter { VideoAgentLimits.allows(tool: $0.name) }

    func answer(_ message: VideoAgentJSON, session: String?) async -> VideoAgentJSON? {
        // A batch: each answered.
        if case .array(let batch) = message {
            var answers: [VideoAgentJSON] = []
            for one in batch { if let answer = await answer(one, session: session) { answers.append(answer) } }
            return answers.isEmpty ? nil : .array(answers)
        }
        let id = message["id"]
        guard let method = message["method"]?.string else {
            return id == nil ? nil : failure(id, code: -32600, "Invalid request")
        }
        let params = message["params"] ?? .object([:])
        switch method {
        case "initialize":
            let client = params["clientInfo"]?["name"]?.string
            VideoAgentHub.shared.noteActivity(client: client)
            let asked = params["protocolVersion"]?.string ?? Self.protocolVersion
            return success(id, .object([
                "protocolVersion": .string(asked),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object(["name": .string("LF Studios"), "version": .string(VideoAgentInstructions.appVersion)]),
                "instructions": .string(VideoAgentInstructions.short),
            ]))
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return success(id, .object([:]))
        case "tools/list":
            return success(id, .object(["tools": .array(tools.map(\.schema))]))
        case "tools/call":
            guard let name = params["name"]?.string, let tool = tools.first(where: { $0.name == name }) else {
                return failure(id, code: -32602, "Unknown tool: \(params["name"]?.string ?? "-")")
            }
            let args = params["arguments"] ?? .object([:])
            return success(id, await call(tool, args).mcp)
        default:
            return id == nil ? nil : failure(id, code: -32601, "Method not found: \(method)")
        }
    }

    /// Runs a tool on the front project: read tools at once; edits only in
    /// a run the user hasn't taken over, recorded in the feed.
    func call(_ tool: VideoAgentTool, _ args: VideoAgentJSON, on project: VideoEditorModel? = nil) async -> VideoAgentToolResult {
        guard let model = project ?? target(), model.isReady else {
            return .error("No project is open in LF Studios. Ask the user to open one.")
        }
        if let refusal = VideoAgentLimits.refusal(tool.name, args, on: model) {
            VideoAgentHub.shared.record(VideoAgentChange(date: Date(), title: refusal, tool: tool.name, time: model.clock.time, selection: nil, refused: true), on: model)
            return .error(refusal)
        }
        let hub = VideoAgentHub.shared
        let dryRun = args["dry_run"]?.bool ?? false
        // A Tack is a note, not an edit: it can always be left, also while
        // the user has taken over (1.19.1; 1.19.0 refused it then).
        if !tool.readOnly, !dryRun, !["begin_agent_session", "end_agent_session", "add_tack"].contains(tool.name) {
            if let run = hub.run(for: model) {
                if run.paused {
                    return .error("The user took over the editor. Wait, then try again after they click Resume in the Agent panel. You can still read, and leave a Tack.")
                }
                if run.reviewing {
                    return .error("This run has ended: the user is reviewing your changes (Keep or Revert all). Call begin_agent_session to start a new one.")
                }
            } else {
                hub.begin(on: model, goal: "")
            }
        }
        do {
            return try await tool.run(model, args, dryRun)
        } catch VideoAgentToolError.forAgent(let message) {
            return .error(message)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func success(_ id: VideoAgentJSON?, _ result: VideoAgentJSON) -> VideoAgentJSON? {
        guard let id else { return nil }
        return .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
    }

    private func failure(_ id: VideoAgentJSON?, code: Int, _ message: String) -> VideoAgentJSON {
        .object(["jsonrpc": .string("2.0"), "id": id ?? .null, "error": .object(["code": .number(Double(code)), "message": .string(message)])])
    }
}

/// The tools.
@MainActor
enum VideoAgentTools {
    private static func number(_ description: String) -> VideoAgentJSON {
        .object(["type": .string("number"), "description": .string(description)])
    }

    private static func text(_ description: String, choices: [String]? = nil) -> VideoAgentJSON {
        var schema: [String: VideoAgentJSON] = ["type": .string("string"), "description": .string(description)]
        if let choices { schema["enum"] = .array(choices.map { .string($0) }) }
        return .object(schema)
    }

    private static func round(_ value: Double) -> VideoAgentJSON { .number((value * 1000).rounded() / 1000) }

    private static func uuid(_ args: VideoAgentJSON, _ key: String) throws -> UUID? {
        guard let raw = args[key]?.string else { return nil }
        guard let id = UUID(uuidString: raw) else { throw VideoAgentToolError.forAgent("\(key) isn't an id from get_timeline: \(raw)") }
        return id
    }

    static var all: [VideoAgentTool] { readTools + sessionTools + commandTools + parameterTools + basicsTools + wholeVideoTools + tackTools }

    /// A track by what get_timeline calls it: "main", "music", or a track
    /// id (a track above the main track, or an added sound).
    private static func track(_ model: VideoEditorModel, _ args: VideoAgentJSON) throws -> VideoTimelineTrack {
        guard let raw = args["track"]?.string else { throw VideoAgentToolError.forAgent("track is needed: main, music, or a track id from get_timeline") }
        switch raw.lowercased() {
        case "main": return .clips
        case "music": return .music
        default: break
        }
        guard let id = UUID(uuidString: raw) else { throw VideoAgentToolError.forAgent("track is main, music, or a track id from get_timeline: \(raw)") }
        if model.project.layerTracks.contains(where: { $0.id == id }) { return .layer(id) }
        if model.project.audioTracks.contains(where: { $0.id == id }) { return .sound(id) }
        throw VideoAgentToolError.forAgent("No track with id \(raw)")
    }

    // MARK: 1.21.0's editor basics

    static var basicsTools: [VideoAgentTool] {
        let track = text("main, music, or a track id from get_timeline (a track above the main track, or an added sound).")
        return [
            VideoAgentTool(name: "delete_gap", description: "Close the empty stretch at `time` on a track above the main track or an added sound track: what comes after it moves back.", properties: ["track": track, "time": number("A moment inside the gap (timeline seconds).")], required: ["track", "time"]) { model, args, dryRun in
                let which = try self.track(model, args)
                guard let time = args["time"]?.double else { throw VideoAgentToolError.forAgent("time is needed") }
                return try edit(model, .object([:]), dryRun: dryRun, tool: "delete_gap") { model.perform(.basics(.deleteGap(track: which, time: time))) }
            },
            VideoAgentTool(name: "paste_attributes", description: "Copy attributes from one clip onto others (like Paste Attributes): effects, filters, adjust, speed, volume, transform, animation. Main-track clips take only speed, volume and transform.", properties: [
                "from_id": text("The clip or item to copy from (get_timeline)."),
                "to_ids": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "description": .string("The clips or items to paste onto.")]),
                "attributes": .object(["type": .string("array"), "items": .object(["type": .string("string"), "enum": .array(VideoClipAttribute.allCases.map { .string($0.rawValue) })]), "description": .string("What to paste.")]),
            ], required: ["from_id", "to_ids", "attributes"]) { model, args, dryRun in
                guard let from = try uuid(args, "from_id") else { throw VideoAgentToolError.forAgent("from_id is needed") }
                let targets = try (args["to_ids"]?.array ?? []).map { value -> VideoEditorModel.Selection in
                    guard let raw = value.string, let id = UUID(uuidString: raw) else { throw VideoAgentToolError.forAgent("to_ids are ids from get_timeline") }
                    if model.project.layerItem(id) != nil { return .layer(id) }
                    if model.project.timelineClips.contains(where: { $0.id == id }) { return .clip(id) }
                    throw VideoAgentToolError.forAgent("No clip with id \(raw)")
                }
                let attributes = Set((args["attributes"]?.array ?? []).compactMap { $0.string.flatMap(VideoClipAttribute.init(rawValue:)) })
                guard !targets.isEmpty, !attributes.isEmpty else { throw VideoAgentToolError.forAgent("to_ids and attributes are needed") }
                if let item = model.project.layerItem(from) {
                    model.copiedAttributes = VideoCopiedAttributes(layer: item)
                } else if let clip = model.project.timelineClips.first(where: { $0.id == from }) {
                    model.copiedAttributes = VideoCopiedAttributes(clip: clip)
                } else {
                    throw VideoAgentToolError.forAgent("No clip with id \(from.uuidString)")
                }
                model.selection = targets[0]
                model.extraSelection = Array(targets.dropFirst())
                return try edit(model, .object([:]), dryRun: dryRun, tool: "paste_attributes") { model.perform(.basics(.pasteAttributes(attributes))) }
            },
            VideoAgentTool(name: "roll_cut", description: "Roll the cut at the end of a clip by `by` seconds (+ later, − earlier): this clip and the next one both change; the video keeps its length. Main track, or two touching clips above it.", properties: ["clip_id": text("The clip before the cut (get_timeline)."), "by": number("Seconds.")], required: ["clip_id", "by"]) { model, args, dryRun in
                guard let id = try uuid(args, "clip_id"), let by = args["by"]?.double else { throw VideoAgentToolError.forAgent("clip_id and by are needed") }
                return try edit(model, .object([:]), dryRun: dryRun, tool: "roll_cut") { model.perform(.basics(.roll(clip: id, by: by))) }
            },
            VideoAgentTool(name: "slide_clip", description: "Slide a clip by `by` seconds between its neighbours: it keeps its frames; the clip before gets longer and the one after shorter (or the other way).", properties: ["clip_id": text("The clip (get_timeline)."), "by": number("Seconds (+ later, − earlier).")], required: ["clip_id", "by"]) { model, args, dryRun in
                guard let id = try uuid(args, "clip_id"), let by = args["by"]?.double else { throw VideoAgentToolError.forAgent("clip_id and by are needed") }
                return try edit(model, .object([:]), dryRun: dryRun, tool: "slide_clip") { model.perform(.basics(.slide(clip: id, by: by))) }
            },
            VideoAgentTool(name: "solo_track", description: "Solo a track on or off: while any track is soloed only soloed tracks are heard in the editor. The export always has every track.", properties: ["track": track], required: ["track"]) { model, args, dryRun in
                let which = try self.track(model, args)
                return try edit(model, .object([:]), dryRun: dryRun, tool: "solo_track") { model.perform(.basics(.solo(which))) }
            },
            VideoAgentTool(name: "rename_track", description: "Give a track its own name (an empty name goes back to the usual one).", properties: ["track": track, "name": text("The name.")], required: ["track", "name"]) { model, args, dryRun in
                let which = try self.track(model, args)
                let name = args["name"]?.string ?? ""
                return try edit(model, .object([:]), dryRun: dryRun, tool: "rename_track") { model.perform(.basics(.renameTrack(which, name))) }
            },
        ]
    }

    // MARK: Read

    static var readTools: [VideoAgentTool] {
        [
            VideoAgentTool(name: "get_project", description: "The open project: name, length, frame size and rate, the playhead, what's selected, and whether an agent run is going.", properties: [:], readOnly: true) { model, _, _ in
                let run = VideoAgentHub.shared.run(for: model)
                return VideoAgentToolResult(json: .object([
                    "name": .string((model.projectFileURL ?? model.project.sourceURL).deletingPathExtension().lastPathComponent),
                    "duration": round(model.timelineDuration),
                    "source_size": .array([.number(model.project.sourceWidth), .number(model.project.sourceHeight)]),
                    "playhead": round(model.clock.time),
                    "selection": selectionJSON(model.selection),
                    "can_undo": .bool(model.canUndo), "can_redo": .bool(model.canRedo),
                    "run": run.map { run in .object(["changes": .number(Double(run.changes.count)), "paused": .bool(run.paused), "reviewing": .bool(run.reviewing)]) } ?? .null,
                ]))
            },
            VideoAgentTool(name: "get_timeline", description: "Every track top to bottom with what's on it, in timeline seconds: captions, zooms, tracks above the main track (items, their sound and whether it's linked), the main track's clips (source range, speed, muted, linked or unlinked sound), added sound and music, and which tracks are locked or hidden.", properties: [:], readOnly: true) { model, _, _ in
                VideoAgentToolResult(json: timelineJSON(model))
            },
            VideoAgentTool(name: "list_media", description: "The project's media (Library): recordings, camera, music, sounds, pictures and imported files, with their paths. Only these can be placed.", properties: [:], readOnly: true) { model, _, _ in
                let entries = model.project.mediaEntries(camera: model.webcamRecordingForAgent)
                return VideoAgentToolResult(json: .object(["media": .array(entries.map { entry in
                    .object(["name": .string(entry.name), "path": .string(entry.path), "kind": .string(entry.kind.rawValue), "in_video": .bool(entry.isInVideo), "missing": .bool(entry.isMissing), "duration": entry.duration.map { round($0) } ?? .null])
                }), "project_folder": model.agentProjectFolder.map { .string($0.path) } ?? .null]))
            },
            VideoAgentTool(name: "get_transcript", description: "What's said, word by word, with each word's timeline start and end (words cut out of the video are left out), and which words are fillers (um, uh). Word indexes are what remove_fillers takes.", properties: [:], readOnly: true) { model, _, _ in
                let words = model.transcriptWords
                var out: [VideoAgentJSON] = []
                for (index, word) in words.enumerated() {
                    guard let start = model.timelineTime(forSource: word.start) else { continue }
                    let end = model.timelineTime(forSource: word.end) ?? start
                    out.append(.object(["index": .number(Double(index)), "text": .string(word.text), "start": round(start), "end": round(end), "filler": .bool(word.isFiller)]))
                }
                return VideoAgentToolResult(json: .object(["words": .array(out), "has_transcript": .bool(!words.isEmpty)]))
            },
            VideoAgentTool(name: "get_captions", description: "The captions with ids, timeline start and end, and text.", properties: [:], readOnly: true) { model, _, _ in
                VideoAgentToolResult(json: .object(["captions": .array(model.plan.captions.map { line in
                    .object(["id": .string(line.id.uuidString), "start": round(line.start), "end": round(line.end), "text": .string(line.text)])
                })]))
            },
            VideoAgentTool(name: "get_markers", description: "The markers, by name and timeline time.", properties: [:], readOnly: true) { model, _, _ in
                VideoAgentToolResult(json: .object(["markers": .array(model.placedMarkers.map { marker in
                    .object(["id": .string(marker.marker.id.uuidString), "name": .string(marker.title), "time": round(marker.time)])
                })]))
            },
            VideoAgentTool(name: "get_keyframes", description: "Keyframes of the items above the main track: for each animated setting, its keys (seconds from the item's start and on the timeline, value, easing, curve handle slopes).", properties: ["item_id": text("One item (optional).")], readOnly: true) { model, args, _ in
                let only = try uuid(args, "item_id")
                var items: [VideoAgentJSON] = []
                for (_, item) in model.project.layerItems where only == nil || item.id == only {
                    guard let keys = item.keys, !keys.isEmpty else { continue }
                    var properties: [String: VideoAgentJSON] = [:]
                    for (name, list) in keys.tracks where !list.isEmpty {
                        properties[name] = .array(list.map { key in
                            .object(["time": round(key.time), "at": round(item.at + key.time), "value": round(key.value), "easing": .string(key.easing.rawValue),
                                     "in_slope": key.inSlope.map { round($0) } ?? .null, "out_slope": key.outSlope.map { round($0) } ?? .null])
                        })
                    }
                    items.append(.object(["item_id": .string(item.id.uuidString), "name": .string(item.name), "keys": .object(properties)]))
                }
                return VideoAgentToolResult(json: .object(["items": .array(items)]))
            },
            VideoAgentTool(name: "get_frame", description: "A picture of the video at a timeline time, as it exports (640 wide).", properties: ["time": number("Timeline seconds.")], required: ["time"], readOnly: true) { model, args, _ in
                guard let time = args["time"]?.double else { throw VideoAgentToolError.forAgent("time is needed") }
                guard let png = await model.agentFrame(at: min(max(time, 0), model.timelineDuration)) else { throw VideoAgentToolError.forAgent("That frame couldn't be drawn.") }
                return VideoAgentToolResult(json: .object(["time": round(time), "width": .number(640)]), image: png)
            },
        ]
    }

    static func selectionJSON(_ selection: VideoEditorModel.Selection) -> VideoAgentJSON {
        switch selection {
        case .none: return .null
        case .clip(let id): return .object(["kind": .string("clip"), "id": .string(id.uuidString)])
        case .layer(let id): return .object(["kind": .string("item"), "id": .string(id.uuidString)])
        case .caption(let id): return .object(["kind": .string("caption"), "id": .string(id.uuidString)])
        case .zoom(let id): return .object(["kind": .string("zoom"), "id": .string(id.uuidString)])
        case .overlay(let id): return .object(["kind": .string("annotation"), "id": .string(id.uuidString)])
        case .range(let range): return .object(["kind": .string("range"), "start": round(range.start), "end": round(range.end)])
        default: return .object(["kind": .string("other")])
        }
    }

    static func timelineJSON(_ model: VideoEditorModel) -> VideoAgentJSON {
        let project = model.project
        let rows = model.timelineSoundRows
        func state(_ track: VideoTimelineTrack) -> [String: VideoAgentJSON] {
            let s = project.trackState(track)
            return ["locked": .bool(s.locked), "hidden": .bool(s.hidden), "muted": .bool(s.muted)]
        }
        var tracks: [VideoAgentJSON] = []
        var captions = state(.captions)
        captions["track"] = .string("captions")
        captions["count"] = .number(Double(project.captions.count))
        tracks.append(.object(captions))
        var zooms = state(.zooms)
        zooms["track"] = .string("zooms")
        zooms["zooms"] = .array(project.zoomRegions.map { .object(["id": .string($0.id.uuidString), "start": round($0.start), "end": round($0.end), "scale": round($0.scale)]) })
        tracks.append(.object(zooms))
        for (index, track) in project.layerTracks.enumerated() {
            var row = state(.layer(track.id))
            row["track"] = .string("above \(index + 1)")
            row["track_id"] = .string(track.id.uuidString)
            row["has_sound_row"] = .bool(rows.layers.contains(track.id))
            row["items"] = .array(track.items.map { item in
                .object(["id": .string(item.id.uuidString), "name": .string(item.name), "kind": .string(item.role.map { "\($0)" } ?? item.kind.rawValue),
                         "start": round(item.at), "end": round(item.end), "enabled": .bool(item.enabled), "volume": round(item.volume),
                         "sound": item.isVideo ? .string(item.audioOffset == nil ? "linked" : "unlinked") : .null,
                         "sound_offset": item.audioOffset.map { round($0) } ?? .null])
            })
            tracks.append(.object(row))
        }
        var main = state(.clips)
        main["track"] = .string("main")
        main["clips"] = .array(model.segments.map { segment in
            .object(["id": .string(segment.id.uuidString), "start": round(segment.timelineStart), "end": round(segment.timelineEnd),
                     "source_start": round(segment.clip.sourceStart), "source_end": round(segment.clip.sourceEnd),
                     "speed": round(segment.clip.normalizedSpeed), "muted": .bool(segment.clip.muted), "enabled": .bool(!segment.clip.disabled),
                     "sound": .string(segment.clip.audioOffset == nil ? "linked" : "unlinked"), "sound_offset": segment.clip.audioOffset.map { round($0) } ?? .null])
        })
        main["sound_rows"] = .array(rows.kinds.map { .string($0.rawValue) })
        tracks.append(.object(main))
        if let music = project.music { tracks.append(.object(["track": .string("music"), "name": .string(music.name), "path": .string(music.path)])) }
        for sound in project.audioTracks {
            var row = state(.sound(sound.id))
            row["track"] = .string("sound")
            row["id"] = .string(sound.id.uuidString)
            row["name"] = .string(sound.name)
            row["pieces"] = .array(sound.pieces.map { .object(["start": round($0.at), "length": round($0.length)]) })
            tracks.append(.object(row))
        }
        return .object(["duration": round(model.timelineDuration), "playhead": round(model.clock.time), "tracks": .array(tracks)])
    }

    // MARK: Sessions

    static var sessionTools: [VideoAgentTool] {
        [
            VideoAgentTool(name: "begin_agent_session", description: "Start a run: everything you change from now on is grouped, shown to the user in the Agent panel's feed, and at the end they choose Keep or Revert all. Say what you're about to do in `goal`.", properties: ["goal": text("What you're going to do, in a sentence the user will read.")]) { model, args, dryRun in
                guard !dryRun else { return VideoAgentToolResult(json: .object(["ok": .bool(true), "dry_run": .bool(true)])) }
                let hub = VideoAgentHub.shared
                // The user decides about the last run first (Keep or Revert all).
                if let run = hub.run(for: model), run.reviewing {
                    return .error("The user is still reviewing your last run (Keep or Revert all in the Agent panel). Wait until they've chosen, then begin again.")
                }
                let run = hub.begin(on: model, goal: args["goal"]?.string ?? "")
                return VideoAgentToolResult(json: .object(["ok": .bool(true), "changes_so_far": .number(Double(run.changes.count))]))
            },
            VideoAgentTool(name: "end_agent_session", description: "End the run: the user sees what changed, marked on the timeline, and chooses Keep or Revert all. Summarize what you did in `summary`.", properties: ["summary": text("What you changed, briefly.")]) { model, args, dryRun in
                guard !dryRun else { return VideoAgentToolResult(json: .object(["ok": .bool(true), "dry_run": .bool(true)])) }
                let hub = VideoAgentHub.shared
                guard let run = hub.run(for: model) else { return VideoAgentToolResult(json: .object(["ok": .bool(true), "changes": .number(0)])) }
                if let summary = args["summary"]?.string, !summary.isEmpty {
                    hub.record(VideoAgentChange(date: Date(), title: summary, tool: "end_agent_session", time: model.clock.time, selection: nil, refused: true), on: model)
                }
                hub.end(on: model)
                return VideoAgentToolResult(json: .object(["ok": .bool(true), "changes": .number(Double(run.changes.filter { !$0.refused }.count))]))
            },
            VideoAgentTool(name: "seek", description: "Move the playhead to a timeline time (commands like split act there).", properties: ["time": number("Timeline seconds.")], required: ["time"]) { model, args, _ in
                guard let time = args["time"]?.double else { throw VideoAgentToolError.forAgent("time is needed") }
                model.seek(to: time)
                return VideoAgentToolResult(json: .object(["ok": .bool(true), "playhead": round(model.clock.time)]))
            },
            VideoAgentTool(name: "select", description: "Select something by its id from get_timeline or get_captions (kind: clip, item, caption, zoom), or nothing.", properties: ["kind": text("What it is.", choices: ["clip", "item", "caption", "zoom", "none"]), "id": text("Its id.")], required: ["kind"]) { model, args, _ in
                model.selection = try selection(model, args)
                return VideoAgentToolResult(json: .object(["ok": .bool(true), "selection": selectionJSON(model.selection)]))
            },
            VideoAgentTool(name: "undo", description: "Undo the last change (the user's or yours), like ⌘Z.", properties: [:]) { model, _, dryRun in
                guard model.canUndo else { throw VideoAgentToolError.forAgent("Nothing to undo.") }
                if dryRun { return VideoAgentToolResult(json: .object(["ok": .bool(true), "would_undo": .string(model.undoLabel.map { VideoEditDescription.undoTitle($0) } ?? "")])) }
                let label = model.undoLabel ?? ""
                model.undo()
                VideoAgentHub.shared.record(VideoAgentChange(date: Date(), title: VideoEditDescription.undoTitle(label), tool: "undo", time: model.clock.time, selection: nil), on: model)
                return VideoAgentToolResult(json: .object(["ok": .bool(true), "undid": .string(label)]))
            },
            VideoAgentTool(name: "redo", description: "Redo what was undone, like ⇧⌘Z.", properties: [:]) { model, _, dryRun in
                guard model.canRedo else { throw VideoAgentToolError.forAgent("Nothing to redo.") }
                if dryRun { return VideoAgentToolResult(json: .object(["ok": .bool(true), "would_redo": .string(model.redoLabel ?? "")])) }
                let label = model.redoLabel ?? ""
                model.redo()
                VideoAgentHub.shared.record(VideoAgentChange(date: Date(), title: VideoEditDescription.redoTitle(label), tool: "redo", time: model.clock.time, selection: nil), on: model)
                return VideoAgentToolResult(json: .object(["ok": .bool(true), "redid": .string(label)]))
            },
        ]
    }

    static func selection(_ model: VideoEditorModel, _ args: VideoAgentJSON) throws -> VideoEditorModel.Selection {
        let kind = args["kind"]?.string ?? "none"
        if kind == "none" { return .none }
        guard let id = try uuid(args, "id") else { throw VideoAgentToolError.forAgent("id is needed") }
        switch kind {
        case "clip":
            guard model.project.timelineClips.contains(where: { $0.id == id }) else { throw VideoAgentToolError.forAgent("No clip with that id on the main track.") }
            return .clip(id)
        case "item":
            guard model.project.layerItem(id) != nil else { throw VideoAgentToolError.forAgent("No item with that id above the main track.") }
            return .layer(id)
        case "caption":
            guard model.project.captions.contains(where: { $0.id == id }) else { throw VideoAgentToolError.forAgent("No caption with that id.") }
            return .caption(id)
        case "zoom":
            guard model.project.zoomRegions.contains(where: { $0.id == id }) else { throw VideoAgentToolError.forAgent("No zoom with that id.") }
            return .zoom(id)
        default:
            throw VideoAgentToolError.forAgent("kind is clip, item, caption, zoom or none")
        }
    }

    // MARK: Edits

    /// Runs an edit: optionally at a time and on a selection first; a dry
    /// run reports what would change and puts everything back.
    static func edit(_ model: VideoEditorModel, _ args: VideoAgentJSON, dryRun: Bool, tool: String, _ body: () -> Bool) throws -> VideoAgentToolResult {
        let before = model.project
        var done = false
        let prepare = {
            if let time = args["time"]?.double { model.seek(to: min(max(time, 0), model.timelineDuration)) }
            if args["kind"] != nil || args["id"] != nil, let selection = try? selection(model, args) { model.selection = selection }
        }
        if dryRun {
            let after = model.trying {
                prepare()
                done = body()
            }
            let changed = after != before
            return VideoAgentToolResult(json: .object([
                "ok": .bool(done || changed), "dry_run": .bool(true), "would_change": .bool(changed),
                "description": .string(changed ? VideoEditDescription.describe(from: before, to: after) : (done ? "Nothing in the project changes." : refusal(model))),
            ]), isError: !done && !changed)
        }
        let notice = model.notice?.id
        prepare()
        done = body()
        model.endGesture()
        let changed = model.project != before
        let title = changed ? VideoEditDescription.describe(from: before, to: model.project) : (done ? tool : refusal(model, since: notice))
        VideoAgentHub.shared.record(VideoAgentChange(date: Date(), title: title, tool: tool, time: model.clock.time, selection: model.selection == .none ? nil : model.selection, refused: !changed), on: model)
        guard done || changed else {
            return .error(refusal(model, since: notice))
        }
        return VideoAgentToolResult(json: .object(["ok": .bool(true), "changed": .bool(changed), "description": .string(title), "undo": .string(model.undoLabel ?? ""), "playhead": round(model.clock.time)]))
    }

    /// Why an edit didn't happen: the editor's message, when it gave one.
    static func refusal(_ model: VideoEditorModel, since earlier: UUID? = nil) -> String {
        if let notice = model.notice, notice.id != earlier { return "Not done: \(notice.message)" }
        return "Not done: nothing there to change (check the playhead and what's selected, or whether the track is locked)."
    }

    /// The editor's commands an agent may use (not the ones that open
    /// windows, record sound, use the clipboard or change the editor's own
    /// settings).
    static let agentCommands: [VideoEditCommand] = [
        .split, .splitAllTracks, .deleteLeft, .deleteRight, .delete, .addMarker, .freezeFrame, .reverse, .mirror, .rotate,
        .toggleEnabled, .group, .ungroup, .extractAudio, .markIn, .markOut, .addText, .addArrow, .addHighlight, .addBlur,
        .addKeyframe, .addTextClip, .makeCompound, .breakApart, .zoomCut,
        .duplicate, .deleteGapsAfterPlayhead, .toggleLoopPlayback, .revealInLibrary, .matchFrame,
    ]

    static func toolName(_ command: VideoEditCommand) -> String {
        command.rawValue.reduce(into: "") { name, character in
            if character.isUppercase { name += "_" + character.lowercased() } else { name.append(character) }
        }
    }

    static var commandTools: [VideoAgentTool] {
        agentCommands.map { command in
            VideoAgentTool(
                name: toolName(command),
                description: "\(command.title) (as in the editor\(command.shortcutHint.map { ", \($0)" } ?? "")). Acts at the playhead and on the selection; pass `time` to move the playhead first, and `kind` + `id` to select first.",
                properties: ["time": number("Move the playhead here first (timeline seconds)."), "kind": text("Select this first.", choices: ["clip", "item", "caption", "zoom"]), "id": text("The id to select first.")]
            ) { model, args, dryRun in
                try edit(model, args, dryRun: dryRun, tool: toolName(command)) { model.perform(command) }
            }
        }
    }

    // MARK: Edits with values

    static var parameterTools: [VideoAgentTool] {
        [
            VideoAgentTool(name: "set_caption_text", description: "Change a caption's words.", properties: ["caption_id": text("From get_captions."), "text": text("The new words.")], required: ["caption_id", "text"]) { model, args, dryRun in
                guard let id = try uuid(args, "caption_id"), let words = args["text"]?.string else { throw VideoAgentToolError.forAgent("caption_id and text are needed") }
                return try edit(model, args, dryRun: dryRun, tool: "set_caption_text") { model.perform(.setCaptionText(id, words)) }
            },
            VideoAgentTool(name: "remove_fillers", description: "Cut out filler words (um, uh) by their indexes from get_transcript.", properties: ["indexes": .object(["type": .string("array"), "items": .object(["type": .string("integer")]), "description": .string("Word indexes.")])], required: ["indexes"]) { model, args, dryRun in
                let indexes = (args["indexes"]?.array ?? []).compactMap { $0.double.map { Int($0) } }
                guard !indexes.isEmpty else { throw VideoAgentToolError.forAgent("indexes are needed") }
                return try edit(model, args, dryRun: dryRun, tool: "remove_fillers") { model.perform(.removeFillers(indexes)) }
            },
            VideoAgentTool(name: "set_clip_speed", description: "A main-track clip's speed (0.1 to 100; 1 is normal).", properties: ["clip_id": text("From get_timeline."), "speed": number("The speed.")], required: ["clip_id", "speed"]) { model, args, dryRun in
                guard let id = try uuid(args, "clip_id"), let speed = args["speed"]?.double else { throw VideoAgentToolError.forAgent("clip_id and speed are needed") }
                return try edit(model, .object(["kind": .string("clip"), "id": .string(id.uuidString)]), dryRun: dryRun, tool: "set_clip_speed") { model.perform(.clip(.setSpeed(speed))) }
            },
            VideoAgentTool(name: "set_transition", description: "A transition at the start of a main-track clip (its cut), or `everywhere` on every cut.", properties: ["clip_id": text("From get_timeline (not needed with everywhere)."), "transition": text("Which.", choices: VideoTransitionKind.allCases.map(\.rawValue)), "length": number("Seconds."), "everywhere": .object(["type": .string("boolean")])], required: ["transition"]) { model, args, dryRun in
                guard let raw = args["transition"]?.string, let kind = VideoTransitionKind(rawValue: raw) else { throw VideoAgentToolError.forAgent("transition is one of: \(VideoTransitionKind.allCases.map(\.rawValue).joined(separator: ", "))") }
                let length = args["length"]?.double
                if args["everywhere"]?.bool == true {
                    return try edit(model, args, dryRun: dryRun, tool: "set_transition") { model.perform(.clip(.transitionEverywhere(kind, length ?? 0.5))) }
                }
                guard let id = try uuid(args, "clip_id") else { throw VideoAgentToolError.forAgent("clip_id is needed") }
                return try edit(model, .object(["kind": .string("clip"), "id": .string(id.uuidString)]), dryRun: dryRun, tool: "set_transition") { model.perform(.clip(.setTransition(kind, length))) }
            },
            VideoAgentTool(name: "unlink_audio", description: "Separate a video's sound from its picture so it can move on its own (a main-track clip or an item above).", properties: ["kind": text("clip or item.", choices: ["clip", "item"]), "id": text("From get_timeline.")], required: ["kind", "id"]) { model, args, dryRun in
                try edit(model, args, dryRun: dryRun, tool: "unlink_audio") { args["kind"]?.string == "item" ? model.perform(.edit(.unlinkAudio)) : model.perform(.clip(.unlinkAudio)) }
            },
            VideoAgentTool(name: "link_audio", description: "Put unlinked sound back with its picture.", properties: ["kind": text("clip or item.", choices: ["clip", "item"]), "id": text("From get_timeline.")], required: ["kind", "id"]) { model, args, dryRun in
                try edit(model, args, dryRun: dryRun, tool: "link_audio") { args["kind"]?.string == "item" ? model.perform(.edit(.linkAudio)) : model.perform(.clip(.linkAudio)) }
            },
            VideoAgentTool(name: "move_audio", description: "Move unlinked sound: seconds after its picture (negative: before).", properties: ["kind": text("clip or item.", choices: ["clip", "item"]), "id": text("From get_timeline."), "offset": number("Seconds.")], required: ["kind", "id", "offset"]) { model, args, dryRun in
                guard let offset = args["offset"]?.double else { throw VideoAgentToolError.forAgent("offset is needed") }
                return try edit(model, args, dryRun: dryRun, tool: "move_audio") { args["kind"]?.string == "item" ? model.perform(.edit(.setAudioOffset(offset))) : model.perform(.clip(.setAudioOffset(offset))) }
            },
            VideoAgentTool(name: "set_item_value", description: "A setting of an item above the main track, at the playhead (a key there when it's animated): opacity, width, rotation, x, y, volume, intensity.", properties: ["item_id": text("From get_timeline."), "property": text("Which.", choices: VideoCurveLane.properties.map(\.rawValue)), "value": number("The value (see get_keyframes for ranges)."), "time": number("Playhead first (timeline seconds).")], required: ["item_id", "property", "value"]) { model, args, dryRun in
                guard let id = try uuid(args, "item_id"), let raw = args["property"]?.string, let property = VideoKeyProperty(rawValue: raw), let value = args["value"]?.double else { throw VideoAgentToolError.forAgent("item_id, property and value are needed") }
                var select = args
                if case .object(var object) = select { object["kind"] = .string("item"); object["id"] = .string(id.uuidString); select = .object(object) }
                return try edit(model, select, dryRun: dryRun, tool: "set_item_value") { model.perform(.edit(.setValue(property, value))) }
            },
            VideoAgentTool(name: "toggle_keyframe", description: "Add (or remove) a keyframe of an item's setting at the playhead.", properties: ["item_id": text("From get_timeline."), "property": text("Which.", choices: VideoCurveLane.properties.map(\.rawValue)), "time": number("Playhead first (timeline seconds).")], required: ["item_id", "property"]) { model, args, dryRun in
                guard let id = try uuid(args, "item_id"), let raw = args["property"]?.string, let property = VideoKeyProperty(rawValue: raw) else { throw VideoAgentToolError.forAgent("item_id and property are needed") }
                var select = args
                if case .object(var object) = select { object["kind"] = .string("item"); object["id"] = .string(id.uuidString); select = .object(object) }
                return try edit(model, select, dryRun: dryRun, tool: "toggle_keyframe") { model.perform(.edit(.toggleKeyframe(property))) }
            },
            VideoAgentTool(name: "set_sound_fades", description: "Fade an item's sound in and out at its ends (seconds).", properties: ["item_id": text("From get_timeline."), "fade_in": number("Seconds."), "fade_out": number("Seconds.")], required: ["item_id"]) { model, args, dryRun in
                guard let id = try uuid(args, "item_id") else { throw VideoAgentToolError.forAgent("item_id is needed") }
                return try edit(model, .object(["kind": .string("item"), "id": .string(id.uuidString)]), dryRun: dryRun, tool: "set_sound_fades") { model.perform(.edit(.setSoundFades(args["fade_in"]?.double ?? 0, args["fade_out"]?.double ?? 0))) }
            },
            VideoAgentTool(name: "place_media", description: "Put a file on the timeline at a time: only media already in the project (list_media). Anything else is refused.", properties: ["path": text("A path from list_media."), "time": number("Timeline seconds."), "where": text("On the main track's end, or a track above.", choices: ["above", "main"])], required: ["path"]) { model, args, dryRun in
                guard let path = args["path"]?.string else { throw VideoAgentToolError.forAgent("path is needed") }
                let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                guard model.agentMayPlace(url) else {
                    throw VideoAgentToolError.forAgent("Refused: \(url.lastPathComponent) isn't in this project. Ask the user to add it to the Library first.")
                }
                guard FileManager.default.fileExists(atPath: url.path), VideoMediaKind.of(url) != nil else { throw VideoAgentToolError.forAgent("That file isn't there, or isn't a video, picture or sound.") }
                let time = args["time"]?.double ?? model.clock.time
                if dryRun { return VideoAgentToolResult(json: .object(["ok": .bool(true), "dry_run": .bool(true), "would_change": .bool(true), "description": .string("Place \(url.lastPathComponent) at \(time) s")])) }
                let before = model.project
                await model.placeMedia([url], at: time, target: args["where"]?.string == "main" ? .main : .layer(.automatic))
                let changed = model.project != before
                let title = changed ? VideoEditDescription.describe(from: before, to: model.project) : "Not placed"
                VideoAgentHub.shared.record(VideoAgentChange(date: Date(), title: title, tool: "place_media", time: time, selection: nil, refused: !changed), on: model)
                guard changed else { return .error(refusal(model)) }
                return VideoAgentToolResult(json: .object(["ok": .bool(true), "description": .string(title)]))
            },
        ]
    }

    // MARK: The whole video (1.20.0)

    /// The editor's own one-click commands, and filling in the Export
    /// window (never exporting: the user clicks Export).
    static var wholeVideoTools: [VideoAgentTool] {
        [
            VideoAgentTool(name: "auto_captions", description: "Transcribe the narration on this Mac and lay it out as captions (the editor's Auto Captions). Takes a while on long videos; it answers when the captions are in.", properties: [:]) { model, _, dryRun in
                guard model.hasAudio else { throw VideoAgentToolError.forAgent("This video has no sound to transcribe.") }
                if dryRun {
                    return VideoAgentToolResult(json: .object(["ok": .bool(true), "dry_run": .bool(true), "would_change": .bool(true),
                                                               "description": .string(model.project.captions.isEmpty ? "Adds captions from the narration." : "Replaces the \(model.project.captions.count) captions with new ones from the narration.")]))
                }
                let before = model.project
                model.generateCaptions()
                // Until it's done (Stop cancels the wait, not the transcription).
                while model.captionTask != nil {
                    try await Task.sleep(nanoseconds: 300_000_000)
                }
                if let error = model.captionJob?.error { throw VideoAgentToolError.forAgent("Auto captions stopped: \(error)") }
                let changed = model.project != before
                let title = changed ? VideoEditDescription.describe(from: before, to: model.project) : "Auto Captions"
                VideoAgentHub.shared.record(VideoAgentChange(date: Date(), title: title, tool: "auto_captions", time: 0, selection: nil, refused: !changed), on: model)
                return VideoAgentToolResult(json: .object(["ok": .bool(true), "changed": .bool(changed), "captions": .number(Double(model.project.captions.count)), "undo": .string(model.undoLabel ?? "")]))
            },
            VideoAgentTool(name: "remove_ums", description: "Cut every filler word (um, uh) out of the video (the editor's Remove Ums). Needs a transcript: run auto_captions first.", properties: [:]) { model, args, dryRun in
                guard model.hasTranscript else { throw VideoAgentToolError.forAgent("There's no transcript yet: run auto_captions first.") }
                return try edit(model, args, dryRun: dryRun, tool: "remove_ums") {
                    guard model.fillerCount > 0 else { return false }
                    model.removeFillers()
                    return true
                }
            },
            VideoAgentTool(name: "shorten_pauses", description: "Shorten every long pause in the video (the editor's Shorten Pauses).", properties: [:]) { model, args, dryRun in
                try edit(model, args, dryRun: dryRun, tool: "shorten_pauses") {
                    guard !model.pauseRanges.isEmpty else { return false }
                    model.shortenPauses()
                    return true
                }
            },
            VideoAgentTool(name: "apply_my_style", description: "Apply the user's My Style preset to the video (background, frame, cursor, zoom, captions, keys and camera bubble).", properties: [:]) { model, args, dryRun in
                guard model.myStyle != nil else { throw VideoAgentToolError.forAgent("The user hasn't chosen a My Style yet (Presets ▸ Edit Presets ▸ Use as My Style).") }
                return try edit(model, args, dryRun: dryRun, tool: "apply_my_style") {
                    model.applyMyStyle()
                    return true
                }
            },
            VideoAgentTool(name: "prepare_export", description: "Fill in the Export window and open it. It doesn't export: the user checks it and clicks Export. Leave out what the user didn't ask for.", properties: [
                "preset": text("Quality: web (smallest), social (the usual) or studio (most detail).", choices: VideoExportSettings.Quality.allCases.map(\.rawValue)),
                "resolution": .object(["type": .string("integer"), "description": .string("Height in pixels."), "enum": .array(VideoExportSettings.Resolution.allCases.map { .number(Double($0.rawValue)) })]),
                "format": text("The file format.", choices: VideoExportSettings.Format.allCases.map(\.rawValue)),
                "fps": .object(["type": .string("integer"), "description": .string("Frames per second."), "enum": .array([24, 25, 30, 50, 60].map { .number(Double($0)) })]),
                "file_name": text("The file's name, without its extension."),
            ], readOnly: true) { model, args, _ in
                var settings = model.exportSettings
                if let raw = args["preset"]?.string {
                    guard let quality = VideoExportSettings.Quality(rawValue: raw) else { throw VideoAgentToolError.forAgent("preset is web, social or studio") }
                    settings.quality = quality
                }
                if let height = args["resolution"]?.double {
                    guard let resolution = VideoExportSettings.Resolution(rawValue: Int(height)) else { throw VideoAgentToolError.forAgent("resolution is 720, 1080, 1440 or 2160") }
                    settings.resolution = resolution
                }
                if let raw = args["format"]?.string {
                    guard let format = VideoExportSettings.Format(rawValue: raw) else { throw VideoAgentToolError.forAgent("format is one of \(VideoExportSettings.Format.allCases.map(\.rawValue).joined(separator: ", "))") }
                    settings.format = format
                }
                if let fps = args["fps"]?.double {
                    guard [24, 25, 30, 50, 60].contains(Int(fps)) else { throw VideoAgentToolError.forAgent("fps is 24, 25, 30, 50 or 60") }
                    settings.fps = Int(fps)
                }
                // Opening the window first: it fills in the project's own
                // settings, then these go on top.
                model.isExportPresented = true
                model.exportSettings = settings
                // A name only, never a place: "../../x" or "/tmp/x" becomes "x".
                if let raw = args["file_name"]?.string, let name = VideoAgentLimits.fileName(raw) {
                    model.exportName = (name as NSString).deletingPathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
                }
                return VideoAgentToolResult(json: .object([
                    "ok": .bool(true), "opened": .bool(true), "exported": .bool(false),
                    "preset": .string(model.exportSettings.quality.rawValue), "resolution": .number(Double(model.exportSettings.resolution.rawValue)),
                    "format": .string(model.exportSettings.format.rawValue), "fps": .number(Double(model.exportSettings.fps)), "file_name": .string(model.exportName),
                    "note": .string("The Export window is open with these settings. The user clicks Export to save the file."),
                ]))
            },
        ]
    }

    // MARK: Tacks

    static var tackTools: [VideoAgentTool] {
        [
            VideoAgentTool(name: "add_tack", description: "Pin a note or a question for the user to a moment (it follows its clip). Use it to explain a choice or ask before something you're unsure of. The user answers in the Agent panel; read answers with list_tacks.", properties: ["time": number("Timeline seconds."), "text": text("The note or question."), "question": .object(["type": .string("boolean"), "description": .string("Ask for an answer.")]), "item_id": text("Pin it to this item above the main track (optional).")], required: ["time", "text"]) { model, args, dryRun in
                guard let time = args["time"]?.double, let words = args["text"]?.string, !words.isEmpty else { throw VideoAgentToolError.forAgent("time and text are needed") }
                if dryRun { return VideoAgentToolResult(json: .object(["ok": .bool(true), "dry_run": .bool(true)])) }
                let hub = VideoAgentHub.shared
                if hub.run(for: model) == nil { hub.begin(on: model, goal: "") }
                let tack = VideoTack(anchor: model.tackAnchor(at: time, item: try uuid(args, "item_id")), text: words, isQuestion: args["question"]?.bool ?? false)
                model.changeTacks { $0.append(tack) }
                hub.record(VideoAgentChange(date: Date(), title: (tack.isQuestion ? "? " : "") + words, tool: "add_tack", time: time, selection: nil, refused: true), on: model)
                return VideoAgentToolResult(json: .object(["ok": .bool(true), "tack_id": .string(tack.id.uuidString)]))
            },
            VideoAgentTool(name: "list_tacks", description: "The project's notes and questions (yours, and any left in earlier sessions: they're saved with the project), where they are now, and the user's answers (or that they dismissed them).", properties: [:], readOnly: true) { model, _, _ in
                let tacks = model.project.tacks ?? []
                return VideoAgentToolResult(json: .object(["tacks": .array(tacks.map { tack in
                    .object(["id": .string(tack.id.uuidString), "text": .string(tack.text), "question": .bool(tack.isQuestion), "time": model.timelineTime(of: tack).map { round($0) } ?? .null,
                             "answer": tack.answer.map { .string($0) } ?? .null, "dismissed": .bool(tack.dismissed)])
                })]))
            },
        ]
    }
}

extension VideoEditCommand {
    /// Its key in the editor, for the tool's description.
    var shortcutHint: String? { nil }
}

// MARK: - The project's side

extension VideoEditorModel {
    var webcamRecordingForAgent: VideoWebcamRecording? { recording?.webcam }

    /// The project's folder: its project file's, or its recording folder.
    var agentProjectFolder: URL? {
        if let file = projectFileURL { return file.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() }
        if projectFolder != nil { return project.sourceURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() }
        return nil
    }

    /// What an agent may place: media already in the project, nothing else
    /// (hard limit 4: agents never import or open a file).
    func agentMayPlace(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return project.mediaEntries(camera: webcamRecordingForAgent).contains {
            URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path == path
        }
    }

    /// The frame at `time` as it exports (no camera), as a PNG 640 wide.
    func agentFrame(at time: Double) async -> Data? {
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: sourceDuration, recording: recording)
        let sourceTime = plan.sourceTime(forTimelineTime: time)
        let asset = AVURLAsset(url: project.sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let source = (try? await generator.image(at: CMTime(seconds: max(sourceTime, 0), preferredTimescale: 600)).image).map { CIImage(cgImage: $0) }
        let width = 640.0
        let aspect = project.sourceWidth > 0 ? project.sourceHeight / project.sourceWidth : 9.0 / 16
        let size = CGSize(width: width, height: (width * aspect).rounded())
        let image = VideoFrameRenderer().render(source: source, timelineTime: time, plan: plan, outputSize: size, options: VideoFrameRenderer.Options(frameRate: 30))
        guard let cg = VideoRenderContext.shared.createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

extension VideoDemoEditorWindowController {
    /// The project an agent works on: the front editor.
    static var agentModel: VideoEditorModel? { frontControllerForAgent()?.model }
}
