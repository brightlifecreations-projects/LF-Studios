import AppKit
import CoreImage
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library ▸ Filters (1.15.0)

/// Our own looks, each a colour formula baked into a 3D LUT.
enum VideoFilterLook: String, Codable, CaseIterable, Identifiable {
    case warm, cool, vivid, muted, film, tealOrange, mono, noir, sepia, vintage, cinematic, pastel, night, golden, matte, crossProcess

    var id: String { rawValue }
    var title: String {
        switch self {
        case .warm: return L("Warm")
        case .cool: return L("Cool")
        case .vivid: return L("Vivid")
        case .muted: return L("Muted")
        case .film: return L("Film")
        case .tealOrange: return L("Teal & orange")
        case .mono: return L("Mono")
        case .noir: return L("Noir")
        case .sepia: return L("Sepia")
        case .vintage: return L("Vintage")
        case .cinematic: return L("Cinematic")
        case .pastel: return L("Pastel")
        case .night: return L("Night")
        case .golden: return L("Golden hour")
        case .matte: return L("Matte")
        case .crossProcess: return L("Cross process")
        }
    }
    var section: String {
        switch self {
        case .warm, .cool, .vivid, .muted, .pastel, .golden: return L("Colour")
        case .film, .tealOrange, .cinematic, .matte, .night, .crossProcess: return L("Cinema")
        case .mono, .noir, .sepia, .vintage: return L("Classic")
        }
    }

    /// The look on one colour (sRGB, 0…1).
    func transform(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        func sat(_ s: Double) -> (Double, Double, Double) { (luma + (r - luma) * s, luma + (g - luma) * s, luma + (b - luma) * s) }
        func curve(_ x: Double, contrast c: Double) -> Double { 0.5 + (x - 0.5) * c }
        func lift(_ x: Double, _ black: Double) -> Double { black + x * (1 - black) }
        switch self {
        case .warm: return (r * 1.06 + 0.02, g * 1.01, b * 0.9)
        case .cool: return (r * 0.92, g * 1.0, b * 1.08 + 0.02)
        case .vivid:
            let (sr, sg, sb) = sat(1.35)
            return (curve(sr, contrast: 1.1), curve(sg, contrast: 1.1), curve(sb, contrast: 1.1))
        case .muted: return sat(0.6)
        case .film:
            let (sr, sg, sb) = sat(0.85)
            return (lift(sr * 1.03, 0.06), lift(sg, 0.05), lift(sb * 0.95, 0.07))
        case .tealOrange:
            // Shadows toward teal, highlights toward orange.
            let t = luma
            return (r + (t - 0.5) * 0.18, g + (t - 0.5) * 0.04, b - (t - 0.5) * 0.22)
        case .mono: return (luma, luma, luma)
        case .noir:
            let x = curve(luma, contrast: 1.45)
            return (x, x, x)
        case .sepia: return (luma * 1.07 + 0.05, luma * 0.88 + 0.03, luma * 0.68)
        case .vintage:
            let (sr, sg, sb) = sat(0.7)
            return (lift(sr * 1.05, 0.08), lift(sg * 0.98, 0.06), lift(sb * 0.85, 0.1))
        case .cinematic:
            let (sr, sg, sb) = sat(0.9)
            return (curve(sr, contrast: 1.15) + (luma - 0.5) * 0.08, curve(sg, contrast: 1.15), curve(sb, contrast: 1.15) - (luma - 0.5) * 0.12 + 0.02)
        case .pastel:
            let (sr, sg, sb) = sat(0.75)
            return (lift(sr, 0.12), lift(sg, 0.12), lift(sb, 0.14))
        case .night:
            let x = luma * 0.75
            return (x * 0.7, x * 0.9, x * 1.25 + 0.03)
        case .golden: return (r * 1.08 + 0.04, g * 1.02 + 0.02, b * 0.82)
        case .matte:
            return (lift(curve(r, contrast: 0.9), 0.08), lift(curve(g, contrast: 0.9), 0.08), lift(curve(b, contrast: 0.9), 0.08))
        case .crossProcess:
            return (curve(r, contrast: 1.2) + 0.03, curve(g, contrast: 1.1) + 0.02, b * 0.75 + 0.12)
        }
    }
}

