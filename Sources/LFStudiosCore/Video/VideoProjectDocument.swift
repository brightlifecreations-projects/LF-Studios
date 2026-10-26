import Foundation

/// An LF Studios project file: `Name.lfstudios`, a folder macOS shows as one
/// file. It holds `project.json` (the edit and every recording's pointer,
/// click, and key data) and, with "Include media", the media itself:
///
///     Name.lfstudios/
///         project.json
///         Media/      the recordings, camera videos, music, pictures
///         Fonts/      fonts added to LF Studios that the project uses
///
/// "Link to media" keeps only paths (and bookmarks to find moved files):
/// small, for this Mac. Paths inside the package are written relative
/// (`@package/Media/…`), so the package can move anywhere.
struct VideoProjectDocument: Codable {
    static let format = "lfstudios-project"
    /// Projects saved while the app was called ShotStyle.
    static let legacyFormat = "shotstyle-project"
    static let legacyFileExtension = "shotstyle"
    static let legacyTypeIdentifier = "com.shotstyle.project"
    /// Both names open.
    static let openableExtensions: Set<String> = [fileExtension, legacyFileExtension]
    /// Bump when the layout changes, and teach `migrate` the step up, so
    /// every older project still opens.
    static let currentVersion = 1
    static let fileExtension = "lfstudios"
    static let typeIdentifier = "com.lfstudios.project"
    static let manifestName = "project.json"
    static let mediaFolder = "Media"
    static let fontsFolder = "Fonts"
    /// The prefix of paths inside the package.
    static let packagePrefix = "@package/"

    enum MediaMode: String, Codable {
        /// Copies inside the package: opens on any Mac.
        case included
        /// Paths to the originals: small, this Mac only.
        case linked
    }

    /// Where a packaged file came from, so saving again skips files that
    /// haven't changed instead of copying them over.
    struct Origin: Codable, Equatable {
        var path: String
        var size: Int64
        var modified: Date
    }

    var format: String
    var version: Int
    var savedAt: Date
    /// The LF Studios version that saved it (for support questions).
    var appVersion: String?
    var mediaMode: MediaMode
    var project: VideoDemoProject
    /// The main recording's data: pointer path, clicks, keys, camera.
    var recording: VideoDemoRecordingMetadata?
    /// Each added recording's data, by its source id.
    var sourceRecordings: [String: VideoDemoRecordingMetadata]
    /// Packaged media by file name → the original it was copied from.
    var origins: [String: Origin]
    /// Linked media: a bookmark per path, to find moved files.
    var bookmarks: [String: Data]

    private enum CodingKeys: String, CodingKey {
        case format, version, savedAt, appVersion, mediaMode, project, recording, sourceRecordings, origins, bookmarks
    }

    init(format: String = Self.format, version: Int = Self.currentVersion, savedAt: Date = Date(), appVersion: String? = nil, mediaMode: MediaMode, project: VideoDemoProject, recording: VideoDemoRecordingMetadata?, sourceRecordings: [String: VideoDemoRecordingMetadata] = [:], origins: [String: Origin] = [:], bookmarks: [String: Data] = [:]) {
        self.format = format
        self.version = version
        self.savedAt = savedAt
        self.appVersion = appVersion
        self.mediaMode = mediaMode
        self.project = project
        self.recording = recording
        self.sourceRecordings = sourceRecordings
        self.origins = origins
        self.bookmarks = bookmarks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        savedAt = (try? c.decode(Date.self, forKey: .savedAt)) ?? Date(timeIntervalSince1970: 0)
        appVersion = try? c.decodeIfPresent(String.self, forKey: .appVersion)
        mediaMode = (try? c.decode(MediaMode.self, forKey: .mediaMode)) ?? .linked
        project = try c.decode(VideoDemoProject.self, forKey: .project)
        recording = try? c.decodeIfPresent(VideoDemoRecordingMetadata.self, forKey: .recording)
        sourceRecordings = (try? c.decode([String: VideoDemoRecordingMetadata].self, forKey: .sourceRecordings)) ?? [:]
        origins = (try? c.decode([String: Origin].self, forKey: .origins)) ?? [:]
        bookmarks = (try? c.decode([String: Data].self, forKey: .bookmarks)) ?? [:]
    }

    enum ReadError: Error, Equatable {
        case notAProject
        case damaged
    }

