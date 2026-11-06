import AppKit
import SwiftUI

// MARK: - Command palette

struct VideoCommandPalette: View {
    @ObservedObject var model: VideoEditorModel
    @State private var query: String

    /// `query`: what's typed when it opens (the Guide's picture).
    init(model: VideoEditorModel, query: String = "") {
        self.model = model
        _query = State(initialValue: query)
    }
    @State private var highlighted = 0
    /// Read once per opening (a file on disk), not on every keystroke.
    @State private var recent: [VideoDemoRecentExport]?
    @AppStorage("videoEditorTipsDismissed") private var tipsDismissed = false
    @FocusState private var focused: Bool

    struct Command: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let shortcut: String
        let action: () -> Void
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { model.isCommandPalettePresented = false }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(VideoEditorTheme.textSecondary)
                    TextField(VideoEditorStyle.current.isNew ? L("Search commands, media, clips, captions, markers") : L("Search commands"), text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .focused($focused)
                        .onSubmit { choose(rows.indices.contains(highlighted) ? rows[highlighted] : rows.first) }
                        .onChange(of: query) { _ in highlighted = 0 }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                Rectangle().fill(VideoEditorTheme.hairline).frame(height: 1)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            // LF Studios layout: each kind under its name.
                            if let group = row.groupStart {
                                VideoSectionLabel(group.title)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.top, index == 0 ? 4 : 10)
                                    .padding(.bottom, 2)
                            }
                            Button {
                                choose(row)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: row.symbol)
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(width: 20)
                                        .foregroundStyle(VideoEditorTheme.textSecondary)
                                    Text(row.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(VideoEditorTheme.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Spacer()
                                    Text(row.detail)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(VideoEditorTheme.textTertiary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(index == highlighted ? VideoEditorTheme.ink.opacity(0.08) : Color.clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { if $0 { highlighted = index } }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VideoEditorTheme.popover))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
            .shadow(color: VideoEditorTheme.shadow, radius: 30, y: 16)
            .padding(.top, 90)
        }
        .onAppear {
            focused = true
            recent = model.recentExports
        }
        .background(
            VideoArrowKeyCatcher { delta in
                guard !rows.isEmpty else { return }
                highlighted = min(max(highlighted + delta, 0), rows.count - 1)
            }
        )
    }

    private func run(_ command: Command?) {
        guard let command else { return }
        model.isCommandPalettePresented = false
        command.action()
    }

