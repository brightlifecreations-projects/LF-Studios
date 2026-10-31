import AppKit
import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library ▸ Stickers (1.15.0)

/// Our own stickers, drawn here in code (no symbols or outside art, so they
/// look the same in every export). See LICENSES.md.
enum VideoSticker: String, CaseIterable, Identifiable {
    case star, heart, sparkle, burst, speech, thought, arrow, curvedArrow, check, cross, warning, question, bolt, sun, cloud,
         smile, laugh, wow, musicNote, flame, like, follow, new, circleScribble, underline, confetti, hundred, pin

    var id: String { rawValue }
    var title: String {
        switch self {
        case .star: return L("Star")
        case .heart: return L("Heart")
        case .sparkle: return L("Sparkle")
        case .burst: return L("Burst")
        case .speech: return L("Speech bubble")
        case .thought: return L("Thought bubble")
        case .arrow: return L("Arrow")
        case .curvedArrow: return L("Curved arrow")
        case .check: return L("Tick")
        case .cross: return L("Cross")
        case .warning: return L("Warning")
        case .question: return L("Question")
        case .bolt: return L("Lightning")
        case .sun: return L("Sun")
        case .cloud: return L("Cloud")
        case .smile: return L("Smile")
        case .laugh: return L("Laugh")
        case .wow: return L("Surprised")
        case .musicNote: return L("Music note")
        case .flame: return L("Flame")
        case .like: return L("Like")
        case .follow: return L("Follow")
        case .new: return L("New badge")
        case .circleScribble: return L("Circle scribble")
        case .underline: return L("Underline")
        case .confetti: return L("Confetti")
        case .hundred: return L("100")
        case .pin: return L("Map pin")
        }
    }
    var section: String {
        switch self {
        case .smile, .laugh, .wow, .heart, .star, .sparkle, .flame, .musicNote, .confetti, .sun, .cloud, .bolt: return L("Fun")
        case .speech, .thought, .like, .follow, .new, .hundred, .burst: return L("Callouts")
        case .arrow, .curvedArrow, .check, .cross, .warning, .question, .circleScribble, .underline, .pin: return L("Point things out")
        }
    }
    /// Width / height.
    var aspect: Double {
        switch self {
        case .like, .follow: return 2.6
        case .underline: return 4
        case .arrow: return 1.8
        case .speech, .thought: return 1.3
        case .circleScribble: return 1.5
        default: return 1
        }
    }

    // MARK: Drawing

