import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Properties in the LF Studios (new) layout (1.17.0)

/// The right panel's tabs: what's selected (Clip), its effect chain
/// (Effects), every caption (Captions), and the whole video's look (Video:
/// Style, Cursor, Zoom, Camera, Audio).
enum VideoPropertiesTab: String, CaseIterable, Identifiable {
    case clip
    case effects
    case captions
    case video

    var id: String { rawValue }
    var title: String {
        switch self {
        case .clip: return L("Clip")
        case .effects: return L("Effects")
        case .captions: return L("Captions")
        case .video: return L("Video")
        }
    }
}

/// At the top: what plays at the playhead, and what comes next; below, the
/// tabs.
struct VideoPropertiesPanel: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VideoAtPlayhead(model: model, clock: model.clock)
                    .frame(height: min(132, proxy.size.height * 0.25))
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                tabBar
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                content(height: proxy.size.height)
            }
        }
        .background(VideoEditorTheme.panel)
    }

    private var tabBar: some View {
        HStack(spacing: 14) {
            ForEach(VideoPropertiesTab.allCases) { tab in
                let selected = model.propertiesTab == tab
                Button {
                    model.propertiesTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(selected ? VideoEditorTheme.textPrimary : VideoEditorTheme.textTertiary)
                        Rectangle()
                            .fill(selected ? VideoEditorTheme.primary : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
    }

    @ViewBuilder
    private func content(height: CGFloat) -> some View {
        switch model.propertiesTab {
        case .clip:
            if model.selection == .none {
                placeholder(L("Select a clip, a zoom or an annotation to change it here."), symbol: "cursorarrow.click")
            } else {
                VideoSelectionInspector(model: model, maxHeight: max(height - 190, 200))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        case .effects:
            if let item = model.selectedLayerItem, item.role != .adjustment {
                ScrollView {
                    VideoEffectChain(model: model, item: item)
                        .padding(14)
                }
            } else {
                placeholder(L("Effects belong to clips above the main track. Select one, or drag an effect from Library ▸ Effects onto the timeline."), symbol: "sparkles")
            }
        case .captions:
            VideoCaptionsPanel(model: model)
                .frame(maxHeight: .infinity, alignment: .top)
        case .video:
            VStack(spacing: 0) {
                VideoSegmented(options: VideoEditorModel.InspectorTab.allCases.filter { $0 != .captions }.map { ($0, $0.title) },
                               selection: Binding(get: { model.inspectorTab == .captions ? .background : model.inspectorTab }, set: { model.inspectorTab = $0 }))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch model.inspectorTab {
                        case .background, .captions: VideoBackgroundInspector(model: model)
                        case .cursor: VideoCursorInspector(model: model)
                        case .zoom: VideoZoomInspector(model: model)
                        case .camera: VideoCameraInspector(model: model)
                        case .audio: VideoAudioInspector(model: model)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func placeholder(_ text: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(VideoEditorTheme.textTertiary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - At playhead

/// NOW PLAYING: the main track's clip, and what's showing above it; NEARBY:
/// what starts in the next ten seconds. Click one to select it.
struct VideoAtPlayhead: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock

    struct Row: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let track: String
        let detail: String
        let select: VideoEditorModel.Selection
    }

    var body: some View {
        let now = clock.time
        let playing = rows(at: now)
        let nearby = upcoming(after: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                VideoSectionLabel(L("Now playing"))
                if playing.isEmpty {
                    Text(L("Nothing at the playhead")).font(.system(size: 11.5)).foregroundStyle(VideoEditorTheme.textTertiary)
                }
                ForEach(playing) { row in rowView(row) }
                if !nearby.isEmpty {
                    VideoSectionLabel(L("Nearby")).padding(.top, 6)
                    ForEach(nearby) { row in rowView(row) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func rowView(_ row: Row) -> some View {
        Button {
            model.selection = row.select
        } label: {
            HStack(spacing: 8) {
                Image(systemName: row.symbol)
                    .font(.system(size: 11))
                    .frame(width: 16)
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.name).font(.system(size: 12, weight: .medium)).foregroundStyle(VideoEditorTheme.primary).lineLimit(1)
                    Text(row.track).font(.system(size: 10.5)).foregroundStyle(VideoEditorTheme.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(row.detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("\(row.name), \(row.track), \(row.detail)"))
    }

    private func rows(at time: Double) -> [Row] {
        var rows: [Row] = []
        if let segment = model.segment(atTimeline: time), let index = model.segments.firstIndex(where: { $0.id == segment.id }) {
            rows.append(Row(id: "clip-\(segment.id)", symbol: "film", name: L("Clip \(index + 1)"), track: VideoTrackNames.mainTrack,
                            detail: L("\(VideoEditorModel.format(max(segment.timelineEnd - time, 0))) left"), select: .clip(segment.id)))
        }
        for (track, item) in model.project.layerItems where item.isShowing(at: time) {
            rows.append(Row(id: "layer-\(item.id)", symbol: Self.symbol(item), name: item.name, track: VideoTrackNames.layer(track),
                            detail: L("\(VideoEditorModel.format(max(item.end - time, 0))) left"), select: .layer(item.id)))
        }
        return rows
    }

    private func upcoming(after time: Double) -> [Row] {
        var rows: [Row] = []
        for (index, segment) in model.segments.enumerated() where segment.timelineStart > time + 0.01 && segment.timelineStart - time <= 10 {
            rows.append(Row(id: "clip-\(segment.id)", symbol: "film", name: L("Clip \(index + 1)"), track: VideoTrackNames.mainTrack,
                            detail: L("in \(VideoEditorModel.format(segment.timelineStart - time))"), select: .clip(segment.id)))
        }
        for (track, item) in model.project.layerItems where item.at > time + 0.01 && item.at - time <= 10 {
            rows.append(Row(id: "layer-\(item.id)", symbol: Self.symbol(item), name: item.name, track: VideoTrackNames.layer(track),
                            detail: L("in \(VideoEditorModel.format(item.at - time))"), select: .layer(item.id)))
        }
        return Array(rows.prefix(4))
    }

    static func symbol(_ item: VideoLayerItem) -> String {
        if item.sticker != nil { return "face.smiling" }
        if item.role == .effect { return "sparkles" }
        if item.role == .adjustment { return "slider.horizontal.3" }
        if item.isText { return "textformat" }
        return item.isVideo ? "film" : "photo"
    }
}

/// The tracks' names in the LF Studios layout: the main track is A roll,
/// the tracks above it V2 · B roll, V3, V4…
enum VideoTrackNames {
    static var mainTrack: String { L("A roll") }
    static func layer(_ index: Int) -> String {
        index == 0 ? L("V2 · B roll") : L("V\(index + 2)")
    }
}

// MARK: - The effect chain

/// The clip's filter, adjustments and effects as cards, in the order
/// they're drawn: the effects' order is changed by dragging a card (one ⌘Z
/// step), each switched on or off.
struct VideoEffectChain: View {
    @ObservedObject var model: VideoEditorModel
    let item: VideoLayerItem
    @State private var dragging: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Drawn top to bottom. Drag a card to change the order."))
                .font(.system(size: 11))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if item.adjust != nil {
                fixedCard(L("Adjust"), symbol: "slider.horizontal.3", detail: L("Change it in Clip ▸ Adjust"))
            }
            if let filter = item.filter {
                fixedCard(filter.look?.title ?? L("Filter"), symbol: "camera.filters", detail: L("Change it in Clip ▸ Filter"))
            }
            let effects = item.effects ?? []
            ForEach(Array(effects.enumerated()), id: \.element.id) { index, effect in
                card(effect, index: index, count: effects.count)
                    .opacity(dragging == effect.id ? 0.4 : 1)
                    .onDrag {
                        dragging = effect.id
                        return NSItemProvider(object: effect.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.plainText], delegate: VideoEffectDrop(model: model, target: index, dragging: $dragging))
            }
            if effects.isEmpty {
                Text(L("No effects yet: drag one from Library ▸ Effects onto this clip, or click + on an effect there."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fixedCard(_ title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 16).foregroundStyle(VideoEditorTheme.textSecondary)
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(VideoEditorTheme.textPrimary)
            Spacer()
            Text(detail).font(.system(size: 10.5)).foregroundStyle(VideoEditorTheme.textTertiary).lineLimit(1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VideoEditorTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(VideoEditorTheme.cardStroke))
    }

    private func card(_ effect: VideoAppliedEffect, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .help(L("Drag to change the order"))
                Text(verbatim: "\(index + 1)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                Text(effect.kind.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(effect.isOn ? VideoEditorTheme.textPrimary : VideoEditorTheme.textTertiary)
                Spacer()
                Toggle("", isOn: Binding(get: { effect.isOn }, set: { on in
                    model.selection = .layer(item.id)
                    model.perform(.edit(.setEffectOn(effect.id, on)))
                }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(L("\(effect.kind.title) on"))
                Menu {
                    Button(L("Move Up")) { move(effect, to: index - 1) }.disabled(index == 0)
                    Button(L("Move Down")) { move(effect, to: index + 1) }.disabled(index == count - 1)
                    if item.role != .effect {
                        Divider()
                        Button(L("Remove")) {
                            model.selection = .layer(item.id)
                            model.perform(.edit(.removeEffect(effect.id)))
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(L("More for \(effect.kind.title)"))
            }
            VideoSliderRow(
                title: L("Strength"),
                value: Binding(get: { effect.intensity * 100 }, set: { value in
                    model.selection = .layer(item.id)
                    var effects = item.effects ?? []
                    guard let i = effects.firstIndex(where: { $0.id == effect.id }) else { return }
                    effects[i].intensity = value / 100
                    model.perform(.edit(.setEffects(effects)))
                }),
                range: 0...100, defaultValue: 60,
                format: { "\(Int($0.rounded())) %" },
                onEditingEnded: { model.endGesture() }
            )
            .disabled(!effect.isOn)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VideoEditorTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(VideoEditorTheme.cardStroke))
    }

    private func move(_ effect: VideoAppliedEffect, to index: Int) {
        model.selection = .layer(item.id)
        model.perform(.edit(.moveEffect(effect.id, index)))
    }
}

/// A card dropped on another: it takes that one's place (one ⌘Z step).
private struct VideoEffectDrop: DropDelegate {
    let model: VideoEditorModel
    let target: Int
    @Binding var dragging: UUID?

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil }
        guard let id = dragging, let item = model.selectedLayerItem else { return false }
        model.selection = .layer(item.id)
        return model.perform(.edit(.moveEffect(id, target)))
    }

    func dropExited(info: DropInfo) {}
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}