    /// The manifest of any version, brought up to this one.
    static func decode(_ data: Data) throws -> VideoProjectDocument {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReadError.damaged }
        guard let found = object["format"] as? String, found == format || found == legacyFormat else { throw ReadError.notAProject }
        object = migrate(object, from: object["version"] as? Int ?? 1)
        do {
            let upgraded = try JSONSerialization.data(withJSONObject: object)
            return try JSONDecoder().decode(VideoProjectDocument.self, from: upgraded)
        } catch {
            throw ReadError.damaged
        }
    }

    /// Steps an older manifest up to `currentVersion` (nothing yet: 1 is
    /// the first). A newer manifest is read as it is: fields this version
    /// doesn't know are skipped.
    static func migrate(_ object: [String: Any], from version: Int) -> [String: Any] {
        object
    }

    func encoded() throws -> Data {
        // Dates stay exact (seconds since 2001, fractions kept): an unchanged
        // file's date must compare equal on the next save.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Saved by a newer LF Studios: opens, but newer settings are dropped.
    var isFromNewerVersion: Bool { version > Self.currentVersion }

    /// The font families the project draws with.
    static func fontFamilies(of project: VideoDemoProject) -> [String] {
        var choices = [project.captionStyle.font, project.keystrokeStyle.font, project.cards.font]
        choices += project.overlayEffects.map(\.font)
        return Array(Set(choices.compactMap { $0?.family })).sorted()
    }
}

// MARK: - Media paths

/// Every media file a project points at, in the edit and in its
/// recordings' data, visited in one place so saving and opening rewrite
/// them all.
struct VideoProjectContents {
    var project: VideoDemoProject
    var recording: VideoDemoRecordingMetadata?
    var sourceRecordings: [String: VideoDemoRecordingMetadata]

    mutating func mapPaths(_ transform: (String) -> String) {
        func map(_ path: inout String) { if !path.isEmpty { path = transform(path) } }
        map(&project.sourcePath)
        for index in project.sources.indices {
            map(&project.sources[index].path)
            if project.sources[index].webcam != nil { map(&project.sources[index].webcam!.path) }
        }
        if project.importedCamera != nil { map(&project.importedCamera!.path) }
        if project.music != nil { map(&project.music!.path) }
        for index in project.overlayEffects.indices where project.overlayEffects[index].image != nil {
            map(&project.overlayEffects[index].image!.path)
        }
        if case .image(var path) = project.background {
            map(&path)
            project.background = .image(path)
        }
        if recording != nil {
            map(&recording!.videoURLPath)
            if recording!.webcam != nil { map(&recording!.webcam!.path) }
        }
        for key in sourceRecordings.keys {
            map(&sourceRecordings[key]!.videoURLPath)
            if sourceRecordings[key]!.webcam != nil { map(&sourceRecordings[key]!.webcam!.path) }
        }
    }

    var paths: [String] {
        var all: [String] = []
        var copy = self
        copy.mapPaths { all.append($0); return $0 }
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }
}

// MARK: - Saving and opening

enum VideoProjectPackage {
    static func manifestURL(_ package: URL) -> URL { package.appendingPathComponent(VideoProjectDocument.manifestName) }

