import AppKit

/// Settings → General → Appearance: ShotStyle's windows follow the Mac, or
/// are always light or always dark. Floating overlays (the capture
/// overlay, recording bar, screenshot thumbnail, countdown) stay dark
/// whatever this says, so they read over any screen.
enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    static let key = "appearance"

    var title: String {
        switch self {
        case .system: return L("System")
        case .light: return L("Light Mode")
        case .dark: return L("Dark Mode")
        }
    }

    /// nil follows the Mac.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// The overlays' look.
    static let overlay = NSAppearance(named: .darkAqua)

    /// Every window switches at once (no restart).
    @MainActor
    static func apply(_ choice: AppAppearance = Settings.appearance) {
        NSApp.appearance = choice.nsAppearance
    }
}

extension Settings {
    static var appearance: AppAppearance {
        get { defaults.string(forKey: AppAppearance.key).flatMap(AppAppearance.init(rawValue:)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: AppAppearance.key) }
    }
}

import SwiftUI

/// Colors shared by Home, Settings, and the Command Center, in both looks.
enum ShotStyleTheme {
    /// Text, icons, and faint fills: white on the dark look, black on the
    /// light one.
    static let ink = Color.adaptive(dark: .white, light: .black)

    /// A darker band (tab strip, footers): black on the dark look, a much
    /// lighter black on the light one.
    static func shade(_ opacity: Double) -> Color {
        Color.adaptive(dark: NSColor.black.withAlphaComponent(opacity), light: NSColor.black.withAlphaComponent(opacity * 0.3))
    }

    /// Settings' and the Command Center's backdrop, top to bottom.
    static let backdropTop = Color.adaptive(dark: NSColor(calibratedRed: 0.045, green: 0.049, blue: 0.062, alpha: 0.96), light: NSColor(srgbRed: 0.975, green: 0.975, blue: 0.982, alpha: 0.96))
    static let backdropBottom = Color.adaptive(dark: NSColor(calibratedRed: 0.105, green: 0.096, blue: 0.13, alpha: 0.96), light: NSColor(srgbRed: 0.93, green: 0.928, blue: 0.945, alpha: 0.96))
}
