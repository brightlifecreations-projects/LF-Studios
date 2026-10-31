import AVFoundation
import CoreImage
import SwiftUI

// MARK: - Videos LF Studios makes for the main track (1.14.0)

/// Pictures on the main track, freeze frames and reversed clips become
/// video files LF Studios writes, joined to the main track like an added
/// recording. They live with the pictures and songs it copies
/// (VideoAssetStore), named `Generated-…`, and go when nothing uses them
/// (`VideoGeneratedMedia.removeUnused`).
enum VideoGeneratedMedia {
    static let prefix = "Generated-"

    static func newURL() throws -> URL {
        try FileManager.default.createDirectory(at: VideoAssetStore.folder, withIntermediateDirectories: true)
        return VideoAssetStore.folder.appendingPathComponent("\(prefix)\(UUID().uuidString).mov")
    }

    static func isGenerated(_ path: String) -> Bool {
        VideoAssetStore.isStored(path) && URL(fileURLWithPath: path).lastPathComponent.hasPrefix(prefix)
    }

    enum Failure: LocalizedError {
        case unreadable
        case cancelled

        var errorDescription: String? {
            switch self {
            case .unreadable: return L("Couldn't read that part of the video")
            case .cancelled: return L("Cancelled")
            }
        }
    }

    // MARK: Stills

    /// `image` held for `seconds`, fitted on black at `size` (even pixels).
    static func stillVideo(_ image: CIImage, size: CGSize, seconds: Double, fps: Int = 30) async throws -> URL {
        let url = try newURL()
        let width = max(Int((size.width / 2).rounded()) * 2, 16)
        let height = max(Int((size.height / 2).rounded()) * 2, 16)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.unreadable }
        writer.startSession(atSourceTime: .zero)
        // One frame drawn, written for every frame of the length.
        let frame = fitted(image, into: CGSize(width: width, height: height))
        let count = max(Int((seconds * Double(fps)).rounded()), 1)
        for index in 0..<count {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? Failure.unreadable }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw Failure.unreadable }
            VideoRenderContext.shared.render(frame, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw writer.error ?? Failure.unreadable
        }
        return url
    }

    /// The picture at `url` as a still video.
    static func stillVideo(fromPicture url: URL, size: CGSize, seconds: Double) async throws -> URL {
        guard let picture = VideoImageOverlayRenderer.picture(path: url.path) else { throw Failure.unreadable }
        return try await stillVideo(picture, size: size, seconds: seconds)
    }

    static func fitted(_ image: CIImage, into size: CGSize) -> CIImage {
        let extent = image.extent
        let black = CIImage(color: CIColor.black).cropped(to: CGRect(origin: .zero, size: size))
        guard extent.width > 0, extent.height > 0 else { return black }
        let scale = min(size.width / extent.width, size.height / extent.height)
        let placed = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: (size.width - extent.width * scale) / 2, y: (size.height - extent.height * scale) / 2))
        return placed.composited(over: black).cropped(to: black.extent)
    }
}

// MARK: - Removing the ones nothing uses

