import CoreImage

// MARK: - Masks (1.15.0)

/// A shape that keeps part of an item above the main track (or, inverted,
/// hides it), with a soft edge. Positions are the item's own, 0…1 from its
/// top left.
struct VideoMask: Codable, Equatable {
    enum Shape: String, Codable, CaseIterable, Identifiable {
        /// Everything on one side of a line.
        case linear
        /// A band between two lines.
        case mirror
        case circle
        case rectangle

        var id: String { rawValue }
        var title: String {
            switch self {
            case .linear: return L("Linear")
            case .mirror: return L("Mirror")
            case .circle: return L("Circle")
            case .rectangle: return L("Rectangle")
            }
        }
        var symbol: String {
            switch self {
            case .linear: return "square.bottomhalf.filled"
            case .mirror: return "square.split.1x2"
            case .circle: return "circle"
            case .rectangle: return "rectangle"
            }
        }
    }

    var shape: Shape = .circle
    var x = 0.5
    var y = 0.5
    /// Circle and rectangle: width as a share of the item's width; mirror:
    /// the band's width as a share of the item's height.
    var size = 0.6
    /// Circle and rectangle: height ÷ width (in the item's pixels).
    var aspect = 1.0
    /// Degrees clockwise.
    var rotation = 0.0
    /// The soft edge, as a share of the item's shorter side.
    var feather = 0.05
    var invert = false

    init(shape: Shape = .circle) {
        self.shape = shape
        if shape == .linear || shape == .mirror { size = 0.4 }
    }

    /// White where the item shows, black where it doesn't, over `extent`.
    func image(over extent: CGRect) -> CIImage {
        let w = extent.width, h = extent.height
        let short = max(min(w, h), 1)
        let soft = max(CGFloat(min(max(feather, 0), 0.5)) * short, 0.5)
        // Item space: x right, y up (Core Image); the mask's y runs down.
        let center = CGPoint(x: extent.minX + w * CGFloat(x), y: extent.minY + h * (1 - CGFloat(y)))
        let angle = -CGFloat(rotation) * .pi / 180
        let white = CIImage(color: .white), black = CIImage(color: .black)
        var mask: CIImage
        switch shape {
        case .circle:
            // A unit circle gradient, stretched into the ellipse and turned.
            let radius = max(w * CGFloat(size) / 2, 1)
            let inner = max(radius - soft / 2, 0)
            let outer = radius + soft / 2
            let gradient = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: 0, y: 0), "inputRadius0": inner, "inputRadius1": outer,
                "inputColor0": CIColor.white, "inputColor1": CIColor.black,
            ])!.outputImage!
            mask = gradient.transformed(by: CGAffineTransform(scaleX: 1, y: CGFloat(max(aspect, 0.01)))
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
        case .rectangle:
            let rw = max(w * CGFloat(size), 2)
            let rh = max(rw * CGFloat(max(aspect, 0.01)), 2)
            let box = CIImage(color: .white).cropped(to: CGRect(x: -rw / 2, y: -rh / 2, width: rw, height: rh))
                .composited(over: black.cropped(to: CGRect(x: -rw / 2 - soft * 3, y: -rh / 2 - soft * 3, width: rw + soft * 6, height: rh + soft * 6)))
                .clampedToExtent()
                .applyingGaussianBlur(sigma: Double(soft / 2))
            mask = box.transformed(by: CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
        case .linear, .mirror:
            // A gradient across the line (perpendicular to it), turned.
            let half = shape == .mirror ? max(h * CGFloat(size) / 2, 1) : 0
            func edge(_ offset: CGFloat, keepsAbove: Bool) -> CIImage {
                CIFilter(name: "CILinearGradient", parameters: [
                    "inputPoint0": CIVector(x: 0, y: offset - soft / 2), "inputPoint1": CIVector(x: 0, y: offset + soft / 2),
                    "inputColor0": keepsAbove ? CIColor.black : CIColor.white, "inputColor1": keepsAbove ? CIColor.white : CIColor.black,
                ])!.outputImage!
            }
            var local: CIImage
            if shape == .linear {
                // Keeps what's above the line (up on screen).
                local = edge(0, keepsAbove: true)
            } else {
                let top = edge(half, keepsAbove: false)
                let bottom = edge(-half, keepsAbove: true)
                local = top.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: bottom])
            }
            mask = local.transformed(by: CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
        }
        mask = mask.composited(over: black).cropped(to: extent)
        if invert { mask = mask.applyingFilter("CIColorInvert") }
        _ = white
        return mask
    }

    /// `image` kept where the mask is white (transparent elsewhere).
    func apply(to image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1, extent.width.isFinite else { return image }
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: self.image(over: extent),
        ])
    }
}
