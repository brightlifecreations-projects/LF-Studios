import Foundation

/// An LF Studios project file: `Name.lfs`, a folder macOS shows as one
/// file. It holds `project.json` (the edit and every recording's pointer,
/// click, and key data) and, with "Include media", the media itself:
///
///     Name.lfs/
///         project.json
///         Media/      the recordings, camera videos, music, pictures
///         Fonts/      fonts added to LF Studios that the project uses
///
/// "Link to media" keeps only paths (and bookmarks to find moved files):
/// small, for this Mac. Paths inside the package are written relative
/// (`@package/Media/…`), so the package can move anywhere.
///
/// A folder project (`.folder`, version 2) sits in a folder with its media
/// around it — a recording's own folder, or a Creative Handoff — and
/// points at it relative to that folder (`@folder/01 Screen/…`), so the
/// whole folder can be moved or renamed:
///
///     Name/
///         Name.lfs/project.json
///         01 Screen/  02 Camera/  03 Audio/  04 Graphics/  05 Captions/  07 Data/  Fonts/
struct VideoProjectDocument: Codable {
    static let format = "lfstudios-project"
    /// Projects saved while the app was called ShotStyle.
    static let legacyFormat = "shotstyle-project"
    static let legacyFileExtension = "shotstyle"
    static let legacyTypeIdentifier = "com.shotstyle.project"
    /// Projects saved by LF Studios 1.1–1.8. Older projects keep their
    /// name: Save (⌘S) writes them where they are, only Save Project As…
    /// makes a `.lfs`.
    static let previousFileExtension = "lfstudios"
    static let previousTypeIdentifier = "com.lfstudios.project"
    /// Projects saved by LF Studios 1.9–1.11.
    static let lfspFileExtension = "lfsp"
    static let lfspTypeIdentifier = "com.lfstudios.lfsp"
    /// Every name opens.
    static let openableExtensions: Set<String> = [fileExtension, lfspFileExtension, previousFileExtension, legacyFileExtension]
    /// In a manifest: the oldest project version that can open it (a newer
    /// one than this means "needs a newer LF Studios"). Projects that every
    /// version since 1.13.0 can read leave it out.
    static let requiresKey = "requires"
    /// Bump when the layout changes, and teach `migrate` the step up, so
    /// every older project still opens.
    /// 2: folder projects (`@folder/` paths). Projects without them are
    /// still written as 1, so older versions of LF Studios open them as before.
    static let currentVersion = 2
    /// LF Studios Project. New projects, Creative Handoffs and recording
    /// folders write it (since 1.12.0; `.lfsp` from 1.9.0).
    static let fileExtension = "lfs"
    static let typeIdentifier = "com.lfstudios.lfs"
    /// The first version that opens a `.lfs` (what README.txt says).
    static let firstVersionOpeningFileExtension = "1.12.0"
    static let manifestName = "project.json"
    static let mediaFolder = "Media"
    static let fontsFolder = "Fonts"
    /// The prefix of paths inside the package.
    static let packagePrefix = "@package/"
    /// The prefix of paths in the folder around a folder project.
    static let folderPrefix = "@folder/"

    /// Save Project As…: the name the panel suggests, the project's (or the
    /// video's) as a `.lfs`, also for an older `.lfsp` or `.lfstudios` project.
    static func saveAsName(current: URL?, source: URL) -> String {
        "\((current ?? source).deletingPathExtension().lastPathComponent).\(fileExtension)"
    }

    /// Save Project As…: the chosen file, ending in `.lfs`.
    static func saveAsURL(_ chosen: URL) -> URL {
        chosen.pathExtension.lowercased() == fileExtension ? chosen : chosen.appendingPathExtension(fileExtension)
    }

    enum MediaMode: String, Codable {
        /// Copies inside the package: opens on any Mac.
        case included
        /// Paths to the originals: small, this Mac only.
        case linked
        /// Paths into the folder around the project (its media is there).
        case folder
    }

    /// What made the folder around a folder project.
    struct FolderInfo: Codable, Equatable {
        enum Kind: String, Codable {
            /// A recording's own folder: LF Studios keeps its project file
            /// and captions up to date as the edit changes.
            case recording
            /// A Creative Handoff.
            case handoff
            /// A folder someone opened: written to only on Save.
            case opened
        }

