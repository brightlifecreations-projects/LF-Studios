import AppKit
import SwiftUI

// MARK: - Library ▸ Text: templates and styles (1.15.0)

/// A ready-made text clip: words, a look and (for some) an animation. Our
/// own designs, in fonts that come with macOS only.
struct VideoTextTemplate: Identifiable {
    var id: String
    var title: String
    var section: String
    var content: VideoTextContent
    var animation: VideoItemAnimation?
    /// Where it goes in the frame (shares from the top left).
    var x = 0.5
    var y = 0.5
    var keywords: [String] = []

    private static func look(_ string: String, font: String = VideoTextFonts.defaultFamily, size: Double = 72, bold: Bool = false, italic: Bool = false,
                             color: VideoRGBA = VideoRGBA(1, 1, 1), stroke: VideoTextContent.Stroke? = nil, background: VideoTextContent.Background? = nil,
                             shadow: VideoTextContent.Shadow? = nil, letterSpacing: Double = 0) -> VideoTextContent {
        var content = VideoTextContent(string: string)
        content.font = font
        content.size = size
        content.bold = bold
        content.italic = italic
        content.color = color
        content.stroke = stroke
        content.background = background
        content.shadow = shadow
        content.letterSpacing = letterSpacing
        return content
    }

    private static func moves(_ inPreset: VideoAnimationPreset?, _ outPreset: VideoAnimationPreset? = nil, combo: VideoComboPreset? = nil, length: Double = 0.5) -> VideoItemAnimation {
        VideoItemAnimation(inPreset: inPreset, inLength: length, outPreset: outPreset, outLength: length, combo: combo)
    }

    static var all: [VideoTextTemplate] {
        let titles = L("Titles"), lower = L("Lower thirds"), social = L("Social"), labels = L("Labels")
        let black = VideoRGBA(0, 0, 0), white = VideoRGBA(1, 1, 1)
        let soft = VideoTextContent.Shadow(color: VideoRGBA(0, 0, 0, 0.55), blur: 10, distance: 4)
        return [
            VideoTextTemplate(id: "title-clean", title: L("Clean title"), section: titles,
                              content: look(L("Big title"), size: 110, bold: true, shadow: soft), animation: moves(.fade, .fade), keywords: ["heading"]),
            VideoTextTemplate(id: "title-pop", title: L("Pop title"), section: titles,
                              content: look(L("Wow!"), font: "Futura", size: 130, bold: true, color: VideoRGBA(1, 0.85, 0.1), stroke: .init(color: black, width: 8)),
                              animation: moves(.pop, .zoomOut), keywords: ["bold", "yellow"]),
            VideoTextTemplate(id: "title-elegant", title: L("Elegant"), section: titles,
                              content: look(L("A new chapter"), font: "Didot", size: 96, italic: true, shadow: soft), animation: moves(.blur, .fade, length: 0.8), keywords: ["serif"]),
            VideoTextTemplate(id: "title-spaced", title: L("Spaced out"), section: titles,
                              content: look(L("STORY"), font: "Avenir Next", size: 90, bold: true, letterSpacing: 40), animation: moves(.zoomIn, .fade), keywords: ["minimal", "letters"]),
            VideoTextTemplate(id: "title-typewriter", title: L("Typewriter"), section: titles,
                              content: look(L("Once upon a time"), font: "American Typewriter", size: 80), animation: moves(.slideRight, .fade), keywords: ["retro"]),
            VideoTextTemplate(id: "title-impact", title: L("Impact"), section: titles,
                              content: look(L("BREAKING"), font: "Impact", size: 140, stroke: .init(color: black, width: 6)), animation: moves(.zoomOut, nil, combo: .shake), keywords: ["meme", "loud"]),
            VideoTextTemplate(id: "lower-bar", title: L("Name bar"), section: lower,
                              content: look(L("Alex Morgan · Designer"), size: 48, bold: true, background: .init(color: VideoRGBA(0.1, 0.1, 0.12, 0.85), padding: 22, radius: 6)),
                              animation: moves(.slideRight, .slideLeft), x: 0.3, y: 0.82, keywords: ["name", "speaker"]),
            VideoTextTemplate(id: "lower-accent", title: L("Accent bar"), section: lower,
                              content: look(L("Chapter 2"), font: "Avenir Next", size: 52, bold: true, background: .init(color: VideoRGBA(0.23, 0.66, 0.86, 1), padding: 20, radius: 0)),
                              animation: moves(.slideUp, .slideDown), x: 0.22, y: 0.84, keywords: ["blue", "chapter"]),
            VideoTextTemplate(id: "lower-light", title: L("Light card"), section: lower,
                              content: look(L("Recorded live"), font: "Gill Sans", size: 46, color: VideoRGBA(0.1, 0.1, 0.1), background: .init(color: VideoRGBA(1, 1, 1, 0.92), padding: 18, radius: 14)),
                              animation: moves(.fade, .fade), x: 0.25, y: 0.85, keywords: ["white"]),
            VideoTextTemplate(id: "social-caption", title: L("Bold caption"), section: social,
                              content: look(L("Wait for it…"), size: 76, bold: true, stroke: .init(color: black, width: 7)), animation: moves(.pop), y: 0.7, keywords: ["tiktok", "reel", "short"]),
            VideoTextTemplate(id: "social-bubble", title: L("Bubble"), section: social,
                              content: look(L("Link in bio"), font: "Avenir Next", size: 60, bold: true, color: black, background: .init(color: white, padding: 22, radius: 40)),
                              animation: moves(.pop, .zoomOut, combo: .pulse), y: 0.8, keywords: ["pill", "cta"]),
            VideoTextTemplate(id: "social-comic", title: L("Comic"), section: social,
                              content: look(L("POW!"), font: "Marker Felt", size: 120, color: VideoRGBA(1, 0.3, 0.2), stroke: .init(color: white, width: 8), shadow: soft),
                              animation: moves(.spin, .zoomOut, combo: .wobble), keywords: ["fun", "cartoon"]),
            VideoTextTemplate(id: "social-note", title: L("Handwritten"), section: social,
                              content: look(L("so good"), font: "Noteworthy", size: 84, bold: true, color: VideoRGBA(1, 0.95, 0.6), shadow: soft), animation: moves(.fade, .fade), keywords: ["note", "casual"]),
            VideoTextTemplate(id: "label-tag", title: L("Tag"), section: labels,
                              content: look(L("NEW"), font: "Avenir Next", size: 44, bold: true, background: .init(color: VideoRGBA(0.95, 0.25, 0.35, 1), padding: 14, radius: 8), letterSpacing: 6),
                              animation: moves(.pop, .fade), x: 0.85, y: 0.12, keywords: ["badge", "red"]),
            VideoTextTemplate(id: "label-code", title: L("Code"), section: labels,
                              content: look("npm install", font: "Menlo", size: 48, color: VideoRGBA(0.55, 0.95, 0.6), background: .init(color: VideoRGBA(0.08, 0.09, 0.1, 0.92), padding: 20, radius: 10)), // l10n-ignore: code
                              animation: moves(.fade, .fade), keywords: ["terminal", "developer"]),
            VideoTextTemplate(id: "label-quote", title: L("Quote"), section: labels,
                              content: look(L("“Simple is better”"), font: "Georgia", size: 70, italic: true, shadow: soft), animation: moves(.slideUp, .fade, length: 0.7), keywords: ["citation"]),
        ]
    }
}

