import AppKit
import SwiftUI

// MARK: - Editor keys you can change (1.15.0)

/// One key with its modifiers, as `charactersIgnoringModifiers` gives it
/// (lowercased).
struct VideoKeyBinding: Hashable {
    var key: String
    var modifiers: NSEvent.ModifierFlags

    static func == (a: Self, b: Self) -> Bool { a.key == b.key && a.modifiers.rawValue == b.modifiers.rawValue }
    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
    }

    init(key: String, modifiers: NSEvent.ModifierFlags = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers.intersection([.command, .shift, .option, .control])
    }

    /// From how it's written: "⇧⌘B", "⌥[", "`", "\".
    init?(_ text: String) {
        var mods: NSEvent.ModifierFlags = []
        var rest = Substring(text)
        while let first = rest.first, "⌃⌥⇧⌘".contains(first) {
            switch first {
            case "⌃": mods.insert(.control)
            case "⌥": mods.insert(.option)
            case "⇧": mods.insert(.shift)
            default: mods.insert(.command)
            }
            rest = rest.dropFirst()
        }
        guard rest.count == 1 else { return nil }
        self.init(key: String(rest), modifiers: mods)
    }

    /// As menus write it: ⌃⌥⇧⌘ then the key.
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key.uppercased()
    }

    /// The same key typed with ⌥ (and ⇧) on a US keyboard, which some Macs
    /// report instead of the plain letter.
    static let optionCharacters: [Character: Character] = {
        let plain = Array("abcdefghijklmnopqrstuvwxyz1234567890-=[];',./")
        let option = Array("å∫ç∂´ƒ©˙ˆ∆˚¬µ˜øπœ®ß†¨√∑≈¥Ω¡™£¢∞§¶•ªº–≠“‘…æ≤≥÷")
        let shifted = Array("ÅıÇÎ´Ï˝ÓˆÔÒÂ˜ØŒ‰Íˇ¨◊„˛Á¸")
        var map: [Character: Character] = [:]
        for (p, o) in zip(plain, option) { map[o] = p }
        for (p, o) in zip(plain.prefix(26), shifted) where map[o] == nil { map[o] = p }
        return map
    }()

    /// `key` as typed, with ⌥'s special characters turned back.
    static func normalized(_ key: String) -> String {
        guard key.count == 1, let c = key.first, let plain = optionCharacters[c] else { return key.lowercased() }
        return String(plain)
    }
}

enum VideoKeymapPreset: String, CaseIterable, Identifiable, Codable {
    case lfStudios, finalCut, premiere

    var id: String { rawValue }
    var title: String {
        switch self {
        case .lfStudios: return L("LF Studios")
        case .finalCut: return L("Final Cut Pro style")
        case .premiere: return L("Premiere Pro style")
        }
    }
}

/// Which key runs which timeline command: a preset, and your own changes on
/// top of it. Kept in Settings for every editor.
struct VideoKeymap: Equatable, Codable {
    var preset: VideoKeymapPreset = .lfStudios
    /// Your own keys (command name → how it's written; "" for no key).
    var custom: [String: String] = [:]

    /// Commands whose keys can change (undo, redo and delete stay).
    static var editable: [VideoEditCommand] {
        VideoEditCommand.allCases.filter { ![.undo, .redo, .delete].contains($0) }
    }

    /// LF Studios' own keys (CapCut's, 1.14.0).
    static let standard: [VideoEditCommand: String] = [
        .selectTool: "A", .splitTool: "B", .split: "⌘B", .splitAllTracks: "⇧⌘B", .deleteLeft: "Q", .deleteRight: "W",
        .toggleMagnet: "P", .toggleSnapping: "N", .toggleLinkage: "`", .togglePreviewAxis: "S", .zoomToFit: "⇧Z", .toggleEnabled: "V",
        .group: "⌘G", .ungroup: "⇧⌘G", .extractAudio: "⇧⌘A", .selectLeft: "[", .selectRight: "]", .copy: "⌘C", .paste: "⌘V",
        .markIn: "I", .markOut: "O", .addText: "⌥T", .addArrow: "⌥A", .addHighlight: "⌥H", .addBlur: "⌥B",
        .addKeyframe: "⌥K", .previousKeyframe: "⌥[", .nextKeyframe: "⌥]", .addTextClip: "⌥⇧T",
        .makeCompound: "⌥G", .breakApart: "⌥⇧G",
    ]