        var kind: Kind
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
    /// Folder projects: what made the folder.
    var folder: FolderInfo?

    private enum CodingKeys: String, CodingKey {
        case format, version, savedAt, appVersion, mediaMode, project, recording, sourceRecordings, origins, bookmarks, folder
    }

    init(format: String = Self.format, version: Int? = nil, savedAt: Date = Date(), appVersion: String? = nil, mediaMode: MediaMode, project: VideoDemoProject, recording: VideoDemoRecordingMetadata?, sourceRecordings: [String: VideoDemoRecordingMetadata] = [:], origins: [String: Origin] = [:], bookmarks: [String: Data] = [:], folder: FolderInfo? = nil) {
        self.format = format
        self.version = version ?? (mediaMode == .folder ? 2 : 1)
        self.folder = folder
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
        folder = try? c.decodeIfPresent(FolderInfo.self, forKey: .folder)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(version, forKey: .version)
        try c.encode(savedAt, forKey: .savedAt)
        try c.encodeIfPresent(appVersion, forKey: .appVersion)
        try c.encode(mediaMode, forKey: .mediaMode)
        try c.encode(project, forKey: .project)
        try c.encodeIfPresent(recording, forKey: .recording)
        try c.encode(sourceRecordings, forKey: .sourceRecordings)
        try c.encode(origins, forKey: .origins)
        try c.encode(bookmarks, forKey: .bookmarks)
        try c.encodeIfPresent(folder, forKey: .folder)
    }

    enum ReadError: Error, Equatable {
        case notAProject
        case damaged
        /// Saved by a newer LF Studios in a form this one can't read: it
        /// says so, with Check for Updates (1.13.0).
        case needsNewerVersion
    }

    /// The manifest of any version, brought up to this one.
    static func decode(_ data: Data) throws -> VideoProjectDocument {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReadError.damaged }
        guard let found = object["format"] as? String else { throw ReadError.notAProject }
        guard found == format || found == legacyFormat else {
            // A later kind of LF Studios project ("lfstudios-project-3"…).
            throw found.hasPrefix(format) ? ReadError.needsNewerVersion : ReadError.notAProject
        }
        // A project that says this version can't show it as it is.
        if let required = object[Self.requiresKey] as? Int, required > currentVersion { throw ReadError.needsNewerVersion }
        object = migrate(object, from: object["version"] as? Int ?? 1)
        do {
            let upgraded = try JSONSerialization.data(withJSONObject: object)
            return try JSONDecoder().decode(VideoProjectDocument.self, from: upgraded)
        } catch {
            throw ReadError.damaged
        }
    }

    /// Steps an older manifest up to `currentVersion` (1 → 2 needs nothing:
    /// 2 only adds folder projects). A newer manifest is read as it is:
    /// fields this version doesn't know are skipped.
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

    /// What a file is, for where a folder project puts its copy.
    enum MediaKind {
        case screen, camera, audio, graphic, data

        /// Its folder in a recording's folder or a handoff.
        var folder: String {
            switch self {
            case .screen: return VideoRecordingFolder.Layout.screen
            case .camera: return VideoRecordingFolder.Layout.camera
            case .audio: return VideoRecordingFolder.Layout.audio
            case .graphic: return VideoRecordingFolder.Layout.graphics
            case .data: return VideoRecordingFolder.Layout.data
            }
        }
    }

    mutating func mapPaths(_ transform: (String) -> String) {
        mapPaths { path, _ in transform(path) }
    }

