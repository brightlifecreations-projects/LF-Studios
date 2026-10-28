import AppKit
import SwiftUI

/// In the Captions tab: Apple or Whisper, and for Whisper the model, its
/// download, and "Transcribe with Whisper".
struct VideoCaptionEngineControls: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var whisper = VideoWhisperModels.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L("Engine"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                Spacer()
                VideoSegmented(options: VideoCaptionEngine.allCases.map { ($0, $0.title) }, selection: $whisper.engine)
                    .frame(width: 150)
            }
            if whisper.engine == .whisper {
                whisperRows
            }
        }
    }

    @ViewBuilder
    private var whisperRows: some View {
        HStack(spacing: 8) {
            Text(L("Model"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(VideoEditorTheme.textSecondary)
            Spacer()
            Menu {
                ForEach(VideoWhisperModel.allCases) { choice in
                    Button {
                        whisper.selected = choice
                    } label: {
                        let title = "\(choice.title) — \(choice.detail), \(choice.sizeText)" + (whisper.installed.contains(choice) ? "" : " · " + L("not downloaded")) // l10n-ignore: translated parts joined with punctuation
                        if choice == whisper.selected { Label(title, systemImage: "checkmark") } else { Text(title) }
                    }
                }
            } label: {
                Text(verbatim: "\(whisper.selected.title) · \(whisper.selected.sizeText)")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(whisper.download != nil)
        }
        if let warning = VideoWhisperModels.unsuitability(of: whisper.selected) {
            Label(warning.message, systemImage: "tortoise.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            if let smaller = warning.suggestion {
                Button(L("Use \(smaller.title)")) { whisper.selected = smaller }
                    .buttonStyle(VideoSecondaryButtonStyle())
            }
        }
        if let download = whisper.download {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(L("Downloading \(download.model.title)…"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Spacer()
                    Text(VideoEditorFormat.percent(download.fraction))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                }
                ProgressView(value: download.fraction).progressViewStyle(.linear).tint(VideoEditorTheme.caption)
                Button(L("Cancel")) { whisper.cancelDownload() }
                    .buttonStyle(VideoSecondaryButtonStyle())
            }
        } else if !whisper.installed.contains(whisper.selected) {
            Text(L("Whisper runs on this Mac. The model is downloaded once from Hugging Face; your recording is never uploaded."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                whisper.startDownload(whisper.selected)
            } label: {
                Label(L("Download \(whisper.selected.title) (\(whisper.selected.sizeText))"), systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
        }
        if let error = whisper.downloadError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Settings → General: the downloaded Whisper models, and Delete.
struct WhisperModelsSettingsSection: View {
    @ObservedObject var whisper = VideoWhisperModels.shared

    var body: some View {
        PreferenceSection(L("Whisper Models")) {
            ForEach(Array(VideoWhisperModel.allCases.enumerated()), id: \.element) { index, choice in
                if index > 0 { PreferenceDivider() }
                PreferenceRow(choice.title, detail: detail(choice)) {
                    if whisper.download?.model == choice {
                        HStack(spacing: 8) {
                            ProgressView(value: whisper.download?.fraction ?? 0)
                                .frame(width: 80)
                            Button(L("Cancel")) { whisper.cancelDownload() }
                        }
                    } else if whisper.installed.contains(choice) {
                        Button(L("Delete")) { confirmDelete(choice) }
                    } else {
                        Button(L("Download")) { whisper.startDownload(choice) }
                            .disabled(whisper.download != nil)
                    }
                }
            }
        }
        .onAppear { whisper.refresh() }
        PreferenceFootnote(text: L("For captions with the Whisper engine. Models are downloaded from Hugging Face only when you choose one; transcribing happens on this Mac and nothing is uploaded."))
    }

    private func detail(_ choice: VideoWhisperModel) -> String {
        if whisper.installed.contains(choice) {
            return L("Downloaded · \(ByteCountFormatter.string(fromByteCount: VideoWhisperModels.bytesOnDisk(choice), countStyle: .file)) on this Mac")
        }
        return L("\(choice.detail) · about \(choice.sizeText)")
    }

    private func confirmDelete(_ choice: VideoWhisperModel) {
        let alert = NSAlert()
        alert.messageText = L("Delete the \(choice.title) model?")
        alert.informativeText = L("Captions already made stay. To use this model again, download it again.")
        alert.addButton(withTitle: L("Delete"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { whisper.delete(choice) }
    }
}
