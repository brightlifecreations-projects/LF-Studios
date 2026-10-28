import CoreImage
import Foundation

/// Color and sharpness for the camera picture only (never the screen),
/// drawn with Core Image. The values at rest change nothing.
struct VideoCameraColor: Codable, Equatable {
    static let brightnessRange: ClosedRange<Double> = -0.3...0.3
    static let contrastRange: ClosedRange<Double> = 0.6...1.5
    static let saturationRange: ClosedRange<Double> = 0...2
    static let warmthRange: ClosedRange<Double> = -1...1
    static let tintRange: ClosedRange<Double> = -1...1
    static let sharpnessRange: ClosedRange<Double> = 0...1

    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    /// −1 cooler … 1 warmer.
    var warmth = 0.0
    /// −1 greener … 1 more magenta.
    var tint = 0.0
    var sharpness = 0.0

    static let neutral = VideoCameraColor()

    init() {}

    init(brightness: Double = 0, contrast: Double = 1, saturation: Double = 1, warmth: Double = 0, tint: Double = 0, sharpness: Double = 0) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.tint = tint
        self.sharpness = sharpness
    }

    private enum CodingKeys: String, CodingKey { case brightness, contrast, saturation, warmth, tint, sharpness }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = (try? c.decodeIfPresent(Double.self, forKey: .brightness)) ?? 0
        contrast = (try? c.decodeIfPresent(Double.self, forKey: .contrast)) ?? 1
        saturation = (try? c.decodeIfPresent(Double.self, forKey: .saturation)) ?? 1
        warmth = (try? c.decodeIfPresent(Double.self, forKey: .warmth)) ?? 0
        tint = (try? c.decodeIfPresent(Double.self, forKey: .tint)) ?? 0
        sharpness = (try? c.decodeIfPresent(Double.self, forKey: .sharpness)) ?? 0
    }

    var clamped: VideoCameraColor {
        VideoCameraColor(
            brightness: min(max(brightness, Self.brightnessRange.lowerBound), Self.brightnessRange.upperBound),
            contrast: min(max(contrast, Self.contrastRange.lowerBound), Self.contrastRange.upperBound),
            saturation: min(max(saturation, Self.saturationRange.lowerBound), Self.saturationRange.upperBound),
            warmth: min(max(warmth, Self.warmthRange.lowerBound), Self.warmthRange.upperBound),
            tint: min(max(tint, Self.tintRange.lowerBound), Self.tintRange.upperBound),
            sharpness: min(max(sharpness, Self.sharpnessRange.lowerBound), Self.sharpnessRange.upperBound)
        )
    }

    var isNeutral: Bool {
        let c = clamped
        return abs(c.brightness) < 0.001 && abs(c.contrast - 1) < 0.001 && abs(c.saturation - 1) < 0.001
            && abs(c.warmth) < 0.001 && abs(c.tint) < 0.001 && c.sharpness < 0.001
    }

    // MARK: Looks

    enum Look: String, CaseIterable, Identifiable {
        case natural
        case warm
        case bright
        case cinematic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .natural: return L("Natural")
            case .warm: return L("Warm")
            case .bright: return L("Bright")
            case .cinematic: return L("Cinematic")
            }
        }

        var color: VideoCameraColor {
            switch self {
            case .natural: return VideoCameraColor(contrast: 1.04, saturation: 1.04, sharpness: 0.2)
            case .warm: return VideoCameraColor(brightness: 0.02, contrast: 1.05, saturation: 1.1, warmth: 0.45, tint: 0.05, sharpness: 0.2)
            case .bright: return VideoCameraColor(brightness: 0.09, contrast: 0.96, saturation: 1.08, warmth: 0.1, sharpness: 0.25)
            case .cinematic: return VideoCameraColor(brightness: -0.01, contrast: 1.1, saturation: 0.82, warmth: 0.2, tint: -0.06, sharpness: 0.3)
            }
        }
    }

    /// The look these values are, if they're one.
    var look: Look? { Look.allCases.first { $0.color == self } }

    // MARK: Drawing

    /// The picture with these values. `pixelsPerPoint` sizes the
    /// sharpening to the picture as drawn.
    func apply(to image: CIImage, pixelsPerPoint: CGFloat = 1) -> CIImage {
        let c = clamped
        guard !c.isNeutral else { return image }
        var output = image
        if abs(c.warmth) > 0.001 || abs(c.tint) > 0.001 {
            // A target neutral below the source's warms the picture; above
            // it, cools it.
            output = output.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: CGFloat(6500 - c.warmth * 2200), y: CGFloat(c.tint * 40)),
            ])
        }
        if abs(c.brightness) > 0.001 || abs(c.contrast - 1) > 0.001 || abs(c.saturation - 1) > 0.001 {
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: c.brightness,
                kCIInputContrastKey: c.contrast,
                kCIInputSaturationKey: c.saturation,
            ])
        }
        if c.sharpness > 0.001 {
            output = output.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: c.sharpness * 1.2,
                kCIInputRadiusKey: max(1.2 * pixelsPerPoint, 1),
            ])
        }
        return output.cropped(to: image.extent)
    }

    // MARK: Auto adjust

    /// What a camera picture is like: average brightness and spread, and
    /// its color cast (all 0…1, from a small copy of the frame).
    struct Measure: Equatable {
        var luminance: Double
        var spread: Double
        var red: Double
        var green: Double
        var blue: Double
        var chroma: Double

        static func of(_ image: CIImage, context: CIContext = VideoRenderContext.shared) -> Measure? {
            let extent = image.extent
            guard extent.width > 1, extent.height > 1 else { return nil }
            let width = 64, height = 36
            let small = image
                .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height))
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            context.render(small, toBitmap: &pixels, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            var sum = 0.0, squares = 0.0, r = 0.0, g = 0.0, b = 0.0, chroma = 0.0
            let count = Double(width * height)
            for index in stride(from: 0, to: pixels.count, by: 4) {
                let pr = Double(pixels[index]) / 255, pg = Double(pixels[index + 1]) / 255, pb = Double(pixels[index + 2]) / 255
                let y = 0.2126 * pr + 0.7152 * pg + 0.0722 * pb
                sum += y
                squares += y * y
                r += pr
                g += pg
                b += pb
                chroma += max(pr, pg, pb) - min(pr, pg, pb)
            }
            let mean = sum / count
            return Measure(luminance: mean, spread: max(squares / count - mean * mean, 0).squareRoot(), red: r / count, green: g / count, blue: b / count, chroma: chroma / count)
        }
    }

    /// Suggested values for pictures like these: lift or lower toward a
    /// well-exposed middle, open up flat pictures, and cancel a color cast.
    static func suggestion(from measures: [Measure]) -> VideoCameraColor {
        guard !measures.isEmpty else { return VideoCameraColor() }
        let n = Double(measures.count)
        let luminance = measures.map(\.luminance).reduce(0, +) / n
        let spread = measures.map(\.spread).reduce(0, +) / n
        let red = measures.map(\.red).reduce(0, +) / n
        let green = measures.map(\.green).reduce(0, +) / n
        let blue = measures.map(\.blue).reduce(0, +) / n
        let chroma = measures.map(\.chroma).reduce(0, +) / n

        func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        var color = VideoCameraColor()
        color.brightness = rounded(min(max((0.48 - luminance) * 0.5, -0.15), 0.15))
        color.contrast = rounded(min(max(0.21 / max(spread, 0.02), 0.92), 1.3))
        // A cast is the channels apart from their average.
        let average = (red + green + blue) / 3
        color.warmth = rounded(min(max((blue - red) * 3, -0.6), 0.6))
        color.tint = rounded(min(max((green - average) * -4, -0.5), 0.5))
        color.saturation = rounded(chroma < 0.12 ? 1.12 : (chroma > 0.35 ? 0.92 : 1.04))
        color.sharpness = 0.2
        return color.clamped
    }
}