    mutating func mapPaths(_ transform: (String, MediaKind) -> String) {
        func map(_ path: inout String, _ kind: MediaKind) { if !path.isEmpty { path = transform(path, kind) } }
        map(&project.sourcePath, .screen)
        for index in project.sources.indices {
            map(&project.sources[index].path, .screen)
            if project.sources[index].webcam != nil { map(&project.sources[index].webcam!.path, .camera) }
        }
        if project.importedCamera != nil { map(&project.importedCamera!.path, .camera) }
        if project.music != nil { map(&project.music!.path, .audio) }
        for index in project.audioTracks.indices { map(&project.audioTracks[index].path, .audio) }
        if project.cursor.customImage != nil { map(&project.cursor.customImage!.path, .graphic) }
        for index in project.overlayEffects.indices where project.overlayEffects[index].image != nil {
            map(&project.overlayEffects[index].image!.path, .graphic)
        }
        if case .image(var path) = project.background {
            map(&path, .graphic)
            project.background = .image(path)
        }
        // A macOS wallpaper: another Mac may not have that one.
        if case .systemWallpaper(var path) = project.background {
            map(&path, .graphic)
            project.background = .systemWallpaper(path)
        }
        // This Mac's caches the edit uses (VideoProjectCaches.swift).
        for index in project.carriedVoices.indices { map(&project.carriedVoices[index].path, .audio) }
        if project.faceTracking?.analysisPath != nil { map(&project.faceTracking!.analysisPath!, .data) }
        // The Library's imported media (VideoMediaBin.swift).
        if project.mediaBin != nil { project.mediaBin!.mapPaths { path, kind in transform(path, kind) } }
        if recording != nil {
            map(&recording!.videoURLPath, .screen)
            if recording!.webcam != nil { map(&recording!.webcam!.path, .camera) }
        }
        for key in sourceRecordings.keys {
            map(&sourceRecordings[key]!.videoURLPath, .screen)
            if sourceRecordings[key]!.webcam != nil { map(&sourceRecordings[key]!.webcam!.path, .camera) }
        }
    }

    /// Every path with what it is (the first kind seen for a path).
    var kindedPaths: [(path: String, kind: MediaKind)] {
        var all: [(String, MediaKind)] = []
        var copy = self
        copy.mapPaths { path, kind in all.append((path, kind)); return path }
        var seen = Set<String>()
        return all.filter { seen.insert($0.0).inserted }
    }

    /// Readable names for copies of cached files (a cache's own name is a
    /// long key).
    var preferredNames: [String: String] {
        var names: [String: String] = [:]
        for voice in project.carriedVoices {
            let whose: String
            if voice.owner == VideoCarriedVoice.primary {
                whose = project.sourceURL.deletingPathExtension().lastPathComponent
            } else if let source = project.sources.first(where: { $0.id.uuidString == voice.owner }) {
                whose = URL(fileURLWithPath: source.name).deletingPathExtension().lastPathComponent
            } else {
                whose = project.audioTracks.first { VideoCarriedVoice.audioPrefix + $0.id.uuidString == voice.owner }?.name ?? "Voice"
            }
            names[voice.path] = "\(whose) - voice, cleaned up.m4a" // l10n-ignore: a file name, like the folders'
        }
        if let path = project.faceTracking?.analysisPath { names[path] = "Face tracking.json" } // l10n-ignore
        return names
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
    /// `copiesOutsideFiles` (folder projects): copy what's outside the folder
    /// into it. Off (a handoff, which decided what it holds): those stay
    /// linked where they are.
    static func save(_ contents: VideoProjectContents, to package: URL, mode: VideoProjectDocument.MediaMode, appVersion: String? = nil, folder: VideoProjectDocument.FolderInfo? = nil, copiesOutsideFiles: Bool = true, fontFiles: (String) -> [URL] = { VideoFonts.addedFontFiles(forFamily: $0) }) throws -> VideoProjectDocument {
        if mode == .folder {
            return try saveFolderProject(contents, to: package, appVersion: appVersion, folder: folder ?? VideoProjectDocument.FolderInfo(kind: .opened), copiesOutsideFiles: copiesOutsideFiles, fontFiles: fontFiles)
        }
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

    /// A folder project: its media stays where it is in the folder around
    /// the package and is pointed at relative to it. Anything outside the
    /// folder (music LF Studios keeps, a picture from elsewhere) is copied
    /// into the folder's matching subfolder first, so the folder holds the
    /// whole edit.
    private static func saveFolderProject(_ contents: VideoProjectContents, to package: URL, appVersion: String?, folder: VideoProjectDocument.FolderInfo, copiesOutsideFiles: Bool, fontFiles: (String) -> [URL]) throws -> VideoProjectDocument {
        let fm = FileManager.default
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        let root = package.standardizedFileURL.deletingLastPathComponent()
        let rootPath = root.path
        var references: [String: String] = [:]
        var bookmarks: [String: Data] = [:]
        let names = contents.preferredNames
        for (path, kind) in contents.kindedPaths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if url.path.hasPrefix(rootPath + "/") {
                references[path] = VideoProjectDocument.folderPrefix + String(url.path.dropFirst(rootPath.count + 1))
                continue
            }
            guard fm.fileExists(atPath: url.path) else { continue } // missing: stays missing
            guard copiesOutsideFiles else {
                if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) { bookmarks[path] = bookmark }
                continue
            }
            let subfolder = root.appendingPathComponent(kind.folder, isDirectory: true)
            try fm.createDirectory(at: subfolder, withIntermediateDirectories: true)
            // Copied on an earlier save (the editor keeps its own copy and
            // writes the folder's project again after edits): reused, never
            // copied twice.
            let destination: URL
            let name = names[path] ?? url.lastPathComponent
            if let copied = existingCopy(of: url, named: name, in: subfolder) {
                destination = copied
            } else {
                destination = VideoRecordingFolder.uniqueFile(named: name, in: subfolder)
                try fm.copyItem(at: url, to: destination)
                if videoExtensions.contains(destination.pathExtension.lowercased()) {
                    _ = VideoFileIdentity.restamp(destination)
                }
            }
            references[path] = VideoProjectDocument.folderPrefix + "\(kind.folder)/\(destination.lastPathComponent)"
            if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                bookmarks[path] = bookmark
            }
        }
        var stored = contents
        stored.mapPaths { references[$0] ?? $0 }
        for index in stored.project.sources.indices { stored.project.sources[index].bookmark = nil }
        stored.project.importedCamera?.bookmark = nil
        if stored.recording != nil { stored.recording!.bookmark = nil }

