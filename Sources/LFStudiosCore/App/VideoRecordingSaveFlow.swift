import AppKit

/// After each recording: "Where do you want to save this recording?", then
/// the recording moves into a folder of its own there
/// (VideoRecordingFolder.swift). With asking off, or Cancel, it goes in the
/// Recording folder, laid out the same way: nothing is ever lost.
@MainActor
enum VideoRecordingSaveFlow {
    /// Returns where the recording is now (where it was, if it couldn't move).
    static func save(_ finished: FinishedRecording) async -> URL {
        let video = finished.url
        guard FileManager.default.fileExists(atPath: video.path) else {
            ToastWindow.show(message: finished.message, duration: 4, on: finished.screen)
            return video
        }
        let chosen = Settings.askWhereToSaveRecordings ? choose(name: video.deletingPathExtension().lastPathComponent) : nil
        let (parent, name) = destination(for: video, chosen: chosen)
        if chosen != nil { Settings.lastRecordingSaveFolder = parent.path }
        do {
            let result = try await VideoRecordingFolderWriter.organize(video: video, into: parent, name: name)
            let saved = L("Saved to “\(result.folder.lastPathComponent)” in \(parent.lastPathComponent)")
            ToastWindow.show(message: finished.isComplete ? saved : finished.message, duration: 4, on: finished.screen)
            if !result.skipped.isEmpty {
                ToastWindow.show(message: L("Some files couldn't be written — README.txt in the folder lists them"), duration: 5, on: finished.screen)
            }
            return result.video
        } catch {
            let alert = NSAlert()
            alert.messageText = L("The recording stayed where it was")
            alert.informativeText = L("\(error.localizedDescription) It's in “\(video.deletingLastPathComponent().lastPathComponent)” and opens as before.")
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
            return video
        }
    }

    /// Where the folder goes: what the save window chose, or — Cancel, or
    /// not asking — the Recording folder, named after the recording.
    static func destination(for video: URL, chosen: URL?) -> (parent: URL, name: String) {
        if let chosen { return (chosen.deletingLastPathComponent(), chosen.lastPathComponent) }
        return (URL(fileURLWithPath: Settings.recordingFolder, isDirectory: true), video.deletingPathExtension().lastPathComponent)
    }

    /// The save window. Nil: Cancel.
    private static func choose(name: String) -> URL? {
        NSApp.ensureForegroundCapable()
        LFStudiosEditorActivation.activateApp()
        let panel = NSSavePanel()
        panel.title = L("Save Recording")
        panel.message = L("Where do you want to save this recording?")
        panel.prompt = L("Save")
        panel.nameFieldLabel = L("Folder name:")
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = true
        panel.directoryURL = URL(fileURLWithPath: Settings.lastRecordingSaveFolder, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
