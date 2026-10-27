import AppKit
import CoreImage
import Foundation

// MARK: - Settings

/// The pointer's look in the video. Classic draws the recording's own
/// pointer; the others are drawn here, each with an arrow, a text (I-beam)
/// and a hand version.
enum VideoCursorStyle: String, Codable, CaseIterable, Identifiable {
    case classic
    case white
    case outlined
    case touch
    case ring
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return L("macOS classic")
        case .white: return L("White")
        case .outlined: return L("Outlined")
        case .touch: return L("Touch dot")
        case .ring: return L("Ring")
        case .custom: return L("Custom image…")
        }
    }
}

/// A picture used as the pointer, for every pointer shape.
struct VideoCursorImage: Codable, Equatable {
    /// LF Studios' own copy (Application Support), like picture overlays.
    var path: String
    /// The file name it was chosen from.
    var name: String
    /// Where it points: 0…1 across the picture, from its top left.
    var hotSpotX: Double
    var hotSpotY: Double
    /// Width / height.
    var aspect: Double
}

/// What a pointer shape is for.
enum VideoCursorKind: String, Codable {
    case arrow
    case text
    case hand

    /// Recognized by its size and hot spot: an I-beam is narrow and points
    /// from its middle; the pointing hand is about square and points from
    /// its fingertip, near the top; arrows point from the top left.
    static func guess(size: CGSize, hotSpot: CGPoint) -> VideoCursorKind {
        let width = max(size.width, 1), height = max(size.height, 1)
        let hx = hotSpot.x / width, hy = hotSpot.y / height
        let aspect = width / height
        if aspect < 0.65, (0.25...0.75).contains(hx), (0.25...0.75).contains(hy) { return .text }
        if (0.3...0.65).contains(hx), hy < 0.35, (0.7...1.4).contains(aspect) { return .hand }
        return .arrow
    }

    /// The system's own pointer this one is, when it is one of them.
    @MainActor
    static func match(_ cursor: NSCursor) -> VideoCursorKind? {
        func same(_ other: NSCursor) -> Bool {
            abs(cursor.image.size.width - other.image.size.width) < 0.5
                && abs(cursor.image.size.height - other.image.size.height) < 0.5
                && abs(cursor.hotSpot.x - other.hotSpot.x) < 0.5
                && abs(cursor.hotSpot.y - other.hotSpot.y) < 0.5
        }
        if same(.iBeam) || same(.iBeamCursorForVerticalLayout) { return .text }
        if same(.pointingHand) { return .hand }
        if same(.arrow) { return .arrow }
        return nil
    }
}

extension VideoCursorArtwork {
    /// Which kind a shape of this recording is (an arrow when unsure).
    func kind(of shape: Shape) -> VideoCursorKind {
        if shape.id == arrow.id { return .arrow }
        return kinds[shape.id] ?? VideoCursorKind.guess(size: shape.size, hotSpot: shape.hotSpot)
    }
}

// MARK: - Artwork

/// The pointers of one style, drawn once.
final class VideoCursorStyleArtwork: @unchecked Sendable {
    let style: VideoCursorStyle
    private let shapes: [VideoCursorKind: VideoCursorArtwork.Shape]

    private init(style: VideoCursorStyle, shapes: [VideoCursorKind: VideoCursorArtwork.Shape]) {
        self.style = style
        self.shapes = shapes
    }

