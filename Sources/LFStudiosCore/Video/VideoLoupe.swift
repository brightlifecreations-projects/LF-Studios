import CoreImage
import Foundation

// MARK: - Look

/// How a loupe looks: a round or rounded magnifier over one spot while
/// the rest of the frame stays as it is. Its magnification is the zoom
/// block's own `scale`.
struct VideoLoupeStyle: Codable, Equatable {
    enum Shape: String, Codable, CaseIterable, Identifiable {
        case circle
        case rounded

        var id: String { rawValue }
        var title: String { self == .circle ? L("Circle") : L("Rounded") }
    }

    static let sizeRange: ClosedRange<Double> = 0.15...0.6
    static let borderRange: ClosedRange<Double> = 0...0.02
    static let animationRange: ClosedRange<Double> = 0...1

    /// Width as a fraction of the output's short side.
    var size = 0.34
    var shape: Shape = .circle
    /// Thickness as a fraction of the output's short side (0: none).
    var borderWidth = 0.006
    var borderColor = VideoRGBA(1, 1, 1)
    /// 0 none … 1 strong.
    var shadow = 0.5
    /// Seconds the loupe takes to open and to close.
    var animation = 0.3

    init() {}

    private enum CodingKeys: String, CodingKey { case size, shape, borderWidth, borderColor, shadow, animation }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VideoLoupeStyle()
        size = (try? c.decodeIfPresent(Double.self, forKey: .size)) ?? d.size
        shape = (try? c.decodeIfPresent(Shape.self, forKey: .shape)) ?? d.shape
        borderWidth = (try? c.decodeIfPresent(Double.self, forKey: .borderWidth)) ?? d.borderWidth
        borderColor = (try? c.decodeIfPresent(VideoRGBA.self, forKey: .borderColor)) ?? d.borderColor
        shadow = (try? c.decodeIfPresent(Double.self, forKey: .shadow)) ?? d.shadow
        animation = (try? c.decodeIfPresent(Double.self, forKey: .animation)) ?? d.animation
    }

    /// Every value inside its range.
    var clamped: VideoLoupeStyle {
        var style = self
        style.size = min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        style.borderWidth = min(max(borderWidth, Self.borderRange.lowerBound), Self.borderRange.upperBound)
        style.shadow = min(max(shadow, 0), 1)
        style.animation = min(max(animation, Self.animationRange.lowerBound), Self.animationRange.upperBound)
        return style
    }

    /// Corner radius for a loupe `width` wide.
    func cornerRadius(width: CGFloat) -> CGFloat {
        shape == .circle ? width / 2 : width * 0.2
    }
}

// MARK: - Timing

/// A loupe on the edited timeline.
struct VideoLoupeSpan {
    let region: VideoZoomRegion
    let style: VideoLoupeStyle
    /// Timeline seconds.
    let start: Double
    let end: Double

    /// 0 closed … 1 fully open.
    func openness(at time: Double) -> Double {
        guard time >= start, time <= end else { return 0 }
        let ramp = min(style.animation, (end - start) / 2)
        guard ramp > 0.001 else { return 1 }
        let opening = VideoCameraEasing.spring((time - start) / ramp)
        let closing = VideoCameraEasing.spring((end - time) / ramp)
        return min(opening, closing)
    }

    static func spans(project: VideoDemoProject, segments: [VideoDemoTimelineSegment]) -> [VideoLoupeSpan] {
        project.zoomRegions.compactMap { region in
            guard let style = region.loupe else { return nil }
            let ranges = VideoDemoProject.timelineRanges(sourceStart: region.start, sourceEnd: region.end, segments: segments).sorted { $0.lowerBound < $1.lowerBound }
            guard let first = ranges.first, let last = ranges.last else { return nil }
            return VideoLoupeSpan(region: region, style: style.clamped, start: first.lowerBound, end: last.upperBound)
        }
    }
}

