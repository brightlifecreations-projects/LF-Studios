import CoreImage
import Foundation

// MARK: - Adjust (1.15.0)

/// Properties ▸ Adjust, on a clip or an adjustment clip. Every value starts
/// at 0 (no change); sliders run −1…1 unless noted.
struct VideoAdjustSettings: Codable, Equatable {
    var exposure = 0.0
    var contrast = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var whites = 0.0
    var blacks = 0.0
    var saturation = 0.0
    var vibrance = 0.0
    var temperature = 0.0
    var tint = 0.0
    /// 0…1.
    var sharpen = 0.0
    var vignette = 0.0
    var grain = 0.0
    var fade = 0.0
    /// By colour (VideoHSLColor raw value).
    var hsl: [String: HSL]?
    var curves: Curves?
    var wheels: Wheels?

    struct HSL: Codable, Equatable {
        /// −1…1: up to 30° either way.
        var hue = 0.0
        var saturation = 0.0
        var luminance = 0.0
        var isNeutral: Bool { abs(hue) < 0.001 && abs(saturation) < 0.001 && abs(luminance) < 0.001 }
    }

    /// Points (x in, y out; 0…1) for all channels and each one.
    struct Curves: Codable, Equatable {
        var rgb: [VideoCurvePoint] = VideoCurvePoint.straight
        var red: [VideoCurvePoint] = VideoCurvePoint.straight
        var green: [VideoCurvePoint] = VideoCurvePoint.straight
        var blue: [VideoCurvePoint] = VideoCurvePoint.straight
        var isNeutral: Bool { [rgb, red, green, blue].allSatisfy { $0 == VideoCurvePoint.straight } }
    }

    /// Colour wheels: a colour push (x, y on the wheel, −1…1) and a
    /// brightness (−1…1) for shadows (lift), midtones (gamma), highlights
    /// (gain) and everything (offset).
    struct Wheels: Codable, Equatable {
        var lift = Wheel()
        var gamma = Wheel()
        var gain = Wheel()
        var offset = Wheel()
        var isNeutral: Bool { [lift, gamma, gain, offset].allSatisfy(\.isNeutral) }
    }

    struct Wheel: Codable, Equatable {
        var x = 0.0
        var y = 0.0
        var luminance = 0.0
        var isNeutral: Bool { abs(x) < 0.001 && abs(y) < 0.001 && abs(luminance) < 0.001 }

        /// The push on red, green and blue (sums to the luminance).
        var rgb: (Double, Double, Double) {
            // Hue 0° (right) is red; anticlockwise to yellow, green, blue.
            let amount = min(sqrt(x * x + y * y), 1)
            let angle = atan2(y, x)
            func channel(_ at: Double) -> Double { cos(angle - at) * amount }
            return (channel(0) + luminance, channel(2 * .pi / 3) + luminance, channel(4 * .pi / 3) + luminance)
        }
    }

    var isNeutral: Bool { self == VideoAdjustSettings() || (Self.toneKeys.allSatisfy { abs(self[keyPath: $0]) < 0.000_1 } && (hsl ?? [:]).values.allSatisfy(\.isNeutral) && (curves?.isNeutral ?? true) && (wheels?.isNeutral ?? true)) }
    /// Changes colour only (baked into a LUT).
    var colourIsNeutral: Bool { Self.colourKeys.allSatisfy { abs(self[keyPath: $0]) < 0.000_1 } && (hsl ?? [:]).values.allSatisfy(\.isNeutral) && (curves?.isNeutral ?? true) && (wheels?.isNeutral ?? true) }

    static let colourKeys: [WritableKeyPath<VideoAdjustSettings, Double>] = [\.exposure, \.contrast, \.highlights, \.shadows, \.whites, \.blacks, \.saturation, \.vibrance, \.temperature, \.tint, \.fade]
    static let toneKeys = colourKeys + [\.sharpen, \.vignette, \.grain]
}

struct VideoCurvePoint: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    static let straight = [VideoCurvePoint(x: 0, y: 0), VideoCurvePoint(x: 1, y: 1)]
}

