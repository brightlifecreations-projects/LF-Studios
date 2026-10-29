import CoreGraphics
import Foundation

/// "Adapt to this ratio": the parts of a project each aspect ratio keeps
/// for itself once adapted, so 16:9, 9:16 and 1:1 versions live side by
/// side. Cuts, caption text, styles and zooms themselves stay shared.
struct VideoRatioVersion: Codable, Equatable {
    struct ZoomFraming: Codable, Equatable {
        var offsetX: Double
        var offsetY: Double
        var cameraCorner: VideoWebcamSettings.Anchor?
    }

    /// Keyed by zoom id (uuidString); zooms added later keep their own.
    var zooms: [String: ZoomFraming]
    var webcamAnchor: VideoWebcamSettings.Anchor
    var webcamSize: Double
    /// Placed by hand (nil: at the anchor; versions saved before 1.10.0).
    var webcamPlacement: VideoWebcamSettings.Placement?
    var cameraLayouts: [VideoCameraLayoutRegion]
    var captionPosition: VideoTextPosition
    var captionPlacement: VideoTextPlacement?
    /// Captions placed one by one (uuidString → spot).
    var captionPlacements: [String: VideoTextPlacement]
    var reframe: Bool
    var reframeFollowsZooms: Bool
}

/// What Adapt changed, for its notice.
struct VideoRatioAdaptReport: Equatable {
    var zooms = 0
    var movedCamera = false
    var captions = 0
}

extension VideoDemoProject {
    /// The current values of everything a ratio keeps for itself.
    func ratioSnapshot() -> VideoRatioVersion {
        VideoRatioVersion(
            zooms: Dictionary(uniqueKeysWithValues: zoomRegions.map { ($0.id.uuidString, VideoRatioVersion.ZoomFraming(offsetX: $0.offsetX, offsetY: $0.offsetY, cameraCorner: $0.cameraCorner)) }),
            webcamAnchor: webcam.anchor,
            webcamSize: webcam.size,
            webcamPlacement: webcam.placement,
            cameraLayouts: cameraLayouts,
            captionPosition: captionStyle.position,
            captionPlacement: captionStyle.placement,
            captionPlacements: Dictionary(uniqueKeysWithValues: captions.compactMap { line in line.placement.map { (line.id.uuidString, $0) } }),
            reframe: reframe,
            reframeFollowsZooms: reframeFollowsZooms
        )
    }

    mutating func restore(_ version: VideoRatioVersion) {
        for index in zoomRegions.indices {
            guard let framing = version.zooms[zoomRegions[index].id.uuidString] else { continue }
            zoomRegions[index].offsetX = framing.offsetX
            zoomRegions[index].offsetY = framing.offsetY
            zoomRegions[index].cameraCorner = framing.cameraCorner
        }
        webcam.anchor = version.webcamAnchor
        webcam.size = version.webcamSize
        webcam.placement = version.webcamPlacement
        cameraLayouts = version.cameraLayouts
        captionStyle.position = version.captionPosition
        captionStyle.placement = version.captionPlacement
        for index in captions.indices {
            captions[index].placement = version.captionPlacements[captions[index].id.uuidString]
        }
        reframe = version.reframe
        reframeFollowsZooms = version.reframeFollowsZooms
    }

    /// Ratios with a version of their own.
    var adaptedRatios: [AspectPreset] {
        AspectPreset.allCases.filter { ratioVersions[$0.rawValue] != nil }
    }

    var isAdaptedRatio: Bool { ratioVersions[aspectPreset.rawValue] != nil }

    /// Every version to export: the ratio the project started from, then
    /// each adapted one.
    var ratiosToExport: [AspectPreset] {
        var ratios = adaptedRatios
        if let base = ratioBase, !ratios.contains(base) { ratios.insert(base, at: 0) }
        return ratios
    }

    /// Switches ratio. Once any ratio is adapted, the one being left keeps
    /// its values (an adapted ratio in its own version, any other in the
    /// shared one) and the new one gets its own back.
    mutating func switchRatio(to preset: AspectPreset) {
        guard preset != aspectPreset else { return }
        guard let shared = ratioShared else {
            previousRatio = aspectPreset
            apply(aspectPreset: preset)
            return
        }
        let snapshot = ratioSnapshot()
        if isAdaptedRatio {
            ratioVersions[aspectPreset.rawValue] = snapshot
        } else {
            ratioShared = snapshot
        }
        previousRatio = aspectPreset
        apply(aspectPreset: preset)
        restore(ratioVersions[preset.rawValue] ?? ratioShared ?? shared)
    }

    /// The project as it looks in another ratio (for Export all ratios).
    func version(for preset: AspectPreset) -> VideoDemoProject {
        var copy = self
        copy.switchRatio(to: preset)
        return copy
    }

