import Foundation

// MARK: - Keyframes (1.15.0)

/// How a value travels from one keyframe to the next.
enum VideoEasing: String, Codable, CaseIterable, Identifiable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    var id: String { rawValue }
    var title: String {
        switch self {
        case .linear: return L("Linear")
        case .easeIn: return L("Ease in")
        case .easeOut: return L("Ease out")
        case .easeInOut: return L("Ease in and out")
        }
    }

    /// 0…1 → 0…1.
    func apply(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear: return t
        case .easeIn: return t * t * t
        case .easeOut: return 1 - pow(1 - t, 3)
        case .easeInOut: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        }
    }
}

/// What can be animated on an item above the main track.
enum VideoKeyProperty: String, Codable, CaseIterable, Identifiable {
    case x, y, width, rotation, opacity
    case cropX, cropY, cropWidth, cropHeight
    case maskX, maskY, maskSize, maskRotation, maskFeather
    case volume
    case intensity

    var id: String { rawValue }
    var title: String {
        switch self {
        case .x, .y: return L("Position")
        case .width: return L("Size")
        case .rotation: return L("Rotation")
        case .opacity: return L("Opacity")
        case .cropX, .cropY, .cropWidth, .cropHeight: return L("Crop")
        case .maskX, .maskY, .maskSize, .maskRotation, .maskFeather: return L("Mask")
        case .volume: return L("Volume")
        case .intensity: return L("Intensity")
        }
    }

    /// The diamond next to a control keys these together (Position is x
    /// and y; Crop its four sides; Mask all of its own).
    static func group(_ property: VideoKeyProperty) -> [VideoKeyProperty] {
        switch property {
        case .x, .y: return [.x, .y]
        case .cropX, .cropY, .cropWidth, .cropHeight: return [.cropX, .cropY, .cropWidth, .cropHeight]
        case .maskX, .maskY, .maskSize, .maskRotation, .maskFeather: return [.maskX, .maskY, .maskSize, .maskRotation, .maskFeather]
        default: return [property]
        }
    }
}

struct VideoKey: Codable, Equatable {
    /// Seconds from the item's start.
    var time: Double
    var value: Double
    /// How it travels to the next key.
    var easing: VideoEasing = .linear
}

/// Each animated property's keys, sorted by time.
struct VideoKeyframes: Codable, Equatable {
    var tracks: [String: [VideoKey]] = [:]

    var isEmpty: Bool { tracks.values.allSatisfy(\.isEmpty) }

    func keys(_ property: VideoKeyProperty) -> [VideoKey] { tracks[property.rawValue] ?? [] }
    func isAnimated(_ property: VideoKeyProperty) -> Bool { !keys(property).isEmpty }

    /// Every key time, once (the marks on the clip).
    var times: [Double] {
        Array(Set(tracks.values.flatMap { $0.map { ($0.time * 1000).rounded() / 1000 } })).sorted()
    }

    /// The value at `time`: `base` with no keys; held before the first and
    /// after the last; eased between.
    func value(_ property: VideoKeyProperty, at time: Double, base: Double) -> Double {
        let keys = self.keys(property)
        guard let first = keys.first, let last = keys.last else { return base }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        guard let index = keys.lastIndex(where: { $0.time <= time }), index + 1 < keys.count else { return last.value }
        let a = keys[index], b = keys[index + 1]
        let span = max(b.time - a.time, 0.000_001)
        return a.value + (b.value - a.value) * a.easing.apply((time - a.time) / span)
    }

    /// A key at `time` (within a frame, `tolerance`): replaced, or added.
    mutating func set(_ property: VideoKeyProperty, at time: Double, value: Double, tolerance: Double = 1.0 / 120) {
        var keys = self.keys(property)
        if let index = keys.firstIndex(where: { abs($0.time - time) <= tolerance }) {
            keys[index].value = value
        } else {
            keys.append(VideoKey(time: time, value: value))
            keys.sort { $0.time < $1.time }
        }
        tracks[property.rawValue] = keys
    }

    mutating func remove(_ property: VideoKeyProperty, at time: Double, tolerance: Double = 1.0 / 120) {
        var keys = self.keys(property)
        keys.removeAll { abs($0.time - time) <= tolerance }
        tracks[property.rawValue] = keys.isEmpty ? nil : keys
    }

    func hasKey(_ property: VideoKeyProperty, at time: Double, tolerance: Double = 1.0 / 120) -> Bool {
        keys(property).contains { abs($0.time - time) <= tolerance }
    }

    mutating func setEasing(_ easing: VideoEasing, at time: Double, tolerance: Double = 1.0 / 120) {
        for (name, keys) in tracks {
            tracks[name] = keys.map { key in
                var key = key
                if abs(key.time - time) <= tolerance { key.easing = easing }
                return key
            }
        }
    }

    /// Keys moved by `delta` seconds and kept inside `0…length` (a trim at
    /// the start shifts them; one at the end drops those past it).
    mutating func shift(by delta: Double, length: Double) {
        for (name, keys) in tracks {
            let moved = keys.map { key -> VideoKey in
                var key = key
                key.time += delta
                return key
            }.filter { $0.time >= -0.0005 && $0.time <= length + 0.0005 }
            tracks[name] = moved.isEmpty ? nil : moved
        }
    }
}

extension VideoLayerItem {
    /// The base value of an animatable property (what it is without keys).
    func base(_ property: VideoKeyProperty) -> Double {
        let crop = (self.crop ?? .full).normalized
        let mask = self.mask ?? VideoMask()
        switch property {
        case .x: return x
        case .y: return y
        case .width: return width
        case .rotation: return rotation
        case .opacity: return opacity
        case .cropX: return crop.x
        case .cropY: return crop.y
        case .cropWidth: return crop.width
        case .cropHeight: return crop.height
        case .maskX: return mask.x
        case .maskY: return mask.y
        case .maskSize: return mask.size
        case .maskRotation: return mask.rotation
        case .maskFeather: return mask.feather
        case .volume: return volume
        case .intensity: return intensity
        }
    }

    mutating func setBase(_ property: VideoKeyProperty, _ value: Double) {
        switch property {
        case .x: x = value
        case .y: y = value
        case .width: width = value
        case .rotation: rotation = value
        case .opacity: opacity = value
        case .cropX, .cropY, .cropWidth, .cropHeight:
            var crop = (self.crop ?? .full).normalized
            switch property {
            case .cropX: crop.x = value
            case .cropY: crop.y = value
            case .cropWidth: crop.width = value
            default: crop.height = value
            }
            crop = crop.normalized
            self.crop = crop.isFull ? nil : crop
        case .maskX, .maskY, .maskSize, .maskRotation, .maskFeather:
            guard var mask = self.mask else { return }
            switch property {
            case .maskX: mask.x = value
            case .maskY: mask.y = value
            case .maskSize: mask.size = value
            case .maskRotation: mask.rotation = value
            default: mask.feather = value
            }
            self.mask = mask
        case .volume: volume = value
        case .intensity: intensity = value
        }
    }

    /// The value of `property` at timeline `time` (keys, or the base).
    func value(_ property: VideoKeyProperty, at time: Double) -> Double {
        keys?.value(property, at: time - at, base: base(property)) ?? base(property)
    }

    /// This item as it is at timeline `time`: every keyed property at its
    /// value there (what the renderer and the handles draw).
    func resolved(at time: Double) -> VideoLayerItem {
        guard let keys, !keys.isEmpty else { return self }
        var item = self
        for property in VideoKeyProperty.allCases where keys.isAnimated(property) {
            item.setBase(property, keys.value(property, at: time - at, base: base(property)))
        }
        return item
    }
}
