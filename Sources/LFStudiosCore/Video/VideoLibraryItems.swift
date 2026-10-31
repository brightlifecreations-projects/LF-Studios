import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library items: text templates, stickers, effects… (1.15.0)

/// Something from a Library tab (not a file): dragged onto the timeline or
/// the player, or clicked to add at the playhead.
struct VideoLibraryPayload: Equatable, Hashable {
    /// The tab it's from ("text", "sticker", "effect", "filter",
    /// "adjustment", "transition", "sound", "caption").
    var kind: String
    var id: String

    static let prefix = "lfstudios-library:"
    var string: String { Self.prefix + kind + "/" + id }
    /// Its key among the favourites.
    var key: String { kind + "/" + id }

    init(kind: String, id: String) {
        self.kind = kind
        self.id = id
    }

    init?(string: String) {
        guard string.hasPrefix(Self.prefix) else { return nil }
        let rest = string.dropFirst(Self.prefix.count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        kind = String(rest[..<slash])
        id = String(rest[rest.index(after: slash)...])
        guard !kind.isEmpty, !id.isEmpty else { return nil }
    }

    var itemProvider: NSItemProvider { NSItemProvider(object: string as NSString) }
}

extension VideoEditorModel {
    /// A Library item at `time` (nil: the playhead) where it was dropped.
    /// Each tab adds its own kinds (VideoTextTemplates.swift and others).
    @discardableResult
    func placeLibraryItem(_ payload: VideoLibraryPayload, at time: Double?, target: DropTarget = .anywhere) -> Bool {
        let place: LayerPlace
        switch target {
        case .layer(let p): place = p
        case .main, .anywhere: place = .automatic
        }
        for handler in Self.libraryHandlers where handler.kind == payload.kind {
            return handler.place(self, payload.id, time, place)
        }
        return false
    }

    struct LibraryHandler {
        var kind: String
        var place: @MainActor (VideoEditorModel, String, Double?, LayerPlace) -> Bool
    }

    static var libraryHandlers: [LibraryHandler] {
        [
            LibraryHandler(kind: "text") { model, id, time, place in
                guard let template = VideoTextTemplate.all.first(where: { $0.id == id }) else { return false }
                model.addTextTemplate(template, at: time, place: place)
                return true
            },
            LibraryHandler(kind: "transition") { model, id, time, _ in
                guard let kind = VideoTransitionKind(rawValue: id) else { return false }
                if time == nil { return model.perform(.clip(.setTransition(kind, Settings.videoTransitionLength))) }
                guard !model.refuseLocked(.clips), let cut = model.transitionCutClip(near: time) else { return false }
                model.setTransition(into: cut, kind: kind, duration: Settings.videoTransitionLength)
                return true
            },
            LibraryHandler(kind: "filter") { model, id, time, place in
                guard let look = VideoFilterLook(rawValue: id) else { return false }
                return model.addFilter(VideoAppliedFilter(look: look), at: time, place: place, onSelection: time == nil)
            },
            LibraryHandler(kind: "adjustment") { model, id, time, place in
                guard let preset = VideoAdjustPreset.all.first(where: { $0.id == id }) else { return false }
                return model.addAdjustment(preset, at: time, place: place, onSelection: time == nil)
            },
            LibraryHandler(kind: "caption") { model, id, _, _ in
                guard let template = VideoCaptionTemplate.all.first(where: { $0.id == id }) else { return false }
                return model.applyCaptionTemplate(template)
            },
            LibraryHandler(kind: "sound") { model, id, time, _ in
                guard let effect = VideoSoundEffect(rawValue: id) else { return false }
                Task { await model.addSoundEffect(effect, at: time) }
                return true
            },
            LibraryHandler(kind: "sticker") { model, id, time, place in
                guard let sticker = VideoSticker(rawValue: id) else { return false }
                model.addSticker(sticker, at: time, place: place)
                return true
            },
            LibraryHandler(kind: "effect") { model, id, time, place in
                guard let kind = VideoEffectKind(rawValue: id) else { return false }
                // Dropped somewhere: an effect clip there; + : on the selection.
                return model.addEffect(kind, at: time, place: place, onSelection: time == nil)
            },
        ]
    }

    /// Starred Library items (kept for every project).
    func isFavourite(_ payload: VideoLibraryPayload) -> Bool { libraryFavourites.contains(payload.key) }

    func toggleFavourite(_ payload: VideoLibraryPayload) {
        var stars = libraryFavourites
        if let i = stars.firstIndex(of: payload.key) { stars.remove(at: i) } else { stars.append(payload.key) }
        libraryFavourites = stars
        Settings.videoLibraryFavourites = stars
    }
}

extension VideoMediaDrop {
    /// Library items in a drag (as text).
    static func payloads(from providers: [NSItemProvider]) async -> [VideoLibraryPayload] {
        var payloads: [VideoLibraryPayload] = []
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            if let text = await withCheckedContinuation({ (done: CheckedContinuation<String?, Never>) in
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in done.resume(returning: value as? String) }
            }), let payload = VideoLibraryPayload(string: text) {
                payloads.append(payload)
            }
        }
        return payloads
    }
}

/// One item in a Library grid.
struct VideoLibraryTile: Identifiable {
    var payload: VideoLibraryPayload
    var title: String
    /// Words to find it by (besides its title).
    var keywords: [String] = []
    var section: String
    var id: String { payload.key }

