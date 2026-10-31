import CoreImage
import SwiftUI

// MARK: - Library ▸ Effects (1.15.0)

/// What a clip above the main track is when it isn't media or text: it
/// changes what's under it while it shows.
enum VideoLayerRole: String, Codable {
    /// Effect clip: an effect on everything under it.
    case effect
    /// Adjustment clip: the Adjust settings and a filter on everything under
    /// it (VideoAdjust.swift).
    case adjustment
}

/// Our own Core Image effects.
enum VideoEffectKind: String, Codable, CaseIterable, Identifiable {
    case blur, glow, glitch, shake, vhs, zoomPulse, vignette, grain, rgbSplit, pixelate, noir, strobe, letterbox, mirror

    var id: String { rawValue }
    var title: String {
        switch self {
        case .blur: return L("Blur")
        case .glow: return L("Glow")
        case .glitch: return L("Glitch")
        case .shake: return L("Shake")
        case .vhs: return L("VHS")
        case .zoomPulse: return L("Zoom pulse")
        case .vignette: return L("Vignette")
        case .grain: return L("Film grain")
        case .rgbSplit: return L("RGB split")
        case .pixelate: return L("Pixelate")
        case .noir: return L("Black & white")
        case .strobe: return L("Strobe")
        case .letterbox: return L("Cinema bars")
        case .mirror: return L("Mirror")
        }
    }
    var symbol: String {
        switch self {
        case .blur: return "drop"
        case .glow: return "sun.max"
        case .glitch: return "waveform.path.ecg"
        case .shake: return "iphone.radiowaves.left.and.right"
        case .vhs: return "videoprojector"
        case .zoomPulse: return "plus.magnifyingglass"
        case .vignette: return "circle.dashed"
        case .grain: return "circle.grid.3x3"
        case .rgbSplit: return "square.3.layers.3d"
        case .pixelate: return "square.grid.4x3.fill"
        case .noir: return "circle.lefthalf.filled"
        case .strobe: return "bolt"
        case .letterbox: return "rectangle.split.1x2"
        case .mirror: return "arrow.left.and.right.square"
        }
    }
    var section: String {
        switch self {
        case .blur, .glow, .vignette, .noir, .letterbox: return L("Look")
        case .shake, .zoomPulse, .strobe: return L("Motion")
        case .glitch, .vhs, .grain, .rgbSplit, .pixelate, .mirror: return L("Retro and glitch")
        }
    }
    var keywords: [String] {
        switch self {
        case .blur: return ["soft", "focus"]
        case .glow: return ["bloom", "dream"]
        case .glitch: return ["error", "digital"]
        case .shake: return ["camera", "earthquake"]
        case .vhs: return ["tape", "retro", "80s"]
        case .zoomPulse: return ["beat", "bounce"]
        case .vignette: return ["dark", "edges"]
        case .grain: return ["noise", "film"]
        case .rgbSplit: return ["chromatic", "aberration"]
        case .pixelate: return ["mosaic", "8-bit"]
        case .noir: return ["mono", "grey"]
        case .strobe: return ["flash", "light"]
        case .letterbox: return ["film", "widescreen"]
        case .mirror: return ["symmetry", "kaleidoscope"]
        }
    }
}

/// An effect on a clip, with its strength.
struct VideoAppliedEffect: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: VideoEffectKind
    var intensity = 0.6
}

