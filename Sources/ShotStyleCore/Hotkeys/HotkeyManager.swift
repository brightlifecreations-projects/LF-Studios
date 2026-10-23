import AppKit
import KeyboardShortcuts

/// Registers all global keyboard shortcuts.
@MainActor
final class HotkeyManager {

    func register(captureEngine: CaptureEngine, historyManager: HistoryManager, openCommandCenter: @escaping () -> Void) {
        KeyboardShortcuts.removeAllHandlers()

        KeyboardShortcuts.onKeyDown(for: .shotstyleCaptureArea) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.startAreaCapture(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .shotstyleCaptureWindow) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.startWindowCapture(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .shotstyleCaptureFullscreenNative) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.captureFullscreen(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .shotstyleCaptureFullscreenFallback) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.captureFullscreen(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .shotstyleCaptureAllDisplays) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.captureAllDisplays(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .shotstyleCapturePreviousArea) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.capturePreviousArea(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .shotstyleCaptureTimed) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.startTimedCapture(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .shotstyleCaptureText) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine else { return }
            Task { await e.startOCRCapture(historyManager: historyManager) }
        }

        // Pressed again during a scrolling capture, this finishes it.
        KeyboardShortcuts.onKeyDown(for: .shotstyleCaptureScrolling) { [weak captureEngine, weak historyManager] in
            guard let e = captureEngine, let h = historyManager else { return }
            Task { await e.startScrollingCapture(historyManager: h) }
        }

        KeyboardShortcuts.onKeyDown(for: .shotstyleRecordArea) { [weak captureEngine] in
            guard let e = captureEngine else { return }
            Task { await e.startAreaRecording() }
        }

        KeyboardShortcuts.onKeyDown(for: .shotstyleRecordWindow) { [weak captureEngine] in
            guard let e = captureEngine else { return }
            Task { await e.startWindowRecording() }
        }

        KeyboardShortcuts.onKeyDown(for: .shotstyleRecordFullscreen) { [weak captureEngine] in
            guard let e = captureEngine else { return }
            Task { await e.startFullscreenRecording() }
        }

        // Always registered — CaptureEngine.stopRecording() shows a
        // "No recording in progress" toast when nothing is being recorded.
        KeyboardShortcuts.onKeyDown(for: .shotstyleStopRecording) { [weak captureEngine] in
            captureEngine?.stopRecording()
        }

        KeyboardShortcuts.onKeyDown(for: .shotstylePauseRecording) { [weak captureEngine] in
            captureEngine?.togglePauseRecording()
        }

        // Menu-bar-independent access: opens the command center even when a
        // crowded menu bar makes macOS hide the status icon.
        KeyboardShortcuts.onKeyDown(for: .shotstyleOpenCommandCenter) {
            openCommandCenter()
        }
    }

    static func resetDefaults() {
        KeyboardShortcuts.reset(ShotStyleShortcut.allNames)
    }
}
