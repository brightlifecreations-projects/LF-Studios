import AVFoundation
import Foundation
import WhisperKit

// MARK: - Engine and models

/// Which recognizer makes captions: Apple's (built into macOS, the
/// default) or Whisper (WhisperKit, on this Mac with Core ML).
enum VideoCaptionEngine: String, CaseIterable, Identifiable {
    case apple
    case whisper

    var id: String { rawValue }
    var title: String { self == .apple ? L("Apple") : L("Whisper") }
}

/// The Whisper models LF Studios offers, smallest first.
enum VideoWhisperModel: String, CaseIterable, Identifiable, Codable {
    case tiny
    case base
    case small
    case largeTurbo

    var id: String { rawValue }

    /// The folder's name in Argmax's model repository.
    var variant: String {
        switch self {
        case .tiny: return "openai_whisper-tiny"
        case .base: return "openai_whisper-base"
        case .small: return "openai_whisper-small"
        case .largeTurbo: return "openai_whisper-large-v3-v20240930_turbo_632MB"
        }
    }

    var tokenizerVariant: ModelVariant {
        switch self {
        case .tiny: return .tiny
        case .base: return .base
        case .small: return .small
        case .largeTurbo: return .largev3
        }
    }

    var title: String {
        switch self {
        case .tiny: return L("Tiny")
        case .base: return L("Base")
        case .small: return L("Small")
        case .largeTurbo: return L("Large v3 Turbo")
        }
    }

    var detail: String {
        switch self {
        case .tiny: return L("Fastest, least accurate")
        case .base: return L("Fast")
        case .small: return L("Balanced")
        case .largeTurbo: return L("Most accurate, slowest")
        }
    }

    /// About how much it downloads.
    var approximateBytes: Int64 {
        switch self {
        case .tiny: return 75_000_000
        case .base: return 145_000_000
        case .small: return 480_000_000
        case .largeTurbo: return 630_000_000
        }
    }

    var sizeText: String { ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file) }
}

// MARK: - Downloaded models

/// The Whisper models on this Mac: downloaded only when the user picks
/// one, removed with Delete in Settings. Downloading is the only time
/// Whisper uses the network; transcribing never does.
@MainActor
final class VideoWhisperModels: ObservableObject {
    static let shared = VideoWhisperModels()

    /// Tests point this somewhere of their own.
    nonisolated(unsafe) static var baseOverride: URL?

