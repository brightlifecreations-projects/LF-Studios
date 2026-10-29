import AppKit
import UniformTypeIdentifiers

/// Projects opened or saved lately, newest first (LF Studios/Projects).
enum VideoProjectRecents {
    struct Entry: Codable, Equatable {
        var path: String
        var bookmark: Data?
        var openedAt: Date
    }

    static let limit = 20

    static func fileURL(root: URL = VideoStorageLocation.root) -> URL {
        root.appendingPathComponent("LF Studios", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("recent.json", isDirectory: false)
    }

    /// The ones still on disk (found again after a move by their bookmark).
    static func load(root: URL = VideoStorageLocation.root) -> [URL] {
        guard let data = try? Data(contentsOf: fileURL(root: root)),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        var seen = Set<String>()
        return entries.sorted { $0.openedAt > $1.openedAt }.compactMap { entry -> URL? in
            var url = URL(fileURLWithPath: entry.path)
            if !FileManager.default.fileExists(atPath: url.path), let bookmark = entry.bookmark {
                var stale = false
                if let found = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) { url = found }
            }
            guard FileManager.default.fileExists(atPath: VideoProjectPackage.manifestURL(url).path), seen.insert(url.standardizedFileURL.path).inserted else { return nil }
            return url
        }
    }

    static func add(_ url: URL, root: URL = VideoStorageLocation.root) {
        let file = fileURL(root: root)
        var entries = ((try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) }) ?? []
        let path = url.standardizedFileURL.path
        entries.removeAll { $0.path == path }
        entries.insert(Entry(path: path, bookmark: try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), openedAt: Date()), at: 0)
        entries = Array(entries.prefix(limit))
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
        NotificationCenter.default.post(name: .lfstudiosRecordingsDidChange, object: nil)
    }
}

extension UTType {
    /// An LF Studios project (declared in Info.plist).
    static var lfstudiosProject: UTType {
        UTType(VideoProjectDocument.typeIdentifier) ?? UTType(filenameExtension: VideoProjectDocument.fileExtension, conformingTo: .package) ?? .package
    }

    /// A project saved while the app was called ShotStyle (still opens).
    static var shotstyleProject: UTType {
        UTType(VideoProjectDocument.legacyTypeIdentifier) ?? UTType(filenameExtension: VideoProjectDocument.legacyFileExtension, conformingTo: .package) ?? .package
    }
}

