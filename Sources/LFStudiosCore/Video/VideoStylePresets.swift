import Combine
import Foundation

/// A look saved under a name (Style ▸ Presets): what `VideoStylePreset`
/// holds, plus whether applying it also sets the aspect ratio.
struct VideoNamedStylePreset: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var style: VideoStylePreset
    /// "Include aspect ratio" in Save as Preset…: off, the video keeps its
    /// own aspect ratio when the preset is applied.
    var includesAspectRatio: Bool

    init(id: UUID = UUID(), name: String, style: VideoStylePreset, includesAspectRatio: Bool = false) {
        self.id = id
        self.name = name
        self.style = style
        self.includesAspectRatio = includesAspectRatio
    }

    private enum CodingKeys: String, CodingKey { case id, name, style, includesAspectRatio }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        style = (try? c.decode(VideoStylePreset.self, forKey: .style)) ?? .factory
        includesAspectRatio = (try? c.decode(Bool.self, forKey: .includesAspectRatio)) ?? false
    }

    /// Whether the project already looks like this (its aspect ratio only
    /// counts when the preset sets it).
    func matches(_ project: VideoDemoProject) -> Bool {
        var current = project.style
        if !includesAspectRatio { current.aspectPreset = style.aspectPreset }
        // The pointer's visibility is the recording's, never the preset's.
        current.cursor.visible = style.cursor.visible
        // A preset without an auto-zoom choice matches either way.
        if style.autoZoom == nil { current.autoZoom = nil }
        return current == style
    }
}

extension VideoDemoProject {
    /// Applies a preset; the aspect ratio only when the preset includes it.
    mutating func apply(preset: VideoNamedStylePreset) {
        let aspect = aspectPreset
        apply(style: preset.style)
        if !preset.includesAspectRatio { aspectPreset = aspect }
    }
}

/// Every saved preset and which one new recordings start from.
struct VideoStylePresetLibrary: Codable, Equatable {
    var presets: [VideoNamedStylePreset] = []
    /// The preset new recordings use (nil: the built-in LF Studios look).
    var defaultID: UUID?

    init(presets: [VideoNamedStylePreset] = [], defaultID: UUID? = nil) {
        self.presets = presets
        self.defaultID = defaultID
    }

    private enum CodingKeys: String, CodingKey { case presets, defaultID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        presets = (try? c.decode([VideoNamedStylePreset].self, forKey: .presets)) ?? []
        defaultID = try? c.decodeIfPresent(UUID.self, forKey: .defaultID)
        if let defaultID, !presets.contains(where: { $0.id == defaultID }) { self.defaultID = nil }
    }

    /// My Style: the preset Apply my style puts on a video. It's kept as
    /// `defaultID`, where the "default for new recordings" used to be, so a
    /// default chosen before 1.2.0 became My Style by itself.
    var myStyleID: UUID? { defaultID }
    var myStyle: VideoNamedStylePreset? { defaultPreset }
    mutating func setMyStyle(_ id: UUID?) { setDefault(id) }

    var defaultPreset: VideoNamedStylePreset? {
        defaultID.flatMap { id in presets.first { $0.id == id } }
    }

    func preset(_ id: UUID) -> VideoNamedStylePreset? {
        presets.first { $0.id == id }
    }

    /// `name`, or "name 2", "name 3"… when another preset has it.
    func uniqueName(_ name: String, excluding id: UUID? = nil) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(presets.filter { $0.id != id }.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    @discardableResult
    mutating func add(name: String, style: VideoStylePreset, includesAspectRatio: Bool) -> VideoNamedStylePreset {
        let preset = VideoNamedStylePreset(name: uniqueName(name), style: style, includesAspectRatio: includesAspectRatio)
        presets.append(preset)
        return preset
    }

    mutating func rename(_ id: UUID, to name: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets[index].name = uniqueName(trimmed, excluding: id)
    }

    /// "Update with current style" (keeps the name and the aspect setting).
    mutating func update(_ id: UUID, with style: VideoStylePreset) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].style = style
    }

    mutating func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
        if defaultID == id { defaultID = nil }
    }

    mutating func setDefault(_ id: UUID?) {
        defaultID = id.flatMap { id in presets.contains { $0.id == id } ? id : nil }
    }

    /// Imported presets, as new ones (new ids, names kept apart from the
    /// ones already here).
    @discardableResult
    mutating func adding(_ imported: [VideoNamedStylePreset]) -> [VideoNamedStylePreset] {
        var added: [VideoNamedStylePreset] = []
        for var preset in imported {
            preset.id = UUID()
            let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            preset.name = uniqueName(name.isEmpty ? L("Imported Preset") : name)
            presets.append(preset)
            added.append(preset)
        }
        return added
    }
}

// MARK: - Storage

/// The preset library on disk (LF Studios/Presets/presets.json), shared by
/// every editor window. The look saved before presets existed becomes the
/// first preset, "My Look", and stays the default for new recordings.
@MainActor
final class VideoStylePresetStore: ObservableObject {
    static let shared = VideoStylePresetStore()

    @Published private(set) var library = VideoStylePresetLibrary()

    private init() {
        reloadIfNeeded()
    }
    /// The storage root the library was read from (tests swap it), and the
    /// file's date then (written elsewhere since: read again).
    private var loadedRoot: URL?
    private var loadedDate: Date?

    /// The look from before presets, in UserDefaults (left in place).
    nonisolated static let legacyDefaultsKey = "videoDefaultStylePreset"

