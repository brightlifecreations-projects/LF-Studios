import AppKit
import CoreImage
import Vision

// MARK: - Edits with values (1.15.0)

/// What a `VideoEditCommand.edit` does to the selected item above the main
/// track. Settings act at the playhead (a key there when animated); each
/// makes one ⌘Z step (a slider's drag is one step) and refuses on a locked
/// track.
enum VideoItemEdit: Equatable {
    /// An animatable setting, at the playhead.
    case setValue(VideoKeyProperty, Double)
    case toggleKeyframe(VideoKeyProperty)
    case setEasing(VideoEasing)
    case setBlend(VideoBlendMode?)
    case setRemoveBackground(Bool)
    case setChromaKey(VideoChromaKey?)
    case setMask(VideoMask?)
    case setAnimation(VideoItemAnimation?)
    case setSpeed(Double)
    case setKeepPitch(Bool)
    case setSoundFades(Double, Double)
    case normalize
    /// A text clip's words and look (its size follows).
    case setText(VideoTextContent)

    var name: String {
        switch self {
        case .setValue(let p, let v): return "setValue.\(p.rawValue).\(v)"
        case .toggleKeyframe(let p): return "toggleKeyframe.\(p.rawValue)"
        case .setEasing(let e): return "setEasing.\(e.rawValue)"
        case .setBlend(let b): return "setBlend.\(b?.rawValue ?? "normal")"
        case .setRemoveBackground(let on): return "setRemoveBackground.\(on)"
        case .setChromaKey(let c): return "setChromaKey.\(c == nil ? "off" : "on")"
        case .setMask(let m): return "setMask.\(m?.shape.rawValue ?? "none")"
        case .setSpeed(let s): return "setSpeed.\(s)"
        case .setKeepPitch(let on): return "setKeepPitch.\(on)"
        case .setSoundFades(let a, let b): return "setSoundFades.\(a).\(b)"
        case .normalize: return "normalize"
        case .setText(let t): return "setText.\(t.string.count)"
        case .setAnimation(let a): return "setAnimation.\(a?.inPreset?.rawValue ?? "-").\(a?.outPreset?.rawValue ?? "-").\(a?.combo?.rawValue ?? "-")"
        }
    }

    var title: String {
        switch self {
        case .setValue(let p, _): return p.title
        case .toggleKeyframe(let p): return L("Keyframe: \(p.title)")
        case .setEasing: return L("Easing")
        case .setBlend: return L("Blend")
        case .setRemoveBackground: return L("Remove background")
        case .setChromaKey: return L("Chroma key")
        case .setMask: return L("Mask")
        case .setAnimation: return L("Animation")
        case .setSpeed: return L("Speed")
        case .setKeepPitch: return L("Keep pitch")
        case .setSoundFades: return L("Fade")
        case .normalize: return L("Normalize loudness")
        case .setText: return L("Text")
        }
    }
}

extension VideoEditorModel {
    func perform(_ edit: VideoItemEdit) -> Bool {
        guard let item = selectedLayerItem else {
            showNotice(L("Select a clip above the main track first"), symbol: "square.2.layers.3d.top.filled")
            return false
        }
        guard let track = project.layerTrackIndex(of: item.id), !refuseLockedLayer(track) else { return false }
        switch edit {
        case .setValue(let property, let value):
            setLayerAnimated(item.id, coalesce: "value-\(property.rawValue)-\(item.id)", label: "Clip Change") { $0.setBase(property, value) }
        case .toggleKeyframe(let property):
            toggleKeyframe(item.id, property)
        case .setEasing(let easing):
            setKeyEasing(item.id, easing)
        case .setBlend(let blend):
            setLayerItem(item.id, label: "Blend") { $0.blend = blend == .normal ? nil : blend }
        case .setRemoveBackground(let on):
            setLayerItem(item.id, label: on ? "Remove Background" : "Keep Background") { $0.removesBackground = on ? true : nil }
        case .setChromaKey(let key):
            setLayerItem(item.id, coalesce: key == nil ? nil : "chroma-\(item.id)", label: "Chroma Key") { $0.chroma = key }
        case .setMask(let mask):
            setLayerItem(item.id, coalesce: mask == nil ? nil : "mask-\(item.id)", label: "Mask") { stored in
                // A new shape keeps the place of the old one.
                if var mask, let old = stored.mask, mask.shape != old.shape, mask.x == 0.5, mask.y == 0.5 {
                    mask.x = old.x
                    mask.y = old.y
                    stored.mask = mask
                } else {
                    stored.mask = mask
                }
                if mask == nil { stored.removeKeys(VideoKeyProperty.group(.maskX)) }
            }
        case .setSpeed(let speed):
            guard item.isVideo else { return false }
            setLayerSpeed(item.id, speed)
        case .setKeepPitch(let on):
            guard item.isVideo else { return false }
            setLayerItem(item.id, label: on ? "Keep Pitch" : "Change Pitch") { $0.keepsPitch = on ? nil : false }
        case .setSoundFades(let fadeIn, let fadeOut):
            guard item.isVideo else { return false }
            setLayerItem(item.id, coalesce: "sound-fades-\(item.id)", label: "Audio Track Change") { item in
                item.soundFadeIn = fadeIn > 0.01 ? min(fadeIn, 10) : nil
                item.soundFadeOut = fadeOut > 0.01 ? min(fadeOut, 10) : nil
            }
        case .normalize:
            guard item.isVideo else { return false }
            let url = URL(fileURLWithPath: item.path), id = item.id
            Task {
                let volume = await Task.detached(priority: .userInitiated) { VideoAudioAnalysis.normalizedVolume(url) }.value
                guard let volume else {
                    showNotice(L("It's silent: nothing to normalize"), symbol: "speaker.slash")
                    return
                }
                setLayerItem(id, label: "Normalize Loudness") { $0.volume = volume }
            }
        case .setText(let content):
            guard item.isText else { return false }
            setTextContent(item.id, content)
        case .setAnimation(let animation):
            setLayerItem(item.id, coalesce: "animation-\(item.id)", label: "Animation") { $0.animation = animation?.isEmpty == true ? nil : animation }
        }
        return true
    }
}