/// A filter on a clip, or on an adjustment clip: one of our looks or an
/// imported .cube file, at a strength.
struct VideoAppliedFilter: Codable, Equatable {
    var look: VideoFilterLook?
    /// An imported .cube LUT (copied next to the project's pictures).
    var cubePath: String?
    var cubeName: String?
    var intensity = 0.8

    var title: String { look?.title ?? cubeName ?? L("LUT") }
}

/// A 3D LUT ready for CIColorCube.
struct VideoColorCube {
    let size: Int
    let data: Data

    /// Bakes `transform` into a size³ cube.
    static func bake(size: Int = 32, _ transform: (Double, Double, Double) -> (Double, Double, Double)) -> VideoColorCube {
        var floats = [Float](repeating: 0, count: size * size * size * 4)
        var i = 0
        let step = 1 / Double(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let out = transform(Double(r) * step, Double(g) * step, Double(b) * step)
                    floats[i] = Float(min(max(out.0, 0), 1))
                    floats[i + 1] = Float(min(max(out.1, 0), 1))
                    floats[i + 2] = Float(min(max(out.2, 0), 1))
                    floats[i + 3] = 1
                    i += 4
                }
            }
        }
        return VideoColorCube(size: size, data: floats.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    /// A .cube file (Adobe/Resolve 3D LUT): LUT_3D_SIZE, then size³ lines of
    /// "r g b", red changing fastest. nil when it isn't one.
    static func parse(_ text: String) -> VideoColorCube? {
        var size = 0
        var values: [Float] = []
        var domainMin: [Float] = [0, 0, 0], domainMax: [Float] = [1, 1, 1]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("TITLE") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.first == "LUT_3D_SIZE", parts.count > 1 { size = Int(parts[1]) ?? 0; continue }
            if parts.first == "LUT_1D_SIZE" { return nil }
            if parts.first == "DOMAIN_MIN", parts.count > 3 { domainMin = parts[1...3].compactMap { Float($0) }; continue }
            if parts.first == "DOMAIN_MAX", parts.count > 3 { domainMax = parts[1...3].compactMap { Float($0) }; continue }
            let numbers = parts.compactMap { Float($0) }
            guard numbers.count == 3 else { continue }
            values.append(contentsOf: numbers)
        }
        guard (2...128).contains(size), values.count == size * size * size * 3, domainMin.count == 3, domainMax.count == 3 else { return nil }
        var floats = [Float](repeating: 1, count: size * size * size * 4)
        for n in 0..<(size * size * size) {
            for c in 0..<3 {
                let span = max(domainMax[c] - domainMin[c], 0.000_1)
                floats[n * 4 + c] = min(max((values[n * 3 + c] - domainMin[c]) / span, 0), 1)
            }
        }
        return VideoColorCube(size: size, data: floats.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    func apply(to image: CIImage) -> CIImage {
        image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": size, "inputCubeData": data, "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!,
        ])
    }
}

enum VideoFilterRenderer {
    private static let lock = NSLock()
    private static var cubes: [String: VideoColorCube] = [:]

    static func cube(for filter: VideoAppliedFilter) -> VideoColorCube? {
        let key = filter.look?.rawValue ?? ("cube:" + (filter.cubePath ?? ""))
        lock.lock()
        if let cached = cubes[key] { lock.unlock(); return cached }
        lock.unlock()
        let made: VideoColorCube?
        if let look = filter.look {
            made = VideoColorCube.bake(look.transform)
        } else if let path = filter.cubePath, let text = try? String(contentsOfFile: path, encoding: .utf8) {
            made = VideoColorCube.parse(text)
        } else {
            made = nil
        }
        if let made {
            lock.lock()
            cubes[key] = made
            lock.unlock()
        }
        return made
    }

