import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Editor actions (VideoStylePresets.swift)

extension VideoEditorModel {
    private var presets: VideoStylePresetStore { .shared }

    /// The preset the video looks like right now (nil: a look of its own).
    var matchingPreset: VideoNamedStylePreset? {
        presets.library.presets.first { $0.matches(project) }
    }

    /// Applies a preset to this video, as one undo step.
    func applyPreset(_ id: UUID) {
        guard let preset = presets.current.preset(id) else { return }
        let total = sourceDuration
        mutate(label: "Apply Preset") { $0.apply(preset: preset, totalDuration: total) }
        showNotice(L("Applied “\(preset.name)”"), symbol: "paintpalette")
    }

    /// The preset chosen as My Style (Presets ▸ Edit Presets ▸ Use as My Style).
    var myStyle: VideoNamedStylePreset? { presets.current.myStyle }

    /// Style ▸ Apply my style (⇧⌘Y): My Style on this video, one undo step.
    /// Without one, it says how to choose it.
    func applyMyStyle() {
        guard isReady else { return }
        guard let preset = myStyle else {
            showNotice(L("No My Style yet — open Presets ▸ Edit Presets and choose Use as My Style on one"), symbol: "wand.and.stars", duration: 5)
            return
        }
        let total = sourceDuration
        mutate(label: "Apply My Style") { $0.apply(preset: preset, totalDuration: total) }
        showNotice(L("Applied My Style (“\(preset.name)”) — ⌘Z to undo"), symbol: "wand.and.stars")
    }

    /// Save as Preset…: a name, and whether it sets the aspect ratio.
    func saveCurrentStyleAsPreset() {
        let library = presets.current
        let name = NSTextField(string: library.uniqueName(L("My Preset")))
        name.frame = NSRect(x: 0, y: 30, width: 260, height: 24)
        let aspect = NSButton(checkboxWithTitle: L("Include aspect ratio (\(project.aspectTitle))"), target: nil, action: nil)
        aspect.state = .off
        aspect.frame = NSRect(x: 0, y: 0, width: 260, height: 20)
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        accessory.addSubview(name)
        accessory.addSubview(aspect)

        let alert = NSAlert()
        alert.messageText = L("Save as Preset")
        alert.informativeText = L("Saves the background, frame, cursor, zoom, captions, keys, and camera bubble. Apply it to any video from the Presets menu.")
        alert.accessoryView = accessory
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let style = project.style
        let saved = presets.change { $0.add(name: typed.isEmpty ? L("My Preset") : typed, style: style, includesAspectRatio: aspect.state == .on) }
        showNotice(L("Saved preset “\(saved.name)”"), symbol: "checkmark.circle.fill")
    }

    func updatePreset(_ id: UUID) {
        guard let preset = presets.current.preset(id) else { return }
        let style = project.style
        presets.change { $0.update(id, with: style) }
        showNotice(L("Updated “\(preset.name)”"), symbol: "checkmark.circle.fill")
    }

