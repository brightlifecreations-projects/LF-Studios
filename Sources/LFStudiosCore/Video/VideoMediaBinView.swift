import AppKit
import AVFoundation
import ImageIO
import SwiftUI

// MARK: - Sorting and finding (1.13.0)

enum VideoMediaSort: String, CaseIterable, Identifiable {
    case added
    case name
    case duration
    case kind

    var id: String { rawValue }
    var title: String {
        switch self {
        case .added: return L("Date Added")
        case .name: return L("Name")
        case .duration: return L("Length")
        case .kind: return L("Kind")
        }
    }

    static var remembered: VideoMediaSort {
        get { Settings.videoMediaBinSort.flatMap(VideoMediaSort.init(rawValue:)) ?? .added }
        set { Settings.videoMediaBinSort = newValue.rawValue }
    }
}

enum VideoMediaArrangement {
    /// What the Library shows: `kinds` only; in `folder` (nil: the top),
    /// unless searching, which looks everywhere; or flat (the Audio tab).
    static func entries(_ all: [VideoMediaEntry], kinds: Set<VideoMediaKind>, folder: UUID?, flat: Bool, query: String,
                        sort: VideoMediaSort, duration: (VideoMediaEntry) -> Double? = { $0.duration }) -> [VideoMediaEntry] {
        let words = query.trimmingCharacters(in: .whitespaces)
        var shown = all.filter { kinds.contains($0.kind) }
        if !words.isEmpty {
            shown = shown.filter { $0.name.localizedCaseInsensitiveContains(words) || $0.ownName.localizedCaseInsensitiveContains(words) }
        } else if !flat {
            shown = shown.filter { $0.folder == folder }
        }
        // The video's own media first (in its order), imports after.
        let order = Dictionary(all.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
        func byName(_ a: VideoMediaEntry, _ b: VideoMediaEntry) -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
        switch sort {
        case .added:
            return shown.sorted { a, b in
                switch (a.added, b.added) {
                case let (x?, y?): return x > y
                case (nil, nil): return order[a.key]! < order[b.key]!
                case (nil, _?): return true
                case (_?, nil): return false
                }
            }
        case .name:
            return shown.sorted(by: byName)
        case .duration:
            return shown.sorted { (duration($0) ?? -1, order[$1.key]!) > (duration($1) ?? -1, order[$0.key]!) }
        case .kind:
            let kindOrder: [VideoMediaKind: Int] = [.video: 0, .image: 1, .audio: 2]
            return shown.sorted { kindOrder[$0.kind]! != kindOrder[$1.kind]! ? kindOrder[$0.kind]! < kindOrder[$1.kind]! : byName($0, $1) }
        }
    }
}

// MARK: - Thumbnails

/// Small pictures of the Library's media: a frame from a video (any of ten
/// along it, for hover-scrubbing), a picture itself; and videos' lengths.
@MainActor
final class VideoMediaThumbnails {
    static let shared = VideoMediaThumbnails()
    static let scrubFrames = 10

    private let images = NSCache<NSString, NSImage>()
    private var durations: [String: Double] = [:]

    func cached(_ path: String, frame: Int?) -> NSImage? { images.object(forKey: Self.key(path, frame)) }
    func knownDuration(_ path: String) -> Double? { durations[path] }

    /// `frame` nil: the cover; 0…9: along the video.
    func image(_ path: String, kind: VideoMediaKind, frame: Int?) async -> NSImage? {
        if let cached = cached(path, frame: frame) { return cached }
        let url = URL(fileURLWithPath: path)
        let made: CGImage?
        switch kind {
        case .audio:
            return nil
        case .image:
            made = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 360,
                ] as CFDictionary)
            }.value
        case .video:
            let asset = AVURLAsset(url: url)
            guard let length = await duration(path), length > 0 else { return nil }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 360)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            let at = frame.map { length * (Double($0) + 0.5) / Double(Self.scrubFrames) } ?? min(1, length * 0.1)
            made = try? await generator.image(at: CMTime(seconds: at, preferredTimescale: 600)).image
        }
        guard let made else { return nil }
        let image = NSImage(cgImage: made, size: NSSize(width: made.width, height: made.height))
        images.setObject(image, forKey: Self.key(path, frame))
        return image
    }

    func duration(_ path: String) async -> Double? {
        if let known = durations[path] { return known }
        guard FileManager.default.fileExists(atPath: path),
              let seconds = try? await AVURLAsset(url: URL(fileURLWithPath: path)).load(.duration).seconds,
              seconds.isFinite, seconds > 0 else { return nil }
        durations[path] = seconds
        return seconds
    }

    private static func key(_ path: String, _ frame: Int?) -> NSString { "\(frame ?? -1)|\(path)" as NSString }
}