    /// `image` with the filter, mixed with the original by its strength.
    static func apply(_ filter: VideoAppliedFilter, to image: CIImage, strength: Double = 1) -> CIImage {
        let amount = min(max(filter.intensity * strength, 0), 1)
        guard amount > 0.001, let cube = cube(for: filter) else { return image }
        let extent = image.extent
        let looked = cube.apply(to: image)
        guard amount < 0.999 else { return looked.cropped(to: extent) }
        return looked.applyingFilter("CIDissolveTransition", parameters: [kCIInputImageKey: image, kCIInputTargetImageKey: looked, kCIInputTimeKey: amount]).cropped(to: extent)
    }
}

extension VideoEditorModel {
    /// Library ▸ Filters: on the selected clip above the main track, or as
    /// an adjustment clip with just this filter (over the selected main
    /// clip, or 3 s at `time`). One ⌘Z step.
    @discardableResult
    func addFilter(_ filter: VideoAppliedFilter, at time: Double?, place: LayerPlace = .automatic, onSelection: Bool = true) -> Bool {
        if onSelection, let item = selectedLayerItem, item.role != .effect {
            guard let track = project.layerTrackIndex(of: item.id), !refuseLockedLayer(track) else { return false }
            setLayerItem(item.id, label: "Filter") { $0.filter = filter }
            showNotice(L("\(filter.title) on “\(item.name)”"), symbol: "camera.filters")
            return true
        }
        var start = time ?? clock.time
        var length = 3.0
        if onSelection, time == nil, case .clip(let id) = selection, let segment = segments.first(where: { $0.id == id }) {
            start = segment.timelineStart
            length = segment.timelineEnd - segment.timelineStart
        }
        var item = VideoLayerItem.adjustmentClip(at: start, length: length)
        item.filter = filter
        item.name = filter.title
        mutate(label: "Add Filter") { project in project.insertLayerItem(item, place: place) }
        selection = .layer(item.id)
        return true
    }
}

extension VideoLayerItem {
    /// An adjustment clip (B12): the Adjust settings and a filter on
    /// everything under it while it plays.
    static func adjustmentClip(at time: Double, length: Double = 3) -> VideoLayerItem {
        var item = VideoLayerItem(kind: .image, path: "", name: L("Adjustment"), at: max(time, 0), length: max(length, minimumLength), aspect: 16.0 / 9)
        item.role = .adjustment
        item.width = 1
        return item
    }
}

// MARK: - Properties ▸ Filter

struct VideoFilterSection: View {
    @ObservedObject var model: VideoEditorModel
    let item: VideoLayerItem

    var body: some View {
        VideoInspectorSection(L("Filter")) {
            HStack(spacing: 8) {
                Menu {
                    Button(L("None")) { set(nil) }
                    ForEach(VideoFilterLook.allCases) { look in
                        Button(look.title) { set(VideoAppliedFilter(look: look, intensity: item.filter?.intensity ?? 0.8)) }
                    }
                } label: {
                    Text(item.filter?.title ?? L("None")).frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                Button(L("Import .cube…")) { model.importCubeLUT(for: item.id) }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .help(L("A 3D LUT from another app (.cube)"))
            }
            if let filter = item.filter {
                VideoSliderRow(title: L("Strength"), value: Binding(get: { filter.intensity * 100 }, set: { value in
                    var next = filter
                    next.intensity = value / 100
                    set(next, coalesce: true)
                }), range: 0...100, defaultValue: 80, format: VideoLayerItemEditor.percent, onEditingEnded: { model.endGesture() })
            }
        }
    }

    private func set(_ filter: VideoAppliedFilter?, coalesce: Bool = false) {
        model.selection = .layer(item.id)
        model.perform(.edit(.setFilter(filter)))
        if !coalesce { model.endGesture() }
    }
}

// MARK: - Library ▸ Filters

struct VideoFiltersLibraryTab: View {
    @ObservedObject var model: VideoEditorModel

    private var tiles: [VideoLibraryTile] {
        VideoFilterLook.allCases.map { VideoLibraryTile(payload: .init(kind: "filter", id: $0.rawValue), title: $0.title, section: $0.section) }
    }

