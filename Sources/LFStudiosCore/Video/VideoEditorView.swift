import AppKit
import SwiftUI

struct VideoEditorRootView: View {
    @ObservedObject var model: VideoEditorModel
    @AppStorage("videoEditorTipsDismissed") private var tipsDismissed = false
    /// The divider between the preview and the timeline, once dragged
    /// (nil: where it starts for this window, VideoEditorLayout).
    @State private var chosenFraction = Settings.videoTimelineFraction
    /// The Library, player and Properties widths (VideoEditorPanels.swift).
    @ObservedObject private var panels = VideoEditorPanelStore.shared
    /// Where the panels were when a border drag began.
    @State private var panelDragStart: VideoEditorPanelLayout?
    /// A panel dragged by its header (1.18.0).
    @StateObject private var dock: VideoDockDrag

    init(model: VideoEditorModel, dock: VideoDockDrag? = nil) {
        self.model = model
        _dock = StateObject(wrappedValue: dock ?? VideoDockDrag())
    }

    var body: some View {
        GeometryReader { proxy in
            editor(height: proxy.size.height, width: proxy.size.width)
                // Full-screen preview: the window goes full screen with it.
                .onChange(of: model.isPlayerFullScreen) { on in
                    // The editor's window, even from a floating player.
                    guard let window = dock.window ?? NSApp.keyWindow else { return }
                    if window.styleMask.contains(.fullScreen) != on { window.toggleFullScreen(nil) }
                }
                // Layout ▸ Reset Layout: the timeline where it starts, too.
                .onReceive(NotificationCenter.default.publisher(for: .lfstudiosEditorLayoutReset)) { _ in chosenFraction = nil }
                // A saved layout: its timeline height.
                .onReceive(NotificationCenter.default.publisher(for: .lfstudiosEditorLayoutApplied)) { note in
                    chosenFraction = note.userInfo?["fraction"] as? Double
                }
                // Small tracks on a short window, until one is chosen.
                .onAppear { model.fitTrackHeight(windowHeight: proxy.size.height) }
                .onChange(of: proxy.size.height) { model.fitTrackHeight(windowHeight: $0) }
        }
        .background(VideoEditorTheme.window)
        // A new look (Layout menu): everything drawn again in it.
        .id(panels.style)
        .background(VideoKeyboardBridge(model: model).frame(width: 0, height: 0))
        .ignoresSafeArea()
        .task { await model.load() }
    }

    private var playerArea: some View { VideoPlayerPanel(model: model) }
}

/// The player: the picture tools, the preview, and the notes under it
/// (docked or floating, 1.18.0).
struct VideoPlayerPanel: View {
    @ObservedObject var model: VideoEditorModel
    @AppStorage("videoEditorTipsDismissed") private var tipsDismissed = false

    /// The crop bar and the tips sit under the picture, never over it.
    private var stageBottomInset: CGFloat {
        if model.isCropping { return 66 }
        if VideoEditorStyle.current.isNew { return model.suggestsTranscript ? 58 : 16 }
        return tipsDismissed && !model.suggestsTranscript ? 22 : 58
    }

