import AppKit
import AVFoundation
import UniformTypeIdentifiers

// Sound files added to a video (Audio panel ▸ Add audio…, or dropped on the
// timeline): each is a track of its own, in pieces (split it, trim either
// end, move it, delete a piece). A track sits freely on the edit's timeline
// (a voiceover recorded to the edit), or — once synced by sound — on the
// recording's clock, where it follows the cuts and speed changes like the
// recording's own sound (a separate microphone). "Use as my voice" puts it
// in place of the recording's microphone; "Dip under voice" lowers it while
// the voice speaks (off to start with).

struct VideoExternalAudioTrack: Codable, Equatable, Identifiable {
    struct Piece: Codable, Equatable, Identifiable {
        var id = UUID()
        /// Seconds into the file where this piece starts.
        var fileStart: Double
        var length: Double
        /// Where it starts: edit time (a free track) or recording time
        /// (locked to the recording).
        var at: Double

        var fileEnd: Double { fileStart + length }
        var end: Double { at + length }
    }

    static let volumeRange: ClosedRange<Double> = 0...2
    static let fadeRange: ClosedRange<Double> = 0...8
    static let fileExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "aiff", "aif", "flac", "caf"]

    var id = UUID()
    /// LF Studios' own copy of the file.
    var path: String
    var name: String
    /// The file's length.
    var duration: Double
    var pieces: [Piece]
    var volume = 1.0
    var muted = false
    var fadeIn = 0.0
    var fadeOut = 0.0
    /// On the recording's clock (set by Sync by sound); off: on the edit's.
    var lockedToRecording = false
    /// In place of the recording's microphone.
    var useAsVoice = false
    /// Lower while the voice speaks. Off to start with (manual only).
    var dipUnderVoice = false
    var dipLevel = 0.3
    /// The music ducks under this track's speech too (a voiceover, an
    /// interview): 1.16.0, off to start with (nil). The recording's voice
    /// and a track used as the voice always count.
    var ducksMusic: Bool?
    /// Volume keyframes, in the file's own seconds (1.15.0).
    var volumeKeys: VideoKeyframes?
    /// Detect beats: the file's beats, in its own seconds.
    var beats: [Double]?

    var url: URL { URL(fileURLWithPath: path) }

    init(path: String, name: String, duration: Double, at: Double) {
        self.path = path
        self.name = name
        self.duration = duration
        pieces = [Piece(fileStart: 0, length: duration, at: at)]
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, name, duration, pieces, volume, muted, fadeIn, fadeOut, lockedToRecording, useAsVoice, dipUnderVoice, dipLevel, volumeKeys, beats, ducksMusic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        path = try c.decode(String.self, forKey: .path)
        name = (try? c.decode(String.self, forKey: .name)) ?? URL(fileURLWithPath: path).lastPathComponent
        duration = (try? c.decode(Double.self, forKey: .duration)) ?? 0
        pieces = (try? c.decode([Piece].self, forKey: .pieces)) ?? []
        volume = (try? c.decodeIfPresent(Double.self, forKey: .volume)) ?? 1
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false
        fadeIn = (try? c.decodeIfPresent(Double.self, forKey: .fadeIn)) ?? 0
        fadeOut = (try? c.decodeIfPresent(Double.self, forKey: .fadeOut)) ?? 0
        lockedToRecording = (try? c.decodeIfPresent(Bool.self, forKey: .lockedToRecording)) ?? false
        useAsVoice = (try? c.decodeIfPresent(Bool.self, forKey: .useAsVoice)) ?? false
        dipUnderVoice = (try? c.decodeIfPresent(Bool.self, forKey: .dipUnderVoice)) ?? false
        dipLevel = (try? c.decodeIfPresent(Double.self, forKey: .dipLevel)) ?? 0.3
        volumeKeys = (try? c.decodeIfPresent(VideoKeyframes.self, forKey: .volumeKeys)).flatMap { $0 }
        beats = (try? c.decodeIfPresent([Double].self, forKey: .beats)).flatMap { $0 }
        ducksMusic = (try? c.decodeIfPresent(Bool.self, forKey: .ducksMusic)).flatMap { $0 }
    }

    /// Edit-time stretches each piece plays (several when a locked piece
    /// spans cuts), with the file second each starts at and its speed.
    struct Placed: Equatable {
        var piece: UUID
        var fileStart: Double
        var fileLength: Double
        var timelineStart: Double
        var speed: Double

        var timelineLength: Double { fileLength / max(speed, 0.0001) }
        var timelineEnd: Double { timelineStart + timelineLength }
    }

    func placed(segments: [VideoDemoTimelineSegment], timelineDuration: Double) -> [Placed] {
        var result: [Placed] = []
        for piece in pieces where piece.length > 0.001 {
            if lockedToRecording {
                // Recording time [at, end] → wherever the edit plays it.
                for segment in segments {
                    let clip = segment.clip
                    let a = max(piece.at, clip.sourceStart), b = min(piece.end, clip.sourceEnd)
                    guard b - a > 0.001 else { continue }
                    let speed = clip.normalizedSpeed
                    result.append(Placed(piece: piece.id, fileStart: piece.fileStart + (a - piece.at), fileLength: b - a,
                                         timelineStart: segment.timelineStart + (a - clip.sourceStart) / speed, speed: speed))
                }
            } else {
                let start = max(piece.at, 0)
                let end = min(piece.end, timelineDuration)
                guard end - start > 0.001 else { continue }
                result.append(Placed(piece: piece.id, fileStart: piece.fileStart + (start - piece.at), fileLength: end - start, timelineStart: start, speed: 1))
            }
        }
        return result.sorted { $0.timelineStart < $1.timelineStart }
    }

    /// Splits the piece playing at edit time `time` into two.
    mutating func split(at time: Double, segments: [VideoDemoTimelineSegment]) -> Bool {
        let local: Double?
        let pieceIndex: Int?
        if lockedToRecording {
            guard let segment = segments.first(where: { time >= $0.timelineStart && time < $0.timelineEnd }) else { return false }
            let source = segment.sourceTime(forTimelineTime: time)
            pieceIndex = pieces.firstIndex { source > $0.at + 0.05 && source < $0.end - 0.05 }
            local = pieceIndex.map { source - pieces[$0].at }
        } else {
            pieceIndex = pieces.firstIndex { time > $0.at + 0.05 && time < $0.end - 0.05 }
            local = pieceIndex.map { time - pieces[$0].at }
        }
        guard let pieceIndex, let local else { return false }
        let piece = pieces[pieceIndex]
        pieces[pieceIndex].length = local
        pieces.insert(Piece(fileStart: piece.fileStart + local, length: piece.length - local, at: piece.at + local), at: pieceIndex + 1)
        return true
    }
}