    var body: some View {
        VideoLibraryGrid(model: model, tiles: tiles, minimum: 76, tileHeight: 50) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.selectedLayerItem.map { $0.role != .effect ? L("Click + to put a filter on “\($0.name)”, or drag one onto the timeline for a filter clip.") : L("Click + for a filter clip at the playhead.") }
                     ?? L("Click + for a filter clip at the playhead (over the selected clip), or drag one onto the timeline."))
                    .font(.system(size: 11))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.importCubeLUT(for: nil)
                } label: {
                    Label(L("Import .cube LUT…"), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("A 3D LUT from another app: on the selected clip, or as a filter clip"))
            }
        } preview: { tile, hovering in
            if let look = VideoFilterLook(rawValue: tile.payload.id) {
                VideoFilterPreview(look: look, hovering: hovering)
            }
        }
    }
}

/// Our sample picture with the look; hovering shows before | after.
struct VideoFilterPreview: View {
    let look: VideoFilterLook
    let hovering: Bool
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static var cache: [String: CGImage] = [:]

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                if let image = Self.render(look) {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                }
                if hovering, let plain = Self.plain {
                    Image(decorative: plain, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: box.size.width, height: box.size.height)
                        .mask(alignment: .leading) { Rectangle().frame(width: box.size.width / 2) }
                    Rectangle().fill(Color.white).frame(width: 1).offset(x: box.size.width / 2)
                }
            }
            .frame(width: box.size.width, height: box.size.height)
            .clipped()
        }
    }

    static let plain: CGImage? = context.createCGImage(VideoEffectPreview.sample, from: VideoEffectPreview.sample.extent)

    @MainActor
    static func render(_ look: VideoFilterLook) -> CGImage? {
        if let cached = cache[look.rawValue] { return cached }
        let out = VideoFilterRenderer.apply(VideoAppliedFilter(look: look, intensity: 1), to: VideoEffectPreview.sample)
        let image = context.createCGImage(out, from: VideoEffectPreview.sample.extent)
        cache[look.rawValue] = image
        return image
    }
}

extension VideoEditorModel {
    /// Import .cube…: a 3D LUT from another app, copied next to the
    /// project's pictures, on clip `id` (nil: the selected clip, or a new
    /// filter clip).
    func importCubeLUT(for id: UUID?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cube") ?? .data]
        panel.allowsOtherFileTypes = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importCubeLUT(url, for: id)
    }

    @discardableResult
    func importCubeLUT(_ url: URL, for id: UUID?) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8), VideoColorCube.parse(text) != nil else {
            showNotice(L("That isn't a 3D LUT LF Studios can read (.cube with LUT_3D_SIZE)"), symbol: "exclamationmark.triangle.fill")
            return false
        }
        guard let stored = try? VideoAssetStore.importFile(url) else { return false }
        let filter = VideoAppliedFilter(cubePath: stored.path, cubeName: url.deletingPathExtension().lastPathComponent, intensity: 1)
        if let id { selection = .layer(id) }
        return addFilter(filter, at: nil)
    }
}

/// An adjustment clip: its strength and filter (B12 adds the Adjust panel).
struct VideoAdjustmentClipSection: View {
    @ObservedObject var model: VideoEditorModel
    let editor: VideoLayerItemEditor
    let item: VideoLayerItem

    var body: some View {
        VideoInspectorSection(L("Adjustment")) {
            editor.keyed(L("Strength"), .intensity, range: 0...100, scale: 100, defaultValue: 100, format: VideoLayerItemEditor.percent)
            VideoToggleRow(title: L("Show"), detail: L("Off, it stays on the timeline but does nothing (V)"),
                           isOn: Binding(get: { item.enabled }, set: { on in model.setLayerItem(item.id, label: on ? "Turn On Clip" : "Turn Off Clip") { $0.enabled = on } }))
            Text(L("Changes the main track and the tracks under this one while it plays."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        VideoAdjustSection(model: model, item: item)
        VideoFilterSection(model: model, item: item)
    }
}