// MARK: - The bin

/// The Library's Media and Audio tabs: what the project has, and what was
/// imported for it.
struct VideoMediaBinView: View {
    @ObservedObject var model: VideoEditorModel
    let kinds: Set<VideoMediaKind>

    @State private var query = ""
    @State private var folder: UUID?
    @State private var asList = Settings.videoMediaBinAsList
    @State private var sort = VideoMediaSort.remembered
    @State private var selected: String?
    @State private var dropTargeted = false
    /// Lengths read from the files, for the tiles and sorting by length.
    @State private var durations: [String: Double] = [:]

    /// The Audio tab: sound only, no folders.
    private var flat: Bool { kinds == [.audio] }

    var body: some View {
        let all = model.mediaEntries
        let shown = VideoMediaArrangement.entries(all, kinds: kinds, folder: folder, flat: flat, query: query, sort: sort) { entry in
            entry.duration ?? durations[entry.path]
        }
        let folders = flat || !query.isEmpty || folder != nil ? [] : (model.project.mediaBin?.folders ?? [])
        VStack(spacing: 0) {
            header(all: all)
            if let folder, query.isEmpty, !flat, let current = model.project.mediaBin?.folders.first(where: { $0.id == folder }) {
                breadcrumb(current)
            }
            ScrollView {
                if shown.isEmpty, folders.isEmpty {
                    empty
                } else if asList {
                    LazyVStack(spacing: 2) {
                        ForEach(folders) { folderRow($0) }
                        ForEach(shown) { row($0) }
                    }
                    .padding(8)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 10) {
                        ForEach(folders) { folderTile($0) }
                        ForEach(shown) { tile($0) }
                    }
                    .padding(8)
                }
            }
            .onTapGesture { selected = nil }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(dropTargeted ? 1 : 0)
                .padding(2)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Task { @MainActor in arrive(await VideoMediaDrop.urls(from: providers), in: folder) }
            return true
        }
        .onChange(of: model.project.mediaBin?.folders) { folders in
            if let current = folder, !(folders ?? []).contains(where: { $0.id == current }) { folder = nil }
        }
    }

    // MARK: Header

    private func header(all: [VideoMediaEntry]) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                TextField(L("Search"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(VideoEditorTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Clear search"))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.well))
            if model.isExtractingAudio {
                ProgressView().controlSize(.small).help(L("Extracting the sound…"))
            }
            Button {
                model.chooseMediaToImport(into: flat ? nil : folder)
            } label: {
                Label(L("Import"), systemImage: "plus")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .help(L("Import videos, pictures, and sound files (⌘I)"))
            Menu {
                Picker(L("View"), selection: Binding(get: { asList }, set: { asList = $0; Settings.videoMediaBinAsList = $0 })) {
                    Label(L("Thumbnails"), systemImage: "square.grid.2x2").tag(false)
                    Label(L("List"), systemImage: "list.bullet").tag(true)
                }
                .pickerStyle(.inline)
                Picker(L("Sort By"), selection: Binding(get: { sort }, set: { sort = $0; VideoMediaSort.remembered = $0 })) {
                    ForEach(VideoMediaSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                if !flat {
                    Divider()
                    Button(L("New Folder…")) { newFolder() }
                }
                let videos = all.filter { $0.kind == .video && !$0.isMissing }
                if !videos.isEmpty {
                    Divider()
                    Menu(L("Extract Audio")) {
                        ForEach(videos) { entry in
                            Button(entry.name) { Task { await model.extractAudio(entry) } }
                        }
                    }
                    .disabled(model.isExtractingAudio)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("View, sort, folders, and Extract Audio"))
            .accessibilityLabel(L("Library options"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func breadcrumb(_ current: VideoMediaFolder) -> some View {
        HStack(spacing: 4) {
            Button {
                folder = nil
            } label: {
                Label(L("All media"), systemImage: "chevron.left")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            Text("›").foregroundStyle(VideoEditorTheme.textTertiary) // l10n-ignore: a separator
            Text(current.name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: flat ? "music.note" : "photo.on.rectangle.angled")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(VideoEditorTheme.textTertiary)
            Text(!query.isEmpty ? L("Nothing matches “\(query)”") : flat ? L("No sound yet") : L("Nothing here yet"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textSecondary)
            if query.isEmpty {
                Text(L("Import videos, pictures, and sound files, or drag them here from Finder."))
                    .font(.system(size: 11))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Import Media…")) { model.chooseMediaToImport(into: flat ? nil : folder) }
                    .buttonStyle(VideoSecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 30)
    }

    // MARK: Tiles and rows

    private func tile(_ entry: VideoMediaEntry) -> some View {
        VideoMediaTile(model: model, entry: entry, duration: entry.duration ?? durations[entry.path], selected: selected == entry.key) { length in
            durations[entry.path] = length
        }
        .onTapGesture { selected = entry.key }
        .onDrag { NSItemProvider(object: entry.url as NSURL) }
        .contextMenu { menu(entry) }
    }

    private func row(_ entry: VideoMediaEntry) -> some View {
        VideoMediaRow(model: model, entry: entry, duration: entry.duration ?? durations[entry.path], selected: selected == entry.key) { length in
            durations[entry.path] = length
        }
        .onTapGesture { selected = entry.key }
        .onDrag { NSItemProvider(object: entry.url as NSURL) }
        .contextMenu { menu(entry) }
    }

    private func folderTile(_ item: VideoMediaFolder) -> some View {
        Button {
            folder = item.id
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.card)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in arrive(await VideoMediaDrop.urls(from: providers), in: item.id) }
            return true
        }
        .contextMenu { folderMenu(item) }
        .accessibilityLabel(L("Folder \(item.name)"))
    }

    private func folderRow(_ item: VideoMediaFolder) -> some View {
        Button {
            folder = item.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .frame(width: 48)
                Text(item.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
            }
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in arrive(await VideoMediaDrop.urls(from: providers), in: item.id) }
            return true
        }
        .contextMenu { folderMenu(item) }
        .accessibilityLabel(L("Folder \(item.name)"))
    }

    // MARK: Menus

    @ViewBuilder
    private func menu(_ entry: VideoMediaEntry) -> some View {
        Button(L("Add to Timeline")) { Task { await model.placeEntry(entry) } }
            .disabled(entry.isMissing)
        if entry.kind == .video {
            Button(L("Extract Audio")) { Task { await model.extractAudio(entry) } }
                .disabled(entry.isMissing || model.isExtractingAudio)
        }
        Divider()
        Button(L("Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            .disabled(entry.isMissing)
        Button(L("Rename…")) {
            if let name = VideoMediaPrompt.ask(title: L("Rename “\(entry.name)”"), detail: L("The name in the Library. The file keeps its own."), value: entry.name, button: L("Rename")) {
                model.renameMedia(entry, to: name)
            }
        }
        if !flat, let folders = model.project.mediaBin?.folders, !folders.isEmpty {
            Menu(L("Move to Folder")) {
                Button(L("All media")) { model.moveMedia(entry, to: nil) }.disabled(entry.folder == nil)
                Divider()
                ForEach(folders) { item in
                    Button(item.name) { model.moveMedia(entry, to: item.id) }.disabled(entry.folder == item.id)
                }
            }
        }
        if entry.canReplace {
            if entry.isMissing {
                Button(L("Locate…")) { model.chooseReplacement(for: entry) }
            }
            Button(L("Replace…")) { model.chooseReplacement(for: entry) }
        }
        Divider()
        Button(L("Delete from Project")) { delete(entry) }
            .disabled(!entry.canDelete)
    }

    @ViewBuilder
    private func folderMenu(_ item: VideoMediaFolder) -> some View {
        Button(L("Open")) { folder = item.id }
        Button(L("Rename…")) {
            if let name = VideoMediaPrompt.ask(title: L("Rename “\(item.name)”"), detail: nil, value: item.name, button: L("Rename")) {
                model.renameMediaFolder(item.id, to: name)
            }
        }
        Divider()
        Button(L("Delete Folder")) { model.deleteMediaFolder(item.id) }
    }

    // MARK: Actions

    private func newFolder() {
        if let name = VideoMediaPrompt.ask(title: L("New Folder"), detail: nil, value: L("New Folder"), button: L("Create")) {
            folder = model.newMediaFolder(named: name)
        }
    }

    private func delete(_ entry: VideoMediaEntry) {
        if entry.isInVideo {
            let alert = NSAlert()
            alert.messageText = L("Delete “\(entry.name)” from the project?")
            alert.informativeText = L("It also comes out of the video. The file stays where it is, and ⌘Z brings it back.")
            alert.addButton(withTitle: L("Delete"))
            alert.addButton(withTitle: L("Cancel"))
            alert.buttons.first?.hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        model.deleteMedia(entry)
    }

    /// Files dropped on the Library or a folder: the Library's own move
    /// there, others are imported there.
    private func arrive(_ urls: [URL], in target: UUID?) {
        let entries = model.mediaEntries
        var outside: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            if let entry = entries.first(where: { $0.path == path }) {
                if !flat { model.moveMedia(entry, to: target) }
            } else {
                outside.append(url)
            }
        }
        if !outside.isEmpty { model.importMedia(outside, into: flat ? nil : target) }
    }
}

// MARK: - One piece of media

struct VideoMediaTile: View {
    @ObservedObject var model: VideoEditorModel
    let entry: VideoMediaEntry
    let duration: Double?
    let selected: Bool
    let learnedDuration: (Double) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                VideoMediaThumbnail(entry: entry, scrubs: true, learnedDuration: learnedDuration)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack {
                    HStack(alignment: .top) {
                        if entry.isInVideo {
                            VideoMediaBadge(text: L("Added"), symbol: "checkmark")
                                .help(L("In the video"))
                        }
                        Spacer()
                        if hovering, !entry.isMissing {
                            Button {
                                Task { await model.placeEntry(entry) }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.accentColor))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .help(L("Add to Timeline"))
                            .accessibilityLabel(L("Add to Timeline"))
                        }
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        if let duration, entry.kind != .image {
                            VideoMediaBadge(text: VideoEditorModel.format(duration), symbol: nil)
                        }
                    }
                }
                .padding(4)
                if entry.isMissing { VideoMediaMissing(model: model, entry: entry) }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : VideoEditorTheme.cardStroke, lineWidth: selected ? 2 : 1)
            )
            Text(entry.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(entry.isMissing ? VideoEditorTheme.warning : VideoEditorTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(entry.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VideoMediaRow.accessibility(entry, duration: duration))
    }
}

struct VideoMediaRow: View {
    @ObservedObject var model: VideoEditorModel
    let entry: VideoMediaEntry
    let duration: Double?
    let selected: Bool
    let learnedDuration: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            VideoMediaThumbnail(entry: entry, scrubs: false, learnedDuration: learnedDuration)
                .frame(width: 48, height: 27)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(entry.isMissing ? VideoEditorTheme.warning : VideoEditorTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.detail(entry, duration: duration))
                    .font(.system(size: 10))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if entry.isMissing {
                Button(L("Locate…")) { model.chooseReplacement(for: entry) }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .disabled(!entry.canReplace)
            } else if entry.isInVideo {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .help(L("In the video"))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? Color.accentColor.opacity(0.18) : Color.clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibility(entry, duration: duration))
    }

    static func kindTitle(_ kind: VideoMediaKind) -> String {
        switch kind {
        case .video: return L("Video")
        case .image: return L("Picture")
        case .audio: return L("Sound")
        }
    }

    static func detail(_ entry: VideoMediaEntry, duration: Double?) -> String {
        if entry.isMissing { return L("Missing — Locate… finds it") }
        guard let duration, entry.kind != .image else { return kindTitle(entry.kind) }
        return "\(kindTitle(entry.kind)) · \(VideoEditorModel.format(duration))" // l10n-ignore: parts already translated
    }

    static func accessibility(_ entry: VideoMediaEntry, duration: Double?) -> String {
        var parts = [entry.name, detail(entry, duration: duration)]
        if entry.isInVideo { parts.append(L("In the video")) }
        return parts.joined(separator: ", ")
    }
}

/// A video's frame (scrubbed by moving over it), a picture, or a sound's
/// symbol.
struct VideoMediaThumbnail: View {
    let entry: VideoMediaEntry
    let scrubs: Bool
    let learnedDuration: (Double) -> Void

    @State private var cover: NSImage?
    @State private var scrubbed: NSImage?
    @State private var frame: Int?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(VideoEditorTheme.well)
                if let image = scrubbed ?? cover {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: entry.kind == .image ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Image(systemName: entry.kind == .audio ? "waveform" : entry.kind == .image ? "photo" : "film")
                        .font(.system(size: min(geometry.size.height * 0.4, 22), weight: .medium))
                        .foregroundStyle(entry.kind == .audio ? VideoEditorTheme.addedAudio : VideoEditorTheme.textTertiary)
                }
                if scrubs, let frame, entry.kind == .video {
                    // Where along the video this frame is.
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: geometry.size.height)
                            .offset(x: (CGFloat(frame) + 0.5) / CGFloat(VideoMediaThumbnails.scrubFrames) * geometry.size.width - geometry.size.width / 2)
                    }
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard scrubs, entry.kind == .video, !entry.isMissing else { return }
                switch phase {
                case .active(let point):
                    let width = max(geometry.size.width, 1)
                    frame = min(max(Int(point.x / width * CGFloat(VideoMediaThumbnails.scrubFrames)), 0), VideoMediaThumbnails.scrubFrames - 1)
                case .ended:
                    frame = nil
                }
            }
        }
        .task(id: entry.path) {
            guard !entry.isMissing else { return }
            cover = await VideoMediaThumbnails.shared.image(entry.path, kind: entry.kind, frame: nil)
            if entry.duration == nil, entry.kind != .image, let length = await VideoMediaThumbnails.shared.duration(entry.path) {
                learnedDuration(length)
            }
        }
        .task(id: frame) {
            guard let frame else { scrubbed = nil; return }
            scrubbed = VideoMediaThumbnails.shared.cached(entry.path, frame: frame) ?? scrubbed
            scrubbed = await VideoMediaThumbnails.shared.image(entry.path, kind: entry.kind, frame: frame) ?? scrubbed
        }
    }
}

struct VideoMediaBadge: View {
    let text: String
    let symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .heavy)) }
            Text(text).font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.black.opacity(0.62)))
        .foregroundStyle(.white)
    }
}

/// On a tile whose file is gone: what happened and Locate….
struct VideoMediaMissing: View {
    @ObservedObject var model: VideoEditorModel
    let entry: VideoMediaEntry

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(0.55))
            VStack(spacing: 4) {
                Label(L("Missing"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                if entry.canReplace {
                    Button(L("Locate…")) { model.chooseReplacement(for: entry) }
                        .controlSize(.small)
                }
            }
        }
    }
}

/// A one-line question with a text field (Rename…, New Folder…).
@MainActor
enum VideoMediaPrompt {
    static func ask(title: String, detail: String?, value: String, button: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        if let detail { alert.informativeText = detail }
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
