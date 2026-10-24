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
        mutate(label: "Apply Preset") { $0.apply(preset: preset) }
        showNotice(L("Applied “\(preset.name)”"), symbol: "paintpalette")
    }

    /// Save as Preset…: a name, and whether it sets the aspect ratio.
    func saveCurrentStyleAsPreset() {
        let library = presets.current
        let name = NSTextField(string: library.uniqueName(L("My Preset")))
        name.frame = NSRect(x: 0, y: 30, width: 260, height: 24)
        let aspect = NSButton(checkboxWithTitle: L("Include aspect ratio (\(project.aspectPreset.title))"), target: nil, action: nil)
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
        alert.informativeText = presets.current.defaultID == id
            ? L("New recordings will use the built-in ShotStyle look instead. Videos that use this preset keep their look.")
            : L("Videos that use this preset keep their look.")
        alert.addButton(withTitle: L("Delete"))
        alert.addButton(withTitle: L("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        presets.change { $0.delete(id) }
    }

    /// nil: new recordings start with the built-in look.
    func setDefaultPreset(_ id: UUID?) {
        presets.change { $0.setDefault(id) }
        if let id, let preset = presets.current.preset(id) {
            showNotice(L("New recordings will use “\(preset.name)”"), symbol: "checkmark.seal.fill")
        } else {
            showNotice(L("New recordings will use the ShotStyle look"), symbol: "arrow.counterclockwise")
        }
    }

    // MARK: Sharing

    private static var presetFileType: UTType {
        UTType(filenameExtension: VideoStylePresetFile.fileExtension, conformingTo: .json) ?? .json
    }

    func exportPresets() {
        let library = presets.current
        guard !library.presets.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.presetFileType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(L("ShotStyle Presets")).\(VideoStylePresetFile.fileExtension)"
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
        panel.allowedContentTypes = [Self.presetFileType, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), let file = try? VideoStylePresetFile.read(data) else {
            showNotice(L("That isn't a ShotStyle presets file"), symbol: "exclamationmark.triangle.fill")
            return
        }
        let images = VideoStylePresetStore.directory().appendingPathComponent("Images", isDirectory: true)
        let added = presets.change { $0.adding(file.unpacked(imagesDirectory: images)) }
        showNotice(L("Imported \(added.count) presets"), symbol: "square.and.arrow.down")
    }
}

// MARK: - Menu (top of the Style panel)

struct VideoStylePresetsSection: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject private var store = VideoStylePresetStore.shared

    var body: some View {
        let library = store.library
        let matching = model.matchingPreset
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
                                if library.defaultID == preset.id {
                                    Button(L("Stop Using for New Recordings")) { model.setDefaultPreset(nil) }
                                } else {
                                    Button(L("Set as Default for New Recordings")) { model.setDefaultPreset(preset.id) }
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
                Button(L("Reset to the ShotStyle Look")) { model.resetStyle() }
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

            if let defaultPreset = library.defaultPreset {
                Label(L("New recordings use “\(defaultPreset.name)”"), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
            }
        }
        // Saved from another window (or a test) since: read it again.
        .onAppear { store.reloadIfNeeded() }
    }

    private func title(_ preset: VideoNamedStylePreset, library: VideoStylePresetLibrary) -> String {
        library.defaultID == preset.id ? L("\(preset.name) (default)") : preset.name
    }
}