    nonisolated static func directory(root: URL = VideoStorageLocation.root) -> URL {
        root.appendingPathComponent("LF Studios", isDirectory: true).appendingPathComponent("Presets", isDirectory: true)
    }

    nonisolated static func fileURL(root: URL = VideoStorageLocation.root) -> URL {
        directory(root: root).appendingPathComponent("presets.json", isDirectory: false)
    }

    /// The library, read on first use (and again when the storage root moved).
    var current: VideoStylePresetLibrary {
        reloadIfNeeded()
        return library
    }

    func reloadIfNeeded() {
        let root = VideoStorageLocation.root
        let date = Self.modificationDate(root: root)
        guard loadedRoot != root || loadedDate != date else { return }
        loadedRoot = root
        loadedDate = date
        let loaded = Self.load(root: root)
        if loaded != library { library = loaded }
    }

    nonisolated private static func modificationDate(root: URL) -> Date? {
        (try? fileURL(root: root).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    nonisolated static func load(root: URL, defaults: UserDefaults = .standard) -> VideoStylePresetLibrary {
        let url = fileURL(root: root)
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(VideoStylePresetLibrary.self, from: data) {
            return saved
        }
        // First run with presets: the single saved look carries over, with
        // its aspect ratio, exactly as new recordings used it.
        var library = VideoStylePresetLibrary()
        if let data = defaults.data(forKey: legacyDefaultsKey), let look = try? JSONDecoder().decode(VideoStylePreset.self, from: data) {
            let mine = library.add(name: L("My Look"), style: look, includesAspectRatio: true)
            library.setDefault(mine.id)
        }
        return library
    }

    nonisolated static func save(_ library: VideoStylePresetLibrary, root: URL) -> Bool {
        let url = fileURL(root: root)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(library).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Changes the library and writes it at once.
    @discardableResult
    func change<T>(_ edit: (inout VideoStylePresetLibrary) -> T) -> T {
        reloadIfNeeded()
        var next = library
        let result = edit(&next)
        if next != library {
            library = next
            _ = Self.save(next, root: VideoStorageLocation.root)
            loadedDate = Self.modificationDate(root: VideoStorageLocation.root)
        }
        return result
    }
}

// MARK: - Sharing (Export / Import Presets…)

/// A `.lfstudiospresets` file: presets to hand to someone else. Pictures
/// chosen as backgrounds travel inside it, since the path on this Mac means
/// nothing on another.
struct VideoStylePresetFile: Codable {
    static let kind = "lfstudios-style-presets"
    static let currentVersion = 1
    static let fileExtension = "lfstudiospresets"
    /// Background paths in the file that point at an embedded picture.
    static let embeddedPrefix = "lfstudios-embedded:"
    /// Files exported while the app was called ShotStyle.
    static let legacyKind = "shotstyle-style-presets"
    static let legacyEmbeddedPrefix = "shotstyle-embedded:"
    static let legacyFileExtension = "shotstylepresets"

    var kind: String
    var version: Int
    var presets: [VideoNamedStylePreset]
    /// Embedded background pictures by name.
    var images: [String: Data]

    enum ReadError: Error, Equatable {
        case notAPresetFile
    }

    /// The file for `presets`, with each custom background picture inside.
    static func make(_ presets: [VideoNamedStylePreset]) -> VideoStylePresetFile {
        var images: [String: Data] = [:]
        var packed = presets
        for index in packed.indices {
            guard case .image(let path) = packed[index].style.background,
                  let data = FileManager.default.contents(atPath: path) else { continue }
            let ext = URL(fileURLWithPath: path).pathExtension
            let name = "\(packed[index].id.uuidString)\(ext.isEmpty ? "" : ".\(ext)")"
            images[name] = data
            packed[index].style.background = .image(embeddedPrefix + name)
        }
        return VideoStylePresetFile(kind: kind, version: currentVersion, presets: packed, images: images)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Reads a file written by any LF Studios version (newer fields are
    /// skipped, missing ones take their defaults).
    static func read(_ data: Data) throws -> VideoStylePresetFile {
        guard let file = try? JSONDecoder().decode(VideoStylePresetFile.self, from: data), file.kind == kind || file.kind == legacyKind else {
            throw ReadError.notAPresetFile
        }
        return file
    }

    /// The presets, their embedded pictures written to `imagesDirectory`
    /// and pointed at there.
    func unpacked(imagesDirectory: URL) -> [VideoNamedStylePreset] {
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        return presets.map { preset in
            var preset = preset
            if case .image(let path) = preset.style.background,
               let prefix = [Self.embeddedPrefix, Self.legacyEmbeddedPrefix].first(where: { path.hasPrefix($0) }) {
                let name = String(path.dropFirst(prefix.count))
                let ext = URL(fileURLWithPath: name).pathExtension
                let url = imagesDirectory.appendingPathComponent("\(UUID().uuidString)\(ext.isEmpty ? "" : ".\(ext)")")
                if let data = images[name], (try? data.write(to: url, options: .atomic)) != nil {
                    preset.style.background = .image(url.path)
                } else {
                    // The picture didn't come along: the built-in look.
                    preset.style.background = VideoStylePreset.factory.background
                }
            }
            return preset
        }
    }
}

extension VideoStylePresetFile {
    private enum CodingKeys: String, CodingKey { case kind, version, presets, images }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        presets = (try? c.decode([VideoNamedStylePreset].self, forKey: .presets)) ?? []
        images = (try? c.decode([String: Data].self, forKey: .images)) ?? [:]
    }
}
