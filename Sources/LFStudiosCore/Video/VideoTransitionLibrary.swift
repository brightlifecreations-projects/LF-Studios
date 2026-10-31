import CoreImage
import SwiftUI

// MARK: - Transitions that show both clips (1.15.0)

enum VideoTransitionRenderer {
    /// `from` (the clip before the cut) turning into `to` at `progress`
    /// (0…1, already eased), on a frame `rect` big.
    static func blend(_ kind: VideoTransitionKind, from: CIImage, to: CIImage, progress raw: Double, rect: CGRect) -> CIImage {
        let p = CGFloat(min(max(raw, 0), 1))
        let w = rect.width, h = rect.height
        let black = CIImage(color: .black).cropped(to: rect)
        func dissolve(_ a: CIImage, _ b: CIImage, _ t: CGFloat) -> CIImage {
            b.cropped(to: rect).applyingFilter("CIDissolveTransition", parameters: [kCIInputImageKey: a.cropped(to: rect), kCIInputTargetImageKey: b.cropped(to: rect), kCIInputTimeKey: t]).cropped(to: rect)
        }
        func scaled(_ image: CIImage, _ s: CGFloat, turn: CGFloat = 0) -> CIImage {
            image.transformed(by: CGAffineTransform(translationX: -rect.midX, y: -rect.midY)
                .concatenating(CGAffineTransform(rotationAngle: turn))
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
        }
        switch kind {
        case .slide:
            // The next clip comes in from the right, over this one.
            return to.transformed(by: CGAffineTransform(translationX: (1 - p) * w, y: 0)).cropped(to: rect).composited(over: from).cropped(to: rect)
        case .push:
            let out = from.transformed(by: CGAffineTransform(translationX: -p * w, y: 0)).cropped(to: rect)
            return to.transformed(by: CGAffineTransform(translationX: (1 - p) * w, y: 0)).cropped(to: rect).composited(over: out.composited(over: black)).cropped(to: rect)
        case .wipe:
            // A soft edge 6% wide sweeps left to right.
            let soft = w * 0.06
            let edge = rect.minX - soft + p * (w + soft * 2)
            guard let mask = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: edge - soft / 2, y: 0), "inputPoint1": CIVector(x: edge + soft / 2, y: 0),
                "inputColor0": CIColor.white, "inputColor1": CIColor.black,
            ])?.outputImage?.cropped(to: rect) else { return dissolve(from, to, p) }
            return to.cropped(to: rect).applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: from.cropped(to: rect), kCIInputMaskImageKey: mask]).cropped(to: rect)
        case .zoom:
            // Into this clip, out of the next one.
            let a = scaled(from.clampedToExtent(), 1 + p * 0.6).cropped(to: rect)
            let b = scaled(to.clampedToExtent(), 1.6 - p * 0.6).cropped(to: rect)
            return dissolve(a, b, p)
        case .blur:
            let amount = sin(p * .pi) * 28 * h / 1080
            let a = from.clampedToExtent().applyingGaussianBlur(sigma: amount).cropped(to: rect)
            let b = to.clampedToExtent().applyingGaussianBlur(sigma: amount).cropped(to: rect)
            return dissolve(a, b, p)
        case .spin:
            // A half turn out, a half turn in, on black.
            if p < 0.5 {
                let t = p * 2
                return scaled(from.cropped(to: rect), 1 - t * 0.7, turn: -t * .pi).composited(over: black).cropped(to: rect)
            }
            let t = (p - 0.5) * 2
            return scaled(to.cropped(to: rect), 0.3 + t * 0.7, turn: (1 - t) * .pi).composited(over: black).cropped(to: rect)
        case .dissolve:
            return dissolve(from, to, p)
        case .none, .fadeThroughBlack, .fadeThroughWhite:
            return (p < 0.5 ? from : to).cropped(to: rect)
        }
    }
}

extension VideoDemoProject {
    /// A cut uses a transition only 1.15.0 shows.
    var usesNewTransitions: Bool {
        transitions.betweenClips.isNew || transitions.overrides.contains { $0.kind.isNew }
    }
}

extension VideoEditorModel {
    /// The clip after the cut that a transition goes on: the selected clip's
    /// cut in (or out, for the first clip), else the cut nearest `time`.
    func transitionCutClip(near time: Double? = nil) -> UUID? {
        guard segments.count > 1 else { return nil }
        if time == nil, case .clip(let id) = selection, let index = segments.firstIndex(where: { $0.id == id }) {
            return segments[max(index, 1)].id
        }
        let at = time ?? clock.time
        return segments.dropFirst().min { abs($0.timelineStart - at) < abs($1.timelineStart - at) }?.id
    }

    /// Every cut the same (the per-cut choices go). One ⌘Z step.
    func applyTransitionToAll(_ kind: VideoTransitionKind, duration: Double) {
        if refuseLocked(.clips) { return }
        mutate(label: "Transitions") { project in
            project.transitions.betweenClips = kind
            project.transitions.duration = min(max(duration, VideoTransitionSettings.durationRange.lowerBound), VideoTransitionSettings.durationRange.upperBound)
            project.transitions.overrides = []
        }
        showNotice(L("\(kind.title) on every cut"), symbol: kind.symbol)
    }
}

