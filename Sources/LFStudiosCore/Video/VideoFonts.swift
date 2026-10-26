import AppKit
import CoreText
import Foundation

/// The typeface for captions, title cards, text annotations, or the
/// shortcut keys: a font family (any installed on the Mac, or one added to
/// LF Studios), a weight, and an optional outline and shadow for
/// readability. nil everywhere keeps the built-in look.
struct VideoFontChoice: Codable, Equatable, Hashable {
    enum Weight: String, Codable, CaseIterable, Identifiable {
        case regular, bold, black

        var id: String { rawValue }
        var title: String {
            switch self {
            case .regular: return L("Regular")
            case .bold: return L("Bold")
            case .black: return L("Black")
            }
        }

        /// NSFontManager's 0…15 scale.
        var managerWeight: Int {
            switch self {
            case .regular: return 5
            case .bold: return 9
            case .black: return 11
            }
        }

        var systemWeight: NSFont.Weight {
            switch self {
            case .regular: return .regular
            case .bold: return .bold
            case .black: return .black
            }
        }
    }

    /// Family name (nil: the built-in system font).
    var family: String?
    /// nil: the text's own weight (a caption look's, for captions).
    var weight: Weight?
    /// A contrasting edge around the letters.
    var outline = false
    /// A soft shadow under the letters.
    var shadow = false

    init(family: String? = nil, weight: Weight? = nil, outline: Bool = false, shadow: Bool = false) {
        self.family = family
        self.weight = weight
        self.outline = outline
        self.shadow = shadow
    }

    private enum CodingKeys: String, CodingKey { case family, weight, outline, shadow }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = (try? c.decodeIfPresent(String.self, forKey: .family)).flatMap { $0 }.flatMap { $0.isEmpty ? nil : $0 }
        weight = try? c.decodeIfPresent(Weight.self, forKey: .weight)
        outline = (try? c.decodeIfPresent(Bool.self, forKey: .outline)).flatMap { $0 } ?? false
        shadow = (try? c.decodeIfPresent(Bool.self, forKey: .shadow)).flatMap { $0 } ?? false
    }

    /// For the renderer's image caches.
    var cacheKey: String {
        "\(family ?? "-")|\(weight?.rawValue ?? "-")|\(outline ? 1 : 0)|\(shadow ? 1 : 0)"
    }

    /// The family isn't on this Mac (or in LF Studios): drawn in the
    /// built-in font instead.
    var isMissing: Bool {
        guard let family else { return false }
        return !VideoFonts.isAvailable(family)
    }
}

enum VideoFonts {
    // MARK: Families

