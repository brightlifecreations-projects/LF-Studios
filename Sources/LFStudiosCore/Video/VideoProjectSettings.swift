import SwiftUI

// MARK: - Project settings (1.16.0)

/// The colours a video is made in: Rec. 709 for every screen, or Display P3
/// for Apple's wider-colour screens. Same look; P3 can show deeper colours.
enum VideoColorSpace: String, Codable, CaseIterable, Identifiable {
    case rec709
    case displayP3

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rec709: return "Rec. 709" // l10n-ignore: standard's name
        case .displayP3: return "Display P3" // l10n-ignore: standard's name
        }
    }

    var detail: String {
        switch self {
        case .rec709: return L("Standard video colours. Looks the same on every screen and site.")
        case .displayP3: return L("Wider colours for Apple screens. Elsewhere it looks like Rec. 709.")
        }
    }
}

/// A project's resolution, frame rate and colour space, set in Project
/// settings (click the project's name). Export starts from them. A project
/// that never set them has none (`projectSettings` is nil) and exports as
/// before, from the export window's last choices.
struct VideoProjectSettings: Codable, Equatable {
    static let frameRates = [24, 25, 30, 50, 60]

    /// 720, 1080, 1440 or 2160 (4K): the picture's height.
    var height: Int
    var frameRate: Int
    var colorSpace: VideoColorSpace

    var resolution: VideoExportSettings.Resolution {
        get { VideoExportSettings.Resolution(rawValue: height) ?? .p1080 }
        set { height = newValue.rawValue }
    }

    init(resolution: VideoExportSettings.Resolution, frameRate: Int, colorSpace: VideoColorSpace) {
        self.height = resolution.rawValue
        self.frameRate = Self.frameRates.contains(frameRate) ? frameRate : 30
        self.colorSpace = colorSpace
    }

    /// What a project without settings exports at now.
    static func current(from export: VideoExportSettings) -> VideoProjectSettings {
        VideoProjectSettings(resolution: export.resolution, frameRate: export.fps, colorSpace: export.colorSpace)
    }

    /// The export window's starting point.
    func apply(to export: inout VideoExportSettings) {
        export.resolution = resolution
        export.fps = frameRate
        export.colorSpace = colorSpace
    }

    var summary: String {
        "\(resolution.title) · \(frameRate) fps · \(colorSpace.title)"
    }
}

extension VideoEditorModel {
    /// Project settings: one undo step; the export window starts from them.
    func setProjectSettings(_ settings: VideoProjectSettings) {
        guard settings != project.projectSettings else { return }
        mutate(label: "Project Settings") { $0.projectSettings = settings }
        applyProjectSettingsToExport()
    }

    /// The export window starts from the project's settings, when it has
    /// some (a project without keeps the export's last choices).
    func applyProjectSettingsToExport() {
        guard let settings = project.projectSettings else { return }
        var export = exportSettings
        settings.apply(to: &export)
        if export != exportSettings { exportSettings = export }
    }

    /// What the window shows: the project's, or what it exports at now.
    var shownProjectSettings: VideoProjectSettings {
        project.projectSettings ?? .current(from: exportSettings)
    }
}

/// The Project settings window: resolution, frame rate, colour space.
struct VideoProjectSettingsSheet: View {
    @ObservedObject var model: VideoEditorModel
    @State private var settings: VideoProjectSettings

    init(model: VideoEditorModel) {
        self.model = model
        _settings = State(initialValue: model.shownProjectSettings)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { model.isProjectSettingsPresented = false }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("Project Settings"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(VideoEditorTheme.textPrimary)
                    Spacer()
                    Button { model.isProjectSettingsPresented = false } label: {
                        Image(systemName: "xmark").frame(width: 26, height: 26)
                    }
                    .buttonStyle(VideoToolButtonStyle())
                    .help(L("Close (Esc)"))
                    .accessibilityLabel(L("Close"))
                }
                Text(model.project.sourceURL.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .lineLimit(1)

                row(L("Resolution")) {
                    VideoSegmented(options: VideoExportSettings.Resolution.allCases.map { ($0, $0.title) }, selection: $settings.resolution)
                }
                row(L("Frame rate")) {
                    VideoSegmented(options: VideoProjectSettings.frameRates.map { ($0, "\($0)") }, selection: $settings.frameRate)
                }
                row(L("Colour space")) {
                    VStack(alignment: .leading, spacing: 4) {
                        VideoSegmented(options: VideoColorSpace.allCases.map { ($0, $0.title) }, selection: $settings.colorSpace)
                        Text(settings.colorSpace.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(VideoEditorTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(L("Export starts from these. You can still choose something else in the export window."))
                    .font(.system(size: 11))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(L("Cancel")) { model.isProjectSettingsPresented = false }
                        .buttonStyle(VideoSecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(L("Done")) {
                        model.perform(.projectSettings(settings))
                        model.isProjectSettingsPresented = false
                    }
                    .buttonStyle(VideoPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 440)
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VideoEditorTheme.popover))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
            .shadow(color: VideoEditorTheme.shadow, radius: 30, y: 16)
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VideoEditorTheme.textPrimary)
            content()
        }
    }
}