enum VideoEffectRenderer {
    /// `image` (its extent is the frame) with `kind` at `intensity` (0…1),
    /// `time` seconds into the effect.
    static func apply(_ kind: VideoEffectKind, to image: CIImage, intensity raw: Double, time: Double) -> CIImage {
        let i = min(max(raw, 0), 1)
        guard i > 0.001 else { return image }
        let extent = image.extent
        guard extent.width.isFinite, extent.width > 1, extent.height > 1 else { return image }
        let scale = extent.height / 1080
        let clamped = image.clampedToExtent()
        func mix(_ effected: CIImage) -> CIImage {
            effected.cropped(to: extent).applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: effected.cropped(to: extent), kCIInputImageKey: image, kCIInputTimeKey: i]).cropped(to: extent)
        }
        switch kind {
        case .blur:
            return clamped.applyingGaussianBlur(sigma: 30 * i * scale).cropped(to: extent)
        case .glow:
            return clamped.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 24 * scale, kCIInputIntensityKey: 1.4 * i]).cropped(to: extent)
        case .vignette:
            return image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 2 * i, kCIInputRadiusKey: 1.6]).cropped(to: extent)
        case .noir:
            return mix(image.applyingFilter("CIPhotoEffectNoir"))
        case .pixelate:
            let size = max(2, 60 * i * scale)
            return clamped.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: size, kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY)]).cropped(to: extent)
        case .rgbSplit:
            return channelSplit(image, by: 14 * i * scale, extent: extent)
        case .shake:
            let amount = 0.025 * i
            let dx = (sin(time * 37) + sin(time * 23 + 1)) / 2 * amount * extent.width
            let dy = (sin(time * 31 + 2) + sin(time * 19)) / 2 * amount * extent.height
            return zoomed(clamped, by: 1 + amount * 2.2, extent: extent).transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: extent)
        case .zoomPulse:
            // Twice a second: a quick push in, eased back.
            let phase = (time * 2).truncatingRemainder(dividingBy: 1)
            let push = phase < 0.15 ? phase / 0.15 : max(0, 1 - (phase - 0.15) / 0.6)
            return zoomed(clamped, by: 1 + 0.12 * i * VideoEasing.easeOut.apply(push), extent: extent).cropped(to: extent)
        case .strobe:
            let on = (time * 6).truncatingRemainder(dividingBy: 1) < 0.25
            return on ? image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.8 * i]).cropped(to: extent) : image
        case .letterbox:
            let bar = extent.height * 0.13 * i
            let black = CIImage(color: .black)
            let top = black.cropped(to: CGRect(x: extent.minX, y: extent.maxY - bar, width: extent.width, height: bar))
            let bottom = black.cropped(to: CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: bar))
            return top.composited(over: bottom.composited(over: image))
        case .mirror:
            let half = image.cropped(to: CGRect(x: extent.minX, y: extent.minY, width: extent.width / 2, height: extent.height))
            let flipped = half.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: extent.minX * 2 + extent.width, ty: 0))
            return mix(flipped.composited(over: half).cropped(to: extent))
        case .grain:
            return grain(image, amount: 0.22 * i, time: time, extent: extent)
        case .glitch:
            // A few frames in every ten: bands pushed sideways and colours split.
            let tick = Int(time * 12)
            let strong = Self.random(tick, 0) < 0.35 + 0.4 * i
            guard strong else { return channelSplit(image, by: 3 * i * scale, extent: extent) }
            var out = image
            let bands = 6
            for b in 0..<bands where Self.random(tick, b + 1) < 0.6 {
                let y = extent.minY + extent.height * Self.random(tick, b + 20)
                let h = extent.height * (0.02 + 0.08 * Self.random(tick, b + 40))
                let shift = (Self.random(tick, b + 60) - 0.5) * extent.width * 0.12 * i
                let band = clamped.cropped(to: CGRect(x: extent.minX, y: y, width: extent.width, height: h)).transformed(by: CGAffineTransform(translationX: shift, y: 0))
                out = band.cropped(to: extent).composited(over: out)
            }
            return channelSplit(out, by: 10 * i * scale, extent: extent)
        case .vhs:
            var out = channelSplit(image, by: 5 * i * scale, extent: extent)
            out = out.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 - 0.3 * i, kCIInputContrastKey: 1 - 0.1 * i])
            out = out.clampedToExtent().applyingGaussianBlur(sigma: 1.2 * i * scale).cropped(to: extent)
            // Scan lines.
            let lines = CIFilter(name: "CIStripesGenerator", parameters: [
                "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0.25 * i), "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
                kCIInputWidthKey: max(1.5 * scale, 1), kCIInputSharpnessKey: 0.5, kCIInputCenterKey: CIVector(x: 0, y: 0),
            ])?.outputImage?.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: extent)
            if let lines { out = lines.composited(over: out) }
            return grain(out, amount: 0.12 * i, time: time, extent: extent)
        }
    }

    static func apply(_ effects: [VideoAppliedEffect], to image: CIImage, time: Double) -> CIImage {
        effects.reduce(image) { apply($1.kind, to: $0, intensity: $1.intensity, time: time) }
    }

    /// Red one way, blue the other.
    private static func channelSplit(_ image: CIImage, by shift: CGFloat, extent: CGRect) -> CIImage {
        guard shift > 0.2 else { return image }
        func only(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
            image.clampedToExtent().applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        }
        let red = only(1, 0, 0).transformed(by: CGAffineTransform(translationX: shift, y: 0))
        let green = only(0, 1, 0)
        let blue = only(0, 0, 1).transformed(by: CGAffineTransform(translationX: -shift, y: 0))
        return red.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blue]).cropped(to: extent)
    }

    private static func zoomed(_ image: CIImage, by factor: CGFloat, extent: CGRect) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY).scaledBy(x: factor, y: factor).concatenating(CGAffineTransform(translationX: extent.midX, y: extent.midY)))
    }

    private static func grain(_ image: CIImage, amount: Double, time: Double, extent: CGRect) -> CIImage {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        let shift = CGFloat(Int(time * 24) % 97) * 13
        let mono = noise.transformed(by: CGAffineTransform(translationX: shift, y: -shift)).cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount)),
            ])
        return mono.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: extent)
    }

    /// The same number for the same tick and slot (0…1): a glitch looks the
    /// same every time it plays and in the export.
    static func random(_ tick: Int, _ slot: Int) -> Double {
        var x = UInt64(bitPattern: Int64(tick &* 7919 &+ slot &* 104_729 &+ 1))
        x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33; x = x &* 0xc4ceb9fe1a85ec53; x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }
}