    /// The tiles with every word of `search` in their title, section or
    /// keywords (and starred, when `favourites` is given).
    static func matching(_ tiles: [VideoLibraryTile], search: String, favourites: Set<String>?) -> [VideoLibraryTile] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        return tiles.filter { tile in
            (favourites?.contains(tile.payload.key) ?? true)
                && words.allSatisfy { word in tile.title.lowercased().contains(word) || tile.section.lowercased().contains(word) || tile.keywords.contains { $0.lowercased().contains(word) } }
        }
    }
}

/// A Library tab's items: a search field, Favourites, sections of tiles.
/// Hovering a tile previews it; click + (or double-click) adds it at the
/// playhead; drag it onto the timeline or the player.
struct VideoLibraryGrid<Preview: View, Header: View>: View {
    @ObservedObject var model: VideoEditorModel
    let tiles: [VideoLibraryTile]
    var minimum: CGFloat = 92
    var tileHeight: CGFloat = 64
    let header: Header
    /// The tile's look; `hovering` plays its preview.
    let preview: (VideoLibraryTile, Bool) -> Preview

    @State private var search = ""
    @State private var onlyFavourites = false
    @State private var hovered: String?

    init(model: VideoEditorModel, tiles: [VideoLibraryTile], minimum: CGFloat = 92, tileHeight: CGFloat = 64,
         @ViewBuilder header: () -> Header, @ViewBuilder preview: @escaping (VideoLibraryTile, Bool) -> Preview) {
        self.model = model
        self.tiles = tiles
        self.minimum = minimum
        self.tileHeight = tileHeight
        self.header = header()
        self.preview = preview
    }

    private var shown: [VideoLibraryTile] {
        VideoLibraryTile.matching(tiles, search: search, favourites: onlyFavourites ? Set(model.libraryFavourites) : nil)
    }

    private var sections: [(String, [VideoLibraryTile])] {
        var order: [String] = []
        var groups: [String: [VideoLibraryTile]] = [:]
        for tile in shown {
            if groups[tile.section] == nil { order.append(tile.section) }
            groups[tile.section, default: []].append(tile)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(VideoEditorTheme.textTertiary)
                    TextField(L("Search"), text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                            .buttonStyle(.plain)
                            .foregroundStyle(VideoEditorTheme.textTertiary)
                            .accessibilityLabel(L("Clear search"))
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.well))
                Button {
                    onlyFavourites.toggle()
                } label: {
                    Image(systemName: onlyFavourites ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(onlyFavourites ? Color.yellow : VideoEditorTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.card))
                }
                .buttonStyle(.plain)
                .help(L("Show only favourites"))
                .accessibilityLabel(L("Favourites"))
                .accessibilityAddTraits(onlyFavourites ? .isSelected : [])
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if shown.isEmpty {
                        Text(onlyFavourites ? L("No favourites yet: hover an item and click its star.") : L("Nothing matches “\(search)”."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(VideoEditorTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    }
                    ForEach(sections, id: \.0) { section, tiles in
                        Text(section)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(VideoEditorTheme.textTertiary)
                            .textCase(.uppercase)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 8)], spacing: 8) {
                            ForEach(tiles) { tile in tileView(tile) }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }

    private func tileView(_ tile: VideoLibraryTile) -> some View {
        let hovering = hovered == tile.id
        let favourite = model.isFavourite(tile.payload)
        return VStack(spacing: 4) {
            preview(tile, hovering)
                .frame(maxWidth: .infinity)
                .frame(height: tileHeight)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(hovering ? VideoEditorTheme.layer : VideoEditorTheme.cardStroke, lineWidth: hovering ? 1.5 : 1))
                .overlay(alignment: .topTrailing) {
                    if hovering || favourite {
                        Button { model.toggleFavourite(tile.payload) } label: {
                            Image(systemName: favourite ? "star.fill" : "star")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(favourite ? Color.yellow : Color.white)
                                .shadow(color: .black.opacity(0.6), radius: 1.5)
                                .padding(5)
                        }
                        .buttonStyle(.plain)
                        .help(favourite ? L("Remove from favourites") : L("Add to favourites"))
                        .accessibilityLabel(favourite ? L("Remove from favourites") : L("Add to favourites"))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if hovering {
                        Button { model.placeLibraryItem(tile.payload, at: nil) } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, VideoEditorTheme.layer)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help(L("Add at the playhead"))
                        .accessibilityLabel(L("Add at the playhead"))
                    }
                }
            Text(tile.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? tile.id : (hovered == tile.id ? nil : hovered) }
        .onTapGesture(count: 2) { model.placeLibraryItem(tile.payload, at: nil) }
        .onDrag { tile.payload.itemProvider }
        .help(L("“\(tile.title)” — drag onto the timeline, or double-click to add it at the playhead"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tile.title)
        .accessibilityAction { model.placeLibraryItem(tile.payload, at: nil) }
    }
}

extension VideoLibraryGrid where Header == EmptyView {
    init(model: VideoEditorModel, tiles: [VideoLibraryTile], minimum: CGFloat = 92, tileHeight: CGFloat = 64, @ViewBuilder preview: @escaping (VideoLibraryTile, Bool) -> Preview) {
        self.init(model: model, tiles: tiles, minimum: minimum, tileHeight: tileHeight, header: { EmptyView() }, preview: preview)
    }
}
