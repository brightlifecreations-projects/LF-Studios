import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library ▸ Captions (1.15.0)

/// Subtitle files read back in (.srt and .vtt).
enum VideoSubtitleImport {
    struct Cue: Equatable {
        var start: Double
        var end: Double
        var text: String
    }

    /// The cues of an .srt or .vtt file (timeline seconds), in order. Tags
    /// like <i> and {\an8} are dropped.
    static func parse(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var cues: [Cue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = time(parts[0]), let end = time(parts[1].split(separator: " ").first.map(String.init) ?? parts[1]), end > start else { continue }
            let words = lines[(timing + 1)...].map(clean).filter { !$0.isEmpty }.joined(separator: " ")
            guard !words.isEmpty else { continue }
            cues.append(Cue(start: start, end: end, text: words))
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// "00:01:02,500", "01:02.500" or "1:02:03.25".
    static func time(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let number = Double(part), number >= 0 else { return nil }
            seconds = seconds * 60 + number
        }
        return seconds
    }

    private static func clean(_ line: String) -> String {
        var text = line
        while let open = text.range(of: "<"), let close = text.range(of: ">", range: open.upperBound..<text.endIndex) { text.removeSubrange(open.lowerBound..<close.upperBound) }
        while let open = text.range(of: "{"), let close = text.range(of: "}", range: open.upperBound..<text.endIndex) { text.removeSubrange(open.lowerBound..<close.upperBound) }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Cues as caption lines on the recording's own clock (what the
    /// captions store), each word given an even share of its cue for the
    /// spoken-word highlight. Cues on no clip are left out.
    static func lines(_ cues: [Cue], segments: [VideoDemoTimelineSegment]) -> [VideoCaptionLine] {
        cues.compactMap { cue in
            guard let segment = segments.first(where: { cue.start >= $0.timelineStart - 0.001 && cue.start < $0.timelineEnd }) else { return nil }
            let start = segment.sourceTime(forTimelineTime: cue.start)
            let end = segment.sourceTime(forTimelineTime: min(cue.end, segment.timelineEnd))
            guard end > start + 0.05 else { return nil }
            let words = cue.text.split(separator: " ").map(String.init)
            let share = (end - start) / Double(max(words.count, 1))
            let timed = words.enumerated().map { i, word in VideoCaptionWord(text: word, start: start + Double(i) * share, end: start + Double(i + 1) * share) }
            return VideoCaptionLine(start: start, end: end, text: cue.text, words: timed)
        }
    }
}

extension VideoEditorModel {
    /// Import Captions…: an .srt or .vtt file in place of the captions
    /// (one ⌘Z step brings the old ones back).
    func importSubtitles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText, UTType(filenameExtension: "vtt") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importSubtitles(from: url)
    }

    @discardableResult
    func importSubtitles(from url: URL) -> Int {
        if refuseLocked(.captions) { return 0 }
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return 0 }
        let lines = VideoSubtitleImport.lines(VideoSubtitleImport.parse(text), segments: segments)
        guard !lines.isEmpty else {
            showNotice(L("No captions found in “\(url.lastPathComponent)”"), symbol: "exclamationmark.triangle.fill")
            return 0
        }
        mutate(label: "Import Captions") { project in
            project.captions = lines
            // Translations were of the old lines.
            project.captionTracks = VideoCaptionTracks()
            project.captionStyle.visible = true
        }
        showNotice(L("Imported \(lines.count) captions from “\(url.lastPathComponent)”"), symbol: "captions.bubble")
        return lines.count
    }
}

// MARK: - Caption style templates

/// A ready-made caption look: one of the looks, a macOS font, a highlight
/// colour, an animation, a size and a place.
struct VideoCaptionTemplate: Identifiable {
    var id: String
    var title: String
    var preset: VideoCaptionPreset
    var font: String?
    var weight: VideoFontChoice.Weight?
    var outline = false
    var shadow = false
    var highlight: VideoRGBA?
    var highlightWords = true
    var animation: VideoCaptionAnimation = .none
    var size: VideoTextSize = .medium
    var position: VideoTextPosition = .bottom

