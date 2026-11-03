import AppKit
import AVFoundation
import AVKit
import MediaToolbox
import os
import SwiftUI

// MARK: - Safe zones and grid (1.21.0)

/// Guides drawn over the player only: never in the export (the renderer
/// never sees them). All off to start with.
enum VideoPlayerGuide: String, CaseIterable, Identifiable {
    case titleSafe, actionSafe, thirds, centre, tiktok, reels, shorts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .titleSafe: return L("Title safe")
        case .actionSafe: return L("Action safe")
        case .thirds: return L("Rule of thirds")
        case .centre: return L("Centre lines")
        case .tiktok: return "TikTok" // l10n-ignore: a name
        case .reels: return "Instagram Reels" // l10n-ignore: a name
        case .shorts: return "YouTube Shorts" // l10n-ignore: a name
        }
    }

    /// The apps' own buttons and captions cover these parts of a 9:16
    /// video (approximate: the apps change them, and don't publish sizes).
    var isSocial: Bool { [.tiktok, .reels, .shorts].contains(self) }

    /// Covered parts as fractions of the frame (x, y from the top-left,
    /// width, height): the caption and name at the bottom, the buttons on
    /// the right, the top bar.
    var coveredAreas: [CGRect] {
        switch self {
        case .tiktok:
            return [CGRect(x: 0, y: 0, width: 1, height: 0.07), CGRect(x: 0.86, y: 0.35, width: 0.14, height: 0.45), CGRect(x: 0, y: 0.80, width: 1, height: 0.20)]
        case .reels:
            return [CGRect(x: 0, y: 0, width: 1, height: 0.08), CGRect(x: 0.87, y: 0.45, width: 0.13, height: 0.37), CGRect(x: 0, y: 0.82, width: 1, height: 0.18)]
        case .shorts:
            return [CGRect(x: 0, y: 0, width: 1, height: 0.06), CGRect(x: 0.86, y: 0.42, width: 0.14, height: 0.40), CGRect(x: 0, y: 0.80, width: 1, height: 0.20)]
        default:
            return []
        }
    }
}

extension VideoEditorModel {
    /// A 9:16 (or narrower) video: the social apps' areas apply.
    var isVertical: Bool {
        let canvas = project.canvasSize()
        return canvas.height > 0 && canvas.width / canvas.height < 0.6
    }

    func togglePlayerGuide(_ guide: VideoPlayerGuide) {
        if playerGuides.contains(guide) { playerGuides.remove(guide) } else { playerGuides.insert(guide) }
    }
}

/// The guides, drawn over a player of `size`.
struct VideoPlayerGuidesView: View {
    let guides: Set<VideoPlayerGuide>
    let size: CGSize
    let vertical: Bool

