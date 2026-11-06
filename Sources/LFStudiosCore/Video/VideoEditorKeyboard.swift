import AppKit
import SwiftUI

// MARK: - Keyboard

struct VideoKeyboardBridge: NSViewRepresentable {
    let model: VideoEditorModel

    /// The editor's window, or one of its floating panels (1.18.0): the
    /// editor's keys work in each.
    static func belongs(_ window: NSWindow, to editor: NSWindow) -> Bool {
        window === editor || (window as? VideoFloatingPanelWindow)?.editor?.window === editor
    }

    /// A key pressed in `event`'s window (key: in front): the editor's,
    /// when it's the editor's window or one of its floating panels and no
    /// text is being typed. True: used.
    static func route(_ event: NSEvent, editor: NSWindow, isKey: Bool, model: VideoEditorModel) -> Bool {
        guard let window = event.window, isKey, belongs(window, to: editor) else { return false }
        // Typing while an agent edits: it waits for Resume (1.19.0).
        VideoAgentHub.shared.userTookOver(model)
        if let responder = window.firstResponder, responder is NSText || responder is NSTextField {
            // Esc leaves a text field (and closes the command
            // palette it belongs to); everything else types.
            if event.keyCode == 53 {
                window.makeFirstResponder(nil)
                if model.isCommandPalettePresented { model.isCommandPalettePresented = false }
                return true
            }
            return false
        }
        return model.handleKey(event)
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class Coordinator {
        private let model: VideoEditorModel
        private var monitor: Any?
        private var clickMonitor: Any?
        private weak var view: NSView?

        init(model: VideoEditorModel) {
            self.model = model
        }

        func install(on view: NSView) {
            self.view = view
            guard monitor == nil else { return }
            // Clicking anywhere outside the text being edited ends the
            // editing, so the editor's keys work again.
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] incoming in
                nonisolated(unsafe) let event = incoming
                MainActor.assumeIsolated {
                    // Clicking while an agent edits: it waits for Resume (1.19.0).
                    if let self, let editor = self.view?.window, let window = event.window, VideoKeyboardBridge.belongs(window, to: editor) {
                        VideoAgentHub.shared.userTookOver(self.model)
                    }
                }
                MainActor.assumeIsolated {
                    guard let self, let editor = self.view?.window, let window = event.window,
                          VideoKeyboardBridge.belongs(window, to: editor),
                          let responder = window.firstResponder as? NSView,
                          responder is NSText || responder is NSTextField,
                          // The command palette keeps its search field.
                          !self.model.isCommandPalettePresented else { return }
                    // A field's editor stands in for the field itself.
                    let editing: NSView = (responder as? NSText).flatMap { $0.isFieldEditor ? ($0.delegate as? NSView) : nil } ?? responder
                    let frame = window.contentView?.superview ?? window.contentView
                    let hit = frame?.hitTest(frame?.convert(event.locationInWindow, from: nil) ?? .zero)
                    if let hit, hit === editing || hit.isDescendant(of: editing) { return }
                    // Clicks in the box around the field (its padding) count too.
                    let box = editing.convert(editing.bounds, to: nil).insetBy(dx: -12, dy: -12)
                    if box.contains(event.locationInWindow) { return }
                    window.makeFirstResponder(nil)
                }
                return incoming
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] incoming in
                nonisolated(unsafe) let event = incoming
                let consumed: Bool = MainActor.assumeIsolated {
                    guard let self, let editor = self.view?.window else { return false }
                    return VideoKeyboardBridge.route(event, editor: editor, isKey: event.window?.isKeyWindow ?? false, model: self.model)
                }
                return consumed ? nil : incoming
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        }
    }
}

extension VideoEditorModel {
    /// Returns true when the key was handled.
    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let code = event.keyCode

        // Holding a key down doesn't repeat edits (a held ⌫ would delete
        // clip after clip, a held T stack up texts). Arrows, J/L, and the
        // timeline scale keys still repeat.
        if event.isARepeat, modifiers.isEmpty || modifiers == [.shift],
           [51, 117].contains(code) || ["a", "b", "z", "s", "c", "i", "o", "m", "q", "w", "p", "n", "v", "`", "[", "]", " ", "1", "2", "3", "4", "5", "?"].contains(key) {
            return true
        }

        // A new key being picked for a command (VideoKeymap.swift).
        if recordingShortcut != nil {
            recordShortcut(event)
            return true
        }

