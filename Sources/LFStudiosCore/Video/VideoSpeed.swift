import SwiftUI

// MARK: - Speed: Normal and Curve (1.15.0)

/// A speed curve: speed (×) along a clip (x: 0 at its start → 1 at its end
/// in the recording).
struct VideoSpeedCurve: Codable, Equatable {
    struct Point: Codable, Equatable {
        var x: Double
        var speed: Double
    }

    var preset: VideoSpeedPreset?
    var points: [Point]

    static let speedRange: ClosedRange<Double> = 0.1...10

    /// The speed at `x`, eased between points (in steps of doubling, so
    /// 0.5× → 2× passes 1× half way).
    func speed(at x: Double) -> Double {
        let sorted = points.sorted { $0.x < $1.x }
        guard let first = sorted.first, let last = sorted.last else { return 1 }
        if x <= first.x { return first.speed }
        if x >= last.x { return last.speed }
        guard let i = sorted.lastIndex(where: { $0.x <= x }), i + 1 < sorted.count else { return last.speed }
        let a = sorted[i], b = sorted[i + 1]
        let t = VideoEasing.easeInOut.apply((x - a.x) / max(b.x - a.x, 0.000_001))
        return exp(log(max(a.speed, 0.01)) + (log(max(b.speed, 0.01)) - log(max(a.speed, 0.01))) * t)
    }

    /// How many steady pieces a clip `sourceSeconds` long is played in.
    static func pieces(sourceSeconds: Double) -> Int {
        min(max(Int((sourceSeconds / 0.25).rounded()), 8), 40)
    }
}

enum VideoSpeedPreset: String, Codable, CaseIterable, Identifiable {
    case montage, hero, bullet, jumpCut, flashIn, flashOut, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .montage: return L("Montage")
        case .hero: return L("Hero")
        case .bullet: return L("Bullet")
        case .jumpCut: return L("Jump cut")
        case .flashIn: return L("Flash in")
        case .flashOut: return L("Flash out")
        case .custom: return L("Custom")
        }
    }

    var curve: VideoSpeedCurve {
        func p(_ points: [(Double, Double)]) -> VideoSpeedCurve {
            VideoSpeedCurve(preset: self, points: points.map { .init(x: $0.0, speed: $0.1) })
        }
        switch self {
        case .montage: return p([(0, 1), (0.2, 4), (0.4, 0.6), (0.6, 4), (0.8, 0.6), (1, 1)])
        case .hero: return p([(0, 3), (0.35, 3), (0.5, 0.3), (0.65, 3), (1, 3)])
        case .bullet: return p([(0, 2.5), (0.4, 0.2), (0.6, 0.2), (1, 2.5)])
        case .jumpCut: return p([(0, 1), (0.3, 1), (0.36, 8), (0.44, 8), (0.5, 1), (0.7, 1), (0.76, 8), (0.84, 8), (0.9, 1), (1, 1)])
        case .flashIn: return p([(0, 6), (0.5, 1), (1, 1)])
        case .flashOut: return p([(0, 1), (0.5, 1), (1, 6)])
        case .custom: return p([(0, 1), (0.5, 1), (1, 1)])
        }
    }
}

/// The pieces of one clip played with a curve share this.
struct VideoSpeedCurveGroup: Codable, Equatable {
    var id: UUID
    var curve: VideoSpeedCurve
}

extension VideoDemoProject {
    /// The clips of a curve group, in order (or just the clip).
    func curvePieces(of id: UUID) -> [VideoDemoTimelineClip] {
        guard let clip = timelineClips.first(where: { $0.id == id }) else { return [] }
        guard let group = clip.curve?.id else { return [clip] }
        return timelineClips.filter { $0.curve?.id == group }
    }

    /// Plays `id` (and its curve group) with `curve` (nil: back to one clip
    /// at `speed`), keeping its place and everything else about it.
    mutating func applySpeedCurve(to id: UUID, _ curve: VideoSpeedCurve?, speed: Double = 1, totalDuration: Double) {
        var clips = normalizedTimelineClips(totalDuration: totalDuration)
        let group = clips.first { $0.id == id }?.curve?.id
        let members = clips.filter { $0.id == id || (group != nil && $0.curve?.id == group) }
        guard let first = members.first, let last = members.last, let index = clips.firstIndex(where: { $0.id == first.id }) else { return }
        clips.removeAll { member in members.contains { $0.id == member.id } }
        var model = first
        model.fadeOut = last.fadeOut
        model.curve = nil
        let start = first.sourceStart, end = last.sourceEnd
        var replacement: [VideoDemoTimelineClip] = []
        if let curve {
            let count = VideoSpeedCurve.pieces(sourceSeconds: end - start)
            let group = VideoSpeedCurveGroup(id: UUID(), curve: curve)
            for step in 0..<count {
                var piece = model
                piece.id = step == 0 ? first.id : UUID()
                piece.sourceStart = start + (end - start) * Double(step) / Double(count)
                piece.sourceEnd = start + (end - start) * Double(step + 1) / Double(count)
                piece.speed = min(max(curve.speed(at: (Double(step) + 0.5) / Double(count)), VideoSpeedCurve.speedRange.lowerBound), VideoSpeedCurve.speedRange.upperBound)
                piece.fadeIn = step == 0 ? first.fadeIn : 0
                piece.fadeOut = step == count - 1 ? last.fadeOut : 0
                piece.curve = group
                replacement.append(piece)
            }
        } else {
            var clip = model
            clip.sourceEnd = end
            clip.speed = speed
            replacement = [clip]
        }
        clips.insert(contentsOf: replacement, at: index)
        timelineClips = clips
        syncTrimToTimeline(totalDuration: totalDuration)
    }
}

