import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension VideoEditorTheme {
    static let addedAudio = Color(red: 0.26, green: 0.72, blue: 0.86)
}

/// An added sound file's lane: one block per piece (a synced piece shows
/// wherever the edit plays it). Drag a block to move it, its edges to trim
/// it; click to pick it (S splits, ⌫ deletes).
struct VideoExternalAudioLane: View, Equatable {
    let track: VideoExternalAudioTrack
    let placed: [VideoExternalAudioTrack.Placed]
    let selected: UUID?
    let geometry: VideoTimelineGeometry
    let model: VideoEditorModel

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.track == b.track && a.placed == b.placed && a.selected == b.selected && a.geometry == b.geometry
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(placed.enumerated()), id: \.offset) { _, piece in
                VideoExternalAudioBlock(track: track, piece: piece, isSelected: selected == piece.piece, geometry: geometry, model: model)
            }
        }
        .frame(width: geometry.width, height: VideoTimelineMetrics.musicLaneHeight, alignment: .topLeading)
    }
}

private struct VideoExternalAudioBlock: View {
    let track: VideoExternalAudioTrack
    let piece: VideoExternalAudioTrack.Placed
    let isSelected: Bool
    let geometry: VideoTimelineGeometry
    let model: VideoEditorModel
    @State private var drag: CGFloat = 0
    @State private var trim: (leading: Bool, width: CGFloat)?

    private var ref: VideoAudioPieceRef { VideoAudioPieceRef(track: track.id, piece: piece.piece) }

    var body: some View {
        let x = geometry.x(piece.timelineStart)
        let width = max(CGFloat(piece.timelineLength) * geometry.pointsPerSecond, 6)
        let leading = trim?.leading == true ? trim!.width : 0
        let trailing = trim?.leading == false ? trim!.width : 0
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(VideoEditorTheme.addedAudio.opacity(track.muted ? 0.1 : 0.24))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(VideoEditorTheme.addedAudio.opacity(isSelected ? 1 : 0.5), lineWidth: isSelected ? 2 : 1))
            .overlay(alignment: .leading) {
                if width > 60 {
                    Label(track.name, systemImage: track.useAsVoice ? "mic.fill" : (track.lockedToRecording ? "link" : "waveform"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.laneText(0.92))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            }
            .overlay(alignment: .leading) { edge(leading: true) }
            .overlay(alignment: .trailing) { edge(leading: false) }
            .frame(width: max(width - leading + trailing, 6), height: VideoTimelineMetrics.musicLaneHeight)
            .offset(x: x + drag + leading)
            .contentShape(Rectangle())
            .onTapGesture {
                model.selection = .none
                model.selectedAudioPiece = ref
                model.inspectorTab = .audio
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { drag = $0.translation.width }
                    .onEnded { value in
                        model.moveAudioPiece(ref, by: Double(value.translation.width / geometry.pointsPerSecond))
                        model.endGesture()
                        drag = 0
                    }
            )
            .help(L("“\(track.name)” — drag to move, drag an edge to trim, click to change it in Audio"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Added sound “\(track.name)”"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.selectedAudioPiece = ref }
    }

    private func edge(leading: Bool) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: 7)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { trim = (leading, $0.translation.width) }
                    .onEnded { value in
                        model.trimAudioPiece(ref, leading: leading, by: Double(value.translation.width / geometry.pointsPerSecond) * piece.speed)
                        model.endGesture()
                        trim = nil
                    }
            )
    }
}

/// Sound files dropped on the timeline: each becomes a track where it was dropped.
struct VideoAudioDrop: DropDelegate {
    let model: VideoEditorModel
    let geometry: VideoTimelineGeometry

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func performDrop(info: DropInfo) -> Bool {
        let time = max(geometry.time(info.location.x), 0)
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await withCheckedContinuation({ (done: CheckedContinuation<URL?, Never>) in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in done.resume(returning: url) }
                }), VideoExternalAudioTrack.fileExtensions.contains(url.pathExtension.lowercased()) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty { await model.addAudio(urls, at: time) }
        }
        return true
    }
}