        // Fonts added to LF Studios that the project uses go in Fonts/.
        for family in VideoProjectDocument.fontFamilies(of: contents.project) {
            for file in fontFiles(family) {
                let fonts = root.appendingPathComponent(VideoProjectDocument.fontsFolder, isDirectory: true)
                try fm.createDirectory(at: fonts, withIntermediateDirectories: true)
                let destination = fonts.appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath: destination.path) { try fm.copyItem(at: file, to: destination) }
            }
        }

        let document = VideoProjectDocument(
            appVersion: appVersion,
            mediaMode: .folder,
            project: stored.project,
            recording: stored.recording,
            sourceRecordings: stored.sourceRecordings,
            bookmarks: bookmarks,
            folder: folder
        )
        try document.encoded().write(to: manifestURL(package), options: .atomic)
        return document
    }

    /// A file in `folder` with `original`'s name (or "name 2"…) and the same
    /// size and contents.
    private static func existingCopy(of original: URL, named name: String, in folder: URL) -> URL? {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        guard let size = fileInfo(original)?.size else { return nil }
        let candidates = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []).filter { candidate in
            let name = candidate.deletingPathExtension().lastPathComponent
            return candidate.pathExtension.lowercased() == ext && (name == base || name.hasPrefix(base + " ")) && fileInfo(candidate)?.size == size
        }
        return candidates.first { fm.contentsEqual(atPath: $0.path, andPath: original.path) }
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
        let folder = root.deletingLastPathComponent()
        contents.mapPaths { path in
            if path.hasPrefix(VideoProjectDocument.packagePrefix) {
                return root.appendingPathComponent(String(path.dropFirst(VideoProjectDocument.packagePrefix.count))).path
            }
            if path.hasPrefix(VideoProjectDocument.folderPrefix) {
                return folder.appendingPathComponent(String(path.dropFirst(VideoProjectDocument.folderPrefix.count))).path
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
        let fontsRoot = document.mediaMode == .folder ? folder : root
        let fonts = (try? FileManager.default.contentsOfDirectory(at: fontsRoot.appendingPathComponent(VideoProjectDocument.fontsFolder, isDirectory: true), includingPropertiesForKeys: nil)) ?? []
        return Opened(document: document, contents: contents, package: root, fontFiles: fonts.filter { VideoFonts.fileExtensions.contains($0.pathExtension.lowercased()) })
    }
}