// MARK: - Commands on the main track's clip

/// Edits of the main track's clip (selected, or under the playhead).
enum VideoClipEdit: Equatable {
    case setSpeed(Double)
    case setKeepPitch(Bool)
    case setSpeedCurve(VideoSpeedCurve?)
    /// A transition on the clip's cut (nil length: as it was).
    case setTransition(VideoTransitionKind, Double?)
    /// The same transition on every cut.
    case transitionEverywhere(VideoTransitionKind, Double)

    var name: String {
        switch self {
        case .setSpeed(let s): return "setSpeed.\(s)"
        case .setKeepPitch(let on): return "setKeepPitch.\(on)"
        case .setSpeedCurve(let c): return "setSpeedCurve.\(c?.preset?.rawValue ?? "none")"
        case .setTransition(let k, let d): return "setTransition.\(k.rawValue).\(d.map { "\($0)" } ?? "-")"
        case .transitionEverywhere(let k, let d): return "transitionEverywhere.\(k.rawValue).\(d)"
        }
    }

    var title: String {
        switch self {
        case .setSpeed: return L("Speed")
        case .setKeepPitch: return L("Keep pitch")
        case .setSpeedCurve: return L("Speed curve")
        case .setTransition(let k, _): return k.title
        case .transitionEverywhere: return L("Apply to all cuts")
        }
    }
}

extension VideoEditorModel {
    func perform(_ edit: VideoClipEdit) -> Bool {
        if refuseLocked(.clips) { return false }
        guard let segment = targetClip else { return false }
        let total = sourceDuration
        switch edit {
        case .setSpeed(let speed):
            let clamped = min(max(speed, VideoDemoTimelineClip.speedRange.lowerBound), VideoDemoTimelineClip.speedRange.upperBound)
            mutate(coalesce: "speed-\(segment.id)", label: "Speed") { project in
                if segment.clip.curve != nil {
                    // A steady speed takes the curve's place.
                    project.applySpeedCurve(to: segment.id, nil, speed: clamped, totalDuration: total)
                } else {
                    _ = project.updateClip(id: segment.id, totalDuration: total) { $0.speed = clamped }
                }
            }
        case .setKeepPitch(let on):
            let ids = Set(project.curvePieces(of: segment.id).map(\.id))
            mutate(label: on ? "Keep Pitch" : "Change Pitch") { project in
                for index in project.timelineClips.indices where ids.contains(project.timelineClips[index].id) {
                    project.timelineClips[index].keepsPitch = on ? nil : false
                }
            }
        case .setTransition(let kind, let duration):
            guard let cut = transitionCutClip() else {
                showNotice(L("Split the video (⌘B) to make a cut for a transition"), symbol: "scissors")
                return false
            }
            setTransition(into: cut, kind: kind, duration: duration)
        case .transitionEverywhere(let kind, let duration):
            guard segments.count > 1 else { return false }
            applyTransitionToAll(kind, duration: duration)
        case .setSpeedCurve(let curve):
            mutate(coalesce: curve?.preset == .custom ? "curve-\(segment.id)" : nil, label: "Speed Curve") { project in
                project.applySpeedCurve(to: segment.id, curve, speed: 1, totalDuration: total)
            }
            if let first = project.curvePieces(of: segment.id).first ?? segments.first(where: { $0.clip.sourceStart <= segment.clip.sourceStart + 0.001 && $0.clip.sourceEnd > segment.clip.sourceStart })?.clip {
                selection = .clip(first.id)
            }
        }
        return true
    }
}

// MARK: - Properties ▸ Speed (a main-track clip)

/// Normal (a steady speed, 0.1× to 100×) or Curve (presets, or drawn).
struct VideoClipSpeedSection: View {
    @ObservedObject var model: VideoEditorModel
    let segment: VideoDemoTimelineSegment
    @State private var tab = 0

