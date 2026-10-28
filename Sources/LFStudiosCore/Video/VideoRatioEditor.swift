import AppKit
import SwiftUI

// MARK: - Adapt to this ratio, Export all ratios

extension VideoEditorModel {
    /// After a switch to a ratio that has no version of its own yet.
    var canAdaptRatio: Bool {
        guard let previous = project.previousRatio else { return false }
        return previous != project.aspectPreset && !project.isAdaptedRatio
    }

    func adaptToRatio() {
        var report = VideoRatioAdaptReport()
        let hasCursor = !project.cursorSamples.isEmpty || !(recording?.cursorSamples.isEmpty ?? true)
        mutate(label: "Adapt to This Ratio") { project in
            report = project.adaptToCurrentRatio(hasCursor: hasCursor)
        }
        var parts: [String] = []
        if report.zooms > 0 { parts.append(L("\(report.zooms) zooms")) }
        if report.movedCamera, project.activeCamera(recorded: recording?.webcam) != nil { parts.append(L("the camera")) }
        if report.captions > 0 { parts.append(L("captions")) }
        let title = project.aspectPreset.title
        showNotice(parts.isEmpty ? L("\(title) has its own version now") : L("Adapted to \(title): \(parts.joined(separator: ", "))"), symbol: project.aspectPreset.symbol, duration: 3.5)
    }

    /// File name part for a ratio: "9x16".
    static func ratioFileTag(_ preset: VideoDemoProject.AspectPreset) -> String {
        preset == .source ? L("Original shape") : preset.title.replacingOccurrences(of: ":", with: "x")
    }

    /// Every adapted ratio (and the one they started from), each its own
    /// export in the queue, into one folder.
    func exportAllRatios() {
        let ratios = project.ratiosToExport
        guard ratios.count > 1 else { return }
        followRenamedRecording()
        var settings = exportSettings
        if settings.format.isAudioOnly || settings.format == .gif { settings.format = .mp4 }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Export Here")
        panel.message = L("Exports \(ratios.map(\.title).joined(separator: ", ")) into this folder.")
        panel.directoryURL = URL(fileURLWithPath: Settings.recordingFolder, isDirectory: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        playback.pause()
        var base = project
        if base.cursorSamples.isEmpty, let recording { base.cursorSamples = recording.cursorSamples }
        for preset in ratios {
            let destination = folder.appendingPathComponent("\(exportBaseName) – \(Self.ratioFileTag(preset)).\(settings.fileExtension)")
            _ = VideoExportQueue.shared.enqueue(project: base.version(for: preset), recording: recording, settings: settings, destination: destination, toClipboard: false)
        }
        showNotice(L("Exporting \(ratios.count) versions"), symbol: "square.stack.3d.up", duration: 3)
    }
}

/// Beside the ratio menu: Adapt right after a switch, then Export all
/// ratios once there's more than one version.
struct VideoRatioButtons: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        HStack(spacing: 6) {
            if model.canAdaptRatio {
                Button {
                    model.adaptToRatio()
                } label: {
                    Label(L("Adapt to this ratio"), systemImage: "wand.and.rays")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("Reframes zooms, moves the camera bubble, and keeps captions in the safe area for \(model.project.aspectPreset.title). This ratio then keeps its own version."))
            }
            if model.project.ratiosToExport.count > 1 {
                Button {
                    model.exportAllRatios()
                } label: {
                    Label(L("Export all ratios"), systemImage: "square.stack.3d.up")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("Exports \(model.project.ratiosToExport.map(\.title).joined(separator: ", ")) in one go"))
                .disabled(!model.isReady)
            }
        }
    }
}
