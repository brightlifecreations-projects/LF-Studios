import AppKit
import SwiftUI

// MARK: - The job

/// A handoff being written in the background; the dialog (or the pill in
/// the editor once the dialog is closed) shows it.
@MainActor
final class VideoHandoffJob: ObservableObject {
    enum State: Equatable {
        case preparing
        case running(VideoHandoffWriter.Progress)
        case finished(folder: URL, skipped: [String])
        case failed(String)
    }

    @Published private(set) var state: State = .preparing
    private var cancelled = false
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch state {
        case .preparing, .running: return true
        default: return false
        }
    }

    func start(plan: VideoHandoffPlan, input: VideoHandoffInput, location: URL) {
        let writer = VideoHandoffWriter(plan: plan, input: input, parent: location)
        writer.progress = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.state = .running(progress)
            }
        }
        let flag = CancelFlag()
        writer.isCancelled = { flag.value }
        cancelFlag = flag
        task = Task {
            let accessing = location.startAccessingSecurityScopedResource()
            defer { if accessing { location.stopAccessingSecurityScopedResource() } }
            do {
                let result = try await writer.run()
                state = .finished(folder: result.folder, skipped: result.skipped)
                NSSound(named: "Glass")?.play()
            } catch is CancellationError {
                state = .failed(L("Cancelled — the partly made folder was removed"))
            } catch {
                state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private var cancelFlag: CancelFlag?

    func cancel() {
        cancelled = true
        cancelFlag?.value = true
    }

    final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var value: Bool {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }
}

// MARK: - Editor

extension VideoEditorModel {
    /// The name the handoff folder and the finished video carry.
    var handoffName: String {
        projectFileURL?.deletingPathExtension().lastPathComponent ?? project.sourceURL.deletingPathExtension().lastPathComponent
    }

    /// File ▸ Creative Handoff… (⇧⌘E) and the export dialog's button.
    func showCreativeHandoff() {
        guard isReady else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            isExportPresented = false
            isHandoffPresented = true
        }
    }

    func showCreativeHandoffWhenReady() {
        if isReady { showCreativeHandoff() } else { handoffWhenReady = true }
    }

    func closeCreativeHandoff() {
        withAnimation(.easeOut(duration: 0.15)) { isHandoffPresented = false }
        if let job = handoffJob, !job.isRunning { handoffJob = nil }
    }

    /// What this edit would hand off with `options` (and the folder's name
    /// in `location`).
    func handoffPlan(options: VideoHandoffOptions, location: URL?) async -> (VideoHandoffPlan, VideoHandoffInput) {
        let input = await VideoHandoffInput.gather(
            name: handoffName, project: project, recording: recording,
            appendedMetadata: media.appendedMetadata.compactMapValues { $0 }, exportSettings: exportSettings
        )
        let name = VideoHandoffPlanner.folderName(project: handoffName) { name in
            location.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(name).path) } ?? false
        }
        return (VideoHandoffPlanner.plan(input, options: options, folderName: name), input)
    }

    func startCreativeHandoff(options: VideoHandoffOptions, location: URL) {
        options.save()
        VideoHandoffOptions.remember(location: location)
        let job = VideoHandoffJob()
        handoffJob = job
        Task {
            let (plan, input) = await handoffPlan(options: options, location: location)
            job.start(plan: plan, input: input, location: location)
        }
    }
}

// MARK: - The dialog

