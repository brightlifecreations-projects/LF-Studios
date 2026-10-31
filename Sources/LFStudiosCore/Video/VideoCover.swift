import AppKit
import AVFoundation
import SwiftUI

// MARK: - Cover (1.15.0)

/// The picture a video file shows before it plays (its artwork): a frame
/// of the video, or a picture of your own. Off until you pick one.
struct VideoCover: Codable, Equatable {
    /// A frame: timeline seconds.
    var time: Double?
    /// A picture: LF Studios' own copy.
    var imagePath: String?
}

enum VideoCoverEmbedder {
    /// JPEG of the finished video at `seconds`.
    static func frame(of url: URL, at seconds: Double) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        let time = CMTime(seconds: min(max(seconds, 0), max(duration - 0.05, 0)), preferredTimescale: 600)
        let image = try await generator.image(at: time).image
        guard let data = jpeg(image) else { throw VideoDemoExportError.exportFailed(L("Couldn't make the cover")) }
        return data
    }

    /// JPEG of a picture, no bigger than `size` on its long side.
    static func picture(_ path: String, longSide: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max(longSide, 64), kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        return jpeg(image)
    }

    static func jpeg(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }

    /// `jpeg` as the file's artwork. The movie is copied as it is (nothing
    /// is encoded again) with the artwork in its metadata.
    static func embed(_ jpeg: Data, into url: URL, fileType: AVFileType) async throws {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoDemoExportError.exportFailed(L("Couldn't add the cover"))
        }
        let item = AVMutableMetadataItem()
        item.identifier = fileType == .mp4 ? .iTunesMetadataCoverArt : .quickTimeMetadataArtwork
        item.value = jpeg as NSData
        item.dataType = kCMMetadataBaseDataType_JPEG as String
        let common = AVMutableMetadataItem()
        common.identifier = .commonIdentifierArtwork
        common.value = jpeg as NSData
        common.dataType = kCMMetadataBaseDataType_JPEG as String
        let existing = (try? await asset.load(.metadata)) ?? []
        session.metadata = existing.filter { $0.commonKey != .commonKeyArtwork } + [item, common]
        let partial = url.deletingLastPathComponent().appendingPathComponent(".cover-\(UUID().uuidString.prefix(8)).\(url.pathExtension)")
        session.outputURL = partial
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = fileType == .mp4
        await session.export()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: partial)
            throw session.error ?? VideoDemoExportError.exportFailed(L("Couldn't add the cover"))
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: partial)
    }

    /// The artwork a file carries (nil: none).
    static func artwork(of url: URL) async -> Data? {
        let items = (try? await AVURLAsset(url: url).load(.metadata)) ?? []
        for item in items where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue) { return data }
        }
        return nil
    }
}

extension VideoEditorModel {
    /// Cover ▸ This frame: the frame at the playhead. One ⌘Z step.
    func setCoverFrame(at time: Double? = nil) {
        let at = min(max(time ?? clock.time, 0), timelineDuration)
        mutate(label: "Cover") { $0.cover = VideoCover(time: at) }
    }

    /// Cover ▸ Picture…: your own picture (copied, like other pictures).
    func chooseCoverPicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setCoverPicture(url)
    }

    @discardableResult
    func setCoverPicture(_ url: URL) -> Bool {
        guard VideoImageOverlayRenderer.pixelSize(of: url) != nil, let stored = try? VideoAssetStore.importFile(url) else {
            showNotice(L("Couldn't open that picture"), symbol: "exclamationmark.triangle.fill")
            return false
        }
        mutate(label: "Cover") { $0.cover = VideoCover(imagePath: stored.path) }
        return true
    }

    func clearCover() {
        mutate(label: "Cover") { $0.cover = nil }
    }
}

/// The export window's Cover row.
struct VideoCoverRow: View {
    @ObservedObject var model: VideoEditorModel

    private enum Choice: Hashable { case none, frame, picture }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VideoSegmented(options: [(Choice.none, L("None")), (.frame, L("A frame")), (.picture, L("A picture"))], selection: Binding(
                get: { model.project.cover?.imagePath != nil ? .picture : model.project.cover?.time != nil ? .frame : .none },
                set: { choice in
                    switch choice {
                    case .none: model.clearCover()
                    case .frame: model.setCoverFrame()
                    case .picture: model.chooseCoverPicture()
                    }
                }
            ))
            if let time = model.project.cover?.time {
                HStack(spacing: 8) {
                    Text(L("The frame at \(VideoEditorModel.timecode(time))"))
                        .font(.system(size: 11))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                    Spacer()
                    Button(L("Use the playhead")) { model.setCoverFrame() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                        .disabled(abs(model.clock.time - time) < 0.01)
                }
            } else if let path = model.project.cover?.imagePath {
                HStack(spacing: 8) {
                    if let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(height: 34).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer()
                    Button(L("Choose…")) { model.chooseCoverPicture() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                }
            }
            Text(L("What Finder, QuickTime and video sites show before it plays."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
