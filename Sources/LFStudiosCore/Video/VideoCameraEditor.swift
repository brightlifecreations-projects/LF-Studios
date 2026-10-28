import AVFoundation
import CoreImage
import Foundation

/// The Camera panel's face tracking, silence blocks, and color. Each is a
/// button or a switch, each press one ⌘Z step.
extension VideoEditorModel {
    // MARK: Face tracking

    /// The camera video being used: imported footage, else the recorded one.
    var activeCameraURL: URL? {
        if let imported = project.importedCamera { return imported.resolved() }
        return webcamRecording.map(\.url).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    var hasFaceAnalysis: Bool { activeCameraURL.flatMap(VideoFaceStore.load(for:)) != nil }

    func faceCropPath() -> VideoFaceCropPath? {
        guard hasWebcamFootage, let settings = project.faceTracking, settings.enabled, let url = activeCameraURL else { return nil }
        let camera = project.activeCamera(recorded: webcamRecording)
        let key = "\(VideoFaceStore.key(for: url))|\(settings.smoothness)|\(settings.tightness)|\(project.webcam.shape.rawValue)|\(camera?.offset ?? 0)"
        if let cache = faceCropCache, cache.key == key { return cache.path }
        let path = VideoFaceCropPath.make(project: project, recordedCamera: webcamRecording)
        faceCropCache = (key, path)
        return path
    }

    /// "Keep face centered": analyzes the camera video once (cached), then
    /// turns tracking on.
    func keepFaceCentered() {
        guard faceAnalysisTask == nil else { return }
        guard hasWebcamFootage, let url = activeCameraURL else {
            showNotice(L("This video has no camera footage to track"), symbol: "video.slash")
            return
        }
        if let analysis = VideoFaceStore.load(for: url) {
            finishFaceAnalysis(analysis)
            return
        }
        faceAnalysisProgress = 0
        faceAnalysisTask = Task { @MainActor [weak self] in
            do {
                let analysis = try await Task.detached(priority: .userInitiated) {
                    try await VideoFaceAnalyzer.analyze(url: url) { fraction in
                        Task { @MainActor in self?.faceAnalysisProgress = fraction }
                    }
                }.value
                VideoFaceStore.save(analysis, for: url)
                self?.faceAnalysisProgress = nil
                self?.faceAnalysisTask = nil
                self?.finishFaceAnalysis(analysis)
            } catch {
                self?.faceAnalysisProgress = nil
                self?.faceAnalysisTask = nil
                if !(error is CancellationError) {
                    self?.showNotice(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    func cancelFaceAnalysis() {
        faceAnalysisTask?.cancel()
        faceAnalysisTask = nil
        faceAnalysisProgress = nil
        showNotice(L("Face tracking canceled"), symbol: "xmark.circle")
    }

    private func finishFaceAnalysis(_ analysis: VideoFaceAnalysis) {
        guard !analysis.faces.isEmpty else {
            showNotice(L("No face found in the camera video"), symbol: "face.dashed")
            return
        }
        mutate(label: "Keep Face Centered") { project in
            var settings = project.faceTracking ?? VideoFaceTracking()
            settings.enabled = true
            project.faceTracking = settings
        }
        let share = Double(analysis.faces.count) / Double(max(analysis.times.count, 1))
        showNotice(share > 0.95 ? L("The bubble now follows your face") : L("The bubble follows your face; where none was found it holds the last framing"), symbol: "face.smiling", duration: 3.2)
    }

    func setFaceTracking(coalesce: String? = nil, _ change: (inout VideoFaceTracking) -> Void) {
        mutate(coalesce: coalesce, label: "Face Tracking") { project in
            var settings = project.faceTracking ?? VideoFaceTracking()
            change(&settings)
            project.faceTracking = settings
        }
    }

    // MARK: Hide camera during silences

    func hideCameraDuringSilences(minimum: Double) {
        guard hasWebcamFootage else {
            showNotice(L("This video has no camera footage to hide"), symbol: "video.slash")
            return
        }
        guard VideoAudioKind.voiceTrackIndex(in: audioKinds) != nil else {
            showNotice(L("This video has no voice to listen for silences"), symbol: "waveform.slash")
            return
        }
        Task { @MainActor in
            await loadSpeech()
            let shift = project.primaryOffset
            let speech = (media.speech[""] ?? []).map { ($0.lowerBound + shift)...($0.upperBound + shift) }
            let duration = sourceDuration
            var count = 0
            mutate(label: "Hide Camera During Silences") { count = $0.hideCameraDuringSilences(speech: speech, duration: duration, minimum: minimum) }
            showNotice(count == 0 ? L("No silences that long") : L("Camera hidden in \(count) silences — ⌘Z to undo"), symbol: "video.slash", duration: 3)
        }
    }

    // MARK: Color

    func setCameraColor(coalesce: String? = nil, _ change: (inout VideoCameraColor) -> Void) {
        setStyle(coalesce: coalesce) { project in
            var color = project.webcam.color ?? VideoCameraColor()
            change(&color)
            color = color.clamped
            project.webcam.color = color.isNeutral ? nil : color
        }
    }

    func applyCameraLook(_ look: VideoCameraColor.Look) {
        setStyle { $0.webcam.color = look.color }
    }

    func resetCameraColor() {
        setStyle { $0.webcam.color = nil }
    }

    /// Suggests values from a few frames of the camera video.
    func autoAdjustCameraColor() {
        guard let url = activeCameraURL, !isAutoAdjustingColor else { return }
        isAutoAdjustingColor = true
        Task { @MainActor in
            defer { isAutoAdjustingColor = false }
            let measures = await Self.cameraMeasures(url: url)
            guard !measures.isEmpty else {
                showNotice(L("The camera video couldn't be read"), symbol: "exclamationmark.triangle.fill")
                return
            }
            let suggestion = VideoCameraColor.suggestion(from: measures)
            mutate(label: "Auto Adjust Camera Color") { project in
                project.webcam.color = suggestion.isNeutral ? nil : suggestion
            }
            showNotice(L("Camera color adjusted — tweak the sliders, or ⌘Z to undo"), symbol: "wand.and.stars")
        }
    }

    /// Five frames spread over the camera video.
    nonisolated static func cameraMeasures(url: URL) async -> [VideoCameraColor.Measure] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        var measures: [VideoCameraColor.Measure] = []
        for fraction in [0.1, 0.3, 0.5, 0.7, 0.9] {
            guard let image = try? await generator.image(at: CMTime(seconds: duration * fraction, preferredTimescale: 600)).image,
                  let measure = VideoCameraColor.Measure.of(CIImage(cgImage: image)) else { continue }
            measures.append(measure)
        }
        return measures
    }
}
