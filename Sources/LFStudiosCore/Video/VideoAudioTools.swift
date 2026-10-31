import AVFoundation
import SwiftUI

// MARK: - Audio tools (1.15.0): volume keyframes, Normalize, Detect beats

/// A sound file's loudness and beats, read from the file.
enum VideoAudioAnalysis {
    /// Mono samples (48 kHz) of `url`, at most `limit` seconds.
    static func samples(_ url: URL, limit: Double = 1200) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.processingFormat.sampleRate, channels: file.processingFormat.channelCount, interleaved: false) else { return [] }
        let total = min(AVAudioFrameCount(file.length), AVAudioFrameCount(limit * file.processingFormat.sampleRate))
        guard total > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else { return [] }
        try? file.read(into: buffer, frameCount: total)
        let channels = Int(format.channelCount), frames = Int(buffer.frameLength)
        guard let data = buffer.floatChannelData else { return [] }
        var mono = [Float](repeating: 0, count: frames)
        for c in 0..<channels { for i in 0..<frames { mono[i] += data[c][i] / Float(channels) } }
        // To 48 kHz-equivalent spacing isn't needed: callers use `rate`.
        return mono
    }

    static func sampleRate(_ url: URL) -> Double {
        (try? AVAudioFile(forReading: url))?.processingFormat.sampleRate ?? 48_000
    }

    /// The level that brings the file to −16 LUFS (peaks under −1 dBFS),
    /// as a volume (0…2); nil for silence.
    static func normalizedVolume(_ url: URL) -> Double? {
        let mono = samples(url)
        guard !mono.isEmpty else { return nil }
        let meter = VideoLoudnessMeter(channels: 2, sampleRate: sampleRate(url))
        var stereo = [Float](repeating: 0, count: mono.count * 2)
        for (i, v) in mono.enumerated() { stereo[i * 2] = v; stereo[i * 2 + 1] = v }
        stereo.withUnsafeBufferPointer { meter.add(interleaved: $0) }
        guard meter.integratedLoudness != nil else { return nil }
        return min(max(meter.gain(), 0), 2)
    }

    /// Beats: where the sound's energy jumps (onsets), at least 0.25 s
    /// apart, in the file's own seconds.
    static func beats(_ url: URL) -> [Double] {
        let mono = samples(url)
        let rate = sampleRate(url)
        let hop = max(Int(rate / 100), 1)   // 10 ms
        guard mono.count > hop * 8 else { return [] }
        var energy: [Double] = []
        var i = 0
        while i + hop <= mono.count {
            var sum = 0.0
            for j in i..<(i + hop) { sum += Double(mono[j] * mono[j]) }
            energy.append(sqrt(sum / Double(hop)))
            i += hop
        }
        // Onset strength: the rise from one frame to the next.
        var flux = [Double](repeating: 0, count: energy.count)
        for k in 1..<energy.count { flux[k] = max(energy[k] - energy[k - 1], 0) }
        let peak = flux.max() ?? 0
        guard peak > 0.000_1 else { return [] }
        var beats: [Double] = []
        let window = 50 // ±0.5 s
        for k in 1..<(flux.count - 1) where flux[k] >= flux[k - 1] && flux[k] > flux[k + 1] {
            let lo = max(k - window, 0), hi = min(k + window, flux.count - 1)
            let local = flux[lo...hi].reduce(0, +) / Double(hi - lo + 1)
            guard flux[k] > local * 1.6 + peak * 0.15 else { continue }
            let time = Double(k) * Double(hop) / rate
            if let last = beats.last, time - last < 0.25 { continue }
            beats.append(time)
        }
        return beats
    }
}

/// Which sound an audio tool works on.
enum VideoAudioTarget: Equatable {
    case music
    case sound(UUID)
}

/// Audio edits (`VideoEditCommand.audio`).
enum VideoAudioEdit: Equatable {
    /// ◆ next to the volume: a key at the playhead, or it goes.
    case toggleVolumeKey(UUID)
    /// The volume at the playhead (a key there when keyed).
    case setVolume(UUID, Double)
    case normalize(VideoAudioTarget)
    case detectBeats(VideoAudioTarget)
    case clearBeats(VideoAudioTarget)

