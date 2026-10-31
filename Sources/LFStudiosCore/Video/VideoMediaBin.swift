import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The media bin (1.13.0)

/// What a file in the Library is.
enum VideoMediaKind: String, Codable, CaseIterable {
    case video, image, audio

    /// What `url` is, by its extension (nil: not something the video can use).
    static func of(_ url: URL) -> VideoMediaKind? {
        let ext = url.pathExtension.lowercased()
        if VideoExternalAudioTrack.fileExtensions.contains(ext) { return .audio }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        return nil
    }

    var contentTypes: [UTType] {
        switch self {
        case .video: return [.movie]
        case .image: return [.image]
        case .audio: return VideoExternalAudioTrack.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        }
    }

    /// Its folder when a project includes its media.
    var projectKind: VideoProjectContents.MediaKind {
        switch self {
        case .video: return .screen
        case .image: return .graphic
        case .audio: return .audio
        }
    }
}

/// A file imported into the Library. It stays where it is (linked) until
/// the project is saved with Include media.
struct VideoMediaItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var path: String
    var name: String
    var kind: VideoMediaKind
    var added: Date
    /// LF Studios' copies of it in the video (a picture or a sound file is
    /// copied in when it's placed), so the Library knows it's been added.
    var placed: [String] = []
}

struct VideoMediaFolder: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
}

/// The project's Library: imported files, folders, and the names given there.
struct VideoMediaBin: Codable, Equatable {
    var imported: [VideoMediaItem] = []
    var folders: [VideoMediaFolder] = []
    /// Names given in the Library, by entry key (the files keep theirs).
    var names: [String: String] = [:]
    /// The folder each entry is in, by entry key.
    var folderOf: [String: UUID] = [:]

    var isEmpty: Bool { imported.isEmpty && folders.isEmpty && names.isEmpty && folderOf.isEmpty }

    /// Keys that hold a path follow it when the project moves its media.
    static let pathKeyPrefix = "path:"