    static func fileInfo(_ url: URL) -> (size: Int64, modified: Date)? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
        return (Int64(size), modified)
    }

    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// Writes `contents` as a project at `package`. Included media is
    /// copied in once: saving again copies only what's new or changed, and
    /// files nothing uses anymore are removed.
    @discardableResult
    static func save(_ contents: VideoProjectContents, to package: URL, mode: VideoProjectDocument.MediaMode, appVersion: String? = nil, fontFiles: (String) -> [URL] = { VideoFonts.addedFontFiles(forFamily: $0) }) throws -> VideoProjectDocument {
        let fm = FileManager.default
        let media = package.appendingPathComponent(VideoProjectDocument.mediaFolder, isDirectory: true)
        let fonts = package.appendingPathComponent(VideoProjectDocument.fontsFolder, isDirectory: true)
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        let previous = (try? Data(contentsOf: manifestURL(package))).flatMap { try? VideoProjectDocument.decode($0) }
        let packagePath = package.standardizedFileURL.path

        var origins: [String: VideoProjectDocument.Origin] = [:]
        var bookmarks: [String: Data] = [:]
        var references: [String: String] = [:]
        var keep: Set<String> = []

        for path in contents.paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if mode == .linked {
                if fm.fileExists(atPath: url.path), let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    bookmarks[path] = bookmark
                }
                continue
            }
            // Already inside this package: stays where it is.
            if url.path.hasPrefix(packagePath + "/") {
                let relative = String(url.path.dropFirst(packagePath.count + 1))
                references[path] = VideoProjectDocument.packagePrefix + relative
                keep.insert(url.lastPathComponent)
                if let origin = previous?.origins[url.lastPathComponent] { origins[url.lastPathComponent] = origin }
                continue
            }
            guard let info = fileInfo(url) else { continue } // missing: stays missing
            let origin = VideoProjectDocument.Origin(path: url.path, size: info.size, modified: info.modified)
            // Copied on an earlier save and unchanged since: reused.
            if let reused = previous?.origins.first(where: { $0.value == origin && fm.fileExists(atPath: media.appendingPathComponent($0.key).path) })?.key {
                references[path] = VideoProjectDocument.packagePrefix + "\(VideoProjectDocument.mediaFolder)/\(reused)"
                origins[reused] = origin
                keep.insert(reused)
                continue
            }
            var name = url.lastPathComponent
            var number = 2
            while keep.contains(name) || fm.fileExists(atPath: media.appendingPathComponent(name).path) {
                name = "\(url.deletingPathExtension().lastPathComponent) \(number)\(url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)")"
                number += 1
            }
            let destination = media.appendingPathComponent(name)
            try fm.copyItem(at: url, to: destination)
            // Its own identity: the copy's auto-saved edits never mix with
            // the original's (VideoDemoStores.swift).
            if videoExtensions.contains(destination.pathExtension.lowercased()) {
                _ = VideoFileIdentity.restamp(destination)
            }
            references[path] = VideoProjectDocument.packagePrefix + "\(VideoProjectDocument.mediaFolder)/\(name)"
            origins[name] = origin
            keep.insert(name)
        }

        var stored = contents
        if mode == .included {
            stored.mapPaths { references[$0] ?? $0 }
            for index in stored.project.sources.indices { stored.project.sources[index].bookmark = nil }
            stored.project.importedCamera?.bookmark = nil
        }

        // Fonts added to LF Studios that the project uses travel with it.
        var keepFonts: Set<String> = []
        if mode == .included {
            for family in VideoProjectDocument.fontFamilies(of: contents.project) {
                for file in fontFiles(family) {
                    try fm.createDirectory(at: fonts, withIntermediateDirectories: true)
                    let destination = fonts.appendingPathComponent(file.lastPathComponent)
                    if !fm.fileExists(atPath: destination.path) { try fm.copyItem(at: file, to: destination) }
                    keepFonts.insert(file.lastPathComponent)
                }
            }
        }

        let document = VideoProjectDocument(
            appVersion: appVersion,
            mediaMode: mode,
            project: stored.project,
            recording: stored.recording,
            sourceRecordings: stored.sourceRecordings,
            origins: origins,
            bookmarks: bookmarks
        )
        try document.encoded().write(to: manifestURL(package), options: .atomic)

        // What nothing points at anymore goes.
        for file in (try? fm.contentsOfDirectory(at: media, includingPropertiesForKeys: nil)) ?? [] where !keep.contains(file.lastPathComponent) {
            try? fm.removeItem(at: file)
        }
        for file in (try? fm.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil)) ?? [] where !keepFonts.contains(file.lastPathComponent) {
            try? fm.removeItem(at: file)
        }
        return document
    }

    struct Opened {
        var document: VideoProjectDocument
        /// With every path pointing at a real place on this Mac.
        var contents: VideoProjectContents
        var package: URL
        /// The fonts that came inside it.
        var fontFiles: [URL]
    }

    /// Reads a project: package paths made absolute, moved linked files
    /// found by their bookmarks.
    static func open(_ package: URL) throws -> Opened {
        guard let data = try? Data(contentsOf: manifestURL(package)) else { throw VideoProjectDocument.ReadError.notAProject }
        let document = try VideoProjectDocument.decode(data)
        var contents = VideoProjectContents(project: document.project, recording: document.recording, sourceRecordings: document.sourceRecordings)
        let root = package.standardizedFileURL
        contents.mapPaths { path in
            if path.hasPrefix(VideoProjectDocument.packagePrefix) {
                return root.appendingPathComponent(String(path.dropFirst(VideoProjectDocument.packagePrefix.count))).path
            }
            if !FileManager.default.fileExists(atPath: path), let bookmark = document.bookmarks[path] {
                var stale = false
                if let found = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
                   FileManager.default.fileExists(atPath: found.path) {
                    return found.path
                }
            }
            return path
        }
        let fonts = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(VideoProjectDocument.fontsFolder, isDirectory: true), includingPropertiesForKeys: nil)) ?? []
        return Opened(document: document, contents: contents, package: root, fontFiles: fonts.filter { VideoFonts.fileExtensions.contains($0.pathExtension.lowercased()) })
    }
}