extension VideoDemoProject {
    /// The added track used as the voice, if any.
    var externalVoice: VideoExternalAudioTrack? { audioTracks.first { $0.useAsVoice && !$0.muted } }
    /// Sound tracks the music ducks under besides the voice (heard ones).
    var duckingTracks: [VideoExternalAudioTrack] {
        audioTracks.filter { $0.ducksMusic == true && !$0.useAsVoice && !$0.muted && !trackState(.sound($0.id)).muted }
    }
}

// MARK: - Into the composition

/// The added tracks' files, loaded, for building the edit.
struct VideoExternalAudioInput {
    struct Track {
        var settings: VideoExternalAudioTrack
        var file: VideoAudioFile
    }

    var tracks: [Track]
    /// Edit-time stretches with speech (a track set to dip lowers under them).
    var voice: [ClosedRange<Double>]
    /// Range exports: where the exported part starts on the edit's timeline.
    var timelineOffset: Double = 0

    struct StructureKey: Equatable {
        let pieces: [String]
    }

    struct MixKey: Equatable {
        let tracks: [VideoExternalAudioTrack]
        let voice: [ClosedRange<Double>]
    }

    var structureKey: StructureKey {
        StructureKey(pieces: tracks.map { track in
            "\(track.file.asset.url.path)|\(track.settings.lockedToRecording)|" + track.settings.pieces.map { "\($0.fileStart),\($0.length),\($0.at)" }.joined(separator: ";")
        })
    }