    /// One row of the list: a command, or (LF Studios layout) something
    /// found in the video.
    struct Row: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        /// The first row of its kind: its name goes above it.
        var groupStart: VideoGlobalSearch.Group?
        let command: Command?
        let result: VideoGlobalSearch.Result?
    }

    private var rows: [Row] {
        var rows = filtered.map { Row(id: $0.id, title: $0.title, detail: $0.shortcut, symbol: $0.symbol, command: $0, result: nil) }
        guard VideoEditorStyle.current.isNew, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return rows }
        if !rows.isEmpty { rows[0].groupStart = .commands }
        var last: VideoGlobalSearch.Group?
        for result in VideoGlobalSearch.results(query, in: model) {
            rows.append(Row(id: result.id, title: result.title, detail: result.detail, symbol: result.symbol,
                            groupStart: result.group == last ? nil : result.group, command: nil, result: result))
            last = result.group
        }
        return rows
    }

    private func choose(_ row: Row?) {
        guard let row else { return }
        if let command = row.command { return run(command) }
        guard let result = row.result else { return }
        model.isCommandPalettePresented = false
        VideoGlobalSearch.show(result.target, in: model)
    }

    private var filtered: [Command] {
        let search = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !search.isEmpty else { return commands }
        return commands.filter { $0.title.lowercased().contains(search) }
    }

    var commands: [Command] {
        [
            Command(id: "export", title: L("Export…"), symbol: "square.and.arrow.up", shortcut: "⌘E") { model.isExportPresented = true },
            Command(id: "play", title: model.isPlaying ? L("Pause") : L("Play"), symbol: "playpause.fill", shortcut: L("Space")) { model.togglePlay() },
            Command(id: "split", title: L("Split at Skimmer or Playhead"), symbol: "scissors", shortcut: "⌘B") { model.perform(.split) },
            Command(id: "zoom", title: L("Add Zoom at Playhead"), symbol: "plus.magnifyingglass", shortcut: "Z") { model.addZoom(at: model.clock.time) },
            Command(id: "auto", title: model.project.autoZoom ? L("Turn Off Auto-Zoom on Clicks") : L("Turn On Auto-Zoom on Clicks"), symbol: "sparkles", shortcut: "") { model.setAutoZoom(!model.project.autoZoom) },
            Command(id: "my-style", title: L("Apply My Style"), symbol: "wand.and.stars", shortcut: "⇧⌘Y") { model.applyMyStyle() },
            Command(id: "remove-zooms", title: L("Remove All Zooms"), symbol: "trash", shortcut: "") { model.removeAllZooms() },
            Command(id: "idle", title: L("Speed Up Idle Moments"), symbol: "hare", shortcut: "") { model.speedUpIdle() },
            Command(id: "crop", title: L("Crop the Recording…"), symbol: "crop", shortcut: "") { model.beginCrop() },
            Command(id: "text", title: L("Add Text"), symbol: "textformat", shortcut: "⌥T") { model.addOverlay(.text) },
            Command(id: "highlight", title: L("Add Highlight"), symbol: "rectangle.dashed", shortcut: "⌥H") { model.addOverlay(.highlight) },
            Command(id: "arrow", title: L("Add Arrow"), symbol: "arrow.up.right", shortcut: "⌥A") { model.addOverlay(.arrow) },
            Command(id: "blur", title: L("Add Blur"), symbol: "eye.slash", shortcut: "⌥B") { model.addOverlay(.blur) },
            Command(id: "find-private", title: L("Find Private Info…"), symbol: "eye.trianglebadge.exclamationmark", shortcut: "") { model.showPrivacyScan() },
            Command(id: "adapt-ratio", title: L("Adapt to This Ratio"), symbol: "wand.and.rays", shortcut: "") { model.adaptToRatio() },
            Command(id: "spotlight", title: L("Add Spotlight (Dim Around a Spot)"), symbol: VideoDemoOverlayEffectKind.spotlight.icon, shortcut: "") { model.addOverlay(.spotlight) },
            Command(id: "shuffle", title: L("Shuffle Background"), symbol: "dice", shortcut: "") { model.shuffleBackground() },
            Command(id: "full-frame", title: model.project.usesRawSourceFrame ? L("Show Background") : L("Full Frame (No Background)"), symbol: "rectangle.inset.filled", shortcut: "") {
                model.setStyle { $0.toggleBackground() }
            },
            Command(id: "save-look", title: L("Save This Look as My Style"), symbol: "checkmark.seal", shortcut: "") { model.saveStyleAsDefault() },
            Command(id: "reset-look", title: L("Reset to the LF Studios Look"), symbol: "arrow.counterclockwise", shortcut: "") { model.resetStyle() },
            Command(id: "copy-frame", title: L("Copy Current Frame"), symbol: "photo.on.rectangle", shortcut: "") { model.copyCurrentFrame() },
            Command(id: "undo", title: VideoEditDescription.undoTitle(model.undoLabel), symbol: "arrow.uturn.backward", shortcut: "⌘Z") { model.undo() },
            Command(id: "redo", title: VideoEditDescription.redoTitle(model.redoLabel), symbol: "arrow.uturn.forward", shortcut: "⇧⌘Z") { model.redo() },
        ] + VideoEditCommand.allCases.filter { ![.undo, .redo, .addText, .addArrow, .addHighlight, .addBlur].contains($0) }.map { command in
            Command(id: "command-\(command.rawValue)", title: command.title, symbol: command.symbol, shortcut: command.keys) { model.perform(command) }
        } + [
            Command(id: "start", title: L("Go to Start"), symbol: "backward.end.fill", shortcut: "⌘←") { model.seek(to: 0) },
            Command(id: "end", title: L("Go to End"), symbol: "forward.end.fill", shortcut: "⌘→") { model.seek(to: model.timelineDuration) },
            Command(id: "reveal", title: L("Show Recording in Finder"), symbol: "folder", shortcut: "") { model.revealSource() },
            Command(id: "start-over", title: L("Start Over from the Original Recording…"), symbol: "arrow.counterclockwise.circle", shortcut: "") { model.startOver() },
            Command(id: "shortcuts", title: L("Keyboard Shortcuts"), symbol: "keyboard", shortcut: "?") { model.isShortcutsPresented = true },
        ] + (tipsDismissed ? [Command(id: "tips", title: L("Show Editor Tips"), symbol: "lightbulb", shortcut: "") { tipsDismissed = false }] : [])
            + scriptCommands + recentCommands + cameraCommands + soundCommands + framingCommands + VideoDemoProject.AspectPreset.allCases.map { preset in
            Command(id: "aspect-\(preset.rawValue)", title: L("Aspect Ratio \(preset.title) — \(preset.detail)"), symbol: preset.symbol, shortcut: "") {
                model.setAspect(preset)
            }
        }
    }
}