struct VideoHandoffSheet: View {
    @ObservedObject var model: VideoEditorModel
    @State private var options = VideoHandoffOptions.load()
    @State private var location: URL? = VideoHandoffOptions.lastLocation()
    @State private var plan: VideoHandoffPlan?
    @State private var available: Int64?

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { model.closeCreativeHandoff() }
            VStack(alignment: .leading, spacing: 16) {
                header
                if let job = model.handoffJob {
                    VideoHandoffProgressView(job: job, model: model)
                } else {
                    form
                }
            }
            .padding(22)
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VideoEditorTheme.popover))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
            .shadow(color: VideoEditorTheme.shadow, radius: 40, y: 20)
        }
        .task(id: options) { await refreshPlan() }
        .task(id: location) { await refreshPlan() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Creative Handoff"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Text(L("Every part of this video as its own file, in a new folder — for another editor or editing app."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { model.closeCreativeHandoff() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
            }
            .buttonStyle(VideoToolButtonStyle())
            .accessibilityLabel(L("Close"))
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(L("Clips")) {
                VideoSegmented(options: [(VideoHandoffOptions.Clips.trimmed, L("Trimmed to my edit")), (.full, L("Full original files"))], selection: $options.clips)
            }
            VideoToggleRow(title: L("Line everything up"), detail: L("Every file starts at the same moment and is as long as the others: drop them all at 0:00 and they play in sync, the camera too."), isOn: $options.lineUp)
            VideoToggleRow(title: L("Include the finished video"), detail: L("Exported with your export settings"), isOn: $options.includeFinal)
            VideoToggleRow(title: L("Include a timeline for editing apps"), detail: L("For Final Cut Pro, DaVinci Resolve, and Adobe Premiere Pro"), isOn: $options.includeTimeline)
            let hasNotes = !(model.project.speakerNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            VideoToggleRow(
                title: L("Include speaker notes"),
                detail: hasNotes ? L("Your notes from recording, as Notes.txt") : L("This video has no speaker notes"),
                isOn: Binding(get: { hasNotes && options.includeSpeakerNotes }, set: { options.includeSpeakerNotes = $0 })
            )
            .disabled(!hasNotes)
            row(L("Quality")) {
                VideoSegmented(options: [(VideoHandoffOptions.Quality.proRes422HQ, L("Best (ProRes 422 HQ)")), (.proRes422, L("Smaller files (ProRes 422)"))], selection: $options.quality)
            }
            Text(L("Files are copied as they are wherever they can be. Only what has to change — clips cut to your edit, a camera with its background removed — is re-encoded to ProRes."))
                .font(.system(size: 10.5))
                .foregroundStyle(VideoEditorTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundStyle(VideoEditorTheme.textSecondary)
                Text(location.map { $0.path } ?? L("No location chosen"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(location == nil ? VideoEditorTheme.textTertiary : VideoEditorTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Button(L("Choose Location…")) { chooseLocation() }
                    .buttonStyle(VideoSecondaryButtonStyle())
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(VideoEditorTheme.well))

            if let plan {
                summary(plan)
            }

            HStack {
                Spacer()
                Button(L("Cancel")) { model.closeCreativeHandoff() }
                    .buttonStyle(VideoSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    guard let location else { return }
                    model.startCreativeHandoff(options: options, location: location)
                } label: {
                    Label(L("Create Handoff"), systemImage: "shippingbox")
                }
                .buttonStyle(VideoPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(location == nil || plan == nil || !fits)
            }
        }
    }

    private var fits: Bool {
        guard let plan, let available else { return true }
        return available >= Int64(Double(plan.estimatedBytes) * 1.1)
    }

    @ViewBuilder
    private func summary(_ plan: VideoHandoffPlan) -> some View {
        let files = plan.items.count
        let size = ByteCountFormatter.string(fromByteCount: plan.estimatedBytes, countStyle: .file)
        VStack(alignment: .leading, spacing: 5) {
            Text(L("\(files) files, about \(size)") + (available.map { L(" — \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)) free there") } ?? ""))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(fits ? VideoEditorTheme.textSecondary : VideoEditorTheme.warning)
            if !fits {
                Label(L("It won't fit there. Choose another location, or pick Smaller files."), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.warning)
            }
            if plan.reencodes, !VideoHandoffWriter.hasProResHardware {
                Text(L("This Mac has no ProRes chip, so the re-encoded files take a while — the progress shows how long."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(plan.skipped, id: \.self) { reason in
                Label(reason, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoEditorTheme.warning)
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VideoEditorTheme.textPrimary)
                .frame(width: VideoEditorTheme.rowTitleWidth([L("Clips"), L("Quality")]), alignment: .leading)
            content()
        }
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Choose")
        panel.message = L("Choose where to put the handoff folder — any folder or drive")
        panel.directoryURL = location
        guard panel.runModal() == .OK, let url = panel.url else { return }
        location = url
    }

    private func refreshPlan() async {
        let (plan, _) = await model.handoffPlan(options: options, location: location)
        self.plan = plan
        available = location.flatMap { VideoExportFiles.availableBytes(at: $0) }
    }
}

/// Writing: the file, the progress, time left, Cancel; then Reveal in Finder.
struct VideoHandoffProgressView: View {
    @ObservedObject var job: VideoHandoffJob
    let model: VideoEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch job.state {
            case .preparing:
                ProgressView().controlSize(.small)
                Text(L("Getting ready…")).font(.system(size: 12)).foregroundStyle(VideoEditorTheme.textSecondary)
            case .running(let progress):
                Text(L("File \(progress.index + 1) of \(progress.count): \(progress.file)"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView(value: progress.fraction).tint(VideoEditorTheme.primary)
                ProgressView(value: progress.overall) {
                    Text(L("All files")).font(.system(size: 11)).foregroundStyle(VideoEditorTheme.textSecondary)
                } currentValueLabel: {
                    Text(Self.left(progress)).font(.system(size: 11)).foregroundStyle(VideoEditorTheme.textSecondary)
                }
                HStack {
                    Text(L("You can close this — the handoff keeps going."))
                        .font(.system(size: 10.5)).foregroundStyle(VideoEditorTheme.textTertiary)
                    Spacer()
                    Button(L("Cancel")) { job.cancel() }
                        .buttonStyle(VideoSecondaryButtonStyle(destructive: true))
                }
            case .finished(let folder, let skipped):
                Label(L("The handoff is ready"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Text(folder.path)
                    .font(.system(size: 11)).foregroundStyle(VideoEditorTheme.textSecondary)
                    .lineLimit(2).truncationMode(.middle)
                if !skipped.isEmpty {
                    Text(L("Left out:")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(VideoEditorTheme.warning)
                    ForEach(skipped, id: \.self) { reason in
                        Text("• \(reason)").font(.system(size: 11)).foregroundStyle(VideoEditorTheme.textSecondary) // l10n-ignore: a bullet before a translated reason
                    }
                }
                HStack {
                    Spacer()
                    Button(L("Done")) { model.closeCreativeHandoff() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                    Button(L("Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        .buttonStyle(VideoPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(L("OK")) { model.handoffJob = nil; model.closeCreativeHandoff() }
                        .buttonStyle(VideoSecondaryButtonStyle())
                }
            }
        }
    }

    static func left(_ progress: VideoHandoffWriter.Progress) -> String {
        let percent = VideoEditorFormat.percent(progress.overall)
        guard let seconds = progress.secondsLeft, seconds > 20 else { return percent }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes <= 1 ? L("\(percent) — about a minute left") : L("\(percent) — about \(minutes) min left")
    }
}

/// The handoff's progress in the editor once its dialog is closed: click
/// to open it again.
struct VideoHandoffPill: View {
    @ObservedObject var job: VideoHandoffJob
    let model: VideoEditorModel

    var body: some View {
        Button { model.showCreativeHandoff() } label: {
            HStack(spacing: 7) {
                switch job.state {
                case .preparing, .running:
                    ProgressView().controlSize(.mini)
                    if case .running(let progress) = job.state {
                        Text(L("Handoff — \(VideoHandoffProgressView.left(progress))"))
                    } else {
                        Text(L("Handoff — getting ready"))
                    }
                case .finished:
                    Image(systemName: "checkmark.circle.fill")
                    Text(L("Handoff ready — show it"))
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(L("Handoff didn't finish"))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.black.opacity(0.78)))
        }
        .buttonStyle(.plain)
    }
}
