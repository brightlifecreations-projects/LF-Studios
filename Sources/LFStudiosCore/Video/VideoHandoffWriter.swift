import AVFoundation
import CoreImage
import Foundation
import VideoToolbox
import Vision

/// Writes a handoff plan into a new folder: copies, passthrough movies,
/// ProRes re-encodes, WAV sound, captions, the finished video, the timeline
/// files, and README.txt. Missing or failing parts are listed and skipped;
/// cancelling removes the folder.
final class VideoHandoffWriter: @unchecked Sendable {
    struct Progress: Equatable {
        var index: Int
        var count: Int
        var file: String
        /// The current file, 0…1.
        var fraction: Double
        /// All of it, 0…1.
        var overall: Double
        /// While re-encoding: seconds left for everything, from how fast
        /// this Mac is going.
        var secondsLeft: Double?
    }

    struct Result {
        var folder: URL
        var written: [String]
        var skipped: [String]
        var durations: [String: Double]
    }

    enum Failure: LocalizedError {
        case notEnoughSpace(needed: Int64, available: Int64)
        case couldNotCreateFolder(String)

        var errorDescription: String? {
            switch self {
            case .notEnoughSpace(let needed, let available):
                return L("Not enough space: the handoff needs about \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) and \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is free there.")
            case .couldNotCreateFolder(let reason):
                return L("Couldn't create the handoff folder — \(reason)")
            }
        }
    }

    let plan: VideoHandoffPlan
    let input: VideoHandoffInput
    let parent: URL
    var progress: (Progress) -> Void = { _ in }
    var isCancelled: () -> Bool = { false }
    var appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    private var startedReencoding: Date?
    private var reencodedSeconds = 0.0
    private var totalReencodeSeconds = 0.0

    init(plan: VideoHandoffPlan, input: VideoHandoffInput, parent: URL) {
        self.plan = plan
        self.input = input
        self.parent = parent
    }

    /// Whether this Mac has a ProRes encoder chip (otherwise ProRes is
    /// encoded by the processor, much more slowly).
    static var hasProResHardware: Bool {
        var properties: CFDictionary?
        let status = VTCopySupportedPropertyDictionaryForEncoder(
            width: 1920, height: 1080, codecType: kCMVideoCodecType_AppleProRes422HQ,
            encoderSpecification: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as CFDictionary,
            encoderIDOut: nil, supportedPropertiesOut: &properties
        )
        return status == noErr
    }

