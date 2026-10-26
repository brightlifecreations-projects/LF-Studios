import AppKit
import AVFoundation
import SwiftUI

/// Camera footage filmed apart from the recording (a phone, a camera),
/// added in the Camera panel. It's linked, not copied: the project keeps
/// its path and a bookmark to find it after a move. It takes the place of
/// the camera recorded with the video, and every camera setting applies.
struct VideoImportedCamera: Codable, Equatable {
    var path: String
    var bookmark: Data?
    /// Seconds the footage starts after the recording (negative: before).
    /// Footage time = recording time − offset.
    var offset: Double
    var width: Double
    var height: Double
    var duration: Double

    static let offsetRange: ClosedRange<Double> = -3600...3600

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }

    /// As the renderer and exporter take camera footage.
    var recording: VideoWebcamRecording {
        VideoWebcamRecording(path: path, offset: offset, width: width, height: height)
    }

    /// Where it is now: its path, or wherever its bookmark leads.
    func resolved() -> URL? {
        if FileManager.default.fileExists(atPath: path) { return url }
        guard let bookmark else { return nil }
        var stale = false
        guard let found = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: found.path) else { return nil }
        return found
    }

    /// A video's size (upright) and length; nil when it has no picture.
    static func read(_ url: URL, offset: Double = 0) async -> VideoImportedCamera? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0.2,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return nil }
        let upright = natural.applying(transform)
        return VideoImportedCamera(
            path: url.standardizedFileURL.path,
            bookmark: VideoSourceLocator.bookmark(for: url),
            offset: offset,
            width: abs(Double(upright.width)),
            height: abs(Double(upright.height)),
            duration: duration
        )
    }
}

extension VideoDemoProject {
    /// The camera footage the video shows: added footage first, else the
    /// camera recorded with it.
    func activeCamera(recorded: VideoWebcamRecording?) -> VideoWebcamRecording? {
        importedCamera?.recording ?? recorded
    }

    /// Imported footage found at a new place (by its bookmark) is used
    /// from there (not an edit).
    mutating func relocateImportedCamera() {
        guard let camera = importedCamera, !FileManager.default.fileExists(atPath: camera.path), let found = camera.resolved() else { return }
        importedCamera?.path = found.standardizedFileURL.path
    }
}

extension VideoCameraSource {
    /// The same footage at another offset (no reload while nudging).
    func moved(to offset: Double) -> VideoCameraSource {
        VideoCameraSource(asset: asset, track: track, duration: duration, size: size, offset: offset)
    }
}

// MARK: - Editor

extension VideoEditorModel {
    /// The imported footage's file, when it can't be found.
    var missingImportedCamera: VideoImportedCamera? {
        guard let camera = project.importedCamera, camera.resolved() == nil else { return nil }
        return camera
    }