/// The eight colours of HSL.
enum VideoHSLColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, aqua, blue, purple, magenta
    var id: String { rawValue }
    /// Degrees.
    var hue: Double {
        switch self {
        case .red: return 0
        case .orange: return 30
        case .yellow: return 60
        case .green: return 120
        case .aqua: return 180
        case .blue: return 225
        case .purple: return 270
        case .magenta: return 315
        }
    }
    var title: String {
        switch self {
        case .red: return L("Red")
        case .orange: return L("Orange")
        case .yellow: return L("Yellow")
        case .green: return L("Green")
        case .aqua: return L("Aqua")
        case .blue: return L("Blue")
        case .purple: return L("Purple")
        case .magenta: return L("Magenta")
        }
    }
}

enum VideoCurve {
    /// y at `x` through `points` (sorted by x; a smooth monotone curve).
    static func value(_ points: [VideoCurvePoint], at x: Double) -> Double {
        let p = points.sorted { $0.x < $1.x }
        guard let first = p.first, let last = p.last, p.count > 1 else { return x }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        // Fritsch–Carlson tangents.
        let n = p.count
        var d = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) { d[i] = (p[i + 1].y - p[i].y) / max(p[i + 1].x - p[i].x, 0.000_1) }
        var m = [Double](repeating: 0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        for i in 1..<(n - 1) { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
        for i in 0..<(n - 1) where abs(d[i]) < 0.000_1 { m[i] = 0; m[i + 1] = 0 }
        let i = (0..<(n - 1)).last { p[$0].x <= x } ?? 0
        let h = max(p[i + 1].x - p[i].x, 0.000_1)
        let t = (x - p[i].x) / h
        let t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * p[i].y + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * p[i + 1].y + (t3 - t2) * h * m[i + 1]
    }
}

extension VideoAdjustSettings {
    /// What it does to one colour (sRGB, 0…1).
    func transform(_ r0: Double, _ g0: Double, _ b0: Double) -> (Double, Double, Double) {
        var r = r0, g = g0, b = b0
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func gamma(_ c: Double) -> Double { let c = max(c, 0); return c <= 0.003_130_8 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }
        // Exposure: ±2 stops.
        if abs(exposure) > 0.000_1 {
            let gain = pow(2, exposure * 2)
            r = gamma(linear(r) * gain); g = gamma(linear(g) * gain); b = gamma(linear(b) * gain)
        }
        // Temperature (warmer: more red, less blue) and tint (toward magenta).
        r *= 1 + temperature * 0.12; b *= 1 - temperature * 0.12
        g *= 1 - tint * 0.08; r *= 1 + tint * 0.03; b *= 1 + tint * 0.03
        // Tones on brightness, keeping the colour.
        let l0 = max(0.2126 * r + 0.7152 * g + 0.0722 * b, 0)
        var l = l0
        if abs(contrast) > 0.000_1 {
            // An S-curve around the middle.
            let k = 1 + contrast * 0.8
            l = 0.5 + (l - 0.5) * k - contrast * 0.3 * (l - 0.5) * (1 - abs(2 * l - 1)) * 0.5
        }
        func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }
        l += highlights * 0.25 * smooth(0.45, 1, l0)
        l += shadows * 0.25 * (1 - smooth(0, 0.55, l0))
        l += whites * 0.2 * smooth(0.7, 1, l0)
        l += blacks * 0.15 * (1 - smooth(0, 0.3, l0))
        if abs(l - l0) > 0.000_01 {
            if l0 > 0.001 {
                let s = max(l, 0) / l0
                r *= s; g *= s; b *= s
            } else {
                r += l; g += l; b += l
            }
        }
        // Colour wheels.
        if let wheels, !wheels.isNeutral {
            let lift = wheels.lift.rgb, gam = wheels.gamma.rgb, gain = wheels.gain.rgb, off = wheels.offset.rgb
            func grade(_ c: Double, _ lift: Double, _ gamma: Double, _ gain: Double, _ offset: Double) -> Double {
                var c = max(c, 0)
                c = c * (1 + gain * 0.5)
                c = c + lift * 0.25 * (1 - c)
                c = pow(c, 1 / max(1 + gamma * 0.5, 0.2))
                return c + offset * 0.15
            }
            r = grade(r, lift.0, gam.0, gain.0, off.0)
            g = grade(g, lift.1, gam.1, gain.1, off.1)
            b = grade(b, lift.2, gam.2, gain.2, off.2)
        }
        // Saturation and vibrance (vibrance lifts the dull colours most).
        if abs(saturation) > 0.000_1 || abs(vibrance) > 0.000_1 {
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let current = (max(r, g, b) - min(r, g, b)) / max(max(r, g, b), 0.001)
            let s = max(1 + saturation, 0) * max(1 + vibrance * (1 - current), 0)
            r = luma + (r - luma) * s; g = luma + (g - luma) * s; b = luma + (b - luma) * s
        }
        // HSL by colour.
        if let hsl, hsl.values.contains(where: { !$0.isNeutral }) {
            var (h, s, v) = Self.hsv(r, g, b)
            var hueShift = 0.0, satScale = 0.0, lum = 0.0, total = 0.0
            for colour in VideoHSLColor.allCases {
                guard let change = hsl[colour.rawValue], !change.isNeutral else { continue }
                var distance = abs(h - colour.hue).truncatingRemainder(dividingBy: 360)
                if distance > 180 { distance = 360 - distance }
                let weight = max(0, 1 - distance / 40) * min(s * 3, 1)
                guard weight > 0 else { continue }
                hueShift += change.hue * 30 * weight
                satScale += change.saturation * weight
                lum += change.luminance * 0.3 * weight
                total += weight
            }
            if total > 0 {
                h = (h + hueShift).truncatingRemainder(dividingBy: 360)
                if h < 0 { h += 360 }
                s = min(max(s * (1 + satScale), 0), 1)
                v = max(v * (1 + lum), 0)
                (r, g, b) = Self.rgb(h, s, v)
            }
        }
        // Curves: all channels, then each.
        if let curves, !curves.isNeutral {
            r = VideoCurve.value(curves.rgb, at: min(max(r, 0), 1)); g = VideoCurve.value(curves.rgb, at: min(max(g, 0), 1)); b = VideoCurve.value(curves.rgb, at: min(max(b, 0), 1))
            r = VideoCurve.value(curves.red, at: min(max(r, 0), 1))
            g = VideoCurve.value(curves.green, at: min(max(g, 0), 1))
            b = VideoCurve.value(curves.blue, at: min(max(b, 0), 1))
        }
        // Fade: lifted blacks, a little less contrast.
        if fade > 0.000_1 {
            r = r * (1 - fade * 0.25) + fade * 0.12; g = g * (1 - fade * 0.25) + fade * 0.12; b = b * (1 - fade * 0.25) + fade * 0.12
        }
        return (min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1))
    }

    static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0.000_01 {
            if mx == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = 60 * ((b - r) / d + 2) }
            else { h = 60 * ((r - g) / d + 4) }
        }
        if h < 0 { h += 360 }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}