extension VideoLayerItem {
    mutating func removeKeys(_ properties: [VideoKeyProperty]) {
        guard var keys else { return }
        for property in properties { keys.tracks[property.rawValue] = nil }
        self.keys = keys.isEmpty ? nil : keys
    }
}

// MARK: - Blend modes

enum VideoBlendMode: String, Codable, CaseIterable, Identifiable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight, difference, add

    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: return L("Normal")
        case .multiply: return L("Multiply")
        case .screen: return L("Screen")
        case .overlay: return L("Overlay")
        case .darken: return L("Darken")
        case .lighten: return L("Lighten")
        case .colorDodge: return L("Color dodge")
        case .colorBurn: return L("Color burn")
        case .softLight: return L("Soft light")
        case .hardLight: return L("Hard light")
        case .difference: return L("Difference")
        case .add: return L("Add")
        }
    }

    var filter: String? {
        switch self {
        case .normal: return nil
        case .multiply: return "CIMultiplyBlendMode"
        case .screen: return "CIScreenBlendMode"
        case .overlay: return "CIOverlayBlendMode"
        case .darken: return "CIDarkenBlendMode"
        case .lighten: return "CILightenBlendMode"
        case .colorDodge: return "CIColorDodgeBlendMode"
        case .colorBurn: return "CIColorBurnBlendMode"
        case .softLight: return "CISoftLightBlendMode"
        case .hardLight: return "CIHardLightBlendMode"
        case .difference: return "CIDifferenceBlendMode"
        case .add: return "CIAdditionCompositing"
        }
    }

    /// `image` blended onto `scene`, only where `image` is.
    func composite(_ image: CIImage, over scene: CIImage) -> CIImage {
        guard let filter else { return image.composited(over: scene) }
        let blended = image.applyingFilter(filter, parameters: [kCIInputBackgroundImageKey: scene])
        return blended.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: scene,
            kCIInputMaskImageKey: image,
        ]).cropped(to: scene.extent)
    }
}

// MARK: - Cutout

/// Chroma key: one colour (a green or blue screen) taken out.
struct VideoChromaKey: Codable, Equatable {
    var color = VideoRGBA(0.0, 0.85, 0.2)
    /// How far from the colour still goes (0…1).
    var strength = 0.35
    /// How much of the shadows on the screen stays (0…1).
    var shadow = 0.0

    /// The colour cube that makes it see-through.
    func cube(size: Int = 32) -> Data {
        func ycc(_ r: Double, _ g: Double, _ b: Double) -> (y: Double, cb: Double, cr: Double) {
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return (y, (b - y) / 1.8556, (r - y) / 1.5748)
        }
        let key = ycc(color.r, color.g, color.b)
        let tolerance = 0.03 + 0.4 * min(max(strength, 0), 1)
        let edge = 0.06
        var data = [Float](repeating: 0, count: size * size * size * 4)
        var index = 0
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let rf = Double(r) / Double(size - 1), gf = Double(g) / Double(size - 1), bf = Double(b) / Double(size - 1)
                    let c = ycc(rf, gf, bf)
                    let distance = hypot(c.cb - key.cb, c.cr - key.cr)
                    var alpha = min(max((distance - tolerance) / edge, 0), 1)
                    if shadow > 0, alpha < 1 {
                        // Darker than the screen: kept as a shadow.
                        let darker = min(max((key.y - c.y) / max(key.y, 0.01), 0), 1)
                        alpha = max(alpha, darker * min(max(shadow, 0), 1))
                    }
                    let a = Float(alpha)
                    data[index] = Float(rf) * a
                    data[index + 1] = Float(gf) * a
                    data[index + 2] = Float(bf) * a
                    data[index + 3] = a
                    index += 4
                }
            }
        }
        return data.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

enum VideoCutout {
    private static let cubes = NSCache<NSString, NSData>()

    /// The key's colour taken out of `image`.
    static func chroma(_ image: CIImage, key: VideoChromaKey) -> CIImage {
        let name = "\(key.color.r),\(key.color.g),\(key.color.b),\(key.strength),\(key.shadow)" as NSString
        let data: Data
        if let cached = cubes.object(forKey: name) {
            data = cached as Data
        } else {
            data = key.cube()
            cubes.setObject(data as NSData, forKey: name)
        }
        return image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": 32, "inputCubeData": data,
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
    }

    private static let masks = NSCache<NSString, CIImage>()
    private static let lock = NSLock()

    /// Just the person in `image` (Vision person segmentation), the rest
    /// see-through. `key` names the frame, so each is found once.
    static func person(_ image: CIImage, key: String) -> CIImage {
        let mask: CIImage
        if let cached = masks.object(forKey: key as NSString) {
            mask = cached
        } else {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .balanced
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(ciImage: image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)))
            lock.lock()
            try? handler.perform([request])
            lock.unlock()
            guard let buffer = request.results?.first?.pixelBuffer else { return image }
            let found = CIImage(cvPixelBuffer: buffer)
            // Back over the picture's own size and place.
            let sx = image.extent.width / max(found.extent.width, 1)
            let sy = image.extent.height / max(found.extent.height, 1)
            mask = found.transformed(by: CGAffineTransform(scaleX: sx, y: sy).concatenating(CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY)))
            masks.setObject(mask, forKey: key as NSString)
        }
        return image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask])
    }
}
