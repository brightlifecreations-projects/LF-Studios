import AppKit
import AVFoundation
import SwiftUI

/// The editor's look (style) and speeding up idle parts.
extension VideoEditorModel {
    // MARK: Style

    func setStyle(coalesce key: String? = nil, _ change: (inout VideoDemoProject) -> Void) {
        mutate(coalesce: key, change)
    }

    /// This look as My Style (made "My Look" when there's no My Style yet).
    /// Nothing is applied: new recordings still open plain.
    func saveStyleAsDefault() {
        VideoStylePreset.saveAsDefault(project.style)
        VideoStylePresetStore.shared.reloadIfNeeded()
        showNotice(L("Saved as My Style — Apply my style (⇧⌘Y) puts it on a video"), symbol: "checkmark.circle.fill")
    }

    /// Back to the built-in LF Studios look.
    func resetStyle() {
        mutate(label: "Reset Look") { project in
            project.apply(style: .factory)
        }
        showNotice(L("Back to the LF Studios look"), symbol: "arrow.counterclockwise")
    }

    var styleMatchesDefault: Bool {
        guard let saved = VideoStylePreset.savedDefault else { return false }
        return saved == project.style
    }

    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setStyle { $0.background = .image(url.path) }
    }

    func shuffleBackground() {
        let options = VideoBackgroundCatalog.wallpapers.map { VideoBackground.wallpaper($0.id) }
            + VideoBackgroundCatalog.pickerGradients.map { VideoBackground.gradient($0.id) }
        let choices = options.filter { $0 != project.background }
        guard let pick = choices.randomElement() else { return }
        setStyle { $0.background = pick }
    }

    // MARK: Idle speed-up

    /// Stretches of the recording where nothing happens: the pointer is
    /// still, nobody clicks or presses a shortcut, the screen isn't
    /// changing (typing, scrolling), and it's quiet. Source seconds.
    func idleRanges(minimum: Double = 2.5) -> [ClosedRange<Double>] {
        guard sourceDuration > 0 else { return [] }
        var activity = VideoTranscript.activityTimes(
            cursor: project.cursorSamples,
            clicks: project.clickEvents,
            keystrokes: project.keystrokes,
            screen: screenActivityOnAxis,
            pointerStep: 0.002
        )
        if let waveform, !waveform.peaks.isEmpty {
            let loud: Float = 0.06
            for (index, peak) in waveform.peaks.enumerated() where peak > loud && index % 5 == 0 {
                activity.append(Double(index) / VideoWaveform.bucketsPerSecond)
            }
        }
        activity.sort()
        var ranges: [ClosedRange<Double>] = []
        var last = 0.0
        let margin = 0.5
        for time in activity + [sourceDuration] {
            if time - last >= minimum + margin * 2 {
                ranges.append((last + margin)...(time - margin))
            }
            last = max(last, time)
        }
        // Added videos without pointer data are never "idle".
        return project.limitedToPointerCoverage(ranges)
    }

    func speedUpIdle(speed: Double = 8) {
        if refuseLocked(.clips) { return }
        // Without the pointer's path (or the screen's changes) there's no
        // telling a quiet screen from a busy one — it would speed up
        // everything.
        guard !project.cursorSamples.isEmpty || seesScreenChanges else {
            showNotice(L("Speed Up Idle works on LF Studios recordings — it watches the pointer"), symbol: "hare")
            return
        }
        let ranges = idleRanges()
        guard !ranges.isEmpty else {
            showNotice(L("No idle moments found — nice and tight"), symbol: "hare")
            return
        }
        var saved = 0.0
        mutate(label: "Speed Up Idle") { project in
            for range in ranges {
                // Only speed up material still on the timeline at 1×.
                _ = project.splitClip(atSourceTime: range.lowerBound, totalDuration: sourceDuration)
                _ = project.splitClip(atSourceTime: range.upperBound, totalDuration: sourceDuration)
                let clips = project.normalizedTimelineClips(totalDuration: sourceDuration)
                for clip in clips where clip.sourceStart >= range.lowerBound - 0.001 && clip.sourceEnd <= range.upperBound + 0.001 && abs(clip.normalizedSpeed - 1) < 0.01 {
                    _ = project.updateClip(id: clip.id, totalDuration: sourceDuration) { $0.speed = speed; $0.muted = true }
                    saved += clip.sourceDuration * (1 - 1 / speed)
                }
            }
        }
        let savedTime = Self.format(saved)
        if seesScreenChanges {
            showNotice(L("Sped up \(ranges.count) idle moments — saved \(savedTime)"), symbol: "hare.fill")
        } else {
            // Recordings from before the recorder watched the screen can't
            // tell typing from waiting.
            showNotice(L("Sped up \(ranges.count) idle moments — saved \(savedTime) · check any typing"), symbol: "hare.fill", duration: 4)
        }
    }
}