/// Audio panel ▸ Added sound: Add audio…, and each track's settings.
struct VideoExternalAudioSection: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        VideoInspectorSection(L("Added sound")) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.project.audioTracks) { track in
                    trackCard(track)
                }
                Button {
                    model.chooseAudio()
                } label: {
                    Label(L("Add audio…"), systemImage: "waveform.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                Text(L("Each file is its own track: drag it on the timeline, trim its ends, split it with S. MP3, WAV, M4A, AAC, AIFF, FLAC, or CAF — or drop files on the timeline."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func trackCard(_ track: VideoExternalAudioTrack) -> some View {
        let selected = model.selectedAudioPiece?.track == track.id
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: track.useAsVoice ? "mic.fill" : "waveform")
                    .foregroundStyle(VideoEditorTheme.addedAudio)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.addedAudio.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(track.lockedToRecording ? L("Follows the recording") : L("On the edit's timeline"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button(L("Split at Playhead")) { model.splitAudioTrack(track.id) }
                    Divider()
                    Button(L("Remove Track"), role: .destructive) { model.removeAudioTrack(track.id) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 26, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(L("Track options"))
            }
            if !FileManager.default.fileExists(atPath: track.path) {
                Label(L("This sound file is gone — add it again."), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.orange)
            }
            HStack {
                Button {
                    Task { await model.syncAudioTrack(track.id) }
                } label: {
                    if model.isSyncingAudio == track.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L("Sync by sound"), systemImage: "waveform.badge.magnifyingglass")
                    }
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .disabled(!model.hasAudio || model.isSyncingAudio != nil)
                .help(L("Line it up with the recording's own sound; then it follows your cuts"))
                Spacer()
            }
            VideoSliderRow(
                title: L("Volume"),
                value: Binding(get: { track.volume }, set: { value in model.setAudioTrack(track.id) { $0.volume = value } }),
                range: VideoExternalAudioTrack.volumeRange,
                defaultValue: 1,
                format: { VideoEditorModel.formatPercent($0) },
                onEditingEnded: { model.endGesture() }
            )
            HStack(spacing: 12) {
                VideoSliderRow(
                    title: L("Fade in"),
                    value: Binding(get: { track.fadeIn }, set: { value in model.setAudioTrack(track.id) { $0.fadeIn = (value * 2).rounded() / 2 } }),
                    range: VideoExternalAudioTrack.fadeRange, defaultValue: nil,
                    format: { VideoEditorModel.formatTenths($0) }, onEditingEnded: { model.endGesture() }
                )
                VideoSliderRow(
                    title: L("Fade out"),
                    value: Binding(get: { track.fadeOut }, set: { value in model.setAudioTrack(track.id) { $0.fadeOut = (value * 2).rounded() / 2 } }),
                    range: VideoExternalAudioTrack.fadeRange, defaultValue: nil,
                    format: { VideoEditorModel.formatTenths($0) }, onEditingEnded: { model.endGesture() }
                )
            }
            VideoToggleRow(title: L("Mute"), detail: nil, isOn: Binding(get: { track.muted }, set: { value in model.setAudioTrack(track.id) { $0.muted = value } }))
            VideoToggleRow(
                title: L("Use as my voice"),
                detail: L("In place of the recording's microphone — Enhance voice and Podcast mode clean it up"),
                isOn: Binding(get: { track.useAsVoice }, set: { model.setUseAsVoice(track.id, $0) })
            )
            if !track.useAsVoice {
                VideoToggleRow(
                    title: L("Dip under voice"),
                    detail: L("Quieter while you talk"),
                    isOn: Binding(get: { track.dipUnderVoice }, set: { value in model.setAudioTrack(track.id) { $0.dipUnderVoice = value } })
                )
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(VideoEditorTheme.well))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(VideoEditorTheme.addedAudio.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
    }
}
