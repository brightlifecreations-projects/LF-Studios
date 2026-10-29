import AVFoundation
import Foundation

/// A recording's own folder: after recording, everything the recording is
/// made of moves out of LF Studios' hidden folder into one folder the user
/// chose, laid out like a Creative Handoff, with a project file that opens
/// the whole edit:
///
///     Name/
///         Name.lfsp              the edit (paths relative to this folder)
///         01 Screen/Name.mp4     the recording, untouched, with its sound tracks
///         02 Camera/Camera.mov   the camera, if recorded
///         03 Audio/              Microphone.wav, System Audio.wav, if recorded
///         05 Captions/           written once there are captions
///         07 Data/Recording data.json   pointer, clicks, keys, typing, markers
///         Speaker notes.txt      if notes were used
///         README.txt
///
/// While recording, files are written where they always were (crash
/// recovery reads them there); they move only once the recording is done,
/// each one checked before the original goes.
enum VideoRecordingFolder {
    enum Layout {
        static let screen = "01 Screen"
        static let camera = "02 Camera"
        static let audio = "03 Audio"
        static let graphics = "04 Graphics"
        static let captions = "05 Captions"
        static let data = "07 Data"
        static let microphone = "Microphone.wav"
        static let systemAudio = "System Audio.wav"
        static let dataFile = "Recording data.json"
        static let notes = "Speaker notes.txt"
        static let readme = "README.txt"
    }

    /// `name` in `parent`, or "name 2", "name 3"… when taken.
    static func uniqueFolder(named name: String, in parent: URL) -> URL {
        let base = safeName(name)
        var candidate = parent.appendingPathComponent(base, isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(base) \(number)", isDirectory: true)
            number += 1
        }
        return candidate
    }

    /// A file name not taken in `folder` ("Name 2.ext"…).
    static func uniqueFile(named name: String, in folder: URL) -> URL {
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }

