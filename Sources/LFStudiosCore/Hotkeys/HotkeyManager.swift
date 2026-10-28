import AppKit
import KeyboardShortcuts

/// Registers all global keyboard shortcuts.
@MainActor
final class HotkeyManager {

    func register(captureEngine: CaptureEngine, historyManager: HistoryManager, openCommandCenter: @escaping () -> Void) {
        KeyboardShortcuts.removeAllHandlers()

        KeyboardShortcuts.onKeyDown(for: .lfstudiosCaptureArea) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.startAreaCapture(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosCaptureWindow) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.startWindowCapture(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosCaptureFullscreenNative) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.captureFullscreen(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosCaptureFullscreenFallback) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.captureFullscreen(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosCaptureAllDisplays) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.captureAllDisplays(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosCapturePreviousArea) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.capturePreviousArea(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosCaptureTimed) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.startTimedCapture(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosCaptureText) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine else { return }
            Task { await e.startOCRCapture(historyManager: historyManager) }
        }

        // Pressed again during a scrolling capture, this finishes it.
        KeyboardShortcuts.onKeyDown(for: .lfstudiosCaptureScrolling) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.startScrollingCapture(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosRecordArea) { [weak captureEngine] in
            guard let e = captureEngine else { return }
            Task { await e.startAreaRecording() }
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosRecordWindow) { [weak captureEngine] in
            guard let e = captureEngine else { return }
            Task { await e.startWindowRecording() }
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosRecordFullscreen) { [weak captureEngine] in
            guard let e = captureEngine else { return }
            Task { await e.startFullscreenRecording() }
        }

        // Always registered — CaptureEngine.stopRecording() shows a
        // "No recording in progress" toast when nothing is being recorded.
        KeyboardShortcuts.onKeyDown(for: .lfstudiosStopRecording) { [weak captureEngine] in
            captureEngine?.stopRecording()
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosPauseRecording) { [weak captureEngine] in
            captureEngine?.togglePauseRecording()
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosAddMarker) { [weak captureEngine] in
            captureEngine?.addRecordingMarker()
        }

        KeyboardShortcuts.onKeyDown(for: .lfstudiosPauseSpeakerNotes) {
            SpeakerNotes.shared.toggleScrolling()
        }

        // Menu-bar-independent access: opens the command center even when a
        // crowded menu bar makes macOS hide the status icon.
        KeyboardShortcuts.onKeyDown(for: .lfstudiosOpenCommandCenter) {
            openCommandCenter()
        }
    }

    static func resetDefaults() {
        KeyboardShortcuts.reset(LFStudiosShortcut.allNames)
    }
}