extension VideoCommandPalette {
    /// Words, captions, and edit-by-text — each wherever it can work (typed
    /// captions need no sound).
    fileprivate var scriptCommands: [Command] {
        var commands: [Command] = []
        if model.hasAudio, model.captionTask == nil {
            commands.append(Command(id: "transcribe", title: model.hasTranscript ? L("Transcribe Again…") : L("Transcribe Narration (Captions, Edit by Text)"), symbol: "waveform", shortcut: "") {
                model.inspectorTab = .captions
                model.selection = .none
                model.transcribeAgain()
            })
        }
        if model.hasTranscript {
            commands.append(Command(id: "fillers", title: L("Remove Ums"), symbol: "wand.and.stars", shortcut: "") { model.perform(.reviewFillers) })
            commands.append(Command(id: "pauses", title: L("Shorten Pauses"), symbol: "forward.end", shortcut: "") { model.shortenPauses() })
            commands.append(Command(id: "find", title: L("Find in Transcript"), symbol: "magnifyingglass", shortcut: "⌘F") { model.findInTranscript() })
        }
        commands.append(Command(id: "caption-line", title: L("Add Caption Line at Playhead"), symbol: "captions.bubble", shortcut: "") {
            model.inspectorTab = .captions
            model.addCaptionAtPlayhead()
        })
        if !model.project.captions.isEmpty {
            commands.append(Command(id: "srt", title: L("Save Subtitles (.srt)…"), symbol: "doc.text", shortcut: "") { model.exportSRT() })
        }
        return commands
    }

    /// This recording's latest exports, shown in Finder.
    fileprivate var recentCommands: [Command] {
        (recent ?? model.recentExports).prefix(3).map { export in
            Command(id: "recent-\(export.id)", title: L("Show Recent Export “\(export.exportURL.lastPathComponent)” in Finder"), symbol: "clock.arrow.circlepath", shortcut: "") {
                model.revealExport(export.exportURL)
            }
        }
    }

    fileprivate var cameraCommands: [Command] {
        guard model.hasWebcamFootage else { return [] }
        return [
            Command(id: "camera-full", title: L("Full Camera at Playhead"), symbol: "person.crop.rectangle", shortcut: "") { model.addCameraLayout(.fullscreen) },
            Command(id: "camera-side", title: L("Camera Side by Side at Playhead"), symbol: "rectangle.split.2x1", shortcut: "") { model.addCameraLayout(.sideBySide) },
            Command(id: "camera-intro", title: L("Full-Camera Intro and Outro"), symbol: "person.crop.rectangle.stack", shortcut: "") { model.addCameraIntroOutro() },
        ]
    }

    fileprivate var soundCommands: [Command] {
        var commands: [Command] = []
        if model.hasAudio {
            commands.append(Command(id: "preview-mute", title: model.previewMuted ? L("Unmute the Preview") : L("Mute the Preview (the Export Keeps Its Sound)"), symbol: model.previewMuted ? "speaker.wave.2" : "speaker.slash", shortcut: "M") {
                model.togglePreviewMute()
            })
        }
        if model.canEnhanceVoice || model.project.audio.enhanceVoice {
            let on = model.project.audio.enhanceVoice
            commands.append(Command(id: "enhance", title: on ? L("Stop Enhancing Voice") : L("Enhance Voice"), symbol: "waveform.badge.plus", shortcut: "") {
                model.setStyle { $0.audio.enhanceVoice = !on }
            })
        }
        if model.project.canReframe, !model.project.cursorSamples.isEmpty || model.project.reframe {
            let on = model.project.reframe
            commands.append(Command(id: "reframe", title: on ? L("Letterbox Instead of Following the Cursor") : L("Fill the Frame, Follow the Cursor"), symbol: "rectangle.portrait.arrowtriangle.2.outward", shortcut: "") {
                model.setStyle { $0.reframe = !on }
            })
        }
        return commands
    }
}

/// Up/down arrows while a text field has focus (command palette).
struct VideoArrowKeyCatcher: NSViewRepresentable {
    let onMove: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onMove: onMove) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === view.window else { return event }
            switch event.keyCode {
            case 125: context.coordinator.onMove(1); return nil
            case 126: context.coordinator.onMove(-1); return nil
            default: return event
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMove = onMove
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }

    final class Coordinator {
        var onMove: (Int) -> Void
        var monitor: Any?
        init(onMove: @escaping (Int) -> Void) { self.onMove = onMove }
    }
}
