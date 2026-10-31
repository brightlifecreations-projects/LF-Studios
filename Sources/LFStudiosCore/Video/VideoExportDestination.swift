import AppKit

// MARK: - The export window's name and folder (1.15.0)

extension VideoEditorModel {
    /// The file's name, without its extension ("Demo (edited)" until you
    /// type another).
    var exportName: String {
        get { exportNameEdited ?? exportBaseName }
        set {
            let trimmed = newValue.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            exportNameEdited = trimmed == exportBaseName ? nil : trimmed
        }
    }

    /// Where Export saves (the recordings folder until you choose one).
    var exportFolder: URL {
        let path = exportFolderPath.isEmpty ? Settings.recordingFolder : exportFolderPath
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = exportFolder
        panel.prompt = L("Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportFolderPath = url.path
        Settings.videoExportFolder = url.path
    }

    /// "Name.mp4" in the folder; when it's there already, Replace or Keep
    /// Both ("Name 2.mp4"). nil: cancelled.
    func exportDestination(settings: VideoExportSettings, ask: @MainActor (URL) -> NSApplication.ModalResponse = VideoEditorModel.askReplace) -> URL? {
        let name = exportName.trimmingCharacters(in: .whitespaces).isEmpty ? exportBaseName : exportName.trimmingCharacters(in: .whitespaces)
        try? FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        let wanted = exportFolder.appendingPathComponent("\(name).\(settings.fileExtension)")
        guard FileManager.default.fileExists(atPath: wanted.path) else { return wanted }
        switch ask(wanted) {
        case .alertFirstButtonReturn: return wanted
        case .alertSecondButtonReturn: return Self.unique(wanted)
        default: return nil
        }
    }

    static func unique(_ url: URL) -> URL {
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension, folder = url.deletingLastPathComponent()
        var number = 2
        var candidate = url
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }

    static func askReplace(_ url: URL) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = L("“\(url.lastPathComponent)” is already there")
        alert.informativeText = L("Replace it, or keep both (the new one gets a number)?")
        alert.addButton(withTitle: L("Replace"))
        alert.addButton(withTitle: L("Keep Both"))
        alert.addButton(withTitle: L("Cancel"))
        return alert.runModal()
    }
}