    var body: some View {
        let curve = segment.clip.curve?.curve
        VideoInspectorSection(L("Speed")) {
            VideoSegmented(options: [(0, L("Normal")), (1, L("Curve"))], selection: Binding(get: { curve != nil ? 1 : tab }, set: { tab = $0 }))
            if curve == nil && tab == 0 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach([0.1, 0.25, 0.5, 1.0, 1.5, 2.0, 4.0, 8.0, 16.0, 100.0], id: \.self) { speed in
                        let selected = abs(segment.clip.normalizedSpeed - speed) < 0.001
                        Button {
                            model.perform(.clip(.setSpeed(speed)))
                            model.endGesture()
                        } label: {
                            Text(VideoEditorModel.formatScale(speed))
                                .font(.system(size: 11, weight: selected ? .bold : .semibold))
                                .foregroundStyle(selected ? Color.black : VideoEditorTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? VideoEditorTheme.clip : VideoEditorTheme.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
                VideoSliderRow(title: L("Speed"), value: Binding(get: { log10(segment.clip.normalizedSpeed) }, set: { value in
                    model.perform(.clip(.setSpeed((pow(10, value) * 100).rounded() / 100)))
                }), range: -1...2, defaultValue: 0, format: { VideoEditorModel.formatScale(pow(10, $0)) }, onEditingEnded: { model.endGesture() })
                Text(L("\(VideoEditorModel.format(segment.clip.sourceDuration)) of recording plays in \(VideoEditorModel.format(segment.duration))."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    curveButton(nil)
                    ForEach(VideoSpeedPreset.allCases) { curveButton($0) }
                }
                if let curve {
                    VideoSpeedCurveEditor(curve: curve) { edited in
                        var custom = edited
                        custom.preset = .custom
                        model.perform(.clip(.setSpeedCurve(custom)))
                    } done: {
                        model.endGesture()
                    }
                    .frame(height: 110)
                    Text(L("Drag a point up for faster, down for slower. Double-click to add a point; double-click a point to take it away."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VideoToggleRow(title: L("Keep pitch"), detail: L("Off: faster sounds higher, slower lower. The sound is silent faster than 32× or slower than 1/32×."),
                           isOn: Binding(get: { segment.clip.keepsPitch != false }, set: { on in
                               model.perform(.clip(.setKeepPitch(on)))
                           }))
        }
    }

    private func curveButton(_ preset: VideoSpeedPreset?) -> some View {
        let selected = segment.clip.curve?.curve.preset == preset && (preset != nil || segment.clip.curve == nil)
        return Button {
            model.perform(.clip(.setSpeedCurve(preset?.curve)))
            model.endGesture()
            if preset == nil { tab = 0 }
        } label: {
            Text(preset?.title ?? L("None"))
                .font(.system(size: 10.5, weight: selected ? .bold : .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Color.black : VideoEditorTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? VideoEditorTheme.clip : VideoEditorTheme.card))
        }
        .buttonStyle(.plain)
    }
}

/// The curve: speed up and down along the clip. Points drag; double-click
/// adds or takes one away.
struct VideoSpeedCurveEditor: View {
    let curve: VideoSpeedCurve
    let changed: (VideoSpeedCurve) -> Void
    let done: () -> Void
    @State private var dragging: Int?

    /// Speed ↔ height: log scale, 0.1× at the bottom, 10× at the top.
    private func y(_ speed: Double, _ height: CGFloat) -> CGFloat {
        let t = (log10(min(max(speed, 0.1), 10)) + 1) / 2
        return height * CGFloat(1 - t)
    }

    private func speed(_ y: CGFloat, _ height: CGFloat) -> Double {
        let t = 1 - Double(min(max(y / max(height, 1), 0), 1))
        return (pow(10, t * 2 - 1) * 100).rounded() / 100
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let points = curve.points.sorted { $0.x < $1.x }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VideoEditorTheme.well)
                // 1× line.
                Path { $0.move(to: CGPoint(x: 0, y: y(1, h))); $0.addLine(to: CGPoint(x: w, y: y(1, h))) }
                    .stroke(VideoEditorTheme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Path { path in
                    for step in 0...60 {
                        let x = Double(step) / 60
                        let p = CGPoint(x: w * CGFloat(x), y: y(curve.speed(at: x), h))
                        if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                }
                .stroke(VideoEditorTheme.clip, lineWidth: 2)
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(VideoEditorTheme.clip, lineWidth: 2))
                        .frame(width: 11, height: 11)
                        .position(x: w * CGFloat(point.x), y: y(point.speed, h))
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("speed-curve"))
                            .onChanged { value in
                                var next = curve
                                var moved = points
                                let lower = index == 0 ? 0 : points[index - 1].x + 0.02
                                let upper = index == points.count - 1 ? 1 : points[index + 1].x - 0.02
                                // The ends stay at the clip's ends.
                                let x = (index == 0 || index == points.count - 1) ? point.x : min(max(Double(value.location.x / max(w, 1)), lower), upper)
                                moved[index] = .init(x: x, speed: speed(value.location.y, h))
                                next.points = moved
                                changed(next)
                            }
                            .onEnded { _ in done() })
                        .onTapGesture(count: 2) {
                            guard index != 0, index != points.count - 1 else { return }
                            var next = curve
                            var fewer = points
                            fewer.remove(at: index)
                            next.points = fewer
                            changed(next)
                            done()
                        }
                        .accessibilityLabel(L("Speed point: \(VideoEditorModel.formatScale(point.speed))"))
                }
            }
            .coordinateSpace(name: "speed-curve")
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                var next = curve
                next.points.append(.init(x: Double(location.x / max(w, 1)), speed: speed(location.y, h)))
                next.points.sort { $0.x < $1.x }
                changed(next)
                done()
            }
        }
    }
}