    static var all: [VideoCaptionTemplate] {
        [
            VideoCaptionTemplate(id: "clean", title: L("Clean"), preset: .classic, highlightWords: false),
            VideoCaptionTemplate(id: "karaoke", title: L("Karaoke"), preset: .outline, font: "Avenir Next", weight: .black, highlight: VideoRGBA(hex: 0xFFD60A), animation: .karaoke, size: .large),
            VideoCaptionTemplate(id: "one-word", title: L("One word"), preset: .outline, font: "Futura", weight: .bold, highlight: VideoRGBA(hex: 0x30D158), animation: .oneWord, size: .large),
            VideoCaptionTemplate(id: "pop", title: L("Pop"), preset: .highlight, font: "Avenir Next", weight: .bold, highlight: VideoRGBA(hex: 0xFF375F), animation: .popIn),
            VideoCaptionTemplate(id: "bounce", title: L("Bounce"), preset: .outline, font: "Marker Felt", outline: true, highlight: VideoRGBA(hex: 0x64D2FF), animation: .bounce, size: .large),
            VideoCaptionTemplate(id: "typewriter", title: L("Typewriter"), preset: .minimal, font: "American Typewriter", shadow: true, highlightWords: false, animation: .typewriter),
            VideoCaptionTemplate(id: "fade-up", title: L("Soft rise"), preset: .minimal, font: "Gill Sans", shadow: true, highlightWords: false, animation: .fadeUp),
            VideoCaptionTemplate(id: "box", title: L("Word box"), preset: .highlight, font: "Helvetica Neue", weight: .bold, highlight: VideoRGBA(hex: 0x7C4DFF), animation: .highlightBox),
            VideoCaptionTemplate(id: "news", title: L("News"), preset: .classic, font: "Helvetica Neue", weight: .bold, highlightWords: false, size: .small),
            VideoCaptionTemplate(id: "top", title: L("Top line"), preset: .classic, font: "Avenir Next", highlightWords: false, position: .top),
            VideoCaptionTemplate(id: "elegant", title: L("Elegant"), preset: .minimal, font: "Didot", shadow: true, highlightWords: false, animation: .fadeUp),
            VideoCaptionTemplate(id: "loud", title: L("Loud"), preset: .outline, font: "Impact", outline: true, highlight: VideoRGBA(hex: 0xFF9F0A), animation: .popIn, size: .large),
        ]
    }

    func apply(to style: inout VideoCaptionStyle) {
        style.preset = preset
        style.font = font == nil && weight == nil && !outline && !shadow ? nil : VideoFontChoice(family: font, weight: weight, outline: outline, shadow: shadow)
        style.highlightColor = highlight
        style.highlightWords = highlightWords
        style.animation = animation
        style.size = size
        style.position = position
        style.placement = nil
        style.visible = true
    }

    var style: VideoCaptionStyle {
        var style = VideoCaptionStyle()
        apply(to: &style)
        return style
    }
}

extension VideoEditorModel {
    /// A caption template on every caption. One ⌘Z step.
    @discardableResult
    func applyCaptionTemplate(_ template: VideoCaptionTemplate) -> Bool {
        if refuseLocked(.captions) { return false }
        mutate(label: "Caption Style") { project in template.apply(to: &project.captionStyle) }
        if project.captions.isEmpty {
            showNotice(L("Style set — make or import captions to see it"), symbol: "captions.bubble")
        }
        return true
    }
}

struct VideoCaptionsLibraryTab: View {
    @ObservedObject var model: VideoEditorModel

    private var tiles: [VideoLibraryTile] {
        VideoCaptionTemplate.all.map { VideoLibraryTile(payload: .init(kind: "caption", id: $0.id), title: $0.title, keywords: [$0.animation.title], section: L("Caption styles")) }
    }

    var body: some View {
        VideoLibraryGrid(model: model, tiles: tiles, minimum: 110, tileHeight: 50) {
            VStack(spacing: 8) {
                Button {
                    model.selection = .none
                    model.inspectorTab = .captions
                    model.generateCaptions()
                } label: {
                    Label(model.project.captions.isEmpty ? L("Auto captions") : L("Make captions again"), systemImage: "waveform.badge.mic").frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .disabled(model.captionTask != nil)
                .help(L("Captions from what's said, made on this Mac (language and Whisper in the Captions panel)"))
                HStack(spacing: 8) {
                    Button { model.importSubtitles() } label: {
                        Label(L("Import .srt…"), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .help(L("Captions from an .srt or .vtt file, in place of these"))
                    Button { model.exportSubtitles(.srt) } label: {
                        Label(L("Export .srt…"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .disabled(model.project.captions.isEmpty)
                }
            }
        } preview: { tile, hovering in
            if let template = VideoCaptionTemplate.all.first(where: { $0.id == tile.payload.id }) {
                VideoCaptionTemplatePreview(template: template, hovering: hovering, selected: model.project.captionStyle == template.style)
            }
        }
    }
}

/// A sample line drawn by the real caption renderer; hovering steps the
/// spoken word along.
struct VideoCaptionTemplatePreview: View {
    let template: VideoCaptionTemplate
    let hovering: Bool
    let selected: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.24, green: 0.3, blue: 0.46), Color(red: 0.42, green: 0.3, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if hovering {
                TimelineView(.periodic(from: .now, by: 0.35)) { timeline in
                    line(spoken: Int(timeline.date.timeIntervalSinceReferenceDate / 0.35) % 3)
                }
            } else {
                line(spoken: 1)
            }
            if selected {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(4)
            }
        }
    }

    @ViewBuilder
    private func line(spoken: Int) -> some View {
        if let image = Self.image(template, spoken: spoken) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(.horizontal, 6)
        }
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(_ template: VideoCaptionTemplate, spoken: Int) -> NSImage? {
        let sample = L("Captions look like this")
        let key = "\(template.id)-\(spoken)-\(sample)"
        if let cached = cache[key] { return cached }
        let words = sample.split(separator: " ").map(String.init)
        guard let cg = VideoCaptionDrawing.image(text: VideoCaptionBuilder.joined(words), words: words, spoken: min(spoken, max(words.count - 1, 0)), style: template.style, fontSize: 26, maxWidth: 400) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        cache[key] = image
        return image
    }
}
