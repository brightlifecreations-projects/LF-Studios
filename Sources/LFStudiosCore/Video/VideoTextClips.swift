import AppKit
import CoreImage
import SwiftUI

// MARK: - Text on its own track (1.15.0)

/// A text clip's words and look. Sizes are points on a 1080-high video.
struct VideoTextContent: Codable, Equatable {
    var string: String
    var font: String = VideoTextFonts.defaultFamily
    var size = 72.0
    var bold = false
    var italic = false
    var underline = false
    var color = VideoRGBA(1, 1, 1)
    var stroke: Stroke?
    var background: Background?
    var shadow: Shadow?
    /// Extra space between letters and lines (points).
    var letterSpacing = 0.0
    var lineSpacing = 0.0
    var alignment: Alignment = .center

    struct Stroke: Codable, Equatable {
        var color = VideoRGBA(0, 0, 0)
        var width = 4.0
    }

    struct Background: Codable, Equatable {
        var color = VideoRGBA(0, 0, 0, 0.6)
        var padding = 18.0
        var radius = 12.0
    }

    struct Shadow: Codable, Equatable {
        var color = VideoRGBA(0, 0, 0, 0.7)
        var blur = 8.0
        var distance = 4.0
    }

    enum Alignment: String, Codable, CaseIterable, Identifiable {
        case left, center, right
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .left: return "text.alignleft"
            case .center: return "text.aligncenter"
            case .right: return "text.alignright"
            }
        }
        var nsAlignment: NSTextAlignment {
            switch self {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            }
        }
    }
}

/// Fonts that come with macOS (no others: a project never depends on fonts
/// someone happens to have installed). See LICENSES.md.
enum VideoTextFonts {
    static let defaultFamily = "Helvetica Neue"
    static let families = [
        "Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Optima", "Georgia", "Baskerville", "Didot",
        "American Typewriter", "Menlo", "Rockwell", "Impact", "Marker Felt", "Chalkboard SE", "Noteworthy", "Copperplate",
    ]

