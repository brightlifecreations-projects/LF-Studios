import SwiftUI

/// Home ▸ Guide: an outline on the left, the page on the right, and a
/// search box over both. Content: GuideContent.swift.
struct GuideRootView: View {
    @ObservedObject var model: GuideModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(L("Guide"))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(HomeColors.ink.opacity(0.95))
                Spacer()
                HomeSearchField(text: $model.query, placeholder: L("Search the Guide"))
                    .frame(width: 260)
            }
            .padding(.horizontal, 32)
            .padding(.top, 44)
            .padding(.bottom, 18)

            Rectangle().fill(HomeColors.stroke).frame(height: 1)

            HStack(spacing: 0) {
                GuideOutline(model: model)
                    .frame(width: 226)
                Rectangle().fill(HomeColors.stroke).frame(width: 1)
                ScrollView {
                    GuidePageView(model: model)
                        .frame(maxWidth: 700, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 26)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(model.query.isEmpty ? "\(model.page)" : "search")
            }
        }
    }
}

// MARK: - Outline

private struct GuideOutline: View {
    @ObservedObject var model: GuideModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.chapters) { chapter in
                    GuideOutlineButton(
                        title: chapter.title,
                        symbol: chapter.symbol,
                        isSelected: model.query.isEmpty && model.selectedChapter == chapter.id && model.selectedCategory == nil,
                        isSub: false
                    ) {
                        model.jump(to: .chapter(chapter.id))
                    }
                    if chapter.id == .features {
                        ForEach(chapter.categories) { category in
                            GuideOutlineButton(
                                title: category.title,
                                symbol: category.symbol,
                                isSelected: model.query.isEmpty && model.selectedCategory == category.id,
                                isSub: true
                            ) {
                                model.jump(to: .category(category.id))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
    }
}

private struct GuideOutlineButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let isSub: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: isSub ? 11.5 : 13, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: isSub ? 12 : 13, weight: isSub ? .medium : .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(HomeColors.ink.opacity(isSelected ? 0.96 : (isSub ? 0.6 : 0.72)))
            .padding(.leading, isSub ? 22 : 8)
            .padding(.trailing, 8)
            .frame(height: isSub ? 26 : 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? HomeColors.ink.opacity(0.11) : (isHovering ? HomeColors.ink.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
    }
}

// MARK: - Pages

private struct GuidePageView: View {
    @ObservedObject var model: GuideModel

    var body: some View {
        if !model.query.trimmingCharacters(in: .whitespaces).isEmpty {
            GuideSearchResults(model: model)
        } else {
            switch model.page {
            case .chapter(let id):
                if let chapter = model.chapter(id) { GuideChapterPage(model: model, chapter: chapter) }
            case .category(let id):
                if let category = model.category(id) { GuideCategoryPage(model: model, category: category) }
            case .entry(let id):
                if let entry = model.entry(id) { GuideEntryPage(model: model, entry: entry) }
            }
        }
    }
}

private struct GuideSearchResults: View {
    @ObservedObject var model: GuideModel

    var body: some View {
        let results = model.search(model.query)
        VStack(alignment: .leading, spacing: 14) {
            GuidePageTitle(title: L("Search results"), symbol: "magnifyingglass")
            if results.isEmpty {
                Text(L("Nothing in the Guide matches your search. Try a shorter word, like “zoom” or “camera”."))
                    .font(.system(size: 13.5))
                    .foregroundStyle(HomeColors.ink.opacity(0.6))
            } else {
                ForEach(results) { entry in
                    GuideEntryRow(entry: entry, context: model.category(containing: entry.id)?.title) {
                        model.open(.entry(entry.id))
                    }
                }
            }
        }
    }
}

private struct GuideChapterPage: View {
    @ObservedObject var model: GuideModel
    let chapter: GuideChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GuidePageTitle(title: chapter.title, symbol: chapter.symbol)
            if let intro = chapter.intro {
                GuideParagraph(text: intro)
            }
            switch chapter.id {
            case .gettingStarted, .privacy:
                // Read top to bottom: every page in full.
                ForEach(chapter.entries) { entry in
                    GuideCard {
                        GuideEntryBody(model: model, entry: entry, showsTitle: true)
                    }
                }
            case .features:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(chapter.categories) { category in
                        GuideCategoryCard(category: category) { model.open(.category(category.id)) }
                    }
                }
            case .shortcuts:
                GuideShortcutsPage(model: model)
            case .whatsNew:
                ForEach(chapter.categories) { category in
                    GuideSectionHeader(title: category.title)
                    ForEach(category.entries) { entry in
                        GuideEntryRow(entry: entry, context: model.category(containing: entry.id)?.title) {
                            model.open(.entry(entry.id))
                        }
                    }
                }
            case .howTo, .troubleshooting:
                ForEach(chapter.entries) { entry in
                    GuideEntryRow(entry: entry, context: nil) { model.open(.entry(entry.id)) }
                }
            }
        }
    }
}

