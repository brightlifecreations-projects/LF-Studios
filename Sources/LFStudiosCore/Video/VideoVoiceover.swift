import AVFoundation
import SwiftUI

// MARK: - Record voiceover (1.14.0)

/// Writes the microphone's samples (float mono, 48 kHz, as
/// RecordingMicrophone delivers them) to an AAC file. Tests feed it
/// samples directly; the real microphone needs a person to check.
final class VideoVoiceoverWriter: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private(set) var frames = 0

    init(url: URL) throws {
        self.url = url
        file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000],
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    var seconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(frames) / 48_000
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { memcpy(buffer.floatChannelData![0], $0.baseAddress!, samples.count * 4) }
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return }
        try? file.write(from: buffer)
        frames += samples.count
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
        guard let pointer else { return }
        let samples = pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { Array(UnsafeBufferPointer(start: $0, count: length / 4)) }
        append(samples)
    }

    /// Closes the file (nothing more is written).
    func finish() {
        lock.lock()
        file = nil
        lock.unlock()
    }
}

/// A voiceover being recorded: the countdown, then the microphone.
@MainActor
final class VideoVoiceoverSession: ObservableObject {
    /// 3, 2, 1, then 0 while recording.
    @Published var countdown = 3
    @Published var elapsed = 0.0
    /// Where on the timeline it starts.
    let start: Double
    let writer: VideoVoiceoverWriter
    var microphone: RecordingMicrophone?
    let sampleQueue = DispatchQueue(label: "com.lfstudios.voiceover", qos: .userInitiated)

    init(start: Double, writer: VideoVoiceoverWriter) {
        self.start = start
        self.writer = writer
    }
}

extension VideoEditorModel {
    /// Record voiceover: starts (after 3, 2, 1) or stops.
    func toggleVoiceover() {
        if voiceover != nil {
            Task { await stopVoiceover() }
        } else {
            startVoiceover()
        }
    }

    func startVoiceover() {
        guard voiceover == nil else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { [weak self] in if granted { self?.startVoiceover() } }
            }
            return
        default:
            showNotice(L("LF Studios needs the microphone: System Settings ▸ Privacy & Security ▸ Microphone"), symbol: "mic.slash", duration: 5)
            return
        }
        guard let device = RecordingMicrophone.device(for: Settings.recordingMicrophoneDeviceID) else {
            showNotice(L("No microphone found"), symbol: "mic.slash")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Voiceover \(UUID().uuidString).m4a")
        guard let writer = try? VideoVoiceoverWriter(url: url) else { return }
        let session = VideoVoiceoverSession(start: clock.time, writer: writer)
        voiceover = session
        if isPlaying { pause() }
        Task {
            for count in [3, 2, 1] {
                guard voiceover === session else { return }
                session.countdown = count
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard voiceover === session else { return }
            let microphone = RecordingMicrophone(delegate: writer, sampleQueue: session.sampleQueue)
            do {
                try microphone.prepare(device: device)
            } catch {
                voiceover = nil
                showNotice(L("Couldn't open the microphone"), symbol: "mic.slash")
                return
            }
            session.microphone = microphone
            await microphone.start()
            session.countdown = 0
            // The video plays along, silent, so you can talk over it.
            playback.player.isMuted = true
            seek(to: session.start)
            if !isPlaying { togglePlay() }
            while voiceover === session {
                session.elapsed = writer.seconds
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    /// Stops recording; the voiceover becomes a new sound track where it
    /// started. Returns it.
    @discardableResult
    func stopVoiceover() async -> UUID? {
        guard let session = voiceover else { return nil }
        voiceover = nil
        session.microphone?.stop()
        if isPlaying { pause() }
        playback.player.isMuted = false
        return await finishVoiceover(session.writer, at: session.start)
    }

    /// The recorded file onto its own sound track at `time`.
    func finishVoiceover(_ writer: VideoVoiceoverWriter, at time: Double) async -> UUID? {
        writer.finish()
        defer { try? FileManager.default.removeItem(at: writer.url) }
        guard writer.seconds > 0.3 else {
            showNotice(L("Nothing was recorded"), symbol: "mic.slash")
            return nil
        }
        let number = project.audioTracks.filter { $0.name.hasPrefix(L("Voiceover")) }.count + 1
        guard let id = await addAudio([writer.url], at: time).first else { return nil }
        mutate(label: "Record Voiceover") { project in
            guard let index = project.audioTracks.firstIndex(where: { $0.id == id }) else { return }
            project.audioTracks[index].name = number == 1 ? L("Voiceover") : L("Voiceover \(number)")
        }
        joinLastUndoSteps(label: "Record Voiceover")
        return id
    }
}

/// While a voiceover records: the countdown, the time, Stop.
struct VideoVoiceoverPill: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        if let session = model.voiceover {
            VideoVoiceoverPillContent(session: session) { model.toggleVoiceover() }
        }
    }
}

private struct VideoVoiceoverPillContent: View {
    @ObservedObject var session: VideoVoiceoverSession
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 9, height: 9)
            if session.countdown > 0 {
                Text(L("Recording voiceover in \(session.countdown)…"))
            } else {
                Text(L("Recording voiceover — \(VideoEditorModel.timecode(session.elapsed))"))
                    .monospacedDigit()
            }
            Button(L("Stop")) { stop() }
                .buttonStyle(VideoSecondaryButtonStyle())
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(VideoEditorTheme.textPrimary)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Capsule().fill(VideoEditorTheme.floatingPill))
        .shadow(color: VideoEditorTheme.shadow, radius: 10, y: 4)
    }
}
