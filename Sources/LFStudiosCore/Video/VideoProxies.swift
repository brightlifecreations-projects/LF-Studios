import AppKit
import AVFoundation
import CryptoKit
import SwiftUI

// MARK: - Proxies (1.15.0)

/// Light copies of the videos for smooth editing: ProRes 422 Proxy at half
/// size, picture only (the sound plays from the original). Made only when
/// you click Create proxies; kept with LF Studios' caches on this Mac (never
/// in a project, a Creative Handoff or Include media); removed by Clean Up.
/// The editor shows them only with Edit with proxies on; exports always
/// read the originals. Another Mac without them just plays the originals.
enum VideoProxies {
    nonisolated(unsafe) static var folderOverride: URL?

    static var folder: URL {
        folderOverride ?? VideoStorageLocation.root
            .appendingPathComponent("LF Studios", isDirectory: true)
            .appendingPathComponent("VideoProxies", isDirectory: true)
    }

    /// Where the proxy of `original` is (named after the file's path, size
    /// and date, so a changed file gets a new one).
    static func url(for original: URL) -> URL {
        let path = original.standardizedFileURL.resolvingSymlinksInPath().path
        // A fresh URL: a URL keeps the values it read once (a changed file
        // would keep its old name).
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let stamp = "\(path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let digest = SHA256.hash(data: Data(stamp.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent("\(digest)-half.mov")
    }

    /// The proxy of `original`, if it's been made on this Mac.
    static func existing(for original: URL) -> URL? {
        let proxy = url(for: original)
        guard let size = try? proxy.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { return nil }
        return proxy
    }

    /// The videos a project plays (the recordings on the main track and the
    /// videos above it) that are on this Mac.
    static func originals(in project: VideoDemoProject) -> [URL] {
        var urls = [project.sourceURL]
        for source in project.sources where !source.isPrimary { if let url = VideoSourceLocator.resolve(source) { urls.append(url) } }
        urls += project.layerVideoPaths.map { URL(fileURLWithPath: $0) }
        var seen = Set<String>()
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) && seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Half the size, even numbers (a codec needs them).
    static func halfSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, (size.width / 4).rounded() * 2), height: max(2, (size.height / 4).rounded() * 2))
    }

    /// About how many bytes a proxy takes: ProRes 422 Proxy is about 45
    /// Mbit/s for 1920×1080 at 30 frames a second.
    static func estimatedBytes(size: CGSize, frameRate: Double, duration: Double) -> Int64 {
        let half = halfSize(size)
        let bitsPerSecond = 45_000_000 * Double(half.width * half.height) / (1920 * 1080) * max(frameRate, 1) / 29.97
        return Int64(bitsPerSecond / 8 * max(duration, 0))
    }

    static func estimatedBytes(for url: URL) async -> Int64 {
        guard let tracks = try? await VideoSourceTracks.load(url: url) else { return 0 }
        let natural = (try? await tracks.video.load(.naturalSize)) ?? tracks.size
        return estimatedBytes(size: natural, frameRate: tracks.frameRate, duration: tracks.duration)
    }

    /// Makes the proxy of `original` (picture only, same timing and turn).
    @discardableResult
    static func create(from original: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }, cancelled: @escaping @Sendable () -> Bool = { false }) async throws -> URL {
        let destination = url(for: original)
        if let done = existing(for: original) { return done }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: original, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoDemoExportError.missingVideoTrack }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let duration = max(try await asset.load(.duration).seconds, 0.001)
        let size = halfSize(natural)
        let partial = folder.appendingPathComponent("making-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: partial) }
        try await Task.detached(priority: .utility) {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_422YpCbCr8,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            let writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.proRes422Proxy,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
            ])
            input.expectsMediaDataInRealTime = false
            input.transform = transform
            writer.add(input)
            guard reader.startReading() else { throw reader.error ?? VideoDemoExportError.exportFailed(L("Couldn't read the video")) }
            guard writer.startWriting() else { throw writer.error ?? VideoDemoExportError.exportFailed(L("Couldn't write the proxy")) }
            writer.startSession(atSourceTime: .zero)
            var lastProgress = 0.0
            while let sample = output.copyNextSampleBuffer() {
                if cancelled() {
                    reader.cancelReading()
                    writer.cancelWriting()
                    throw VideoDemoExportError.cancelled
                }
                while !input.isReadyForMoreMediaData { usleep(2000) }
                guard input.append(sample) else { throw writer.error ?? VideoDemoExportError.exportFailed(L("Couldn't write the proxy")) }
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if time - lastProgress > 0.5 {
                    lastProgress = time
                    progress(min(time / duration, 1))
                }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed, reader.status == .completed else { throw writer.error ?? reader.error ?? VideoDemoExportError.exportFailed(L("Couldn't write the proxy")) }
        }.value
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        progress(1)
        return destination
    }

    /// `tracks` with the proxy's picture (the original's sound, size and
    /// length kept), when there is one.
    static func swapping(_ tracks: VideoSourceTracks) async -> VideoSourceTracks {
        guard let proxy = existing(for: tracks.asset.url),
              let proxyTracks = try? await VideoSourceTracks.load(url: proxy),
              abs(proxyTracks.duration - tracks.duration) < 0.25 else { return tracks }
        return VideoSourceTracks(asset: tracks.asset, video: proxyTracks.video, audio: tracks.audio, audioRanges: tracks.audioRanges,
                                 audioChannelCounts: tracks.audioChannelCounts, duration: tracks.duration, size: tracks.size,
                                 orientation: proxyTracks.orientation, frameRate: tracks.frameRate)
    }

    /// A video above the main track, from its proxy when there is one.
    static func layerFile(_ url: URL) async -> VideoLayerFile? {
        guard let original = await VideoLayerFile.load(url) else { return nil }
        guard let proxy = existing(for: url), let small = await VideoLayerFile.load(proxy), abs(small.duration - original.duration) < 0.25 else { return original }
        return VideoLayerFile(asset: original.asset, video: small.video, audio: original.audio, duration: original.duration)
    }
}