    /// Fits zooms, the camera bubble and captions to the current ratio, and
    /// gives the ratio its own version from now on.
    @discardableResult
    mutating func adaptToCurrentRatio(hasCursor: Bool) -> VideoRatioAdaptReport {
        var report = VideoRatioAdaptReport()
        if ratioShared == nil {
            // The values every other ratio shares are the ones from before.
            ratioShared = ratioSnapshot()
            ratioBase = ratioBase ?? previousRatio ?? aspectPreset
        }
        let canvas = canvasSize()
        let aspect = Double(canvas.width / max(canvas.height, 1))
        let vertical = aspect < 0.8
        let narrow = aspect < 1.2

        // Zooms: the subject in the middle of a narrow frame (framing moved
        // aside for a wide frame would push it out), loupes kept inside.
        if canReframe, hasCursor { reframe = true }
        reframeFollowsZooms = reframeActive
        for index in zoomRegions.indices {
            var zoom = zoomRegions[index]
            let before = zoom
            if zoom.isLoupe {
                let limit = narrow ? 0.18 : 0.3
                zoom.offsetX = min(max(zoom.offsetX, -limit), limit)
                zoom.offsetY = min(max(zoom.offsetY, -limit), limit)
            } else {
                zoom.offsetX = narrow ? 0 : min(max(zoom.offsetX, -0.25), 0.25)
                zoom.offsetY = min(max(zoom.offsetY, -0.2), 0.2)
            }
            if narrow { zoom.cameraCorner = nil }
            if zoom != before { report.zooms += 1 }
            zoomRegions[index] = zoom
        }

        // The camera bubble: on a vertical frame the bottom belongs to the
        // captions and the app's buttons, so it goes up top.
        let anchor = webcam.anchor
        let size = webcam.size
        let placement = webcam.placement
        if let placed = placement {
            // Placed by hand for another shape: the nearest spot, as big.
            let rect = VideoFrameRenderer.webcamRect(webcam, outputSize: canvas)
            let short = max(min(canvas.width, canvas.height), 1)
            webcam.placement = nil
            webcam.anchor = VideoWebcamSettings.Anchor.nearest(to: CGPoint(x: placed.x, y: placed.y))
            webcam.size = min(max(Double(rect.height / short), VideoWebcamSettings.sizeRange.lowerBound), VideoWebcamSettings.sizeRange.upperBound)
        }
        if vertical {
            if anchor == .bottomLeft { webcam.anchor = .topLeft }
            if anchor == .bottomRight { webcam.anchor = .topRight }
            webcam.size = min(max(webcam.size, 0.24), 0.34)
        } else if narrow {
            webcam.size = min(webcam.size, 0.3)
        }
        report.movedCamera = webcam.visible && (placement != nil || anchor != webcam.anchor || abs(size - webcam.size) > 0.0001)

        // Captions inside the safe area (on a vertical frame, clear of the
        // parts a phone app covers: VideoPhoneOverlay.swift).
        let band: ClosedRange<Double> = vertical ? 0.16...0.74 : 0.1...0.9
        let across: ClosedRange<Double> = vertical ? 0.4...0.6 : 0.15...0.85
        func safe(_ placement: VideoTextPlacement) -> VideoTextPlacement {
            VideoTextPlacement(x: min(max(placement.x, across.lowerBound), across.upperBound), y: min(max(placement.y, band.lowerBound), band.upperBound))
        }
        // (Only said when there are captions to see it.)
        let hasCaptions = !captions.isEmpty
        if let placement = captionStyle.placement {
            let fitted = safe(placement)
            if fitted != placement { captionStyle.placement = fitted; if hasCaptions { report.captions += 1 } }
        } else if vertical {
            captionStyle.placement = VideoTextPlacement(x: 0.5, y: captionStyle.position == .top ? band.lowerBound + 0.04 : band.upperBound)
            if hasCaptions { report.captions += 1 }
        }
        for index in captions.indices {
            guard let placement = captions[index].placement else { continue }
            let fitted = safe(placement)
            if fitted != placement { captions[index].placement = fitted; report.captions += 1 }
        }
        ratioVersions[aspectPreset.rawValue] = ratioSnapshot()
        return report
    }

    /// While a zoom plays in an adapted narrow ratio, what it zooms on, for
    /// the reframing window (recording-normalized, at a source time).
    func zoomSubject(cursor: ((Double) -> CGPoint?)?, typing: ((Double) -> CGPoint?)?) -> ((Double) -> CGPoint?)? {
        guard reframeFollowsZooms, !zoomRegions.isEmpty else { return nil }
        let regions = zoomRegions.filter { !$0.isLoupe }.sorted { $0.start < $1.start }
        return { source in
            guard let zoom = regions.last(where: { $0.start <= source && source <= $0.end }) else { return nil }
            if zoom.followsTyping, let point = typing?(source) { return point }
            if zoom.followsCursor, let point = cursor?(source) { return point }
            return CGPoint(x: zoom.focusX, y: zoom.focusY)
        }
    }
}
