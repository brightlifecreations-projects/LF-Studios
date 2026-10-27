import Foundation

// Manual only: a new recording opens plain — the recording as it is, the
// real pointer, no background or effects — and every creative effect is
// turned on by its own button or switch. The settings types keep their old
// built-in values on purpose: drafts and project files saved before a field
// existed fall back on them, so older work opens looking exactly as it did.

extension VideoCursorSettings {
    /// The pointer as recorded: real size, no smoothing, no click effect,
    /// never hidden or blurred.
    static var plain: VideoCursorSettings {
        var cursor = VideoCursorSettings()
        cursor.size = 1
        cursor.smoothing = .off
        cursor.clickEffect = .none
        cursor.hideWhenIdle = false
        cursor.motionBlur = false
        cursor.tidyEnding = false
        return cursor
    }
}

extension VideoWebcamSettings {
    /// The recorded camera in a plain bubble: not mirrored, never shrinking.
    static var plain: VideoWebcamSettings {
        var webcam = VideoWebcamSettings()
        webcam.mirror = false
        webcam.shrinkWhenZoomed = false
        return webcam
    }
}

extension VideoStylePreset {
    /// A plain video: the recording's own frame, no background, padding,
    /// corners, shadow, or edge; no zoom motion blur; captions without word
    /// highlighting; keys hidden until they're switched on.
    static var plain: VideoStylePreset {
        var captions = VideoCaptionStyle()
        captions.highlightWords = false
        var keys = VideoKeystrokeStyle()
        keys.visible = false
        return VideoStylePreset(
            aspectPreset: .source,
            background: VideoBackgroundCatalog.defaultBackground,
            backgroundBlur: 0,
            padding: 0,
            cornerRadius: 0,
            shadow: 0,
            outline: false,
            zoomSpeed: .smooth,
            defaultZoomScale: 2,
            motionBlur: 0,
            cursor: .plain,
            webcam: .plain,
            captionStyle: captions,
            keystrokeStyle: keys,
            autoZoom: false
        )
    }
}

extension VideoDemoProject {
    /// Auto-zoom's own settings when it's switched on.
    static let autoZoomMotionBlur = 0.5

    /// A new recording, opened for the first time: plain, nothing applied.
    static func fresh(sourceURL: URL, duration: Double = 0, sourceSize: CGSize = .zero) -> VideoDemoProject {
        var project = make(sourceURL: sourceURL, duration: duration, sourceSize: sourceSize)
        project.apply(style: .plain)
        project.autoZoom = false
        // The export doesn't even out the loudness unless asked to.
        project.audio.normalizeLoudness = false
        return project
    }

    /// Auto-zoom on clicks. On: zooms planned from the clicks (hand-made
    /// zooms stay, generated ones that would overlap them are left out) and
    /// its options switched on. Off: the generated zooms go and its options
    /// switch off. Returns how many zooms were generated.
    @discardableResult
    mutating func setAutoZoom(_ on: Bool, totalDuration: Double) -> Int {
        autoZoom = on
        let manual = zoomRegions.filter { !$0.isAuto }
        guard on else {
            zoomRegions = manual
            motionBlur = 0
            webcam.shrinkWhenZoomed = false
            return 0
        }
        motionBlur = Self.autoZoomMotionBlur
        webcam.shrinkWhenZoomed = true
        let generated = VideoAutoZoomPlanner.regions(
            clicks: clicksInsideCrop,
            cursorSamples: cursorSamples,
            segments: timelineSegments(totalDuration: totalDuration),
            scale: defaultZoomScale,
            speed: zoomSpeed
        )
        let kept = generated.filter { candidate in
            !manual.contains { $0.start < candidate.end && $0.end > candidate.start }
        }
        zoomRegions = (manual + kept).sorted { $0.start < $1.start }
        return kept.count
    }

    /// Full frame ↔ background. Showing the background of a plain video
    /// brings the whole framed look: padding, corners, shadow, the edge,
    /// and a 16:9 frame when it was the recording's own.
    mutating func toggleBackground() {
        guard usesRawSourceFrame else {
            padding = 0
            return
        }
        let look = VideoStylePreset.factory
        padding = look.padding
        if cornerRadius <= 0.5 { cornerRadius = look.cornerRadius }
        if shadow <= 0.001 { shadow = look.shadow }
        if !outline { outline = look.outline }
        if aspectPreset == .source, sourceWidth >= sourceHeight { aspectPreset = .widescreen }
    }

    /// A preset, its auto-zoom choice included (presets saved before it
    /// existed leave auto-zoom as it is).
    mutating func apply(preset: VideoNamedStylePreset, totalDuration: Double) {
        apply(preset: preset)
        if let autoZoom = preset.style.autoZoom, autoZoom != self.autoZoom {
            setAutoZoom(autoZoom, totalDuration: totalDuration)
        }
    }
}
