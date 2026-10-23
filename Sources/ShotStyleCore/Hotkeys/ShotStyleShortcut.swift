import AppKit
import KeyboardShortcuts

enum ShotStyleShortcutSection: String {
    case screenshots = "Screenshots"
    case tools = "Advanced Tools"
    case recording = "Recording"
}

enum ShotStyleShortcut: CaseIterable, Identifiable {
    case captureArea
    case captureWindow
    case captureFullscreenNative
    case captureFullscreenFallback
    case captureAllDisplays
    case capturePreviousArea
    case captureTimed
    case captureText
    case captureScrolling
    case openCommandCenter
    case recordArea
    case recordWindow
    case recordFullscreen
    case stopRecording
    case pauseRecording

    var id: String { name.rawValue }

    var title: String {
        switch self {
        case .captureArea: return L("Capture Area")
        case .captureWindow: return L("Capture Window")
        case .captureFullscreenNative: return L("Capture Fullscreen")
        case .captureFullscreenFallback: return L("Capture Fullscreen Alt")
        case .captureAllDisplays: return L("Capture All Displays")
        case .capturePreviousArea: return L("Capture Previous Area")
        case .captureTimed: return L("Timed Capture")
        case .captureText: return L("OCR / Capture Text")
        case .captureScrolling: return L("Scrolling Capture")
        case .openCommandCenter: return L("Open Command Center")
        case .recordArea: return L("Record Area")
        case .recordWindow: return L("Record Window")
        case .recordFullscreen: return L("Record Fullscreen")
        case .stopRecording: return L("Stop Recording")
        case .pauseRecording: return L("Pause / Resume Recording")
        }
    }

    var section: ShotStyleShortcutSection {
        switch self {
        case .captureArea, .captureWindow, .captureFullscreenNative, .captureFullscreenFallback, .captureAllDisplays, .capturePreviousArea, .captureTimed:
            return .screenshots
        case .captureText, .captureScrolling, .openCommandCenter:
            return .tools
        case .recordArea, .recordWindow, .recordFullscreen, .stopRecording, .pauseRecording:
            return .recording
        }
    }

    var name: KeyboardShortcuts.Name {
        switch self {
        case .captureArea: return .shotstyleCaptureArea
        case .captureWindow: return .shotstyleCaptureWindow
        case .captureFullscreenNative: return .shotstyleCaptureFullscreenNative
        case .captureFullscreenFallback: return .shotstyleCaptureFullscreenFallback
        case .captureAllDisplays: return .shotstyleCaptureAllDisplays
        case .capturePreviousArea: return .shotstyleCapturePreviousArea
        case .captureTimed: return .shotstyleCaptureTimed
        case .captureText: return .shotstyleCaptureText
        case .captureScrolling: return .shotstyleCaptureScrolling
        case .openCommandCenter: return .shotstyleOpenCommandCenter
        case .recordArea: return .shotstyleRecordArea
        case .recordWindow: return .shotstyleRecordWindow
        case .recordFullscreen: return .shotstyleRecordFullscreen
        case .stopRecording: return .shotstyleStopRecording
        case .pauseRecording: return .shotstylePauseRecording
        }
    }

    /// The assigned keys ("⌥⌘P"), nil while unassigned.
    @MainActor
    var assignedShortcutText: String? {
        KeyboardShortcuts.getShortcut(for: name)?.description
    }

    static var allNames: [KeyboardShortcuts.Name] {
        allCases.map(\.name)
    }

    /// The user's current binding as menus show it (e.g. "⇧⌘4"), or nil
    /// when the shortcut is unassigned — hints must never promise a key
    /// that does nothing.
    @MainActor
    var displayShortcut: String? {
        KeyboardShortcuts.getShortcut(for: name)?.description
    }
}