    func renamePreset(_ id: UUID) {
        guard let preset = presets.current.preset(id) else { return }
        let name = NSTextField(string: preset.name)
        name.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let alert = NSAlert()
        alert.messageText = L("Rename Preset")
        alert.accessoryView = name
        alert.addButton(withTitle: L("Rename"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        presets.change { $0.rename(id, to: name.stringValue) }
    }

    func deletePreset(_ id: UUID) {
        guard let preset = presets.current.preset(id) else { return }
        let alert = NSAlert()
        alert.messageText = L("Delete “\(preset.name)”?")
        alert.informativeText = presets.current.myStyleID == id
            ? L("It's your My Style, so Apply my style will have nothing to apply until you choose another. Videos that use this preset keep their look.")
            : L("Videos that use this preset keep their look.")
        alert.addButton(withTitle: L("Delete"))
        alert.addButton(withTitle: L("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        presets.change { $0.delete(id) }
    }

    /// The preset Apply my style applies (nil: none). Choosing it applies
    /// nothing: new recordings still open plain.
    func setMyStyle(_ id: UUID?) {
        presets.change { $0.setMyStyle(id) }
        if let id, let preset = presets.current.preset(id) {
            showNotice(L("“\(preset.name)” is your My Style — Apply my style (⇧⌘Y) puts it on a video"), symbol: "wand.and.stars")
        } else {
            showNotice(L("No My Style now"), symbol: "wand.and.stars")
        }
    }

    // MARK: Sharing

    private static var presetFileType: UTType {
        UTType(VideoStylePresetFile.typeIdentifier) ?? UTType(filenameExtension: VideoStylePresetFile.fileExtension, conformingTo: .json) ?? .json
    }

    /// `.lfstudiospresets`, exported by LF Studios 1.1–1.8.
    private static var previousPresetFileType: UTType {
        UTType(VideoStylePresetFile.previousTypeIdentifier) ?? UTType(filenameExtension: VideoStylePresetFile.previousFileExtension, conformingTo: .json) ?? .json
    }

    /// Presets exported while the app was called ShotStyle.
    private static var legacyPresetFileType: UTType {
        UTType(filenameExtension: VideoStylePresetFile.legacyFileExtension, conformingTo: .json) ?? .json
    }

    func exportPresets() {
        let library = presets.current
        guard !library.presets.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.presetFileType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(L("LF Studios Presets")).\(VideoStylePresetFile.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try VideoStylePresetFile.make(library.presets).encoded().write(to: url, options: .atomic)
            showNotice(L("Exported \(library.presets.count) presets"), symbol: "square.and.arrow.up")
        } catch {
            showNotice(L("Couldn't save the presets file"), symbol: "exclamationmark.triangle.fill")
        }
    }

    func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.presetFileType, Self.previousPresetFileType, Self.legacyPresetFileType, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let count = presets.importFile(url) else {
            showNotice(L("That isn't an LF Studios presets file"), symbol: "exclamationmark.triangle.fill")
            return
        }
        showNotice(L("Imported \(count) presets"), symbol: "square.and.arrow.down")
    }
}

extension VideoStylePresetStore {
    /// Adds the presets in a `.lfss` (or older `.lfstudiospresets`/`.shotstylepresets`)
    /// file; nil when it isn't one. Returns how many were added.
    @discardableResult
    func importFile(_ url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url), let file = try? VideoStylePresetFile.read(data) else { return nil }
        let images = Self.directory().appendingPathComponent("Images", isDirectory: true)
        return change { $0.adding(file.unpacked(imagesDirectory: images)) }.count
    }
}

// MARK: - Menu (top of the Style panel)

struct VideoStylePresetsSection: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject private var store = VideoStylePresetStore.shared

    var body: some View {
        let library = store.library
        let matching = model.matchingPreset
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.applyMyStyle()
            } label: {
                Label(L("Apply my style"), systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VideoPrimaryButtonStyle())
            .help(library.myStyle.map { L("Put “\($0.name)” on this video (⇧⌘Y)") } ?? L("Choose My Style first: Presets ▸ Edit Presets ▸ Use as My Style (⇧⌘Y)"))
            if library.myStyle == nil {
                Text(L("Pick a preset as My Style (Presets ▸ Edit Presets ▸ Use as My Style), then one click puts it on any video."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        VideoInspectorSection(L("Presets")) {
            Menu {
                if library.presets.isEmpty {
                    Text(L("No presets yet"))
                }
                ForEach(library.presets) { preset in
                    Button {
                        model.applyPreset(preset.id)
                    } label: {
                        if matching?.id == preset.id {
                            Label(title(preset, library: library), systemImage: "checkmark")
                        } else {
                            Text(title(preset, library: library))
                        }
                    }
                }
                Divider()
                Button(L("Save as Preset…")) { model.saveCurrentStyleAsPreset() }
                if !library.presets.isEmpty {
                    Menu(L("Edit Presets")) {
                        ForEach(library.presets) { preset in
                            Menu(preset.name) {
                                Button(L("Update with Current Style")) { model.updatePreset(preset.id) }
                                Button(L("Rename…")) { model.renamePreset(preset.id) }
                                if library.myStyleID == preset.id {
                                    Button(L("Stop Using as My Style")) { model.setMyStyle(nil) }
                                } else {
                                    Button(L("Use as My Style")) { model.setMyStyle(preset.id) }
                                }
                                Divider()
                                Button(L("Delete…"), role: .destructive) { model.deletePreset(preset.id) }
                            }
                        }
                    }
                }
                Divider()
                Button(L("Import Presets…")) { model.importPresets() }
                Button(L("Export Presets…")) { model.exportPresets() }
                    .disabled(library.presets.isEmpty)
                Divider()
                Button(L("Reset to the LF Studios Look")) { model.resetStyle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette")
                    Text(matching.map(\.name) ?? L("Custom look"))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(VideoEditorTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(VideoEditorTheme.cardStroke, lineWidth: 1))

            if let myStyle = library.myStyle {
                Label(L("My Style: “\(myStyle.name)”"), systemImage: "wand.and.stars")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
            }
        }
        // Saved from another window (or a test) since: read it again.
        .onAppear { store.reloadIfNeeded() }
    }

    private func title(_ preset: VideoNamedStylePreset, library: VideoStylePresetLibrary) -> String {
        library.myStyleID == preset.id ? L("\(preset.name) (My Style)") : preset.name
    }
}