// MARK: - The editor

struct VideoProxyJob: Equatable {
    var done: Int
    var total: Int
    var progress: Double
}

extension VideoEditorModel {
    /// The videos still without a proxy here.
    var videosWithoutProxies: [URL] {
        VideoProxies.originals(in: project).filter { VideoProxies.existing(for: $0) == nil }
    }

    /// Create proxies: tells how much space they'll take, then makes them
    /// (one at a time, in the background). Edit with proxies turns on.
    func createProxies(confirm: Bool = true) async {
        guard proxyJob == nil else { return }
        let wanted = videosWithoutProxies
        guard !wanted.isEmpty else {
            showNotice(L("Every video here has a proxy"), symbol: "checkmark.circle.fill")
            if !usesProxies { setUsesProxies(true) }
            return
        }
        var bytes: Int64 = 0
        for url in wanted { bytes += await VideoProxies.estimatedBytes(for: url) }
        if confirm {
            let alert = NSAlert()
            alert.messageText = L("Create proxies for \(wanted.count) videos?")
            alert.informativeText = L("They take about \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) on this Mac (ProRes 422 Proxy at half size). The editor plays them instead of the originals; exports always use the originals. Clean Up in Settings removes them.")
            alert.addButton(withTitle: L("Create Proxies"))
            alert.addButton(withTitle: L("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let flag = proxyCancelFlag
        flag.value = false
        proxyJob = VideoProxyJob(done: 0, total: wanted.count, progress: 0)
        defer { proxyJob = nil }
        for (index, url) in wanted.enumerated() {
            do {
                try await VideoProxies.create(from: url, progress: { [weak self] p in
                    Task { @MainActor in self?.proxyJob?.progress = (Double(index) + p) / Double(wanted.count) }
                }, cancelled: { flag.value })
                proxyJob?.done = index + 1
            } catch VideoDemoExportError.cancelled {
                showNotice(L("Stopped making proxies"), symbol: "film.stack")
                return
            } catch {
                showNotice(L("Couldn't make a proxy of “\(url.lastPathComponent)”: \(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill", duration: 5)
            }
        }
        showNotice(L("Proxies ready — the editor plays them; exports use the originals"), symbol: "film.stack")
        setUsesProxies(true)
    }

    func cancelProxies() { proxyCancelFlag.value = true }

    /// Edit with proxies: the editor plays the proxies (where there are
    /// some); off, the originals.
    func setUsesProxies(_ on: Bool) {
        Settings.videoEditWithProxies = on
        usesProxies = on
        Task { await applyProxySetting() }
    }

    /// Swaps the editor's videos for their proxies or back.
    func applyProxySetting() async {
        guard let primary = playback.originalSource ?? playback.source else { return }
        playback.replaceSource(usesProxies ? await VideoProxies.swapping(primary) : primary, original: primary)
        media.layerFiles = [:]
        loadLayerFiles()
        if project.hasAppendedSources { await reloadSources() }
        refreshPlayback()
    }
}

/// The player's Proxies menu.
struct VideoProxyMenu: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        Menu {
            Toggle(L("Edit with Proxies"), isOn: Binding(get: { model.usesProxies }, set: { model.setUsesProxies($0) }))
            Button(L("Create Proxies…")) { Task { await model.createProxies() } }
                .disabled(model.proxyJob != nil)
            if model.proxyJob != nil {
                Button(L("Stop Making Proxies")) { model.cancelProxies() }
            }
        } label: {
            HStack(spacing: 4) {
                if let job = model.proxyJob {
                    ProgressView(value: job.progress).progressViewStyle(.circular).controlSize(.mini)
                } else {
                    Image(systemName: "film.stack")
                }
                Text(model.usesProxies ? L("Proxy") : L("Originals"))
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(model.usesProxies ? L("Playing lighter copies of the videos (exports use the originals)") : L("Proxies: lighter copies for smooth editing"))
        .accessibilityLabel(L("Proxies"))
    }
}