    var body: some View {
        ZStack(alignment: .top) {
            VideoEditorTheme.stage
            VStack(spacing: 0) {
                // The picture tools, centered above the preview.
                if !model.isCropping {
                    // A narrow player (the smallest window, wide side
                    // panels): the tools as symbols.
                    ViewThatFits(in: .horizontal) {
                        VideoToolDock(model: model)
                        VideoToolDock(model: model, compact: true)
                    }
                    // LF Studios (new): a strip along the monitor's top.
                    .frame(maxWidth: VideoEditorStyle.current.isNew ? .infinity : nil, alignment: .leading)
                    .padding(.horizontal, VideoEditorStyle.current.isNew ? 8 : 12)
                    .padding(.top, VideoEditorStyle.current.isNew ? 6 : 12)
                }
                VideoStageView(model: model)
                    .padding(.horizontal, 28)
                    .padding(.top, model.isCropping ? 22 : 12)
                    .padding(.bottom, stageBottomInset)
            }
            // Vertical videos: the phone overlay's button, above
            // the preview on the right.
            if model.canShowPhoneOverlay, !model.isCropping {
                VideoPhoneOverlayButton(model: model)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 16)
                    .padding(.trailing, 20)
            }
            // With the export sheet up, the message shows on the
            // sheet instead (see VideoOverlayNotice).
            // Reversing a clip, recording a voiceover (1.14.0).
            VStack(spacing: 8) {
                VideoShortcutsChangedNotice()
                VideoPanelTipNotice()
                VideoGenerationPill(model: model)
                VideoVoiceoverPill(model: model)
            }
            // Under a notice that's showing, not on it.
            .padding(.top, model.notice != nil && !model.isExportPresented ? 132 : 80)
            if let notice = model.notice, !model.isExportPresented {
                VideoNoticePill(notice: notice)
                    .padding(.top, model.isCropping ? 12 : 80)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            VStack {
                Spacer()
                if model.isCropping {
                    VideoCropBar(model: model)
                        .padding(.bottom, 12)
                } else if model.suggestsTranscript {
                    VideoTranscribeSuggestion(model: model)
                        .padding(.bottom, 10)
                } else if !VideoEditorStyle.current.isNew {
                    // LF Studios (new): the keys are in the status strip.
                    VideoTipsBar()
                        .padding(.bottom, 10)
                }
            }
        }
        // Nothing reaches over the Library or Properties.
        .clipped()
        // Files dropped on the player go in at the playhead (videos at
        // the end).
        .onDrop(of: [.fileURL, .plainText], delegate: VideoMediaDrop(model: model) { _ in (nil, .layer(.automatic)) })
    }
}

extension VideoEditorRootView {

    /// A border between panels dragged by `delta`: the Library's (left)
    /// or Properties' (right), kept in range (VideoEditorPanelLayout).
    private func dragBorder(library: Bool, by delta: CGFloat, done: Bool, width: CGFloat) {
        let start = panelDragStart ?? panels.layout
        if panelDragStart == nil { panelDragStart = start }
        var moved = start
        let fitted = start.fitted(windowWidth: width)
        if library {
            moved.library = min(max(fitted.library + delta, VideoEditorPanelLayout.libraryRange.lowerBound), min(VideoEditorPanelLayout.libraryRange.upperBound, fitted.library + fitted.player - VideoEditorPanelLayout.minimumPlayer))
        } else {
            moved.properties = min(max(fitted.properties - delta, VideoEditorPanelLayout.propertiesRange.lowerBound), min(VideoEditorPanelLayout.propertiesRange.upperBound, fitted.properties + fitted.player - VideoEditorPanelLayout.minimumPlayer))
        }
        panels.set(moved, remember: done)
        if done { panelDragStart = nil }
    }

    /// CapCut style: exactly 1.16.0's editor.
    private func capCutEditor(height: CGFloat, width: CGFloat, widths: (library: CGFloat, player: CGFloat, properties: CGFloat)) -> some View {
    VStack(spacing: 0) {
        VideoEditorToolbar(model: model)
            .frame(height: 52)
        Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
        HStack(spacing: 0) {
            VideoLibraryPanel(model: model)
                .frame(width: widths.library)
                .dockPanel(.library, dock: dock, permanent: false)
            VideoPanelBorder(
                moved: { delta, done in dragBorder(library: true, by: delta, done: done, width: width) },
                reset: { panels.set(VideoEditorPanelLayout(library: VideoEditorPanelLayout.standard.library, properties: panels.layout.properties), remember: true) }
            )
            VStack(spacing: 0) {
                playerArea
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                VideoPlayerBar(model: model, clock: model.clock)
                    .background(VideoEditorTheme.panel)
            }
            .frame(width: widths.player)
            .dockPanel(.player, dock: dock, permanent: false)
            VideoPanelBorder(
                moved: { delta, done in dragBorder(library: false, by: delta, done: done, width: width) },
                reset: { panels.set(VideoEditorPanelLayout(library: panels.layout.library, properties: VideoEditorPanelLayout.standard.properties), remember: true) }
            )
            // Properties: the selected thing's settings (the panels
            // that were the inspector).
            VideoInspectorView(model: model)
                .frame(width: widths.properties)
                .dockPanel(.properties, dock: dock, permanent: false)
        }
        VideoTimelineDivider(
            fraction: VideoEditorLayout.fraction(chosen: chosenFraction, windowHeight: height),
            windowHeight: height,
            moved: { fraction, done in
                chosenFraction = fraction
                if done { Settings.videoTimelineFraction = fraction }
            },
            reset: {
                chosenFraction = nil
                Settings.videoTimelineFraction = nil
            }
        )
        VideoTimelineView(model: model).equatable()
            .frame(height: timelineHeight(windowHeight: height))
            .dockPanel(.timeline, dock: dock, permanent: false)
    }
    }

