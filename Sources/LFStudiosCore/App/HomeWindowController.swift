import AppKit
import AVFoundation
import ImageIO
import SwiftUI

extension Notification.Name {
    /// A recording was saved, opened, or moved to the Trash.
    static let lfstudiosRecordingsDidChange = Notification.Name("lfstudiosRecordingsDidChange")
}

/// What the Home window's buttons do. AppDelegate owns the capture engine,
/// so it hands these in.
struct HomeActions {
    var newRecording: () -> Void
    var takeScreenshot: () -> Void
    var scrollCapture: () -> Void
    var openVideo: () -> Void
    var openHistory: () -> Void = {}
}

/// LF Studios' main window: start a capture, and find every recording and
/// screenshot again. Closing it only hides it; the Dock icon brings it back.
@MainActor
final class HomeWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: HomeWindowController?

    private let model: HomeModel

    /// How the window comes back after stepping aside for a capture.
    private enum Return {
        /// In front again: the capture was started from Home.
        case front
        /// Behind other windows, where it was.
        case behind
    }

    private var pendingReturn: Return?

    static func configure(historyManager: HistoryManager, actions: HomeActions) {
        guard shared == nil else { return }
        shared = HomeWindowController(model: HomeModel(historyManager: historyManager, actions: actions))
    }

    static func show() {
        shared?.showHome()
    }

    /// Home, open on one section (Help ▸ LF Studios Guide opens the Guide).
    static func show(section: HomeSection) {
        shared?.model.section = section
        shared?.showHome()
    }

    static var isVisible: Bool {
        shared?.window?.isVisible ?? false
    }

    /// A capture overlay is about to show.
    static func stepAsideForCapture() {
        shared?.stepAside(returning: .behind)
    }

    /// The capture overlay closed (or was cancelled).
    static func returnAfterCapture() {
        shared?.comeBack()
    }

    private init(model: HomeModel) {
        self.model = model
        let hostingController = NSHostingController(rootView: HomeRootView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "LF Studios" // l10n-ignore: a name
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = HomeColors.windowBackground
        window.setContentSize(NSSize(width: 1120, height: 740))
        window.minSize = NSSize(width: 880, height: 580)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.setFrameAutosaveName("LFStudiosHome")
        super.init(window: window)
        window.delegate = self
        model.stepAside = { [weak self] comesBack in
            if comesBack {
                self?.stepAside(returning: .front)
            } else {
                self?.window?.orderOut(nil)
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // The user went to another app mid-capture: back behind it.
            MainActor.assumeIsolated {
                guard let self, self.pendingReturn != nil else { return }
                self.pendingReturn = .behind
                self.comeBack()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func stepAside(returning: Return) {
        guard let window, window.isVisible, !window.isMiniaturized else { return }
        pendingReturn = returning
        window.orderOut(nil)
    }

    private func comeBack() {
        guard let pending = pendingReturn else { return }
        pendingReturn = nil
        switch pending {
        case .front: showHome()
        case .behind: window?.orderBack(nil)
        }
    }

    private func showHome() {
        pendingReturn = nil
        model.reload()
        NSApp.ensureForegroundCapable()
        LFStudiosEditorActivation.activateApp()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }
}

// MARK: - Model

enum HomeSection: String, CaseIterable, Identifiable {
    case home
    case recordings
    case screenshots
    case settings
    case guide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return L("Home")
        case .recordings: return L("Recordings")
        case .screenshots: return L("Screenshots")
        case .settings: return L("Settings")
        case .guide: return L("Guide")
        }
    }

    var symbolName: String {
        switch self {
        case .home: return "house"
        case .recordings: return "video"
        case .screenshots: return "photo.on.rectangle"
        case .settings: return "gearshape"
        case .guide: return "book"
        }
    }
}

struct HomeProject: Identifiable {
    enum Kind {
        case recording(URL)
        case screenshot(HistoryItem)
        /// A saved project (`.lfs`, `.lfsp`, `.lfstudios`, `.shotstyle`) (VideoProjectFiles.swift).
        case projectFile(URL)
        /// A recording in its own folder: the folder's project file
        /// (VideoRecordingFolder.swift).
        case recordingFolder(URL)
    }

    let id: String
    let kind: Kind
    let name: String
    let date: Date
    /// Name plus, for screenshots, the text recognized in them.
    let searchText: String

    var isRecording: Bool {
        if case .recording = kind { return true }
        return false
    }

    var isProjectFile: Bool {
        if case .projectFile = kind { return true }
        return false
    }

    var isRecordingFolder: Bool {
        if case .recordingFolder = kind { return true }
        return false
    }

    /// A recording, a recording's folder, or a project: opens in the video editor.
    var isVideo: Bool { isRecording || isProjectFile || isRecordingFolder }

    /// The badge on its card.
    var symbol: String {
        switch kind {
        case .recording: return "video.fill"
        case .screenshot: return "photo.fill"
        case .projectFile: return "doc.fill"
        case .recordingFolder: return "video.fill"
        }
    }
}

/// What has to be read from disk: loaded in the background, once per file.
struct HomeProjectDetails {
    var thumbnail: NSImage?
    var fileSize: Int64?
    var duration: Double?
    var pixelSize: CGSize?
}

@MainActor
final class HomeModel: ObservableObject {
    @Published var section: HomeSection = .home
    @Published var query = ""
    @Published private(set) var projects: [HomeProject] = []
    @Published private(set) var details: [String: HomeProjectDetails] = [:]

    let historyManager: HistoryManager
    let actions: HomeActions
    let preferencesSelection = PreferencesSelectionModel()
    let guide = GuideModel()
    /// Hides the Home window, so it isn't in the way of a capture; with true,
    /// it comes back once the capture overlay closes.
    var stepAside: (_ comesBack: Bool) -> Void = { _ in }

    private var loading: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    init(historyManager: HistoryManager, actions: HomeActions) {
        self.historyManager = historyManager
        self.actions = actions
        guide.navigate = { [weak self] destination in
            guard let self else { return }
            GuideNavigator.go(to: destination, home: self)
        }
        for name in [Notification.Name.lfstudiosHistoryDidChange, .lfstudiosRecordingsDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
    }

    var visibleProjects: [HomeProject] {
        let inSection: [HomeProject]
        switch section {
        case .recordings: inSection = projects.filter(\.isVideo)
        case .screenshots: inSection = projects.filter { !$0.isVideo }
        case .home, .settings, .guide: inSection = projects
        }
        let terms = query.split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return inSection }
        return inSection.filter { project in
            terms.allSatisfy { project.searchText.localizedCaseInsensitiveContains($0) }
        }
    }

    func reload() {
        // Recordings in folders of their own: wherever they were saved, and
        // any in the folders Home looks in.
        let scanned = Array(Set([Settings.recordingFolder, Settings.autoSaveLocation, Settings.defaultAutoSaveLocation]))
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let folderProjects = VideoRecordingFolders.projects(scanning: scanned)
        let inFolders = Set(folderProjects.map(\.path))
        let folders = folderProjects.map { project in
            HomeProject(
                id: "folder:" + project.path,
                kind: .recordingFolder(project),
                name: project.deletingLastPathComponent().lastPathComponent,
                date: Self.modificationDate(of: VideoProjectPackage.manifestURL(project)),
                searchText: project.deletingLastPathComponent().lastPathComponent
            )
        }
        let recordings = Settings.recordingURLs.filter { VideoRecordingFolder.project(ofVideo: $0) == nil }.map { url in
            HomeProject(
                id: url.path,
                kind: .recording(url),
                name: url.deletingPathExtension().lastPathComponent,
                date: Self.modificationDate(of: url),
                searchText: url.deletingPathExtension().lastPathComponent
            )
        }
        let screenshots = historyManager.items.map { item in
            let name = ImageExporter.renderFilenameTemplate(Settings.filenameTemplate, date: item.createdAt)
            return HomeProject(
                id: item.id.uuidString,
                kind: .screenshot(item),
                name: name,
                date: item.createdAt,
                searchText: [name, item.ocrText ?? ""].joined(separator: " ")
            )
        }
        let projectFiles = VideoProjectRecents.load().filter { !inFolders.contains($0.standardizedFileURL.path) }.map { url in
            HomeProject(
                id: "project:" + url.standardizedFileURL.path,
                kind: .projectFile(url),
                name: url.deletingPathExtension().lastPathComponent,
                date: Self.modificationDate(of: VideoProjectPackage.manifestURL(url)),
                searchText: url.deletingPathExtension().lastPathComponent
            )
        }
        projects = (folders + projectFiles + recordings + screenshots).sorted { $0.date > $1.date }
        let ids = Set(projects.map(\.id))
        details = details.filter { ids.contains($0.key) }
        projects.forEach(loadDetailsIfNeeded)
    }

    // MARK: Actions

    /// A screenshot brings Home back once it's taken; a recording or a
    /// scrolling capture keeps going after its overlay closes, so Home stays
    /// out of the way until the Dock icon brings it back.
    func run(_ action: @escaping () -> Void, comesBack: Bool) {
        stepAside(comesBack)
        // A beat for the window to leave the screen before the capture
        // overlay looks at it.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            action()
        }
    }

    func open(_ project: HomeProject) {
        switch project.kind {
        case .recording(let url):
            Settings.lastRecordingPath = url.path
            VideoDemoEditorWindowController.open(videoURL: url)
        case .screenshot(let item):
            AnnotationWindowController.open(image: item.fullImage, historyItem: item, historyManager: historyManager)
        case .projectFile(let url), .recordingFolder(let url):
            VideoProjectOpener.open(url)
        }
    }

    /// Opens the recording (or project) and its Creative Handoff dialog.
    func handoff(_ project: HomeProject) {
        guard project.isVideo else { return }
        VideoDemoEditorWindowController.handoffOnNextOpen = true
        open(project)
    }

    func showInFinder(_ project: HomeProject) {
        switch project.kind {
        case .recording(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .screenshot(let item):
            let url = historyManager.storedImageURL(for: item) ?? URL(fileURLWithPath: item.imagePath)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .projectFile(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .recordingFolder(let project):
            NSWorkspace.shared.activateFileViewerSelecting([project.deletingLastPathComponent()])
        }
    }

    func delete(_ project: HomeProject) {
        switch project.kind {
        case .recording(let url), .projectFile(let url):
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                if Settings.lastRecordingPath == url.path { Settings.lastRecordingPath = "" }
                ToastWindow.show(message: L("Moved to the Trash"), duration: 2)
            } catch {
                NSSound.beep()
            }
            reload()
        case .screenshot(let item):
            historyManager.delete(item)
        case .recordingFolder(let project):
            let folder = project.deletingLastPathComponent()
            guard confirmDeletingFolder(folder) else { return }
            do {
                try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
                VideoRecordingFolders.remove(folder)
                if Settings.lastRecordingPath.hasPrefix(folder.standardizedFileURL.path + "/") { Settings.lastRecordingPath = "" }
                ToastWindow.show(message: L("Moved to the Trash"), duration: 2)
            } catch {
                NSSound.beep()
            }
            reload()
        }
    }

    /// The whole folder goes: the recording, its camera, sound, captions,
    /// and project. Asks first.
    private func confirmDeletingFolder(_ folder: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = L("Move “\(folder.lastPathComponent)” to the Trash?")
        alert.informativeText = L("The whole folder goes to the Trash: the recording, its camera video, its sound files, captions, and project.")
        alert.addButton(withTitle: L("Move to Trash"))
        alert.addButton(withTitle: L("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Loading

    private func loadDetailsIfNeeded(_ project: HomeProject) {
        loadDetailsIfNeeded(project, attempt: 0)
    }

    private func loadDetailsIfNeeded(_ project: HomeProject, attempt: Int) {
        guard attempt > 0 || details[project.id] == nil, !loading.contains(project.id) else { return }
        loading.insert(project.id)
        let id = project.id
        let kind = project.kind
        Task {
            let loaded: HomeProjectDetails
            switch kind {
            case .recording(let url):
                loaded = await Self.recordingDetails(url)
            case .screenshot(let item):
                loaded = await Task.detached(priority: .utility) { Self.screenshotDetails(item) }.value
            case .projectFile(let url):
                loaded = await Self.projectFileDetails(url)
            case .recordingFolder(let url):
                loaded = await Self.projectFileDetails(url, sizeOf: url.deletingLastPathComponent())
            }
            loading.remove(id)
            guard let current = projects.first(where: { $0.id == id }) else { return }
            // History writes a new capture's file in the background: until
            // it's there, show the thumbnail and look again in a moment.
            if loaded.fileSize == nil, attempt < 5 {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self.loadDetailsIfNeeded(current, attempt: attempt + 1)
                }
                if loaded.thumbnail == nil { return }
            }
            details[id] = loaded
        }
    }

    /// A project's card: its recording's frame and length, the package's
    /// size on disk.
    /// `sizeOf`: what to measure (a recording's whole folder; else the package).
    nonisolated private static func projectFileDetails(_ url: URL, sizeOf measured: URL? = nil) async -> HomeProjectDetails {
        let primary = await Task.detached(priority: .utility) { (try? VideoProjectPackage.open(url))?.contents.project.sourceURL }.value
        var details = HomeProjectDetails()
        if let primary, FileManager.default.fileExists(atPath: primary.path) {
            details = await recordingDetails(primary)
        }
        details.fileSize = await Task.detached(priority: .utility) { () -> Int64 in
            let files = FileManager.default.enumerator(at: measured ?? url, includingPropertiesForKeys: [.fileSizeKey])
            var total: Int64 = 0
            while let file = files?.nextObject() as? URL {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return total
        }.value
        return details
    }

    nonisolated private static func recordingDetails(_ url: URL) async -> HomeProjectDetails {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 520, height: 520)
        let time = CMTime(seconds: min(1, (duration ?? 0) / 2), preferredTimescale: 600)
        let frame = try? await generator.image(at: time).image
        return HomeProjectDetails(
            thumbnail: frame.map { NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height)) },
            fileSize: fileSize(of: url),
            duration: duration.flatMap { $0.isFinite ? $0 : nil }
        )
    }

    nonisolated private static func screenshotDetails(_ item: HistoryItem) -> HomeProjectDetails {
        let url = URL(fileURLWithPath: item.imagePath)
        var pixelSize: CGSize?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            pixelSize = CGSize(width: width, height: height)
        }
        return HomeProjectDetails(
            thumbnail: HistoryImageCache.loadThumbnailDecoded(for: item.thumbnailPath),
            fileSize: fileSize(of: url),
            pixelSize: pixelSize
        )
    }

    nonisolated private static func fileSize(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

// MARK: - Views

enum HomeColors {
    static let windowBackground = NSColor.adaptive(dark: NSColor(calibratedRed: 0.055, green: 0.058, blue: 0.07, alpha: 1), light: NSColor(srgbRed: 0.965, green: 0.965, blue: 0.972, alpha: 1))
    static let sidebar = Color.adaptive(dark: NSColor(calibratedRed: 0.075, green: 0.078, blue: 0.094, alpha: 1), light: NSColor(srgbRed: 0.918, green: 0.918, blue: 0.93, alpha: 1))
    static let content = Color(nsColor: windowBackground)
    /// Text and icons: white on the dark look, black on the light one.
    static let ink = Color.adaptive(dark: .white, light: .black)
    static let card = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.055), light: NSColor.white)
    static let cardHover = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.09), light: NSColor.black.withAlphaComponent(0.04))
    static let stroke = Color.adaptive(dark: NSColor.white.withAlphaComponent(0.08), light: NSColor.black.withAlphaComponent(0.1))
    /// Behind a thumbnail that hasn't loaded.
    static let placeholder = Color.adaptive(dark: NSColor.black.withAlphaComponent(0.35), light: NSColor.black.withAlphaComponent(0.06))
    /// The logo's orange → pink → purple.
    static let brand = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.42, blue: 0.24),
            Color(red: 0.91, green: 0.25, blue: 0.48),
            Color(red: 0.55, green: 0.31, blue: 0.88),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

