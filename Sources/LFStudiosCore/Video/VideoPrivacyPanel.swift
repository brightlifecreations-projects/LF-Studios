import AppKit
import AVFoundation
import SwiftUI

// MARK: - The scan

/// "Find private info": scans in the background, lists what it found,
/// and blurs nothing until the user ticks items and presses Blur selected.
@MainActor
final class VideoPrivacyJob: ObservableObject {
    enum State: Equatable {
        case idle
        case scanning(Double)
        case done
        case failed(String)
    }

    struct Target {
        var url: URL
        /// Source time = file time + offset.
        var offset: Double
        var onCamera: Bool
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var items: [VideoPrivacyItem] = []
    /// Ticked for blurring: none to start with.
    @Published var checked: Set<UUID> = []
    @Published private(set) var blurred: Set<UUID> = []
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]
    @Published var customWords: String {
        didSet { UserDefaults.standard.set(customWords, forKey: "privacyCustomWords") }
    }
    /// Things behind you (a whiteboard, a document) on the camera video.
    @Published var scanCamera: Bool {
        didSet { UserDefaults.standard.set(scanCamera, forKey: "privacyScanCamera") }
    }

    private var task: Task<Void, Never>?

    init() {
        customWords = UserDefaults.standard.string(forKey: "privacyCustomWords") ?? ""
        scanCamera = UserDefaults.standard.bool(forKey: "privacyScanCamera")
    }

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    /// The custom words, one per line or comma.
    var words: [String] {
        customWords.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func targets(project: VideoDemoProject, recording: VideoDemoRecordingMetadata?, camera: Bool) -> [Target] {
        var targets: [Target] = []
        if project.sources.isEmpty {
            targets.append(Target(url: project.sourceURL, offset: 0, onCamera: false))
        } else {
            for source in project.sources {
                guard let url = source.isPrimary ? project.sourceURL : VideoSourceLocator.resolve(source) else { continue }
                targets.append(Target(url: url, offset: source.offset, onCamera: false))
            }
        }
        if camera, let footage = project.activeCamera(recorded: recording?.webcam) {
            let url = project.importedCamera?.resolved() ?? footage.url
            if FileManager.default.fileExists(atPath: url.path) {
                targets.append(Target(url: url, offset: footage.offset, onCamera: true))
            }
        }
        return targets
    }

    func start(project: VideoDemoProject, recording: VideoDemoRecordingMetadata?) {
        guard !isScanning else { return }
        let targets = Self.targets(project: project, recording: recording, camera: scanCamera)
        let words = words
        state = .scanning(0)
        items = []
        checked = []
        blurred = []
        thumbnails = [:]
        task = Task { [weak self] in
            do {
                var found: [VideoPrivacyItem] = []
                for (index, target) in targets.enumerated() {
                    let share = 1 / Double(max(targets.count, 1))
                    let scan = try await Task.detached(priority: .userInitiated) {
                        try await VideoPrivacyReader.scan(url: target.url) { fraction in
                            Task { @MainActor in
                                guard let self, self.isScanning else { return }
                                self.state = .scanning((Double(index) + fraction) * share)
                            }
                        }
                    }.value
                    try Task.checkCancellation()
                    found += VideoPrivacyTracker.items(from: scan, timeOffset: target.offset, onCamera: target.onCamera, customWords: words)
                }
                guard let self else { return }
                self.present(found)
                self.task = nil
                await self.makeThumbnails(targets: targets)
            } catch {
                guard let self else { return }
                self.task = nil
                self.state = error is CancellationError || Task.isCancelled ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    /// A finished scan's items, none ticked.
    func present(_ found: [VideoPrivacyItem]) {
        items = found.sorted { $0.start < $1.start }
        checked = []
        blurred = []
        state = .done
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    func markBlurred(_ ids: Set<UUID>) {
        blurred.formUnion(ids)
        checked.subtract(ids)
    }

    /// A small picture of each find, from the middle of when it shows.
    private func makeThumbnails(targets: [Target]) async {
        for target in targets {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: target.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 1280)
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 10)
            generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
            for item in items where item.onCamera == target.onCamera && thumbnails[item.id] == nil {
                let key = item.keys[item.keys.count / 2]
                guard let image = try? await generator.image(at: CMTime(seconds: max(key.time - target.offset, 0), preferredTimescale: 600)).image else { continue }
                let w = Double(image.width), h = Double(image.height)
                let box = key.box
                let side = max(box.width * w, box.height * h) * 1.8 + 40
                let rect = CGRect(x: box.center.x * w - side * 0.9, y: box.center.y * h - side / 2, width: side * 1.8, height: side).intersection(CGRect(x: 0, y: 0, width: w, height: h))
                guard let crop = image.cropping(to: rect) else { continue }
                thumbnails[item.id] = NSImage(cgImage: crop, size: CGSize(width: crop.width, height: crop.height))
            }
        }
    }
}

// MARK: - Editor

extension VideoEditorModel {
    func showPrivacyScan() {
        pause()
        withAnimation(.easeOut(duration: 0.15)) { isPrivacyPresented = true }
    }

    func closePrivacyScan() {
        withAnimation(.easeOut(duration: 0.15)) { isPrivacyPresented = false }
    }

    func startPrivacyScan() {
        privacyJob.start(project: project, recording: recording)
    }

    /// The ticked items as normal blur blocks (one ⌘Z), each following its
    /// item; they can be moved, resized, or deleted like any blur.
    func blurSelectedPrivateInfo() {
        let chosen = privacyJob.items.filter { privacyJob.checked.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let crop = project.crop.normalized
        let strength = VideoOverlayStyleMemory.blurStrength
        mutate(label: "Blur Private Info") { project in
            for item in chosen {
                let overlapping = project.overlayEffects.filter { $0.time < item.end && $0.time + $0.duration > item.start }
                let layer = (overlapping.map(\.layer).max() ?? -1) + 1
                project.overlayEffects.append(item.blurEffect(crop: crop, layer: layer, strength: strength))
            }
            project.overlayEffects = VideoDemoProject.normalizedEffectLayers(project.overlayEffects)
        }
        privacyJob.markBlurred(Set(chosen.map(\.id)))
        showNotice(L("Blurred \(chosen.count) items — adjust or delete them on the timeline"), symbol: "eye.slash", duration: 3.5)
    }
}

// MARK: - The dialog

struct VideoPrivacySheet: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var job: VideoPrivacyJob

    init(model: VideoEditorModel) {
        self.model = model
        self.job = model.privacyJob
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { model.closePrivacyScan() }
            VStack(alignment: .leading, spacing: 14) {
                header
                options
                switch job.state {
                case .idle:
                    EmptyView()
                case .scanning(let fraction):
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L("Looking through the video…"))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(VideoEditorTheme.textPrimary)
                            Spacer()
                            Text(VideoEditorFormat.percent(fraction))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(VideoEditorTheme.textSecondary)
                        }
                        ProgressView(value: fraction).progressViewStyle(.linear)
                        Text(L("Keep editing — close this and it carries on."))
                            .font(.system(size: 10.5))
                            .foregroundStyle(VideoEditorTheme.textTertiary)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange)
                case .done:
                    results
                }
                footer
            }
            .padding(22)
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VideoEditorTheme.popover))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(VideoEditorTheme.cardStroke, lineWidth: 1))
            .shadow(color: VideoEditorTheme.shadow, radius: 40, y: 20)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Find Private Info"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Text(L("Faces, email addresses, phone and card numbers, keys and passwords on screen, and your own words. Read on this Mac with Apple's Vision; nothing is blurred until you choose."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { model.closePrivacyScan() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
            }
            .buttonStyle(VideoToolButtonStyle())
            .accessibilityLabel(L("Close"))
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Also look for these words"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                TextField(L("Client names, project code names… (separate with commas)"), text: $job.customWords)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
            VideoToggleRow(title: L("Also scan the camera video"), detail: L("For things behind you, like a whiteboard or a document"), isOn: $job.scanCamera)
                .disabled(model.project.activeCamera(recorded: model.recording?.webcam) == nil)
        }
        .disabled(job.isScanning)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job.items.isEmpty ? L("Nothing private found") : L("Found \(job.items.count)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textPrimary)
                Spacer()
                if !job.items.isEmpty {
                    Button(job.checked.count == job.items.count - job.blurred.count ? L("Select None") : L("Select All")) {
                        let open = Set(job.items.map(\.id)).subtracting(job.blurred)
                        job.checked = job.checked == open ? [] : open
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                }
            }
            if !job.items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(job.items) { item in
                            row(item)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func row(_ item: VideoPrivacyItem) -> some View {
        let isBlurred = job.blurred.contains(item.id)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { job.checked.contains(item.id) },
                set: { on in if on { job.checked.insert(item.id) } else { job.checked.remove(item.id) } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(isBlurred)
            .accessibilityLabel(L("Blur \(item.kind.title) \(item.label)"))
            Group {
                if let image = job.thumbnails[item.id] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.kind.symbol).foregroundStyle(VideoEditorTheme.textTertiary)
                }
            }
            .frame(width: 84, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(VideoEditorTheme.ink.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Label(item.kind.title, systemImage: item.kind.symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(item.kind == .possibleKey ? Color.orange : VideoEditorTheme.textPrimary)
                    if item.onCamera {
                        Text(L("Camera"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(VideoEditorTheme.ink.opacity(0.08)))
                    }
                    if isBlurred {
                        Text(L("Blurred"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(item.label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.seek(to: model.timelineTime(forSource: item.start + 0.2) ?? item.start)
            } label: {
                Text(timeRange(item))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VideoEditorTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(L("Jump here"))
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VideoEditorTheme.ink.opacity(0.035)))
    }

    private func timeRange(_ item: VideoPrivacyItem) -> String {
        let start = model.timelineTime(forSource: max(item.start, 0)) ?? item.start
        let end = model.timelineTime(forSource: item.end) ?? item.end
        return "\(VideoEditorModel.timecode(start))–\(VideoEditorModel.timecode(max(end, start)))"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if job.isScanning {
                Button(L("Cancel")) { job.cancel() }
                    .buttonStyle(VideoSecondaryButtonStyle())
            } else {
                Button(job.state == .done ? L("Scan Again") : L("Find Private Info")) { model.startPrivacyScan() }
                    .buttonStyle(job.state == .done ? AnyButtonStyle(VideoSecondaryButtonStyle()) : AnyButtonStyle(VideoPrimaryButtonStyle()))
                    .disabled(!model.isReady)
            }
            Spacer()
            if job.state == .done, !job.items.isEmpty {
                Button(L("Blur Selected (\(job.checked.count))")) { model.blurSelectedPrivateInfo() }
                    .buttonStyle(VideoPrimaryButtonStyle())
                    .disabled(job.checked.isEmpty)
            }
        }
    }
}

/// Picks one of two button styles at run time.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