    /// File ▸ Add camera video… (and Replace…).
    func chooseCameraVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = L("Choose the camera video to show in the bubble")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await addCameraVideo(url) }
    }

    /// Links `url` as the camera footage. A replacement keeps the offset;
    /// new footage is lined up by its sound when it can be.
    @discardableResult
    func addCameraVideo(_ url: URL, autoSync: Bool = true) async -> Bool {
        let replacing = project.importedCamera
        guard var camera = await VideoImportedCamera.read(url, offset: replacing?.offset ?? 0) else {
            showNotice(L("That video has no picture to show"), symbol: "exclamationmark.triangle.fill")
            return false
        }
        let missing = replacing.map { $0.resolved() == nil } ?? false
        if replacing == nil || missing, autoSync {
            isSyncingCamera = true
            if case .success(let match) = await VideoAudioSync.match(reference: project.sourceURL, other: url) {
                camera.offset = Self.clampedCameraOffset(match.offset)
            }
            isSyncingCamera = false
        }
        mutate(label: replacing == nil ? "Add Camera Video" : "Replace Camera Video") { project in
            project.importedCamera = camera
            project.webcam.visible = true
        }
        showNotice(L("Camera video: \(camera.name)"), symbol: "video.fill")
        return true
    }

    func removeCameraVideo() {
        guard project.importedCamera != nil else { return }
        mutate(label: "Remove Camera Video") { $0.importedCamera = nil }
        showNotice(L("Camera video removed — ⌘Z to undo"), symbol: "trash")
    }

    /// The Locate… button: the same footage, found somewhere else.
    func locateCameraVideo() {
        guard let missing = project.importedCamera else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = L("Find “\(missing.name)”")
        panel.directoryURL = missing.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await addCameraVideo(url, autoSync: false) }
    }

    static func clampedCameraOffset(_ offset: Double) -> Double {
        min(max(offset, VideoImportedCamera.offsetRange.lowerBound), VideoImportedCamera.offsetRange.upperBound)
    }

    /// From the offset field, the nudge buttons, and the timeline strip.
    func setCameraOffset(_ offset: Double, coalesce: String? = nil) {
        guard project.importedCamera != nil else { return }
        let value = Self.clampedCameraOffset((offset * 1000).rounded() / 1000)
        guard abs(value - (project.importedCamera?.offset ?? 0)) > 0.0001 else { return }
        mutate(coalesce: coalesce, label: "Camera Offset") { $0.importedCamera?.offset = value }
    }

    /// Lines the footage up with the recording by their sound.
    func syncCameraBySound() async {
        guard let camera = project.importedCamera, let url = camera.resolved() else { return }
        isSyncingCamera = true
        defer { isSyncingCamera = false }
        switch await VideoAudioSync.match(reference: project.sourceURL, other: url) {
        case .success(let match):
            setCameraOffset(match.offset)
            showNotice(L("Synced by sound — the camera starts \(Self.formatOffset(match.offset))"), symbol: "waveform")
        case .failure(.noSound):
            showNotice(L("Can't sync — the recording or the camera video has no sound"), symbol: "exclamationmark.triangle.fill", duration: 5)
        case .failure(.weakMatch):
            showNotice(L("Can't sync — their sound doesn't match clearly enough. Set the offset by hand."), symbol: "exclamationmark.triangle.fill", duration: 5)
        }
    }

    /// "0.70 s later", "1.20 s earlier", "in step".
    static func formatOffset(_ offset: Double) -> String {
        let amount = String(format: "%.2f", abs(offset))
        if abs(offset) < 0.005 { return L("in step with the recording") }
        return offset > 0 ? L("\(amount) s after the recording") : L("\(amount) s before the recording")
    }

    /// The camera footage in use, loaded for playback: called whenever the
    /// imported footage changes (added, replaced, removed, moved in time,
    /// undone).
    func cameraFootageDidChange(from old: VideoImportedCamera?) {
        guard isReady else { return }
        let now = project.importedCamera
        // Only nudged: the loaded footage moves, nothing reloads.
        if let now, let old, now.path == old.path, let loaded = playback.camera, loaded.asset.url.standardizedFileURL.path == now.path {
            playback.setCamera(loaded.moved(to: now.offset))
            cameraSourceReloaded()
            return
        }
        cameraLoad?.cancel()
        cameraLoad = Task {
            await reloadCamera()
        }
    }

    /// Loads the active camera (imported, else recorded) into playback.
    func reloadCamera() async {
        var camera: VideoCameraSource?
        if let active = project.activeCamera(recorded: webcamRecording), project.importedCamera.map({ $0.resolved() != nil }) ?? true {
            camera = await VideoCameraSource.load(active)
        }
        guard !Task.isCancelled else { return }
        playback.setCamera(camera)
        cameraSourceReloaded()
    }

    private func cameraSourceReloaded() {
        if project.hasAppendedSources {
            Task { await reloadSources() }
            return
        }
        applySourceDuration(sourceDuration, hasAudio: hasAudio, hasCamera: playback.camera != nil)
        refreshPlan()
        refreshPlayback()
    }
}