    var mixKey: MixKey { MixKey(tracks: tracks.map(\.settings), voice: voice) }

    /// Each piece on its own composition track. Returns the tracks with
    /// what each one holds.
    func insert(into composition: AVMutableComposition, segments: [VideoDemoTimelineSegment], duration: Double) -> [(track: AVMutableCompositionTrack, id: UUID, placed: [VideoExternalAudioTrack.Placed])] {
        var result: [(AVMutableCompositionTrack, UUID, [VideoExternalAudioTrack.Placed])] = []
        for input in tracks {
            var settings = input.settings
            if timelineOffset > 0, !settings.lockedToRecording {
                for index in settings.pieces.indices { settings.pieces[index].at -= timelineOffset }
            }
            let placed = settings.placed(segments: segments, timelineDuration: duration)
            guard !placed.isEmpty, let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            var kept: [VideoExternalAudioTrack.Placed] = []
            for piece in placed {
                let wanted = CMTimeRange(start: VideoCompositionBuilder.time(piece.fileStart), duration: VideoCompositionBuilder.time(piece.fileLength))
                let range = wanted.intersection(CMTimeRange(start: .zero, duration: VideoCompositionBuilder.time(input.settings.duration)))
                guard range.duration.seconds > 0.001 else { continue }
                let at = VideoCompositionBuilder.time(piece.timelineStart)
                do {
                    try track.insertTimeRange(range, of: input.file.track, at: at)
                } catch {
                    continue
                }
                if abs(piece.speed - 1) > 0.0001 {
                    track.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: VideoCompositionBuilder.time(range.duration.seconds / piece.speed))
                }
                kept.append(piece)
            }
            if kept.isEmpty {
                composition.removeTrack(track)
            } else {
                result.append((track, input.settings.id, kept))
            }
        }
        return result
    }

    /// Level, mute, fades at each piece's ends, and the dip under the voice.
    func apply(to params: AVMutableAudioMixInputParameters, track id: UUID, placed: [VideoExternalAudioTrack.Placed], audio: VideoAudioSettings) {
        guard let settings = tracks.first(where: { $0.settings.id == id })?.settings else { return }
        var level = audio.muted || settings.muted ? 0 : settings.volume * audio.volume
        if settings.useAsVoice { level *= audio.voiceVolume }
        params.setVolume(0, at: .zero)
        for piece in placed {
            var keyframes = Self.envelope(level: level, piece: piece, fadeIn: settings.fadeIn, fadeOut: settings.fadeOut,
                                          dip: settings.dipUnderVoice && !settings.useAsVoice ? settings.dipLevel : nil, voice: voice)
            // Volume keyframes (1.15.0): the level follows them, sampled
            // every tenth of a second.
            if let keys = settings.volumeKeys, keys.isAnimated(.volume), settings.volume > 0.000_1 {
                func factor(_ t: Double) -> Double {
                    let fileTime = piece.fileStart + (t - piece.timelineStart) * piece.speed
                    return keys.value(.volume, at: fileTime, base: settings.volume) / settings.volume
                }
                var times = Set(keyframes.map(\.time))
                var t = piece.timelineStart
                while t < piece.timelineEnd { times.insert((t * 1000).rounded() / 1000); t += 0.1 }
                let base = Self.envelope(level: level, piece: piece, fadeIn: settings.fadeIn, fadeOut: settings.fadeOut,
                                         dip: settings.dipUnderVoice && !settings.useAsVoice ? settings.dipLevel : nil, voice: voice)
                func envelopeGain(_ t: Double) -> Double {
                    guard let i = base.lastIndex(where: { $0.time <= t }) else { return base.first?.gain ?? level }
                    guard i + 1 < base.count else { return base[i].gain }
                    let a = base[i], b = base[i + 1]
                    return a.gain + (b.gain - a.gain) * (t - a.time) / max(b.time - a.time, 0.000_001)
                }
                keyframes = times.sorted().map { ($0, envelopeGain($0) * factor($0)) }
            }
            for (index, keyframe) in keyframes.enumerated() {
                let time = VideoCompositionBuilder.time(keyframe.time)
                if index + 1 < keyframes.count {
                    let next = keyframes[index + 1]
                    params.setVolumeRamp(fromStartVolume: Float(keyframe.gain), toEndVolume: Float(next.gain),
                                         timeRange: CMTimeRange(start: time, duration: VideoCompositionBuilder.time(max(next.time - keyframe.time, 0.001))))
                } else {
                    params.setVolume(Float(keyframe.gain), at: time)
                }
            }
            params.setVolume(0, at: VideoCompositionBuilder.time(piece.timelineEnd))
        }
    }

    /// A piece's level over time: fades at its ends, dipping (attack 0.25 s,
    /// release 0.6 s) where the voice speaks.
    static func envelope(level: Double, piece: VideoExternalAudioTrack.Placed, fadeIn: Double, fadeOut: Double, dip: Double?, voice: [ClosedRange<Double>]) -> [(time: Double, gain: Double)] {
        let start = piece.timelineStart, end = piece.timelineEnd
        var times = [start, end]
        let fadeIn = min(max(fadeIn, 0), (end - start) / 2), fadeOut = min(max(fadeOut, 0), (end - start) / 2)
        if fadeIn > 0.001 { times.append(start + fadeIn) }
        if fadeOut > 0.001 { times.append(end - fadeOut) }
        if dip != nil {
            for range in voice where range.upperBound > start && range.lowerBound < end {
                times += [range.lowerBound - 0.25, range.lowerBound, range.upperBound, range.upperBound + 0.6].filter { $0 > start && $0 < end }
            }
        }
        func gain(_ t: Double) -> Double {
            var g = level
            if fadeIn > 0.001, t < start + fadeIn { g *= max(t - start, 0) / fadeIn }
            if fadeOut > 0.001, t > end - fadeOut { g *= max(end - t, 0) / fadeOut }
            if let dip {
                var duck = 1.0
                for range in voice {
                    if t >= range.lowerBound && t <= range.upperBound { duck = dip; break }
                    if t < range.lowerBound && t > range.lowerBound - 0.25 { duck = min(duck, 1 - (1 - dip) * (t - (range.lowerBound - 0.25)) / 0.25) }
                    if t > range.upperBound && t < range.upperBound + 0.6 { duck = min(duck, dip + (1 - dip) * (t - range.upperBound) / 0.6) }
                }
                g *= duck
            }
            return g
        }
        return Array(Set(times.map { ($0 * 1000).rounded() / 1000 })).sorted().map { ($0, gain($0)) }
    }
}