private struct GuideCategoryPage: View {
    @ObservedObject var model: GuideModel
    let category: GuideCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideBackButton(model: model)
            GuidePageTitle(title: category.title, symbol: category.symbol)
            ForEach(category.entries) { entry in
                GuideEntryRow(entry: entry, context: nil) { model.open(.entry(entry.id)) }
            }
        }
    }
}

private struct GuideEntryPage: View {
    @ObservedObject var model: GuideModel
    let entry: GuideEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GuideBackButton(model: model)
            HStack(alignment: .center, spacing: 14) {
                GuideIconTile(symbol: entry.symbol, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    if let context = model.category(containing: entry.id)?.title {
                        Text(context.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(HomeColors.ink.opacity(0.45))
                    }
                    HStack(spacing: 8) {
                        Text(entry.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(HomeColors.ink.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                        if entry.isNew { GuideNewBadge() }
                    }
                }
            }
            GuideEntryBody(model: model, entry: entry, showsTitle: false)
        }
    }
}

/// A page's words: what it does, where it is, steps, keys, tips, Show me.
private struct GuideEntryBody: View {
    @ObservedObject var model: GuideModel
    let entry: GuideEntry
    let showsTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitle {
                HStack(spacing: 10) {
                    GuideIconTile(symbol: entry.symbol, size: 30)
                    Text(entry.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(HomeColors.ink.opacity(0.94))
                    if entry.isNew { GuideNewBadge() }
                    Spacer(minLength: 0)
                    if case .systemSettings(let pane) = entry.showMe, let allowed = pane.isAllowed {
                        GuidePermissionStatus(isAllowed: allowed)
                    }
                }
            }
            GuideParagraph(text: entry.summary, size: showsTitle ? 13.5 : 14.5)
            if !entry.points.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(entry.points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: "•")
                                .foregroundStyle(HomeColors.ink.opacity(0.45))
                            GuideParagraph(text: point)
                        }
                    }
                }
            }

            if let location = entry.location {
                GuideBlock(title: L("Where to find it"), symbol: "mappin.and.ellipse") {
                    GuideParagraph(text: location)
                }
            }
            if !entry.steps.isEmpty {
                GuideBlock(title: L("Steps"), symbol: "list.number") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(entry.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(verbatim: "\(index + 1)")
                                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                                    .foregroundStyle(HomeColors.ink.opacity(0.75))
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(HomeColors.ink.opacity(0.09)))
                                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                                GuideParagraph(text: step)
                            }
                        }
                    }
                }
            }
            if !entry.keys.isEmpty {
                GuideBlock(title: L("Keyboard"), symbol: "keyboard") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(entry.keys, id: \.self) { key in
                            GuideKeyRow(key: key)
                        }
                    }
                }
            }
            if !entry.tips.isEmpty {
                GuideBlock(title: L("Good to know"), symbol: "lightbulb") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(entry.tips, id: \.self) { tip in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(verbatim: "•")
                                    .foregroundStyle(HomeColors.ink.opacity(0.45))
                                GuideParagraph(text: tip)
                            }
                        }
                    }
                }
            }
            if let destination = entry.showMe {
                GuideShowMeButton(model: model, destination: destination)
            }
            if !entry.related.isEmpty {
                let related = entry.related.compactMap(model.entry)
                if !related.isEmpty {
                    GuideBlock(title: L("See also"), symbol: "arrow.turn.down.right") {
                        GuideFlow(spacing: 8) {
                            ForEach(related) { other in
                                Button { model.open(.entry(other.id)) } label: {
                                    Label(other.title, systemImage: other.symbol)
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 10)
                                        .frame(height: 26)
                                        .background(HomeColors.ink.opacity(0.07), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(HomeColors.ink.opacity(0.8))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Keyboard shortcuts page

private struct GuideShortcutsPage: View {
    @ObservedObject var model: GuideModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                model.show(.settings(.shortcuts))
            } label: {
                Label(L("Change Shortcuts in Settings"), systemImage: "keyboard")
            }
            .controlSize(.large)
            ForEach(GuideContent.shortcutGroups(), id: \.title) { group in
                GuideCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: group.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(HomeColors.ink.opacity(0.7))
                            Text(group.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(HomeColors.ink.opacity(0.92))
                        }
                        if let note = group.note {
                            GuideParagraph(text: note, size: 12, opacity: 0.55)
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(group.keys, id: \.self) { key in
                                GuideKeyRow(key: key)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

private struct GuidePageTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            GuideIconTile(symbol: symbol, size: 36)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(HomeColors.ink.opacity(0.95))
        }
    }
}

private struct GuideSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(HomeColors.ink.opacity(0.9))
            .padding(.top, 6)
    }
}

private struct GuideParagraph: View {
    let text: String
    var size: CGFloat = 13.5
    var opacity: Double = 0.8

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .lineSpacing(2.5)
            .foregroundStyle(HomeColors.ink.opacity(opacity))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private struct GuideBlock<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(HomeColors.ink.opacity(0.48))
            content
        }
        .padding(.top, 2)
    }
}

private struct GuideCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HomeColors.stroke, lineWidth: 1))
    }
}

