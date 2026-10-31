import CoreImage
import SwiftUI

// MARK: - Properties ▸ Adjust (1.15.0)

struct VideoAdjustSection: View {
    @ObservedObject var model: VideoEditorModel
    let item: VideoLayerItem
    @State private var page = Page.basic
    @State private var hslColor = VideoHSLColor.red
    @State private var curveChannel = CurveChannel.rgb

    enum Page: String, CaseIterable { case basic, hsl, curves, wheels }
    enum CurveChannel: String, CaseIterable { case rgb, red, green, blue }

    private var settings: VideoAdjustSettings { item.adjust ?? VideoAdjustSettings() }

    var body: some View {
        VideoInspectorSection(L("Adjust")) {
            VideoSegmented(options: [(Page.basic, L("Basic")), (.hsl, L("HSL")), (.curves, L("Curves")), (.wheels, L("Wheels"))], selection: $page)
            switch page {
            case .basic: basic
            case .hsl: hsl
            case .curves: curves
            case .wheels: wheels
            }
            if item.adjust != nil {
                Button {
                    set(nil)
                    model.endGesture()
                } label: {
                    Label(L("Reset Adjust"), systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
            }
        }
    }

    // MARK: Basic

    @ViewBuilder private var basic: some View {
        slider(L("Exposure"), \.exposure)
        slider(L("Contrast"), \.contrast)
        slider(L("Highlights"), \.highlights)
        slider(L("Shadows"), \.shadows)
        slider(L("Whites"), \.whites)
        slider(L("Blacks"), \.blacks)
        slider(L("Saturation"), \.saturation)
        slider(L("Vibrance"), \.vibrance)
        slider(L("Temperature"), \.temperature)
        slider(L("Tint"), \.tint)
        slider(L("Sharpen"), \.sharpen, range: 0...100)
        slider(L("Vignette"), \.vignette, range: 0...100)
        slider(L("Grain"), \.grain, range: 0...100)
        slider(L("Fade"), \.fade, range: 0...100)
    }

    private func slider(_ title: String, _ key: WritableKeyPath<VideoAdjustSettings, Double>, range: ClosedRange<Double> = -100...100) -> some View {
        VideoSliderRow(title: title, value: Binding(get: { settings[keyPath: key] * 100 }, set: { value in
            var next = settings
            next[keyPath: key] = value.rounded() / 100
            set(next)
        }), range: range, defaultValue: 0, format: { "\(Int($0.rounded()))" }, onEditingEnded: { model.endGesture() }) // l10n-ignore: a number
    }

    // MARK: HSL

    @ViewBuilder private var hsl: some View {
        HStack(spacing: 6) {
            ForEach(VideoHSLColor.allCases) { colour in
                Button { hslColor = colour } label: {
                    Circle()
                        .fill(Color(hue: colour.hue / 360, saturation: 0.85, brightness: 0.95))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: hslColor == colour ? 2 : 0))
                        .overlay(alignment: .bottomTrailing) {
                            if !(settings.hsl?[colour.rawValue]?.isNeutral ?? true) {
                                Circle().fill(Color.white).frame(width: 5, height: 5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(colour.title)
                .accessibilityLabel(colour.title)
                .accessibilityAddTraits(hslColor == colour ? .isSelected : [])
            }
        }
        hslSlider(L("Hue"), \.hue)
        hslSlider(L("Saturation"), \.saturation)
        hslSlider(L("Luminance"), \.luminance)
    }

    private func hslSlider(_ title: String, _ key: WritableKeyPath<VideoAdjustSettings.HSL, Double>) -> some View {
        let current = settings.hsl?[hslColor.rawValue] ?? .init()
        return VideoSliderRow(title: title, value: Binding(get: { current[keyPath: key] * 100 }, set: { value in
            var next = settings
            var change = next.hsl?[hslColor.rawValue] ?? .init()
            change[keyPath: key] = value.rounded() / 100
            var all = next.hsl ?? [:]
            all[hslColor.rawValue] = change.isNeutral ? nil : change
            next.hsl = all.isEmpty ? nil : all
            set(next)
        }), range: -100...100, defaultValue: 0, format: { "\(Int($0.rounded()))" }, onEditingEnded: { model.endGesture() }) // l10n-ignore: a number
    }

    // MARK: Curves

    @ViewBuilder private var curves: some View {
        VideoSegmented(options: [(CurveChannel.rgb, L("RGB")), (.red, L("Red")), (.green, L("Green")), (.blue, L("Blue"))], selection: $curveChannel)
        VideoCurveEditor(points: points(curveChannel), tint: tint(curveChannel)) { next in
            var all = settings.curves ?? .init()
            switch curveChannel {
            case .rgb: all.rgb = next
            case .red: all.red = next
            case .green: all.green = next
            case .blue: all.blue = next
            }
            var adjusted = settings
            adjusted.curves = all.isNeutral ? nil : all
            set(adjusted)
        } ended: {
            model.endGesture()
        }
        .frame(height: 170)
        Text(L("Click to add a point, drag to move it, double-click to take it away."))
            .font(.system(size: 10.5))
            .foregroundStyle(VideoEditorTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func points(_ channel: CurveChannel) -> [VideoCurvePoint] {
        let c = settings.curves ?? .init()
        switch channel {
        case .rgb: return c.rgb
        case .red: return c.red
        case .green: return c.green
        case .blue: return c.blue
        }
    }

    private func tint(_ channel: CurveChannel) -> Color {
        switch channel {
        case .rgb: return .white
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        }
    }

    // MARK: Wheels

    @ViewBuilder private var wheels: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            wheel(L("Shadows (lift)"), \.lift)
            wheel(L("Midtones (gamma)"), \.gamma)
            wheel(L("Highlights (gain)"), \.gain)
            wheel(L("Everything (offset)"), \.offset)
        }
    }

    private func wheel(_ title: String, _ key: WritableKeyPath<VideoAdjustSettings.Wheels, VideoAdjustSettings.Wheel>) -> some View {
        let current = (settings.wheels ?? .init())[keyPath: key]
        return VideoColorWheel(title: title, wheel: current) { next in
            var all = settings.wheels ?? .init()
            all[keyPath: key] = next
            var adjusted = settings
            adjusted.wheels = all.isNeutral ? nil : all
            set(adjusted)
        } ended: {
            model.endGesture()
        }
    }

    private func set(_ next: VideoAdjustSettings?) {
        model.selection = .layer(item.id)
        model.perform(.edit(.setAdjust(next.flatMap { $0.isNeutral ? nil : $0 })))
    }
}

/// A curve: points to drag on a square, the curve through them.
struct VideoCurveEditor: View {
    let points: [VideoCurvePoint]
    let tint: Color
    let changed: ([VideoCurvePoint]) -> Void
    let ended: () -> Void
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { box in
            let size = box.size
            let spot = { (p: VideoCurvePoint) -> CGPoint in CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(VideoEditorTheme.well)
                Path { path in
                    for i in 1..<4 {
                        let f = CGFloat(i) / 4
                        path.move(to: CGPoint(x: f * size.width, y: 0)); path.addLine(to: CGPoint(x: f * size.width, y: size.height))
                        path.move(to: CGPoint(x: 0, y: f * size.height)); path.addLine(to: CGPoint(x: size.width, y: f * size.height))
                    }
                }
                .stroke(VideoEditorTheme.hairline, lineWidth: 1)
                Path { path in
                    for step in 0...64 {
                        let x = Double(step) / 64
                        let point = CGPoint(x: x * size.width, y: (1 - min(max(VideoCurve.value(points, at: x), 0), 1)) * size.height)
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(tint, lineWidth: 1.5)
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(tint, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .position(spot(point))
                        .onTapGesture(count: 2) {
                            // The two ends stay.
                            guard index > 0, index < points.count - 1 else { return }
                            var next = points
                            next.remove(at: index)
                            changed(next)
                            ended()
                        }
                        .accessibilityLabel(L("Curve point"))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let x = min(max(value.location.x / max(size.width, 1), 0), 1)
                let y = min(max(1 - value.location.y / max(size.height, 1), 0), 1)
                var next = points
                if dragging == nil {
                    // Grab the nearest point, or add one.
                    let start = value.startLocation
                    if let near = points.indices.min(by: { hypot(spot(points[$0]).x - start.x, spot(points[$0]).y - start.y) < hypot(spot(points[$1]).x - start.x, spot(points[$1]).y - start.y) }),
                       hypot(spot(points[near]).x - start.x, spot(points[near]).y - start.y) < 12 {
                        dragging = near
                    } else if points.count < 12 {
                        next.append(VideoCurvePoint(x: x, y: y))
                        next.sort { $0.x < $1.x }
                        dragging = next.firstIndex(of: VideoCurvePoint(x: x, y: y))
                    }
                }
                guard let index = dragging, next.indices.contains(index) else { return }
                // Ends stay at the edges; the rest keep their order.
                let lo = index == 0 ? 0 : next[index - 1].x + 0.01
                let hi = index == next.count - 1 ? 1 : next[index + 1].x - 0.01
                next[index] = VideoCurvePoint(x: index == 0 ? 0 : index == next.count - 1 ? 1 : min(max(x, lo), hi), y: y)
                changed(next)
            }.onEnded { _ in
                dragging = nil
                ended()
            })
        }
    }
}

/// A colour wheel: drag the dot toward a colour; the slider under it is
/// brightness. Double-click the wheel to reset.
struct VideoColorWheel: View {
    let title: String
    let wheel: VideoAdjustSettings.Wheel
    let changed: (VideoAdjustSettings.Wheel) -> Void
    let ended: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { box in
                let side = min(box.size.width, box.size.height)
                let radius = side / 2
                ZStack {
                    Circle()
                        .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center, angle: .degrees(0)))
                        .overlay(Circle().fill(RadialGradient(colors: [Color(white: 0.5), Color(white: 0.5).opacity(0)], center: .center, startRadius: 0, endRadius: radius)))
                        .scaleEffect(x: 1, y: -1)
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                        .frame(width: 9, height: 9)
                        .offset(x: wheel.x * radius, y: -wheel.y * radius)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity)
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let cx = box.size.width / 2, cy = side / 2
                    var x = (value.location.x - cx) / radius, y = -(value.location.y - cy) / radius
                    let length = sqrt(x * x + y * y)
                    if length > 1 { x /= length; y /= length }
                    var next = wheel
                    next.x = Double(x)
                    next.y = Double(y)
                    changed(next)
                }.onEnded { _ in ended() })
                .onTapGesture(count: 2) {
                    var next = wheel
                    next.x = 0
                    next.y = 0
                    changed(next)
                    ended()
                }
            }
            .frame(height: 74)
            Slider(value: Binding(get: { wheel.luminance }, set: { value in
                var next = wheel
                next.luminance = (value * 100).rounded() / 100
                changed(next)
            }), in: -1...1) { editing in if !editing { ended() } }
            .controlSize(.mini)
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(VideoEditorTheme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Library ▸ Adjustment

/// Ready-made adjustments (our own settings).
struct VideoAdjustPreset: Identifiable {
    var id: String
    var title: String
    var settings: VideoAdjustSettings

    static var all: [VideoAdjustPreset] {
        func make(_ id: String, _ title: String, _ change: (inout VideoAdjustSettings) -> Void) -> VideoAdjustPreset {
            var s = VideoAdjustSettings()
            change(&s)
            return VideoAdjustPreset(id: id, title: title, settings: s)
        }
        return [
            VideoAdjustPreset(id: "blank", title: L("Adjustment clip"), settings: VideoAdjustSettings()),
            make("brighten", L("Brighten")) { $0.exposure = 0.25; $0.shadows = 0.3 },
            make("punchy", L("Punchy")) { $0.contrast = 0.35; $0.vibrance = 0.4; $0.sharpen = 0.3 },
            make("warm-up", L("Warm up")) { $0.temperature = 0.45; $0.vibrance = 0.15 },
            make("cool-down", L("Cool down")) { $0.temperature = -0.45; $0.tint = -0.1 },
            make("soft", L("Soft")) { $0.contrast = -0.25; $0.highlights = -0.3; $0.fade = 0.25 },
            make("crisp", L("Crisp")) { $0.sharpen = 0.6; $0.contrast = 0.15; $0.whites = 0.2 },
            make("moody", L("Moody")) { $0.exposure = -0.15; $0.contrast = 0.25; $0.saturation = -0.3; $0.vignette = 0.5 },
            make("teal-shadows", L("Teal shadows")) { var w = VideoAdjustSettings.Wheels(); w.lift = .init(x: -0.4, y: -0.25, luminance: 0); w.gain = .init(x: 0.25, y: 0.2, luminance: 0); $0.wheels = w },
            make("lifted", L("Lifted blacks")) { $0.curves = .init(rgb: [VideoCurvePoint(x: 0, y: 0.08), VideoCurvePoint(x: 0.5, y: 0.52), VideoCurvePoint(x: 1, y: 0.97)]) },
        ]
    }
}

extension VideoEditorModel {
    /// Library ▸ Adjustment: an adjustment clip with `preset` (over the
    /// selected main clip, or 3 s at `time`), or the preset on the selected
    /// clip above the main track. One ⌘Z step.
    @discardableResult
    func addAdjustment(_ preset: VideoAdjustPreset, at time: Double?, place: LayerPlace = .automatic, onSelection: Bool = true) -> Bool {
        if onSelection, preset.id != "blank", let item = selectedLayerItem, item.role != .effect {
            guard let track = project.layerTrackIndex(of: item.id), !refuseLockedLayer(track) else { return false }
            setLayerItem(item.id, label: "Adjust") { $0.adjust = preset.settings }
            showNotice(L("\(preset.title) on “\(item.name)”"), symbol: "slider.horizontal.3")
            return true
        }
        var start = time ?? clock.time
        var length = 3.0
        if onSelection, time == nil, case .clip(let id) = selection, let segment = segments.first(where: { $0.id == id }) {
            start = segment.timelineStart
            length = segment.timelineEnd - segment.timelineStart
        }
        var item = VideoLayerItem.adjustmentClip(at: start, length: length)
        if preset.id != "blank" {
            item.adjust = preset.settings
            item.name = preset.title
        }
        mutate(label: "Add Adjustment") { project in project.insertLayerItem(item, place: place) }
        selection = .layer(item.id)
        return true
    }
}

struct VideoAdjustmentLibraryTab: View {
    @ObservedObject var model: VideoEditorModel

    private var tiles: [VideoLibraryTile] {
        VideoAdjustPreset.all.map {
            VideoLibraryTile(payload: .init(kind: "adjustment", id: $0.id), title: $0.title, section: $0.id == "blank" ? L("Adjustment clip") : L("Ready-made"))
        }
    }

    var body: some View {
        VideoLibraryGrid(model: model, tiles: tiles, minimum: 84, tileHeight: 50) {
            Text(L("An adjustment clip changes everything under it while it plays: set it up in Properties ▸ Adjust (exposure, HSL, curves, colour wheels) and Filter."))
                .font(.system(size: 11))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } preview: { tile, hovering in
            if let preset = VideoAdjustPreset.all.first(where: { $0.id == tile.payload.id }) {
                VideoAdjustPreview(preset: preset, hovering: hovering)
            }
        }
    }
}

struct VideoAdjustPreview: View {
    let preset: VideoAdjustPreset
    let hovering: Bool
    private static let context = CIContext(options: [.cacheIntermediates: false])

    var body: some View {
        GeometryReader { box in
            ZStack {
                if preset.id == "blank" {
                    LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                } else if let image = Self.render(preset) {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    if hovering, let plain = VideoFilterPreview.plain {
                        Image(decorative: plain, scale: 1).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: box.size.width, height: box.size.height)
                            .mask(alignment: .leading) { Rectangle().frame(width: box.size.width / 2) }
                        Rectangle().fill(Color.white).frame(width: 1).offset(x: 0)
                    }
                }
            }
            .frame(width: box.size.width, height: box.size.height)
            .clipped()
        }
    }

    static func render(_ preset: VideoAdjustPreset) -> CGImage? {
        let out = VideoAdjustRenderer.apply(preset.settings, to: VideoEffectPreview.sample, time: 0)
        return context.createCGImage(out, from: VideoEffectPreview.sample.extent)
    }
}
