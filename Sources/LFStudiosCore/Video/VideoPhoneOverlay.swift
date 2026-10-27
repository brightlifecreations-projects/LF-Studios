import SwiftUI

/// Phone overlay: over a vertical (9:16) preview, the kind of interface a
/// short-video app puts on top of a video — a top bar, buttons down the
/// side, the caption area — drawn from plain shapes, with the parts it
/// would cover shaded. Three generic layouts; no app's logo or name. It's
/// the preview's alone: never saved, never in an export.
enum VideoPhoneLayout: String, CaseIterable, Identifiable {
    case sideRail
    case fullRail
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideRail: return L("Side rail")
        case .fullRail: return L("Full rail")
        case .minimal: return L("Minimal")
        }
    }

    var detail: String {
        switch self {
        case .sideRail: return L("Buttons on the right, caption bottom-left, tabs at the top")
        case .fullRail: return L("A taller button column, a spinning-disc spot, a bottom navigation bar")
        case .minimal: return L("A short button column, a pill button by the caption, a search bar at the top")
        }
    }

    /// The parts the interface covers, as fractions of the frame (y down).
    struct Zones: Equatable {
        /// Status bar and tabs or search.
        let top: Double
        /// Caption, account and navigation.
        let bottom: Double
        /// The button column on the right: its width, and where it runs.
        let railWidth: Double
        let railTop: Double
        let railBottom: Double
        /// A bottom navigation bar (inside `bottom`).
        let navigationBar: Double
    }

    var zones: Zones {
        switch self {
        case .sideRail: return Zones(top: 0.10, bottom: 0.20, railWidth: 0.15, railTop: 0.46, railBottom: 0.80, navigationBar: 0)
        case .fullRail: return Zones(top: 0.12, bottom: 0.26, railWidth: 0.17, railTop: 0.36, railBottom: 0.84, navigationBar: 0.075)
        case .minimal: return Zones(top: 0.08, bottom: 0.17, railWidth: 0.13, railTop: 0.56, railBottom: 0.83, navigationBar: 0)
        }
    }

    /// The rectangles a viewer can't see clearly (in a frame of `size`).
    func unsafeRects(in size: CGSize) -> [CGRect] {
        let z = zones
        let w = size.width, h = size.height
        return [
            CGRect(x: 0, y: 0, width: w, height: h * z.top),
            CGRect(x: 0, y: h * (1 - z.bottom), width: w, height: h * z.bottom),
            CGRect(x: w * (1 - z.railWidth), y: h * z.railTop, width: w * z.railWidth, height: h * (min(z.railBottom, 1 - z.bottom) - z.railTop)),
        ]
    }

    /// The overlay makes sense for vertical frames only.
    static func isAvailable(for canvas: CGSize) -> Bool {
        guard canvas.width > 0, canvas.height > 0 else { return false }
        return abs(canvas.width / canvas.height - 9.0 / 16) < 0.02
    }
}

extension VideoEditorModel {
    var canShowPhoneOverlay: Bool { VideoPhoneLayout.isAvailable(for: project.canvasSize()) }

    func togglePhoneOverlay() {
        phoneOverlay = phoneOverlay == nil ? .sideRail : nil
    }
}

/// The button above a vertical preview: click to show or hide the overlay;
/// its menu picks the layout.
struct VideoPhoneOverlayButton: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        Menu {
            ForEach(VideoPhoneLayout.allCases) { layout in
                Button {
                    model.phoneOverlay = layout
                } label: {
                    if model.phoneOverlay == layout {
                        Label(layout.title, systemImage: "checkmark")
                    } else {
                        Text(layout.title)
                    }
                }
                .help(layout.detail)
            }
            if model.phoneOverlay != nil {
                Divider()
                Button(L("Hide Phone Overlay")) { model.phoneOverlay = nil }
            }
        } label: {
            Label(L("Phone overlay"), systemImage: model.phoneOverlay == nil ? "iphone" : "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 12, weight: .semibold))
        } primaryAction: {
            model.togglePhoneOverlay()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(model.phoneOverlay == nil ? VideoEditorTheme.well : VideoEditorTheme.accent.opacity(0.28)))
        .help(L("Preview how a phone app's buttons and captions sit over this video, with the covered parts shaded — never in the export"))
        .accessibilityLabel(L("Phone overlay"))
    }
}

/// The overlay itself, drawn over the preview (hit-testing off).
struct VideoPhoneOverlayView: View {
    let layout: VideoPhoneLayout
    let size: CGSize

    private var unit: CGFloat { size.width / 100 }
    private let ink = Color.white