    var name: String {
        switch self {
        case .toggleVolumeKey(let id): return "toggleVolumeKey.\(id)"
        case .setVolume(let id, let v): return "setVolume.\(id).\(v)"
        case .normalize(let t): return "normalize.\(t)"
        case .detectBeats(let t): return "detectBeats.\(t)"
        case .clearBeats(let t): return "clearBeats.\(t)"
        }
    }

    var title: String {
        switch self {
        case .toggleVolumeKey: return L("Volume keyframe")
        case .setVolume: return L("Volume")
        case .normalize: return L("Normalize loudness")
        case .detectBeats: return L("Detect beats")
        case .clearBeats: return L("Clear beats")
        }
    }
}

extension VideoEditorModel {
    /// The file second of a sound track under the playhead (nil: none of it
    /// plays there).
    func fileTime(ofSound id: UUID, atTimeline time: Double) -> Double? {
        guard let track = audioTrack(id) else { return nil }
        for piece in track.placed(segments: segments, timelineDuration: timelineDuration) where time >= piece.timelineStart - 0.001 && time <= piece.timelineEnd + 0.001 {
            return piece.fileStart + (time - piece.timelineStart) * piece.speed
        }
        return nil
    }

    func perform(_ edit: VideoAudioEdit) -> Bool {
        switch edit {
        case .toggleVolumeKey(let id):
            guard !refuseLocked(.sound(id)), let track = audioTrack(id) else { return false }
            guard let fileTime = fileTime(ofSound: id, atTimeline: clock.time) else {
                showNotice(L("Move the playhead onto the sound to add a keyframe"), symbol: "diamond")
                return false
            }
            let value = track.volumeKeys?.value(.volume, at: fileTime, base: track.volume) ?? track.volume
            let removing = track.volumeKeys?.hasKey(.volume, at: fileTime) == true
            mutate(label: removing ? "Remove Keyframe" : "Add Keyframe") { project in
                guard let i = project.audioTracks.firstIndex(where: { $0.id == id }) else { return }
                var keys = project.audioTracks[i].volumeKeys ?? VideoKeyframes()
                if removing { keys.remove(.volume, at: fileTime) } else { keys.set(.volume, at: fileTime, value: value) }
                project.audioTracks[i].volumeKeys = keys.isEmpty ? nil : keys
            }
        case .setVolume(let id, let volume):
            guard !refuseLocked(.sound(id)), let track = audioTrack(id) else { return false }
            let clamped = min(max(volume, 0), VideoExternalAudioTrack.volumeRange.upperBound)
            let fileTime = fileTime(ofSound: id, atTimeline: clock.time)
            mutate(coalesce: "sound-volume-\(id)", label: "Audio Track Change") { project in
                guard let i = project.audioTracks.firstIndex(where: { $0.id == id }) else { return }
                if let keys = track.volumeKeys, keys.isAnimated(.volume), let fileTime {
                    var next = keys
                    next.set(.volume, at: fileTime, value: clamped)
                    project.audioTracks[i].volumeKeys = next
                } else {
                    project.audioTracks[i].volume = clamped
                }
            }
        case .normalize(let target):
            Task { await normalize(target) }
        case .detectBeats(let target):
            Task { await detectBeats(target) }
        case .clearBeats(let target):
            mutate(label: "Clear Beats") { project in
                switch target {
                case .music: project.music?.beats = nil
                case .sound(let id): if let i = project.audioTracks.firstIndex(where: { $0.id == id }) { project.audioTracks[i].beats = nil }
                }
            }
        }
        return true
    }

    private func url(of target: VideoAudioTarget) -> URL? {
        switch target {
        case .music: return project.music?.url
        case .sound(let id): return audioTrack(id)?.url
        }
    }

