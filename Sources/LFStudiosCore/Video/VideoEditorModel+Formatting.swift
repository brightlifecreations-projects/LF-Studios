import AppKit
import AVFoundation
import SwiftUI

/// How times, percentages, scales and sizes are written.
extension VideoEditorModel {
    // MARK: Formatting

    /// "4.2s", "42s", "1:05": seconds the way the language writes them
    /// ("4,2 s", "4.2 秒"); a minute or more is a timecode, kept plain.
    static func format(_ seconds: Double) -> String {
        let safe = max(seconds, 0)
        if safe < 10 { return formatTenths(safe) }
        if safe < 60 { return L("\(decimal(safe, digits: 0))s") }
        return String(format: "%d:%02d", Int(safe) / 60, Int(safe) % 60)
    }

    /// "1.5s", always to the tenth (fades and lengths set in tenths).
    static func formatTenths(_ seconds: Double) -> String {
        L("\(decimal(max(seconds, 0), digits: 1))s")
    }

    /// A number with the decimal mark of the language the text is in
    /// (English "4.2" on any Mac, German and French "4,2").
    private static func decimal(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(textLocale))
    }

    /// The language L(…) shows ("en", "de", "zh-hans"): the one tests
    /// picked (an .lproj folder), else the one macOS chose for LF Studios.
    /// Looked up once per bundle (tests switch it): every clip on the
    /// timeline formats its length on each zoom step.
    private static var textLocale: Locale {
        let bundle = L10n.bundle
        if let cached = localeCache, cached.bundle === bundle { return cached.locale }
        let language = bundle.bundleURL.pathExtension == "lproj" ? bundle.bundleURL.deletingPathExtension().lastPathComponent : bundle.preferredLocalizations.first ?? "en"
        localeCache = (bundle, Locale(identifier: language))
        return Locale(identifier: language)
    }

    nonisolated(unsafe) private static var localeCache: (bundle: Bundle, locale: Locale)?

    /// "35%" (a slider's level) — "35 %" where the language spaces it.
    static func formatPercent(_ fraction: Double) -> String {
        L("\(Int((fraction * 100).rounded()))%")
    }

    static func timecode(_ seconds: Double) -> String {
        let safe = max(seconds, 0)
        let minutes = Int(safe) / 60
        let whole = Int(safe) % 60
        let tenths = Int((safe - Double(Int(safe))) * 10)
        return String(format: "%d:%02d.%d", minutes, whole, tenths)
    }

    /// "2×", "1.5×" ("1,5×" in German and French).
    static func formatScale(_ scale: Double) -> String {
        decimal(scale, digits: abs(scale - scale.rounded()) < 0.05 ? 0 : 1) + "×"
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