// MARK: - Camera panel

/// Add camera video…, Replace…, Remove, the offset, and Sync by Sound.
struct VideoCameraVideoSection: View {
    @ObservedObject var model: VideoEditorModel
    @State private var offsetText = ""
    @FocusState private var editingOffset: Bool

    static let nudges: [Double] = [-0.1, -0.01, 0.01, 0.1]

    var body: some View {
        if let missing = model.missingImportedCamera {
            VideoCard {
                Label(L("Camera video missing"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Text(L("“\(missing.name)” isn't in \(missing.url.deletingLastPathComponent().lastPathComponent) anymore. Locate it to get the camera back."))
                    .font(.system(size: 11))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(L("Locate…")) { model.locateCameraVideo() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                    Button(L("Remove")) { model.removeCameraVideo() }
                        .buttonStyle(VideoSecondaryButtonStyle(destructive: true))
                }
            }
        } else if let camera = model.project.importedCamera {
            VideoInspectorSection(L("Camera video")) {
                HStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                    Text(camera.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(camera.path)
                    Spacer(minLength: 4)
                    Button(L("Replace…")) { model.chooseCameraVideo() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                    Button(L("Remove")) { model.removeCameraVideo() }
                        .buttonStyle(VideoSecondaryButtonStyle(destructive: true))
                }
                HStack(spacing: 6) {
                    Text(L("Offset"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                        .fixedSize()
                    TextField("0.00", text: $offsetText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 6)
                        .frame(width: 64, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.3)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
                        .focused($editingOffset)
                        .onSubmit(commitOffset)
                        .onChange(of: editingOffset) { editing in if !editing { commitOffset() } }
                        .help(L("Seconds the camera video starts after the recording (negative: before)"))
                    Text(L("s"))
                        .font(.system(size: 11))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                    Spacer(minLength: 2)
                    ForEach(Self.nudges, id: \.self) { step in
                        Button(Self.nudgeTitle(step)) { model.setCameraOffset(camera.offset + step, coalesce: "camera-nudge") }
                            .buttonStyle(VideoSecondaryButtonStyle())
                            .help(step < 0 ? L("Camera earlier by \(Self.amount(step)) s") : L("Camera later by \(Self.amount(step)) s"))
                    }
                }
                Button {
                    Task { await model.syncCameraBySound() }
                } label: {
                    HStack(spacing: 6) {
                        if model.isSyncingCamera {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "waveform")
                        }
                        Text(model.isSyncingCamera ? L("Listening…") : L("Sync by Sound"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .disabled(model.isSyncingCamera)
                Text(L("Lines the camera up by the sound both recorded. Or drag the camera strip on the timeline."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear { offsetText = Self.format(camera.offset) }
            .onChange(of: camera.offset) { offset in if !editingOffset { offsetText = Self.format(offset) } }
        } else {
            addButton
        }
    }

    /// Footage from a phone or camera, shown in the bubble.
    var addButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.chooseCameraVideo()
            } label: {
                HStack(spacing: 6) {
                    if model.isSyncingCamera {
                        ProgressView().controlSize(.small)
                        Text(L("Listening…"))
                    } else {
                        Label(L("Add camera video…"), systemImage: "video.badge.plus")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .disabled(model.isSyncingCamera)
            Text(model.webcamRecording == nil
                ? L("Filmed yourself on a phone or camera? Add that video and it shows in the bubble, lined up by sound.")
                : L("Show a video from a phone or camera instead of the recorded camera, lined up by sound."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commitOffset() {
        guard let camera = model.project.importedCamera else { return }
        let typed = offsetText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if let value = Double(typed), value.isFinite {
            model.setCameraOffset(value)
        }
        offsetText = Self.format(model.project.importedCamera?.offset ?? camera.offset)
    }

    static func format(_ offset: Double) -> String { String(format: "%.2f", offset) }
    static func signed(_ offset: Double) -> String { String(format: "%+.2f", offset) }
    static func amount(_ step: Double) -> String { String(format: "%g", abs(step)) }
    static func nudgeTitle(_ step: Double) -> String { (step < 0 ? "−" : "+") + amount(step) }
}

// MARK: - Timeline strip

extension VideoTimelineMetrics {
    static let cameraFootageLaneHeight: CGFloat = 22
}

extension VideoEditorModel {
    /// Where the imported footage runs on the timeline (cut like the
    /// recording), at `offset`.
    func cameraFootageSpans(offset: Double) -> [ClosedRange<Double>] {
        guard let camera = project.importedCamera else { return [] }
        let start = max(offset, 0), end = min(offset + camera.duration, sourceDuration)
        guard end > start else { return [] }
        return VideoDemoProject.timelineRanges(sourceStart: start, sourceEnd: end, segments: segments)
    }
}

/// The imported camera footage under the clips: drag it sideways to move
/// the camera earlier or later against the recording.
struct VideoCameraFootageLane: View, Equatable {
    let camera: VideoImportedCamera
    let spans: [ClosedRange<Double>]
    let geometry: VideoTimelineGeometry
    let model: VideoEditorModel

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.camera == b.camera && a.spans == b.spans && a.geometry == b.geometry
    }

    /// The offset being dragged to (committed when the drag ends).
    @State private var dragOffset: Double?
    private typealias M = VideoTimelineMetrics

    var body: some View {
        let offset = dragOffset ?? camera.offset
        let shown = dragOffset == nil ? spans : model.cameraFootageSpans(offset: offset)
        Canvas { context, size in
            // The file name and the offset in seconds (a number, as typed in
            // the offset field).
            let label = (Text(Image(systemName: "video.fill")) + Text(verbatim: " \(camera.name)  \(VideoCameraVideoSection.signed(offset))"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
            guard !shown.isEmpty else {
                // Wholly outside the video: still there to drag back.
                let frame = CGRect(x: geometry.x(0) + 1, y: 0.5, width: max(geometry.width - M.inset * 2 - 2, 10), height: size.height - 1)
                let path = Path(roundedRect: frame, cornerRadius: 6, style: .continuous)
                context.stroke(path, with: .color(VideoEditorTheme.camera.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                context.draw(label, at: CGPoint(x: frame.minX + 8, y: frame.midY), anchor: .leading)
                return
            }
            for (index, span) in shown.enumerated() {
                let frame = CGRect(x: geometry.x(span.lowerBound) + 1, y: 0, width: max(CGFloat(span.upperBound - span.lowerBound) * geometry.pointsPerSecond - 2, 6), height: size.height)
                let path = Path(roundedRect: frame, cornerRadius: 6, style: .continuous)
                context.fill(path, with: .color(VideoEditorTheme.camera.opacity(dragOffset == nil ? 0.32 : 0.55)))
                context.stroke(path, with: .color(VideoEditorTheme.camera.opacity(0.8)), lineWidth: 1)
                if index == 0, frame.width > 60 {
                    var inner = context
                    inner.clip(to: path)
                    inner.draw(label, at: CGPoint(x: frame.minX + 8, y: frame.midY), anchor: .leading)
                }
            }
        }
        .frame(width: geometry.width, height: M.cameraFootageLaneHeight)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let delta = Double(value.translation.width / geometry.pointsPerSecond)
                    dragOffset = VideoEditorModel.clampedCameraOffset(((camera.offset + delta) * 100).rounded() / 100)
                }
                .onEnded { _ in
                    if let dragOffset { model.setCameraOffset(dragOffset) }
                    dragOffset = nil
                }
        )
        .help(L("Camera video — drag to line it up with the recording"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Camera video “\(camera.name)”, \(VideoEditorModel.formatOffset(camera.offset))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.setCameraOffset(camera.offset + 0.1)
            case .decrement: model.setCameraOffset(camera.offset - 0.1)
            @unknown default: break
            }
        }
    }
}