struct HomeRootView: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar(selection: $model.section)
                .frame(width: 212)
            Rectangle()
                .fill(HomeColors.stroke)
                .frame(width: 1)
            Group {
                switch model.section {
                case .settings:
                    PreferencesRootView(selection: model.preferencesSelection)
                case .guide:
                    GuideRootView(model: model.guide)
                default:
                    HomeLibraryView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HomeColors.content)
        }
        .ignoresSafeArea()
        .frame(minWidth: 880, minHeight: 580)
        // A folder, project, or video dropped anywhere on Home opens.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { VideoFolderOpener.open(url) }
                }
            }
            return !providers.isEmpty
        }
    }
}

private struct HomeSidebar: View {
    @Binding var selection: HomeSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                Text(verbatim: "LF Studios")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(HomeColors.ink.opacity(0.94))
            }
            .padding(.horizontal, 10)
            .padding(.top, 48)
            .padding(.bottom, 18)

            ForEach(HomeSection.allCases) { section in
                HomeSidebarButton(section: section, isSelected: selection == section) {
                    selection = section
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HomeColors.sidebar)
    }
}

private struct HomeSidebarButton: View {
    let section: HomeSection
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text(section.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(HomeColors.ink.opacity(isSelected ? 0.96 : 0.66))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? HomeColors.ink.opacity(0.11) : (isHovering ? HomeColors.ink.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct HomeLibraryView: View {
    @ObservedObject var model: HomeModel

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                if model.section == .home {
                    actions
                }

                projectsSection
            }
            .padding(.horizontal, 32)
            .padding(.top, 44)
            .padding(.bottom, 32)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(model.section.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(HomeColors.ink.opacity(0.95))
            Spacer()
            Button {
                VideoProjectOpener.chooseAndOpen()
            } label: {
                Label(L("Open…"), systemImage: "folder")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(HomeColors.ink.opacity(0.8))
            .help(L("Open a project, a recording's folder, a Creative Handoff, or a video"))
            HomeSearchField(text: $model.query)
                .frame(width: 260)
        }
    }

    private var actions: some View {
        HStack(alignment: .top, spacing: 16) {
            HomeNewRecordingButton { model.run(model.actions.newRecording, comesBack: false) }
                .frame(maxWidth: .infinity)
            HStack(spacing: 16) {
                HomeActionCard(title: L("Take screenshot"), symbol: "camera.viewfinder") {
                    model.run(model.actions.takeScreenshot, comesBack: true)
                }
                HomeActionCard(title: L("Scroll capture"), symbol: "scroll") {
                    model.run(model.actions.scrollCapture, comesBack: false)
                }
                HomeActionCard(title: L("Open video…"), symbol: "film") {
                    model.actions.openVideo()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 132)
    }

    private var projectsSection: some View {
        let projects = model.visibleProjects
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("Projects"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(HomeColors.ink.opacity(0.92))
                Text(verbatim: "\(projects.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeColors.ink.opacity(0.4))
            }

            if projects.isEmpty {
                HomeEmptyState(isSearching: !model.query.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(projects) { project in
                        HomeProjectCard(project: project, details: model.details[project.id])
                            .onTapGesture { model.open(project) }
                            .contextMenu {
                                Button(L("Open")) { model.open(project) }
                                Button(L("Show in Finder")) { model.showInFinder(project) }
                                if project.isVideo {
                                    Button(L("Creative Handoff…")) { model.handoff(project) }
                                }
                                Divider()
                                Button(L("Delete"), role: .destructive) { model.delete(project) }
                            }
                    }
                }
            }
        }
    }
}

struct HomeSearchField: View {
    @Binding var text: String
    var placeholder = L("Search projects")

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HomeColors.ink.opacity(0.45))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(HomeColors.ink.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help(L("Clear"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(HomeColors.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(HomeColors.stroke, lineWidth: 1))
    }
}

private struct HomeNewRecordingButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("New recording"))
                        .font(.system(size: 21, weight: .bold))
                    Text(L("Record an area, a window, or the whole screen"))
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.85)
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HomeColors.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .brightness(isHovering ? 0.05 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct HomeActionCard: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(HomeColors.ink.opacity(0.9))
                Spacer(minLength: 8)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeColors.ink.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(isHovering ? HomeColors.cardHover : HomeColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HomeColors.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct HomeProjectCard: View {
    let project: HomeProject
    let details: HomeProjectDetails?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeColors.ink.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(project.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HomeColors.ink.opacity(0.48))
                    .lineLimit(1)
                Text(verbatim: metadata)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HomeColors.ink.opacity(0.48))
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .background(isHovering ? HomeColors.cardHover : HomeColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HomeColors.stroke, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { isHovering = $0 }
        .help(project.name)
    }

    private var thumbnail: some View {
        HomeColors.placeholder
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                if let image = details?.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: project.isVideo ? "video" : "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(HomeColors.ink.opacity(0.25))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .topLeading) {
                Image(systemName: project.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(7)
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration = details?.duration {
                    Text(verbatim: Self.durationText(duration))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(7)
                }
            }
    }

    private var metadata: String {
        var parts: [String] = []
        if let pixelSize = details?.pixelSize {
            parts.append("\(Int(pixelSize.width)) × \(Int(pixelSize.height))")
        }
        if let fileSize = details?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }
        // Keeps the line's height while the details load.
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    static func durationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

private struct HomeEmptyState: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isSearching ? "magnifyingglass" : "square.stack.3d.up")
                .font(.system(size: 30))
                .foregroundStyle(HomeColors.ink.opacity(0.3))
            Text(isSearching ? L("No projects match your search") : L("Your recordings and screenshots will appear here"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HomeColors.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(HomeColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