extension VideoLayerItem {
    /// Not a file: text, an effect or an adjustment clip.
    var hasFile: Bool { text == nil && role == nil && sticker == nil }

    /// An effect clip `length` long at `time`.
    static func effectClip(_ kind: VideoEffectKind, at time: Double, length: Double = 3) -> VideoLayerItem {
        var item = VideoLayerItem(kind: .image, path: "", name: kind.title, at: max(time, 0), length: max(length, minimumLength), aspect: 16.0 / 9)
        item.role = .effect
        item.effects = [VideoAppliedEffect(kind: kind, intensity: 1)]
        item.level = 0.6
        item.width = 1
        return item
    }

    /// What the effect clip does to `scene` at timeline `time` (its
    /// strength keyed with ◆).
    func applyAsLayer(to scene: CIImage, at time: Double) -> CIImage {
        guard enabled else { return scene }
        let strength = value(.intensity, at: time)
        if role == .adjustment {
            var adjusted = scene
            if let adjust { adjusted = VideoAdjustRenderer.apply(adjust, to: adjusted, time: time - at) }
            if let filter { adjusted = VideoFilterRenderer.apply(filter, to: adjusted) }
            guard strength < 0.999 else { return adjusted }
            return adjusted.applyingFilter("CIDissolveTransition", parameters: [kCIInputImageKey: scene, kCIInputTargetImageKey: adjusted, kCIInputTimeKey: max(strength, 0)]).cropped(to: scene.extent)
        }
        guard role == .effect, let effects else { return scene }
        let local = time - at
        return effects.reduce(scene) { VideoEffectRenderer.apply($1.kind, to: $0, intensity: $1.intensity * strength, time: local) }
    }
}

extension VideoEditorModel {
    /// Library ▸ Effects: on the selected clip above the main track (its
    /// own picture), or as an effect clip — over the selected main-track
    /// clip, or at `time` for 3 seconds. One ⌘Z step.
    @discardableResult
    func addEffect(_ kind: VideoEffectKind, at time: Double?, place: LayerPlace = .automatic, onSelection: Bool = true) -> Bool {
        if onSelection, let item = selectedLayerItem, item.role == nil {
            guard let track = project.layerTrackIndex(of: item.id), !refuseLockedLayer(track) else { return false }
            setLayerItem(item.id, label: "Add Effect") { $0.effects = ($0.effects ?? []) + [VideoAppliedEffect(kind: kind)] }
            showNotice(L("\(kind.title) on “\(item.name)”"), symbol: kind.symbol)
            return true
        }
        var start = time ?? clock.time
        var length = 3.0
        if onSelection, time == nil, case .clip(let id) = selection, let segment = segments.first(where: { $0.id == id }) {
            start = segment.timelineStart
            length = segment.timelineEnd - segment.timelineStart
        }
        let item = VideoLayerItem.effectClip(kind, at: start, length: length)
        mutate(label: "Add Effect") { project in project.insertLayerItem(item, place: place) }
        selection = .layer(item.id)
        return true
    }
}

// MARK: - Properties

/// An effect clip's effect and strength.
struct VideoEffectClipSection: View {
    @ObservedObject var model: VideoEditorModel
    let editor: VideoLayerItemEditor
    let item: VideoLayerItem