    func shape(for kind: VideoCursorKind) -> VideoCursorArtwork.Shape {
        shapes[kind] ?? shapes[.arrow]!
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var drawn: [String: VideoCursorStyleArtwork] = [:]

    /// The artwork for these settings; nil for the recording's own pointer
    /// (or a custom picture that can't be read).
    static func make(settings: VideoCursorSettings) -> VideoCursorStyleArtwork? {
        let style = settings.style
        guard style != .classic else { return nil }
        let key: String
        if style == .custom {
            guard let image = settings.customImage else { return nil }
            key = "custom|\(image.path)|\(image.hotSpotX)|\(image.hotSpotY)"
        } else {
            key = style.rawValue
        }
        lock.lock()
        defer { lock.unlock() }
        if let cached = drawn[key] { return cached }
        let artwork: VideoCursorStyleArtwork?
        if style == .custom {
            artwork = settings.customImage.flatMap(customArtwork)
        } else {
            artwork = VideoCursorStyleArtwork(style: style, shapes: [
                .arrow: draw(style, .arrow),
                .text: draw(style, .text),
                .hand: draw(style, .hand),
            ])
        }
        if let artwork { drawn[key] = artwork }
        return artwork
    }

    private static func customArtwork(_ image: VideoCursorImage) -> VideoCursorStyleArtwork? {
        guard let picture = NSImage(contentsOfFile: image.path),
              let cg = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let height: CGFloat = 32
        let width = height * CGFloat(cg.width) / CGFloat(max(cg.height, 1))
        let shape = VideoCursorArtwork.Shape(
            id: "custom",
            hotSpot: CGPoint(x: CGFloat(image.hotSpotX) * width, y: CGFloat(image.hotSpotY) * height),
            size: CGSize(width: width, height: height),
            mips: VideoCursorArtwork.mipChain(CIImage(cgImage: cg))
        )
        return VideoCursorStyleArtwork(style: .custom, shapes: [.arrow: shape])
    }

    // MARK: Drawing

    /// Draws at 12× the point size so every zoom stays sharp.
    private static let scale: CGFloat = 12

    private struct Canvas {
        let context: CGContext
        let height: CGFloat
        /// Points (top-left origin) → context (bottom-left).
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * VideoCursorStyleArtwork.scale, y: (height - y) * VideoCursorStyleArtwork.scale) }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * VideoCursorStyleArtwork.scale, y: (height - y - h) * VideoCursorStyleArtwork.scale, width: w * VideoCursorStyleArtwork.scale, height: h * VideoCursorStyleArtwork.scale)
        }
        func points(_ value: CGFloat) -> CGFloat { value * VideoCursorStyleArtwork.scale }
    }

    private static func render(_ id: String, size: CGSize, hotSpot: CGPoint, _ body: (Canvas) -> Void) -> VideoCursorArtwork.Shape {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return VideoCursorArtwork.Shape(id: id, hotSpot: hotSpot, size: size, mips: [CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))])
        }
        context.setLineJoin(.round)
        context.setLineCap(.round)
        body(Canvas(context: context, height: size.height))
        let image = context.makeImage().map { CIImage(cgImage: $0) } ?? CIImage(color: .black)
        return VideoCursorArtwork.Shape(id: id, hotSpot: hotSpot, size: size, mips: VideoCursorArtwork.mipChain(image))
    }

    private static func arrowPath(_ c: Canvas) -> CGPath {
        let path = CGMutablePath()
        path.move(to: c.p(3, 3))
        path.addLine(to: c.p(3, 21.6))
        path.addLine(to: c.p(7.4, 17.4))
        path.addLine(to: c.p(10.5, 24.4))
        path.addLine(to: c.p(13.6, 23))
        path.addLine(to: c.p(10.6, 16.3))
        path.addLine(to: c.p(16.6, 16.3))
        path.closeSubpath()
        return path
    }

    private static func handPath(_ c: Canvas) -> CGPath {
        let path = CGMutablePath()
        // Index finger, three folded fingers, palm, thumb.
        path.addRoundedRect(in: c.r(8, 2, 4.6, 15), cornerWidth: c.points(2.3), cornerHeight: c.points(2.3))
        path.addRoundedRect(in: c.r(12.2, 9.5, 3.6, 8), cornerWidth: c.points(1.8), cornerHeight: c.points(1.8))
        path.addRoundedRect(in: c.r(15.4, 10.5, 3.6, 8), cornerWidth: c.points(1.8), cornerHeight: c.points(1.8))
        path.addRoundedRect(in: c.r(18.4, 12, 3.2, 7), cornerWidth: c.points(1.6), cornerHeight: c.points(1.6))
        path.addRoundedRect(in: c.r(6.5, 14, 15, 13), cornerWidth: c.points(4.5), cornerHeight: c.points(4.5))
        path.addRoundedRect(in: c.r(3.2, 15.5, 6.5, 4), cornerWidth: c.points(2), cornerHeight: c.points(2))
        return path
    }

    private static func beamPath(_ c: Canvas, x: CGFloat, top: CGFloat, bottom: CGFloat, serif: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: c.p(x - serif, top))
        path.addQuadCurve(to: c.p(x, top + 1.6), control: c.p(x - 0.4, top))
        path.addQuadCurve(to: c.p(x + serif, top), control: c.p(x + 0.4, top))
        path.move(to: c.p(x, top + 1.6))
        path.addLine(to: c.p(x, bottom - 1.6))
        path.move(to: c.p(x - serif, bottom))
        path.addQuadCurve(to: c.p(x, bottom - 1.6), control: c.p(x - 0.4, bottom))
        path.addQuadCurve(to: c.p(x + serif, bottom), control: c.p(x + 0.4, bottom))
        return path
    }

    private static let ink = CGColor(gray: 0.08, alpha: 1)
    private static let paper = CGColor(gray: 1, alpha: 1)
    private static let shade = CGColor(gray: 0, alpha: 0.35)

    /// A filled shape: an outline stroke underneath, the fill on top (so
    /// overlapping parts read as one piece).
    private static func solid(_ c: Canvas, _ path: CGPath, fill: CGColor, edge: CGColor, edgeWidth: CGFloat) {
        let ctx = c.context
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -c.points(1)), blur: c.points(2.4), color: shade)
        ctx.addPath(path)
        ctx.setStrokeColor(edge)
        ctx.setLineWidth(c.points(edgeWidth * 2))
        ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setFillColor(fill)
        ctx.fillPath()
    }

    /// A hollow shape: a dark line with a light halo, clear inside.
    private static func hollow(_ c: Canvas, _ path: CGPath) {
        let ctx = c.context
        ctx.addPath(path)
        ctx.setStrokeColor(paper)
        ctx.setLineWidth(c.points(5))
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(c.points(3))
        ctx.strokePath()
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// A bar the I-beam's way: a light line on a dark one, or the reverse.
    private static func beam(_ c: Canvas, _ path: CGPath, line: CGColor, edge: CGColor) {
        let ctx = c.context
        ctx.addPath(path)
        ctx.setStrokeColor(edge)
        ctx.setLineWidth(c.points(3.4))
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(line)
        ctx.setLineWidth(c.points(1.6))
        ctx.strokePath()
    }

    private static func draw(_ style: VideoCursorStyle, _ kind: VideoCursorKind) -> VideoCursorArtwork.Shape {
        let id = "\(style.rawValue)-\(kind.rawValue)"
        switch (style, kind) {
        case (.white, .arrow), (.outlined, .arrow):
            return render(id, size: CGSize(width: 20, height: 28), hotSpot: CGPoint(x: 3, y: 3)) { c in
                if style == .white { solid(c, arrowPath(c), fill: paper, edge: ink, edgeWidth: 1.2) } else { hollow(c, arrowPath(c)) }
            }
        case (.white, .hand), (.outlined, .hand):
            return render(id, size: CGSize(width: 25, height: 30), hotSpot: CGPoint(x: 10.3, y: 2.5)) { c in
                if style == .white { solid(c, handPath(c), fill: paper, edge: ink, edgeWidth: 1.1) } else { hollow(c, handPath(c)) }
            }
        case (.white, .text), (.outlined, .text):
            return render(id, size: CGSize(width: 12, height: 24), hotSpot: CGPoint(x: 6, y: 12)) { c in
                let path = beamPath(c, x: 6, top: 3, bottom: 21, serif: 3)
                if style == .white { beam(c, path, line: paper, edge: ink) } else { beam(c, path, line: ink, edge: paper) }
            }
        case (.touch, _):
            // A fingertip-sized dot; over text it carries a thin bar, over
            // links it's a little bigger and stronger.
            let diameter: CGFloat = kind == .hand ? 26 : 22
            let box = diameter + 6
            return render(id, size: CGSize(width: box, height: box), hotSpot: CGPoint(x: box / 2, y: box / 2)) { c in
                let ctx = c.context
                let rect = c.r(3, 3, diameter, diameter)
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: c.points(2), color: shade)
                ctx.setFillColor(CGColor(gray: 0.45, alpha: kind == .hand ? 0.62 : 0.48))
                ctx.fillEllipse(in: rect)
                ctx.restoreGState()
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.92))
                ctx.setLineWidth(c.points(1.6))
                ctx.strokeEllipse(in: rect.insetBy(dx: c.points(0.8), dy: c.points(0.8)))
                if kind == .text {
                    beam(c, beamPath(c, x: box / 2, top: box / 2 - 6.5, bottom: box / 2 + 6.5, serif: 2.2), line: paper, edge: CGColor(gray: 0.1, alpha: 0.7))
                }
            }
        case (.ring, _):
            let diameter: CGFloat = 24
            let box = diameter + 6
            return render(id, size: CGSize(width: box, height: box), hotSpot: CGPoint(x: box / 2, y: box / 2)) { c in
                let ctx = c.context
                let rect = c.r(3, 3, diameter, diameter)
                ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.45))
                ctx.setLineWidth(c.points(4.6))
                ctx.strokeEllipse(in: rect)
                ctx.setStrokeColor(paper)
                ctx.setLineWidth(c.points(2.6))
                ctx.strokeEllipse(in: rect)
                switch kind {
                case .text:
                    beam(c, beamPath(c, x: box / 2, top: box / 2 - 6, bottom: box / 2 + 6, serif: 2), line: paper, edge: CGColor(gray: 0, alpha: 0.5))
                case .hand:
                    let dot = c.r(box / 2 - 3, box / 2 - 3, 6, 6)
                    ctx.setFillColor(CGColor(gray: 0, alpha: 0.45))
                    ctx.fillEllipse(in: dot.insetBy(dx: -c.points(1), dy: -c.points(1)))
                    ctx.setFillColor(paper)
                    ctx.fillEllipse(in: dot)
                case .arrow:
                    break
                }
            }
        default:
            return render(id, size: CGSize(width: 20, height: 28), hotSpot: CGPoint(x: 3, y: 3)) { c in
                solid(c, arrowPath(c), fill: ink, edge: paper, edgeWidth: 1.2)
            }
        }
    }
}