    static func font(_ family: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let chosen = families.contains(family) ? family : defaultFamily
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        let manager = NSFontManager.shared
        if let font = manager.font(withFamily: chosen, traits: traits, weight: bold ? 9 : 5, size: size) { return font }
        if let font = NSFont(name: chosen, size: size) { return font }
        return NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

extension VideoTextContent {
    func attributed(scale: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment.nsAlignment
        paragraph.lineSpacing = CGFloat(lineSpacing) * scale
        var attributes: [NSAttributedString.Key: Any] = [
            .font: VideoTextFonts.font(font, size: CGFloat(size) * scale, bold: bold, italic: italic),
            .foregroundColor: NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a),
            .paragraphStyle: paragraph,
            .kern: CGFloat(letterSpacing) * scale,
        ]
        if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let stroke {
            // Negative: fill and stroke (a percentage of the font size).
            attributes[.strokeWidth] = -CGFloat(stroke.width) / CGFloat(max(size, 1)) * 100
            attributes[.strokeColor] = NSColor(srgbRed: stroke.color.r, green: stroke.color.g, blue: stroke.color.b, alpha: stroke.color.a)
        }
        if let shadow {
            let s = NSShadow()
            s.shadowColor = NSColor(srgbRed: shadow.color.r, green: shadow.color.g, blue: shadow.color.b, alpha: shadow.color.a)
            s.shadowBlurRadius = CGFloat(shadow.blur) * scale
            s.shadowOffset = NSSize(width: 0, height: -CGFloat(shadow.distance) * scale)
            attributes[.shadow] = s
        }
        return NSAttributedString(string: string.isEmpty ? " " : string, attributes: attributes)
    }

    /// Its size on a 1080-high video (text, background and room for the
    /// stroke and shadow).
    func naturalSize(scale: CGFloat = 1) -> CGSize {
        let bounds = attributed(scale: scale).boundingRect(with: CGSize(width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let pad = margin * scale
        return CGSize(width: ceil(bounds.width) + pad * 2, height: ceil(bounds.height) + pad * 2)
    }

    /// Room around the words: the background's padding, the stroke, the shadow.
    var margin: CGFloat {
        CGFloat((background?.padding ?? 0) + (stroke?.width ?? 0) + (shadow.map { $0.blur + $0.distance } ?? 0) + 2)
    }

    /// The text drawn `pixelHeight` high (its own shape).
    func image(pixelHeight: CGFloat) -> CGImage? {
        let natural = naturalSize()
        guard natural.height > 0 else { return nil }
        let scale = max(pixelHeight / natural.height, 0.05)
        let size = CGSize(width: ceil(natural.width * scale), height: ceil(natural.height * scale))
        guard size.width >= 1, size.height >= 1, size.width < 16_384, size.height < 16_384,
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previous }
        if let background {
            let pad = CGFloat((stroke?.width ?? 0) + (shadow.map { $0.blur + $0.distance } ?? 0) + 2) * scale
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: pad, dy: pad)
            let path = NSBezierPath(roundedRect: rect, xRadius: CGFloat(background.radius) * scale, yRadius: CGFloat(background.radius) * scale)
            NSColor(srgbRed: background.color.r, green: background.color.g, blue: background.color.b, alpha: background.color.a).setFill()
            path.fill()
        }
        let text = attributed(scale: scale)
        let pad = margin * scale
        text.draw(with: CGRect(x: pad, y: pad, width: size.width - pad * 2, height: size.height - pad * 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return context.makeImage()
    }
}

enum VideoTextClipRenderer {
    private static let cache = NSCache<NSString, CIImage>()

    /// The text at about `pixelHeight` (cached by look and size).
    static func image(_ content: VideoTextContent, pixelHeight: CGFloat) -> CIImage? {
        let bucket = max((pixelHeight / 8).rounded(.up) * 8, 8)
        let data = (try? JSONEncoder().encode(content)) ?? Data()
        let key = "\(bucket)|\(data.hashValue)|\(data.count)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let cg = content.image(pixelHeight: bucket) else { return nil }
        let image = CIImage(cgImage: cg)
        cache.setObject(image, forKey: key)
        return image
    }
}

extension VideoLayerItem {
    /// Size and shape from the words (after an edit of them or their look),
    /// on a video `canvas` big. The middle stays where it is.
    mutating func fitText(canvas: CGSize) {
        guard let text else { return }
        let natural = text.naturalSize()
        aspect = Double(natural.width / max(natural.height, 1))
        let canvasWidthAt1080 = 1080 * canvas.width / max(canvas.height, 1)
        width = Double(natural.width / max(canvasWidthAt1080, 1))
    }

    var isText: Bool { text != nil }

    /// A new text clip at `time`, in the middle, 3 seconds long.
    static func text(_ content: VideoTextContent, at time: Double, canvas: CGSize) -> VideoLayerItem {
        var item = VideoLayerItem(kind: .image, path: "", name: content.string, at: max(time, 0), length: 3, aspect: 1)
        item.text = content
        item.fitText(canvas: canvas)
        return item
    }
}

// MARK: - Adding and editing

extension VideoEditorModel {
    /// Library ▸ Text ▸ Add text (or a template): on a track above the main
    /// track, at the playhead (or `time`).
    @discardableResult
    func addTextClip(_ content: VideoTextContent = VideoTextContent(string: L("Your text")), at time: Double? = nil, place: LayerPlace = .automatic) -> UUID {
        var item = VideoLayerItem.text(content, at: time ?? clock.time, canvas: project.canvasSize())
        item.name = content.string
        let id = item.id
        mutate(label: "Add Text") { project in
            project.insertLayerItem(item, place: place)
        }
        selection = .layer(id)
        return id
    }

    /// The selected text clip's words or look; its size follows.
    func setTextContent(_ id: UUID, _ content: VideoTextContent, coalesce: Bool = true) {
        let canvas = project.canvasSize()
        setLayerItem(id, coalesce: coalesce ? "text-\(id)" : nil, label: "Text Change") { item in
            guard item.text != nil else { return }
            // A bigger font or more words: bigger on the video, by as much
            // (a size set by hand stays in proportion; the place stays).
            let before = item.text?.naturalSize().width ?? 0
            let width = item.width
            item.text = content
            item.name = content.string
            item.fitText(canvas: canvas)
            if before > 0 {
                let factor = Double(content.naturalSize().width / before)
                item.width = width * factor
                if let keyed = item.keys?.tracks[VideoKeyProperty.width.rawValue] {
                    item.keys?.tracks[VideoKeyProperty.width.rawValue] = keyed.map { var key = $0; key.value *= factor; return key }
                }
            }
        }
    }
}

/// Properties ▸ Text: the words, font, size, style, colour, stroke,
/// background, shadow, spacing and alignment.
struct VideoTextClipSection: View {
    @ObservedObject var model: VideoEditorModel
    let item: VideoLayerItem
    let content: VideoTextContent

    var body: some View {
        VideoInspectorSection(L("Text")) {
            TextEditor(text: Binding(get: { content.string }, set: { value in apply { $0.string = value } }))
                .font(.system(size: 13))
                .frame(height: 64)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.well))
                .accessibilityLabel(L("Text"))
            HStack(spacing: 8) {
                Picker(L("Font"), selection: Binding(get: { content.font }, set: { value in apply { $0.font = value } })) {
                    ForEach(VideoTextFonts.families, id: \.self) { family in
                        Text(family).font(.custom(family, size: 12)).tag(family)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer(minLength: 0)
                toggle("bold", content.bold, help: L("Bold")) { $0.bold.toggle() }
                toggle("italic", content.italic, help: L("Italic")) { $0.italic.toggle() }
                toggle("underline", content.underline, help: L("Underline")) { $0.underline.toggle() }
            }
            VideoSliderRow(title: L("Size"), value: Binding(get: { content.size }, set: { value in apply { $0.size = value.rounded() } }),
                           range: 12...300, defaultValue: 72, format: { "\(Int($0))" }, onEditingEnded: { model.endGesture() }) // l10n-ignore: a number
            ColorPicker(L("Colour"), selection: colorBinding(content.color) { c, rgba in c.color = rgba }, supportsOpacity: true)
                .font(.system(size: 12, weight: .medium))
            HStack(spacing: 4) {
                ForEach(VideoTextContent.Alignment.allCases) { alignment in
                    Button {
                        apply { $0.alignment = alignment }
                        model.endGesture()
                    } label: {
                        Image(systemName: alignment.symbol).frame(maxWidth: .infinity).frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 6).fill(content.alignment == alignment ? VideoEditorTheme.layer.opacity(0.25) : VideoEditorTheme.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(alignment == .left ? L("Align left") : alignment == .center ? L("Centre") : L("Align right"))
                }
            }
            VideoSliderRow(title: L("Letter spacing"), value: Binding(get: { content.letterSpacing }, set: { value in apply { $0.letterSpacing = value.rounded() } }),
                           range: -10...60, defaultValue: 0, format: { "\(Int($0))" }, onEditingEnded: { model.endGesture() }) // l10n-ignore: a number
            VideoSliderRow(title: L("Line spacing"), value: Binding(get: { content.lineSpacing }, set: { value in apply { $0.lineSpacing = value.rounded() } }),
                           range: 0...80, defaultValue: 0, format: { "\(Int($0))" }, onEditingEnded: { model.endGesture() }) // l10n-ignore: a number
        }
        VideoInspectorSection(L("Stroke")) {
            VideoToggleRow(title: L("Stroke"), isOn: Binding(get: { content.stroke != nil }, set: { on in apply { $0.stroke = on ? .init() : nil }; model.endGesture() }))
            if let stroke = content.stroke {
                ColorPicker(L("Colour"), selection: colorBinding(stroke.color) { c, rgba in c.stroke?.color = rgba }, supportsOpacity: true).font(.system(size: 12, weight: .medium))
                VideoSliderRow(title: L("Width"), value: Binding(get: { stroke.width }, set: { value in apply { $0.stroke?.width = value } }),
                               range: 1...20, defaultValue: 4, format: { "\(Int($0))" }, onEditingEnded: { model.endGesture() }) // l10n-ignore: a number
            }
        }
        VideoInspectorSection(L("Background")) {
            VideoToggleRow(title: L("Background"), isOn: Binding(get: { content.background != nil }, set: { on in apply { $0.background = on ? .init() : nil }; model.endGesture() }))
            if let background = content.background {
                ColorPicker(L("Colour"), selection: colorBinding(background.color) { c, rgba in c.background?.color = rgba }, supportsOpacity: true).font(.system(size: 12, weight: .medium))
                VideoSliderRow(title: L("Roundness"), value: Binding(get: { background.radius }, set: { value in apply { $0.background?.radius = value } }),
                               range: 0...60, defaultValue: 12, format: { "\(Int($0))" }, onEditingEnded: { model.endGesture() }) // l10n-ignore: a number
            }
        }
        VideoInspectorSection(L("Shadow")) {
            VideoToggleRow(title: L("Shadow"), isOn: Binding(get: { content.shadow != nil }, set: { on in apply { $0.shadow = on ? .init() : nil }; model.endGesture() }))
            if let shadow = content.shadow {
                ColorPicker(L("Colour"), selection: colorBinding(shadow.color) { c, rgba in c.shadow?.color = rgba }, supportsOpacity: true).font(.system(size: 12, weight: .medium))
                VideoSliderRow(title: L("Blur"), value: Binding(get: { shadow.blur }, set: { value in apply { $0.shadow?.blur = value } }),
                               range: 0...40, defaultValue: 8, format: { "\(Int($0))" }, onEditingEnded: { model.endGesture() }) // l10n-ignore: a number
                VideoSliderRow(title: L("Distance"), value: Binding(get: { shadow.distance }, set: { value in apply { $0.shadow?.distance = value } }),
                               range: 0...40, defaultValue: 4, format: { "\(Int($0))" }, onEditingEnded: { model.endGesture() }) // l10n-ignore: a number
            }
        }
    }

    private func apply(_ change: (inout VideoTextContent) -> Void) {
        var next = content
        change(&next)
        model.selection = .layer(item.id)
        model.perform(.edit(.setText(next)))
    }

    private func toggle(_ symbol: String, _ on: Bool, help: String, _ change: @escaping (inout VideoTextContent) -> Void) -> some View {
        Button {
            apply(change)
            model.endGesture()
        } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? VideoEditorTheme.layer.opacity(0.3) : VideoEditorTheme.card))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func colorBinding(_ rgba: VideoRGBA, _ set: @escaping (inout VideoTextContent, VideoRGBA) -> Void) -> Binding<Color> {
        Binding(get: { Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a) }, set: { color in
            guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
            apply { set(&$0, VideoRGBA(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))) }
        })
    }
}
