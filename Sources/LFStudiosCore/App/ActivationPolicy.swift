import AppKit

@MainActor
extension NSApplication {
    func restoreBackgroundOnlyActivationPolicyIfNeeded(excluding closingWindow: NSWindow? = nil) {
        // A capture overlay closed: the Home window comes back.
        defer { HomeWindowController.returnAfterCapture() }
        // Never drop to background while an editor is open (even minimized) — it must keep its
        // Dock icon / ⌘-Tab entry so the user can return to it. See `LFStudiosEditorActivation`.
        if VideoDemoEditorWindowController.hasOpenEditors || AnnotationWindowController.hasOpenEditors {
            // Transient UI (menu, capture overlay, a panel) may have run in
            // the meantime — make sure the editors kept their Dock presence.
            LFStudiosEditorActivation.sync()
            return
        }
        // Stopping a recording holds the foreground for the editor about to
        // open; dropping to background here would hand focus back to the
        // recorded app and macOS won't give it back.
        if LFStudiosEditorActivation.isHoldingForeground {
            return
        }

        guard !hasVisiblePersistentWindow(excluding: closingWindow) else {
            return
        }

        // LF Studios is a regular app (Dock icon, ⌘-Tab) and stays one; with
        // nothing left on screen it steps back so the app the user came from
        // gets focus again.
        if isActive { deactivate() }
    }

    /// Makes sure LF Studios can come to the front for transient UI (menu,
    /// capture overlay, panels): it always runs as a regular app. For a
    /// capture, the Home window steps aside first: activating LF Studios would
    /// otherwise bring it in front of what the user is about to capture.
    func ensureForegroundCapable(forCapture: Bool = false) {
        if forCapture {
            HomeWindowController.stepAsideForCapture()
        }
        if activationPolicy() != .regular {
            setActivationPolicy(.regular)
        }
    }

    private func hasVisiblePersistentWindow(excluding closingWindow: NSWindow?) -> Bool {
        windows.contains { window in
            if let closingWindow, window === closingWindow {
                return false
            }

            guard window.isVisible, !window.isMiniaturized else {
                return false
            }

            if window is PinnedWindow {
                return true
            }

            let persistentMasks: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
            return !window.styleMask.intersection(persistentMasks).isEmpty
        }
    }
}


/// Keeps LF Studios a regular app (Dock icon + ⌘-Tab) and holds the foreground
/// between pressing Stop and the video editor opening.
@MainActor
enum LFStudiosEditorActivation {
    /// Set between pressing Stop and the editor opening.
    private(set) static var isHoldingForeground = false

    static func sync() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    /// Called at the moment the user acts (e.g. presses Stop) when an
    /// editor will open shortly: macOS only lets an app take focus right
    /// after the user interacts with it, not a second later.
    static func holdForeground() {
        isHoldingForeground = true
        sync()
        activateApp()
    }

    /// The editor opened (or won't): back to normal policy rules.
    static func releaseForeground() {
        guard isHoldingForeground else { return }
        isHoldingForeground = false
        if VideoDemoEditorWindowController.hasOpenEditors || AnnotationWindowController.hasOpenEditors {
            sync()
        } else {
            // No editor after all (the save failed): step back when nothing
            // is on screen.
            NSApp.restoreBackgroundOnlyActivationPolicyIfNeeded()
        }
    }

    static func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