private struct GuideIconTile: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(HomeColors.ink.opacity(0.85))
            .frame(width: size, height: size)
            .background(HomeColors.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

private struct GuideNewBadge: View {
    var body: some View {
        Text(L("New"))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(HomeColors.brand, in: Capsule())
            .fixedSize()
    }
}

private struct GuideEntryRow: View {
    let entry: GuideEntry
    let context: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GuideIconTile(symbol: entry.symbol, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(entry.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(HomeColors.ink.opacity(0.94))
                        if entry.isNew { GuideNewBadge() }
                        if let context {
                            Text(context)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(HomeColors.ink.opacity(0.42))
                                .lineLimit(1)
                        }
                    }
                    Text(entry.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(HomeColors.ink.opacity(0.58))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HomeColors.ink.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? HomeColors.cardHover : HomeColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HomeColors.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct GuideCategoryCard: View {
    let category: GuideCategory
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GuideIconTile(symbol: category.symbol, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(category.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(HomeColors.ink.opacity(0.94))
                            .lineLimit(1)
                        if category.entries.contains(where: \.isNew) { GuideNewBadge() }
                    }
                    Text(category.entries.prefix(3).map(\.title).joined(separator: " · "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(HomeColors.ink.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? HomeColors.cardHover : HomeColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HomeColors.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct GuideBackButton: View {
    @ObservedObject var model: GuideModel

    var body: some View {
        if !model.history.isEmpty {
            Button { model.back() } label: {
                Label(L("Back"), systemImage: "chevron.left")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(HomeColors.ink.opacity(0.65))
        }
    }
}

private struct GuideKeyRow: View {
    let key: GuideKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let keys = key.currentKeys {
                GuideKeycap(text: keys)
            } else {
                Text(L("Not set"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(HomeColors.ink.opacity(0.42))
                    .frame(minWidth: 52, alignment: .leading)
            }
            Text(key.label)
                .font(.system(size: 13))
                .foregroundStyle(HomeColors.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GuideKeycap: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(HomeColors.ink.opacity(0.88))
            .padding(.horizontal, 7)
            .frame(minWidth: 52, minHeight: 22)
            .background(HomeColors.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(HomeColors.stroke, lineWidth: 1))
            .fixedSize()
    }
}

private struct GuidePermissionStatus: View {
    let isAllowed: Bool

    var body: some View {
        Label(isAllowed ? L("Allowed") : L("Not allowed yet"), systemImage: isAllowed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(isAllowed ? Color.green : Color.orange)
            .fixedSize()
    }
}

private struct GuideShowMeButton: View {
    @ObservedObject var model: GuideModel
    let destination: GuideDestination

    var body: some View {
        let available = GuideModel.isAvailable(destination)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.show(destination)
            } label: {
                Label(Self.title(for: destination), systemImage: Self.symbol(for: destination))
            }
            .controlSize(.large)
            .disabled(!available)
            if !available {
                GuideParagraph(text: L("Open a recording in the video editor first, then click Show me."), size: 12, opacity: 0.55)
            }
        }
        .padding(.top, 4)
    }

    static func title(for destination: GuideDestination) -> String {
        switch destination {
        case .systemSettings: return L("Open System Settings")
        case .page(let id): return L("Read: \(GuideContent.title(of: id))")
        default: return L("Show me")
        }
    }

    static func symbol(for destination: GuideDestination) -> String {
        switch destination {
        case .systemSettings: return "gear"
        case .page: return "book"
        default: return "arrow.up.forward.app"
        }
    }
}

/// Lays chips out in rows.
private struct GuideFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