    var body: some View {
        VideoInspectorSection(L("Effect")) {
            Picker(L("Effect"), selection: Binding(get: { item.effects?.first?.kind ?? .blur }, set: { kind in
                model.selection = .layer(item.id)
                var effects = item.effects ?? []
                if effects.isEmpty { effects = [VideoAppliedEffect(kind: kind, intensity: 1)] } else { effects[0].kind = kind }
                model.perform(.edit(.setEffects(effects)))
                model.endGesture()
            })) {
                ForEach(VideoEffectKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            editor.keyed(L("Strength"), .intensity, range: 0...100, scale: 100, defaultValue: 60, format: VideoLayerItemEditor.percent)
            VideoToggleRow(title: L("Show"), detail: L("Off, it stays on the timeline but does nothing (V)"),
                           isOn: Binding(get: { item.enabled }, set: { on in model.setLayerItem(item.id, label: on ? "Turn On Clip" : "Turn Off Clip") { $0.enabled = on } }))
            Text(L("Changes the main track and the tracks under this one while it plays. Drag its ends on the timeline to make it longer or shorter."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Effects on a video, picture or text clip.
struct VideoItemEffectsSection: View {
    @ObservedObject var model: VideoEditorModel
    let item: VideoLayerItem

    var body: some View {
        VideoInspectorSection(L("Effects")) {
            let effects = item.effects ?? []
            if effects.isEmpty {
                Text(L("Pick one in Library ▸ Effects while this clip is selected."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(effects) { effect in
                HStack(alignment: .top, spacing: 6) {
                    VideoSliderRow(title: effect.kind.title, value: Binding(get: { effect.intensity * 100 }, set: { value in
                        change { list in if let i = list.firstIndex(where: { $0.id == effect.id }) { list[i].intensity = value / 100 } }
                    }), range: 0...100, defaultValue: 60, format: VideoLayerItemEditor.percent, onEditingEnded: { model.endGesture() })
                    Button {
                        change { $0.removeAll { $0.id == effect.id } }
                        model.endGesture()
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .help(L("Take this effect off"))
                    .accessibilityLabel(L("Take \(effect.kind.title) off"))
                    .padding(.top, 2)
                }
            }
        }
    }

    private func change(_ edit: (inout [VideoAppliedEffect]) -> Void) {
        var effects = item.effects ?? []
        edit(&effects)
        model.selection = .layer(item.id)
        model.perform(.edit(.setEffects(effects)))
    }
}

// MARK: - Library ▸ Effects

struct VideoEffectsLibraryTab: View {
    @ObservedObject var model: VideoEditorModel

    private var tiles: [VideoLibraryTile] {
        VideoEffectKind.allCases.map { VideoLibraryTile(payload: .init(kind: "effect", id: $0.rawValue), title: $0.title, keywords: $0.keywords, section: $0.section) }
    }

    var body: some View {
        VideoLibraryGrid(model: model, tiles: tiles, minimum: 84, tileHeight: 56) {
            Text(model.selectedLayerItem.map { $0.role == nil ? L("Click + to put an effect on “\($0.name)”, or drag it onto the timeline for an effect clip.") : L("Click + for an effect clip at the playhead, or drag one onto the timeline.") }
                 ?? L("Click + for an effect clip at the playhead (over the selected clip), or drag one onto the timeline."))
                .font(.system(size: 11))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } preview: { tile, hovering in
            if let kind = VideoEffectKind(rawValue: tile.payload.id) {
                VideoEffectPreview(kind: kind, hovering: hovering)
            }
        }
    }
}

/// An effect on our own sample picture (drawn here); hovering plays it.
struct VideoEffectPreview: View {
    let kind: VideoEffectKind
    let hovering: Bool
    private static let context = CIContext(options: [.cacheIntermediates: false])

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15)) { timeline in
            let time = hovering ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) : 0.4
            if let image = Self.render(kind, time: time) {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
            }
        }
    }

    /// A sunset over hills: shapes and colours that show every effect.
    static let sample: CIImage = {
        let size = CGRect(x: 0, y: 0, width: 192, height: 112)
        let sky = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 112), "inputPoint1": CIVector(x: 0, y: 30),
            "inputColor0": CIColor(red: 0.25, green: 0.3, blue: 0.7), "inputColor1": CIColor(red: 1, green: 0.6, blue: 0.35),
        ])!.outputImage!.cropped(to: size)
        let sun = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 120, y: 50), "inputRadius0": 16, "inputRadius1": 18,
            "inputColor0": CIColor(red: 1, green: 0.95, blue: 0.6), "inputColor1": CIColor(red: 1, green: 0.95, blue: 0.6, alpha: 0),
        ])!.outputImage!.cropped(to: size)
        let hill = CIImage(color: CIColor(red: 0.1, green: 0.25, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 192, height: 34))
        let hill2 = CIImage(color: CIColor(red: 0.15, green: 0.35, blue: 0.25)).cropped(to: CGRect(x: 0, y: 0, width: 80, height: 46))
        return hill2.composited(over: hill.composited(over: sun.composited(over: sky)))
    }()

    static func render(_ kind: VideoEffectKind, time: Double) -> CGImage? {
        let out = VideoEffectRenderer.apply(kind, to: sample, intensity: 0.8, time: time)
        return context.createCGImage(out, from: sample.extent)
    }
}