    mutating func mapPaths(_ transform: (String, VideoProjectContents.MediaKind) -> String) {
        for index in imported.indices {
            let kind = imported[index].kind.projectKind
            imported[index].path = transform(imported[index].path, kind)
            imported[index].placed = imported[index].placed.map { transform($0, kind) }
        }
        func moved(_ key: String) -> String {
            guard key.hasPrefix(Self.pathKeyPrefix) else { return key }
            let path = String(key.dropFirst(Self.pathKeyPrefix.count))
            let kind: VideoProjectContents.MediaKind = VideoMediaKind.of(URL(fileURLWithPath: path)).map(\.projectKind) ?? .graphic
            return Self.pathKeyPrefix + transform(path, kind)
        }
        names = Dictionary(names.map { (moved($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        folderOf = Dictionary(folderOf.map { (moved($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
    }
}

/// One tile in the Library: an imported file, or something the video
/// already uses (its recordings, camera, music, sound files, pictures).
struct VideoMediaEntry: Identifiable, Equatable {
    enum Origin: Equatable {
        case recording
        case addedRecording(UUID)
        case camera
        case music
        case sound(UUID)
        case picture
        /// On a track above the main track (1.14.0).
        case layer
        case imported(UUID)
    }

    var key: String
    var path: String
    var name: String
    /// Its name before any Rename… (what the file was called).
    var ownName: String
    var kind: VideoMediaKind
    var origin: Origin
    /// Known without opening the file (nil: read when shown).
    var duration: Double?
    var added: Date?
    /// In the video: on the timeline, under it, or on the picture.
    var isInVideo: Bool
    var folder: UUID?
    var isMissing: Bool

    var id: String { key }
    var url: URL { URL(fileURLWithPath: path) }
    var fileName: String { url.lastPathComponent }

    var isImported: Bool { if case .imported = origin { return true } else { return false } }
    /// Delete from Project works on it (the video's own recording and
    /// camera stay).
    var canDelete: Bool { origin != .recording && origin != .camera }
    /// Replace… and Locate… work on it.
    var canReplace: Bool {
        switch origin {
        case .imported, .picture, .sound, .music, .layer: return true
        case .recording, .addedRecording, .camera: return false
        }
    }
}

extension VideoDemoProject {
    /// Every path the video itself uses (not the Library's own imports).
    var pathsInVideo: Set<String> {
        var copy = self
        copy.mediaBin = nil
        return Set(VideoProjectContents(project: copy, recording: nil, sourceRecordings: [:]).paths)
    }

    /// The Library's entries: the video's own media first, then imports,
    /// with the names and folders given in the Library. `camera` is the
    /// recording's own camera footage.
    func mediaEntries(camera: VideoWebcamRecording? = nil) -> [VideoMediaEntry] {
        let bin = mediaBin ?? VideoMediaBin()
        let fileManager = FileManager.default
        // An imported file that was placed shows once, as the import.
        var importedPaths = Set<String>()
        for item in bin.imported {
            importedPaths.insert(item.path)
            importedPaths.formUnion(item.placed)
        }
        var entries: [VideoMediaEntry] = []
        var seen = Set<String>()
        func add(_ key: String, _ path: String, _ name: String, _ kind: VideoMediaKind, _ origin: VideoMediaEntry.Origin, duration: Double? = nil) {
            guard !path.isEmpty, !importedPaths.contains(path), seen.insert(path).inserted else { return }
            entries.append(VideoMediaEntry(
                key: key, path: path, name: bin.names[key] ?? name, ownName: name, kind: kind, origin: origin,
                duration: duration, added: nil, isInVideo: true, folder: bin.folderOf[key],
                isMissing: !fileManager.fileExists(atPath: path)
            ))
        }
        let recordingDuration = sources.first(where: \.isPrimary)?.duration
        add("recording", sourcePath, URL(fileURLWithPath: sourcePath).lastPathComponent, .video, .recording, duration: recordingDuration)
        if let camera { add(Self.pathKey(camera.path), camera.path, L("Camera"), .video, .camera) }
        for source in sources where !source.isPrimary {
            add("source:\(source.id.uuidString)", source.path, source.name, .video, .addedRecording(source.id), duration: source.duration)
            if let webcam = source.webcam { add(Self.pathKey(webcam.path), webcam.path, L("Camera — \(source.name)"), .video, .camera) }
        }
        if let importedCamera { add(Self.pathKey(importedCamera.path), importedCamera.path, URL(fileURLWithPath: importedCamera.path).lastPathComponent, .video, .camera, duration: importedCamera.duration) }
        if let music { add("music", music.path, music.name, .audio, .music, duration: music.duration) }
        for track in audioTracks { add("sound:\(track.id.uuidString)", track.path, track.name, .audio, .sound(track.id), duration: track.duration) }
        for effect in overlayEffects {
            guard let image = effect.image else { continue }
            add(Self.pathKey(image.path), image.path, image.name, .image, .picture)
        }
        // On the tracks above the main track.
        for (_, item) in layerItems {
            add(Self.pathKey(item.path), item.path, item.name, item.kind, .layer, duration: item.isVideo ? item.fileDuration : nil)
        }

        let inVideo = pathsInVideo
        for item in bin.imported {
            let key = Self.importedKey(item.id)
            entries.append(VideoMediaEntry(
                key: key, path: item.path, name: bin.names[key] ?? item.name, ownName: item.name, kind: item.kind, origin: .imported(item.id),
                duration: nil, added: item.added,
                isInVideo: inVideo.contains(item.path) || item.placed.contains(where: inVideo.contains),
                folder: bin.folderOf[key], isMissing: !fileManager.fileExists(atPath: item.path)
            ))
        }
        return entries
    }

    static func pathKey(_ path: String) -> String { VideoMediaBin.pathKeyPrefix + path }
    static func importedKey(_ id: UUID) -> String { "imported:\(id.uuidString)" }
}

// MARK: - In the editor

extension VideoEditorModel {
    var mediaEntries: [VideoMediaEntry] { project.mediaEntries(camera: webcamRecording) }

    /// File ▸ Import Media… (⌘I) and the Library's Import button.
    func chooseMediaToImport(into folder: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = VideoMediaKind.allCases.flatMap(\.contentTypes)
        panel.message = L("Choose videos, pictures, or sound files to add to the Library")
        panel.prompt = L("Import")
        guard panel.runModal() == .OK else { return }
        importMedia(panel.urls, into: folder)
    }

    /// Adds files to the Library without putting them in the video. A
    /// folder brings the files directly in it, in a Library folder of its
    /// name. Files already there aren't added twice.
    @discardableResult
    func importMedia(_ urls: [URL], into folder: UUID? = nil) -> [VideoMediaItem] {
        var bin = project.mediaBin ?? VideoMediaBin()
        let known = Set(project.mediaEntries(camera: webcamRecording).map(\.path))
        var items: [VideoMediaItem] = []
        var skipped = 0
        func take(_ url: URL, folder: UUID?) {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard let kind = VideoMediaKind.of(url) else { skipped += 1; return }
            if let existing = bin.imported.first(where: { $0.path == path }) {
                items.append(existing)
                return
            }
            guard !known.contains(path) else { return }
            let item = VideoMediaItem(path: path, name: url.lastPathComponent, kind: kind, added: Date())
            bin.imported.append(item)
            if let folder { bin.folderOf[VideoDemoProject.importedKey(item.id)] = folder }
            items.append(item)
        }
        for url in urls {
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
                let files = ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                    .filter { VideoMediaKind.of($0) != nil }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                guard !files.isEmpty else { skipped += 1; continue }
                let newFolder = VideoMediaFolder(name: url.lastPathComponent)
                bin.folders.append(newFolder)
                for file in files { take(file, folder: newFolder.id) }
            } else {
                take(url, folder: folder)
            }
        }
        if bin != (project.mediaBin ?? VideoMediaBin()) {
            mutate(label: "Import Media") { $0.mediaBin = bin }
        }
        if skipped > 0 {
            showNotice(L("Some files weren't added: LF Studios takes videos, pictures, and sound files"), symbol: "exclamationmark.triangle.fill", duration: 4)
        }
        return items
    }

    /// Where a dropped file goes (1.14.0): the main track, a track above
    /// it, or wherever it fits (videos and pictures on a track above the
    /// main track, sound on a track of its own).
    enum DropTarget: Equatable {
        case main
        case layer(LayerPlace)
        case anywhere
    }

    /// Dropped on the timeline or the player, or dragged there from the
    /// Library: into the Library and into the video, at `time` (nil: the
    /// playhead), on the track it was dropped on. Several files follow one
    /// another.
    func placeMedia(_ urls: [URL], at time: Double?, target: DropTarget = .anywhere) async {
        var at = time ?? clock.time
        for url in urls {
            guard let kind = VideoMediaKind.of(url) else { continue }
            let item = importMedia([url]).first
            switch (kind, target) {
            case (.audio, _):
                let ids = await addAudio([url], at: at)
                for id in ids { if let track = audioTrack(id) { notePlaced(item, track.path); at = track.pieces.last?.end ?? at } }
            case (_, .main):
                if let end = await insertOnMainTrack(url, at: at) { at = end }
            case (_, .layer(let place)):
                if let id = await addLayerItem(from: url, at: at, place: place), let added = project.layerItem(id) { at = added.end }
            case (_, .anywhere):
                if let id = await addLayerItem(from: url, at: at, place: .automatic), let added = project.layerItem(id) { at = added.end }
            }
        }
    }

    /// A video (or a picture, as a still video) on the main track at
    /// `time`: a clip there is split, and the rest moves along. One ⌘Z
    /// takes it back. Returns where it ends.
    @discardableResult
    func insertOnMainTrack(_ url: URL, at time: Double) async -> Double? {
        if refuseLocked(.clips) { return nil }
        var video = url
        let isPicture = VideoMediaKind.of(url) == .image
        if isPicture {
            do {
                video = try await VideoGeneratedMedia.stillVideo(fromPicture: url, size: CGSize(width: project.sourceWidth, height: project.sourceHeight), seconds: VideoLayerItem.pictureLength)
            } catch {
                showNotice(L("Couldn't open that image"), symbol: "exclamationmark.triangle.fill")
                return nil
            }
        }
        let before = Set(project.sources.map(\.id))
        guard await appendVideo(video) else { return nil }
        // (The first one added also makes the project's own recording a source.)
        guard let source = project.sources.last(where: { !before.contains($0.id) && !$0.isPrimary }) else { return nil }
        let total = sourceDuration
        mutate(label: "Add to Track") { project in
            if isPicture, let index = project.sources.firstIndex(where: { $0.id == source.id }) { project.sources[index].name = url.lastPathComponent }
            project.moveSourceClips(source, toTimeline: time, totalDuration: total)
        }
        joinLastUndoSteps(label: "Add to Track")
        let placed = segments.first { $0.clip.sourceStart >= source.offset - 0.001 && $0.clip.sourceEnd <= source.end + 0.001 }
        if let placed { seek(to: placed.timelineStart) }
        return placed?.timelineEnd
    }

    /// Library ▸ Add to Timeline.
    func placeEntry(_ entry: VideoMediaEntry, at time: Double? = nil) async {
        await placeMedia([entry.url], at: time)
    }

    private func notePlaced(_ item: VideoMediaItem?, _ path: String) {
        guard let item, path != item.path else { return }
        mutate(label: "Import Media") { project in
            guard let index = project.mediaBin?.imported.firstIndex(where: { $0.id == item.id }) else { return }
            if !project.mediaBin!.imported[index].placed.contains(path) { project.mediaBin!.imported[index].placed.append(path) }
        }
    }

    // MARK: Names and folders

    func renameMedia(_ entry: VideoMediaEntry, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updateBin(label: "Rename Media") { bin in
            bin.names[entry.key] = trimmed.isEmpty || trimmed == entry.ownName ? nil : trimmed
        }
    }

    @discardableResult
    func newMediaFolder(named name: String) -> UUID {
        let folder = VideoMediaFolder(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("New Folder") : name)
        updateBin(label: "New Folder") { $0.folders.append(folder) }
        return folder.id
    }

    func renameMediaFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateBin(label: "Rename Folder") { bin in
            guard let index = bin.folders.firstIndex(where: { $0.id == id }) else { return }
            bin.folders[index].name = trimmed
        }
    }

    /// Its media goes back to the top of the Library.
    func deleteMediaFolder(_ id: UUID) {
        updateBin(label: "Delete Folder") { bin in
            bin.folders.removeAll { $0.id == id }
            bin.folderOf = bin.folderOf.filter { $0.value != id }
        }
    }

    func moveMedia(_ entry: VideoMediaEntry, to folder: UUID?) {
        updateBin(label: "Move Media") { $0.folderOf[entry.key] = folder }
    }

    private func updateBin(label: String, _ change: (inout VideoMediaBin) -> Void) {
        mutate(label: label) { project in
            var bin = project.mediaBin ?? VideoMediaBin()
            change(&bin)
            project.mediaBin = bin.isEmpty ? nil : bin
        }
    }

    // MARK: Delete, replace, locate

    /// Library ▸ Delete from Project: out of the Library and out of the
    /// video (one ⌘Z brings it back).
    func deleteMedia(_ entry: VideoMediaEntry) {
        guard entry.canDelete else { return }
        if case .addedRecording(let id) = entry.origin {
            removeSource(id)
            updateBin(label: "Delete from Project") { $0.names[entry.key] = nil; $0.folderOf[entry.key] = nil }
            return
        }
        var removesRecording: UUID?
        mutate(label: "Delete from Project") { project in
            var paths: Set<String> = [entry.path]
            if case .imported(let id) = entry.origin, let item = project.mediaBin?.imported.first(where: { $0.id == id }) {
                paths.formUnion(item.placed)
                project.mediaBin?.imported.removeAll { $0.id == id }
                removesRecording = project.sources.first { !$0.isPrimary && $0.path == item.path }?.id
            }
            project.overlayEffects.removeAll { effect in effect.image.map { paths.contains($0.path) } ?? false }
            project.audioTracks.removeAll { paths.contains($0.path) }
            for t in project.layerTracks.indices { project.layerTracks[t].items.removeAll { paths.contains($0.path) } }
            project.dropEmptyLayerTracks()
            if let music = project.music, paths.contains(music.path) { project.music = nil }
            project.mediaBin?.names[entry.key] = nil
            project.mediaBin?.folderOf[entry.key] = nil
            if project.mediaBin?.isEmpty == true { project.mediaBin = nil }
        }
        if case .sound = entry.origin { selectedAudioPiece = nil }
        validateSelection()
        // A video placed from the Library leaves the timeline too.
        if let removesRecording {
            var removed = false
            mutate(coalesce: lastCoalesceKeyForBin, label: "Delete from Project") { removed = $0.removeSource(id: removesRecording) }
            if removed { Task { await reloadSources() } }
        }
        showNotice(L("Deleted from the project — ⌘Z to undo"), symbol: "trash")
    }

    private var lastCoalesceKeyForBin: String { "media-delete" }

    /// Library ▸ Replace… (any time) or Locate… (the file is gone).
    func chooseReplacement(for entry: VideoMediaEntry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = entry.kind.contentTypes
        panel.message = entry.isMissing ? L("Find “\(entry.ownName)”") : L("Choose a file to use in place of “\(entry.name)”")
        if entry.isMissing { panel.directoryURL = entry.url.deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await replaceMedia(entry, with: url) }
    }

    /// Puts `url` wherever `entry` was: in the Library, and on every
    /// picture or sound track that used it.
    @discardableResult
    func replaceMedia(_ entry: VideoMediaEntry, with url: URL) async -> Bool {
        guard entry.canReplace, VideoMediaKind.of(url) == entry.kind else {
            showNotice(L("Choose a file of the same kind"), symbol: "exclamationmark.triangle.fill")
            return false
        }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        var uses: Set<String> = [entry.path]
        if case .imported(let id) = entry.origin, let item = project.mediaBin?.imported.first(where: { $0.id == id }) {
            uses.formUnion(item.placed)
        }
        // What the video's own copies become.
        var picture: VideoOverlayImage?
        var sound: (path: String, duration: Double)?
        // On the tracks above the main track the file is used where it is.
        var layerMedia: (aspect: Double, duration: Double)?
        if project.layerItems.contains(where: { uses.contains($0.item.path) }) {
            switch entry.kind {
            case .image:
                guard let size = VideoImageOverlayRenderer.pixelSize(of: url) else {
                    showNotice(L("Couldn't open that image"), symbol: "exclamationmark.triangle.fill")
                    return false
                }
                layerMedia = (Double(size.width / max(size.height, 1)), 0)
            case .video:
                guard let tracks = try? await VideoSourceTracks.load(url: url) else {
                    showNotice(L("Couldn't open that video"), symbol: "exclamationmark.triangle.fill")
                    return false
                }
                layerMedia = (Double(tracks.size.width / max(tracks.size.height, 1)), tracks.duration)
            case .audio:
                break
            }
        }
        let placedInVideo = project.overlayEffects.contains { $0.image.map { uses.contains($0.path) } ?? false }
            || project.audioTracks.contains { uses.contains($0.path) }
            || project.music.map { uses.contains($0.path) } == true
        if placedInVideo || !entry.isImported {
            switch entry.kind {
            case .image:
                guard let size = VideoImageOverlayRenderer.pixelSize(of: url), let stored = try? VideoAssetStore.importFile(url) else {
                    showNotice(L("Couldn't open that image"), symbol: "exclamationmark.triangle.fill")
                    return false
                }
                picture = VideoOverlayImage(path: stored.path, name: url.lastPathComponent, aspect: Double(size.width / max(size.height, 1)))
            case .audio:
                do {
                    let prepared = try await VideoExternalAudioImport.prepare(url)
                    sound = (prepared.url.path, prepared.duration)
                } catch {
                    showNotice(error.localizedDescription, symbol: "exclamationmark.triangle.fill", duration: 5)
                    return false
                }
            case .video:
                break
            }
        }
        mutate(label: "Replace Media") { project in
            if let layerMedia {
                for t in project.layerTracks.indices {
                    for i in project.layerTracks[t].items.indices where uses.contains(project.layerTracks[t].items[i].path) {
                        project.layerTracks[t].items[i].path = path
                        project.layerTracks[t].items[i].name = url.lastPathComponent
                        project.layerTracks[t].items[i].aspect = layerMedia.aspect
                        if project.layerTracks[t].items[i].isVideo {
                            // Kept inside the new video's length.
                            let item = project.layerTracks[t].items[i]
                            project.layerTracks[t].items[i].fileDuration = layerMedia.duration
                            project.layerTracks[t].items[i].fileStart = min(item.fileStart, max(layerMedia.duration - VideoLayerItem.minimumLength, 0))
                            let room = (layerMedia.duration - project.layerTracks[t].items[i].fileStart) / item.normalizedSpeed
                            project.layerTracks[t].items[i].length = max(min(item.length, room), VideoLayerItem.minimumLength)
                        }
                    }
                }
            }
            if let picture {
                for index in project.overlayEffects.indices {
                    guard let old = project.overlayEffects[index].image, uses.contains(old.path) else { continue }
                    var new = picture
                    new.opacity = old.opacity
                    new.rotation = old.rotation
                    project.overlayEffects[index].image = new
                    // Same width, the new picture's shape.
                    let canvas = project.canvasSize()
                    project.overlayEffects[index].height = project.overlayEffects[index].width * Double(canvas.width) / new.aspect / Double(max(canvas.height, 1))
                }
            }
            if let sound {
                for index in project.audioTracks.indices where uses.contains(project.audioTracks[index].path) {
                    project.audioTracks[index].path = sound.path
                    project.audioTracks[index].name = url.lastPathComponent
                    project.audioTracks[index].duration = sound.duration
                    project.audioTracks[index].pieces = project.audioTracks[index].pieces.compactMap { piece in
                        var piece = piece
                        guard piece.fileStart < sound.duration - 0.05 else { return nil }
                        piece.length = min(piece.length, sound.duration - piece.fileStart)
                        return piece
                    }
                }
                project.audioTracks.removeAll { $0.pieces.isEmpty }
                if let music = project.music, uses.contains(music.path) {
                    project.music!.path = sound.path
                    project.music!.name = url.lastPathComponent
                    project.music!.duration = sound.duration
                }
            }
            guard var bin = project.mediaBin else { return }
            if case .imported(let id) = entry.origin, let index = bin.imported.firstIndex(where: { $0.id == id }) {
                bin.imported[index].path = path
                if bin.names[entry.key] == nil { bin.imported[index].name = url.lastPathComponent }
                bin.imported[index].placed = [picture?.path, sound?.path].compactMap { $0 }
            } else if entry.key.hasPrefix(VideoMediaBin.pathKeyPrefix), let newPath = picture?.path {
                // A picture's name and folder follow it to its new file.
                let newKey = VideoDemoProject.pathKey(newPath)
                bin.names[newKey] = bin.names.removeValue(forKey: entry.key)
                bin.folderOf[newKey] = bin.folderOf.removeValue(forKey: entry.key)
            }
            project.mediaBin = bin
        }
        showNotice(entry.isMissing ? L("Found “\(url.lastPathComponent)”") : L("Replaced with “\(url.lastPathComponent)”"), symbol: "arrow.triangle.2.circlepath")
        return true
    }

    // MARK: Extract audio

    /// Library ▸ Extract Audio: the video's sound as its own file in the
    /// Library (the video keeps its sound).
    @discardableResult
    func extractAudio(_ entry: VideoMediaEntry) async -> VideoMediaItem? {
        guard entry.kind == .video else { return nil }
        let asset = AVURLAsset(url: entry.url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty else {
            showNotice(L("“\(entry.name)” has no sound"), symbol: "speaker.slash")
            return nil
        }
        let output = VideoAssetStore.folder.appendingPathComponent("\(UUID().uuidString).m4a")
        isExtractingAudio = true
        defer { isExtractingAudio = false }
        do {
            try FileManager.default.createDirectory(at: VideoAssetStore.folder, withIntermediateDirectories: true)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw CocoaError(.fileWriteUnknown) }
            session.outputURL = output
            session.outputFileType = .m4a
            await session.export()
            if let error = session.error { throw error }
            guard session.status == .completed else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? FileManager.default.removeItem(at: output)
            showNotice(L("Couldn't extract the sound — \(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill", duration: 5)
            return nil
        }
        let base = URL(fileURLWithPath: entry.name).deletingPathExtension().lastPathComponent
        let item = VideoMediaItem(path: output.path, name: L("\(base) (audio).m4a"), kind: .audio, added: Date())
        updateBin(label: "Extract Audio") { bin in
            bin.imported.append(item)
            if let folder = bin.folderOf[entry.key] { bin.folderOf[VideoDemoProject.importedKey(item.id)] = folder }
        }
        showNotice(L("The sound is in the Library as “\(item.name)”"), symbol: "waveform")
        return item
    }
}

// MARK: - Dropping files

/// Files from Finder or the Library dropped on the timeline (at the drop
/// point) or the player (at the playhead).
struct VideoMediaDrop: DropDelegate {
    let model: VideoEditorModel
    /// Edit time at the drop point (nil: the playhead) and the track under
    /// it.
    let place: (CGPoint) -> (time: Double?, target: VideoEditorModel.DropTarget)

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func performDrop(info: DropInfo) -> Bool {
        let spot = place(info.location)
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            let urls = await VideoMediaDrop.urls(from: providers)
            if !urls.isEmpty { await model.placeMedia(urls, at: spot.time, target: spot.target) }
        }
        return true
    }

    /// The files a drag carries, in order.
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await withCheckedContinuation({ (done: CheckedContinuation<URL?, Never>) in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in done.resume(returning: url) }
            }) {
                urls.append(url)
            }
        }
        return urls
    }
}

extension VideoDemoProject {
    /// The clips of `source` (just added, at the end) moved to `time` on
    /// the timeline; a clip there is split in two around them.
    mutating func moveSourceClips(_ source: VideoProjectSource, toTimeline time: Double, totalDuration: Double) {
        var clips = normalizedTimelineClips(totalDuration: totalDuration)
        let isMoving: (VideoDemoTimelineClip) -> Bool = { $0.sourceStart >= source.offset - 0.001 && $0.sourceEnd <= source.end + 0.001 }
        let moving = clips.filter(isMoving)
        guard !moving.isEmpty else { return }
        clips.removeAll(where: isMoving)
        var index = clips.count
        var start = timelineLeadIn
        for (position, clip) in clips.enumerated() {
            let end = start + clip.outputDuration
            if time <= start + Self.minimumClipDuration {
                index = position
                break
            }
            if time < end - Self.minimumClipDuration {
                // In the middle of this clip: split it.
                let cut = clip.sourceStart + (time - start) * clip.normalizedSpeed
                var first = clip
                first.sourceEnd = cut
                first.fadeOut = 0
                var second = clip
                second.id = UUID()
                second.sourceStart = cut
                second.fadeIn = 0
                clips.replaceSubrange(position...position, with: [first, second])
                index = position + 1
                break
            }
            start = end
        }
        clips.insert(contentsOf: moving, at: index)
        timelineClips = clips
        syncTrimToTimeline(totalDuration: totalDuration)
    }
}