extension VideoExternalAudioInput {
    /// The file a track plays: the one used as the voice plays its
    /// cleaned-up version once it's ready (Enhance voice, Podcast mode).
    static func fileURL(for track: VideoExternalAudioTrack, recipe: VideoVoiceRecipe?) -> URL {
        if track.useAsVoice, let recipe {
            let cleaned = VideoVoiceEnhancer.cacheURL(for: track.url, trackIndex: 0, recipe: recipe)
            if FileManager.default.fileExists(atPath: cleaned.path) { return cleaned }
        }
        return track.url
    }
}

// MARK: - Adding a file

enum VideoExternalAudioImport {
    enum Failure: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return L("“\(name)” isn't a sound file this Mac can play")
            }
        }
    }

    /// LF Studios' own copy, playable in a video: copied as it is when the
    /// Mac's video pipeline plays it, otherwise converted once to lossless
    /// CAF (some FLAC files). Returns the copy and its length.
    static func prepare(_ url: URL) async throws -> (url: URL, duration: Double) {
        if let length = await playableLength(url) {
            return (try VideoAssetStore.importFile(url), length)
        }
        let converted = FileManager.default.temporaryDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent).caf")
        try? FileManager.default.removeItem(at: converted)
        do {
            let input = try AVAudioFile(forReading: url)
            var settings = input.fileFormat.settings
            settings[AVFormatIDKey] = kAudioFormatAppleLossless
            settings[AVEncoderBitDepthHintKey] = 24
            let output = try AVAudioFile(forWriting: converted, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 48_000)!
            while input.framePosition < input.length {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
            }
        } catch {
            throw Failure.unreadable(url.lastPathComponent)
        }
        defer { try? FileManager.default.removeItem(at: converted) }
        guard let length = await playableLength(converted) else { throw Failure.unreadable(url.lastPathComponent) }
        return (try VideoAssetStore.importFile(converted), length)
    }

    /// The file's length, if it has sound a composition can take.
    static func playableLength(_ url: URL) async -> Double? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let range = try? await track.load(.timeRange), range.duration.seconds > 0.05 else { return nil }
        let composition = AVMutableComposition()
        guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              (try? target.insertTimeRange(range, of: track, at: .zero)) != nil else { return nil }
        return range.duration.seconds
    }
}