    /// Drawn into `rect` (bottom-left origin) of the current context.
    func draw(in rect: CGRect, _ cg: CGContext) {
        let w = rect.width, h = rect.height, x0 = rect.minX, y0 = rect.minY
        let outline = max(min(w, h) * 0.045, 1)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x0 + x * w, y: y0 + y * h) }
        func fillStroke(_ path: CGPath, _ fill: NSColor, stroke: NSColor? = NSColor(white: 0.1, alpha: 1), width: CGFloat? = nil) {
            cg.addPath(path); cg.setFillColor(fill.cgColor); cg.fillPath()
            if let stroke {
                cg.addPath(path); cg.setStrokeColor(stroke.cgColor); cg.setLineWidth(width ?? outline); cg.setLineJoin(.round); cg.setLineCap(.round); cg.strokePath()
            }
        }
        func line(_ path: CGPath, _ color: NSColor, _ width: CGFloat) {
            cg.addPath(path); cg.setStrokeColor(color.cgColor); cg.setLineWidth(width); cg.setLineCap(.round); cg.setLineJoin(.round); cg.strokePath()
        }
        func star(points: Int, inner: CGFloat, center: CGPoint, radius: CGFloat, turn: CGFloat = 0) -> CGPath {
            let path = CGMutablePath()
            for i in 0..<(points * 2) {
                let r = i % 2 == 0 ? radius : radius * inner
                let a = turn + .pi / 2 + CGFloat(i) * .pi / CGFloat(points)
                let pt = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
            return path
        }
        func words(_ text: String, size: CGFloat, color: NSColor, in box: CGRect, font: String = "Avenir Next") {
            let attributes: [NSAttributedString.Key: Any] = [.font: VideoTextFonts.font(font, size: size, bold: true, italic: false), .foregroundColor: color]
            let string = NSAttributedString(string: text, attributes: attributes)
            let bounds = string.size()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
            string.draw(at: CGPoint(x: box.midX - bounds.width / 2, y: box.midY - bounds.height / 2))
            NSGraphicsContext.restoreGraphicsState()
        }
        func face(_ fill: NSColor) {
            fillStroke(CGPath(ellipseIn: rect.insetBy(dx: w * 0.06, dy: h * 0.06), transform: nil), fill)
        }
        let yellow = NSColor(srgbRed: 1, green: 0.82, blue: 0.2, alpha: 1)
        let red = NSColor(srgbRed: 0.93, green: 0.22, blue: 0.27, alpha: 1)
        let ink = NSColor(white: 0.1, alpha: 1)
        let white = NSColor.white
        let blue = NSColor(srgbRed: 0.2, green: 0.55, blue: 0.95, alpha: 1)
        let green = NSColor(srgbRed: 0.2, green: 0.75, blue: 0.4, alpha: 1)
        let center = p(0.5, 0.5)
        switch self {
        case .star:
            fillStroke(star(points: 5, inner: 0.45, center: p(0.5, 0.47), radius: min(w, h) * 0.46), yellow)
        case .heart:
            let path = CGMutablePath()
            path.move(to: p(0.5, 0.12))
            path.addCurve(to: p(0.06, 0.62), control1: p(0.3, 0.3), control2: p(0.04, 0.42))
            path.addCurve(to: p(0.5, 0.74), control1: p(0.08, 0.92), control2: p(0.42, 0.95))
            path.addCurve(to: p(0.94, 0.62), control1: p(0.58, 0.95), control2: p(0.92, 0.92))
            path.addCurve(to: p(0.5, 0.12), control1: p(0.96, 0.42), control2: p(0.7, 0.3))
            fillStroke(path, red)
        case .sparkle:
            fillStroke(star(points: 4, inner: 0.22, center: center, radius: min(w, h) * 0.46), white, stroke: NSColor(srgbRed: 0.95, green: 0.7, blue: 0.1, alpha: 1))
            fillStroke(star(points: 4, inner: 0.25, center: p(0.82, 0.8), radius: min(w, h) * 0.12), white, stroke: NSColor(srgbRed: 0.95, green: 0.7, blue: 0.1, alpha: 1))
        case .burst:
            fillStroke(star(points: 12, inner: 0.72, center: center, radius: min(w, h) * 0.48, turn: 0.1), NSColor(srgbRed: 1, green: 0.45, blue: 0.15, alpha: 1))
            fillStroke(star(points: 12, inner: 0.75, center: center, radius: min(w, h) * 0.36, turn: 0.35), yellow, stroke: nil)
            words(L("WOW!"), size: h * 0.2, color: ink, in: rect)
        case .speech, .thought:
            let bubble = CGRect(x: x0 + w * 0.05, y: y0 + h * 0.25, width: w * 0.9, height: h * 0.7)
            let path = CGMutablePath()
            path.addRoundedRect(in: bubble, cornerWidth: bubble.height * 0.35, cornerHeight: bubble.height * 0.35)
            if self == .speech {
                path.move(to: p(0.25, 0.27)); path.addLine(to: p(0.14, 0.04)); path.addLine(to: p(0.42, 0.27))
                fillStroke(path, white)
                // A seam under the tail.
                cg.setFillColor(white.cgColor); cg.fill(CGRect(x: x0 + w * 0.255, y: y0 + h * 0.24, width: w * 0.155, height: outline * 1.6))
            } else {
                fillStroke(path, white)
                fillStroke(CGPath(ellipseIn: CGRect(x: x0 + w * 0.17, y: y0 + h * 0.1, width: w * 0.12, height: h * 0.11), transform: nil), white)
                fillStroke(CGPath(ellipseIn: CGRect(x: x0 + w * 0.08, y: y0 + h * 0.01, width: w * 0.07, height: h * 0.07), transform: nil), white)
            }
        case .arrow:
            let path = CGMutablePath()
            path.move(to: p(0.04, 0.38)); path.addLine(to: p(0.6, 0.38)); path.addLine(to: p(0.6, 0.12)); path.addLine(to: p(0.96, 0.5))
            path.addLine(to: p(0.6, 0.88)); path.addLine(to: p(0.6, 0.62)); path.addLine(to: p(0.04, 0.62)); path.closeSubpath()
            fillStroke(path, red)
        case .curvedArrow:
            let path = CGMutablePath()
            path.move(to: p(0.12, 0.2)); path.addQuadCurve(to: p(0.72, 0.78), control: p(0.15, 0.85))
            line(path, ink, min(w, h) * 0.13)
            line(path, red, min(w, h) * 0.08)
            let head = CGMutablePath()
            head.move(to: p(0.6, 0.92)); head.addLine(to: p(0.94, 0.76)); head.addLine(to: p(0.62, 0.58)); head.closeSubpath()
            fillStroke(head, red)
        case .check, .cross, .question:
            let fill = self == .check ? green : self == .cross ? red : blue
            fillStroke(CGPath(ellipseIn: rect.insetBy(dx: w * 0.05, dy: h * 0.05), transform: nil), fill)
            let mark = CGMutablePath()
            if self == .check {
                mark.move(to: p(0.27, 0.5)); mark.addLine(to: p(0.43, 0.33)); mark.addLine(to: p(0.74, 0.67))
                line(mark, white, min(w, h) * 0.11)
            } else if self == .cross {
                mark.move(to: p(0.32, 0.32)); mark.addLine(to: p(0.68, 0.68)); mark.move(to: p(0.68, 0.32)); mark.addLine(to: p(0.32, 0.68))
                line(mark, white, min(w, h) * 0.11)
            } else {
                words("?", size: h * 0.62, color: white, in: rect.offsetBy(dx: 0, dy: -h * 0.02))
            }
        case .warning:
            let path = CGMutablePath()
            path.move(to: p(0.5, 0.94)); path.addLine(to: p(0.96, 0.1)); path.addLine(to: p(0.04, 0.1)); path.closeSubpath()
            fillStroke(path, yellow)
            words("!", size: h * 0.55, color: ink, in: CGRect(x: x0, y: y0 + h * 0.08, width: w, height: h * 0.62))
        case .bolt:
            let path = CGMutablePath()
            path.move(to: p(0.6, 0.97)); path.addLine(to: p(0.18, 0.44)); path.addLine(to: p(0.46, 0.44)); path.addLine(to: p(0.36, 0.03))
            path.addLine(to: p(0.84, 0.58)); path.addLine(to: p(0.54, 0.58)); path.closeSubpath()
            fillStroke(path, yellow)
        case .sun:
            fillStroke(star(points: 10, inner: 0.7, center: center, radius: min(w, h) * 0.48), NSColor(srgbRed: 1, green: 0.6, blue: 0.1, alpha: 1))
            fillStroke(CGPath(ellipseIn: rect.insetBy(dx: w * 0.24, dy: h * 0.24), transform: nil), yellow)
        case .cloud:
            let path = CGMutablePath()
            for (cx, cy, r) in [(0.3, 0.42, 0.2), (0.5, 0.56, 0.26), (0.72, 0.44, 0.2), (0.5, 0.36, 0.2)] as [(CGFloat, CGFloat, CGFloat)] {
                path.addEllipse(in: CGRect(x: x0 + (cx - r) * w, y: y0 + (cy - r) * h, width: r * 2 * w, height: r * 2 * h))
            }
            cg.addPath(path); cg.setStrokeColor(ink.cgColor); cg.setLineWidth(outline * 2); cg.strokePath()
            cg.addPath(path); cg.setFillColor(white.cgColor); cg.fillPath()
        case .smile, .laugh, .wow:
            face(yellow)
            let eyes = CGMutablePath()
            if self == .laugh {
                eyes.move(to: p(0.28, 0.6)); eyes.addQuadCurve(to: p(0.42, 0.6), control: p(0.35, 0.7))
                eyes.move(to: p(0.58, 0.6)); eyes.addQuadCurve(to: p(0.72, 0.6), control: p(0.65, 0.7))
                line(eyes, ink, outline * 1.4)
            } else {
                for ex in [0.36, 0.64] as [CGFloat] {
                    cg.setFillColor(ink.cgColor)
                    cg.fillEllipse(in: CGRect(x: x0 + (ex - 0.05) * w, y: y0 + 0.56 * h, width: 0.1 * w, height: (self == .wow ? 0.14 : 0.12) * h))
                }
            }
            let mouth = CGMutablePath()
            switch self {
            case .wow:
                cg.setFillColor(ink.cgColor); cg.fillEllipse(in: CGRect(x: x0 + 0.42 * w, y: y0 + 0.2 * h, width: 0.16 * w, height: 0.2 * h))
            case .laugh:
                mouth.move(to: p(0.27, 0.42)); mouth.addQuadCurve(to: p(0.73, 0.42), control: p(0.5, 0.08)); mouth.closeSubpath()
                fillStroke(mouth, ink, stroke: ink)
            default:
                mouth.move(to: p(0.3, 0.38)); mouth.addQuadCurve(to: p(0.7, 0.38), control: p(0.5, 0.18))
                line(mouth, ink, outline * 1.4)
            }
        case .musicNote:
            let stem = CGMutablePath()
            stem.move(to: p(0.42, 0.25)); stem.addLine(to: p(0.42, 0.88)); stem.addLine(to: p(0.8, 0.95)); stem.addLine(to: p(0.8, 0.35))
            line(stem, ink, min(w, h) * 0.07)
            cg.setFillColor(ink.cgColor)
            cg.fillEllipse(in: CGRect(x: x0 + 0.16 * w, y: y0 + 0.1 * h, width: 0.28 * w, height: 0.22 * h))
            cg.fillEllipse(in: CGRect(x: x0 + 0.54 * w, y: y0 + 0.2 * h, width: 0.28 * w, height: 0.22 * h))
        case .flame:
            let outer = CGMutablePath()
            outer.move(to: p(0.5, 0.04))
            outer.addCurve(to: p(0.5, 0.97), control1: p(0.05, 0.1), control2: p(0.2, 0.7))
            outer.addCurve(to: p(0.5, 0.04), control1: p(0.95, 0.62), control2: p(0.95, 0.1))
            fillStroke(outer, NSColor(srgbRed: 1, green: 0.4, blue: 0.1, alpha: 1))
            let inner = CGMutablePath()
            inner.move(to: p(0.5, 0.1))
            inner.addCurve(to: p(0.48, 0.6), control1: p(0.25, 0.14), control2: p(0.3, 0.45))
            inner.addCurve(to: p(0.5, 0.1), control1: p(0.75, 0.42), control2: p(0.75, 0.14))
            fillStroke(inner, yellow, stroke: nil)
        case .like, .follow:
            let pill = CGPath(roundedRect: rect.insetBy(dx: w * 0.03, dy: h * 0.1), cornerWidth: h * 0.4, cornerHeight: h * 0.4, transform: nil)
            fillStroke(pill, self == .like ? red : blue, stroke: white, width: outline * 0.8)
            words(self == .like ? L("LIKE") : L("FOLLOW"), size: h * 0.42, color: white, in: rect)
        case .new:
            fillStroke(star(points: 14, inner: 0.82, center: center, radius: min(w, h) * 0.48), red, stroke: white)
            words(L("NEW"), size: h * 0.26, color: white, in: rect)
        case .circleScribble:
            let path = CGMutablePath()
            path.move(to: p(0.62, 0.9))
            path.addCurve(to: p(0.08, 0.5), control1: p(0.3, 0.97), control2: p(0.06, 0.8))
            path.addCurve(to: p(0.55, 0.08), control1: p(0.1, 0.18), control2: p(0.32, 0.06))
            path.addCurve(to: p(0.94, 0.52), control1: p(0.8, 0.1), control2: p(0.96, 0.3))
            path.addCurve(to: p(0.42, 0.93), control1: p(0.92, 0.82), control2: p(0.65, 0.95))
            line(path, red, min(w, h) * 0.06)
        case .underline:
            let path = CGMutablePath()
            path.move(to: p(0.03, 0.6))
            path.addCurve(to: p(0.97, 0.55), control1: p(0.3, 0.35), control2: p(0.65, 0.8))
            path.move(to: p(0.1, 0.35)); path.addCurve(to: p(0.9, 0.3), control1: p(0.35, 0.2), control2: p(0.6, 0.45))
            line(path, yellow, h * 0.18)
        case .confetti:
            let colours = [red, yellow, blue, green, NSColor(srgbRed: 0.8, green: 0.35, blue: 0.95, alpha: 1)]
            for i in 0..<26 {
                let a = VideoEffectRenderer.random(i, 1), b = VideoEffectRenderer.random(i, 2), c = VideoEffectRenderer.random(i, 3)
                cg.saveGState()
                cg.translateBy(x: x0 + (0.08 + a * 0.84) * w, y: y0 + (0.08 + b * 0.84) * h)
                cg.rotate(by: CGFloat(c) * .pi)
                cg.setFillColor(colours[i % colours.count].cgColor)
                cg.fill(CGRect(x: -w * 0.035, y: -h * 0.015, width: w * 0.07, height: h * 0.03))
                cg.restoreGState()
            }
        case .hundred:
            words("100", size: h * 0.5, color: red, in: CGRect(x: x0, y: y0 + h * 0.2, width: w, height: h * 0.7), font: "Futura")
            let lines = CGMutablePath()
            lines.move(to: p(0.12, 0.24)); lines.addLine(to: p(0.88, 0.24)); lines.move(to: p(0.16, 0.12)); lines.addLine(to: p(0.84, 0.12))
            line(lines, red, h * 0.06)
        case .pin:
            let path = CGMutablePath()
            path.move(to: p(0.5, 0.04))
            path.addCurve(to: p(0.5, 0.96), control1: p(0.1, 0.45), control2: p(0.1, 0.96))
            path.addCurve(to: p(0.5, 0.04), control1: p(0.9, 0.96), control2: p(0.9, 0.45))
            fillStroke(path, red)
            cg.setFillColor(white.cgColor); cg.fillEllipse(in: CGRect(x: x0 + 0.36 * w, y: y0 + 0.56 * h, width: 0.28 * w, height: 0.28 * h))
        }
    }

    /// The sticker `pixelHeight` high.
    func image(pixelHeight: CGFloat) -> CGImage? {
        let height = max(min(pixelHeight, 4096), 8)
        let width = height * CGFloat(aspect)
        guard let cg = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.setShouldAntialias(true)
        draw(in: CGRect(x: 0, y: 0, width: width, height: height).insetBy(dx: height * 0.02, dy: height * 0.02), cg)
        return cg.makeImage()
    }
}

