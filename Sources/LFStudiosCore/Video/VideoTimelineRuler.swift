import AppKit
import SwiftUI

// MARK: - Ruler & playhead

struct VideoTimelineRuler: View {
    let duration: Double
    let pointsPerSecond: CGFloat
    let inset: CGFloat
    /// The part on screen (x across the whole ruler): ticks off it aren't
    /// drawn, so a zoomed-in long video doesn't draw thousands per frame.
    var visible: ClosedRange<CGFloat>?

    var body: some View {
        Canvas { context, size in
            let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
            let major = steps.first { CGFloat($0) * pointsPerSecond >= 72 } ?? 600
            let minor = major / (major >= 1 && major.truncatingRemainder(dividingBy: 5) == 0 ? 5 : 4)
            // From a label's width before the edge: its text reaches in.
            let first = visible.map { max(Int((Double($0.lowerBound - inset - 60) / Double(pointsPerSecond) / minor).rounded(.down)), 0) } ?? 0
            let last = visible.map { Double($0.upperBound - inset) / Double(pointsPerSecond) + major } ?? .infinity
            var index = first
            while true {
                let t = Double(index) * minor
                guard t <= duration + 0.0001, t <= last else { break }
                index += 1
                let x = inset + CGFloat(t) * pointsPerSecond
                let isMajor = abs((t / major).rounded() * major - t) < 0.0001
                let height: CGFloat = isMajor ? 8 : 4
                context.fill(Path(CGRect(x: x, y: size.height - height, width: 1, height: height)), with: .color(VideoEditorTheme.ink.opacity(isMajor ? 0.35 : 0.16)))
                if isMajor {
                    let label = context.resolve(Text(Self.label(t, step: major))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(VideoEditorTheme.textTertiary))
                    // The first label clears the playhead's knob; the last
                    // one is skipped rather than cut off.
                    let labelX = t == 0 ? x + 9 : x + 3
                    if labelX + label.measure(in: size).width <= size.width {
                        context.draw(label, at: CGPoint(x: labelX, y: size.height - 16), anchor: .leading)
                    }
                }
            }
        }
    }

    static func label(_ time: Double, step: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = time - Double(minutes * 60)
        if step < 1 {
            return String(format: "%d:%04.1f", minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, Int(seconds.rounded()))
    }
}

struct VideoTimelinePlayhead: View {
    /// Snapshots for the website, which draws its own live playhead.
    nonisolated(unsafe) static var hiddenInSnapshots = false

    @ObservedObject var clock: VideoDemoPlaybackClock
    let x: (Double) -> CGFloat
    let height: CGFloat
    /// The knob sits on the ruler; the lanes get just the line.
    var showsKnob = true

    var body: some View {
        let position = x(clock.time)
        ZStack(alignment: .top) {
            Rectangle()
                .fill(VideoEditorTheme.playhead)
                .frame(width: 2, height: height)
            if showsKnob {
                PlayheadKnob()
                    .fill(VideoEditorTheme.playhead)
                    .frame(width: 13, height: 17)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            }
        }
        // Centred on the moment: by the knob's half when it has one, else
        // the line's (it used to sit 5.5 pt left of the handle).
        .offset(x: position - (showsKnob ? 6.5 : 1))
        .opacity(Self.hiddenInSnapshots ? 0 : 1)
        .allowsHitTesting(false)
    }
}

/// The playhead's handle at the top of the ruler, with the line down to
/// the lanes (where the lanes' own line carries on). Its whole shape shows
/// at any zoom, track height, scroll position and window size; dragging it
/// moves the playhead.
struct VideoPlayheadHandle: View {
    let model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock
    @ObservedObject var offsets: VideoTimelineScrollOffsets
    let x: (Double) -> CGFloat
    let time: (CGFloat) -> Double
    /// The lanes' visible width: off it, the handle hides.
    let width: CGFloat

    static let size = CGSize(width: 13, height: 17)
    /// From the ruler's top edge: room for its rounded top.
    static let top: CGFloat = 2

    var body: some View {
        let position = x(clock.time) - offsets.x
        if position >= -Self.size.width, position <= width + Self.size.width, !VideoTimelinePlayhead.hiddenInSnapshots {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(VideoEditorTheme.playhead)
                    .frame(width: 2, height: VideoTimelineMetrics.rulerHeight + 1 - Self.top)
                PlayheadKnob()
                    .fill(VideoEditorTheme.playhead)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .contentShape(Rectangle().inset(by: -4))
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("lanesArea"))
                            .onChanged { drag in model.seek(to: max(time(drag.location.x + offsets.x), 0), fast: true) }
                            .onEnded { drag in model.seek(to: max(time(drag.location.x + offsets.x), 0)) }
                    )
                    .help(L("Drag to move the playhead"))
                    .accessibilityLabel(L("Playhead"))
                    .accessibilityValue(VideoEditorModel.timecode(clock.time))
            }
            .offset(x: position - Self.size.width / 2, y: Self.top)
        }
    }
}

private struct PlayheadKnob: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 3
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 6))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 6))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