extension VideoGeneratedMedia {
    /// Every video LF Studios made that's still on disk.
    static func all() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: VideoAssetStore.folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    /// Removes the made videos nothing uses: not `inUse` (open editors,
    /// their undo and redo, closed editors' kept history, queued exports),
    /// and no saved draft names them. Returns what was removed.
    @discardableResult
    static func removeUnused(inUse: Set<String>, draftTexts: [String]) -> [URL] {
        let kept = Set(inUse.map { URL(fileURLWithPath: $0).lastPathComponent })
        var removed: [URL] = []
        for url in all() {
            let name = url.lastPathComponent
            guard !kept.contains(name), !draftTexts.contains(where: { $0.contains(name) }) else { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil { removed.append(url) }
        }
        return removed
    }

    /// The saved drafts' text (each names the files its edit uses).
    static func draftTexts() -> [String] {
        let folder = VideoDemoDraftStore.directory()
        return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

// MARK: - Reversed clips

extension VideoGeneratedMedia {
    /// `url` from `start` to `end` (its own seconds) played backwards, its
    /// sound too. Read half a second at a time from the end, so a long clip
    /// never sits in memory whole.
    static func reversedVideo(of url: URL, from start: Double, to end: Double, progress: @escaping @Sendable (Double) -> Void = { _ in }, cancel: CancellationFlag = CancellationFlag()) async throws -> URL {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.unreadable }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let nominal = Double(try await track.load(.nominalFrameRate))
        let fps = nominal > 1 ? nominal : 30
        let length = end - start
        guard length > 0.05 else { throw Failure.unreadable }

        let silent = try newURL()
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.unreadable }
        writer.startSession(atSourceTime: .zero)

        let chunk = 0.5
        var chunkEnd = end
        var index = 0
        while chunkEnd > start + 0.0001 {
            if cancel.isSet {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: silent)
                throw Failure.cancelled
            }
            let chunkStart = max(chunkEnd - chunk, start)
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = CMTimeRange(start: CMTime(seconds: max(chunkStart - 0.5, 0), preferredTimescale: 600), end: CMTime(seconds: chunkEnd, preferredTimescale: 600))
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? Failure.unreadable }
            var frames: [CVPixelBuffer] = []
            while let sample = output.copyNextSampleBuffer() {
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard time >= chunkStart - 0.0005, time < chunkEnd - 0.0005, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                frames.append(buffer)
            }
            reader.cancelReading()
            for buffer in frames.reversed() {
                while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
                adaptor.append(buffer, withPresentationTime: CMTime(seconds: Double(index) / fps, preferredTimescale: 600))
                index += 1
            }
            chunkEnd = chunkStart
            progress(min((end - chunkEnd) / length * 0.9, 0.9))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed, index > 0 else {
            try? FileManager.default.removeItem(at: silent)
            throw writer.error ?? Failure.unreadable
        }

        // The sound, backwards, put next to it.
        guard let sound = try await asset.loadTracks(withMediaType: .audio).first else {
            progress(1)
            return silent
        }
        let samples = try readSound(asset: asset, track: sound, start: start, end: end)
        guard !samples.isEmpty else {
            progress(1)
            return silent
        }
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        try writeReversed(samples, to: audioURL)
        let combined = try newURL()
        let composition = AVMutableComposition()
        let silentAsset = AVURLAsset(url: silent)
        let audioAsset = AVURLAsset(url: audioURL)
        if let video = try await silentAsset.loadTracks(withMediaType: .video).first,
           let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let duration = try await silentAsset.load(.duration)
            try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: video, at: .zero)
            videoTrack.preferredTransform = try await video.load(.preferredTransform)
            if let audio = try await audioAsset.loadTracks(withMediaType: .audio).first,
               let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let audioDuration = try await audioAsset.load(.duration)
                try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: audio, at: .zero)
            }
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw Failure.unreadable }
        session.outputURL = combined
        session.outputFileType = .mov
        await session.export()
        try? FileManager.default.removeItem(at: silent)
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: combined)
            throw session.error ?? Failure.unreadable
        }
        progress(1)
        return combined
    }

    /// Stereo 48 kHz float samples of `start…end`.
    private static func readSound(asset: AVURLAsset, track: AVAssetTrack, start: Double, end: Double) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 48_000), end: CMTime(seconds: end, preferredTimescale: 48_000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure.unreadable }
        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { samples.append(contentsOf: UnsafeBufferPointer(start: $0, count: length / 4)) }
        }
        return samples
    }

    /// Interleaved stereo `samples`, last frame first, as AAC.
    private static func writeReversed(_ samples: [Float], to url: URL) throws {
        let frames = samples.count / 2
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000],
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let block = 48_000
        var written = 0
        while written < frames {
            let count = min(block, frames - written)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { break }
            buffer.frameLength = AVAudioFrameCount(count)
            for i in 0..<count {
                let source = frames - 1 - (written + i)
                buffer.floatChannelData![0][i] = samples[source * 2]
                buffer.floatChannelData![1][i] = samples[source * 2 + 1]
            }
            try file.write(from: buffer)
            written += count
        }
    }
}

// MARK: - In the editor

/// A video being made for the main track (Reverse, Freeze frame): what it
/// is, how far along, and its Cancel.
struct VideoGenerationJob: Equatable {
    let id = UUID()
    let title: String
    var progress: Double
    let cancel: CancellationFlag

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.progress == b.progress }
}

extension VideoEditorModel {
    /// Freeze frame: the main track's frame under the playhead held for 3
    /// seconds there (the clip splits around it).
    func freezeFrame(seconds: Double = 3) async {
        if refuseLocked(.clips) { return }
        let time = clock.time
        guard let segment = segment(atTimeline: time) else { return }
        let location = sourceFrameLocation(at: segment.sourceTime(forTimelineTime: time))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: location.url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let frame = try? await generator.image(at: CMTime(seconds: location.time, preferredTimescale: 600)).image else {
            showNotice(L("Couldn't read that frame"), symbol: "exclamationmark.triangle.fill")
            return
        }
        let image = CIImage(cgImage: frame)
        guard let url = try? await VideoGeneratedMedia.stillVideo(image, size: image.extent.size, seconds: seconds) else {
            showNotice(L("Couldn't make the freeze frame"), symbol: "exclamationmark.triangle.fill")
            return
        }
        if await insertOnMainTrack(url, at: time) != nil {
            renameLastSource(L("Freeze frame"))
            joinLastUndoSteps(label: "Freeze Frame")
            showNotice(L("Freeze frame added — 3 seconds"), symbol: "snowflake")
        }
    }