/// Opening a `.lfstudios` project in the video editor.
@MainActor
enum VideoProjectOpener {
    /// File ▸ Open… (⌘O) and Home's Open…: a project, a folder (a
    /// recording's own, a Creative Handoff, any other), or a video.
    static func chooseAndOpen() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.lfstudiosProject, .shotstyleProject, .folder, .mpeg4Movie, .quickTimeMovie, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = L("Choose a project, a folder, or a video")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        VideoFolderOpener.open(url)
    }

    /// The edit as the editor will pick it up, ready before the window
    /// opens: the recordings' data where the editor reads it, and the edit
    /// as the recording's draft (unless the draft holds newer changes).
    /// Returns the main recording, or nil when it can't open.
    @discardableResult
    static func prepare(_ opened: VideoProjectPackage.Opened, ask: @MainActor (_ name: String) -> Bool = askNewerEdits) -> URL? {
        let contents = opened.contents
        let primary = contents.project.sourceURL
        guard FileManager.default.fileExists(atPath: primary.path) else { return nil }
        for file in opened.fontFiles {
            _ = try? VideoFonts.addFontFile(file)
        }
        // The cleaned-up voices and the face tracking it carries, where
        // this Mac looks for them.
        VideoProjectCaches.restore(contents)
        if let recording = contents.recording {
            VideoDemoSidecarStore.save(recording, for: primary)
        }
        for source in contents.project.sources where !source.isPrimary {
            if let metadata = contents.sourceRecordings[source.id.uuidString], FileManager.default.fileExists(atPath: source.path) {
                VideoDemoSidecarStore.save(metadata, for: URL(fileURLWithPath: source.path))
            }
        }
        var useSaved = true
        if let draft = VideoDemoDraftStore.load(for: primary), draft.savedAt > opened.document.savedAt.addingTimeInterval(1) {
            var saved = contents.project
            saved.cursorSamples = draft.project.cursorSamples
            if draft.project != saved {
                // Included media: the copy is this project's alone, so its
                // newer draft is this project's unsaved work. Linked: the
                // recording may have been edited apart from the project.
                // A folder project: the folder is the edit's home, so its
                // newer draft is that folder's unsaved work too.
                useSaved = opened.document.mediaMode == .linked ? !ask(opened.package.deletingPathExtension().lastPathComponent) : false
            }
        }
        if useSaved {
            VideoDemoDraftStore.save(contents.project, for: primary)
        }
        return primary
    }

    /// true: open the newer edits.
    static func askNewerEdits(_ name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = L("This recording has newer edits than “\(name)”")
        alert.informativeText = L("It was edited after the project was saved. Open those newer edits, or the project as it was saved?")
        alert.addButton(withTitle: L("Open Newer Edits"))
        alert.addButton(withTitle: L("Open Project as Saved"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func open(_ url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let opened: VideoProjectPackage.Opened
        do {
            opened = try VideoProjectPackage.open(url)
        } catch {
            showProblem(L("Couldn't open “\(name)”"), detail: L("It isn't an LF Studios project, or it's damaged."))
            return
        }
        guard let primary = prepare(opened) else {
            let missing = opened.contents.project.sourceURL
            showProblem(L("The recording for “\(name)” is missing"), detail: L("“\(missing.lastPathComponent)” isn't at \(missing.deletingLastPathComponent().path) anymore. Put it back, or save the project with Include Media next time so it carries its own copy."))
            return
        }
        VideoFontLibrary.shared.reload()
        VideoDemoEditorWindowController.open(videoURL: primary, projectFile: opened.package, mode: opened.document.mediaMode, folder: opened.document.folder)
        VideoProjectRecents.add(opened.package)
        if opened.document.isFromNewerVersion {
            VideoDemoEditorWindowController.keyModel?.showNotice(L("Saved by a newer LF Studios — some settings may not show"), symbol: "exclamationmark.triangle.fill", duration: 5)
        }
    }

    private static func showProblem(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }
}

// MARK: - Saving (File ▸ Save Project, Save Project As…)

extension VideoEditorModel {
    var projectContents: VideoProjectContents {
        var sources: [String: VideoDemoRecordingMetadata] = [:]
        for (id, metadata) in media.appendedMetadata {
            if let metadata { sources[id.uuidString] = metadata }
        }
        // Naming this Mac's cached voices and face tracking, so they travel.
        return VideoProjectCaches.carrying(VideoProjectContents(project: project, recording: recording, sourceRecordings: sources), primaryKinds: audioKinds)
    }

    /// ⌘S: into the project file this edit came from or was saved to (asks
    /// where the first time); ⇧⌘S always asks.
    func saveProject(as saveAs: Bool = false) {
        guard isReady else { return }
        saveDraftNow()
        var destination = projectFileURL
        var mode = projectMediaMode ?? .included
        if saveAs || destination == nil {
            guard let chosen = chooseProjectDestination(mode: mode) else { return }
            destination = chosen.url
            mode = chosen.mode
            if chosen.url.standardizedFileURL != projectFileURL?.standardizedFileURL, FileManager.default.fileExists(atPath: chosen.url.path) {
                // The panel asked before replacing it.
                try? FileManager.default.removeItem(at: chosen.url)
            }
        }
        guard let url = destination else { return }
        let contents = projectContents
        let folder = mode == .folder ? (projectFolder ?? .init(kind: .opened)) : nil
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let includeInstalled = Settings.projectIncludesInstalledFonts
        let leftOut = mode == .linked ? [] : VideoFonts.installedFamiliesLeftOut(VideoProjectDocument.fontFamilies(of: contents.project), includeInstalled: includeInstalled)
        isSavingProject = true
        showNotice(L("Saving project…"), symbol: "square.and.arrow.down", duration: 30)
        Task {
            let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    _ = try VideoProjectPackage.save(contents, to: url, mode: mode, appVersion: version, folder: folder,
                                                     fontFiles: { VideoFonts.carriedFontFiles(forFamily: $0, includeInstalled: includeInstalled) })
                }
            }.value
            isSavingProject = false
            switch result {
            case .success:
                projectFileURL = url
                projectMediaMode = mode
                // Saved there on purpose: the folder is the project's now.
                if mode == .folder { VideoFileIdentity.unprotect(url.deletingLastPathComponent()) }
                VideoProjectRecents.add(url)
                if leftOut.isEmpty {
                    showNotice(L("Saved “\(url.deletingPathExtension().lastPathComponent)”"), symbol: "checkmark.circle.fill")
                } else {
                    let names = leftOut.joined(separator: ", ")
                    showNotice(L("Saved. Fonts installed on this Mac aren't included: \(names). Another Mac shows a stand-in font."), symbol: "textformat", duration: 6)
                }
            case .failure:
                showNotice(L("Couldn't save the project — check there's room on the disk"), symbol: "exclamationmark.triangle.fill", duration: 5)
            }
        }
    }

    /// The Save panel, with Include Media / Link to Media below it.
    private func chooseProjectDestination(mode: VideoProjectDocument.MediaMode) -> (url: URL, mode: VideoProjectDocument.MediaMode)? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.lfstudiosProject]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(projectFileURL?.deletingPathExtension().lastPathComponent ?? project.sourceURL.deletingPathExtension().lastPathComponent).\(VideoProjectDocument.fileExtension)"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 26), pullsDown: false)
        popup.addItems(withTitles: [L("Include media (works on any Mac)"), L("Link to media (small, this Mac only)")])
        popup.selectItem(at: mode == .included ? 0 : 1)
        let label = NSTextField(labelWithString: L("Media:"))
        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.spacing = 8
        let fonts = NSButton(checkboxWithTitle: L("Include fonts installed on this Mac"), target: nil, action: nil)
        fonts.state = Settings.projectIncludesInstalledFonts ? .on : .off
        let fontsNote = NSTextField(wrappingLabelWithString: L("Fonts added to LF Studios always go along. Check that a font's license lets you share it before sending."))
        fontsNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        fontsNote.textColor = .secondaryLabelColor
        fontsNote.preferredMaxLayoutWidth = 400
        let stack = NSStackView(views: [row, fonts, fontsNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 10, right: 16)
        panel.accessoryView = stack
        guard panel.runModal() == .OK, var url = panel.url else { return nil }
        Settings.projectIncludesInstalledFonts = fonts.state == .on
        if url.pathExtension != VideoProjectDocument.fileExtension { url.appendPathExtension(VideoProjectDocument.fileExtension) }
        return (url, popup.indexOfSelectedItem == 0 ? .included : .linked)
    }
}