enum VideoStickerRenderer {
    private static let cache = NSCache<NSString, CIImage>()

    static func image(_ id: String, pixelHeight: CGFloat) -> CIImage? {
        guard let sticker = VideoSticker(rawValue: id) else { return nil }
        let bucket = max((pixelHeight / 16).rounded(.up) * 16, 16)
        let key = "\(id)@\(bucket)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let cg = sticker.image(pixelHeight: bucket) else { return nil }
        let image = CIImage(cgImage: cg)
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - Animated GIFs

/// An animated GIF's frames and timing, decoded once (at most 1024 px,
/// 400 frames).
final class VideoGIF {
    let frames: [CIImage]
    let delays: [Double]
    let length: Double

    private init(frames: [CIImage], delays: [Double]) {
        self.frames = frames
        self.delays = delays
        length = max(delays.reduce(0, +), 0.01)
    }

    private static let lock = NSLock()
    private static var loaded: [String: VideoGIF?] = [:]

    static func load(_ path: String) -> VideoGIF? {
        lock.lock()
        if let cached = loaded[path] { lock.unlock(); return cached }
        lock.unlock()
        var gif: VideoGIF?
        if let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), CGImageSourceGetCount(source) > 1 {
            var frames: [CIImage] = [], delays: [Double] = []
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true]
            for i in 0..<min(CGImageSourceGetCount(source), 400) {
                guard let cg = CGImageSourceCreateThumbnailAtIndex(source, i, options as CFDictionary) else { continue }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
                let info = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                let delay = (info?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (info?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
                frames.append(CIImage(cgImage: cg))
                // Browsers treat very short delays as 0.1 s; so do we.
                delays.append(delay < 0.02 ? 0.1 : delay)
            }
            if frames.count > 1 { gif = VideoGIF(frames: frames, delays: delays) }
        }
        lock.lock()
        loaded[path] = gif
        lock.unlock()
        return gif
    }

    /// The frame `seconds` in (it loops).
    func frame(at seconds: Double) -> CIImage {
        var t = seconds.truncatingRemainder(dividingBy: length)
        if t < 0 { t += length }
        for (i, delay) in delays.enumerated() {
            if t < delay { return frames[i] }
            t -= delay
        }
        return frames[frames.count - 1]
    }
}

// MARK: - Placing

extension VideoLayerItem {
    /// A sticker clip in the middle, 4 seconds long, a quarter of the frame high.
    static func sticker(_ sticker: VideoSticker, at time: Double, canvas: CGSize) -> VideoLayerItem {
        var item = VideoLayerItem(kind: .image, path: "", name: sticker.title, at: max(time, 0), length: 4, aspect: sticker.aspect)
        item.sticker = sticker.rawValue
        let canvasAspect = Double(canvas.width / max(canvas.height, 1))
        item.width = 0.25 * sticker.aspect / canvasAspect
        return item
    }
}

extension VideoEditorModel {
    /// A sticker at `time` (nil: the playhead) on a track. One ⌘Z step.
    @discardableResult
    func addSticker(_ sticker: VideoSticker, at time: Double?, place: LayerPlace = .automatic) -> UUID {
        let item = VideoLayerItem.sticker(sticker, at: time ?? clock.time, canvas: project.canvasSize())
        mutate(label: "Add Sticker") { project in project.insertLayerItem(item, place: place) }
        selection = .layer(item.id)
        return item.id
    }

    /// Import sticker: your own PNG or GIF (animated GIFs play), on a track
    /// at the playhead.
    func importSticker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .gif]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await placeMedia(urls, at: nil, target: .layer(.automatic)) }
    }
}