    nonisolated static var base: URL {
        baseOverride ?? VideoStorageLocation.root
            .appendingPathComponent("LF Studios", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
    }

    struct Download: Equatable {
        var model: VideoWhisperModel
        var fraction: Double
    }

    @Published private(set) var installed: Set<VideoWhisperModel> = []
    @Published private(set) var download: Download?
    @Published var downloadError: String?
    /// Apple or Whisper, for the next transcription.
    @Published var engine: VideoCaptionEngine {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: "captionEngine") }
    }
    /// The Whisper model to transcribe with.
    @Published var selected: VideoWhisperModel {
        didSet { UserDefaults.standard.set(selected.rawValue, forKey: "whisperModel") }
    }

    private var task: Task<Void, Never>?

    private init() {
        engine = UserDefaults.standard.string(forKey: "captionEngine").flatMap(VideoCaptionEngine.init(rawValue:)) ?? .apple
        selected = UserDefaults.standard.string(forKey: "whisperModel").flatMap(VideoWhisperModel.init(rawValue:)) ?? .base
        refresh()
    }

    func refresh() {
        installed = Set(VideoWhisperModel.allCases.filter(Self.isInstalled))
    }

    nonisolated static func folder(for model: VideoWhisperModel) -> URL {
        base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.variant)", isDirectory: true)
    }

    nonisolated static func tokenizerFolder(for model: VideoWhisperModel) -> URL {
        base.appendingPathComponent("models/openai/\(tokenizerRepo(model.tokenizerVariant))", isDirectory: true)
    }

    private nonisolated static func tokenizerRepo(_ variant: ModelVariant) -> String {
        switch variant {
        case .tiny: return "whisper-tiny"
        case .base: return "whisper-base"
        case .small: return "whisper-small"
        default: return "whisper-large-v3"
        }
    }

    private nonisolated static func marker(for model: VideoWhisperModel) -> URL {
        folder(for: model).appendingPathComponent(".lfstudios-complete")
    }

    /// Downloaded in full, the tokenizer too.
    nonisolated static func isInstalled(_ model: VideoWhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: marker(for: model).path) && hasTokenizer(model)
    }

    nonisolated static func hasTokenizer(_ model: VideoWhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: tokenizerFolder(for: model).appendingPathComponent("tokenizer.json").path)
            || FileManager.default.fileExists(atPath: folder(for: model).appendingPathComponent("tokenizer.json").path)
    }

    /// Space a model takes on disk.
    nonisolated static func bytesOnDisk(_ model: VideoWhisperModel) -> Int64 {
        [folder(for: model), tokenizerFolder(for: model)].reduce(0) { total, folder in
            guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return total }
            var sum: Int64 = 0
            for case let file as URL in files {
                sum += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
            }
            return total + sum
        }
    }

    // MARK: Fit for this Mac

    /// Models WhisperKit's own table says run well on this Mac (no network:
    /// it's built in).
    nonisolated static func supportedVariants() -> [String] {
        WhisperKit.recommendedModels().supported
    }

    /// nil: fine on this Mac. Otherwise why not, and a smaller model that is.
    nonisolated static func unsuitability(of model: VideoWhisperModel, supported: [String] = supportedVariants()) -> (message: String, suggestion: VideoWhisperModel?)? {
        func fits(_ model: VideoWhisperModel) -> Bool { supported.contains(model.variant) }
        guard !fits(model) else { return nil }
        let smaller = VideoWhisperModel.allCases.filter { $0.approximateBytes < model.approximateBytes && fits($0) }.last
        if let smaller {
            return (L("\(model.title) is too much for this Mac and would be very slow or fail. Try \(smaller.title) instead."), smaller)
        }
        return (L("This Mac is too old or slow for Whisper. Use Apple's captions instead."), nil)
    }

    // MARK: Download, cancel, delete

    func startDownload(_ model: VideoWhisperModel) {
        guard download == nil else { return }
        downloadError = nil
        download = Download(model: model, fraction: 0)
        task = Task { [weak self] in
            do {
                try await Self.fetch(model) { fraction in
                    Task { @MainActor in
                        guard let self, self.download?.model == model else { return }
                        self.download?.fraction = fraction
                    }
                }
                guard let self else { return }
                self.download = nil
                self.task = nil
                self.refresh()
                self.selected = model
            } catch {
                guard let self else { return }
                self.download = nil
                self.task = nil
                // A cancelled or failed download leaves nothing half done.
                Self.remove(model)
                self.refresh()
                if !(error is CancellationError), !Task.isCancelled {
                    self.downloadError = L("\(model.title) couldn't be downloaded: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelDownload() {
        task?.cancel()
    }

    func delete(_ model: VideoWhisperModel) {
        Self.remove(model)
        refresh()
    }

    nonisolated static func remove(_ model: VideoWhisperModel) {
        try? FileManager.default.removeItem(at: folder(for: model))
        // The large model's tokenizer is its own; the others' too.
        try? FileManager.default.removeItem(at: tokenizerFolder(for: model))
        VideoWhisperTranscriber.forget(model)
    }

    /// The model, then its tokenizer, from Hugging Face, into `base`.
    nonisolated static func fetch(_ model: VideoWhisperModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        _ = try await WhisperKit.download(variant: model.variant, downloadBase: base) { value in
            progress(min(value.fractionCompleted, 1) * 0.97)
        }
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: folder(for: model).path) else { throw CocoaError(.fileNoSuchFile) }
        // Fetched now, so loading the model later never goes online.
        if !hasTokenizer(model) {
            _ = try await ModelUtilities.loadTokenizer(for: model.tokenizerVariant, tokenizerFolder: base)
        }
        try Task.checkCancellation()
        guard hasTokenizer(model) else { throw CocoaError(.fileNoSuchFile) }
        try Data().write(to: marker(for: model))
        progress(1)
    }
}

// MARK: - Transcribing

/// Words from a recording's sound with a downloaded Whisper model, all on
/// this Mac (Core ML). Times come back in SOURCE seconds, like Apple's.
enum VideoWhisperTranscriber {
    enum Failure: LocalizedError {
        case notDownloaded(VideoWhisperModel)

        var errorDescription: String? {
            switch self {
            case .notDownloaded(let model): return L("Download the \(model.title) model first, in the Captions tab or Settings → General.")
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var loaded: (model: VideoWhisperModel, kit: WhisperKit)?

    static func forget(_ model: VideoWhisperModel) {
        lock.withLock { if loaded?.model == model { loaded = nil } }
    }

    private static func cachedKit(_ model: VideoWhisperModel) -> WhisperKit? {
        lock.withLock { loaded?.model == model ? loaded?.kit : nil }
    }

    private static func keep(_ kit: WhisperKit, for model: VideoWhisperModel) {
        lock.withLock { loaded = (model, kit) }
    }

    private static func kit(for model: VideoWhisperModel) async throws -> WhisperKit {
        if let kit = cachedKit(model) { return kit }
        // Nothing missing, so WhisperKit never fetches anything itself.
        guard VideoWhisperModels.isInstalled(model) else { throw Failure.notDownloaded(model) }
        let config = WhisperKitConfig(
            downloadBase: VideoWhisperModels.base,
            modelFolder: VideoWhisperModels.folder(for: model).path,
            tokenizerFolder: VideoWhisperModels.base,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: false
        )
        let kit = try await WhisperKit(config)
        keep(kit, for: model)
        return kit
    }

    /// Whisper's code for a caption language ("en-US" → "en"; nil: it
    /// listens for the language itself).
    static func languageCode(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        let code = Locale(identifier: identifier).language.languageCode?.identifier ?? String(identifier.prefix(2))
        return Constants.languages.values.contains(code) ? code : nil
    }

    static func transcribe(
        url: URL,
        trackIndex: Int?,
        timeOffset: Double,
        languageIdentifier: String?,
        model: VideoWhisperModel,
        progress: @escaping @Sendable (VideoCaptionTranscriber.Stage) -> Void
    ) async throws -> VideoCaptionTranscriber.Result {
        progress(.preparing)
        let samples = try await audio(url: url, trackIndex: trackIndex)
        guard samples.count > 1600 else { throw VideoCaptionTranscriber.Failure.noAudio }
        let duration = Double(samples.count) / 16_000
        let kit = try await kit(for: model)
        try Task.checkCancellation()
        progress(.transcribing(0))
        let language = languageCode(languageIdentifier)
        let options = DecodingOptions(
            language: language,
            temperature: 0,
            usePrefillPrompt: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )
        let results = try await kit.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: { _ in Task.isCancelled ? false : nil },
            segmentCallback: { segments in
                guard let end = segments.map(\.end).max() else { return }
                progress(.transcribing(min(Double(end) / duration, 0.99)))
            }
        )
        try Task.checkCancellation()
        let words = Self.words(from: timedWords(results.flatMap(\.segments)), offset: timeOffset)
        guard !words.isEmpty else { throw VideoCaptionTranscriber.Failure.nothingHeard }
        progress(.transcribing(1))
        let detected = results.first?.language ?? language ?? "en"
        return VideoCaptionTranscriber.Result(words: words, language: languageIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? detected)
    }

    /// A word as Whisper timed it (file seconds).
    struct TimedWord: Equatable {
        var text: String
        var start: Double
        var end: Double
    }

    static func timedWords(_ segments: [TranscriptionSegment]) -> [TimedWord] {
        segments.flatMap { segment in
            (segment.words ?? []).map { TimedWord(text: $0.word, start: Double($0.start), end: Double($0.end)) }
        }
    }

    /// Whisper's timed words as caption words: special tokens dropped,
    /// punctuation kept on its word.
    static func words(from timed: [TimedWord], offset: Double) -> [VideoCaptionWord] {
        var words: [VideoCaptionWord] = []
        for timing in timed {
            let text = timing.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !(text.hasPrefix("<|") && text.hasSuffix("|>")), !(text.hasPrefix("[") && text.hasSuffix("]")) else { continue }
            let start = timing.start + offset
            let end = max(timing.end + offset, start + 0.02)
            if text.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }), !words.isEmpty {
                words[words.count - 1].text += text
                words[words.count - 1].end = max(words[words.count - 1].end, end)
            } else {
                words.append(VideoCaptionWord(text: text, start: start, end: end))
            }
        }
        return words.sorted { $0.start < $1.start }
    }

    /// 16 kHz mono, as Whisper hears.
    static func audio(url: URL, trackIndex: Int?) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        var tracks = try await asset.loadTracks(withMediaType: .audio)
        if let trackIndex, tracks.indices.contains(trackIndex) { tracks = [tracks[trackIndex]] }
        guard !tracks.isEmpty else { throw VideoCaptionTranscriber.Failure.noAudio }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 16_000,
        ])
        guard reader.canAdd(output) else { throw VideoCaptionTranscriber.Failure.noAudio }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? VideoCaptionTranscriber.Failure.noAudio }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            try Task.checkCancellation()
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { samples.append(contentsOf: UnsafeBufferPointer(start: $0, count: length / 4)) }
        }
        if reader.status == .failed { throw reader.error ?? VideoCaptionTranscriber.Failure.noAudio }
        return samples
    }
}