    /// Every font family on this Mac, LF Studios' added fonts included.
    static var installedFamilies: [String] {
        registerAddedFonts()
        return NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func isAvailable(_ family: String) -> Bool {
        registerAddedFonts()
        return !(NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).isEmpty
    }

    // MARK: Resolving

    /// The font for `choice` at `size`: the family's member closest to the
    /// weight (upright first), or the built-in font when the family is
    /// missing or nothing's chosen.
    static func font(_ choice: VideoFontChoice?, size: CGFloat, defaultWeight: NSFont.Weight) -> NSFont {
        let weight = choice?.weight?.systemWeight ?? defaultWeight
        guard let family = choice?.family else {
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
        registerAddedFonts()
        let target = choice?.weight?.managerWeight ?? managerWeight(for: defaultWeight)
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        let candidates: [(name: String, weight: Int, italic: Bool)] = members.compactMap { member in
            guard member.count >= 4, let name = member[0] as? String, let memberWeight = member[2] as? Int, let traits = member[3] as? UInt else { return nil }
            return (name, memberWeight, NSFontTraitMask(rawValue: traits).contains(.italicFontMask))
        }
        let best = candidates.min { a, b in
            if a.italic != b.italic { return !a.italic }
            return abs(a.weight - target) < abs(b.weight - target)
        }
        if let best, let font = NSFont(name: best.name, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// NSFont.Weight on NSFontManager's 0…15 scale.
    static func managerWeight(for weight: NSFont.Weight) -> Int {
        switch weight {
        case ..<NSFont.Weight.thin: return 2
        case ..<NSFont.Weight.light: return 3
        case ..<NSFont.Weight.regular: return 4
        case ..<NSFont.Weight.medium: return 5
        case ..<NSFont.Weight.semibold: return 6
        case ..<NSFont.Weight.bold: return 8
        case ..<NSFont.Weight.heavy: return 9
        case ..<NSFont.Weight.black: return 10
        default: return 11
        }
    }

    // MARK: Drawing

    /// Draws `text` in `rect` with the choice's outline and shadow (in the
    /// current graphics context): the outline is a stroke-only copy drawn
    /// first, in a color that contrasts with `ink`.
    static func draw(_ text: NSAttributedString, in rect: CGRect, options: NSString.DrawingOptions, choice: VideoFontChoice?, fontSize: CGFloat, ink: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if choice?.shadow == true {
            shadow(fontSize: fontSize).set()
        }
        if choice?.outline == true {
            outlined(text, ink: ink).draw(with: rect, options: options)
        }
        text.draw(with: rect, options: options)
    }

    /// A stroke-only copy of `text`, for drawing under it.
    static func outlined(_ text: NSAttributedString, ink: NSColor) -> NSAttributedString {
        let edge = outlineColor(for: ink)
        let copy = NSMutableAttributedString(attributedString: text)
        copy.addAttributes([.strokeColor: edge, .strokeWidth: 12.0, .foregroundColor: edge], range: NSRange(location: 0, length: copy.length))
        return copy
    }

    static func outlineColor(for ink: NSColor) -> NSColor {
        let rgb = ink.usingColorSpace(.sRGB) ?? ink
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.5 ? NSColor.black : NSColor.white
    }

    static func shadow(fontSize: CGFloat) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = fontSize * 0.2
        // Shadow offsets ignore the flip: negative is down.
        shadow.shadowOffset = NSSize(width: 0, height: -fontSize * 0.05)
        return shadow
    }

    // MARK: Added fonts (Add Font File…)

    static let fileExtensions: Set<String> = ["ttf", "otf", "ttc"]

    /// LF Studios' own copies (LF Studios/Fonts), so a font keeps working
    /// after the file it came from is deleted.
    static func directory(root: URL = VideoStorageLocation.root) -> URL {
        root.appendingPathComponent("LF Studios", isDirectory: true).appendingPathComponent("Fonts", isDirectory: true)
    }

    static func addedFontFiles(root: URL = VideoStorageLocation.root) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory(root: root), includingPropertiesForKeys: nil)) ?? []
        return urls.filter { fileExtensions.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    enum AddError: Error, Equatable {
        case notAFont
    }

    /// Copies a .ttf/.otf into LF Studios' fonts and makes it usable now.
    /// Returns its families.
    @discardableResult
    static func addFontFile(_ url: URL, root: URL = VideoStorageLocation.root) throws -> [String] {
        guard fileExtensions.contains(url.pathExtension.lowercased()),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], !descriptors.isEmpty else {
            throw AddError.notAFont
        }
        let families = Array(Set(descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String })).sorted()
        let folder = directory(root: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var destination = folder.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            // Same file again: nothing to do; a different one: its own name.
            if FileManager.default.contentsEqual(atPath: destination.path, andPath: url.path) { return families }
            destination = folder.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(8)).\(url.pathExtension)")
        }
        try FileManager.default.copyItem(at: url, to: destination)
        register([destination])
        return families
    }

    /// The added font files for `family` (to carry them in project files).
    static func addedFontFiles(forFamily family: String, root: URL = VideoStorageLocation.root) -> [URL] {
        addedFontFiles(root: root).filter { url in
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return false }
            return descriptors.contains { (CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String) == family }
        }
    }

    private static let registrationLock = NSLock()
    nonisolated(unsafe) private static var registered: Set<String> = []

    /// Makes LF Studios' added fonts usable in this process (the preview and
    /// every export), once each.
    static func registerAddedFonts() {
        register(addedFontFiles())
    }

    static func register(_ urls: [URL]) {
        registrationLock.lock()
        let fresh = urls.filter { !registered.contains($0.path) }
        fresh.forEach { registered.insert($0.path) }
        registrationLock.unlock()
        guard !fresh.isEmpty else { return }
        CTFontManagerRegisterFontURLs(fresh as CFArray, .process, true, nil)
    }
}