    /// Checks the space, makes the folder, and writes every file.
    func run() async throws -> Result {
        if let available = VideoExportFiles.availableBytes(at: parent) {
            let needed = Int64(Double(plan.estimatedBytes) * 1.1) + 50_000_000
            guard available >= needed else { throw Failure.notEnoughSpace(needed: needed, available: available) }
        }
        let name = VideoHandoffPlanner.folderName(project: input.name) { FileManager.default.fileExists(atPath: self.parent.appendingPathComponent($0).path) }
        let folder = parent.appendingPathComponent(name.isEmpty ? plan.folderName : name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            throw Failure.couldNotCreateFolder(error.localizedDescription)
        }
        do {
            return try await write(into: folder)
        } catch {
            // Cancelled (or something that stops everything): nothing half-made stays.
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func write(into folder: URL) async throws -> Result {
        var written: [String] = []
        var skipped = plan.skipped
        var durations: [String: Double] = [:]
        let media = plan.items.filter { if case .text("") = $0.work { return false } else { return true } }
        totalReencodeSeconds = media.reduce(0) { total, item in
            if case .reencode(_, let duration, _, _, _, _) = item.work { return total + duration }
            return total
        }
        let weights = media.map { item -> Double in max(Double(item.estimatedBytes), 1) }
        let totalWeight = weights.reduce(0, +)
        var done = 0.0

        for (index, item) in media.enumerated() {
            try checkCancelled()
            let url = folder.appendingPathComponent(item.relativePath)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let before = done
            let weight = weights[index]
            let report = { [weak self] (fraction: Double) in
                guard let self else { return }
                self.progress(Progress(index: index, count: media.count, file: item.relativePath, fraction: fraction,
                                       overall: (before + weight * fraction) / totalWeight, secondsLeft: self.secondsLeft()))
            }
            report(0)
            do {
                try await write(item, to: url, report: report)
                written.append(item.relativePath)
                if let measured = await Self.duration(of: url, item: item) { durations[item.relativePath] = measured }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? FileManager.default.removeItem(at: url)
                if isCancelled() { throw CancellationError() }
                skipped.append(L("\(item.relativePath) — \(error.localizedDescription)"))
            }
            done += weights[index]
            report(1)
        }

        var finalPlan = plan
        finalPlan.skipped = skipped
        if plan.options.includeTimeline {
            for (name, text) in [
                ("Timeline.fcpxml", VideoHandoffTimeline.fcpxml(plan: finalPlan, input: input, folder: folder, durations: durations)),
                ("Timeline (Premiere).xml", VideoHandoffTimeline.premiereXML(plan: finalPlan, input: input, folder: folder, durations: durations)),
            ] {
                try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
                written.append(name)
            }
        }
        if plan.options.includeSpeakerNotes, let notes = input.project.speakerNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try notes.write(to: folder.appendingPathComponent("Notes.txt"), atomically: true, encoding: .utf8)
            written.append("Notes.txt")
        }
        written.append("README.txt")
        let readme = VideoHandoffReadme.text(plan: finalPlan, name: input.name, appVersion: appVersion, durations: durations, written: Set(written), markers: input.project.placedMarkers(segments: input.segments), timelineDuration: input.timelineDuration)
        try readme.write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        return Result(folder: folder, written: written, skipped: skipped, durations: durations)
    }

    private func checkCancelled() throws {
        if isCancelled() { throw CancellationError() }
    }

    private func secondsLeft() -> Double? {
        guard let startedReencoding, reencodedSeconds > 1 else { return nil }
        let rate = reencodedSeconds / Date().timeIntervalSince(startedReencoding)
        guard rate > 0 else { return nil }
        return (totalReencodeSeconds - reencodedSeconds) / rate
    }

    private static func duration(of url: URL, item: VideoHandoffItem) async -> Double? {
        guard [.screen, .camera, .audio, .final].contains(item.folder) else { return nil }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let seconds = try? await asset.load(.duration).seconds, seconds.isFinite else { return nil }
        return seconds
    }

    // MARK: Each kind of file

    private func write(_ item: VideoHandoffItem, to url: URL, report: @escaping (Double) -> Void) async throws {
        switch item.work {
        case .copy(let source):
            try FileManager.default.copyItem(at: source, to: url)
        case .text(let text):
            try text.write(to: url, atomically: true, encoding: .utf8)
        case .passthrough(let pieces, let duration):
            try await Self.passthrough(pieces, duration: duration, to: url)
        case .reencode(let pieces, let duration, let codec, let alpha, _, let frameRate):
            if startedReencoding == nil { startedReencoding = Date() }
            let before = reencodedSeconds
            try await reencode(pieces, duration: duration, codec: codec, alpha: alpha, frameRate: frameRate, to: url) { [weak self] seconds in
                self?.reencodedSeconds = before + seconds
                report(duration > 0 ? seconds / duration : 1)
            }
        case .audio(let pieces, let duration, let channels, let aac):
            try await Self.audio(pieces, duration: duration, channels: channels, aac: aac, to: url, report: report, isCancelled: isCancelled)
        case .fullMix(let duration):
            let cancelled = isCancelled
            try await VideoDemoExporter.writeFullMix(
                project: input.project, recording: input.recording, settings: input.exportSettings, duration: duration, to: url,
                progress: { report($0) }, isCancelled: { cancelled() }
            )
        case .finalVideo:
            let cancelled = isCancelled
            try await VideoDemoExporter.export(
                project: input.project, recording: input.recording, destinationURL: url, settings: input.exportSettings,
                progress: { value in report(value) },
                shouldCancel: { cancelled() }
            )
        }
    }

    // MARK: Passthrough

    /// The pieces' video placed on a `duration` clock without re-encoding:
    /// the gap before is an empty edit, and a silent track keeps the file
    /// as long as the clock (a trailing empty edit isn't kept).
    static func passthrough(_ pieces: [VideoHandoffPiece], duration: Double, to url: URL) async throws {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw VideoDemoExportError.exportFailed(L("Couldn't prepare the video")) }
        var cursor = 0.0
        var transform: CGAffineTransform?
        for piece in pieces.sorted(by: { $0.at < $1.at }) {
            let asset = AVURLAsset(url: piece.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            guard let source = try await asset.loadTracks(withMediaType: .video).first else { continue }
            if transform == nil { transform = try? await source.load(.preferredTransform) }
            let at = max(piece.at, cursor)
            try track.insertTimeRange(CMTimeRange(start: time(piece.sourceStart), duration: time(piece.sourceDuration)), of: source, at: time(cursor))
            if at > cursor + 0.0001 {
                track.insertEmptyTimeRange(CMTimeRange(start: time(cursor), duration: time(at - cursor)))
            }
            if abs(piece.speed - 1) > 0.0001 {
                track.scaleTimeRange(CMTimeRange(start: time(at), duration: time(piece.sourceDuration)), toDuration: time(piece.outputDuration))
            }
            cursor = at + piece.outputDuration
        }
        track.preferredTransform = transform ?? .identity
        // Uncompressed silence: exactly as long as the clock.
        let silence = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-silence-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: silence) }
        try writeSilence(seconds: duration, to: silence)
        let silenceAsset = AVURLAsset(url: silence, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        if let silent = try await silenceAsset.loadTracks(withMediaType: .audio).first,
           let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audio.insertTimeRange(CMTimeRange(start: .zero, duration: time(duration)), of: silent, at: .zero)
        }
        try? FileManager.default.removeItem(at: url)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoDemoExportError.exportFailed(L("Couldn't prepare the video"))
        }
        session.timeRange = CMTimeRange(start: .zero, duration: time(duration))
        try await session.export(to: url, as: .mov)
    }

    static func writeSilence(seconds: Double, to url: URL) throws {
        let rate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
        var left = AVAudioFrameCount((seconds * rate).rounded(.up)) + 1
        let chunk = AVAudioFrameCount(rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
        while left > 0 {
            buffer.frameLength = min(chunk, left)
            try file.write(from: buffer)
            left -= buffer.frameLength
        }
    }

    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 60_000)
    }

    // MARK: ProRes

    /// Frame by frame on a constant clock: each output frame shows the
    /// source frame at its moment (speed changes pick frames), black (or
    /// transparent) where nothing plays. `alpha`: the person cut out of the
    /// camera picture, written with transparency.
    private func reencode(_ pieces: [VideoHandoffPiece], duration: Double, codec: AVVideoCodecType, alpha: Bool, frameRate: Double, to url: URL, report: @escaping (Double) -> Void) async throws {
        let sorted = pieces.sorted { $0.at < $1.at }
        guard let first = sorted.first else { throw VideoDemoExportError.exportFailed(L("There's nothing to write")) }
        let firstAsset = AVURLAsset(url: first.url)
        guard let firstTrack = try await firstAsset.loadTracks(withMediaType: .video).first else { throw VideoDemoExportError.exportFailed(L("The video has no picture")) }
        let natural = try await firstTrack.load(.naturalSize)
        let transform = try await firstTrack.load(.preferredTransform)
        let width = Int(natural.width), height = Int(natural.height)

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.transform = transform
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoDemoExportError.exportFailed(L("Couldn't start writing")) }
        writer.startSession(atSourceTime: .zero)

        let context = CIContext(options: [.cacheIntermediates: false])
        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = .balanced
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let sequence = VNSequenceRequestHandler()

        let rate = max(frameRate, 1)
        let frames = Int((duration * rate).rounded())
        var reader: PieceReader?
        var blank: CVPixelBuffer?
        var lastPicture: CVPixelBuffer?
        for frame in 0..<max(frames, 1) {
            try checkCancelled()
            let t = Double(frame) / rate
            var picture: CVPixelBuffer?
            if let piece = sorted.last(where: { t >= $0.at - 0.0001 && t < $0.end - 0.0001 }) {
                if reader?.piece != piece { reader = try await PieceReader(piece: piece) }
                if let source = reader?.frame(at: piece.sourceStart + (t - piece.at) * piece.speed) {
                    if alpha {
                        picture = cutout(source, context: context, request: segmentation, sequence: sequence, pool: adaptor.pixelBufferPool)
                    } else {
                        picture = source
                    }
                }
                if picture == nil { picture = lastPicture }
            }
            if picture == nil {
                if blank == nil { blank = Self.blankBuffer(pool: adaptor.pixelBufferPool, width: width, height: height) }
                picture = blank
            } else {
                lastPicture = picture
            }
            while !input.isReadyForMoreMediaData {
                try checkCancelled()
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            if let picture, !adaptor.append(picture, withPresentationTime: CMTime(seconds: t, preferredTimescale: 60_000)) {
                throw writer.error ?? VideoDemoExportError.exportFailed(L("Couldn't write a frame"))
            }
            if frame % 15 == 0 { report(t) }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: Double(max(frames, 1)) / rate, preferredTimescale: 60_000))
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? VideoDemoExportError.exportFailed(L("Couldn't finish the file")) }
        report(duration)
    }

    static func blankBuffer(pool: CVPixelBufferPool?, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
        if buffer == nil {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// The person in `frame`, everything else transparent.
    private func cutout(_ frame: CVPixelBuffer, context: CIContext, request: VNGeneratePersonSegmentationRequest, sequence: VNSequenceRequestHandler, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard (try? sequence.perform([request], on: frame)) != nil, let mask = request.results?.first?.pixelBuffer else { return nil }
        let image = CIImage(cvPixelBuffer: frame)
        var maskImage = CIImage(cvPixelBuffer: mask)
        maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: image.extent.width / maskImage.extent.width, y: image.extent.height / maskImage.extent.height))
        let person = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: image.extent),
            kCIInputMaskImageKey: maskImage,
        ])
        var output: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) }
        guard let output else { return nil }
        context.render(person, to: output, bounds: image.extent, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return output
    }

    /// Decodes one piece's source frames in order, handing out the frame
    /// shown at a source time.
    private final class PieceReader {
        let piece: VideoHandoffPiece
        private let reader: AVAssetReader
        private let output: AVAssetReaderTrackOutput
        private var current: (time: Double, buffer: CVPixelBuffer)?
        private var next: (time: Double, buffer: CVPixelBuffer)?
        private var finished = false

        init(piece: VideoHandoffPiece) async throws {
            self.piece = piece
            let asset = AVURLAsset(url: piece.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoDemoExportError.exportFailed(L("The video has no picture")) }
            reader = try AVAssetReader(asset: asset)
            reader.timeRange = CMTimeRange(start: VideoHandoffWriter.time(max(piece.sourceStart - 0.5, 0)), duration: VideoHandoffWriter.time(piece.sourceDuration + 1))
            output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? VideoDemoExportError.exportFailed(L("Couldn't read the video")) }
        }

        private func read() -> (time: Double, buffer: CVPixelBuffer)? {
            guard !finished else { return nil }
            while let sample = output.copyNextSampleBuffer() {
                if let buffer = CMSampleBufferGetImageBuffer(sample) {
                    return (CMSampleBufferGetPresentationTimeStamp(sample).seconds, buffer)
                }
            }
            finished = true
            return nil
        }

        /// The last frame at or before `time` (the first one if none is).
        func frame(at time: Double) -> CVPixelBuffer? {
            if current == nil { current = read(); next = read() }
            while let upcoming = next, upcoming.time <= time + 0.0005 {
                current = upcoming
                next = read()
            }
            return current?.buffer
        }
    }

    // MARK: Sound

    /// The pieces' sound laid out on a `duration` clock: silence in between,
    /// each piece at its speed (pitch kept), music at its level with fades.
    static func audio(_ pieces: [VideoHandoffPiece], duration: Double, channels: Int, aac: Bool, to url: URL, report: (Double) -> Void, isCancelled: () -> Bool) async throws {
        let rate = 48_000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels)) else { throw VideoDemoExportError.exportFailed(L("Couldn't prepare the sound")) }
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = aac
            ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 256_000]
            : [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let totalFrames = AVAudioFramePosition((duration * rate).rounded())
        var position: AVAudioFramePosition = 0
        let chunk = AVAudioFrameCount(rate / 2)
        let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!

        func writeSilence(until target: AVAudioFramePosition) throws {
            while position < target {
                silence.frameLength = AVAudioFrameCount(min(Int64(chunk), target - position))
                try file.write(from: silence)
                position += AVAudioFramePosition(silence.frameLength)
            }
        }

        for piece in pieces.sorted(by: { $0.at < $1.at }) {
            if isCancelled() { throw CancellationError() }
            let start = AVAudioFramePosition((piece.at * rate).rounded())
            let end = min(AVAudioFramePosition((piece.end * rate).rounded()), totalFrames)
            guard end > position else { continue }
            try writeSilence(until: start)
            let asset = AVURLAsset(url: piece.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.indices.contains(piece.audioTrack ?? 0) ? tracks[piece.audioTrack ?? 0] : nil else {
                try writeSilence(until: end)
                continue
            }
            // A composition of just this stretch, at its speed.
            let composition = AVMutableComposition()
            guard let part = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try part.insertTimeRange(CMTimeRange(start: time(piece.sourceStart), duration: time(piece.sourceDuration)), of: track, at: .zero)
            if abs(piece.speed - 1) > 0.0001 {
                part.scaleTimeRange(CMTimeRange(start: .zero, duration: time(piece.sourceDuration)), toDuration: time(piece.outputDuration))
            }
            let reader = try AVAssetReader(asset: composition)
            let output = AVAssetReaderAudioMixOutput(audioTracks: [part], audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: true, AVLinearPCMIsBigEndianKey: false,
            ])
            output.audioTimePitchAlgorithm = .spectral
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? VideoDemoExportError.exportFailed(L("Couldn't read the sound")) }
            var written = 0.0
            while position < end, let sample = output.copyNextSampleBuffer() {
                guard let buffer = pcmBuffer(sample, format: format) else { continue }
                let room = AVAudioFrameCount(end - position)
                if buffer.frameLength > room { buffer.frameLength = room }
                if piece.gain != 1 || piece.fadeIn > 0 || piece.fadeOut > 0 {
                    applyGain(buffer, piece: piece, offset: written, rate: rate)
                }
                try file.write(from: buffer)
                position += AVAudioFramePosition(buffer.frameLength)
                written += Double(buffer.frameLength)
                report(min(Double(position) / Double(max(totalFrames, 1)), 1))
            }
            reader.cancelReading()
            // A piece a little shorter than planned: silence to its end.
            try writeSilence(until: end)
        }
        try writeSilence(until: totalFrames)
    }

    private static func pcmBuffer(_ sample: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    /// The music's level, fading in at its start and out at its end.
    private static func applyGain(_ buffer: AVAudioPCMBuffer, piece: VideoHandoffPiece, offset: Double, rate: Double) {
        guard let channels = buffer.floatChannelData else { return }
        let length = piece.outputDuration
        for frame in 0..<Int(buffer.frameLength) {
            let t = (offset + Double(frame)) / rate
            var gain = piece.gain
            if piece.fadeIn > 0, t < piece.fadeIn { gain *= t / piece.fadeIn }
            if piece.fadeOut > 0, t > length - piece.fadeOut { gain *= max(length - t, 0) / piece.fadeOut }
            for channel in 0..<Int(buffer.format.channelCount) {
                channels[channel][frame] *= Float(gain)
            }
        }
    }
}
