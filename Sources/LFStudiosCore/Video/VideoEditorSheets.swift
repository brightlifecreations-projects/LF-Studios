import AppKit
import SwiftUI

// MARK: - Shortcuts sheet

struct VideoShortcutsSheet: View {
    @ObservedObject var model: VideoEditorModel
    @AppStorage("videoEditorTipsDismissed") private var tipsDismissed = false
    @State private var customizing: Bool
    @State private var keymap = VideoKeymap.current

    init(model: VideoEditorModel, customizing: Bool = false) {
        self.model = model
        _customizing = State(initialValue: customizing)
    }

    /// Every key the editor answers to (VideoEditorModel.handleKey). Keys
    /// keep their symbols; only the ones with words are translated.
    static var groups: [(String, [(String, String)])] {
        [
            (L("Playback"), [(L("Space"), L("Play / pause")), ("J  K  L", L("Back · pause · faster")), ("← →", L("Previous / next frame")), ("⇧← ⇧→", L("Jump one second")), ("⌘← ⌘→", L("Start / end")), (L("Home  End"), L("Start / end")), ("M", L("Mute the preview (or the selected clip)")), ("⌘L", L("Loop playback: the In/Out range, the selected clip, or the whole video"))]),
            (L("Editing"), [("⌘B  C", L("Split at the skimmer, else the playhead")), ("⇧⌘B", L("Split all tracks at the skimmer, else the playhead")), ("A  B  T", L("Select tool · split tool · trim tool")), ("⌘D", L("Duplicate the selection right after itself")), (L("⌥-drag"), L("Copy a clip above the main track")), (L("Drag a cut"), L("Roll: both clips change, no gap")), ("⇧⌘V", L("Paste attributes")), ("⇧F", L("Reveal in Library")), (L("Drag empty space"), L("Select clips in a box (⇧ adds, ⌘ toggles)")), ("Q  W", L("Delete left / right of the playhead")), (L("⇧-drag"), L("Select a range to cut")), (L("⇧/⌘-click"), L("Select several items")), ("I  O", L("Mark in / out")), ("[  ]", L("Select left / right of the playhead")), ("V", L("Turn a clip on or off")), ("⌫", L("Delete selection")), ("⌘C  ⌘V", L("Copy / paste clips")), ("⌘G  ⇧⌘G", L("Group / ungroup")), ("⌥G  ⌥⇧G", L("Make compound clip / break apart")), ("⌥← ⌥→", L("Select previous / next item")), ("⌘Z  ⇧⌘Z", L("Undo / redo"))]),
            (L("Keyframes"), [("⌥K", L("Add keyframe")), ("⌥[  ⌥]", L("Previous / next keyframe"))]),
            (L("Zooms & annotations"), [("Z", L("Add zoom at playhead")), ("1 – 5", L("Zoom level (zoom selected)")), ("⌥T  ⌥H  ⌥A  ⌥B", L("Text · highlight · arrow · blur")), ("⌥⇧T", L("Text clip")), ("⌥Z", L("Zoom cut")), (L("Double-click"), L("Type in a text annotation"))]),
            (L("Timeline"), [("=  −", L("Show more / less detail")), ("⌘=  ⌘−", L("Show more / less detail")), ("⇧Z", L("Fit the whole video")), (L("⌘ scroll"), L("Zoom the timeline")), (L("Pointer over the timeline"), L("Zoom and ⌘B keep to the skimmer, else the playhead")), ("P", L("Main track magnet")), ("N", L("Auto snapping")), ("`", L("Linkage")), ("S", L("Preview axis")), ("⇧⌘A", L("Extract audio"))]),
            (L("General"), [("⌘E", L("Export")), ("⇧⌘Y", L("Apply my style")), ("⌘K", L("All commands")), ("⌘C", L("Copy current frame (nothing selected)")), ("⌘F", L("Find in the transcript")), ("?", L("This list")), (L("Esc"), L("Deselect / close"))]),
        ]
    }

    /// Your own keys (a preset's or changed) first: they replace the ones
    /// listed under them.
    private var groups: [(String, [(String, String)])] {
        let changed = VideoKeymap.editable.filter { $0.keys != $0.standardKeys }
        guard !changed.isEmpty else { return Self.groups }
        let yours = changed.map { ($0.keys.isEmpty ? L("None") : $0.keys, $0.title) }
        return [(L("Your keys (they replace the ones below)"), yours)] + Self.groups
    }

