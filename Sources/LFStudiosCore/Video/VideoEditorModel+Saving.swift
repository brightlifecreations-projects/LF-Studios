import AppKit
import AVFoundation
import SwiftUI

/// Notices, saving edits as you go (drafts), and exporting.
extension VideoEditorModel {
    // MARK: Notices

    /// A short message where the user is looking (over the export sheet
    /// while it's up). Warnings stay up longer.
    func showNotice(_ message: String, symbol: String = "info.circle", duration: Double = 2.4) {
        noticeWork?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            notice = VideoEditorNotice(message: message, symbol: symbol)
        }
        lastNotice = notice
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.notice = nil }
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: Autosave

    func scheduleAutosave() {
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveDraftNow() }
        }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func saveDraftNow() {
        guard isReady else { return }
        autosaveWork?.cancel()
        autosaveWork = nil
        var draft = project
        // The pointer path can't be edited and lives in the recording's
        // sidecar — keeping it out makes autosave instant on long takes.
        if let recording, recording.cursorSamples == draft.cursorSamples {
            draft.cursorSamples = []
        }
        VideoDemoDraftStore.save(draft, for: draft.sourceURL)
        updateRecordingFolder()
    }

    /// Export, the command palette, or the shortcut sheet is up: edits
    /// behind it (undo) stay put.
    var hasOverlayOpen: Bool { isExportPresented || isHandoffPresented || isPrivacyPresented || isCommandPalettePresented || isShortcutsPresented }

    /// Something that shouldn't be dropped silently by closing the window,
    /// as the title of the "close anyway?" question: a whole sentence, so
    /// every language can word it. (Exports carry on in the background:
    /// they work from a snapshot.)
    var runningJobTitle: String? {
        if captionTask != nil { return L("LF Studios is still transcribing") }
        if voiceJob != nil { return L("LF Studios is still cleaning up the voice") }
        return nil
    }

    /// The window closed: nothing keeps working (or writing to the
    /// clipboard) unseen — except exports, which finish and say so.
    func stop() {
        playback.pause()
        cancelCaptions()
        voiceTask?.cancel()
        // Nothing left running asks about the quit (or holds an update).
        endVoiceQuitToken()
        saveDraftNow()
        keepHistoryForSession()
        VideoExportQueue.shared.editorClosed(sourcePath: project.sourcePath)
    }

    // MARK: Export

    var exportCanvas: CGSize { project.canvasSize() }

    /// Exports queue up and run in the background (VideoExportJobs.swift).
    func beginExport(toClipboard: Bool, range: VideoExportRange = .whole) {
        followRenamedRecording()
        let settings = exportSettings
        settings.saveAsDefaults()
        let destination: URL
        if toClipboard {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LF Studios Exports", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            destination = folder.appendingPathComponent("\(exportBaseName).\(settings.fileExtension)")
        } else {
            // The name and folder from the export window (1.15.0).
            guard let chosen = exportDestination(settings: settings) else { return }
            destination = chosen
        }
        enqueueExport(to: destination, settings: settings, toClipboard: toClipboard, range: range)
    }

    /// The recording's name as it is now (renamed in Finder while open
    /// included).
    var recordingName: String { currentSourceURL.deletingPathExtension().lastPathComponent }

    /// One name for everything made from this recording — the video and
    /// its subtitles side by side ("Demo (edited).mp4", "Demo (edited).srt",
    /// which players pair up) — never the recording's own file name.
    var exportBaseName: String { L("\(recordingName) (edited)") }

    /// Where the recording is now: a bookmark follows it through renames
    /// and moves.
    var currentSourceURL: URL {
        var stale = false
        guard let sourceBookmark,
              let url = try? URL(resolvingBookmarkData: sourceBookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { return project.sourceURL }
        return url.standardizedFileURL
    }

    /// A recording renamed or moved while it's open: the project (and its
    /// undo history) points at where it is now, so exports can read it.
    func followRenamedRecording() {
        let current = currentSourceURL
        guard VideoFileIdentity.canonicalURL(current) != VideoFileIdentity.canonicalURL(project.sourceURL),
              FileManager.default.fileExists(atPath: current.path) else { return }
        func moved(_ snapshot: VideoDemoProject) -> VideoDemoProject {
            var copy = snapshot
            copy.sourcePath = current.path
            return copy
        }
        undoStack = undoStack.map { UndoStep(project: moved($0.project), label: $0.label) }
        redoStack = redoStack.map { UndoStep(project: moved($0.project), label: $0.label) }
        project = moved(project)
    }

    func cancelExport() {
        cancelLatestExport()
    }

    /// Closes the export sheet; a finished or failed export is cleared so
    /// the next ⌘E starts on the options.
    func closeExportSheet() {
        withAnimation(.easeOut(duration: 0.15)) {
            isExportPresented = false
        }
        if case .running = exportPhase { return }
        exportPhase = .idle
    }

    func revealExport(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openExport(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func copyExport(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        showNotice(L("Copied — paste it anywhere"), symbol: "doc.on.doc")
    }

    func revealSource() {
        NSWorkspace.shared.activateFileViewerSelecting([project.sourceURL])
    }

    /// Copies the frame under the playhead (as rendered) to the clipboard.
    func copyCurrentFrame() {
        let size = exportSettings.outputSize(canvas: project.canvasSize())
        guard let image = previewRenderer.snapshot(size: size) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        showNotice(L("Frame copied"), symbol: "photo.on.rectangle")
    }
}