// MARK: - Library ▸ Stickers

struct VideoStickersLibraryTab: View {
    @ObservedObject var model: VideoEditorModel

    private var tiles: [VideoLibraryTile] {
        VideoSticker.allCases.map { VideoLibraryTile(payload: .init(kind: "sticker", id: $0.rawValue), title: $0.title, section: $0.section) }
    }

    var body: some View {
        VideoLibraryGrid(model: model, tiles: tiles, minimum: 64, tileHeight: 56) {
            Button {
                model.importSticker()
            } label: {
                Label(L("Import sticker…"), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoSecondaryButtonStyle())
            .help(L("Your own PNG or GIF (GIFs play)"))
        } preview: { tile, hovering in
            if let sticker = VideoSticker(rawValue: tile.payload.id) {
                VideoStickerPreview(sticker: sticker, hovering: hovering)
            }
        }
    }
}

struct VideoStickerPreview: View {
    let sticker: VideoSticker
    let hovering: Bool

    var body: some View {
        ZStack {
            VideoEditorTheme.well
            if let image = Self.image(sticker) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(6)
                    .scaleEffect(hovering ? 1.12 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
            }
        }
    }

    private static let cache = NSCache<NSString, NSImage>()

    static func image(_ sticker: VideoSticker) -> NSImage? {
        if let cached = cache.object(forKey: sticker.rawValue as NSString) { return cached }
        guard let cg = sticker.image(pixelHeight: 112) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        cache.setObject(image, forKey: sticker.rawValue as NSString)
        return image
    }
}