    /// LF Studios (new): tools down the left, the Library, the Program
    /// monitor and Properties across the top, the timeline, a status strip.
    private func newEditor(height: CGFloat, width: CGFloat) -> some View {
        let widths = panels.layout.fitted(windowWidth: width - VideoEditorNewMetrics.railWidth - 1)
        return VStack(spacing: 0) {
            VideoEditorToolbar(model: model)
                .frame(height: 44)
            Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            HStack(spacing: 0) {
                VideoToolRail(model: model)
                Rectangle().fill(VideoEditorTheme.hairline).frame(width: 1)
                VideoLibraryPanel(model: model)
                    .frame(width: widths.library)
                    .dockPanel(.library, dock: dock, permanent: false)
                VideoPanelBorder(
                    moved: { delta, done in dragBorder(library: true, by: delta, done: done, width: width - VideoEditorNewMetrics.railWidth - 1) },
                    reset: { panels.set(VideoEditorPanelLayout(library: VideoEditorPanelLayout.standard.library, properties: panels.layout.properties), remember: true) }
                )
                VStack(spacing: 0) {
                    playerArea
                    Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                    VideoPlayerBar(model: model, clock: model.clock)
                        .background(VideoEditorTheme.panel)
                }
                .frame(width: widths.player)
                .dockPanel(.player, dock: dock, permanent: false)
                VideoPanelBorder(
                    moved: { delta, done in dragBorder(library: false, by: delta, done: done, width: width - VideoEditorNewMetrics.railWidth - 1) },
                    reset: { panels.set(VideoEditorPanelLayout(library: panels.layout.library, properties: VideoEditorPanelLayout.standard.properties), remember: true) }
                )
                VideoPropertiesPanel(model: model)
                    .frame(width: widths.properties)
                    .dockPanel(.properties, dock: dock, permanent: false)
            }
            VideoTimelineDivider(
                fraction: VideoEditorLayout.fraction(chosen: chosenFraction, windowHeight: height),
                windowHeight: height,
                moved: { fraction, done in
                    chosenFraction = fraction
                    if done { Settings.videoTimelineFraction = fraction }
                },
                reset: {
                    chosenFraction = nil
                    Settings.videoTimelineFraction = nil
                }
            )
            VideoTimelineView(model: model).equatable()
                .frame(height: max(timelineHeight(windowHeight: height) - VideoEditorNewMetrics.statusHeight - 1, 120))
                .dockPanel(.timeline, dock: dock, permanent: false)
            Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            VideoStatusStrip(model: model)
        }
    }

    /// Panels moved (1.18.0): each with its header, where the arrangement
    /// puts them; the toolbar on top, and in the new layout the tools down
    /// the left and the status strip along the bottom.
    private func dockedEditor() -> some View {
        VStack(spacing: 0) {
            VideoEditorToolbar(model: model)
                .frame(height: panels.style.isNew ? 44 : 52)
            Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
            HStack(spacing: 0) {
                if panels.style.isNew {
                    VideoToolRail(model: model)
                    Rectangle().fill(VideoEditorTheme.hairline).frame(width: 1)
                }
                VideoDockArea(node: panels.arrangement.docked, model: model, dock: dock)
            }
            if panels.style.isNew {
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                VideoStatusStrip(model: model)
            }
        }
    }