    /// Each preset changes only the keys of commands LF Studios has.
    static func keys(for preset: VideoKeymapPreset) -> [VideoEditCommand: String] {
        var keys = standard
        switch preset {
        case .lfStudios:
            break
        case .finalCut:
            // Trim start / end, add marker, freeze frame, detach audio,
            // crop, previous / next keyframe (⌥G is already its New
            // Compound Clip).
            keys[.deleteLeft] = "⌥["
            keys[.deleteRight] = "⌥]"
            keys[.previousKeyframe] = "⌥;"
            keys[.nextKeyframe] = "⌥'"
            keys[.addMarker] = "M"
            keys[.freezeFrame] = "⌥F"
            keys[.extractAudio] = "⌃⇧S"
            keys[.crop] = "⇧C"
        case .premiere:
            // Selection V, razor C, enable ⇧E, marker M, zoom to fit \,
            // snapping S.
            keys[.selectTool] = "V"
            keys[.splitTool] = "C"
            keys[.toggleEnabled] = "⇧E"
            keys[.addMarker] = "M"
            keys[.zoomToFit] = "\\"
            keys[.toggleSnapping] = "S"
            keys[.togglePreviewAxis] = "⇧S"
        }
        return keys
    }

    /// The key that runs `command` now (nil: none).
    func binding(for command: VideoEditCommand) -> VideoKeyBinding? {
        if let own = custom[command.rawValue] { return own.isEmpty ? nil : VideoKeyBinding(own) }
        return Self.keys(for: preset)[command].flatMap(VideoKeyBinding.init)
    }

    var bindings: [VideoEditCommand: VideoKeyBinding] {
        var all: [VideoEditCommand: VideoKeyBinding] = [:]
        for command in Self.editable { if let binding = binding(for: command) { all[command] = binding } }
        return all
    }

    /// The command for a key press (nil: not one of these).
    func command(key: String, modifiers: NSEvent.ModifierFlags) -> VideoEditCommand? {
        let pressed = VideoKeyBinding(key: VideoKeyBinding.normalized(key), modifiers: modifiers)
        // ⇧ with a letter: "T" and "t" alike; ⇧` arrives as "~".
        let alternatives = [pressed, VideoKeyBinding(key: pressed.key == "~" ? "`" : pressed.key, modifiers: pressed.modifiers)]
        for (command, binding) in bindings where alternatives.contains(binding) { return command }
        // LF Studios' own: ⇧` and ` both toggle linkage.
        if pressed == VideoKeyBinding(key: "~", modifiers: [.shift]), binding(for: .toggleLinkage) == VideoKeyBinding(key: "`") { return .toggleLinkage }
        return nil
    }

    // MARK: Conflicts

    /// Keys the editor keeps for itself (playback, undo, export…).
    static let reserved: [(VideoKeyBinding, String)] = [
        (VideoKeyBinding(key: " "), L("Play / pause")), (VideoKeyBinding(key: "z", modifiers: .command), L("Undo")),
        (VideoKeyBinding(key: "z", modifiers: [.command, .shift]), L("Redo")), (VideoKeyBinding(key: "k", modifiers: .command), L("All commands")),
        (VideoKeyBinding(key: "e", modifiers: .command), L("Export")), (VideoKeyBinding(key: "w", modifiers: .command), L("Close")),
        (VideoKeyBinding(key: "s", modifiers: .command), L("Save")), (VideoKeyBinding(key: "q", modifiers: .command), L("Quit")),
        (VideoKeyBinding(key: "?"), L("Keyboard Shortcuts")), (VideoKeyBinding(key: "?", modifiers: .shift), L("Keyboard Shortcuts")),
    ]