enum VideoAdjustRenderer {
    private static let cache = NSCache<NSString, VideoColorCubeBox>()

    final class VideoColorCubeBox {
        let cube: VideoColorCube
        init(_ cube: VideoColorCube) { self.cube = cube }
    }

    /// The colour part, baked into a 33³ LUT (cached by the settings).
    static func cube(_ settings: VideoAdjustSettings) -> VideoColorCube {
        let key = String(decoding: (try? JSONEncoder().encode(settings)) ?? Data(), as: UTF8.self) as NSString
        if let box = cache.object(forKey: key) { return box.cube }
        let cube = VideoColorCube.bake(size: 33, settings.transform)
        cache.setObject(VideoColorCubeBox(cube), forKey: key)
        return cube
    }

    /// `image` adjusted; `time` (seconds into the clip) moves the grain.
    static func apply(_ settings: VideoAdjustSettings, to image: CIImage, time: Double) -> CIImage {
        guard !settings.isNeutral else { return image }
        let extent = image.extent
        var out = image
        if !settings.colourIsNeutral { out = cube(settings).apply(to: out) }
        let scale = max(extent.height / 1080, 0.1)
        if settings.sharpen > 0.001 {
            out = out.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: settings.sharpen * 1.5, kCIInputRadiusKey: 1.5 * scale])
        }
        out = out.cropped(to: extent)
        if settings.vignette > 0.001 { out = VideoEffectRenderer.apply(.vignette, to: out, intensity: settings.vignette, time: time) }
        if settings.grain > 0.001 { out = VideoEffectRenderer.apply(.grain, to: out, intensity: settings.grain, time: time) }
        return out.cropped(to: extent)
    }
}