// MARK: - Library ▸ Transitions

struct VideoTransitionsLibraryTab: View {
    @ObservedObject var model: VideoEditorModel
    @State private var length = Settings.videoTransitionLength

    private var tiles: [VideoLibraryTile] {
        VideoTransitionKind.allCases.filter { $0 != .none }.map {
            VideoLibraryTile(payload: .init(kind: "transition", id: $0.rawValue), title: $0.title, section: $0.usesBothSides ? L("Between the clips") : L("Through a colour"))
        }
    }

    var body: some View {
        VideoLibraryGrid(model: model, tiles: tiles, minimum: 84, tileHeight: 50) {
            VStack(alignment: .leading, spacing: 8) {
                VideoSliderRow(title: L("Length"), value: Binding(get: { length }, set: { length = ($0 * 10).rounded() / 10; Settings.videoTransitionLength = length }), range: VideoTransitionSettings.durationRange, defaultValue: 0.5,
                               format: { VideoEditorModel.formatTenths($0) }) // l10n-ignore: a number
                Text(model.segments.count > 1
                     ? L("Click + to put one on the selected clip's cut (or the cut nearest the playhead), or drag one onto a cut on the timeline.")
                     : L("Split the video (⌘B) to make cuts; transitions go between clips on the main track."))
                    .font(.system(size: 11))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Menu {
                    ForEach(VideoTransitionKind.allCases) { kind in
                        Button(kind.title) { model.perform(.clip(.transitionEverywhere(kind, length))) }
                    }
                } label: {
                    Label(L("Apply to all cuts…"), systemImage: "square.stack.3d.forward.dottedline").frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
                .disabled(model.segments.count < 2)
                .help(L("The same transition on every cut between clips"))
            }
        } preview: { tile, hovering in
            if let kind = VideoTransitionKind(rawValue: tile.payload.id) {
                VideoTransitionPreview(kind: kind, hovering: hovering)
            }
        }
    }
}

/// Two of our own sample frames turning into each other.
struct VideoTransitionPreview: View {
    let kind: VideoTransitionKind
    let hovering: Bool
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let rect = CGRect(x: 0, y: 0, width: 160, height: 90)
    static let a: CIImage = {
        let base = CIImage(color: CIColor(red: 0.95, green: 0.55, blue: 0.25)).cropped(to: rect)
        let disc = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": CIVector(x: 60, y: 45), "inputRadius0": 20, "inputRadius1": 22,
                                                                   "inputColor0": CIColor.white, "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0)])!.outputImage!.cropped(to: rect)
        return disc.composited(over: base)
    }()
    static let b: CIImage = {
        let base = CIImage(color: CIColor(red: 0.2, green: 0.45, blue: 0.85)).cropped(to: rect)
        let bar = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 1)).cropped(to: CGRect(x: 90, y: 25, width: 40, height: 40))
        return bar.composited(over: base)
    }()

    var body: some View {
        TimelineView(.animation(paused: !hovering)) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2)
            let p = hovering ? min(max((cycle - 0.4) / 1.2, 0), 1) : 0.5
            if let image = Self.render(kind, progress: p) {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
            }
        }
    }

    static func render(_ kind: VideoTransitionKind, progress: Double) -> CGImage? {
        let image: CIImage
        switch kind {
        case .fadeThroughBlack, .fadeThroughWhite:
            let dip = 1 - abs(progress - 0.5) * 2
            let colour = kind == .fadeThroughBlack ? CIColor(red: 0, green: 0, blue: 0, alpha: dip) : CIColor(red: 1, green: 1, blue: 1, alpha: dip)
            image = CIImage(color: colour).cropped(to: rect).composited(over: progress < 0.5 ? a : b)
        default:
            image = VideoTransitionRenderer.blend(kind, from: a, to: b, progress: VideoCameraEasing.glide(progress), rect: rect)
        }
        return context.createCGImage(image, from: rect)
    }
}

/// A grid of transitions (the cut's own, in the clip inspector, and the
/// Style tab's “Between clips”).
struct VideoTransitionPicker: View {
    let selection: VideoTransitionKind
    let pick: (VideoTransitionKind) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 5)], spacing: 5) {
            ForEach(VideoTransitionKind.allCases) { kind in
                Button { pick(kind) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: kind.symbol).font(.system(size: 12, weight: .semibold))
                        Text(kind.title).font(.system(size: 9.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundStyle(selection == kind ? VideoEditorTheme.textPrimary : VideoEditorTheme.textSecondary)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selection == kind ? VideoEditorTheme.layer.opacity(0.25) : VideoEditorTheme.card))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.title)
                .accessibilityAddTraits(selection == kind ? .isSelected : [])
            }
        }
    }
}