extension VideoRenderPlan {
    /// What a zoom block looks at, at a source moment: the text cursor,
    /// the pointer, or its own focus (video-normalized, y down, before the
    /// crop is applied).
    func subject(of region: VideoZoomRegion, at sourceTime: Double) -> CGPoint {
        let focus = CGPoint(x: region.focusX, y: region.focusY)
        if region.followsTyping {
            return typingTrack?.position(at: sourceTime) ?? focus
        }
        if region.followsCursor {
            return cursorTrack?.position(at: sourceTime) ?? focus
        }
        return focus
    }

    /// A video point → logical canvas point (top-left origin).
    func canvasPoint(forVideoPoint point: CGPoint) -> CGPoint {
        let mapped = crop.map(point)
        return CGPoint(x: stageRect.minX + stageRect.width * mapped.x, y: stageRect.minY + stageRect.height * mapped.y)
    }
}

// MARK: - Drawing

extension VideoFrameRenderer {
    /// The loupes playing at `timelineTime`, over the scene.
    func drawLoupes(on scene: CIImage, plan: VideoRenderPlan, geometry: Geometry, timelineTime: Double, sourceTime: Double) -> CIImage {
        var output = scene
        for loupe in plan.loupes {
            let open = loupe.openness(at: timelineTime)
            guard open > 0.001 else { continue }
            let subject = geometry.point(plan.canvasPoint(forVideoPoint: plan.subject(of: loupe.region, at: sourceTime)))
            output = drawLoupe(loupe, subject: subject, open: open, over: output, outputSize: geometry.output)
        }
        return output
    }

    /// One loupe: the scene magnified about `subject` (output pixels,
    /// y up), shown in a lens at the subject plus the block's offset.
    func drawLoupe(_ loupe: VideoLoupeSpan, subject: CGPoint, open: Double, over scene: CIImage, outputSize: CGSize) -> CIImage {
        let style = loupe.style
        let shortSide = min(outputSize.width, outputSize.height)
        let e = CGFloat(open)
        let width = CGFloat(style.size) * shortSide * (0.6 + 0.4 * e)
        guard width > 2 else { return scene }
        let center = CGPoint(
            x: subject.x + CGFloat(loupe.region.offsetX) * outputSize.width,
            y: subject.y - CGFloat(loupe.region.offsetY) * outputSize.height
        )
        let magnification = 1 + (CGFloat(loupe.region.scale) - 1) * e
        let rect = CGRect(x: center.x - width / 2, y: center.y - width / 2, width: width, height: width)
        let radius = style.cornerRadius(width: width)

        let magnified = scene.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: -subject.x, y: -subject.y)
                .concatenating(CGAffineTransform(scaleX: magnification, y: magnification))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
            .cropped(to: rect)
        let mask = roundedRect(rect, radius: radius, color: .white)
        var lens = magnified.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: mask])

        let border = CGFloat(style.borderWidth) * shortSide
        if border >= 0.5 {
            let color = style.borderColor
            let outer = roundedRect(rect, radius: radius, color: CIColor(red: color.r, green: color.g, blue: color.b, alpha: color.a))
            let inner = roundedRect(rect.insetBy(dx: border, dy: border), radius: max(radius - border, 0), color: .white)
            let ring = outer.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner])
            lens = ring.composited(over: lens)
        }
        if style.shadow > 0.01 {
            let blur = width * 0.08
            let drop = width * 0.035
            let area = rect.insetBy(dx: -blur * 3, dy: -blur * 3).offsetBy(dx: 0, dy: -drop)
            let shade = roundedRect(rect.offsetBy(dx: 0, dy: -drop), radius: radius, color: CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(0.55 * style.shadow)))
                .composited(over: CIImage(color: .clear).cropped(to: area))
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
                .cropped(to: area)
            lens = lens.composited(over: shade)
        }
        let alpha = min(Double(e) * 1.6, 1)
        if alpha < 0.999 {
            lens = lens.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))])
        }
        return lens.composited(over: scene)
    }
}
