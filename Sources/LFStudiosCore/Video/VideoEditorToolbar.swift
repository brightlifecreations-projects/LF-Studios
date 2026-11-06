import AppKit
import SwiftUI

// MARK: - Toolbar

struct VideoEditorToolbar: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        ZStack {
            VideoWindowDragArea()
            HStack(spacing: 10) {
                Color.clear.frame(width: 76, height: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.project.sourceURL.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VideoEditorTheme.textTertiary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.revealSource() }
                .onTapGesture { model.perform(.showProjectSettings) }
                .help(L("Click for Project Settings. Double-click to show the recording in Finder."))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: L("Project Settings…")) { model.perform(.showProjectSettings) }

                Spacer(minLength: 12)

                // LF Studios (new): one search for everything (⌘K).
                if VideoEditorStyle.current.isNew {
                    VideoSearchField(model: model)
                    Spacer(minLength: 12)
                }

                Button {
                    model.isCropping ? model.endCrop() : model.beginCrop()
                } label: {
                    Label(model.project.crop.isFull ? L("Crop") : L("Cropped"), systemImage: "crop")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(model.isCropping ? Color.accentColor.opacity(0.35) : VideoEditorTheme.ink.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(L("Crop the recording — trim away toolbars or empty space"))

                // Adapt to this ratio, Export all ratios (VideoRatioEditor.swift).
                VideoRatioButtons(model: model)
                VideoLayoutMenu()
                // An agent connected (CapCut style; the new layout: the status strip).
                if !VideoEditorStyle.current.isNew { VideoAgentDot() }

                HStack(spacing: 2) {
                    Button { model.undo() } label: {
                        Image(systemName: "arrow.uturn.backward").frame(width: 30, height: 28)
                    }
                    .buttonStyle(VideoToolButtonStyle())
                    .disabled(!model.canUndo)
                    .help(L("\(VideoEditDescription.undoTitle(model.undoLabel)) (⌘Z)"))
                    .accessibilityLabel(VideoEditDescription.undoTitle(model.undoLabel))
                    Button { model.redo() } label: {
                        Image(systemName: "arrow.uturn.forward").frame(width: 30, height: 28)
                    }
                    .buttonStyle(VideoToolButtonStyle())
                    .disabled(!model.canRedo)
                    .help(L("\(VideoEditDescription.redoTitle(model.redoLabel)) (⇧⌘Z)"))
                    .accessibilityLabel(VideoEditDescription.redoTitle(model.redoLabel))
                }
                .font(.system(size: 13, weight: .semibold))

                // LF Studios (new): Search is in the middle, the keys in
                // the status strip.
                if !VideoEditorStyle.current.isNew {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { model.isCommandPalettePresented = true }
                } label: {
                    Image(systemName: "command")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(VideoToolButtonStyle())
                .help(L("All commands (⌘K)"))
                .accessibilityLabel(L("Commands"))

                Button {
                    withAnimation(.easeOut(duration: 0.15)) { model.isShortcutsPresented = true }
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(VideoToolButtonStyle())
                .help(L("Keyboard shortcuts (?)"))
                .accessibilityLabel(L("Keyboard shortcuts"))
                }

                // Background exports (VideoExportJobs.swift).
                VideoExportToolbarStatus(model: model)

                Button {
                    withAnimation(.easeOut(duration: 0.15)) { model.isExportPresented = true }
                } label: {
                    Label(L("Export"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(VideoPrimaryButtonStyle())
                .help(L("Export (⌘E)"))
                .disabled(!model.isReady)
            }
            .padding(.trailing, 14)
        }
    }

    private var subtitle: String {
        let size = model.project.sourceSize
        var parts: [String] = [VideoEditorModel.timecode(model.timelineDuration)]
        if let settings = model.project.projectSettings {
            // Set in Project Settings: what the video is made at.
            parts.append(settings.resolution.title)
            parts.append("\(settings.frameRate) fps")
            if settings.colorSpace != .rec709 { parts.append(settings.colorSpace.title) }
            return parts.joined(separator: " · ")
        }
        if size.width > 0 { parts.append("\(Int(size.width))×\(Int(size.height))") }
        parts.append("\(Int(model.sourceFrameRate.rounded())) fps")
        return parts.joined(separator: " · ")
    }
}

/// The aspect ratio menu, with Fill the Frame, Adapt to This Ratio and
/// Export All Ratios… (under the player since 1.13.0).
struct VideoAspectMenu: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        Menu {
            ForEach(VideoDemoProject.AspectPreset.allCases) { preset in
                Button {
                    // Custom… asks again, to change its shape.
                    if preset == .custom { model.chooseCustomAspect() } else { model.setAspect(preset) }
                } label: {
                    // Custom… shows its shape once one is chosen.
                    let title = model.project.title(of: preset)
                    if preset == model.project.aspectPreset {
                        Label(L("\(title) — \(preset.detail)"), systemImage: "checkmark")
                    } else {
                        Text(L("\(title) — \(preset.detail)"))
                    }
                }
            }
            Divider()
            Toggle(L("Fill the Frame, Follow the Cursor"), isOn: Binding(
                get: { model.project.reframe },
                set: { on in model.setStyle { $0.reframe = on } }
            ))
            .disabled(!model.project.canReframe || (model.project.cursorSamples.isEmpty && !model.project.reframe))
            Divider()
            Button(L("Adapt to This Ratio")) { model.adaptToRatio() }
                .disabled(!model.isReady)
            Button(L("Export All Ratios…")) { model.exportAllRatios() }
                .disabled(model.project.ratiosToExport.count < 2 || !model.isReady)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.project.aspectPreset.symbol)
                Text(model.project.aspectTitle)
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.ink.opacity(0.06)))
        .help(L("Aspect ratio"))
    }
}

struct VideoNoticePill: View {
    let notice: VideoEditorNotice

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: notice.symbol)
                .font(.system(size: 11, weight: .bold))
            Text(notice.message)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .allowsHitTesting(false)
    }
}

/// The editor's latest message, pinned just above the export sheet so it
/// isn't lost under the dimming ("Copied", "Export cancelled"…).
struct VideoOverlayNotice: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        ZStack {
            if let notice = model.notice {
                VideoNoticePill(notice: notice)
                    .transition(.opacity)
            }
        }
        .offset(y: -42)
        .allowsHitTesting(false)
    }
}

/// In the export summary: says so when the export would be silent though
/// the recording has sound (and turns "Mute video" back off in one click).
struct VideoExportSoundWarning: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        if let warning = model.exportSoundWarning {
            HStack(alignment: .top, spacing: 8) {
                Label(warning, systemImage: "speaker.slash.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.yellow.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if model.project.audio.muted {
                    Button(L("Turn On")) {
                        model.setStyle { $0.audio.muted = false }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                    .help(L("Turn the video's sound back on"))
                }
            }
        }
    }
}