    /// The keys' column: 92 pt, wider only when a language's key names
    /// ("Double-click") need more.
    static var keyColumnWidth: CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        return max(92, TextFitting.widest(groups.flatMap { $0.1.map(\.0) }, font: font) + 4)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { model.isShortcutsPresented = false }
            // Two narrow columns; wider ones when longer descriptions (French,
            // German) wrap until the sheet is taller than the window, and a
            // scroll as the last resort.
            ViewThatFits(in: .vertical) {
                sheet(columnWidth: 280)
                sheet(columnWidth: 340)
                ScrollView { sheet(columnWidth: 340) }
            }
        }
    }

    private func sheet(columnWidth: CGFloat) -> some View {
        let keyWidth = Self.keyColumnWidth
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L("Keyboard Shortcuts"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Spacer()
                Button(customizing ? L("Done") : L("Customize…")) {
                    model.recordingShortcut = nil
                    customizing.toggle()
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .help(L("Change the timeline's keys, or use Final Cut Pro or Premiere Pro keys"))
                Button { model.isShortcutsPresented = false } label: {
                    Image(systemName: "xmark").frame(width: 26, height: 26)
                }
                .buttonStyle(VideoToolButtonStyle())
                .help(L("Close (Esc)"))
                .accessibilityLabel(L("Close"))
            }
            if customizing {
                VideoShortcutsEditor(model: model)
            } else {
            HStack(alignment: .top, spacing: 28) {
                ForEach(0..<2, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups.indices.filter { $0 % 2 == column }, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(groups[index].0.uppercased())
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(VideoEditorTheme.textTertiary)
                                ForEach(groups[index].1, id: \.0) { item in
                                    HStack {
                                        Text(item.0)
                                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(VideoEditorTheme.textPrimary)
                                            .frame(width: keyWidth, alignment: .leading)
                                        Text(item.1)
                                            .font(.system(size: 12))
                                            .foregroundStyle(VideoEditorTheme.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: columnWidth, alignment: .leading)
                }
            }
            }
            if tipsDismissed {
                Button(L("Show tips under the video again")) { tipsDismissed = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
            }
        }
        .frame(width: 2 * columnWidth + 28)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VideoEditorTheme.popover))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
        .shadow(color: VideoEditorTheme.shadow, radius: 30, y: 16)
        .onReceive(NotificationCenter.default.publisher(for: .lfstudiosKeymapChanged)) { _ in keymap = VideoKeymap.current }
    }
}

/// Under the preview of a narrated recording nobody has transcribed yet:
/// captions and edit-by-text are one click away (and easy to wave off).
struct VideoTranscribeSuggestion: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        // One line in a capsule; where this language's sentence is too long
        // for the window, it wraps in a rounded box instead.
        ViewThatFits(in: .horizontal) {
            suggestion(wraps: false)
            suggestion(wraps: true)
        }
        .padding(.horizontal, 12)
        .transition(.opacity)
    }

    private func suggestion(wraps: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "captions.bubble.fill")
                .foregroundStyle(VideoEditorTheme.caption)
                .accessibilityHidden(true)
            Text(L("Your narration can become captions — then cut the video by editing its words."))
                .foregroundStyle(VideoEditorTheme.textPrimary)
                .fixedSize(horizontal: !wraps, vertical: false)
            Button {
                model.inspectorTab = .captions
                model.selection = .none
                model.generateCaptions()
            } label: {
                Text(L("Transcribe"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(VideoEditorTheme.primary))
            }
            .buttonStyle(.plain)
            .help(L("Listens on this Mac — nothing is uploaded"))
            Button {
                withAnimation(.easeOut(duration: 0.2)) { model.dismissTranscriptSuggestion() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(VideoEditorTheme.textSecondary)
            .help(L("Not for this video"))
            .accessibilityLabel(L("Dismiss"))
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            if wraps {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(VideoEditorTheme.floatingPill)
            } else {
                Capsule().fill(VideoEditorTheme.floatingPill)
            }
        }
        .overlay {
            if wraps {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(VideoEditorTheme.caption.opacity(0.35), lineWidth: 1)
            } else {
                Capsule().strokeBorder(VideoEditorTheme.caption.opacity(0.35), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A video that couldn't be opened: what happened in plain words, and a
/// way on — another video, the file in Finder, or closing the window.
struct VideoLoadFailureView: View {
    @ObservedObject var model: VideoEditorModel
    let failure: VideoLoadFailure

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: failure.kind == .missing ? "questionmark.folder.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text(failure.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textPrimary)
            Text(model.project.sourceURL.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(failure.message)
                .font(.system(size: 12))
                .foregroundStyle(VideoEditorTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            HStack(spacing: 8) {
                Button(L("Close")) { model.closeEditor?() }
                    .buttonStyle(VideoSecondaryButtonStyle())
                if let reveal = revealURL {
                    Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([reveal]) }
                        .buttonStyle(VideoSecondaryButtonStyle())
                }
                Button(L("Open Another Video…")) {
                    guard let url = VideoDemoEditorWindowController.chooseVideo() else { return }
                    model.closeEditor?()
                    VideoDemoEditorWindowController.open(videoURL: url)
                }
                .buttonStyle(VideoPrimaryButtonStyle())
            }
            .padding(.top, 4)
            Text(failure.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(24)
    }

    /// The file itself, or the folder it was in.
    private var revealURL: URL? {
        let url = model.project.sourceURL
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let folder = url.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }
}
