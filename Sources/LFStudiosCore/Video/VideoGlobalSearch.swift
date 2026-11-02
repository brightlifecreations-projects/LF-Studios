import SwiftUI

// MARK: - One search for everything (1.17.0, LF Studios layout)

/// ⌘K in the LF Studios layout: besides the commands, the media, the clips
/// (by name), the captions (by their words) and the markers. Commands run;
/// the rest are shown: selected, and the playhead goes there.
enum VideoGlobalSearch {
    enum Group: String, CaseIterable {
        case commands, media, clips, captions, markers

        var title: String {
            switch self {
            case .commands: return L("Commands")
            case .media: return L("Media")
            case .clips: return L("Clips")
            case .captions: return L("Captions")
            case .markers: return L("Markers")
            }
        }
    }

    struct Result: Identifiable, Equatable {
        let id: String
        let group: Group
        let title: String
        /// On the right: where it is, or its keys.
        let detail: String
        let symbol: String
        let target: Target
    }

    /// What choosing it does (a command runs from the palette's own list).
    enum Target: Equatable {
        case command(String)
        case media(path: String)
        case clip(VideoEditorModel.Selection, time: Double)
        case caption(UUID, time: Double)
        case marker(time: Double)
    }

    /// At most this many of each kind (commands are listed by the palette).
    static let perGroup = 6

    /// Everything but the commands that matches `query` (case and accents
    /// ignored), grouped in this order: media, clips, captions, markers.
    @MainActor
    static func results(_ query: String, in model: VideoEditorModel) -> [Result] {
        let search = query.trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty else { return [] }
        func matches(_ text: String) -> Bool { text.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        var results: [Result] = []

        let media = model.mediaEntries.filter { matches($0.name) || matches($0.fileName) }.prefix(perGroup)
        results += media.map { entry in
            Result(id: "media-\(entry.key)", group: .media, title: entry.name, detail: entry.kind.title, symbol: entry.kind.symbol, target: .media(path: entry.path))
        }

        var clips: [Result] = []
        for (index, segment) in model.segments.enumerated() {
            let name = L("Clip \(index + 1)")
            if matches(name) {
                clips.append(Result(id: "clip-\(segment.id)", group: .clips, title: name, detail: "\(VideoTrackNames.mainTrack) · \(VideoEditorModel.timecode(segment.timelineStart))",
                                    symbol: "film", target: .clip(.clip(segment.id), time: segment.timelineStart)))
            }
        }
        for (track, item) in model.project.layerItems where matches(item.name) || (item.text.map { matches($0.string) } ?? false) {
            clips.append(Result(id: "layer-\(item.id)", group: .clips, title: item.name, detail: "\(VideoTrackNames.layer(track)) · \(VideoEditorModel.timecode(item.at))",
                                symbol: VideoAtPlayhead.symbol(item), target: .clip(.layer(item.id), time: item.at)))
        }
        results += clips.prefix(perGroup)

        let captions = model.project.captions.filter { matches($0.text) }.prefix(perGroup)
        results += captions.map { line in
            let time = model.timelineTime(forSource: line.start) ?? line.start
            return Result(id: "caption-\(line.id)", group: .captions, title: line.text, detail: VideoEditorModel.timecode(time), symbol: "captions.bubble", target: .caption(line.id, time: time))
        }

        let markers = model.placedMarkers.filter { matches($0.title) }.prefix(perGroup)
        results += markers.map { marker in
            Result(id: "marker-\(marker.id)", group: .markers, title: marker.title, detail: VideoEditorModel.timecode(marker.time), symbol: "flag", target: .marker(time: marker.time))
        }
        return results
    }

    /// Shows a result: selects it and moves the playhead there (media:
    /// Library ▸ Media, and where the video uses it). Never starts playing.
    @MainActor
    static func show(_ target: Target, in model: VideoEditorModel) {
        switch target {
        case .command:
            break
        case .media(let path):
            model.libraryTab = .media
            if let used = model.project.layerItems.first(where: { $0.item.path == path }) {
                model.selection = .layer(used.item.id)
                model.seek(to: used.item.at)
            }
        case .clip(let selection, let time):
            model.selection = selection
            model.seek(to: time)
        case .caption(let id, let time):
            model.propertiesTab = .captions
            model.selection = .caption(id)
            model.seek(to: time)
        case .marker(let time):
            model.seek(to: time)
        }
    }
}

extension VideoMediaKind {
    var title: String {
        switch self {
        case .video: return L("Video")
        case .image: return L("Picture")
        case .audio: return L("Audio")
        }
    }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .image: return "photo"
        case .audio: return "waveform"
        }
    }
}
