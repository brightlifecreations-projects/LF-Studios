import AppKit
import SwiftUI

extension VideoEditorModel {
    /// Podcast mode on (every step) or off: one ⌘Z step.
    func setPodcastMode(_ on: Bool) {
        mutate(label: on ? "Podcast Mode On" : "Podcast Mode Off") { project in
            project.audio.podcast = on ? VideoPodcastSettings() : nil
        }
        showNotice(on ? L("Podcast mode on — turn off any step you don't want") : L("Podcast mode off"), symbol: "mic")
    }

    func setPodcastStep(_ path: WritableKeyPath<VideoPodcastSettings, Bool>, _ on: Bool) {
        setStyle { project in
            project.audio.podcast?[keyPath: path] = on
        }
    }
}

/// The Audio tab's Podcast section: one button, then each step's switch.
struct VideoPodcastSection: View {
    @ObservedObject var model: VideoEditorModel

    private func step(_ title: String, _ detail: String, _ path: WritableKeyPath<VideoPodcastSettings, Bool>) -> some View {
        VideoToggleRow(
            title: title,
            detail: detail,
            isOn: Binding(get: { model.project.audio.podcast?[keyPath: path] ?? false }, set: { model.setPodcastStep(path, $0) })
        )
    }

    var body: some View {
        VideoInspectorSection(L("Podcast")) {
            if model.project.audio.podcast == nil {
                Button {
                    model.setPodcastMode(true)
                } label: {
                    Label(L("Podcast mode"), systemImage: "mic")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .disabled(!model.hasAudio)
                Text(L("A voice chain for spoken audio: noise removal, de-essing, a warm and clear EQ, compression, and the podcast loudness standard. Each step can be turned off. Processed on this Mac."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                step(L("Noise removal"), L("Removes room noise and hum, and quiets the room between words"), \.noiseRemoval)
                step(L("De-esser"), L("Softens sharp “s” and “sh” sounds"), \.deEsser)
                step(L("Warm and clear EQ"), L("Less rumble and boom, more presence"), \.equalizer)
                step(L("Compression"), L("Keeps loud and quiet words close together"), \.compressor)
                step(L("Podcast loudness"), L("The whole mix at −16 LUFS, peaks under −1 dB"), \.loudness)
                Button {
                    model.setPodcastMode(false)
                } label: {
                    Text(L("Turn off podcast mode"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            }
        }
    }
}

/// The speaker notes read while recording (kept with the project).
struct VideoSpeakerNotesCard: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        if let notes = model.project.speakerNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VideoInspectorSection(L("Speaker notes")) {
                ScrollView {
                    Text(notes)
                        .font(.system(size: 11.5))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(notes, forType: .string)
                    model.showNotice(L("Speaker notes copied"), symbol: "doc.on.clipboard")
                } label: {
                    Label(L("Copy notes"), systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                Text(L("The notes you read while recording. They're saved with the project, and go into Creative Handoff only when you choose."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