// MARK: - A recording's own folder, kept up to date

extension VideoEditorModel {
    /// A recording's own folder (VideoRecordingFolder.swift) holds the whole
    /// edit: after each autosave, its project file is written again, and its
    /// captions (05 Captions) follow the captions in the editor. A folder
    /// someone opened themselves changes only on Save.
    func updateRecordingFolder() {
        guard projectMediaMode == .folder, projectFolder?.kind == .recording, let package = projectFileURL,
              recordingFolderWritten != project else { return }
        recordingFolderWritten = project
        let contents = projectContents
        let folder = package.deletingLastPathComponent()
        let name = package.deletingPathExtension().lastPathComponent
        let captions = recordingFolderCaptions(name: name)
        let version = VideoRecordingFolderWriter.appVersion
        let includeInstalled = Settings.projectIncludesInstalledFonts
        recordingFolderWrite = Task.detached(priority: .utility) { [previous = recordingFolderWrite] in
            _ = await previous?.value
            _ = try? VideoProjectPackage.save(contents, to: package, mode: .folder, appVersion: version, folder: .init(kind: .recording),
                                              fontFiles: { VideoFonts.carriedFontFiles(forFamily: $0, includeInstalled: includeInstalled) })
            VideoRecordingFolder.writeCaptions(captions, in: folder)
        }
    }

    /// The captions files as they should be now: Name.srt and, for each
    /// translation, Name.<language>.srt — on the edit's clock.
    func recordingFolderCaptions(name: String) -> [String: String] {
        guard !project.captions.isEmpty else { return [:] }
        var files = ["\(name).srt": VideoCaptionBuilder.srt(lines: project.captions, segments: segments)]
        for translation in project.captionTracks.translations {
            let lines = Dictionary(translation.lines.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
            files["\(name).\(translation.language).srt"] = VideoCaptionBuilder.srt(lines: project.captions, segments: segments, translation: lines)
        }
        return files
    }
}