    /// Single keys the editor uses that a command may take over.
    static let takeovers: [(VideoKeyBinding, String)] = [
        (VideoKeyBinding(key: "j"), L("Play backwards")), (VideoKeyBinding(key: "k"), L("Pause")), (VideoKeyBinding(key: "l"), L("Play faster")),
        (VideoKeyBinding(key: "z"), L("Add zoom at playhead")), (VideoKeyBinding(key: "m"), L("Mute")), (VideoKeyBinding(key: "c"), L("Split at playhead")),
        (VideoKeyBinding(key: "d", modifiers: .command), L("Duplicate")), (VideoKeyBinding(key: "f", modifiers: .command), L("Find in the transcript")),
        (VideoKeyBinding(key: "y", modifiers: [.command, .shift]), L("Apply my style")),
    ] + (1...5).map { (VideoKeyBinding(key: "\($0)"), L("Zoom level")) }

    enum Conflict: Equatable {
        /// Can't be used: the editor needs it.
        case reserved(String)
        /// Another command has it: it loses it.
        case command(VideoEditCommand)
        /// One of the editor's own keys stops working while this has it.
        case takesOver(String)

        var message: String {
            switch self {
            case .reserved(let what): return L("Kept for \(what)")
            case .command(let other): return L("Also “\(other.title)” — it loses this key")
            case .takesOver(let what): return L("Replaces \(what)")
            }
        }
        var blocks: Bool { if case .reserved = self { return true } else { return false } }
    }

    func conflicts(_ binding: VideoKeyBinding, for command: VideoEditCommand) -> [Conflict] {
        var found: [Conflict] = []
        if let reserved = Self.reserved.first(where: { $0.0 == binding }) { found.append(.reserved(reserved.1)) }
        for (other, existing) in bindings where other != command && existing == binding { found.append(.command(other)) }
        if let takeover = Self.takeovers.first(where: { $0.0 == binding }) { found.append(.takesOver(takeover.1)) }
        return found
    }

    /// Every pair of commands sharing a key (a good keymap has none).
    var clashes: [(VideoEditCommand, VideoEditCommand)] {
        let all = bindings.sorted { $0.key.rawValue < $1.key.rawValue }
        var pairs: [(VideoEditCommand, VideoEditCommand)] = []
        for (i, a) in all.enumerated() { for b in all[(i + 1)...] where a.value == b.value { pairs.append((a.key, b.key)) } }
        return pairs
    }

    /// `command` on `binding` (nil: no key); whoever had it loses it.
    mutating func set(_ command: VideoEditCommand, to binding: VideoKeyBinding?) {
        if let binding {
            for (other, existing) in bindings where other != command && existing == binding { custom[other.rawValue] = "" }
        }
        let presetKey = Self.keys(for: preset)[command]
        let wanted = binding?.display ?? ""
        custom[command.rawValue] = wanted == (presetKey.flatMap(VideoKeyBinding.init)?.display ?? "") ? nil : wanted
    }

    mutating func reset(_ command: VideoEditCommand) {
        custom[command.rawValue] = nil
        // Another command that took its key gives it back.
        if let mine = binding(for: command) {
            for (other, existing) in bindings where other != command && existing == mine { custom[other.rawValue] = "" }
        }
    }

    // MARK: Kept in Settings

    private static var cached: VideoKeymap?

