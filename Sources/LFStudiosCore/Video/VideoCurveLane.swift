import SwiftUI

// MARK: - Keyframe curve lane (1.17.0, LF Studios layout)

/// Under a track above the main track: one setting's value over time for
/// each clip on it, with its keyframes as points. A point is dragged up or
/// down (the value) and sideways (the time): one ⌘Z step a drag. It draws
/// and changes the clips' own keyframes, the same ones the ◆ marks on the
/// clips and Properties ▸ Clip show.
enum VideoCurveLane {
    static let height: CGFloat = 56
    static let symbol = "point.topleft.down.curvedto.point.bottomright.up"
    static let gap: CGFloat = 4

    /// The settings it can show.
    static let properties: [VideoKeyProperty] = [.opacity, .width, .rotation, .x, .y, .volume, .intensity]

    /// The range a setting is drawn across (wider when its values go past).
    static func range(_ property: VideoKeyProperty, values: [Double]) -> ClosedRange<Double> {
        let standard: ClosedRange<Double>
        switch property {
        case .opacity, .intensity, .cropX, .cropY, .cropWidth, .cropHeight, .maskFeather: standard = 0...1
        case .width, .maskSize: standard = 0...1.2
        case .rotation, .maskRotation: standard = -180...180
        case .x, .y, .maskX, .maskY: standard = -0.2...1.2
        case .volume: standard = 0...2
        case .zoom: standard = 1...3
        }
        let low = min(standard.lowerBound, values.min() ?? standard.lowerBound)
        let high = max(standard.upperBound, values.max() ?? standard.upperBound)
        return low...max(high, low + 0.000_1)
    }

    /// A clip's keyframes for `property` as points: time (seconds on the
    /// timeline) and value; the clip's own keys, nothing kept here.
    static func points(_ item: VideoLayerItem, _ property: VideoKeyProperty) -> [(time: Double, value: Double)] {
        (item.keys?.keys(property) ?? []).map { (item.at + $0.time, $0.value) }
    }
}

extension VideoEditorModel {
    /// Opens or closes a track's curve lane (showing `property`).
    func toggleCurveLane(_ track: UUID) {
        if curveLanes[track] != nil {
            curveLanes[track] = nil
        } else {
            curveLanes[track] = .opacity
        }
    }
}

/// The lane: drawn under its track's clips.
struct VideoCurveLaneView: View {
    let model: VideoEditorModel
    let track: VideoLayerTrack
    let property: VideoKeyProperty
    let geometry: VideoTimelineGeometry
    @State private var drag: (item: UUID, from: Double)?

    var body: some View {
        let items = track.items.filter { $0.role == nil || property == .intensity }
        let values = items.flatMap { item in [item.base(property)] + VideoCurveLane.points(item, property).map(\.value) }
        let range = VideoCurveLane.range(property, values: values)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(VideoEditorTheme.trackLane)
                .frame(width: geometry.width, height: VideoCurveLane.height)
            Canvas { context, size in
                for item in items {
                    let x0 = geometry.x(item.at), x1 = geometry.x(item.end)
                    guard x1 > x0 + 1 else { continue }
                    var path = Path()
                    var x = x0
                    while x <= x1 {
                        let t = geometry.time(x)
                        let point = CGPoint(x: x, y: y(item.value(property, at: t), range: range, height: size.height))
                        if x == x0 { path.move(to: point) } else { path.addLine(to: point) }
                        x += 3
                    }
                    context.stroke(path, with: .color(VideoEditorTheme.primary.opacity(item.keys?.isAnimated(property) == true ? 0.9 : 0.35)), lineWidth: 1.5)
                }
            }
            .frame(width: geometry.width, height: VideoCurveLane.height)
            .allowsHitTesting(false)
            ForEach(items) { item in
                ForEach(Array(VideoCurveLane.points(item, property).enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(VideoEditorTheme.panel)
                        .overlay(Circle().stroke(VideoEditorTheme.primary, lineWidth: 2))
                        .frame(width: 9, height: 9)
                        .position(x: geometry.x(point.time), y: y(point.value, range: range, height: VideoCurveLane.height))
                        .gesture(dragGesture(item: item, from: point.time - item.at, value: point.value, range: range))
                        .help(L("\(property.title): drag to change it and when it happens"))
                        .accessibilityLabel(L("Keyframe: \(property.title)"))
                }
            }
        }
        .frame(width: geometry.width, height: VideoCurveLane.height, alignment: .topLeading)
    }

    private func y(_ value: Double, range: ClosedRange<Double>, height: CGFloat) -> CGFloat {
        let f = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return 6 + (1 - CGFloat(min(max(f, 0), 1))) * (height - 12)
    }

    private func dragGesture(item: VideoLayerItem, from local: Double, value: Double, range: ClosedRange<Double>) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { change in
                // Where the drag started (the key moves as it's dragged).
                let start = drag?.item == item.id ? drag!.from : local
                if drag == nil { drag = (item.id, local) }
                let time = local + Double(change.translation.width / max(geometry.pointsPerSecond, 0.001))
                let span = range.upperBound - range.lowerBound
                let newValue = value - Double(change.translation.height / (VideoCurveLane.height - 12)) * span
                model.selection = .layer(item.id)
                if model.perform(.edit(.moveKey(property, from: start, to: time, value: min(max(newValue, range.lowerBound), range.upperBound)))) {
                    let placed = model.project.layerItem(item.id)?.keys?.keys(property).min { abs($0.time - time) < abs($1.time - time) }?.time ?? time
                    drag = (item.id, placed)
                }
            }
            .onEnded { _ in
                drag = nil
                model.endGesture()
            }
    }
}

/// In a track's header (LF Studios layout): the curve lane's switch and
/// which setting it shows.
struct VideoCurveLaneHeader: View {
    @ObservedObject var model: VideoEditorModel
    let track: UUID

    var body: some View {
        if let property = model.curveLanes[track] {
            Menu {
                ForEach(VideoCurveLane.properties) { p in
                    Button { model.curveLanes[track] = p } label: {
                        if p == property { Label(p.title, systemImage: "checkmark") } else { Text(p.title) }
                    }
                }
            } label: {
                Text(property.title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .textCase(.uppercase)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("Which setting the curve shows"))
        }
    }
}
