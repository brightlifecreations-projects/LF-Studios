import AppKit

@MainActor
extension NSApplication {
    func restoreBackgroundOnlyActivationPolicyIfNeeded(excluding closingWindow: NSWindow? = nil) {
        // Never drop to background while an editor is open (even minimized) — it must keep its
        // Dock icon / ⌘-Tab entry so the user can return to it. See `ShotStyleEditorActivation`.
        if VideoDemoEditorWindowController.hasOpenEditors || AnnotationWindowController.hasOpenEditors {
            // Transient UI (menu, capture overlay, a panel) may have run in
            // the meantime — make sure the editors kept their Dock presence.
            ShotStyleEditorActivation.sync()
            return
        }
        // Stopping a recording holds the foreground for the editor about to
        // open; dropping to background here would hand focus back to the
        // recorded app and macOS won't give it back.
        if ShotStyleEditorActivation.isHoldingForeground {
            return
        }

        guard !hasVisiblePersistentWindow(excluding: closingWindow) else {
            return
        }

        setActivationPolicy(.prohibited)
    }

    /// Lets a menu-bar-only ShotStyle show transient UI (menu, capture
    /// overlay, panels). Never demotes a regular app — while an editor is
    /// open that would hide its Dock icon and drop it behind other apps.
    func ensureForegroundCapable() {
        if activationPolicy() == .prohibited {
            setActivationPolicy(.accessory)
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


/// Coordinates the Dock-icon presence across both editors. While a photo or video editor window is
/// open, ShotStyle runs as a regular app (Dock icon + ⌘-Tab) so the user can always return to it;
/// once the last editor of either kind closes, it drops back to accessory (menu-bar-only).
@MainActor
enum ShotStyleEditorActivation {
    /// Set between pressing Stop and the editor opening.
    private(set) static var isHoldingForeground = false

    static func sync() {
        let editing = VideoDemoEditorWindowController.hasOpenEditors
            || AnnotationWindowController.hasOpenEditors
            || isHoldingForeground
        let policy: NSApplication.ActivationPolicy = editing ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
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
            // No editor after all (the save failed): menu-bar only again,
            // and fully background when nothing is on screen.
            if NSApp.activationPolicy() == .regular { NSApp.setActivationPolicy(.accessory) }
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
