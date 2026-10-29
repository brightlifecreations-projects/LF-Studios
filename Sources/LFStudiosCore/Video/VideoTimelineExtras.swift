import AppKit
import SwiftUI

// MARK: - VoiceOver

extension VideoEditorModel {
    /// What VoiceOver says for an intro or outro card on the timeline.
    func cardAccessibilityLabel(isIntro: Bool) -> String {
        let card = isIntro ? project.cards.intro : project.cards.outro
        let span = isIntro ? 0...(segments.first?.timelineStart ?? 0) : (segments.last?.timelineEnd ?? 0)...timelineDuration
        let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = Self.timecode(span.lowerBound)
        let end = Self.timecode(span.upperBound)
        switch (isIntro, title.isEmpty) {
        case (true, true): return L("Intro card, \(start) to \(end)")
        case (true, false): return L("Intro card “\(title)”, \(start) to \(end)")
        case (false, true): return L("Outro card, \(start) to \(end)")
        case (false, false): return L("Outro card “\(title)”, \(start) to \(end)")
        }
    }

    /// Opens a card's settings (Style), with the playhead on it.
    func showCardSettings(isIntro: Bool) {
        let span = isIntro ? 0...(segments.first?.timelineStart ?? 0) : (segments.last?.timelineEnd ?? 0)...timelineDuration
        selection = .none
        inspectorTab = .background
        seek(to: span.lowerBound + min(1, (span.upperBound - span.lowerBound) / 2))
    }

    /// What VoiceOver says for the music lane: what it is, then each of its
    /// settings as a phrase of its own.
    var musicAccessibilityLabel: String {
        guard let music = project.music else { return L("No music") }
        var parts = [L("Music “\(music.name)”"), L("\(Int((music.volume * 100).rounded()))% volume")]
        if music.ducking { parts.append(L("dips under your voice")) }
        if music.loops { parts.append(L("loops")) }
        return Self.spokenList(parts) + L(", \(Self.timecode(0)) to \(Self.timecode(timelineDuration))")
    }

    /// Opens the music's settings (Audio).
    func showMusicSettings() {
        selection = .none
        inspectorTab = .audio
    }
}

/// What the timeline shows beyond the recording's own lanes: the intro
/// and outro cards on the clip track, a marker on every cut (click to pick
/// its transition), where one recording hands over to the next, and the
/// music lane under the clips.
struct VideoTimelineExtrasLayer: View {
    let model: VideoEditorModel
    let geometry: VideoTimelineGeometry
    let clipTop: CGFloat
    /// Where the camera, music and sound rows are (VideoTimelineTracks.swift).
    let rows: VideoTimelineRowLayout

    private typealias M = VideoTimelineMetrics

    var body: some View {
        let project = model.project
        ZStack(alignment: .topLeading) {
            if project.cards.intro.enabled, let first = model.segments.first {
                cardBlock(project.cards.intro, isIntro: true, start: 0, end: first.timelineStart)
            }
            if project.cards.outro.enabled, let last = model.segments.last {
                cardBlock(project.cards.outro, isIntro: false, start: last.timelineEnd, end: model.timelineDuration)
            }
            let boundaries = project.sourceBoundaries(segments: model.segments)
            if !boundaries.isEmpty {
                VideoSourceBoundaryMarkers(boundaries: boundaries, geometry: geometry, clipTop: clipTop)
            }
            VideoTransitionMarkers(model: model, geometry: geometry, clipTop: clipTop)
            if let camera = project.importedCamera, let top = rows.contentTop(.camera) {
                let state = project.trackState(.camera)
                VideoCameraFootageLane(camera: camera, spans: model.cameraFootageSpans(offset: camera.offset), geometry: geometry, model: model)
                    .equatable()
                    .offset(y: top + (model.hasWebcamFootage && !project.cameraLayouts.isEmpty ? M.cameraLaneHeight + M.overlayLaneGap : 0))
                    .opacity(state.hidden ? 0.4 : 1)
                    .allowsHitTesting(!state.locked)
            }
            if let music = project.music, let top = rows.contentTop(.music) {
                VideoMusicLane(
                    music: music,
                    waveform: model.media.musicWaveform?.path == music.path ? model.media.musicWaveform?.waveform : nil,
                    duration: model.timelineDuration,
                    voice: music.ducking ? model.voiceTimelineRanges : [],
                    geometry: geometry,
                    model: model
                )
                .equatable()
                .offset(y: top)
                .opacity(project.trackState(.music).muted ? 0.45 : 1)
                .allowsHitTesting(!project.isTrackLocked(.music))
            }
            // Added sound files, a row each, under the music.
            ForEach(project.audioTracks, id: \.id) { track in
                if let top = rows.contentTop(.sound(track.id)) {
                    VideoExternalAudioLane(
                        track: track,
                        placed: track.placed(segments: model.segments, timelineDuration: model.timelineDuration),
                        selected: model.selectedAudioPiece?.track == track.id ? model.selectedAudioPiece?.piece : nil,
                        geometry: geometry,
                        model: model
                    )
                    .equatable()
                    .offset(y: top)
                    .allowsHitTesting(!project.isTrackLocked(.sound(track.id)))
                }
            }
        }
    }

    private func cardBlock(_ card: VideoTitleCard, isIntro: Bool, start: Double, end: Double) -> some View {
        let width = max(CGFloat(end - start) * geometry.pointsPerSecond - 2, 8)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [VideoEditorTheme.card.opacity(1), VideoEditorTheme.ink.opacity(0.1)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(VideoEditorTheme.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            if width > 46 {
                VStack(alignment: .leading, spacing: 2) {
                    Label(isIntro ? L("Intro") : L("Outro"), systemImage: "textformat.size")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    if width > 90, !card.title.isEmpty {
                        Text(card.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(VideoEditorTheme.textSecondary)
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, 8)
            }
        }
        .frame(width: width, height: M.clipTrackHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.showCardSettings(isIntro: isIntro) }
        .help(isIntro ? L("Intro card — click to edit it in Style") : L("Outro card — click to edit it in Style"))
        // VoiceOver: what it is, and what can be done with it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.cardAccessibilityLabel(isIntro: isIntro))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L("Opens its title and length in Style"))
        .accessibilityAction { model.showCardSettings(isIntro: isIntro) }
        .accessibilityAction(named: isIntro ? L("Remove Intro Card") : L("Remove Outro Card")) {
            if isIntro { model.setIntroEnabled(false) } else { model.setOutroEnabled(false) }
        }
        .offset(x: geometry.x(start) + 1, y: clipTop)
    }
}
