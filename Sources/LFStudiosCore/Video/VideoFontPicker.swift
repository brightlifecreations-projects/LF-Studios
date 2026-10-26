import AppKit
import CoreText
import SwiftUI
import UniformTypeIdentifiers

/// The font families to pick from, read once (and again after a font is
/// added) rather than on every inspector redraw.
@MainActor
final class VideoFontLibrary: ObservableObject {
    static let shared = VideoFontLibrary()

    @Published private(set) var families: [String] = []
    /// Families from LF Studios' added font files, listed first.
    @Published private(set) var addedFamilies: [String] = []

    private init() {
        reload()
    }

    func reload() {
        families = VideoFonts.installedFamilies
        let added = VideoFonts.addedFontFiles().flatMap { url -> [String] in
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return [] }
            return descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
        }
        addedFamilies = Array(Set(added)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

extension VideoEditorModel {
    /// Add Font File…: a .ttf/.otf copied into LF Studios' fonts. Returns
    /// its family, to pick it right away.
    func addFontFile() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoFonts.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.message = L("Choose a .ttf or .otf font. LF Studios keeps its own copy, so it keeps working if the file is deleted.")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let families = try VideoFonts.addFontFile(url)
            VideoFontLibrary.shared.reload()
            if let family = families.first {
                showNotice(L("Added “\(family)”"), symbol: "textformat")
            }
            return families.first
        } catch {
            showNotice(L("That file isn't a font LF Studios can use"), symbol: "exclamationmark.triangle.fill")
            return nil
        }
    }

    /// Fonts the project uses that aren't on this Mac (drawn in the
    /// built-in font instead).
    var missingFontFamilies: [String] {
        var choices = [project.captionStyle.font, project.keystrokeStyle.font, project.cards.font]
        choices += project.overlayEffects.map(\.font)
        let missing = choices.compactMap { $0 }.filter(\.isMissing).compactMap(\.family)
        return Array(Set(missing)).sorted()
    }
}

/// Font, weight, outline, and shadow for one kind of text (captions, title
/// cards, a text annotation, the keys).
struct VideoFontPicker: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject private var library = VideoFontLibrary.shared
    @Binding var choice: VideoFontChoice?

    init(model: VideoEditorModel, choice: Binding<VideoFontChoice?>) {
        self.model = model
        _choice = choice
    }

    private var current: VideoFontChoice { choice ?? VideoFontChoice() }

    /// nil choice once nothing is set, so projects don't gain empty fonts.
    private func update(_ change: (inout VideoFontChoice) -> Void) {
        var next = current
        change(&next)
        choice = next == VideoFontChoice() ? nil : next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L("Font"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                    .frame(width: VideoEditorTheme.rowTitleWidth([L("Font"), L("Weight")]), alignment: .leading)
                Menu {
                    Button(L("Built-in (San Francisco)")) { update { $0.family = nil } }
                    if !library.addedFamilies.isEmpty {
                        Divider()
                        Section(L("Added to LF Studios")) {
                            ForEach(library.addedFamilies, id: \.self) { family in
                                Button(family) { update { $0.family = family } }
                            }
                        }
                    }
                    Divider()
                    Button(L("Add Font File…")) {
                        if let family = model.addFontFile() { update { $0.family = family } }
                    }
                    Divider()
                    ForEach(library.families, id: \.self) { family in
                        Button(family) { update { $0.family = family } }
                    }
                } label: {
                    Text(current.family ?? L("Built-in"))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(VideoEditorTheme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(VideoEditorTheme.cardStroke, lineWidth: 1))
            }
            HStack(spacing: 10) {
                Text(L("Weight"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                    .frame(width: VideoEditorTheme.rowTitleWidth([L("Font"), L("Weight")]), alignment: .leading)
                VideoSegmented(
                    options: [(nil, L("Auto"))] + VideoFontChoice.Weight.allCases.map { (Optional($0), $0.title) },
                    selection: Binding(get: { current.weight }, set: { weight in update { $0.weight = weight } })
                )
            }
            VideoToggleRow(title: L("Outline"), detail: L("A contrasting edge around the letters"), isOn: Binding(get: { current.outline }, set: { on in update { $0.outline = on } }))
            VideoToggleRow(title: L("Shadow"), detail: L("A soft shadow under the letters"), isOn: Binding(get: { current.shadow }, set: { on in update { $0.shadow = on } }))
            if current.isMissing, let family = current.family {
                Label(L("“\(family)” isn't on this Mac — showing the built-in font. Install it, or add its file with Add Font File…"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
