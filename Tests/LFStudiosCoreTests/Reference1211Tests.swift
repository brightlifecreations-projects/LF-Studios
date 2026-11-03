import AppKit
import AVFoundation
import CryptoKit
import XCTest
@testable import LFStudiosCore

/// 1.22.0 changed only how the code is laid out, so it must behave exactly as
/// 1.21.1 did. These compare it with what 1.21.1 itself recorded
/// (Fixtures/Reference-1.21.1, written by running this test on 1.21.1 with
/// LF_REF_RECORD=1): the commands, AI tools, menus and keys; the bytes of
/// saved projects; and every older kind of project's export (picture and
/// sound). Checksums and 64 × 36 frame thumbnails, so the fixtures stay small.
@MainActor
final class Reference1211Tests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Reference-1.21.1", isDirectory: true)
    private var recording: Bool { ProcessInfo.processInfo.environment["LF_REF_RECORD"] != nil }
    private var suiteName: String!
    private var directory: URL!

    override func setUp() async throws {
        _ = NSApplication.shared
        suiteName = "LFStudiosCoreTests.Reference1211.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        L10n.use("en")
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-ref-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        L10n.use(nil)
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        try? FileManager.default.removeItem(at: directory)
    }

    /// Writes `value` as the reference (recording), or compares it with the
    /// saved one, key by key.
    private func check(_ name: String, _ value: [String: String], file: StaticString = #filePath, line: UInt = #line) throws {
        let url = Self.folder.appendingPathComponent(name)
        if recording {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url)
            return
        }
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String], "\(name) is missing", file: file, line: line)
        XCTAssertEqual(Set(value.keys), Set(saved.keys), "\(name): the same entries", file: file, line: line)
        for key in value.keys.sorted() where saved[key] != nil {
            if key.hasSuffix(".frames"), let a = Self.thumbnails(value[key]!), let b = Self.thumbnails(saved[key]!) {
                // Pictures: the encoder's own run-to-run noise is allowed, nothing more.
                let worst = a.count == b.count ? zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0 : 255
                if ProcessInfo.processInfo.environment["LF_REF_VERBOSE"] != nil { print("REF \(key) worst \(worst)") }
                XCTAssertLessThanOrEqual(worst, Self.frameTolerance, "\(name): \(key) differs by \(worst)", file: file, line: line)
                continue
            }
            XCTAssertEqual(value[key], saved[key], "\(name): \(key)", file: file, line: line)
        }
    }

    /// The most a 64 × 36 frame thumbnail's pixel may differ (of 255): the
    /// export's own noise between runs of the same code.
    static let frameTolerance = 4

    /// A frame at 64 × 36, RGBA: small enough to keep, fine enough to see
    /// anything that moved, changed colour, or appeared.
    private static func thumbnail(_ image: CGImage) throws -> Data {
        var data = Data(count: 64 * 36 * 4)
        try data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.featureUnsupported) }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 36))
        }
        return data
    }

    private static func thumbnails(_ text: String) -> [UInt8]? {
        guard let data = Data(base64Encoded: text), let raw = try? (data as NSData).decompressed(using: .zlib) else { return nil }
        return [UInt8](raw as Data)
    }

    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: Commands, AI tools, menus and keys

    func testCommandsToolsMenusAndKeysAreUnchanged() throws {
        var entries: [String: String] = [:]
        entries["commands"] = VideoEditCommand.allCases.map(\.rawValue).joined(separator: " ")
        for preset in VideoKeymapPreset.allCases {
            entries["keys.\(preset.rawValue)"] = VideoKeymap.keys(for: preset).map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: " ")
        }
        entries["keys.editable"] = VideoKeymap.editable.map(\.rawValue).joined(separator: " ")
        entries["agentCommands"] = VideoAgentTools.agentCommands.map(\.rawValue).joined(separator: " ")
        for tool in VideoAgentTools.all {
            entries["tool.\(tool.name)"] = "\(tool.description) \(try Self.json(tool.schema))"
        }
        for shortcut in LFStudiosShortcut.allCases {
            entries["shortcut.\(shortcut.name.rawValue)"] = "\(shortcut.title) \(shortcut.section.rawValue) \(shortcut.name.defaultShortcut.map { String(describing: $0) } ?? "none")"
        }

        let previous = NSApp.mainMenu
        defer { NSApp.mainMenu = previous }
        AppDelegate().setupMainMenu()
        var menus: [String] = []
        func walk(_ menu: NSMenu, _ path: String) {
            for item in menu.items {
                let title = item.isSeparatorItem ? "—" : item.title
                menus.append("\(path)/\(title) [\(item.keyEquivalent)|\(item.keyEquivalentModifierMask.rawValue)|\(item.action.map(NSStringFromSelector) ?? "")]")
                if let submenu = item.submenu { walk(submenu, "\(path)/\(title)") }
            }
        }
        walk(try XCTUnwrap(NSApp.mainMenu), "")
        entries["menus"] = menus.joined(separator: "\n")
        try check("interface.json", entries)
    }

    // MARK: Saved projects

    /// The manifest as ⌘S writes it, with what changes on every run (the
    /// date, new ids, file bookmarks, the test media's size) put in a fixed form.
    private func savedBytes(_ model: VideoEditorModel, _ name: String) throws -> String {
        let package = directory.appendingPathComponent("\(name).lfs", isDirectory: true)
        try VideoProjectPackage.save(model.projectContents, to: package, mode: .included, appVersion: "reference")
        var text = String(decoding: try Data(contentsOf: VideoProjectPackage.manifestURL(package)), as: UTF8.self)
        text = text.replacingOccurrences(of: #""(savedAt|createdAt|modified)" : [-0-9.e+]+"#, with: "\"$1\" : 0", options: .regularExpression)
        // The test's recording is made afresh each run; a busy Mac encodes it a few bytes different.
        text = text.replacingOccurrences(of: #""size" : [0-9]+"#, with: "\"size\" : 0", options: .regularExpression)
        // A macOS file bookmark holds the temporary folder and the file's disk id.
        text = text.replacingOccurrences(of: #""bookmark" : "[^"]*""#, with: "\"bookmark\" : \"…\"", options: .regularExpression)
        // Ids: numbered in the order they first appear.
        let pattern = try NSRegularExpression(pattern: "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}")
        var ids: [String: String] = [:]
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let id = String(text[Range(match.range, in: text)!])
            if ids[id] == nil { ids[id] = "id-\(ids.count)" }
        }
        for (id, number) in ids { text = text.replacingOccurrences(of: id, with: number) }
        return text
    }

    func testSavedProjectsAreByteIdentical() async throws {
        var options = VideoEditorTestModel.Options()
        options.seconds = 8
        options.audio = true
        options.keystrokes = [VideoKeystrokeEvent(time: 1.5, keys: ["⌘", "S"])]
        let model = try await VideoEditorTestModel.make(in: directory, name: "Reference.mp4", options)
        var entries: [String: String] = [:]
        func save(_ name: String) throws {
            let text = try savedBytes(model, name)
            if let dump = ProcessInfo.processInfo.environment["LF_REF_DUMP"] { try text.write(toFile: "\(dump)/\(name).json", atomically: true, encoding: .utf8) }
            entries[name] = Self.sha(Data(text.utf8))
        }
        try save("fresh")

        // Cuts, speed, fades, a mute and a deleted range.
        model.seek(to: 2)
        model.perform(.split)
        model.seek(to: 5)
        model.perform(.split)
        model.endGesture()
        let clips = model.segments.map(\.id)
        model.setClipSpeed(clips[1], 2)
        model.setClipFade(clips[0], fadeIn: 0.3)
        model.setClipFade(clips[2], fadeOut: 0.5)
        model.setClipMuted(clips[2], true)
        model.deleteRange(VideoDemoTimelineRange(start: 0.5, end: 1))
        model.endGesture()
        try save("cuts")

        // Zooms, an overlay, captions, the look.
        _ = model.addZoom(at: 1)
        model.addOverlay(.text)
        model.mutate { $0.captions = [VideoCaptionLine(start: 0.2, end: 1.5, text: "Open the settings")] }
        model.setStyle { $0.background = .gradient("graphite"); $0.shadow = 0.6 }
        model.endGesture()
        try save("effects")

        // A picture above the main track, solo and a renamed track (1.21.0).
        let picture = directory.appendingPathComponent("Shot.png")
        try VideoInspection.writePNG(to: picture, size: CGSize(width: 320, height: 180), color: .systemTeal)
        _ = await model.addLayerItem(from: picture, at: 1)
        let layer = VideoTimelineTrack.layer(model.project.layerTracks[0].id)
        _ = model.renameTrack(layer, to: "B-roll")
        _ = model.toggleSolo(.clips)
        try save("layers")

        // Undone back to the start: as fresh again.
        while model.canUndo { model.undo() }
        try save("undone")
        try check("projects.json", entries)
    }

    // MARK: Older projects' exports

    /// The sound as the export builds it: each track's pieces (which file,
    /// from where, to where, how fast) and its level every 10 ms. (The
    /// decoded sound itself differs a little from run to run in Apple's
    /// mixer, so the recipe is what's compared; Project114/117/118 tests
    /// still measure the real loudness.)
    private static func soundRecipe(_ edit: VideoEditComposition) -> String {
        func t(_ time: CMTime) -> String { String(format: "%.4f", time.seconds) }
        var lines: [String] = []
        let parameters = edit.audioMix?.inputParameters ?? []
        let length = edit.duration.seconds + max(edit.musicDuration - edit.duration.seconds, 0)
        for (index, track) in edit.mixedAudioTracks.enumerated() {
            lines.append("track \(index)")
            for segment in track.segments {
                let mapping = segment.timeMapping
                lines.append(segment.isEmpty ? "  empty → \(t(mapping.target.start))+\(t(mapping.target.duration))"
                    : "  \(segment.sourceURL?.lastPathComponent ?? "?")#\(segment.sourceTrackID) \(t(mapping.source.start))+\(t(mapping.source.duration)) → \(t(mapping.target.start))+\(t(mapping.target.duration))")
            }
            guard let parameter = parameters.first(where: { $0.trackID == track.trackID }) else { continue }
            lines.append("  pitch \(parameter.audioTimePitchAlgorithm?.rawValue ?? "-")")
            var levels: [String] = []
            for step in 0...Int(length * 100) {
                let time = CMTime(seconds: Double(step) / 100, preferredTimescale: 600)
                var start: Float = 0, end: Float = 0
                var range = CMTimeRange.zero
                if parameter.getVolumeRamp(for: time, startVolume: &start, endVolume: &end, timeRange: &range), range.duration.seconds > 0 {
                    let fraction = Float((time.seconds - range.start.seconds) / range.duration.seconds)
                    levels.append(String(format: "%.4f", start + (end - start) * min(max(fraction, 0), 1)))
                } else {
                    levels.append(String(format: "%.4f", start))
                }
            }
            lines.append("  levels " + levels.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    /// Exports `project` and adds its picture (small thumbnails of decoded
    /// frames) and the checksum of its sound recipe.
    private func export(_ name: String, _ project: VideoDemoProject, recording: VideoDemoRecordingMetadata?, times: [Double], into entries: inout [String: String]) async throws {
        var settings = VideoExportSettings()
        settings.resolution = .p720
        settings.fps = 30
        settings.endCard = false
        let prepared = try await VideoDemoExporter.prepareEdit(project: project, recording: recording, settings: settings)
        entries["\(name).sound"] = Self.sha(Data(Self.soundRecipe(prepared.edit).utf8))
        let url = directory.appendingPathComponent("\(name).mp4")
        try await VideoDemoExporter.export(project: project, recording: recording, destinationURL: url, settings: settings)
        var frames = Data()
        for time in times {
            frames.append(try Self.thumbnail(VideoInspection.frame(of: url, at: time)))
        }
        entries["\(name).frames"] = try (frames as NSData).compressed(using: .zlib).base64EncodedString()
    }

    func testOlderProjectsExportTheSame() async throws {
        var entries: [String: String] = [:]
        let old = OldProjectPixelTests()
        let oldMedia = try await old.media()
        for kind in old.projects(oldMedia) {
            try await export("1.13-\(kind.name)", kind.project, recording: kind.recording, times: kind.times + [0.2, 3.5], into: &entries)
        }
        let p114 = Project114PixelTests()
        let media114 = try await p114.media()
        for kind in p114.projects(media114) {
            try await export("1.14-\(kind.name)", kind.project, recording: kind.recording, times: kind.times + [0.2], into: &entries)
        }
        let p117 = Project117SoundTests()
        for kind in p117.projects(try await p117.media()) {
            try await export("1.17-\(kind.name)", kind.project, recording: kind.recording, times: [0.2, 1.1, 2.3], into: &entries)
        }
        let p118 = Project118SoundTests()
        for kind in p118.projects(try await p118.media()) {
            try await export("1.18-\(kind.name)", kind.project, recording: kind.recording, times: [0.2, 1.1, 2.3], into: &entries)
        }
        try check("exports.json", entries)
    }
}