extension KeyboardShortcuts.Name {
    static let shotstyleCaptureArea = Self("captureArea", default: KeyboardShortcuts.Shortcut(.four, modifiers: [.command, .shift]))
    static let shotstyleCaptureWindow = Self("captureWindow", default: KeyboardShortcuts.Shortcut(.five, modifiers: [.command, .shift]))
    static let shotstyleCaptureFullscreenNative = Self("captureFullscreenNative", default: KeyboardShortcuts.Shortcut(.three, modifiers: [.command, .shift]))
    static let shotstyleCaptureFullscreenFallback = Self("captureFullscreenFallback", default: KeyboardShortcuts.Shortcut(.six, modifiers: [.command, .shift]))
    static let shotstyleCapturePreviousArea = Self("capturePreviousArea", default: KeyboardShortcuts.Shortcut(.seven, modifiers: [.command, .shift]))
    // Timed capture ships unassigned — users opt in via Preferences → Shortcuts.
    static let shotstyleCaptureTimed = Self("captureTimed")
    static let shotstyleCaptureAllDisplays = Self("captureAllDisplays")
    // Unassigned since 0.24: ⌘⇧S and ⌘⇧O are Save As / Open in countless apps,
    // and a global hotkey steals them everywhere. Installs from before keep
    // them (see migrateLegacyToolShortcutsIfNeeded).
    static let shotstyleCaptureText = Self("captureText")
    static let shotstyleCaptureScrolling = Self("captureScrolling")
    // Ships unassigned — the rescue hatch for menu bars so full that macOS
    // hides the ShotStyle icon entirely.
    static let shotstyleOpenCommandCenter = Self("openCommandCenter")
    // Recording shortcuts ship unassigned — users opt in via Preferences → Shortcuts.
    static let shotstyleRecordArea = Self("recordArea")
    static let shotstyleRecordWindow = Self("recordWindow")
    static let shotstyleRecordFullscreen = Self("recordFullscreen")
    static let shotstyleStopRecording = Self("stopRecording")
    static let shotstylePauseRecording = Self("pauseRecording")
}

// MARK: – Legacy default migration

extension ShotStyleShortcut {
    /// Shortcuts that shipped as defaults before 0.24.
    static let legacyToolDefaults: [(shortcut: ShotStyleShortcut, binding: KeyboardShortcuts.Shortcut)] = [
        (.captureScrolling, KeyboardShortcuts.Shortcut(.s, modifiers: [.command, .shift])),
        (.captureText, KeyboardShortcuts.Shortcut(.o, modifiers: [.command, .shift])),
    ]

    /// Existing users keep ⌘⇧S / ⌘⇧O. KeyboardShortcuts normally stored the
    /// old default the first time a name was touched, so this only writes
    /// when that stored value is missing — never over a user's own choice
    /// (including a deliberately cleared field).
    static func migrateLegacyToolShortcutsIfNeeded(
        isExistingInstall: Bool = Settings.isExistingInstall,
        hasStoredValue: (KeyboardShortcuts.Name) -> Bool = { UserDefaults.standard.object(forKey: "KeyboardShortcuts_\($0.rawValue)") != nil },
        setShortcut: (KeyboardShortcuts.Shortcut, KeyboardShortcuts.Name) -> Void = { KeyboardShortcuts.setShortcut($0, for: $1) }
    ) {
        guard !Settings.didMigrateLegacyToolShortcuts else { return }
        Settings.didMigrateLegacyToolShortcuts = true
        guard isExistingInstall else { return }
        for legacy in legacyToolDefaults where !hasStoredValue(legacy.shortcut.name) {
            setShortcut(legacy.binding, legacy.shortcut.name)
        }
    }
}

// MARK: – Key matching

enum ShortcutKeyMatching {
    /// ANSI key positions, so ⌘C still means copy on layouts whose C key
    /// types a non-Latin letter (Russian "с", Greek "ψ", Hebrew "ב"…).
    private static let ansiLetters: [UInt16: String] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i",
        38: "j", 40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q",
        15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
    ]

    /// The Latin letter a key event stands for in ⌘-shortcuts: the typed
    /// letter on Latin layouts (so Dvorak and AZERTY keep their meaning),
    /// otherwise the letter printed at that key's ANSI position.
    static func latinLetter(for event: NSEvent) -> String? {
        if let typed = event.charactersIgnoringModifiers?.lowercased(),
           typed.count == 1,
           let scalar = typed.unicodeScalars.first,
           scalar.isASCII, CharacterSet.lowercaseLetters.contains(scalar) {
            return typed
        }
        return ansiLetters[event.keyCode]
    }
}