    /// A name Finder accepts: no slashes or colons, not empty.
    static func safeName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = cleaned.hasPrefix(".") ? String(cleaned.drop(while: { $0 == "." })) : cleaned
        return trimmed.isEmpty ? "Recording" : trimmed
    }

    /// The project files directly in `folder`, newest first.
    static func projectFiles(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { VideoProjectDocument.openableExtensions.contains($0.pathExtension.lowercased()) }
            .filter { FileManager.default.fileExists(atPath: VideoProjectPackage.manifestURL($0).path) }
            .sorted { modified($0) > modified($1) }
    }

    /// What made the project: nil for a project that isn't a folder
    /// project (or can't be read).
    static func folderInfo(of project: URL) -> VideoProjectDocument.FolderInfo? {
        guard let data = try? Data(contentsOf: VideoProjectPackage.manifestURL(project)),
              let document = try? VideoProjectDocument.decode(data), document.mediaMode == .folder else { return nil }
        return document.folder
    }

    /// The recording folder a project file belongs to: the folder around it,
    /// when LF Studios made it for a recording.
    static func recordingFolder(ofProject project: URL) -> URL? {
        folderInfo(of: project)?.kind == .recording ? project.deletingLastPathComponent() : nil
    }

    /// For a video in a recording's folder (`Name/01 Screen/Name.mp4`): that
    /// folder's project file.
    static func project(ofVideo video: URL) -> URL? {
        let screen = video.standardizedFileURL.deletingLastPathComponent()
        guard screen.lastPathComponent == Layout.screen else { return nil }
        return projectFiles(in: screen.deletingLastPathComponent()).first { recordingFolder(ofProject: $0) != nil }
    }

    /// 05 Captions as `files` says (name → contents): files that changed are
    /// written, captions files LF Studios wrote that are gone are removed,
    /// and other files there are left alone.
    static func writeCaptions(_ files: [String: String], in folder: URL) {
        let fm = FileManager.default
        let captions = folder.appendingPathComponent(Layout.captions, isDirectory: true)
        let existing = ((try? fm.contentsOfDirectory(at: captions, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension.lowercased() == "srt" }
        let name = projectFiles(in: folder).first?.deletingPathExtension().lastPathComponent
        for file in existing where !files.keys.contains(file.lastPathComponent) {
            // Only its own: "Name.srt" and "Name.<language>.srt".
            if let name, file.lastPathComponent == "\(name).srt" || (file.lastPathComponent.hasPrefix("\(name).") && file.lastPathComponent.split(separator: ".").count == name.split(separator: ".").count + 2) {
                try? fm.removeItem(at: file)
            }
        }
        guard !files.isEmpty else {
            if ((try? fm.contentsOfDirectory(atPath: captions.path)) ?? []).filter({ $0 != ".DS_Store" }).isEmpty { try? fm.removeItem(at: captions) }
            return
        }
        try? fm.createDirectory(at: captions, withIntermediateDirectories: true)
        for (file, text) in files {
            let url = captions.appendingPathComponent(file)
            if (try? String(contentsOf: url, encoding: .utf8)) != text {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

// MARK: - Moving files safely

/// Moves one file. A move on the same drive is a rename (nothing copied,
/// nothing to lose); to another drive it's a copy that's checked — same
/// size, and a video that still plays — before the original is removed.
protocol VideoFileMoving: Sendable {
    func move(_ source: URL, to destination: URL) async throws
}

struct VideoSafeFileMover: VideoFileMoving {
    enum Failure: LocalizedError {
        case copyDiffers(String)

        var errorDescription: String? {
            switch self {
            case .copyDiffers(let name): return "The copy of “\(name)” isn't the same as the original" // l10n-ignore: logged
            }
        }
    }

    func move(_ source: URL, to destination: URL) async throws {
        let fm = FileManager.default
        if Self.sameVolume(source, destination.deletingLastPathComponent()) {
            try fm.moveItem(at: source, to: destination)
            return
        }
        try fm.copyItem(at: source, to: destination)
        do {
            try await Self.verify(copy: destination, of: source)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
        try fm.removeItem(at: source)
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key = URLResourceKey.volumeIdentifierKey
        guard let first = try? a.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject,
              let second = try? b.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject else { return false }
        return first.isEqual(second)
    }

    /// Same size, and a video's copy still has its tracks and length.
    static func verify(copy: URL, of original: URL) async throws {
        let size = { (url: URL) in (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1 }
        guard size(copy) == size(original), size(copy) >= 0 else { throw Failure.copyDiffers(original.lastPathComponent) }
        guard VideoProjectPackage.videoExtensions.contains(original.pathExtension.lowercased()) else { return }
        let a = AVURLAsset(url: original)
        let b = AVURLAsset(url: copy)
        let tracksA = (try? await a.load(.tracks).count) ?? -1
        let tracksB = (try? await b.load(.tracks).count) ?? -2
        let lengthA = (try? await a.load(.duration).seconds) ?? -1
        let lengthB = (try? await b.load(.duration).seconds) ?? -2
        guard tracksA == tracksB, abs(lengthA - lengthB) < 0.01 else { throw Failure.copyDiffers(original.lastPathComponent) }
    }
}

// MARK: - Interrupted moves

/// A note of the moves in progress, written before each one: if LF Studios
/// stops halfway (a crash, power off), the next launch puts every file back
/// where it was and tries again.
struct VideoRecordingMoveLog: Codable, Equatable {
    struct Move: Codable, Equatable {
        var from: String
        var to: String
    }

    var id = UUID()
    /// The recording and where it was going.
    var video: String
    var parent: String
    var name: String
    var folder: String
    var moves: [Move] = []

    static func directory(root: URL = VideoStorageLocation.root) -> URL {
        root.appendingPathComponent("LF Studios", isDirectory: true).appendingPathComponent("RecordingMoves", isDirectory: true)
    }

    func url(root: URL = VideoStorageLocation.root) -> URL {
        Self.directory(root: root).appendingPathComponent("\(id.uuidString).json")
    }

    func save(root: URL = VideoStorageLocation.root) {
        try? FileManager.default.createDirectory(at: Self.directory(root: root), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url(root: root), options: .atomic) }
    }

    func remove(root: URL = VideoStorageLocation.root) {
        try? FileManager.default.removeItem(at: url(root: root))
    }

    static func all(root: URL = VideoStorageLocation.root) -> [VideoRecordingMoveLog] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory(root: root), includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { try? JSONDecoder().decode(VideoRecordingMoveLog.self, from: Data(contentsOf: $0)) }
    }

    /// Every file back where it was, and the half-made folder gone if
    /// nothing else is in it. A copy left halfway is removed; the original
    /// is still there.
    func rollBack() {
        let fm = FileManager.default
        for move in moves.reversed() {
            let from = URL(fileURLWithPath: move.from)
            let to = URL(fileURLWithPath: move.to)
            if fm.fileExists(atPath: to.path) {
                if fm.fileExists(atPath: from.path) {
                    try? fm.removeItem(at: to)
                } else {
                    try? fm.createDirectory(at: from.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? fm.moveItem(at: to, to: from)
                }
            }
        }
        VideoRecordingFolderWriter.removeIfOnlyEmptyFolders(URL(fileURLWithPath: folder, isDirectory: true))
    }
}

// MARK: - Writing the folder

enum VideoRecordingFolderWriter {
    struct Result: Equatable {
        /// Where the recording was before.
        var original: URL
        var folder: URL
        var video: URL
        var project: URL
        /// Files that couldn't be written (the folder works without them).
        var skipped: [String]
    }

    enum Failure: LocalizedError, Equatable {
        case notFound
        case couldNotMove(file: String, reason: String)
        case couldNotCreate(String)

        var errorDescription: String? {
            switch self {
            case .notFound: return L("The recording isn't where it was saved.")
            case .couldNotMove(let file, let reason): return L("“\(file)” couldn't be moved: \(reason)")
            case .couldNotCreate(let reason): return L("The folder couldn't be made: \(reason)")
            }
        }
    }

    /// Moves a finished recording, its camera, and its data into a new
    /// folder `name` in `parent`, and writes its sound files, data, README,
    /// and project file. If a file can't be moved, everything goes back as
    /// it was and this throws: the recording still opens from where it was.
    static func organize(video: URL, into parent: URL, name: String, mover: VideoFileMoving = VideoSafeFileMover(), root: URL = VideoStorageLocation.root) async throws -> Result {
        let fm = FileManager.default
        guard fm.fileExists(atPath: video.path) else { throw Failure.notFound }
        let originalID = VideoFileIdentity.ensureID(of: video)
        var metadata = VideoDemoSidecarStore.load(for: video, baseDirectory: root)

        let folder = VideoRecordingFolder.uniqueFolder(named: name, in: parent)
        let finalName = folder.lastPathComponent
        do {
            try fm.createDirectory(at: folder.appendingPathComponent(VideoRecordingFolder.Layout.screen, isDirectory: true), withIntermediateDirectories: true)
        } catch {
            throw Failure.couldNotCreate(error.localizedDescription)
        }

        var log = VideoRecordingMoveLog(video: video.path, parent: parent.path, name: name, folder: folder.path)
        log.save(root: root)

        let newVideo = folder.appendingPathComponent(VideoRecordingFolder.Layout.screen, isDirectory: true)
            .appendingPathComponent("\(finalName).\(video.pathExtension.isEmpty ? "mp4" : video.pathExtension)")
        var plan: [(from: URL, to: URL)] = [(video, newVideo)]
        var newCamera: URL?
        if let webcam = metadata?.webcam, fm.fileExists(atPath: webcam.path) {
            let ext = URL(fileURLWithPath: webcam.path).pathExtension
            newCamera = folder.appendingPathComponent(VideoRecordingFolder.Layout.camera, isDirectory: true)
                .appendingPathComponent("Camera.\(ext.isEmpty ? "mov" : ext)")
            plan.append((URL(fileURLWithPath: webcam.path), newCamera!))
        }

        for step in plan {
            log.moves.append(.init(from: step.from.path, to: step.to.path))
            log.save(root: root)
            do {
                try fm.createDirectory(at: step.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await mover.move(step.from, to: step.to)
            } catch {
                log.rollBack()
                log.remove(root: root)
                throw Failure.couldNotMove(file: step.from.lastPathComponent, reason: error.localizedDescription)
            }
        }
        // Moved within the drive the stamp went along; a copy may have lost it.
        if let originalID, VideoFileIdentity.stampedID(of: newVideo) != originalID {
            VideoFileIdentity.stamp(originalID, on: newVideo)
        }

        // The recording's data now points into the folder.
        if metadata != nil {
            metadata!.videoURLPath = newVideo.path
            metadata!.bookmark = try? newVideo.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
            if let newCamera { metadata!.webcam?.path = newCamera.path }
            VideoDemoSidecarStore.save(metadata!, for: newVideo, baseDirectory: root)
        }

        var skipped: [String] = []
        await writeSoundFiles(video: newVideo, metadata: metadata, folder: folder, skipped: &skipped)
        writeData(metadata, folder: folder, video: newVideo, camera: newCamera, skipped: &skipped)
        if let notes = metadata?.speakerNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            do {
                try notes.write(to: folder.appendingPathComponent(VideoRecordingFolder.Layout.notes), atomically: true, encoding: .utf8)
            } catch {
                skipped.append(VideoRecordingFolder.Layout.notes)
            }
        }

        let project = folder.appendingPathComponent("\(finalName).\(VideoProjectDocument.fileExtension)", isDirectory: true)
        let duration = metadata?.duration ?? 0
        var edit = VideoDemoProject.fresh(sourceURL: newVideo, duration: duration, sourceSize: CGSize(width: metadata?.sourceWidth ?? 0, height: metadata?.sourceHeight ?? 0))
        if let metadata { edit.apply(metadata: metadata) }
        // An edit made already (the editor was opened before the move): kept.
        if let draft = VideoDemoDraftStore.load(for: newVideo, baseDirectory: root) {
            edit = draft.project
            edit.sourcePath = newVideo.path
        }
        let contents = VideoProjectContents(project: edit, recording: metadata, sourceRecordings: [:])
        do {
            try VideoProjectPackage.save(contents, to: project, mode: .folder, appVersion: appVersion, folder: .init(kind: .recording))
        } catch {
            skipped.append(project.lastPathComponent)
        }
        writeReadme(folder: folder, video: newVideo, camera: newCamera, skipped: skipped)
        log.remove(root: root)
        VideoRecordingFolders.add(folder, root: root)
        return Result(original: video, folder: folder, video: newVideo, project: project, skipped: skipped)
    }

    static var appVersion: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    /// 03 Audio: each of the recording's sound tracks as its own WAV
    /// (48 kHz, 24-bit), if there's room for it.
    private static func writeSoundFiles(video: URL, metadata: VideoDemoRecordingMetadata?, folder: URL, skipped: inout [String]) async {
        let asset = AVURLAsset(url: video)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty else { return }
        var channels: [Int] = []
        for track in tracks {
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            let count = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }.map(Int.init) ?? 2
            channels.append(count)
        }
        let kinds = VideoAudioKind.resolve(recorded: metadata?.audioTracks, channelCounts: channels)
        let length = (try? await asset.load(.duration).seconds) ?? metadata?.duration ?? 0
        guard length > 0 else { return }
        let audioFolder = folder.appendingPathComponent(VideoRecordingFolder.Layout.audio, isDirectory: true)
        for (index, kind) in kinds.enumerated() where index < tracks.count {
            let name: String
            switch kind {
            case .microphone: name = VideoRecordingFolder.Layout.microphone
            case .system: name = VideoRecordingFolder.Layout.systemAudio
            case .mixed: name = kinds.count > 1 ? "Audio \(index + 1).wav" : "Audio.wav"
            }
            let channelCount = kind == .microphone ? 1 : 2
            let bytes = Int64(length * 48_000 * 3 * Double(channelCount)) + 1_000_000
            guard (VideoExportFiles.availableBytes(at: audioFolder.deletingLastPathComponent().appendingPathComponent(name)) ?? .max) > bytes * 2 else {
                skipped.append("\(VideoRecordingFolder.Layout.audio)/\(name)")
                continue
            }
            do {
                try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
                let piece = VideoHandoffPiece(url: video, audioTrack: index, sourceStart: 0, sourceDuration: length, at: 0)
                try await VideoHandoffWriter.audio([piece], duration: length, channels: channelCount, aac: false, to: audioFolder.appendingPathComponent(name), report: { _ in }, isCancelled: { false })
            } catch {
                try? FileManager.default.removeItem(at: audioFolder.appendingPathComponent(name))
                skipped.append("\(VideoRecordingFolder.Layout.audio)/\(name)")
            }
        }
        removeIfOnlyEmptyFolders(audioFolder)
    }

    /// 07 Data: the pointer, clicks, keys, typing, and markers, with the
    /// recording's files named relative to the folder.
    private static func writeData(_ metadata: VideoDemoRecordingMetadata?, folder: URL, video: URL, camera: URL?, skipped: inout [String]) {
        guard var data = metadata else { return }
        data.videoURLPath = "\(VideoRecordingFolder.Layout.screen)/\(video.lastPathComponent)"
        if let camera { data.webcam?.path = "\(VideoRecordingFolder.Layout.camera)/\(camera.lastPathComponent)" }
        data.bookmark = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = folder.appendingPathComponent(VideoRecordingFolder.Layout.data, isDirectory: true).appendingPathComponent(VideoRecordingFolder.Layout.dataFile)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(data).write(to: url, options: .atomic)
        } catch {
            skipped.append("\(VideoRecordingFolder.Layout.data)/\(VideoRecordingFolder.Layout.dataFile)")
        }
    }

    /// README.txt: what each file is.
    static func writeReadme(folder: URL, video: URL, camera: URL?, skipped: [String]) {
        let fm = FileManager.default
        let name = folder.lastPathComponent
        func exists(_ relative: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(relative).path) }
        // l10n-ignore-begin: README.txt is written in English, like Creative Handoff's
        var lines = [
            "\(name) — LF Studios recording",
            "Saved by LF Studios\(appVersion.map { " \($0)" } ?? "") on \(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)))." ,
            "",
            "Open \(name).\(VideoProjectDocument.fileExtension) (or this whole folder) in LF Studios to edit it. Move or rename the folder as you like: everything inside is found relative to it.",
            "",
            "FILES",
            "",
            "\(name).\(VideoProjectDocument.fileExtension)",
            "  The project: the whole edit, kept up to date as you edit. It opens in LF Studios 1.9.0 or later.",
            "",
            "\(VideoRecordingFolder.Layout.screen)/\(video.lastPathComponent)",
            "  The screen recording, untouched, with its sound tracks inside.",
        ]
        if let camera {
            lines += ["", "\(VideoRecordingFolder.Layout.camera)/\(camera.lastPathComponent)", "  The camera video, untouched. It may start a moment before or after the screen; the project knows the offset."]
        }
        for (file, about) in [(VideoRecordingFolder.Layout.microphone, "Your microphone (mono)"), (VideoRecordingFolder.Layout.systemAudio, "Sound playing on the Mac (stereo)")] where exists("\(VideoRecordingFolder.Layout.audio)/\(file)") {
            lines += ["", "\(VideoRecordingFolder.Layout.audio)/\(file)", "  \(about), as a WAV (48 kHz, 24-bit), the same length as the screen recording. A copy of the track inside the screen recording, for other apps."]
        }
        lines += ["", "\(VideoRecordingFolder.Layout.captions)/", "  Captions as .srt files, written once there are captions and updated as you edit them."]
        if exists("\(VideoRecordingFolder.Layout.data)/\(VideoRecordingFolder.Layout.dataFile)") {
            lines += ["", "\(VideoRecordingFolder.Layout.data)/\(VideoRecordingFolder.Layout.dataFile)", "  The pointer path, clicks, keyboard shortcuts, typing positions and key-press times (if recorded), and markers, in recording time."]
        }
        if exists(VideoRecordingFolder.Layout.notes) {
            lines += ["", VideoRecordingFolder.Layout.notes, "  The speaker notes you read from while recording."]
        }
        if !skipped.isEmpty {
            lines += ["", "NOT WRITTEN", ""] + skipped.map { "  \($0)" }
        }
        // l10n-ignore-end
        try? (lines.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent(VideoRecordingFolder.Layout.readme), atomically: true, encoding: .utf8)
    }

    /// Removes `folder` if it holds nothing but empty folders.
    static func removeIfOnlyEmptyFolders(_ folder: URL) {
        let fm = FileManager.default
        guard let items = fm.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
        for case let item as URL in items {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDirectory && item.lastPathComponent != ".DS_Store" { return }
        }
        try? fm.removeItem(at: folder)
    }

    /// At launch: moves a crash interrupted go back, and are made again;
    /// recordings finished while quitting get their folders now.
    static func finishInterrupted(root: URL = VideoStorageLocation.root, mover: VideoFileMoving = VideoSafeFileMover()) async -> [Result] {
        var queue: [(video: URL, parent: URL, name: String)] = []
        for log in VideoRecordingMoveLog.all(root: root) {
            log.rollBack()
            log.remove(root: root)
            queue.append((URL(fileURLWithPath: log.video), URL(fileURLWithPath: log.parent, isDirectory: true), log.name))
        }
        for video in VideoRecordingFolders.takePending(root: root) {
            queue.append((video, URL(fileURLWithPath: Settings.recordingFolder, isDirectory: true), video.deletingPathExtension().lastPathComponent))
        }
        var results: [Result] = []
        for item in queue where FileManager.default.fileExists(atPath: item.video.path) && VideoRecordingFolder.project(ofVideo: item.video) == nil {
            if let result = try? await organize(video: item.video, into: item.parent, name: item.name, mover: mover, root: root) {
                results.append(result)
            }
        }
        return results
    }
}

// MARK: - Where recording folders are

/// Every recording folder LF Studios made, wherever it was saved (Home ▸
/// Recordings lists them). Kept as bookmarks, so a folder moved or renamed
/// in Finder is still found; folders in the Recording folder are found by
/// looking there too.
enum VideoRecordingFolders {
    struct Entry: Codable, Equatable {
        var path: String
        var bookmark: Data?
    }

    static func listURL(root: URL = VideoStorageLocation.root) -> URL {
        root.appendingPathComponent("LF Studios", isDirectory: true).appendingPathComponent("RecordingFolders.json")
    }

    static func pendingURL(root: URL = VideoStorageLocation.root) -> URL {
        root.appendingPathComponent("LF Studios", isDirectory: true).appendingPathComponent("RecordingFoldersPending.json")
    }

    private static func read(_ url: URL) -> [Entry] {
        (try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))) ?? []
    }

    private static func write(_ entries: [Entry], to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }

    static func add(_ folder: URL, root: URL = VideoStorageLocation.root) {
        var entries = read(listURL(root: root)).filter { $0.path != folder.standardizedFileURL.path }
        entries.append(Entry(path: folder.standardizedFileURL.path, bookmark: try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)))
        write(entries, to: listURL(root: root))
    }

    static func remove(_ folder: URL, root: URL = VideoStorageLocation.root) {
        write(read(listURL(root: root)).filter { $0.path != folder.standardizedFileURL.path }, to: listURL(root: root))
    }

    /// The project file of every recording folder that's still there,
    /// newest first: the remembered ones (found again if moved), and any in
    /// `scan` (the Recording folder).
    static func projects(scanning scan: [URL], root: URL = VideoStorageLocation.root) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        func take(_ folder: URL) {
            guard let project = VideoRecordingFolder.projectFiles(in: folder).first(where: { VideoRecordingFolder.recordingFolder(ofProject: $0) != nil }),
                  seen.insert(project.standardizedFileURL.path).inserted else { return }
            found.append(project.standardizedFileURL)
        }
        var entries = read(listURL(root: root))
        var changed = false
        for index in entries.indices {
            var folder = URL(fileURLWithPath: entries[index].path, isDirectory: true)
            if !FileManager.default.fileExists(atPath: folder.path), let bookmark = entries[index].bookmark {
                var stale = false
                if let moved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                    folder = moved
                    entries[index].path = moved.standardizedFileURL.path
                    changed = true
                }
            }
            take(folder)
        }
        if changed { write(entries, to: listURL(root: root)) }
        for directory in scan {
            let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for item in items where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && !VideoProjectDocument.openableExtensions.contains(item.pathExtension.lowercased()) {
                take(item)
            }
        }
        return found.sorted { VideoRecordingFolder.modified(VideoProjectPackage.manifestURL($0)) > VideoRecordingFolder.modified(VideoProjectPackage.manifestURL($1)) }
    }

    /// A recording finished while LF Studios quit: it gets its folder (in
    /// the Recording folder) at the next launch.
    static func addPending(_ video: URL, root: URL = VideoStorageLocation.root) {
        var entries = read(pendingURL(root: root))
        entries.append(Entry(path: video.path, bookmark: nil))
        write(entries, to: pendingURL(root: root))
    }

    static func takePending(root: URL = VideoStorageLocation.root) -> [URL] {
        let entries = read(pendingURL(root: root))
        try? FileManager.default.removeItem(at: pendingURL(root: root))
        return entries.map { URL(fileURLWithPath: $0.path) }
    }
}