    static var current: VideoKeymap {
        get {
            if let cached { return cached }
            let loaded = Settings.videoKeymap.flatMap { try? JSONDecoder().decode(VideoKeymap.self, from: $0) } ?? VideoKeymap()
            cached = loaded
            return loaded
        }
        set {
            cached = newValue
            Settings.videoKeymap = newValue == VideoKeymap() ? nil : try? JSONEncoder().encode(newValue)
            NotificationCenter.default.post(name: .lfstudiosKeymapChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let lfstudiosKeymapChanged = Notification.Name("lfstudiosKeymapChanged")
}

// MARK: - Keyboard Shortcuts ▸ Customize

extension VideoEditorModel {
    /// A key pressed while a shortcut is being recorded: Esc stops, ⌫
    /// clears, anything else is the new key (unless the editor needs it).
    func recordShortcut(_ event: NSEvent) {
        guard let command = recordingShortcut else { return }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == 53 {
            recordingShortcut = nil
            return
        }
        var keymap = VideoKeymap.current
        if [51, 117].contains(event.keyCode), modifiers.isEmpty {
            keymap.set(command, to: nil)
            VideoKeymap.current = keymap
            recordingShortcut = nil
            return
        }
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1,
              !(characters.unicodeScalars.first.map { $0.value >= 0xF700 } ?? false) else {
            showNotice(L("Pick a letter, number or symbol key"), symbol: "keyboard")
            return
        }
        let binding = VideoKeyBinding(key: VideoKeyBinding.normalized(characters), modifiers: modifiers)
        if let reserved = keymap.conflicts(binding, for: command).first(where: \.blocks) {
            showNotice(reserved.message, symbol: "exclamationmark.triangle.fill")
            return
        }
        let lost = keymap.conflicts(binding, for: command).compactMap { if case .command(let other) = $0 { return other } else { return nil } }
        keymap.set(command, to: binding)
        VideoKeymap.current = keymap
        recordingShortcut = nil
        if let other = lost.first {
            showNotice(L("\(binding.display) moved from “\(other.title)”, which has no key now"), symbol: "keyboard", duration: 4)
        }
    }
}

struct VideoShortcutsEditor: View {
    @ObservedObject var model: VideoEditorModel
    @State private var keymap = VideoKeymap.current
    @State private var search = ""

    private var commands: [VideoEditCommand] {
        let words = search.lowercased()
        return VideoKeymap.editable.filter { words.isEmpty || $0.title.lowercased().contains(words) || (keymap.binding(for: $0)?.display.lowercased().contains(words) ?? false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(L("Keys like"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                Picker(L("Keys like"), selection: Binding(get: { keymap.preset }, set: { preset in
                    // A preset starts clean: your own keys go.
                    var next = VideoKeymap()
                    next.preset = preset
                    VideoKeymap.current = next
                })) {
                    ForEach(VideoKeymapPreset.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 190)
                Spacer()
                Button(L("Reset All")) {
                    var next = VideoKeymap()
                    next.preset = keymap.preset
                    VideoKeymap.current = next
                }
                .buttonStyle(VideoSecondaryButtonStyle())
                .disabled(keymap.custom.isEmpty)
                .help(L("Back to the preset's keys"))
            }
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(VideoEditorTheme.textTertiary)
                TextField(L("Search"), text: $search).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.well))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(commands, id: \.rawValue) { command in row(command) }
                }
            }
            .frame(maxHeight: 360)
            Text(L("Click a key to change it, then press the new one (Esc stops, ⌫ leaves it without a key). Space, ⌘Z, ⌘K, ⌘E and the arrows stay as they are."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lfstudiosKeymapChanged)) { _ in keymap = VideoKeymap.current }
        .onDisappear { model.recordingShortcut = nil }
    }

    private func row(_ command: VideoEditCommand) -> some View {
        let binding = keymap.binding(for: command)
        let recording = model.recordingShortcut == command
        let changed = keymap.custom[command.rawValue] != nil
        let notes = binding.map { keymap.conflicts($0, for: command) } ?? []
        return HStack(spacing: 8) {
            Image(systemName: command.symbol).font(.system(size: 11)).frame(width: 18).foregroundStyle(VideoEditorTheme.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title).font(.system(size: 12)).foregroundStyle(VideoEditorTheme.textPrimary)
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    Text(note.message).font(.system(size: 10)).foregroundStyle(VideoEditorTheme.warning)
                }
            }
            Spacer(minLength: 8)
            Button {
                model.recordingShortcut = recording ? nil : command
            } label: {
                Text(recording ? L("Press a key…") : (binding?.display ?? L("None")))
                    .font(.system(size: 11.5, weight: .semibold, design: recording ? .default : .monospaced))
                    .foregroundStyle(binding == nil && !recording ? VideoEditorTheme.textTertiary : VideoEditorTheme.textPrimary)
                    .frame(minWidth: 86)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(recording ? VideoEditorTheme.layer.opacity(0.3) : VideoEditorTheme.card))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(recording ? VideoEditorTheme.layer : VideoEditorTheme.cardStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Key for \(command.title): \(binding?.display ?? L("None"))"))
            Button {
                var next = keymap
                next.reset(command)
                VideoKeymap.current = next
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(VideoEditorTheme.textTertiary)
            .opacity(changed ? 1 : 0)
            .disabled(!changed)
            .help(L("Back to the preset's key"))
            .accessibilityLabel(L("Reset"))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(recording ? VideoEditorTheme.card : Color.clear))
    }
}
