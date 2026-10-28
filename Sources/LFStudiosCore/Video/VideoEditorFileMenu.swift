import AppKit

/// The video editor's section of the File menu: Export, Save Subtitles,
/// and the recent exports (each shown in Finder). Its items act on the
/// editor in the key window only.
@MainActor
final class VideoEditorFileMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    static let shared = VideoEditorFileMenu()

    private weak var exportItem: NSMenuItem?
    private weak var saveProjectItem: NSMenuItem?
    private weak var saveProjectAsItem: NSMenuItem?
    private weak var handoffItem: NSMenuItem?
    private let recentMenu = NSMenu(title: L("Recent Exports"))
    private var keyWindowObserver: NSObjectProtocol?

    /// Adds the editor's items to `menu` as their own section.
    func addItems(to menu: NSMenu) {
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        // Projects (VideoProjectFiles.swift): Open from anywhere; Save while
        // a video editor is in front.
        let open = NSMenuItem(title: L("Open…"), action: #selector(openProject(_:)), keyEquivalent: "o")
        open.keyEquivalentModifierMask = [.command]
        open.target = self
        menu.addItem(open)
        let save = NSMenuItem(title: L("Save Project"), action: #selector(saveProject(_:)), keyEquivalent: "")
        save.target = self
        menu.addItem(save)
        saveProjectItem = save
        let saveAs = NSMenuItem(title: L("Save Project As…"), action: #selector(saveProjectAs(_:)), keyEquivalent: "")
        saveAs.target = self
        menu.addItem(saveAs)
        saveProjectAsItem = saveAs
        menu.addItem(.separator())
        let export = NSMenuItem(title: L("Export Video…"), action: #selector(exportVideo(_:)), keyEquivalent: "")
        export.target = self
        menu.addItem(export)
        exportItem = export
        // Every part of the video as its own file (VideoHandoffSheet.swift).
        let handoff = NSMenuItem(title: L("Creative Handoff…"), action: #selector(creativeHandoff(_:)), keyEquivalent: "")
        handoff.target = self
        menu.addItem(handoff)
        handoffItem = handoff
        let subtitles = NSMenuItem(title: L("Save Subtitles (.srt)…"), action: #selector(saveSubtitles(_:)), keyEquivalent: "")
        subtitles.target = self
        menu.addItem(subtitles)
        let recent = NSMenuItem(title: L("Recent Exports"), action: nil, keyEquivalent: "")
        recentMenu.delegate = self
        recent.submenu = recentMenu
        menu.addItem(recent)

        // ⌘E belongs to the item only while an editor is in front: other
        // windows (the capture overlay) use ⌘E for themselves.
        if keyWindowObserver == nil {
            keyWindowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { VideoEditorFileMenu.shared.updateKeyEquivalent() }
            }
        }
        updateKeyEquivalent()
    }

    private func updateKeyEquivalent() {
        let editing = VideoDemoEditorWindowController.keyModel != nil
        exportItem?.keyEquivalent = editing ? "e" : ""
        exportItem?.keyEquivalentModifierMask = [.command]
        // ⌘S is the screenshot editor's Save elsewhere: only claimed here
        // while a video editor is in front.
        saveProjectItem?.keyEquivalent = editing ? "s" : ""
        saveProjectItem?.keyEquivalentModifierMask = [.command]
        saveProjectAsItem?.keyEquivalent = editing ? "S" : ""
        saveProjectAsItem?.keyEquivalentModifierMask = [.command, .shift]
        handoffItem?.keyEquivalent = editing ? "E" : ""
        handoffItem?.keyEquivalentModifierMask = [.command, .shift]
    }

    @objc func openProject(_ sender: Any?) {
        VideoProjectOpener.chooseAndOpen()
    }

    @objc func saveProject(_ sender: Any?) {
        VideoDemoEditorWindowController.saveActiveProject(as: false)
    }

    @objc func saveProjectAs(_ sender: Any?) {
        VideoDemoEditorWindowController.saveActiveProject(as: true)
    }

    @objc func exportVideo(_ sender: Any?) {
        VideoDemoEditorWindowController.exportActive()
    }

    @objc func creativeHandoff(_ sender: Any?) {
        VideoDemoEditorWindowController.keyModel?.showCreativeHandoff()
    }

    @objc func saveSubtitles(_ sender: Any?) {
        VideoDemoEditorWindowController.saveActiveSubtitles()
    }

    @objc func revealExport(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let model = VideoDemoEditorWindowController.keyModel
        switch menuItem.action {
        case #selector(exportVideo(_:)), #selector(creativeHandoff(_:)): return model?.isReady == true && model?.isCropping == false
        case #selector(saveSubtitles(_:)): return model.map { !$0.project.captions.isEmpty } ?? false
        case #selector(revealExport(_:)): return true
        case #selector(openProject(_:)): return true
        case #selector(saveProject(_:)), #selector(saveProjectAs(_:)): return model?.isReady == true && model?.isSavingProject == false
        default: return true
        }
    }

    /// Newest first, the ones still on disk; this editor's own at the top.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let source = VideoDemoEditorWindowController.keyModel?.project.sourceURL.standardizedFileURL.path
        let exports = VideoDemoRecentExportStore.load()
            .filter { FileManager.default.fileExists(atPath: $0.exportPath) }
            .sorted { ($0.sourcePath == source ? 0 : 1, -$0.exportedAt.timeIntervalSince1970) < ($1.sourcePath == source ? 0 : 1, -$1.exportedAt.timeIntervalSince1970) }
        guard !exports.isEmpty else {
            let none = NSMenuItem(title: L("No Exports Yet"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return
        }
        for export in exports {
            let item = NSMenuItem(title: export.exportURL.lastPathComponent, action: #selector(revealExport(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = export.exportPath
            item.toolTip = L("Show in Finder — \(export.exportPath)")
            menu.addItem(item)
        }
    }
}