    /// Normalize loudness: the volume that brings it to −16 LUFS, the level
    /// video sites expect. One ⌘Z step.
    func normalize(_ target: VideoAudioTarget) async {
        if case .sound(let id) = target, refuseLocked(.sound(id)) { return }
        if target == .music, refuseLocked(.music) { return }
        guard let url = url(of: target) else { return }
        let volume = await Task.detached(priority: .userInitiated) { VideoAudioAnalysis.normalizedVolume(url) }.value
        guard let volume else {
            showNotice(L("It's silent: nothing to normalize"), symbol: "speaker.slash")
            return
        }
        mutate(label: "Normalize Loudness") { project in
            switch target {
            case .music: project.music?.volume = min(volume, VideoMusicTrack.volumeRange.upperBound)
            case .sound(let id): if let i = project.audioTracks.firstIndex(where: { $0.id == id }) { project.audioTracks[i].volume = volume }
            }
        }
        showNotice(L("Normalized to −16 LUFS — volume \(Int((volume * 100).rounded()))%"), symbol: "waveform.badge.checkmark")
    }

    /// Detect beats: marks on the sound's lane where the beat is (dragged
    /// clips snap to them). One ⌘Z step.
    func detectBeats(_ target: VideoAudioTarget) async {
        if case .sound(let id) = target, refuseLocked(.sound(id)) { return }
        if target == .music, refuseLocked(.music) { return }
        guard let url = url(of: target) else { return }
        let beats = await Task.detached(priority: .userInitiated) { VideoAudioAnalysis.beats(url) }.value
        guard !beats.isEmpty else {
            showNotice(L("No clear beat found"), symbol: "metronome")
            return
        }
        mutate(label: "Detect Beats") { project in
            switch target {
            case .music: project.music?.beats = beats
            case .sound(let id): if let i = project.audioTracks.firstIndex(where: { $0.id == id }) { project.audioTracks[i].beats = beats }
            }
        }
        showNotice(L("\(beats.count) beats marked — clips snap to them"), symbol: "metronome")
    }

    /// Beats on the timeline (every sound's, where they play).
    var beatTimes: [Double] {
        var times: [Double] = []
        for track in project.audioTracks {
            guard let beats = track.beats else { continue }
            for piece in track.placed(segments: segments, timelineDuration: timelineDuration) {
                for beat in beats where beat >= piece.fileStart && beat <= piece.fileStart + piece.fileLength {
                    times.append(piece.timelineStart + (beat - piece.fileStart) / piece.speed)
                }
            }
        }
        if let music = project.music, let beats = music.beats, music.duration > 0 {
            // The song from the start (looping when set).
            let start = min(max(music.startOffset, 0), music.duration)
            var offset = 0.0
            repeat {
                for beat in beats where beat >= start { times.append(offset + beat - start) }
                offset += music.duration - start
            } while music.loops && offset < timelineDuration && music.duration - start > 0.5
        }
        return times.filter { $0 <= timelineDuration }.sorted()
    }
}

/// Volume ◆, Normalize and Detect beats under a sound track's settings.
struct VideoSoundTools: View {
    @ObservedObject var model: VideoEditorModel
    let target: VideoAudioTarget

    var body: some View {
        HStack(spacing: 6) {
            if case .sound(let id) = target {
                Button {
                    model.perform(.audio(.toggleVolumeKey(id)))
                } label: {
                    Label(L("Volume ◆"), systemImage: "diamond").frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("A volume keyframe at the playhead: set one, move, change the volume"))
            }
            Button {
                model.perform(.audio(.normalize(target)))
            } label: {
                Label(L("Normalize"), systemImage: "waveform.badge.checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .help(L("Sets the volume so it's as loud as video sites expect (−16 LUFS)"))
            Button {
                model.perform(.audio(.detectBeats(target)))
            } label: {
                Label(L("Beats"), systemImage: "metronome").frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .help(L("Detect beats: marks on the track where the beat is; clips snap to them"))
        }
        .font(.system(size: 11, weight: .semibold))
    }
}