/// A look for text (no words, no animation): applied to the selected text
/// clip, or a new one with “Your text”.
struct VideoTextStyle: Identifiable {
    var id: String
    var title: String
    var apply: (inout VideoTextContent) -> Void

    static var all: [VideoTextStyle] {
        let black = VideoRGBA(0, 0, 0), white = VideoRGBA(1, 1, 1)
        return [
            VideoTextStyle(id: "plain", title: L("Plain")) { c in c.color = white; c.stroke = nil; c.background = nil; c.shadow = nil },
            VideoTextStyle(id: "outline", title: L("Outline")) { c in c.color = white; c.stroke = .init(color: black, width: 6); c.background = nil },
            VideoTextStyle(id: "shadow", title: L("Shadow")) { c in c.color = white; c.stroke = nil; c.shadow = .init() },
            VideoTextStyle(id: "box-dark", title: L("Dark box")) { c in c.color = white; c.stroke = nil; c.background = .init() },
            VideoTextStyle(id: "box-light", title: L("Light box")) { c in c.color = black; c.stroke = nil; c.background = .init(color: VideoRGBA(1, 1, 1, 0.92)) },
            VideoTextStyle(id: "yellow", title: L("Yellow")) { c in c.color = VideoRGBA(1, 0.85, 0.1); c.stroke = .init(color: black, width: 6) },
            VideoTextStyle(id: "neon", title: L("Neon")) { c in
                c.color = VideoRGBA(0.6, 1, 0.95); c.stroke = nil; c.background = nil
                c.shadow = .init(color: VideoRGBA(0.1, 0.9, 1, 0.95), blur: 18, distance: 0)
            },
            VideoTextStyle(id: "pink", title: L("Pink pill")) { c in c.color = white; c.stroke = nil; c.background = .init(color: VideoRGBA(0.95, 0.3, 0.55, 1), padding: 18, radius: 40) },
            VideoTextStyle(id: "retro", title: L("Retro")) { c in
                c.color = VideoRGBA(1, 0.55, 0.2); c.stroke = .init(color: VideoRGBA(0.25, 0.1, 0.35), width: 5)
                c.shadow = .init(color: VideoRGBA(0.25, 0.1, 0.35, 1), blur: 0, distance: 8)
            },
            VideoTextStyle(id: "ghost", title: L("Ghost")) { c in c.color = VideoRGBA(1, 1, 1, 0.55); c.stroke = .init(color: white, width: 2); c.background = nil; c.shadow = nil },
        ]
    }
}

extension VideoEditorModel {
    /// A template from Library ▸ Text, as a new text clip (one ⌘Z step).
    @discardableResult
    func addTextTemplate(_ template: VideoTextTemplate, at time: Double?, place: LayerPlace = .automatic) -> UUID {
        var item = VideoLayerItem.text(template.content, at: time ?? clock.time, canvas: project.canvasSize())
        item.x = template.x
        item.y = template.y
        item.animation = template.animation
        let id = item.id
        mutate(label: "Add Text") { project in project.insertLayerItem(item, place: place) }
        selection = .layer(id)
        return id
    }