    private func editor(height: CGFloat, width: CGFloat) -> some View {
        let widths = panels.layout.fitted(windowWidth: width)
        return ZStack {
            if model.isPlayerFullScreen {
                // Full-screen preview: the player alone (Esc leaves).
                VStack(spacing: 0) {
                    playerArea
                    VideoPlayerBar(model: model, clock: model.clock)
                }
                .background(VideoEditorTheme.stage)
            } else {
            Group {
                if !panels.arrangement.isStandard {
                    dockedEditor()
                } else if panels.style.isNew {
                    newEditor(height: height, width: width)
                } else {
                    capCutEditor(height: height, width: width, widths: widths)
                }
            }
            // Behind a sheet or the palette, VoiceOver stays in front.
            .accessibilityHidden(model.hasOverlayOpen || !model.isReady)
            // Where a dragged panel would land.
            VideoDockDropZone(dock: dock)
            }

            if model.isExportPresented {
                VideoExportSheet(model: model)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
            }
            if model.isPrivacyPresented {
                VideoPrivacySheet(model: model)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
            }
            if model.isHandoffPresented {
                VideoHandoffSheet(model: model)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
            } else if let job = model.handoffJob {
                // Closed while it's writing: its progress, bottom left.
                VStack {
                    Spacer()
                    HStack {
                        VideoHandoffPill(job: job, model: model)
                        Spacer()
                    }
                }
                .padding(.leading, 18)
                .padding(.bottom, timelineHeight(windowHeight: height) + 14)
            }
            if model.isCommandPalettePresented {
                VideoCommandPalette(model: model)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityLabel(L("Commands"))
            }
            if model.isShortcutsPresented {
                VideoShortcutsSheet(model: model)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
            }
            if model.isProjectSettingsPresented {
                VideoProjectSettingsSheet(model: model)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
            }
            if model.fillerReview != nil {
                VideoFillerReviewSheet(model: model)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
            }
            if model.isPasteAttributesPresented {
                VideoModalCard(close: { model.isPasteAttributesPresented = false }) { VideoPasteAttributesSheet(model: model) }
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
            }
            if let frame = model.sourceViewer {
                VideoModalCard(close: { model.sourceViewer = nil }) { VideoSourceViewer(model: model, frame: frame) }
                    .transition(.opacity)
                    .accessibilityAddTraits(.isModal)
            }
            if !model.isReady {
                loadingOverlay
                    .accessibilityAddTraits(.isModal)
            }
        }
        // Panels' frames, measured in the editor (docking, 1.18.0).
        .coordinateSpace(name: VideoDockDrag.space)
        .onPreferenceChange(VideoDockFramesKey.self) { frames in
            MainActor.assumeIsolated { dock.frames = frames }
        }
        .background(GeometryReader { proxy in
            let room = proxy.frame(in: .global)
            Color.clear
                .onAppear { dock.room = room }
                .onChange(of: room) { dock.room = $0 }
        })
    }

    /// Where the divider puts it (remembered on this Mac), kept so that
    /// the preview and the timeline stay usable (VideoEditorLayout).
    private func timelineHeight(windowHeight: CGFloat) -> CGFloat {
        VideoEditorLayout.timelineHeight(windowHeight: windowHeight, fraction: VideoEditorLayout.fraction(chosen: chosenFraction, windowHeight: windowHeight))
    }

    private var loadingOverlay: some View {
        ZStack {
            VideoEditorTheme.window.opacity(0.92)
            VStack(spacing: 12) {
                if let failure = model.loadFailure {
                    VideoLoadFailureView(model: model, failure: failure)
                } else if let error = model.loadError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.yellow)
                    Text(L("Couldn't open this video"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                    Text(L("Preparing your video…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                }
            }
        }
    }
}