// MARK: - Sync by sound

extension VideoExternalAudioTrack {
    /// Lines the track up with the recording by their sound, and locks it
    /// to the recording's clock: each piece goes where its part of the file
    /// was heard.
    mutating func lock(toRecordingOffset offset: Double) {
        // File time = recording time − offset.
        lockedToRecording = true
        for index in pieces.indices { pieces[index].at = pieces[index].fileStart + offset }
    }
}

// MARK: - In the editor

/// One piece of one added track.
struct VideoAudioPieceRef: Equatable, Hashable {
    var track: UUID
    var piece: UUID
}

extension VideoEditorModel {
    /// Audio panel ▸ Add audio….
    func chooseAudio() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = VideoExternalAudioTrack.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = L("Choose sound files to add as tracks of their own")
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await addAudio(urls, at: clock.time) }
    }

    /// Each file becomes its own track, starting at edit time `time`.
    @discardableResult
    func addAudio(_ urls: [URL], at time: Double) async -> [UUID] {
        var added: [VideoExternalAudioTrack] = []
        for url in urls where VideoExternalAudioTrack.fileExtensions.contains(url.pathExtension.lowercased()) {
            do {
                let prepared = try await VideoExternalAudioImport.prepare(url)
                added.append(VideoExternalAudioTrack(path: prepared.url.path, name: url.lastPathComponent, duration: prepared.duration, at: max(time, 0)))
            } catch {
                showNotice(error.localizedDescription, symbol: "exclamationmark.triangle.fill", duration: 5)
            }
        }
        guard !added.isEmpty else { return [] }
        mutate(label: "Add Audio") { $0.audioTracks += added }
        inspectorTab = .audio
        if let first = added.first, let piece = first.pieces.first {
            selection = .none
            selectedAudioPiece = VideoAudioPieceRef(track: first.id, piece: piece.id)
        }
        showNotice(added.count == 1 ? L("Added “\(added[0].name)” as its own track") : L("Added \(added.count) sound files as tracks"), symbol: "waveform")
        return added.map(\.id)
    }

    func audioTrack(_ id: UUID) -> VideoExternalAudioTrack? { project.audioTracks.first { $0.id == id } }

    /// Volume, fades, mute, dip: one ⌘Z step per change.
    func setAudioTrack(_ id: UUID, _ change: (inout VideoExternalAudioTrack) -> Void) {
        guard let index = project.audioTracks.firstIndex(where: { $0.id == id }) else { return }
        mutate(coalesce: "audio-track-\(id)", label: "Audio Track Change") { change(&$0.audioTracks[index]) }
    }

    /// Use as my voice: in place of the recording's microphone (one track
    /// at a time).
    func setUseAsVoice(_ id: UUID, _ on: Bool) {
        mutate(label: "Audio Track Change") { project in
            for index in project.audioTracks.indices {
                project.audioTracks[index].useAsVoice = on && project.audioTracks[index].id == id
            }
        }
    }

    func removeAudioTrack(_ id: UUID) {
        if selectedAudioPiece?.track == id { selectedAudioPiece = nil }
        mutate(label: "Remove Audio") { $0.audioTracks.removeAll { $0.id == id } }
    }

    func deleteAudioPiece(_ ref: VideoAudioPieceRef) {
        selectedAudioPiece = nil
        mutate(label: "Remove Audio") { project in
            guard let index = project.audioTracks.firstIndex(where: { $0.id == ref.track }) else { return }
            project.audioTracks[index].pieces.removeAll { $0.id == ref.piece }
            if project.audioTracks[index].pieces.isEmpty { project.audioTracks.remove(at: index) }
        }
    }

    /// S with a piece selected: the track splits at the playhead.
    func splitAudioTrack(_ id: UUID) {
        guard let index = project.audioTracks.firstIndex(where: { $0.id == id }) else { return }
        var track = project.audioTracks[index]
        guard track.split(at: clock.time, segments: segments) else {
            showNotice(L("Move the playhead into the sound to split it"), symbol: "scissors")
            return
        }
        mutate(label: "Split Audio") { $0.audioTracks[index] = track }
    }

    /// Dragged on its lane by `delta` seconds of the edit.
    func moveAudioPiece(_ ref: VideoAudioPieceRef, by delta: Double) {
        guard let track = project.audioTracks.firstIndex(where: { $0.id == ref.track }),
              let piece = project.audioTracks[track].pieces.firstIndex(where: { $0.id == ref.piece }) else { return }
        mutate(coalesce: "audio-move-\(ref.piece)", label: "Move Audio") { project in
            let at = project.audioTracks[track].pieces[piece].at + delta
            project.audioTracks[track].pieces[piece].at = project.audioTracks[track].lockedToRecording ? at : max(at, 0)
        }
    }

    /// Dragged at an edge: the piece starts later or ends sooner in its
    /// file (and back out, up to the file's own ends).
    func trimAudioPiece(_ ref: VideoAudioPieceRef, leading: Bool, by delta: Double) {
        guard let track = project.audioTracks.firstIndex(where: { $0.id == ref.track }),
              let piece = project.audioTracks[track].pieces.firstIndex(where: { $0.id == ref.piece }) else { return }
        let duration = project.audioTracks[track].duration
        mutate(coalesce: "audio-trim-\(ref.piece)-\(leading)", label: "Trim Audio") { project in
            var p = project.audioTracks[track].pieces[piece]
            if leading {
                let shift = min(max(delta, -p.fileStart), p.length - 0.1)
                p.fileStart += shift
                p.at += shift
                p.length -= shift
            } else {
                p.length = min(max(p.length + delta, 0.1), duration - p.fileStart)
            }
            project.audioTracks[track].pieces[piece] = p
        }
    }

    /// Sync by sound: lined up with the recording's sound (the camera's way
    /// of syncing), then locked to the recording's clock.
    func syncAudioTrack(_ id: UUID) async {
        guard let track = audioTrack(id) else { return }
        isSyncingAudio = id
        defer { isSyncingAudio = nil }
        switch await VideoAudioSync.match(reference: project.sourceURL, other: track.url) {
        case .success(let match):
            guard let index = project.audioTracks.firstIndex(where: { $0.id == id }) else { return }
            mutate(label: "Sync Audio by Sound") { $0.audioTracks[index].lock(toRecordingOffset: match.offset) }
            showNotice(L("Synced by sound — “\(track.name)” follows the recording now"), symbol: "waveform.badge.checkmark")
        case .failure(.noSound):
            showNotice(L("Can't sync — the recording or “\(track.name)” has no sound"), symbol: "exclamationmark.triangle.fill", duration: 5)
        case .failure(.weakMatch):
            showNotice(L("Can't sync — their sound doesn't match clearly enough. Drag the track into place instead."), symbol: "exclamationmark.triangle.fill", duration: 5)
        }
    }
}