    /// Reverse: the selected clip above the main track, or the main
    /// track's clip (selected, or under the playhead), plays backwards.
    func reverseSelection() async {
        guard generating == nil else { return }
        let cancel = CancellationFlag()
        if let item = selectedLayerItem {
            guard item.isVideo else {
                showNotice(L("Pictures can't be reversed"), symbol: "arrow.uturn.left.circle")
                return
            }
            guard let url = await generate(L("Reversing “\(item.name)”…"), cancel: cancel, { progress in
                try await VideoGeneratedMedia.reversedVideo(of: URL(fileURLWithPath: item.path), from: item.fileStart, to: item.fileEnd, progress: progress, cancel: cancel)
            }) else { return }
            let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? item.fileLength
            setLayerItem(item.id, label: "Reverse") { reversed in
                reversed.path = url.path
                reversed.fileStart = 0
                reversed.fileDuration = duration
            }
            return
        }
        if refuseLocked(.clips) { return }
        guard let segment = targetClip else { return }
        let clip = segment.clip
        let first = sourceFrameLocation(at: clip.sourceStart)
        let last = sourceFrameLocation(at: max(clip.sourceEnd - 0.01, clip.sourceStart))
        guard first.url == last.url else {
            showNotice(L("Split the clip where one recording meets the next, then reverse each part"), symbol: "arrow.uturn.left.circle")
            return
        }
        guard let url = await generate(L("Reversing clip…"), cancel: cancel, { progress in
            try await VideoGeneratedMedia.reversedVideo(of: first.url, from: first.time, to: first.time + clip.sourceDuration, progress: progress, cancel: cancel)
        }) else { return }
        let before = Set(project.sources.map(\.id))
        guard await appendVideo(url), let source = project.sources.last(where: { !before.contains($0.id) && !$0.isPrimary }) else { return }
        let total = sourceDuration
        mutate(label: "Reverse") { project in
            var clips = project.normalizedTimelineClips(totalDuration: total)
            guard let index = clips.firstIndex(where: { $0.id == clip.id }),
                  let added = clips.lastIndex(where: { $0.sourceStart >= source.offset - 0.001 }) else { return }
            var reversed = clips.remove(at: added)
            reversed.speed = clip.speed
            reversed.muted = clip.muted
            reversed.mirrored = clip.mirrored
            reversed.quarterTurns = clip.quarterTurns
            reversed.fadeIn = clip.fadeIn
            reversed.fadeOut = clip.fadeOut
            clips[index] = reversed
            project.timelineClips = clips
            project.syncTrimToTimeline(totalDuration: total)
            if let s = project.sources.firstIndex(where: { $0.id == source.id }) {
                project.sources[s].name = L("\(URL(fileURLWithPath: first.url.path).deletingPathExtension().lastPathComponent) (reversed)")
            }
        }
        joinLastUndoSteps(label: "Reverse")
        showNotice(L("Clip reversed — ⌘Z to undo"), symbol: "arrow.uturn.left.circle")
    }

    /// Runs `work` with the progress pill and its Cancel showing.
    private func generate(_ title: String, cancel: CancellationFlag, _ work: (@escaping @Sendable (Double) -> Void) async throws -> URL) async -> URL? {
        generating = VideoGenerationJob(title: title, progress: 0, cancel: cancel)
        defer { generating = nil }
        do {
            return try await work { value in
                Task { @MainActor [weak self] in self?.generating?.progress = value }
            }
        } catch VideoGeneratedMedia.Failure.cancelled {
            showNotice(L("Cancelled"), symbol: "xmark.circle")
        } catch {
            showNotice(L("Couldn't reverse it — \(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill", duration: 5)
        }
        return nil
    }

    /// Made videos on the main track that no clip plays any more (a deleted
    /// freeze frame, a reversed clip cut away) leave the project; one ⌘Z
    /// brings them back. Their files go once nothing uses them.
    func dropUnusedGeneratedSources() {
        let unused = project.sources.filter { source in
            !source.isPrimary && VideoGeneratedMedia.isGenerated(source.path)
                && !project.timelineClips.contains { $0.sourceEnd > source.offset + 0.001 && $0.sourceStart < source.end - 0.001 }
        }
        guard !unused.isEmpty else { return }
        mutate(label: "Remove Recording") { project in
            for source in unused { _ = project.removeSource(id: source.id) }
        }
        Task { await reloadSources() }
    }

    private func renameLastSource(_ name: String) {
        guard let index = project.sources.indices.last, !project.sources[index].isPrimary else { return }
        mutate(label: "Freeze Frame") { $0.sources[index].name = name }
    }
}

/// The pill under the toolbar while a reversed clip is made.
struct VideoGenerationPill: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        if let job = model.generating {
            HStack(spacing: 10) {
                ProgressView(value: job.progress).frame(width: 90)
                Text(job.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                    .lineLimit(1)
                Button(L("Cancel")) { job.cancel.set() }
                    .buttonStyle(VideoSecondaryButtonStyle())
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Capsule().fill(VideoEditorTheme.floatingPill))
            .shadow(color: VideoEditorTheme.shadow, radius: 10, y: 4)
        }
    }
}
