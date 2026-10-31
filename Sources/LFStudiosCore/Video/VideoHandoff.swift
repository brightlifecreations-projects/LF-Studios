import AVFoundation
import Foundation

// MARK: - Options

/// Creative Handoff: every part of a video project as its own file, in a new
/// folder, for another editor or editing app.
struct VideoHandoffOptions: Codable, Equatable {
    enum Clips: String, Codable, CaseIterable {
        /// The recordings as recorded, uncut.
        case full
        /// Following the edit: cuts, clip order, speed.
        case trimmed
    }

    /// The codec of files that have to be re-encoded.
    enum Quality: String, Codable, CaseIterable {
        case proRes422HQ
        /// "Smaller files".
        case proRes422

        var codec: AVVideoCodecType { self == .proRes422HQ ? .proRes422HQ : .proRes422 }
        var title: String { self == .proRes422HQ ? "ProRes 422 HQ" : "ProRes 422" } // l10n-ignore: codec names
        /// Apple's figures for 1920×1080 at 29.97 fps, in bits per second.
        var bitsPerSecond1080p30: Double { self == .proRes422HQ ? 220_000_000 : 147_000_000 }
    }

    var clips: Clips = .trimmed
    /// Every file starts at the same moment and has the same length.
    var lineUp = true
    var includeFinal = true
    var includeTimeline = true
    var quality: Quality = .proRes422HQ
    /// The speaker notes as Notes.txt. Off: notes are private until chosen.
    var includeSpeakerNotes = false
    /// The untouched recordings (and camera, and song) as well, wherever
    /// the handoff's own files were cut or re-encoded, so its LF Studios
    /// project opens the whole edit again. Off: a handoff that needs them
    /// gets no project, and README.txt says so.
    var includeOriginals = true
    /// Fonts installed on this Mac (Font Book) as well as those added to LF
    /// Studios. Off: a font's license may not allow sharing it.
    var includeInstalledFonts = false

    init(clips: Clips = .trimmed, lineUp: Bool = true, includeFinal: Bool = true, includeTimeline: Bool = true, quality: Quality = .proRes422HQ, includeSpeakerNotes: Bool = false, includeOriginals: Bool = true, includeInstalledFonts: Bool = false) {
        self.clips = clips
        self.lineUp = lineUp
        self.includeFinal = includeFinal
        self.includeTimeline = includeTimeline
        self.quality = quality
        self.includeSpeakerNotes = includeSpeakerNotes
        self.includeOriginals = includeOriginals
        self.includeInstalledFonts = includeInstalledFonts
    }

    private enum CodingKeys: String, CodingKey { case clips, lineUp, includeFinal, includeTimeline, quality, includeSpeakerNotes, includeOriginals, includeInstalledFonts }