        // Modal surfaces first. Undo never reaches the edit behind them.
        let isUndoKey = key == "z" && (modifiers == [.command] || modifiers == [.command, .shift])
        if isPrivacyPresented {
            // Escape closes it (a scan keeps going); typing reaches its word list.
            if code == 53 {
                closePrivacyScan()
                return true
            }
            return isUndoKey
        }
        if isHandoffPresented {
            // Escape closes the dialog; a running handoff keeps going.
            if code == 53 {
                closeCreativeHandoff()
                return true
            }
            // Like the export dialog: its own buttons get Return, Tab, Space, arrows.
            if [36, 76, 48, 49, 123, 124, 125, 126].contains(code) { return false }
            return modifiers.isEmpty || isUndoKey
        }
        if isExportPresented {
            if code == 53, !isExporting {
                closeExportSheet()
                return true
            }
            // Return presses the sheet's default button; Tab, Space, and the
            // arrows move through and press its controls.
            if [36, 76, 48, 49, 123, 124, 125, 126].contains(code) { return false }
            return modifiers.isEmpty || isUndoKey
        }
        if isCommandPalettePresented || isShortcutsPresented || isProjectSettingsPresented || fillerReview != nil || isPasteAttributesPresented || sourceViewer != nil {
            if code == 53 {
                isCommandPalettePresented = false
                isShortcutsPresented = false
                isProjectSettingsPresented = false
                isPasteAttributesPresented = false
                sourceViewer = nil
                fillerPreview?.cancel()
                fillerReview = nil
                return true
            }
            // Return presses Done (or Remove); Tab and Space reach the ticks.
            if isProjectSettingsPresented || fillerReview != nil || isPasteAttributesPresented || sourceViewer != nil, [36, 76, 48, 49, 123, 124, 125, 126].contains(code) { return false }
            return isUndoKey
        }

        // Esc leaves an open compound clip (1.16.0).
        if openCompound != nil, code == 53, !isCropping, timelineTool == .select {
            closeCompound()
            return true
        }

        if isCropping {
            switch code {
            case 53: cancelCrop(); return true
            case 36, 76: endCrop(); return true
            default:
                if modifiers == [.command], key == "z" { undo(); return true }
                if modifiers == [.command, .shift], key == "z" { redo(); return true }
                return modifiers.isEmpty
            }
        }

        // The timeline's commands (VideoEditCommands.swift).
        if let command = VideoEditCommand.command(key: key, modifiers: modifiers) {
            perform(command)
            return true
        }

        switch (modifiers, key) {
        case ([.command], "z"): undo(); return true
        case ([.command, .shift], "z"): redo(); return true
        case ([.command], "k"):
            withAnimation(.easeOut(duration: 0.15)) { isCommandPalettePresented = true }
            return true
        case ([.command, .shift], "y"): applyMyStyle(); return true
        case ([.command], "e"):
            withAnimation(.easeOut(duration: 0.15)) { isExportPresented = true }
            return true
        case ([.command], "f"): findInTranscript(); return true
        case ([.command], "="), ([.command], "+"): zoomTimeline(by: 1.4); return true
        case ([.command], "-"): zoomTimeline(by: 1 / 1.4); return true
        default: break
        }

        // Arrows / Home / End.
        switch code {
        case 123: // ←
            if modifiers == [.command] { seek(to: 0) } else if modifiers == [.shift] { jump(by: -1) } else if modifiers == [.option] { selectAdjacentItem(forward: false) } else if modifiers.isEmpty { step(frames: -1) } else { return false }
            return true
        case 124: // →
            if modifiers == [.command] { seek(to: timelineDuration) } else if modifiers == [.shift] { jump(by: 1) } else if modifiers == [.option] { selectAdjacentItem(forward: true) } else if modifiers.isEmpty { step(frames: 1) } else { return false }
            return true
        case 115: seek(to: 0); return true
        case 119: seek(to: timelineDuration); return true
        case 51, 117:
            guard modifiers.isEmpty || modifiers == [.command] else { return false }
            deleteSelection()
            return true
        case 53:
            // Full-screen preview first, the split tool, then the
            // selection, then playback.
            if isPlayerFullScreen { isPlayerFullScreen = false } else if timelineTool != .select { timelineTool = .select } else if selection != .none { selection = .none } else if isPlaying { pause() }
            return true
        default:
            break
        }

        guard modifiers.isEmpty || (modifiers == [.shift] && key == "?") else { return false }
        if event.characters == "?" {
            withAnimation(.easeOut(duration: 0.15)) { isShortcutsPresented = true }
            return true
        }

        switch key {
        case " ": togglePlay()
        case "c": perform(.split)
        case "z": addZoom(at: clock.time)
        case "j": shuttleBackward()
        case "k": pause()
        case "l": shuttleForward()
        case "m":
            guard hasAudio else {
                showNotice(L("This recording has no sound"), symbol: "speaker.slash")
                return true
            }
            if let id = selectedClipID, let clip = project.timelineClips.first(where: { $0.id == id }) {
                setClipMuted(id, !clip.muted)
            } else {
                togglePreviewMute()
            }
        case "=", "+": zoomTimeline(by: 1.4)
        case "-": zoomTimeline(by: 1 / 1.4)
        case "1", "2", "3", "4", "5":
            guard let id = selectedZoomID else { return false }
            let levels = ["1": 1.25, "2": 1.5, "3": 2.0, "4": 2.5, "5": 3.0]
            if let level = levels[key] { updateZoom(id) { $0.scale = level } }
        default:
            return false
        }
        return true
    }

    var isExporting: Bool {
        if case .running = exportPhase { return true }
        return false
    }
}