    var body: some View {
        Canvas { context, size in
            let line = Color.white.opacity(0.75)
            let shade = Color.black.opacity(0.35)
            func rect(inset: CGFloat) -> CGRect {
                CGRect(x: size.width * inset, y: size.height * inset, width: size.width * (1 - inset * 2), height: size.height * (1 - inset * 2))
            }
            if guides.contains(.actionSafe) {
                context.stroke(Path(rect(inset: 0.05)), with: .color(line), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
            if guides.contains(.titleSafe) {
                context.stroke(Path(rect(inset: 0.10)), with: .color(Color.yellow.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
            if guides.contains(.thirds) {
                var path = Path()
                for third in [1.0 / 3, 2.0 / 3] {
                    path.move(to: CGPoint(x: size.width * third, y: 0)); path.addLine(to: CGPoint(x: size.width * third, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height * third)); path.addLine(to: CGPoint(x: size.width, y: size.height * third))
                }
                context.stroke(path, with: .color(line.opacity(0.7)), lineWidth: 1)
            }
            if guides.contains(.centre) {
                var path = Path()
                path.move(to: CGPoint(x: size.width / 2, y: 0)); path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height / 2)); path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(path, with: .color(Color.cyan.opacity(0.8)), lineWidth: 1)
            }
            if vertical {
                for guide in VideoPlayerGuide.allCases where guide.isSocial && guides.contains(guide) {
                    for area in guide.coveredAreas {
                        let r = CGRect(x: area.minX * size.width, y: area.minY * size.height, width: area.width * size.width, height: area.height * size.height)
                        context.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(shade))
                        context.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(Color.red.opacity(0.7)), lineWidth: 1)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The player bar's guides menu.
struct VideoPlayerGuidesMenu: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        Menu {
            ForEach([VideoPlayerGuide.titleSafe, .actionSafe, .thirds, .centre]) { guide in
                toggle(guide)
            }
            Divider()
            Section(model.isVertical ? L("Social apps (9:16)") : L("Social apps (9:16 videos only)")) {
                ForEach([VideoPlayerGuide.tiktok, .reels, .shorts]) { guide in
                    toggle(guide).disabled(!model.isVertical)
                }
            }
            if !model.playerGuides.isEmpty {
                Divider()
                Button(L("Hide All Guides")) { model.playerGuides = [] }
            }
        } label: {
            Image(systemName: model.playerGuides.isEmpty ? "squareshape.split.3x3" : "squareshape.split.3x3")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(model.playerGuides.isEmpty ? VideoEditorTheme.textSecondary : Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Safe zones and grid (never in the export)"))
        .accessibilityLabel(L("Safe zones and grid"))
    }

    private func toggle(_ guide: VideoPlayerGuide) -> some View {
        Button {
            model.togglePlayerGuide(guide)
        } label: {
            if model.playerGuides.contains(guide) {
                Label(guide.title, systemImage: "checkmark")
            } else {
                Text(guide.title)
            }
        }
    }
}

// MARK: - Audio meters

/// The player's sound, as levels for the meters: a listening tap on each
/// of the player's sound tracks (the export never gets one).
enum VideoAudioMeterTap {
    /// Peaks since the meters last looked (0…1), written on the audio
    /// thread.
    final class Storage: @unchecked Sendable {
        struct Peaks { var left: Float = 0; var right: Float = 0 }
        let peaks = OSAllocatedUnfairLock(initialState: Peaks())
        let format = OSAllocatedUnfairLock(initialState: (isFloat: true, channels: 2, interleaved: false))

        func add(left: Float, right: Float) {
            peaks.withLock { $0.left = max($0.left, left); $0.right = max($0.right, right) }
        }

        func take() -> (left: Float, right: Float) {
            peaks.withLock { state in
                let taken = (state.left, state.right)
                state = Peaks()
                return taken
            }
        }
    }

    private static func storage(_ tap: MTAudioProcessingTap) -> Storage {
        Unmanaged<Storage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    /// A tap that measures and passes the sound on unchanged.
    static func make(_ storage: Storage) -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(storage).toOpaque()),
            init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
            finalize: { tap in Unmanaged<Storage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, _, description in
                let flags = description.pointee.mFormatFlags
                let format = (isFloat: flags & kAudioFormatFlagIsFloat != 0, channels: Int(description.pointee.mChannelsPerFrame), interleaved: flags & kAudioFormatFlagIsNonInterleaved == 0)
                VideoAudioMeterTap.storage(tap).format.withLock { $0 = format }
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr else { return }
                let storage = VideoAudioMeterTap.storage(tap)
                let format = storage.format.withLock { $0 }
                guard format.isFloat else { return }
                var left: Float = 0, right: Float = 0
                let list = UnsafeMutableAudioBufferListPointer(buffers)
                for (index, buffer) in list.enumerated() {
                    guard let data = buffer.mData else { continue }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = data.assumingMemoryBound(to: Float.self)
                    let channels = max(Int(buffer.mNumberChannels), 1)
                    for sample in 0..<count {
                        let level = abs(samples[sample])
                        let channel = format.interleaved ? sample % channels : index
                        if channel == 0 { left = max(left, level) }
                        if channel == 1 || (format.channels == 1 && channel == 0) { right = max(right, level) }
                    }
                }
                storage.add(left: left, right: right)
            }
        )
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr else { return nil }
        return tap
    }

    /// The player's mix with a tap on every sound track (levels as they
    /// are; fades and volumes kept).
    static func metered(_ mix: AVAudioMix?, composition: AVAsset, storage: Storage?) -> AVAudioMix? {
        guard let storage, let composition = composition as? AVComposition else { return mix }
        let tracks = composition.tracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return mix }
        let metered = AVMutableAudioMix()
        metered.inputParameters = tracks.map { track in
            let existing = mix?.inputParameters.first { $0.trackID == track.trackID }
            let parameters = (existing?.mutableCopy() as? AVMutableAudioMixInputParameters) ?? AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = make(storage)
            return parameters
        }
        return metered
    }
}

/// The meters' levels, refreshed while the player plays.
@MainActor
final class VideoAudioMeters: ObservableObject {
    let storage = VideoAudioMeterTap.Storage()
    /// 0…1 of the meter's height (−60 dB to 0 dB).
    @Published private(set) var left: Double = 0
    @Published private(set) var right: Double = 0
    /// The highest of the last moment, held a second.
    @Published private(set) var leftPeak: Double = 0
    @Published private(set) var rightPeak: Double = 0
    /// The loudest level seen since it last started (tests).
    private(set) var loudest: Double = 0
    private var timer: Timer?
    private var heldAt: (left: Date, right: Date) = (.distantPast, .distantPast)

    /// Where `amplitude` (0…1) sits on the meter.
    nonisolated static func position(forAmplitude amplitude: Float) -> Double {
        guard amplitude > 0.000_001 else { return 0 }
        let decibels = 20 * log10(Double(amplitude))
        return min(max((decibels + 60) / 60, 0), 1)
    }

    enum Zone: Equatable { case green, yellow, red }

    /// Green up to −12 dB, yellow up to −3 dB, red above.
    nonisolated static func zone(at position: Double) -> Zone {
        let decibels = position * 60 - 60
        if decibels > -3 { return .red }
        if decibels > -12 { return .yellow }
        return .green
    }

    func start() {
        guard timer == nil else { return }
        _ = storage.take()
        loudest = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Screenshots: levels as if it were playing.
    func show(left: Double, right: Double, leftPeak: Double, rightPeak: Double) {
        self.left = left; self.right = right; self.leftPeak = leftPeak; self.rightPeak = rightPeak
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        left = 0; right = 0; leftPeak = 0; rightPeak = 0
    }

    private func tick() {
        let peaks = storage.take()
        let now = Date()
        let newLeft = Self.position(forAmplitude: peaks.left), newRight = Self.position(forAmplitude: peaks.right)
        loudest = max(loudest, newLeft, newRight)
        // Up at once, down gently.
        left = max(newLeft, left - 0.04)
        right = max(newRight, right - 0.04)
        if left >= leftPeak || now.timeIntervalSince(heldAt.left) > 1 { leftPeak = left; heldAt.left = now }
        if right >= rightPeak || now.timeIntervalSince(heldAt.right) > 1 { rightPeak = right; heldAt.right = now }
    }
}

/// Two small bars, left and right, next to the player.
struct VideoAudioMeterView: View {
    @ObservedObject var meters: VideoAudioMeters

    var body: some View {
        VStack(spacing: 2) {
            bar(meters.left, peak: meters.leftPeak)
            bar(meters.right, peak: meters.rightPeak)
        }
        .frame(width: 64, height: 12)
        .help(L("Sound levels while playing: green is fine, yellow is loud, red is too loud"))
        .accessibilityElement()
        .accessibilityLabel(L("Audio meters"))
        .accessibilityValue(L("Left \(Int(meters.left * 60 - 60)) dB, right \(Int(meters.right * 60 - 60)) dB"))
    }

    private func bar(_ level: Double, peak: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(VideoEditorTheme.well)
                LinearGradient(stops: [
                    .init(color: .green, location: 0), .init(color: .green, location: 0.8),
                    .init(color: .yellow, location: 0.8), .init(color: .yellow, location: 0.95),
                    .init(color: .red, location: 0.95), .init(color: .red, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                    .mask(alignment: .leading) { Rectangle().frame(width: width * level) }
                if peak > 0.01 {
                    Rectangle()
                        .fill(Self.color(VideoAudioMeters.zone(at: peak)))
                        .frame(width: 2)
                        .offset(x: max(width * peak - 2, 0))
                }
            }
            .clipShape(Capsule())
        }
    }

    static func color(_ zone: VideoAudioMeters.Zone) -> Color {
        switch zone {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }
}

// MARK: - Match Frame: the source at a frame

struct VideoSourceViewer: View {
    @ObservedObject var model: VideoEditorModel
    let frame: VideoSourceFrame
    @State private var player = AVPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(frame.name).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text(L("Source at \(VideoEditorModel.timecode(frame.time))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([frame.url]) }
                Button(L("Done")) { model.sourceViewer = nil }
                    .keyboardShortcut(.defaultAction)
            }
            Group {
                if frame.kind == .image, let image = NSImage(contentsOf: frame.url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    VideoSourcePlayerView(player: player)
                }
            }
            .frame(minWidth: 480, minHeight: 270)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(16)
        .frame(width: 640)
        .onAppear {
            guard frame.kind == .video else { return }
            player.replaceCurrentItem(with: AVPlayerItem(url: frame.url))
            player.seek(to: CMTime(seconds: frame.time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        .onDisappear { player.pause() }
    }
}

private struct VideoSourcePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFrameSteppingButtons = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

// MARK: - Paste Attributes

struct VideoPasteAttributesSheet: View {
    @ObservedObject var model: VideoEditorModel
    @State private var ticked: Set<VideoClipAttribute> = []

    var body: some View {
        let copied = model.copiedAttributes
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Paste Attributes")).font(.headline)
            Text(L("From the copied clip onto \(model.selectedItems.count) selected. Tick what to paste."))
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(copied?.available ?? []) { attribute in
                    Toggle(isOn: Binding(get: { ticked.contains(attribute) }, set: { on in
                        if on { ticked.insert(attribute) } else { ticked.remove(attribute) }
                    })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(attribute.title)
                            Text(attribute.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            HStack {
                Spacer()
                Button(L("Cancel")) { model.isPasteAttributesPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(L("Paste")) {
                    model.isPasteAttributesPresented = false
                    model.perform(.basics(.pasteAttributes(ticked)))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(ticked.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 380)
        .onAppear { ticked = copied?.set ?? [] }
    }
}

// MARK: - A card over the editor

/// A dialog over the dimmed editor (like Project Settings).
struct VideoModalCard<Content: View>: View {
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            content()
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(VideoEditorTheme.panel))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(VideoEditorTheme.hairline))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        }
    }
}