    /// Options saved before a field existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VideoHandoffOptions()
        clips = (try? c.decodeIfPresent(Clips.self, forKey: .clips)) ?? d.clips
        lineUp = (try? c.decodeIfPresent(Bool.self, forKey: .lineUp)) ?? d.lineUp
        includeFinal = (try? c.decodeIfPresent(Bool.self, forKey: .includeFinal)) ?? d.includeFinal
        includeTimeline = (try? c.decodeIfPresent(Bool.self, forKey: .includeTimeline)) ?? d.includeTimeline
        quality = (try? c.decodeIfPresent(Quality.self, forKey: .quality)) ?? d.quality
        includeSpeakerNotes = (try? c.decodeIfPresent(Bool.self, forKey: .includeSpeakerNotes)) ?? d.includeSpeakerNotes
        includeOriginals = (try? c.decodeIfPresent(Bool.self, forKey: .includeOriginals)) ?? d.includeOriginals
        includeInstalledFonts = (try? c.decodeIfPresent(Bool.self, forKey: .includeInstalledFonts)) ?? d.includeInstalledFonts
    }

    static let key = "creativeHandoffOptions"
    static let locationKey = "creativeHandoffLocation"

    static func load(_ defaults: UserDefaults = Settings.defaults) -> VideoHandoffOptions {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? VideoHandoffOptions()
    }

    func save(_ defaults: UserDefaults = Settings.defaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    /// The folder chosen last time (found again after a move or rename).
    static func lastLocation(_ defaults: UserDefaults = Settings.defaults) -> URL? {
        guard let data = defaults.data(forKey: locationKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func remember(location url: URL, _ defaults: UserDefaults = Settings.defaults) {
        defaults.set(try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), forKey: locationKey)
    }
}

// MARK: - What goes in

/// One recording of the project, as found on disk.
struct VideoHandoffRecording: Equatable {
    struct Camera: Equatable {
        /// nil: the file is missing.
        var url: URL?
        var name: String
        /// Camera time = recording time − offset.
        var offset: Double
        var duration: Double
        var size: CGSize
        var frameRate: Double
        /// Its background is removed in the video: the person alone, with
        /// transparency around them.
        var cutout: Bool
    }

    var id: UUID
    /// nil: the file is missing.
    var url: URL?
    var name: String
    /// Where it starts on the recordings' shared time axis.
    var offset: Double
    var duration: Double
    var size: CGSize
    var frameRate: Double
    var audioKinds: [VideoAudioKind]
    var camera: Camera?
    var metadata: VideoDemoRecordingMetadata?

    var end: Double { offset + duration }
}

/// Everything a handoff is made from.
struct VideoHandoffInput {
    var name: String
    var project: VideoDemoProject
    var recordings: [VideoHandoffRecording]
    var exportSettings: VideoExportSettings
    /// The project's own recording data (for the finished video).
    var recording: VideoDemoRecordingMetadata?

    var segments: [VideoDemoTimelineSegment] {
        project.timelineSegments(totalDuration: axisDuration)
    }
    var axisDuration: Double { recordings.map(\.end).max() ?? 0 }
    var timelineDuration: Double { project.outputDuration(segments: segments) }
    var frameRate: Double { recordings.first?.frameRate ?? 30 }
    /// Split screen: its layout in pixels (nil: not split).
    var split: VideoHandoffSplit? {
        VideoHandoffSplit.make(project: project, recordingSize: recordings.first?.size ?? .zero)
    }
    /// The timeline files' frame: the recording's, or a split video's whole.
    var sequenceSize: CGSize { split?.video ?? recordings.first?.size ?? CGSize(width: 1920, height: 1080) }
}

extension VideoHandoffInput {
    /// The project's recordings and camera footage, looked up on disk.
    static func gather(name: String, project: VideoDemoProject, recording: VideoDemoRecordingMetadata?, appendedMetadata: [UUID: VideoDemoRecordingMetadata], exportSettings: VideoExportSettings) async -> VideoHandoffInput {
        let cutout = project.webcam.visible && (project.webcam.shape == .cutout || project.webcam.backdrop == .remove)
        var sources = project.sources
        if sources.isEmpty {
            sources = [VideoProjectSource(isPrimary: true, path: project.sourcePath, name: project.sourceURL.lastPathComponent, duration: 0, width: project.sourceWidth, height: project.sourceHeight, offset: 0, audioKinds: recording?.audioTracks ?? [], hasPointer: false, pointPixelScale: nil, webcam: recording?.webcam)]
        }
        var recordings: [VideoHandoffRecording] = []
        for source in sources {
            let url = source.isPrimary ? (FileManager.default.fileExists(atPath: project.sourcePath) ? project.sourceURL : nil) : VideoSourceLocator.resolve(source)
            var tracks: VideoSourceTracks?
            if let url { tracks = try? await VideoSourceTracks.load(url: url) }
            let metadata = source.isPrimary ? recording : appendedMetadata[source.id]
            let kinds = VideoAudioKind.resolve(recorded: source.isPrimary ? recording?.audioTracks : (source.audioKinds.isEmpty ? nil : source.audioKinds), channelCounts: tracks?.audioChannelCounts ?? [])
            // The primary recording's camera: added footage first, else the recorded one.
            let webcam = source.isPrimary ? project.activeCamera(recorded: recording?.webcam) : source.webcam
            var camera: VideoHandoffRecording.Camera?
            if let webcam {
                let found: URL? = source.isPrimary ? (project.importedCamera.flatMap { $0.resolved() } ?? (FileManager.default.fileExists(atPath: webcam.path) ? webcam.url : nil)) : (FileManager.default.fileExists(atPath: webcam.path) ? webcam.url : nil)
                var cameraSource: VideoCameraSource?
                if let found { cameraSource = await VideoCameraSource.load(VideoWebcamRecording(path: found.path, offset: webcam.offset, width: webcam.width, height: webcam.height)) }
                let frameRate = (try? await cameraSource?.track.load(.nominalFrameRate)).map(Double.init) ?? 30
                camera = .init(url: cameraSource == nil ? nil : found, name: webcam.url.lastPathComponent, offset: webcam.offset, duration: cameraSource?.duration ?? 0, size: cameraSource?.size ?? CGSize(width: webcam.width, height: webcam.height), frameRate: frameRate > 0 ? frameRate : 30, cutout: cutout)
            }
            recordings.append(VideoHandoffRecording(
                id: source.id,
                url: tracks == nil ? nil : url,
                name: source.name,
                offset: source.offset,
                duration: tracks?.duration ?? source.duration,
                size: tracks?.size ?? CGSize(width: source.width, height: source.height),
                frameRate: tracks?.frameRate ?? 30,
                audioKinds: kinds,
                camera: camera,
                metadata: metadata
            ))
        }
        // This Mac's cleaned-up voices and face tracking, named so they go along.
        let primaryKinds = zip(sources, recordings).first { $0.0.isPrimary }?.1.audioKinds ?? []
        let carried = VideoProjectCaches.carrying(project, recordedCamera: recording?.webcam, primaryKinds: primaryKinds)
        return VideoHandoffInput(name: name, project: carried, recordings: recordings, exportSettings: exportSettings, recording: recording)
    }
}

// MARK: - The plan

// Descriptions are English, like the file names: they go into README.txt,
// which travels to other people and editing apps. // l10n-ignore

/// A stretch of a source file placed on the output file's clock.
struct VideoHandoffPiece: Equatable {
    var url: URL
    /// The source's audio track for audio pieces (nil: its video).
    var audioTrack: Int?
    /// Seconds in the source file.
    var sourceStart: Double
    var sourceDuration: Double
    /// Where it starts in the output file.
    var at: Double
    var speed: Double = 1
    /// For music: its level and fades.
    var gain: Double = 1
    var fadeIn: Double = 0
    var fadeOut: Double = 0

    var outputDuration: Double { sourceDuration / max(speed, 0.0001) }
    var end: Double { at + outputDuration }
}

struct VideoHandoffItem: Equatable, Identifiable {
    enum Folder: String, CaseIterable {
        case screen = "01 Screen"
        case camera = "02 Camera"
        case audio = "03 Audio"
        case graphics = "04 Graphics"
        case captions = "05 Captions"
        case final = "06 Final"
        case data = "07 Data"
        case fonts = "Fonts"
        case root = ""
    }

    enum Work: Equatable {
        /// Copied as it is.
        case copy(URL)
        /// Video stretches put together without re-encoding (a .mov whose
        /// edit list places them; `duration` long).
        case passthrough([VideoHandoffPiece], duration: Double)
        /// Video re-encoded to ProRes (cut, sped up, padded with black, or
        /// the cut-out person over transparency).
        case reencode([VideoHandoffPiece], duration: Double, codec: AVVideoCodecType, alpha: Bool, size: CGSize, frameRate: Double)
        /// Sound decoded to WAV (or AAC for music), laid out on the clock.
        case audio([VideoHandoffPiece], duration: Double, channels: Int, aac: Bool)
        case text(String)
        case finalVideo
        /// The edit's whole sound as the finished video has it.
        case fullMix(duration: Double)
        /// The LF Studios project: the whole edit, pointing at the handoff's
        /// own files (original path → path in the handoff).
        case project([String: String])
    }

    /// How README.txt describes the file.
    enum Treatment: Equatable {
        case original
        case originalWithEditList
        case proRes(String)
        case audio(String)
        case written
        case finished

        var readme: String {
            switch self {
            case .original: return "untouched original"
            case .originalWithEditList: return "original frames, not re-encoded (placed with a QuickTime edit list)"
            case .proRes(let codec): return "re-encoded to \(codec)"
            case .audio(let format): return format
            case .written: return "written by LF Studios"
            case .finished: return "the finished video, exported with your export settings"
            }
        }
    }

    var folder: Folder
    var fileName: String
    var description: String
    var work: Work
    var treatment: Treatment
    var duration: Double?
    var frameRate: Double?
    /// Where it starts on the handoff's clock (the edit, or the recordings).
    var startOffset: Double?
    var estimatedBytes: Int64
    /// The recording a screen or camera file comes from.
    var recording: UUID? = nil

    var id: String { relativePath }
    var relativePath: String { folder == .root ? fileName : "\(folder.rawValue)/\(fileName)" }
}

struct VideoHandoffPlan: Equatable {
    var folderName: String
    var items: [VideoHandoffItem]
    /// Parts that couldn't come along (a moved camera video…).
    var skipped: [String]
    /// The clock every lined-up file follows.
    var clockDuration: Double
    var options: VideoHandoffOptions

    var estimatedBytes: Int64 { items.reduce(0) { $0 + $1.estimatedBytes } }
    /// The originals added only so the project reopens (the dialog shows it).
    var originalsBytes: Int64 { items.filter { $0.fileName.hasPrefix(VideoHandoffPlanner.originalsFolder + "/") }.reduce(0) { $0 + $1.estimatedBytes } }
    var includesProject: Bool { items.contains { if case .project = $0.work { return true } else { return false } } }
    var reencodes: Bool { items.contains { if case .reencode = $0.work { return true } else { return false } } }
}

enum VideoHandoffPlanner {
    /// Untouched originals the project needs, inside 01 Screen, 02 Camera, 03 Audio.
    static let originalsFolder = "Originals"

    /// "<Project> – Handoff 2026-10-27", with " 2", " 3"… when it's taken.
    static func folderName(project: String, date: Date = Date(), existing: (String) -> Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let clean = project.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        let base = "\(clean.isEmpty ? "Project" : clean) – Handoff \(formatter.string(from: date))" // l10n-ignore: a folder name
        if !existing(base) { return base }
        var number = 2
        while existing("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    static func plan(_ input: VideoHandoffInput, options: VideoHandoffOptions, folderName: String) -> VideoHandoffPlan {
        var items: [VideoHandoffItem] = []
        var skipped: [String] = []
        let trimmed = options.clips == .trimmed
        let segments = input.segments
        let clock = trimmed ? input.timelineDuration : input.axisDuration
        let fps = input.frameRate

        for recording in input.recordings where recording.url == nil {
            skipped.append(L("Screen recording “\(recording.name)” — the file is missing"))
        }
        for camera in input.recordings.compactMap(\.camera) where camera.url == nil {
            skipped.append(L("Camera video “\(camera.name)” — the file is missing"))
        }

        // 01 Screen
        if trimmed {
            for (index, segment) in segments.enumerated() {
                let pieces = screenPieces(segment, recordings: input.recordings)
                for (part, piece) in pieces.enumerated() {
                    let recording = input.recordings.first { $0.url == piece.url }
                    let name = pieces.count > 1 ? String(format: "Clip %02d-%d.mov", index + 1, part + 1) : String(format: "Clip %02d.mov", index + 1) // l10n-ignore: file names
                    var placed = piece
                    let length = options.lineUp ? clock : piece.outputDuration
                    if !options.lineUp { placed.at = 0 }
                    let size = recording?.size ?? CGSize(width: 1920, height: 1080)
                    let rate = recording?.frameRate ?? fps
                    items.append(VideoHandoffItem(
                        folder: .screen, fileName: name,
                        description: "Clip \(index + 1) of the edit, from “\(recording?.name ?? "")”",
                        work: .reencode([placed], duration: length, codec: options.quality.codec, alpha: false, size: size, frameRate: rate),
                        treatment: .proRes(options.quality.title), duration: length, frameRate: rate,
                        startOffset: options.lineUp ? 0 : piece.at,
                        estimatedBytes: proResBytes(size: size, frameRate: rate, content: piece.outputDuration, padding: length - piece.outputDuration, quality: options.quality, alpha: false)
                    ))
                }
            }
        } else {
            for recording in input.recordings {
                guard let url = recording.url else { continue }
                let bytes = fileSize(url)
                if options.lineUp && (recording.offset > 0.0005 || recording.end < clock - 0.0005) {
                    items.append(VideoHandoffItem(
                        folder: .screen, fileName: movName(recording.name),
                        description: "Screen recording “\(recording.name)”, uncut",
                        work: .passthrough([VideoHandoffPiece(url: url, sourceStart: 0, sourceDuration: recording.duration, at: recording.offset)], duration: clock),
                        treatment: .originalWithEditList, duration: clock, frameRate: recording.frameRate, startOffset: 0, estimatedBytes: bytes, recording: recording.id
                    ))
                } else {
                    items.append(VideoHandoffItem(
                        folder: .screen, fileName: url.lastPathComponent,
                        description: "Screen recording “\(recording.name)”, uncut",
                        work: .copy(url), treatment: .original, duration: recording.duration, frameRate: recording.frameRate, startOffset: recording.offset, estimatedBytes: bytes, recording: recording.id
                    ))
                }
            }
        }

        // 02 Camera
        let cameras = input.recordings.filter { $0.camera?.url != nil }
        for (index, recording) in cameras.enumerated() {
            guard let camera = recording.camera, let url = camera.url else { continue }
            let base = cameras.count > 1 ? "Camera \(index + 1)" : "Camera" // l10n-ignore: a file name
            let pieces = cameraPieces(recording, camera: camera, url: url, segments: trimmed ? segments : nil)
            guard !pieces.isEmpty else {
                skipped.append(L("Camera video “\(camera.name)” — none of it is in the edit"))
                continue
            }
            let first = pieces.map(\.at).min() ?? 0
            let last = pieces.map(\.end).max() ?? 0
            let length = options.lineUp ? clock : last - first
            let placed = options.lineUp ? pieces : pieces.map { var piece = $0; piece.at -= first; return piece }
            let content = pieces.reduce(0) { $0 + $1.outputDuration }
            let description = camera.cutout
                ? "The camera, its background removed: the person over transparency"
                : (trimmed ? "The camera, cut like the edit" : "The camera video, uncut")
            if camera.cutout || trimmed {
                let codec: AVVideoCodecType = camera.cutout ? .proRes4444 : options.quality.codec
                items.append(VideoHandoffItem(
                    folder: .camera, fileName: "\(base).mov", description: description,
                    work: .reencode(placed, duration: length, codec: codec, alpha: camera.cutout, size: camera.size, frameRate: camera.frameRate),
                    treatment: .proRes(camera.cutout ? "ProRes 4444 with transparency" : options.quality.title), // l10n-ignore: codec names
                    duration: length, frameRate: camera.frameRate, startOffset: options.lineUp ? 0 : first,
                    estimatedBytes: proResBytes(size: camera.size, frameRate: camera.frameRate, content: content, padding: length - content, quality: options.quality, alpha: camera.cutout),
                    recording: recording.id
                ))
            } else if options.lineUp && (abs(first) > 0.0005 || last < clock - 0.0005 || pieces.first?.sourceStart ?? 0 > 0.0005) {
                items.append(VideoHandoffItem(
                    folder: .camera, fileName: "\(base).mov", description: description,
                    work: .passthrough(placed, duration: length), treatment: .originalWithEditList,
                    duration: length, frameRate: camera.frameRate, startOffset: 0, estimatedBytes: fileSize(url), recording: recording.id
                ))
            } else {
                items.append(VideoHandoffItem(
                    folder: .camera, fileName: "\(base).\(url.pathExtension.lowercased())", description: description,
                    work: .copy(url), treatment: .original, duration: camera.duration, frameRate: camera.frameRate,
                    startOffset: first, estimatedBytes: fileSize(url), recording: recording.id
                ))
            }
        }

        // 03 Audio
        for kind in [VideoAudioKind.microphone, .system, .mixed] {
            let pieces = audioPieces(kind, recordings: input.recordings, segments: trimmed ? segments : nil)
            guard !pieces.isEmpty else { continue }
            let first = pieces.map(\.at).min() ?? 0
            let last = pieces.map(\.end).max() ?? 0
            let length = options.lineUp ? clock : last - first
            let placed = options.lineUp ? pieces : pieces.map { var piece = $0; piece.at -= first; return piece }
            let name: String
            let description: String
            switch kind {
            case .microphone: name = "Microphone.wav"; description = "Your microphone"
            case .system: name = "System Audio.wav"; description = "Sound playing on the Mac"
            case .mixed: name = "Audio (mixed).wav"; description = "The recording's sound — microphone and Mac sound in one track"
            }
            let channels = kind == .microphone ? 1 : 2
            items.append(VideoHandoffItem(
                folder: .audio, fileName: name, description: description,
                work: .audio(placed, duration: length, channels: channels, aac: false),
                treatment: .audio("WAV, 48 kHz, 24-bit (decoded, no quality lost)"), // l10n-ignore: technical
                duration: length, frameRate: nil, startOffset: options.lineUp ? 0 : first,
                estimatedBytes: Int64(length * 48_000 * 3 * Double(channels))
            ))
        }
        // Everything you hear, mixed as the edit plays it.
        let hasSound = input.recordings.contains { $0.url != nil && !$0.audioKinds.isEmpty } || input.project.music != nil || !input.project.audioTracks.isEmpty
        if hasSound {
            let length = input.timelineDuration
            items.append(VideoHandoffItem(
                folder: .audio, fileName: "Full Mix.wav",
                description: trimmed || !options.lineUp
                    ? "Everything you hear, mixed exactly as the edit plays it: voice, the Mac's sound, and the music dipping under the voice"
                    : "Everything you hear, mixed exactly as the edit plays it: voice, the Mac's sound, and the music dipping under the voice (on the edit's clock, like the finished video)",
                work: .fullMix(duration: length),
                treatment: .audio("WAV, 48 kHz, 24-bit, the finished video's own mix and loudness"), // l10n-ignore: technical
                duration: length, frameRate: nil, startOffset: 0,
                estimatedBytes: Int64(length * 48_000 * 3 * 2)
            ))
        }
        if let music = input.project.music {
            let url = URL(fileURLWithPath: music.path)
            if !FileManager.default.fileExists(atPath: music.path) {
                skipped.append(L("Music “\(music.name)” — the file is missing"))
            } else if trimmed {
                let layout = VideoMusicLayout.pieces(music: music, timelineDuration: input.timelineDuration)
                let pieces = layout.enumerated().map { index, piece in
                    VideoHandoffPiece(url: url, sourceStart: piece.fileStart, sourceDuration: piece.length, at: piece.start, gain: music.volume,
                                      fadeIn: index == 0 ? music.fadeIn : 0, fadeOut: index == layout.count - 1 ? music.fadeOut : 0)
                }
                let length = options.lineUp ? clock : (pieces.map(\.end).max() ?? 0)
                items.append(VideoHandoffItem(
                    folder: .audio, fileName: "Music.m4a", description: "The music as laid out in the edit (its level and fades, without dipping under your voice)",
                    work: .audio(pieces, duration: length, channels: 2, aac: true), treatment: .audio("AAC 256 kbps (re-encoded to lay it out)"), // l10n-ignore: technical
                    duration: length, frameRate: nil, startOffset: 0, estimatedBytes: Int64(length * 32_000)
                ))
            } else {
                items.append(VideoHandoffItem(
                    folder: .audio, fileName: "Music.\(url.pathExtension.lowercased())", description: "The music file, as it was added (in the edit it starts at the beginning of the video)",
                    work: .copy(url), treatment: .original, duration: music.duration, frameRate: nil, startOffset: nil, estimatedBytes: fileSize(url)
                ))
            }
        }

        // Added sound files: laid out like the edit (trimmed), or as added.
        var audioNames: Set<String> = Set(items.filter { $0.folder == .audio }.map(\.fileName))
        for track in input.project.audioTracks {
            guard FileManager.default.fileExists(atPath: track.path) else {
                skipped.append(L("Added sound “\(track.name)” — the file is missing"))
                continue
            }
            let base = URL(fileURLWithPath: track.name).deletingPathExtension().lastPathComponent
            if trimmed {
                let placed = track.placed(segments: segments, timelineDuration: input.timelineDuration)
                guard !track.muted, !placed.isEmpty else { continue }
                let pieces = placed.map { piece in
                    VideoHandoffPiece(url: track.url, audioTrack: 0, sourceStart: piece.fileStart, sourceDuration: piece.fileLength, at: piece.timelineStart,
                                      speed: piece.speed, gain: track.volume, fadeIn: track.fadeIn, fadeOut: track.fadeOut)
                }
                let first = pieces.map(\.at).min() ?? 0
                let last = pieces.map(\.end).max() ?? 0
                let length = options.lineUp ? clock : last - first
                let laid = options.lineUp ? pieces : pieces.map { var piece = $0; piece.at -= first; return piece }
                items.append(VideoHandoffItem(
                    folder: .audio, fileName: unique("\(base).wav", in: &audioNames),
                    description: "Added sound “\(track.name)”, laid out like the edit, with its level and fades",
                    work: .audio(laid, duration: length, channels: 2, aac: false),
                    treatment: .audio("WAV, 48 kHz, 24-bit (decoded, no quality lost)"), // l10n-ignore: technical
                    duration: length, frameRate: nil, startOffset: options.lineUp ? 0 : first,
                    estimatedBytes: Int64(length * 48_000 * 3 * 2)
                ))
            } else {
                items.append(VideoHandoffItem(
                    folder: .audio, fileName: unique(track.url.lastPathComponent, in: &audioNames),
                    description: track.lockedToRecording ? "Added sound “\(track.name)”, as it was added (synced to the recording)" : "Added sound “\(track.name)”, as it was added (placed on the edit's timeline)",
                    work: .copy(track.url), treatment: .original, duration: track.duration, frameRate: nil,
                    startOffset: track.lockedToRecording ? track.pieces.first.map { $0.at - $0.fileStart } : nil, estimatedBytes: fileSize(track.url)
                ))
            }
        }

        // 04 Graphics
        var graphicNames = Set<String>()
        func addGraphic(_ path: String, _ description: String) {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                skipped.append(L("Picture “\(url.lastPathComponent)” — the file is missing"))
                return
            }
            let name = unique(url.lastPathComponent, in: &graphicNames)
            items.append(VideoHandoffItem(folder: .graphics, fileName: name, description: description, work: .copy(url), treatment: .original, duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: fileSize(url)))
        }
        for overlay in input.project.overlayEffects {
            guard let image = overlay.image else { continue }
            let at = trimmed ? VideoDemoProject.timelineTimeIfIncluded(sourceTime: overlay.time, segments: segments) : overlay.time
            addGraphic(image.path, at.map { "Picture on screen from \(VideoHandoffReadme.clock($0))" } ?? "Picture (its moment was cut from the edit)")
        }
        if case .image(let path) = input.project.background {
            addGraphic(path, "The background picture")
        }
        if case .systemWallpaper(let path) = input.project.background {
            addGraphic(path, "The background picture (a macOS wallpaper)")
        }
        if input.project.cursor.style == .custom, let cursor = input.project.cursor.customImage {
            addGraphic(cursor.path, "The pointer's own picture")
        }

        // 05 Captions
        if !input.project.captions.isEmpty {
            let captionSegments = trimmed ? segments : [identitySegment(input.axisDuration)]
            items.append(VideoHandoffItem(folder: .captions, fileName: "Captions.srt", description: "Captions",
                                          work: .text(VideoCaptionBuilder.srt(lines: input.project.captions, segments: captionSegments)),
                                          treatment: .written, duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: 10_000))
            for translation in input.project.captionTracks.translations {
                let lines = Dictionary(translation.lines.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
                items.append(VideoHandoffItem(folder: .captions, fileName: "Captions.\(translation.language).srt", description: "Captions, translated (\(translation.language))",
                                              work: .text(VideoCaptionBuilder.srt(lines: input.project.captions, segments: captionSegments, translation: lines)),
                                              treatment: .written, duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: 10_000))
            }
        }

        // 06 Final
        if options.includeFinal {
            let canvas = input.exportSettings.outputSize(canvas: input.project.canvasSize())
            items.append(VideoHandoffItem(folder: .final, fileName: "\(input.name).\(input.exportSettings.fileExtension)", description: "The finished video",
                                          work: .finalVideo, treatment: .finished, duration: input.timelineDuration, frameRate: Double(input.exportSettings.fps),
                                          startOffset: 0, estimatedBytes: input.exportSettings.estimatedBytes(duration: input.timelineDuration, canvas: canvas, hasAudio: true)))
        }

        // 07 Data
        if let data = pointerData(input, trimmed: trimmed, segments: segments) {
            items.append(VideoHandoffItem(folder: .data, fileName: "Pointer, clicks and keys.json", description: "Pointer path, clicks, and keyboard shortcuts, with recording and edit times",
                                          work: .text(data), treatment: .written, duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: Int64(data.utf8.count)))
        }

        // The cleaned-up voices and the face tracking the LF Studios project
        // plays, so it sounds and looks the same on another Mac.
        let preferred = VideoProjectContents(project: input.project, recording: input.recording, sourceRecordings: [:]).preferredNames
        for voice in input.project.carriedVoices where FileManager.default.fileExists(atPath: voice.path) {
            let url = URL(fileURLWithPath: voice.path)
            items.append(VideoHandoffItem(folder: .audio, fileName: unique(preferred[voice.path] ?? url.lastPathComponent, in: &audioNames),
                                          description: "The cleaned-up voice (Enhance voice), as LF Studios plays it, unaligned",
                                          work: .copy(url), treatment: .original, duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: fileSize(url)))
        }
        if let path = input.project.faceTracking?.analysisPath, FileManager.default.fileExists(atPath: path) {
            items.append(VideoHandoffItem(folder: .data, fileName: "Face tracking.json", description: "Where the face is in the camera video (Keep face centered), for the LF Studios project",
                                          work: .copy(URL(fileURLWithPath: path)), treatment: .original, duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: fileSize(URL(fileURLWithPath: path))))
        }

        // Fonts
        var fontNames = Set<String>()
        let families = VideoProjectDocument.fontFamilies(of: input.project)
        for family in VideoFonts.installedFamiliesLeftOut(families, includeInstalled: options.includeInstalledFonts) {
            skipped.append(L("Font “\(family)” — installed on this Mac, so it's left out: turn on Include fonts installed on this Mac (check the font's license allows sharing it). Without it, another Mac shows a stand-in font."))
        }
        for family in families {
            for file in VideoFonts.carriedFontFiles(forFamily: family, includeInstalled: options.includeInstalledFonts) {
                items.append(VideoHandoffItem(folder: .fonts, fileName: unique(file.lastPathComponent, in: &fontNames), description: "Font “\(family)”",
                                              work: .copy(file), treatment: .original, duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: fileSize(file)))
            }
        }

        var plan = VideoHandoffPlan(folderName: folderName, items: items, skipped: skipped, clockDuration: clock, options: options)
        addProject(to: &plan, input: input, options: options)
        if options.includeTimeline {
            plan.items.append(VideoHandoffItem(folder: .root, fileName: "Timeline.fcpxml", description: "The timeline for Final Cut Pro and DaVinci Resolve",
                                               work: .text(""), treatment: .written, duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: 50_000))
            plan.items.append(VideoHandoffItem(folder: .root, fileName: "Timeline (Premiere).xml", description: "The timeline for Adobe Premiere Pro (File ▸ Import)",
                                               work: .text(""), treatment: .written, duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: 50_000))
        }
        plan.items.append(VideoHandoffItem(folder: .root, fileName: "README.txt", description: "This list", work: .text(""), treatment: .written,
                                           duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: 10_000))
        return plan
    }

    // MARK: The LF Studios project

    /// `<Project>.lfs`, holding the whole edit and pointing at the
    /// handoff's own untouched copies. Files the handoff cut or re-encoded
    /// (clips, a lined-up camera, the laid-out song) can't carry the edit:
    /// their originals come along in Originals/, or — with that off — there's
    /// no project, and the reason is listed.
    static func addProject(to plan: inout VideoHandoffPlan, input: VideoHandoffInput, options: VideoHandoffOptions) {
        var mapping: [String: String] = [:]
        for item in plan.items {
            if case .copy(let url) = item.work { mapping[url.standardizedFileURL.path] = item.relativePath }
        }
        var needed: [(url: URL, folder: VideoHandoffItem.Folder, what: String)] = []
        for recording in input.recordings {
            if let url = recording.url, mapping[url.standardizedFileURL.path] == nil {
                needed.append((url, .screen, "The original screen recording “\(recording.name)”, for the LF Studios project"))
            }
            if let camera = recording.camera, let url = camera.url, mapping[url.standardizedFileURL.path] == nil {
                needed.append((url, .camera, "The original camera video, for the LF Studios project"))
            }
        }
        if let music = input.project.music, FileManager.default.fileExists(atPath: music.path), mapping[URL(fileURLWithPath: music.path).standardizedFileURL.path] == nil {
            needed.append((URL(fileURLWithPath: music.path), .audio, "The original song, for the LF Studios project"))
        }
        for track in input.project.audioTracks where FileManager.default.fileExists(atPath: track.path) && mapping[track.url.standardizedFileURL.path] == nil {
            needed.append((track.url, .audio, "The added sound “\(track.name)” as it was added, for the LF Studios project"))
        }
        var seen = Set<String>()
        needed = needed.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
        if !needed.isEmpty && !options.includeOriginals {
            plan.skipped.append(L("The LF Studios project — it needs the original files: turn on Include originals so it reopens in LF Studios"))
            return
        }
        for original in needed {
            var name = original.url.lastPathComponent
            var number = 2
            while plan.items.contains(where: { $0.folder == original.folder && $0.fileName == "\(originalsFolder)/\(name)" }) {
                name = "\(original.url.deletingPathExtension().lastPathComponent) \(number).\(original.url.pathExtension)"
                number += 1
            }
            let item = VideoHandoffItem(folder: original.folder, fileName: "\(originalsFolder)/\(name)", description: original.what,
                                        work: .copy(original.url), treatment: .original, duration: nil, frameRate: nil, startOffset: nil,
                                        estimatedBytes: fileSize(original.url))
            plan.items.append(item)
            mapping[original.url.standardizedFileURL.path] = item.relativePath
        }
        plan.items.append(VideoHandoffItem(folder: .root, fileName: "\(VideoRecordingFolder.safeName(input.name)).\(VideoProjectDocument.fileExtension)",
                                           description: "The LF Studios project: open it, or this whole folder, in LF Studios (\(VideoProjectDocument.firstVersionOpeningFileExtension) or later) to edit the video again",
                                           work: .project(mapping), treatment: .written, duration: nil, frameRate: nil, startOffset: nil, estimatedBytes: 500_000))
    }

    // MARK: Alignment

    /// The recordings' stretches a clip plays, placed where the edit plays them.
    static func screenPieces(_ segment: VideoDemoTimelineSegment, recordings: [VideoHandoffRecording]) -> [VideoHandoffPiece] {
        let clip = segment.clip
        let speed = clip.normalizedSpeed
        return recordings.compactMap { recording in
            guard let url = recording.url else { return nil }
            let a = max(clip.sourceStart, recording.offset), b = min(clip.sourceEnd, recording.end)
            guard b - a > 0.0005 else { return nil }
            return VideoHandoffPiece(url: url, sourceStart: a - recording.offset, sourceDuration: b - a, at: segment.timelineStart + (a - clip.sourceStart) / speed, speed: speed)
        }
    }

    /// The camera, cut like the edit (segments), or whole on the recordings'
    /// axis (nil): camera time = recording time − offset, limited to what the
    /// camera has.
    static func cameraPieces(_ recording: VideoHandoffRecording, camera: VideoHandoffRecording.Camera, url: URL, segments: [VideoDemoTimelineSegment]?) -> [VideoHandoffPiece] {
        guard let segments else {
            // Uncut: it starts `offset` after the recording (cut at the front
            // when it started before the axis does).
            let at = recording.offset + camera.offset
            let skip = max(-at, 0)
            let length = camera.duration - skip
            return length > 0.0005 ? [VideoHandoffPiece(url: url, sourceStart: skip, sourceDuration: length, at: at + skip)] : []
        }
        return segments.compactMap { segment in
            let clip = segment.clip
            let speed = clip.normalizedSpeed
            // Recording stretch in this clip, then the camera's part of it.
            let a = max(clip.sourceStart, recording.offset), b = min(clip.sourceEnd, recording.end)
            let cameraStart = max(a - recording.offset - camera.offset, 0)
            let cameraEnd = min(b - recording.offset - camera.offset, camera.duration)
            guard cameraEnd - cameraStart > 0.0005 else { return nil }
            let axisStart = cameraStart + recording.offset + camera.offset
            return VideoHandoffPiece(url: url, sourceStart: cameraStart, sourceDuration: cameraEnd - cameraStart, at: segment.timelineStart + (axisStart - clip.sourceStart) / speed, speed: speed)
        }
    }

    /// One kind of sound from every recording that has it, laid out like
    /// the screen (muted clips stay silent).
    static func audioPieces(_ kind: VideoAudioKind, recordings: [VideoHandoffRecording], segments: [VideoDemoTimelineSegment]?) -> [VideoHandoffPiece] {
        var pieces: [VideoHandoffPiece] = []
        for recording in recordings {
            guard let url = recording.url, let track = recording.audioKinds.firstIndex(of: kind) else { continue }
            if let segments {
                for segment in segments where !segment.clip.muted {
                    for var piece in screenPieces(segment, recordings: [recording]) {
                        piece.audioTrack = track
                        pieces.append(piece)
                    }
                }
            } else {
                pieces.append(VideoHandoffPiece(url: url, audioTrack: track, sourceStart: 0, sourceDuration: recording.duration, at: recording.offset))
            }
        }
        return pieces.sorted { $0.at < $1.at }
    }

    /// All of the recordings' axis at normal speed (captions and data on the
    /// recordings' own clock).
    static func identitySegment(_ duration: Double) -> VideoDemoTimelineSegment {
        VideoDemoTimelineSegment(clip: VideoDemoTimelineClip(sourceStart: 0, sourceEnd: max(duration, 0.1)), timelineStart: 0)
    }

    // MARK: Helpers

    static func movName(_ name: String) -> String {
        (name as NSString).deletingPathExtension + ".mov"
    }

    static func unique(_ name: String, in taken: inout Set<String>) -> String {
        var candidate = name
        var number = 2
        while taken.contains(candidate.lowercased()) {
            let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            number += 1
        }
        taken.insert(candidate.lowercased())
        return candidate
    }

    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// ProRes at the size and rate of the video; black padding compresses
    /// to a small part of that.
    static func proResBytes(size: CGSize, frameRate: Double, content: Double, padding: Double, quality: VideoHandoffOptions.Quality, alpha: Bool) -> Int64 {
        let pixels = Double(max(size.width * size.height, 1)) / (1920 * 1080)
        let rate = max(frameRate, 1) / 29.97
        let bits = (alpha ? 330_000_000 : quality.bitsPerSecond1080p30) * pixels * rate
        return Int64(bits / 8 * (max(content, 0) + 0.1 * max(padding, 0)))
    }

    /// The pointer path, clicks, and keys, with recording times (and edit
    /// times when they're in the edit).
    static func pointerData(_ input: VideoHandoffInput, trimmed: Bool, segments: [VideoDemoTimelineSegment]) -> String? {
        let project = input.project
        guard !project.cursorSamples.isEmpty || !project.clickEvents.isEmpty || !project.keystrokes.isEmpty else { return nil }
        func edit(_ time: Double) -> Double? {
            trimmed ? VideoDemoProject.timelineTimeIfIncluded(sourceTime: time, segments: segments).map { (($0 * 1000).rounded()) / 1000 } : time
        }
        struct Sample: Encodable { let time: Double; let editTime: Double?; let x: Double; let y: Double }
        struct Click: Encodable { let time: Double; let editTime: Double?; let x: Double; let y: Double; let button: String; let pressDuration: Double }
        struct Key: Encodable { let time: Double; let editTime: Double?; let keys: [String] }
        struct File: Encodable {
            let about: String
            let duration: Double
            let pointer: [Sample]
            let clicks: [Click]
            let keys: [Key]
        }
        let file = File(
            about: "Times in seconds: `time` on the recordings, `editTime` in the edit (null when that moment was cut). x and y are fractions of the recording's frame, y down.", // l10n-ignore: technical documentation
            duration: trimmed ? input.timelineDuration : input.axisDuration,
            pointer: project.cursorSamples.map { Sample(time: $0.time, editTime: edit($0.time), x: $0.x, y: $0.y) },
            clicks: project.clickEvents.map { Click(time: $0.time, editTime: edit($0.time), x: $0.x, y: $0.y, button: $0.button.rawValue, pressDuration: $0.pressDuration) },
            keys: project.keystrokes.map { Key(time: $0.time, editTime: edit($0.time), keys: $0.keys) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(file)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
