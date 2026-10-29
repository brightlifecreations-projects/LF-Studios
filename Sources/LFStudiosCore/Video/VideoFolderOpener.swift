import AppKit
import AVFoundation
import SwiftUI

// Opening a whole folder (Open…, ⌘O, or a folder dropped on Home or the
// Dock icon):
// - a folder with an LF Studios project in it (a recording's own folder, a
//   Creative Handoff since 1.6.0) opens that project, exactly as it was;
// - an older Creative Handoff without one is rebuilt from what it holds:
//   its files, README.txt, and Timeline.fcpxml;
// - any other folder shows "Import Folder": a role for each video and
//   sound file found.
// Nothing in the folder changes until Save (⌘S) writes the project there.

enum VideoFolderKind: Equatable {
    case project(URL)
    case handoff
    case other
}

enum VideoFolderReader {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "aiff", "aif", "flac", "caf"]

    static func isFolder(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            && !VideoProjectDocument.openableExtensions.contains(url.pathExtension.lowercased())
    }

    static func kind(of folder: URL) -> VideoFolderKind {
        if let project = VideoRecordingFolder.projectFiles(in: folder).first { return .project(project) }
        return isHandoff(folder) ? .handoff : .other
    }

    /// A Creative Handoff: its README says so, or it has a screen folder
    /// and the files a handoff writes next to it.
    static func isHandoff(_ folder: URL) -> Bool {
        let fm = FileManager.default
        if let readme = try? String(contentsOf: folder.appendingPathComponent("README.txt"), encoding: .utf8),
           readme.split(separator: "\n", maxSplits: 1).first?.hasSuffix("— Creative Handoff") == true { // l10n-ignore: README.txt is English
            return true
        }
        let has = { (name: String) in fm.fileExists(atPath: folder.appendingPathComponent(name).path) }
        return has(VideoRecordingFolder.Layout.screen) && (has("Timeline.fcpxml") || has(VideoRecordingFolder.Layout.data))
    }

    /// The video and sound files in a folder and its subfolders (not inside
    /// projects), in name order.
    static func mediaFiles(in folder: URL) -> [URL] {
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let item as URL in items {
            let ext = item.pathExtension.lowercased()
            if videoExtensions.contains(ext) || audioExtensions.contains(ext) { found.append(item.standardizedFileURL) }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func files(in folder: URL, extensions: Set<String>) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .map(\.standardizedFileURL)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

// MARK: - What older handoffs say about themselves

/// README.txt of a Creative Handoff: which clips, whether lined up, and
/// where each file starts.
struct VideoHandoffReadmeFacts: Equatable {
    var trimmed = false
    var linedUp = false
    /// Relative path → "starts at" seconds.
    var starts: [String: Double] = [:]

    static func parse(_ text: String) -> VideoHandoffReadmeFacts {
        var facts = VideoHandoffReadmeFacts()
        let lines = text.components(separatedBy: "\n")
        facts.trimmed = lines.contains { $0.hasPrefix("Clips: trimmed") } // l10n-ignore: README.txt is English
        facts.linedUp = lines.contains { $0.hasPrefix("Lined up:") } // l10n-ignore: README.txt is English
        var current: String?
        for line in lines {
            if !line.hasPrefix(" "), line.contains("/") || line.hasSuffix(".mp4") || line.hasSuffix(".mov") {
                current = line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let current, line.hasPrefix("  "), let range = line.range(of: "starts at ") else { continue }
            let rest = line[range.upperBound...].prefix { $0 != " " }
            if let seconds = clock(String(rest)) { facts.starts[current] = seconds }
        }
        return facts
    }

    /// "0:25.64", "1:02:03.50" → seconds.
    static func clock(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

/// Timeline.fcpxml as LF Studios writes it: the clips in their lanes and
/// the markers.
struct VideoHandoffTimelineFacts: Equatable {
    struct Clip: Equatable {
        /// "01 Screen/Name.mp4"
        var file: String
        var lane: Int
        var offset: Double
        var start: Double
        var duration: Double
        var speed: Double
    }

    struct Marker: Equatable {
        var time: Double
        var name: String
    }

    var clips: [Clip] = []
    var markers: [Marker] = []

    static func parse(_ data: Data) -> VideoHandoffTimelineFacts? {
        guard let document = try? XMLDocument(data: data) else { return nil }
        var files: [String: String] = [:]
        for asset in (try? document.nodes(forXPath: "//asset")) ?? [] {
            guard let element = asset as? XMLElement, let id = element.attribute(forName: "id")?.stringValue,
                  let src = (try? element.nodes(forXPath: "media-rep"))?.compactMap({ ($0 as? XMLElement)?.attribute(forName: "src")?.stringValue }).first,
                  let url = URL(string: src) else { continue }
            // The folder may have moved since: what matters is its place inside.
            let components = url.pathComponents
            files[id] = components.suffix(components.count >= 2 ? 2 : 1).joined(separator: "/")
        }
        var facts = VideoHandoffTimelineFacts()
        for node in (try? document.nodes(forXPath: "//asset-clip")) ?? [] {
            guard let element = node as? XMLElement, let ref = element.attribute(forName: "ref")?.stringValue, let file = files[ref] else { continue }
            let lane = Int(element.attribute(forName: "lane")?.stringValue ?? "0") ?? 0
            let start = time(element.attribute(forName: "start")?.stringValue) ?? 0
            let duration = time(element.attribute(forName: "duration")?.stringValue) ?? 0
            var speed = 1.0
            let points = ((try? element.nodes(forXPath: "timeMap/timept")) ?? []).compactMap { $0 as? XMLElement }
            if points.count == 2, let t0 = time(points[0].attribute(forName: "time")?.stringValue), let t1 = time(points[1].attribute(forName: "time")?.stringValue),
               let v0 = time(points[0].attribute(forName: "value")?.stringValue), let v1 = time(points[1].attribute(forName: "value")?.stringValue), t1 > t0 {
                speed = (v1 - v0) / (t1 - t0)
            }
            facts.clips.append(Clip(file: file, lane: lane, offset: time(element.attribute(forName: "offset")?.stringValue) ?? 0, start: start, duration: duration, speed: speed))
        }
        for node in (try? document.nodes(forXPath: "//marker")) ?? [] {
            guard let element = node as? XMLElement, let start = time(element.attribute(forName: "start")?.stringValue) else { continue }
            facts.markers.append(Marker(time: start, name: element.attribute(forName: "value")?.stringValue ?? ""))
        }
        return facts
    }

    /// "1359/53s", "3s" → seconds.
    static func time(_ text: String?) -> Double? {
        guard var text, text.hasSuffix("s") else { return nil }
        text.removeLast()
        let parts = text.split(separator: "/")
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { return a / b }
        return Double(text)
    }
}

/// SubRip: the cues, in seconds.
enum VideoSubtitleReader {
    struct Cue: Equatable {
        var start: Double
        var end: Double
        var text: String
    }

    static func srt(_ text: String) -> [Cue] {
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        return blocks.compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let sides = lines[timing].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard sides.count == 2, let start = seconds(sides[0]), let end = seconds(sides[1]) else { return nil }
            let words = lines[(timing + 1)...].joined(separator: "\n")
            return words.isEmpty ? nil : Cue(start: start, end: end, text: words)
        }
    }

    /// "00:01:02,500" → 62.5
    static func seconds(_ text: String) -> Double? {
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}

// MARK: - Building a project from files

/// What was opened, and what couldn't be.
struct VideoFolderSummary: Equatable {
    var loaded: [String] = []
    var notLoaded: [String] = []
}

enum VideoFolderProjectBuilder {
    enum Failure: LocalizedError {
        case noScreen

        var errorDescription: String? { L("There's no video to use as the screen recording.") }
    }

    /// A project from screen recordings (played one after the other) and a
    /// camera video `cameraOffset` seconds after the first screen recording
    /// (camera time = recording time − offset).
    static func project(screens: [URL], camera: URL?, cameraOffset: Double, metadata: VideoDemoRecordingMetadata?) async throws -> VideoProjectContents {
        guard let first = screens.first else { throw Failure.noScreen }
        let primary = try await VideoSourceTracks.load(url: first)
        var project = VideoDemoProject.fresh(sourceURL: first, duration: primary.duration, sourceSize: primary.size)
        var recording = metadata ?? VideoDemoRecordingMetadata(
            videoURLPath: first.path, createdAt: Date(), duration: primary.duration,
            sourceWidth: Double(primary.size.width), sourceHeight: Double(primary.size.height),
            fps: Int(primary.frameRate.rounded()), nativeCursorVisible: true, cursorSamples: [], clickEvents: []
        )
        recording.videoURLPath = first.path
        recording.duration = primary.duration
        recording.sourceWidth = Double(primary.size.width)
        recording.sourceHeight = Double(primary.size.height)
        if recording.audioTracks == nil {
            recording.audioTracks = VideoAudioKind.resolve(recorded: nil, channelCounts: primary.audioChannelCounts)
        }
        project.apply(metadata: recording)
        project.trimEnd = primary.duration
        project.ensureTimeline(totalDuration: primary.duration)
        if screens.count > 1 {
            project.ensurePrimarySource(duration: primary.duration, kinds: recording.audioTracks ?? [], webcam: nil, pointPixelScale: recording.pointPixelScale)
            for url in screens.dropFirst() {
                let tracks = try await VideoSourceTracks.load(url: url)
                let source = VideoProjectSource(
                    path: url.path, bookmark: nil, name: url.lastPathComponent, duration: tracks.duration,
                    width: Double(tracks.size.width), height: Double(tracks.size.height),
                    audioKinds: VideoAudioKind.resolve(recorded: nil, channelCounts: tracks.audioChannelCounts),
                    hasPointer: false, pointPixelScale: nil, webcam: nil
                )
                project.appendSource(source, metadata: nil)
            }
            project.trimEnd = project.sourceAxisDuration ?? primary.duration
        }
        if let camera, var imported = await VideoImportedCamera.read(camera, offset: cameraOffset) {
            imported.bookmark = nil
            project.importedCamera = imported
            project.webcam.visible = true
        }
        return VideoProjectContents(project: project, recording: recording, sourceRecordings: [:])
    }
}

/// An older Creative Handoff (no project file), opened again from its files.
@MainActor
enum VideoHandoffRebuilder {
    static func rebuild(_ folder: URL) async throws -> (contents: VideoProjectContents, summary: VideoFolderSummary) {
        var summary = VideoFolderSummary()
        let readme = (try? String(contentsOf: folder.appendingPathComponent("README.txt"), encoding: .utf8)).map(VideoHandoffReadmeFacts.parse) ?? VideoHandoffReadmeFacts()
        let timeline = (try? Data(contentsOf: folder.appendingPathComponent("Timeline.fcpxml"))).flatMap(VideoHandoffTimelineFacts.parse)
        let screenFolder = folder.appendingPathComponent(VideoRecordingFolder.Layout.screen, isDirectory: true)
        var screens = VideoFolderReader.files(in: screenFolder, extensions: VideoFolderReader.videoExtensions)
        guard !screens.isEmpty else { throw VideoFolderProjectBuilder.Failure.noScreen }
        func relative(_ url: URL) -> String { "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)" }
        // In the order the edit plays them.
        let screenClips = timeline?.clips.filter { $0.lane == 1 } ?? []
        if !screenClips.isEmpty {
            let order = screenClips.sorted { $0.offset < $1.offset }.map(\.file)
            screens.sort { (order.firstIndex(of: relative($0)) ?? .max) < (order.firstIndex(of: relative($1)) ?? .max) }
        }

        // The pointer, clicks, and keys: on one uncut recording's clock.
        var metadata: VideoDemoRecordingMetadata?
        let dataFile = folder.appendingPathComponent("\(VideoRecordingFolder.Layout.data)/Pointer, clicks and keys.json") // l10n-ignore: a file name
        if screens.count == 1, !readme.trimmed, let data = try? Data(contentsOf: dataFile), let pointer = VideoHandoffPointerData.parse(data) {
            let tracks = try await VideoSourceTracks.load(url: screens[0])
            metadata = VideoDemoRecordingMetadata(
                videoURLPath: screens[0].path, createdAt: Date(), duration: tracks.duration,
                sourceWidth: Double(tracks.size.width), sourceHeight: Double(tracks.size.height), fps: Int(tracks.frameRate.rounded()),
                nativeCursorVisible: pointer.samples.isEmpty, cursorSamples: pointer.samples, clickEvents: pointer.clicks, renderCursor: !pointer.samples.isEmpty
            )
            metadata?.keystrokes = pointer.keys.isEmpty ? nil : pointer.keys
            summary.loaded.append(L("The pointer, clicks, and keyboard shortcuts"))
        } else if FileManager.default.fileExists(atPath: dataFile.path) {
            summary.notLoaded.append(L("The pointer data — it fits only an uncut recording"))
        }

        // The camera, where it belongs.
        let cameras = VideoFolderReader.files(in: folder.appendingPathComponent(VideoRecordingFolder.Layout.camera, isDirectory: true), extensions: VideoFolderReader.videoExtensions)
        var camera: URL?
        var cameraOffset = 0.0
        if let first = cameras.first {
            if readme.trimmed {
                summary.notLoaded.append(L("\(relative(first)) — it was cut like the edit, so it can't be lined up with the recording again"))
            } else {
                camera = first
                cameraOffset = (readme.starts[relative(first)] ?? 0) - (readme.starts[relative(screens[0])] ?? 0)
                summary.loaded.append(L("The camera, \(VideoEditorModel.format(cameraOffset)) after the screen"))
            }
            for other in cameras.dropFirst() { summary.notLoaded.append(L("\(relative(other)) — only one camera video can be shown")) }
        }

        var contents = try await VideoFolderProjectBuilder.project(screens: screens, camera: camera, cameraOffset: cameraOffset, metadata: metadata)
        summary.loaded.insert(screens.count == 1 ? L("The screen recording") : L("\(screens.count) screen clips, one after the other"), at: 0)

        // Cuts and speed changes from the timeline file.
        if !screenClips.isEmpty {
            let offsets: [String: Double] = {
                var result: [String: Double] = [relative(screens[0]): 0]
                for source in contents.project.sources where !source.isPrimary {
                    result["\(VideoRecordingFolder.Layout.screen)/\(source.name)"] = source.offset
                }
                return result
            }()
            let clips = screenClips.sorted { $0.offset < $1.offset }.compactMap { clip -> VideoDemoTimelineClip? in
                guard let axis = offsets[clip.file], clip.duration > 0.001 else { return nil }
                let start = axis + clip.start
                return VideoDemoTimelineClip(sourceStart: start, sourceEnd: start + clip.duration * clip.speed, speed: clip.speed)
            }
            if !clips.isEmpty {
                contents.project.timelineClips = clips
                summary.loaded.append(L("Cuts and speed changes (\(clips.count) clips)"))
            }
        }
        let segments = contents.project.timelineSegments(totalDuration: contents.project.sourceAxisDuration ?? contents.project.trimEnd)
        /// Edit time → recording time.
        func sourceTime(_ time: Double) -> Double? {
            segments.first { time >= $0.timelineStart - 0.0005 && time <= $0.timelineStart + $0.duration + 0.0005 }?.sourceTime(forTimelineTime: time)
        }

        // Markers (on the edit's clock in the timeline file).
        if let markers = timeline?.markers, !markers.isEmpty {
            contents.project.markers = markers.compactMap { marker in sourceTime(marker.time).map { VideoMarker(time: $0, name: marker.name.isEmpty ? nil : marker.name) } }
            summary.loaded.append(L("\(contents.project.markers.count) markers"))
        }

        // Captions: on the edit's clock (trimmed) or the recording's.
        let captionFiles = VideoFolderReader.files(in: folder.appendingPathComponent(VideoRecordingFolder.Layout.captions, isDirectory: true), extensions: ["srt"])
        if let main = captionFiles.first(where: { $0.deletingPathExtension().pathExtension.isEmpty }) ?? captionFiles.first,
           let text = try? String(contentsOf: main, encoding: .utf8) {
            let cues = VideoSubtitleReader.srt(text)
            let lines = cues.compactMap { cue -> VideoCaptionLine? in
                let start = readme.trimmed ? sourceTime(cue.start) : cue.start
                let end = readme.trimmed ? sourceTime(cue.end) : cue.end
                guard let start, let end, end > start else { return nil }
                return VideoCaptionLine(id: UUID(), start: start, end: end, text: cue.text, words: [])
            }
            contents.project.captions = lines
            summary.loaded.append(L("\(lines.count) captions"))
            for file in captionFiles where file != main {
                let language = file.deletingPathExtension().pathExtension
                guard !language.isEmpty, let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let translated = VideoSubtitleReader.srt(text)
                guard translated.count == lines.count else {
                    summary.notLoaded.append(L("\(relative(file)) — its lines don't match the captions"))
                    continue
                }
                contents.project.captionTracks.translations.append(VideoCaptionTranslation(language: language, lines: zip(lines, translated).map { .init(id: $0.id, text: $1.text, sourceText: $0.text) }))
                summary.loaded.append(L("Captions in \(VideoCaptionTranslation.displayName(language))"))
            }
        }

        // Sound: the screen recording has its tracks inside; separate files
        // become tracks of their own in the next version.
        let audioFolder = folder.appendingPathComponent(VideoRecordingFolder.Layout.audio, isDirectory: true)
        let sounds = VideoFolderReader.files(in: audioFolder, extensions: VideoFolderReader.audioExtensions)
        let screenHasSound = !((try? await VideoSourceTracks.load(url: screens[0]).audio.isEmpty) ?? true)
        for sound in sounds {
            let name = sound.lastPathComponent
            if name.hasPrefix("Music.") {
                var music = VideoMusicTrack(path: sound.path, name: name, duration: (try? await AVURLAsset(url: sound).load(.duration).seconds) ?? 0)
                if readme.trimmed {
                    // Laid out like the edit already: level and fades are in it.
                    music.volume = 1
                    music.fadeIn = 0
                    music.fadeOut = 0
                    music.loops = false
                    music.ducking = false
                }
                contents.project.music = music
                summary.loaded.append(L("The music"))
            } else if name == "Full Mix.wav" { // l10n-ignore: a file name
                continue
            } else if screenHasSound {
                continue // the same sound as the screen recording's own tracks
            } else if let prepared = try? await VideoExternalAudioImport.prepare(sound) {
                // On the handoff's clock: the edit's (trimmed) or the recording's.
                let starts = readme.starts[relative(sound)] ?? 0
                var track = VideoExternalAudioTrack(path: prepared.url.path, name: name, duration: prepared.duration, at: readme.trimmed ? starts : 0)
                if !readme.trimmed { track.lock(toRecordingOffset: starts) }
                track.useAsVoice = name == VideoRecordingFolder.Layout.microphone && !contents.project.audioTracks.contains(where: \.useAsVoice)
                contents.project.audioTracks.append(track)
                summary.loaded.append(L("\(relative(sound)), as its own track"))
            } else {
                summary.notLoaded.append(L("\(relative(sound)) — this Mac can't play it"))
            }
        }
        if screenHasSound { summary.loaded.append(L("The sound recorded with the screen")) }
        if !VideoFolderReader.files(in: folder.appendingPathComponent(VideoRecordingFolder.Layout.graphics, isDirectory: true), extensions: ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]).isEmpty {
            summary.notLoaded.append(L("The pictures in 04 Graphics — older handoffs don't say where they were placed"))
        }
        summary.notLoaded.append(L("Zooms, styles, annotations, and title cards — older handoffs don't include them"))
        return (contents, summary)
    }
}

/// "Pointer, clicks and keys.json" from a Creative Handoff.
struct VideoHandoffPointerData {
    var samples: [VideoDemoCursorSample]
    var clicks: [VideoDemoClickEvent]
    var keys: [VideoKeystrokeEvent]

    static func parse(_ data: Data) -> VideoHandoffPointerData? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
        let pointer = (object["pointer"] as? [[String: Any]] ?? []).compactMap { entry -> VideoDemoCursorSample? in
            guard let time = number(entry["time"]), let x = number(entry["x"]), let y = number(entry["y"]) else { return nil }
            return VideoDemoCursorSample(time: time, x: x, y: y)
        }
        let clicks = (object["clicks"] as? [[String: Any]] ?? []).compactMap { entry -> VideoDemoClickEvent? in
            guard let time = number(entry["time"]), let x = number(entry["x"]), let y = number(entry["y"]) else { return nil }
            let button = VideoDemoClickEvent.Button(rawValue: entry["button"] as? String ?? "left") ?? .left
            return VideoDemoClickEvent(time: time, x: x, y: y, button: button, endTime: number(entry["pressDuration"]).map { time + $0 })
        }
        let keys = (object["keys"] as? [[String: Any]] ?? []).compactMap { entry -> VideoKeystrokeEvent? in
            guard let time = number(entry["time"]), let keys = entry["keys"] as? [String] else { return nil }
            return VideoKeystrokeEvent(time: time, keys: keys)
        }
        return VideoHandoffPointerData(samples: pointer, clicks: clicks, keys: keys)
    }
}

// MARK: - Opening

@MainActor
enum VideoFolderOpener {
    /// A folder, a project, or a video: whichever it is.
    static func open(_ url: URL) {
        if VideoProjectDocument.openableExtensions.contains(url.pathExtension.lowercased()) {
            VideoProjectOpener.open(url)
        } else if VideoFolderReader.isFolder(url) {
            openFolder(url)
        } else if VideoFolderReader.videoExtensions.contains(url.pathExtension.lowercased()) {
            Settings.lastRecordingPath = url.path
            VideoDemoEditorWindowController.open(videoURL: url)
        }
    }

    static func openFolder(_ folder: URL) {
        switch VideoFolderReader.kind(of: folder) {
        case .project(let project):
            VideoProjectOpener.open(project)
        case .handoff:
            Task {
                do {
                    let rebuilt = try await VideoHandoffRebuilder.rebuild(folder)
                    if openUnsaved(rebuilt.contents, folder: folder) {
                        showSummary(rebuilt.summary, folder: folder)
                    }
                } catch {
                    problem(L("Couldn't open “\(folder.lastPathComponent)”"), detail: error.localizedDescription)
                }
            }
        case .other:
            let files = VideoFolderReader.mediaFiles(in: folder)
            guard files.contains(where: { VideoFolderReader.videoExtensions.contains($0.pathExtension.lowercased()) }) else {
                problem(L("There's no video in “\(folder.lastPathComponent)”"), detail: L("Choose a folder with a screen recording in it, as an MP4 or MOV file."))
                return
            }
            Task { await VideoFolderImportWindow.run(folder: folder, files: files) }
        }
    }

    /// Opens a project made from a folder's files. The folder stays as it
    /// is: nothing is written in it (not even the mark that identifies a
    /// recording) until Save writes `<Folder>.lfsp` there.
    @discardableResult
    static func openUnsaved(_ contents: VideoProjectContents, folder: URL) -> Bool {
        VideoFileIdentity.protect(folder)
        let package = folder.appendingPathComponent("\(VideoRecordingFolder.safeName(folder.lastPathComponent)).\(VideoProjectDocument.fileExtension)", isDirectory: true)
        // Saved "long ago": unsaved edits from opening it before are kept.
        let document = VideoProjectDocument(savedAt: .distantPast, mediaMode: .folder, project: contents.project, recording: contents.recording, sourceRecordings: contents.sourceRecordings, folder: .init(kind: .opened))
        let fonts = VideoFolderReader.files(in: folder.appendingPathComponent(VideoProjectDocument.fontsFolder, isDirectory: true), extensions: VideoFonts.fileExtensions)
        let opened = VideoProjectPackage.Opened(document: document, contents: contents, package: package, fontFiles: fonts)
        guard let primary = VideoProjectOpener.prepare(opened) else {
            problem(L("Couldn't open “\(folder.lastPathComponent)”"), detail: L("Its screen recording can't be read."))
            return false
        }
        VideoFontLibrary.shared.reload()
        VideoDemoEditorWindowController.open(videoURL: primary, projectFile: package, mode: .folder, folder: .init(kind: .opened))
        return true
    }

    static func showSummary(_ summary: VideoFolderSummary, folder: URL) {
        let alert = NSAlert()
        alert.messageText = L("Opened “\(folder.lastPathComponent)”")
        var text = L("Loaded:") + "\n" + summary.loaded.map { "• \($0)" }.joined(separator: "\n")
        if !summary.notLoaded.isEmpty {
            text += "\n\n" + L("Not loaded:") + "\n" + summary.notLoaded.map { "• \($0)" }.joined(separator: "\n")
        }
        text += "\n\n" + L("Nothing in the folder changes until you save (⌘S).")
        alert.informativeText = text
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }

    static func problem(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }
}

// MARK: - Import Folder

/// What each file in a folder is, chosen by the user.
struct VideoFolderImportChoice: Identifiable, Equatable {
    enum Role: String, CaseIterable, Identifiable {
        case screen, camera, audio, ignore
        var id: String { rawValue }
        var title: String {
            switch self {
            case .screen: return L("Screen recording")
            case .camera: return L("Camera")
            case .audio: return L("Audio track")
            case .ignore: return L("Ignore")
            }
        }
    }

    var url: URL
    var duration: Double
    var isVideo: Bool
    var role: Role
    /// Camera or audio track: seconds it starts after the screen recording.
    var offset: Double = 0

    var id: String { url.path }

    /// The longest video is the screen; the next one the camera; sound
    /// files are audio tracks; other videos ignored to start with.
    static func suggested(_ files: [(url: URL, duration: Double, isVideo: Bool)]) -> [VideoFolderImportChoice] {
        let videos = files.filter(\.isVideo).sorted { $0.duration > $1.duration }
        let screen = videos.first?.url
        let camera = videos.dropFirst().first?.url
        return files.map { file in
            let role: Role = file.url == screen ? .screen : (file.url == camera ? .camera : (file.isVideo ? .ignore : .audio))
            return VideoFolderImportChoice(url: file.url, duration: file.duration, isVideo: file.isVideo, role: role)
        }
    }

    /// The project these choices make: screens in list order, the first
    /// camera at its offset.
    static func build(_ choices: [VideoFolderImportChoice]) async throws -> VideoProjectContents {
        let screens = choices.filter { $0.role == .screen && $0.isVideo }.map(\.url)
        let camera = choices.first { $0.role == .camera && $0.isVideo }
        var contents = try await VideoFolderProjectBuilder.project(screens: screens, camera: camera?.url, cameraOffset: camera?.offset ?? 0, metadata: nil)
        // Each sound file its own track, on the recording's clock at its offset.
        for choice in choices where choice.role == .audio {
            guard let prepared = try? await VideoExternalAudioImport.prepare(choice.url) else { continue }
            var track = VideoExternalAudioTrack(path: prepared.url.path, name: choice.url.lastPathComponent, duration: prepared.duration, at: 0)
            track.lock(toRecordingOffset: choice.offset)
            contents.project.audioTracks.append(track)
        }
        return contents
    }
}

@MainActor
enum VideoFolderImportWindow {
    static func run(folder: URL, files: [URL]) async {
        var listed: [(url: URL, duration: Double, isVideo: Bool)] = []
        for file in files {
            let duration = (try? await AVURLAsset(url: file).load(.duration).seconds) ?? 0
            listed.append((file, duration.isFinite ? duration : 0, VideoFolderReader.videoExtensions.contains(file.pathExtension.lowercased())))
        }
        let state = VideoFolderImportState(folder: folder, choices: VideoFolderImportChoice.suggested(listed))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L("Import Folder")
        panel.contentView = NSHostingView(rootView: VideoFolderImportView(state: state, folder: folder))
        panel.center()
        state.close = { NSApp.stopModal() }
        NSApp.ensureForegroundCapable()
        LFStudiosEditorActivation.activateApp()
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        guard state.confirmed else { return }
        do {
            let contents = try await VideoFolderImportChoice.build(state.choices)
            VideoFolderOpener.openUnsaved(contents, folder: folder)
        } catch {
            VideoFolderOpener.problem(L("Couldn't open “\(folder.lastPathComponent)”"), detail: error.localizedDescription)
        }
    }
}

@MainActor
final class VideoFolderImportState: ObservableObject {
    let folder: URL
    @Published var choices: [VideoFolderImportChoice]
    var confirmed = false
    var close: () -> Void = {}

    init(folder: URL, choices: [VideoFolderImportChoice]) {
        self.folder = folder
        self.choices = choices
    }

    var hasScreen: Bool { choices.contains { $0.role == .screen && $0.isVideo } }
}

struct VideoFolderImportView: View {
    @ObservedObject var state: VideoFolderImportState
    let folder: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("What is each file in “\(folder.lastPathComponent)”?"))
                .font(.system(size: 14, weight: .semibold))
            Text(L("Choose the screen recording, the camera video if there is one, and the sound files to add as tracks. Nothing in the folder changes until you save."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($state.choices) { $choice in
                        HStack(spacing: 10) {
                            Image(systemName: choice.isVideo ? "film" : "waveform")
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(choice.url.path.replacingOccurrences(of: folder.standardizedFileURL.path + "/", with: ""))
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(VideoEditorModel.format(choice.duration))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if choice.role == .camera || choice.role == .audio {
                                Text(L("Starts after the screen by"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                TextField("", value: $choice.offset, format: .number.precision(.fractionLength(0...2)))
                                    .frame(width: 56)
                                    .textFieldStyle(.roundedBorder)
                                Text(L("s"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Picker("", selection: $choice.role) {
                                ForEach(VideoFolderImportChoice.Role.allCases.filter { choice.isVideo ? $0 != .audio : ($0 == .audio || $0 == .ignore) }) { role in
                                    Text(role.title).tag(role)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            HStack {
                Spacer()
                Button(L("Cancel")) { state.close() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Open")) {
                    state.confirmed = true
                    state.close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.hasScreen)
            }
        }
        .padding(20)
        .frame(width: 620, height: 460)
    }
}