    var body: some View {
        let z = layout.zones
        ZStack(alignment: .topLeading) {
            // Shading on the parts the interface covers.
            ForEach(Array(layout.unsafeRects(in: size).enumerated()), id: \.offset) { _, rect in
                Rectangle()
                    .fill(Color.black.opacity(0.34))
                    .overlay(Rectangle().strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            topBar(z)
            rail(z)
            caption(z)
            if z.navigationBar > 0 { navigationBar(z) }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func line(_ width: CGFloat, _ opacity: Double = 0.85) -> some View {
        Capsule().fill(ink.opacity(opacity)).frame(width: width, height: unit * 2.2)
    }

    @ViewBuilder
    private func topBar(_ z: VideoPhoneLayout.Zones) -> some View {
        VStack(spacing: unit * 2.2) {
            // Status bar: the time and a battery.
            HStack {
                line(unit * 9)
                Spacer()
                RoundedRectangle(cornerRadius: unit * 0.8).strokeBorder(ink.opacity(0.85), lineWidth: max(unit * 0.35, 1))
                    .frame(width: unit * 6, height: unit * 3)
            }
            .padding(.horizontal, unit * 6)
            switch layout {
            case .minimal:
                // A search bar.
                Capsule().fill(ink.opacity(0.22)).frame(height: unit * 6).padding(.horizontal, unit * 8)
                    .overlay(HStack { Circle().strokeBorder(ink.opacity(0.8), lineWidth: max(unit * 0.4, 1)).frame(width: unit * 3, height: unit * 3); line(unit * 18, 0.5); Spacer() }.padding(.horizontal, unit * 12))
            case .sideRail, .fullRail:
                // Two tabs, the chosen one underlined.
                HStack(spacing: unit * 6) {
                    line(unit * 14, 0.55)
                    VStack(spacing: unit * 1) { line(unit * 14); Capsule().fill(ink).frame(width: unit * 7, height: unit * 0.7) }
                }
            }
        }
        .padding(.top, unit * 3)
        .frame(width: size.width, height: size.height * z.top, alignment: .top)
    }

    private func rail(_ z: VideoPhoneLayout.Zones) -> some View {
        let symbols: [String]
        switch layout {
        case .sideRail: symbols = ["heart.fill", "bubble.right.fill", "bookmark.fill", "arrowshape.turn.up.right.fill"]
        case .fullRail: symbols = ["person.crop.circle.fill", "heart.fill", "bubble.right.fill", "bookmark.fill", "arrowshape.turn.up.right.fill"]
        case .minimal: symbols = ["hand.thumbsup.fill", "bubble.right.fill", "arrowshape.turn.up.right.fill"]
        }
        let width = size.width * z.railWidth
        let top = size.height * z.railTop
        let height = size.height * (min(z.railBottom, 1 - z.bottom) - z.railTop)
        return VStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                VStack(spacing: unit * 0.8) {
                    Image(systemName: symbol)
                        .font(.system(size: unit * 6.5, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.92))
                    if symbol != "person.crop.circle.fill" { line(unit * 5, 0.6) }
                }
                .frame(maxHeight: .infinity)
            }
            if layout == .fullRail {
                // The spinning-disc spot.
                Circle().fill(ink.opacity(0.25)).overlay(Circle().strokeBorder(ink.opacity(0.7), lineWidth: max(unit * 0.5, 1)))
                    .overlay(Circle().fill(ink.opacity(0.8)).frame(width: unit * 2, height: unit * 2))
                    .frame(width: unit * 8.5, height: unit * 8.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height)
        .offset(x: size.width - width, y: top)
    }

    private func caption(_ z: VideoPhoneLayout.Zones) -> some View {
        let bottom = size.height * z.bottom
        let nav = size.height * z.navigationBar
        return VStack(alignment: .leading, spacing: unit * 1.8) {
            HStack(spacing: unit * 2) {
                Circle().fill(ink.opacity(0.85)).frame(width: unit * 6, height: unit * 6)
                line(unit * 20)
                if layout == .minimal {
                    // A pill button by the name.
                    Capsule().fill(ink.opacity(0.9)).frame(width: unit * 14, height: unit * 4.6)
                }
            }
            line(unit * 58, 0.75)
            line(unit * 40, 0.6)
            if layout != .minimal {
                HStack(spacing: unit * 1.5) {
                    Image(systemName: "music.note").font(.system(size: unit * 3.2, weight: .bold)).foregroundStyle(ink.opacity(0.8))
                    line(unit * 30, 0.5)
                }
            }
        }
        .padding(.leading, unit * 4)
        .padding(.bottom, nav + unit * 3)
        .frame(width: size.width * (1 - z.railWidth), height: bottom, alignment: .bottomLeading)
        .offset(y: size.height - bottom)
    }

    private func navigationBar(_ z: VideoPhoneLayout.Zones) -> some View {
        let height = size.height * z.navigationBar
        return HStack {
            ForEach(["house.fill", "magnifyingglass", "plus.app.fill", "tray.fill", "person.fill"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: unit * 5.5, weight: .semibold))
                    .foregroundStyle(ink.opacity(symbol == "house.fill" ? 0.95 : 0.6))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: size.width, height: height)
        .background(Color.black.opacity(0.55))
        .offset(y: size.height - height)
    }
}