    /// A style from Library ▸ Text ▸ Styles: on the selected text clip, or
    /// a new one.
    func applyTextStyle(_ style: VideoTextStyle) {
        if let item = selectedLayerItem, var content = item.text {
            style.apply(&content)
            perform(.edit(.setText(content)))
            endGesture()
        } else {
            var content = VideoTextContent(string: L("Your text"))
            style.apply(&content)
            addTextClip(content)
        }
    }
}

/// Library ▸ Text.
struct VideoTextLibraryTab: View {
    @ObservedObject var model: VideoEditorModel

    private var tiles: [VideoLibraryTile] {
        VideoTextTemplate.all.map { VideoLibraryTile(payload: .init(kind: "text", id: $0.id), title: $0.title, keywords: $0.keywords, section: $0.section) }
    }

    var body: some View {
        VideoLibraryGrid(model: model, tiles: tiles, minimum: 96, tileHeight: 58) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.perform(.addTextClip)
                } label: {
                    Label(L("Add text"), systemImage: "character.textbox").frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("A text clip on a track of its own, at the playhead (⌥⇧T)"))
                Text(L("Styles"))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .textCase(.uppercase)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], spacing: 6) {
                    ForEach(VideoTextStyle.all) { style in
                        Button { model.applyTextStyle(style) } label: {
                            VideoTextLookPreview(content: Self.sample(style), animation: nil, hovering: false)
                                .frame(height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(L("\(style.title): on the selected text clip, or a new one"))
                        .accessibilityLabel(style.title)
                    }
                }
                Text(L("On the video (above the player's tools)"))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .textCase(.uppercase)
                HStack(spacing: 6) {
                    ForEach([(L("Arrow"), "arrow.up.right", VideoEditCommand.addArrow), (L("Highlight"), "rectangle.dashed", .addHighlight), (L("Blur"), "eye.slash", .addBlur)], id: \.0) { item in
                        Button { model.perform(item.2) } label: {
                            Label(item.0, systemImage: item.1).labelStyle(.iconOnly).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(VideoSecondaryButtonStyle())
                        .help(item.0)
                        .accessibilityLabel(item.0)
                    }
                    Button { model.addOverlay(.spotlight) } label: {
                        Label(L("Spotlight"), systemImage: "circle.dashed.inset.filled").labelStyle(.iconOnly).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .help(L("Spotlight"))
                    .accessibilityLabel(L("Spotlight"))
                    Button { model.perform(.addText) } label: {
                        Label(L("Text note"), systemImage: "textformat").labelStyle(.iconOnly).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .help(L("A text note pinned over the video (⌥T), as before"))
                    .accessibilityLabel(L("Text note"))
                }
            }
        } preview: { tile, hovering in
            if let template = VideoTextTemplate.all.first(where: { $0.id == tile.payload.id }) {
                VideoTextLookPreview(content: template.content, animation: template.animation, hovering: hovering)
            }
        }
    }

    private static func sample(_ style: VideoTextStyle) -> VideoTextContent {
        var content = VideoTextContent(string: "Aa") // l10n-ignore: a sample
        content.bold = true
        style.apply(&content)
        return content
    }
}

/// A text look on a dark checked well; hovering plays its animation.
struct VideoTextLookPreview: View {
    let content: VideoTextContent
    let animation: VideoItemAnimation?
    let hovering: Bool
    @State private var started = Date()

    var body: some View {
        GeometryReader { box in
            ZStack {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image = Self.image(content) {
                    let fit = min(box.size.width * 0.86 / max(image.size.width, 1), box.size.height * 0.72 / max(image.size.height, 1), 1)
                    TimelineView(.animation(paused: !hovering || animation == nil)) { timeline in
                        let c = change(at: timeline.date)
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: image.size.width * fit, height: image.size.height * fit)
                            .scaleEffect(c.scale)
                            .rotationEffect(.degrees(c.rotation))
                            .offset(x: c.dx * box.size.width, y: c.dy * box.size.height)
                            .opacity(c.opacity)
                            .blur(radius: c.blur / 1080 * box.size.height)
                    }
                }
            }
        }
        .onChange(of: hovering) { on in if on { started = Date() } }
    }

    /// Two seconds on loop: in, hold, out.
    private func change(at date: Date) -> VideoAnimationChange {
        guard hovering, let animation else { return VideoAnimationChange() }
        let local = date.timeIntervalSince(started).truncatingRemainder(dividingBy: 2.4)
        return animation.change(at: min(local, 2), length: 2)
    }

    private static let cache = NSCache<NSString, NSImage>()

    static func image(_ content: VideoTextContent) -> NSImage? {
        let key = (String(decoding: (try? VideoCacheKey.encoder.encode(content)) ?? Data(), as: UTF8.self)) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let cg = content.image(pixelHeight: 120) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        cache.setObject(image, forKey: key)
        return image
    }
}
