import AppKit
import CoreImage
import CryptoKit

// MARK: - Performance (1.15.0)

/// The timeline's filmstrip and waveform, kept on disk so a recording opens
/// with them at once the next time (made again when the file changes).
/// Clean Up removes them; they're made again when needed.
enum VideoTimelineCache {
    nonisolated(unsafe) static var folderOverride: URL?

    static var folder: URL {
        folderOverride ?? VideoStorageLocation.root
            .appendingPathComponent("LF Studios", isDirectory: true)
            .appendingPathComponent("VideoTimelineCache", isDirectory: true)
    }

    private static func key(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        // A fresh URL: a URL keeps the values it read once (a changed file
        // would keep its old name).
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let stamp = "\(path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        return SHA256.hash(data: Data(stamp.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private struct Filmstrip: Codable {
        var times: [Double]
        var pictures: [Data]
    }

    static func thumbnailsURL(for url: URL, count: Int) -> URL { folder.appendingPathComponent("\(key(url))-\(count).filmstrip") }
    static func waveformURL(for url: URL) -> URL { folder.appendingPathComponent("\(key(url)).waveform") }

    static func thumbnails(for url: URL, count: Int) -> [VideoTimelineThumbnail]? {
        guard let data = try? Data(contentsOf: thumbnailsURL(for: url, count: count)),
              let strip = try? PropertyListDecoder().decode(Filmstrip.self, from: data), strip.times.count == strip.pictures.count, !strip.times.isEmpty else { return nil }
        var thumbnails: [VideoTimelineThumbnail] = []
        for (time, picture) in zip(strip.times, strip.pictures) {
            guard let image = NSImage(data: picture) else { return nil }
            thumbnails.append(VideoTimelineThumbnail(time: time, image: image))
        }
        return thumbnails
    }

    static func save(_ thumbnails: [VideoTimelineThumbnail], for url: URL, count: Int) {
        var strip = Filmstrip(times: [], pictures: [])
        for thumbnail in thumbnails {
            guard let cg = thumbnail.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let jpeg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { continue }
            strip.times.append(thumbnail.time)
            strip.pictures.append(jpeg)
        }
        guard !strip.times.isEmpty, let data = try? PropertyListEncoder().encode(strip) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: thumbnailsURL(for: url, count: count), options: .atomic)
    }

    static func waveform(for url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: waveformURL(for: url)), !data.isEmpty, data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    static func save(waveform peaks: [Float], for url: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = peaks.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: waveformURL(for: url), options: .atomic)
    }

    static var files: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { ["filmstrip", "waveform"].contains($0.pathExtension) }
    }
}

/// Background rendering: the slow, cachable parts of what's coming up
/// (text and sticker pictures, LUTs of filters and adjustments, GIF
/// frames) are made ahead of the playhead, off the main thread, so playback
/// only composites.
enum VideoRenderWarmup {
    private static let queue = DispatchQueue(label: "lfstudios.render-warmup", qos: .utility)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: DispatchWorkItem?

    /// What would need making for the clips showing from `time` for
    /// `seconds`, on an output `height` pixels high.
    static func jobs(for project: VideoDemoProject, from time: Double, seconds: Double = 8, height: CGFloat) -> [() -> Void] {
        var jobs: [() -> Void] = []
        let canvas = project.canvasSize()
        let output = CGSize(width: height * canvas.width / max(canvas.height, 1), height: height)
        for (_, item) in project.layerItems where item.enabled && item.end > time && item.at < time + seconds {
            if let text = item.text {
                let h = item.rect(in: output).height
                jobs.append { _ = VideoTextClipRenderer.image(text, pixelHeight: h) }
            }
            if let sticker = item.sticker {
                let h = item.rect(in: output).height
                jobs.append { _ = VideoStickerRenderer.image(sticker, pixelHeight: h) }
            }
            if let adjust = item.adjust, !adjust.colourIsNeutral { jobs.append { _ = VideoAdjustRenderer.cube(adjust) } }
            if let filter = item.filter { jobs.append { _ = VideoFilterRenderer.cube(for: filter) } }
            if item.hasFile, !item.isVideo, item.path.lowercased().hasSuffix(".gif") {
                let path = item.path
                jobs.append { _ = VideoGIF.load(path) }
            } else if item.hasFile, !item.isVideo {
                let path = item.path
                jobs.append { _ = VideoImageOverlayRenderer.picture(path: path) }
            }
        }
        return jobs
    }

    /// Starts making them in the background (a newer call replaces an
    /// older one that hasn't started).
    static func warm(_ project: VideoDemoProject, from time: Double, seconds: Double = 8, height: CGFloat) {
        let work = jobs(for: project, from: time, seconds: seconds, height: height)
        guard !work.isEmpty else { return }
        let item = DispatchWorkItem { for job in work { job() } }
        lock.lock()
        pending?.cancel()
        pending = item
        lock.unlock()
        queue.async(execute: item)
    }

    /// Waits for the background work (tests).
    static func wait() { queue.sync {} }
}

/// Cache keys from a value's JSON: keys sorted, or two encodings of the
/// same value could differ (and every lookup would miss).
enum VideoCacheKey {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}
