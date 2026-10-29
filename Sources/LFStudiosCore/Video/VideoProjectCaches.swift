import AVFoundation
import Foundation

/// A cleaned-up voice the edit plays (Enhance voice, Podcast mode). Apple's
/// voice isolation never comes out the same twice, so the file itself
/// travels with a saved project or handoff (03 Audio) instead of being
/// made again on another Mac.
struct VideoCarriedVoice: Codable, Equatable {
    static let primary = "primary"
    static let audioPrefix = "audio:"

    /// Whose voice: "primary" (the project's own recording), an added
    /// recording's id, or "audio:" and an added sound's id.
    var owner: String
    var trackIndex: Int
    /// The recipe it was made with (VideoVoiceRecipe.signature).
    var recipe: String
    var path: String
}

/// The edit's work kept in this Mac's caches (the cleaned-up voices, the
/// face found in the camera video), named in the project before it's
/// saved or handed off, and put back into the caches when it's opened, so
/// it plays and exports the same on any Mac.
enum VideoProjectCaches {
    /// `contents` naming the cached files it uses, ready to be copied
    /// along with its media.
    static func carrying(_ contents: VideoProjectContents, primaryKinds: [VideoAudioKind]) -> VideoProjectContents {
        var carried = contents
        carried.project = carrying(contents.project, recordedCamera: contents.recording?.webcam, primaryKinds: primaryKinds)
        return carried
    }

    static func carrying(_ project: VideoDemoProject, recordedCamera: VideoWebcamRecording?, primaryKinds: [VideoAudioKind]) -> VideoDemoProject {
        var project = project
        let fm = FileManager.default
        if let recipe = project.audio.voiceRecipe {
            var voices: [VideoCarriedVoice] = []
            for target in project.voiceTargets(primaryKinds: primaryKinds) {
                if target.isReady {
                    voices.append(VideoCarriedVoice(owner: target.owner, trackIndex: target.trackIndex, recipe: recipe.signature, path: target.destination.path))
                } else if let earlier = project.carriedVoices.first(where: { $0.owner == target.owner && $0.trackIndex == target.trackIndex && $0.recipe == recipe.signature }),
                          fm.fileExists(atPath: earlier.path) {
                    // Opened from elsewhere and not put back yet: still carried.
                    voices.append(earlier)
                }
            }
            project.carriedVoices = voices
        } else {
            project.carriedVoices = []
        }
        if var tracking = project.faceTracking {
            if let url = cameraURL(project, recordedCamera: recordedCamera), VideoFaceStore.load(for: url) != nil {
                tracking.analysisPath = VideoFaceStore.fileURL(for: url).path
            } else if let path = tracking.analysisPath, !fm.fileExists(atPath: path) {
                tracking.analysisPath = nil
            }
            project.faceTracking = tracking
        }
        return project
    }

    /// An opened project's carried files back into this Mac's caches (only
    /// where they aren't there already).
    static func restore(_ contents: VideoProjectContents) {
        let project = contents.project
        let fm = FileManager.default
        if let recipe = project.audio.voiceRecipe {
            for voice in project.carriedVoices where voice.recipe == recipe.signature && fm.fileExists(atPath: voice.path) {
                guard let recording = recordingURL(of: voice, in: project) else { continue }
                let destination = VideoVoiceEnhancer.cacheURL(for: recording, trackIndex: voice.trackIndex, recipe: recipe)
                guard !fm.fileExists(atPath: destination.path) else { continue }
                try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.copyItem(at: URL(fileURLWithPath: voice.path), to: destination)
            }
        }
        if let path = project.faceTracking?.analysisPath,
           let camera = cameraURL(project, recordedCamera: contents.recording?.webcam),
           VideoFaceStore.load(for: camera) == nil,
           let analysis = VideoFaceStore.load(file: URL(fileURLWithPath: path)) {
            VideoFaceStore.save(analysis, for: camera)
        }
    }

    /// The camera video face tracking looks at: added footage, else the
    /// recorded one.
    static func cameraURL(_ project: VideoDemoProject, recordedCamera: VideoWebcamRecording?) -> URL? {
        if let imported = project.importedCamera { return imported.resolved() }
        guard let camera = project.activeCamera(recorded: recordedCamera) else { return nil }
        return FileManager.default.fileExists(atPath: camera.path) ? camera.url : nil
    }

    private static func recordingURL(of voice: VideoCarriedVoice, in project: VideoDemoProject) -> URL? {
        if voice.owner == VideoCarriedVoice.primary { return project.sourceURL }
        if voice.owner.hasPrefix(VideoCarriedVoice.audioPrefix) {
            let id = String(voice.owner.dropFirst(VideoCarriedVoice.audioPrefix.count))
            return project.audioTracks.first { $0.id.uuidString == id }?.url
        }
        return project.sources.first { $0.id.uuidString == voice.owner }.flatMap { VideoSourceLocator.resolve($0) }
    }

    /// The project's own recording's sound tracks: which is the voice.
    static func primaryKinds(project: VideoDemoProject, recording: VideoDemoRecordingMetadata?) async -> [VideoAudioKind] {
        let asset = AVURLAsset(url: project.sourceURL)
        var counts: [Int] = []
        for track in (try? await asset.loadTracks(withMediaType: .audio)) ?? [] {
            let formats = (try? await track.load(.formatDescriptions)) ?? []
            counts.append(Int(formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 2))
        }
        return counts.isEmpty ? [] : VideoAudioKind.resolve(recorded: recording?.audioTracks, channelCounts: counts)
    }
}
