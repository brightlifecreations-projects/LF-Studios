import CoreGraphics
import Foundation

/// Split screen's geometry (1.10.0; both directions on any shape since
/// 1.11.0), the same everywhere: the renderer,
/// the frame bar's screen part before recording, the divider in the
/// editor, and Creative Handoff's timelines.
enum VideoSplitLayout {
    /// Side by side on a landscape video; one above the other on a square
    /// or vertical one.
    static func isSideBySide(_ size: CGSize) -> Bool {
        size.width > size.height * 1.0001
    }

    /// The split's direction on a video `size` big: chosen, or from its shape.
    static func isSideBySide(_ split: VideoWebcamSettings.Split, in size: CGSize) -> Bool {
        guard let direction = split.direction else { return isSideBySide(size) }
        return direction == .sideBySide
    }

    static func direction(_ split: VideoWebcamSettings.Split, in size: CGSize) -> VideoWebcamSettings.Split.Direction {
        isSideBySide(split, in: size) ? .sideBySide : .stacked
    }

    /// The screen's and the camera's parts of a video `size` big (bottom-left
    /// origin, like the renderer; whole units), and the gap between them.
    static func parts(_ split: VideoWebcamSettings.Split, in size: CGSize) -> (screen: CGRect, camera: CGRect) {
        let sideBySide = isSideBySide(split, in: size)
        let gap = (min(size.width, size.height) * CGFloat(split.keptGap)).rounded()
        let length = sideBySide ? size.width : size.height
        let available = max(length - gap, 2)
        let cameraLength = (available * CGFloat(split.keptShare)).rounded()
        let screenLength = available - cameraLength
        let cameraFirst = split.cameraSide == .first
        if sideBySide {
            // First is the left.
            let camera = CGRect(x: cameraFirst ? 0 : screenLength + gap, y: 0, width: cameraLength, height: size.height)
            let screen = CGRect(x: cameraFirst ? cameraLength + gap : 0, y: 0, width: screenLength, height: size.height)
            return (screen, camera)
        }
        // First is the top: the high end, bottom-left origin.
        let camera = CGRect(x: 0, y: cameraFirst ? size.height - cameraLength : 0, width: size.width, height: cameraLength)
        let screen = CGRect(x: 0, y: cameraFirst ? 0 : cameraLength + gap, width: size.width, height: screenLength)
        return (screen, camera)
    }

    /// The screen's part of a video of `pixels`, in whole even pixels (what
    /// the frame bar records), bottom-left origin within the video.
    static func screenPixels(_ split: VideoWebcamSettings.Split, video pixels: CGSize) -> CGRect {
        var screen = parts(split, in: pixels).screen
        func even(_ value: CGFloat) -> CGFloat { max(2, (value / 2).rounded(.down) * 2) }
        let width = even(screen.width), height = even(screen.height)
        // Trimmed on the side away from the camera's part.
        if isSideBySide(split, in: pixels) {
            if split.cameraSide == .first { screen.origin.x = screen.maxX - width }
        } else if split.cameraSide == .second {
            screen.origin.y = screen.maxY - height
        }
        screen.size = CGSize(width: width, height: height)
        return screen
    }

    /// The screen part's shape as a ratio label, like "8:9".
    static func ratioText(_ part: CGSize) -> String {
        RecordingFrameRatio(Int(part.width.rounded()), Int(part.height.rounded())).text
    }

    // MARK: The divider

    /// Where the divider is along the video, 0…1 (left to right, or top to
    /// bottom).
    static func dividerPosition(_ split: VideoWebcamSettings.Split, in size: CGSize) -> CGFloat {
        let (screen, camera) = parts(split, in: size)
        if isSideBySide(split, in: size) {
            let left = split.cameraSide == .first ? camera : screen
            let right = split.cameraSide == .first ? screen : camera
            return (left.maxX + right.minX) / 2 / max(size.width, 1)
        }
        // Top to bottom, so measured from the top.
        let top = split.cameraSide == .first ? camera : screen
        let bottom = split.cameraSide == .first ? screen : camera
        return (size.height - (top.minY + bottom.maxY) / 2) / max(size.height, 1)
    }

    /// The camera's share for the divider dragged to `position` (0…1 along
    /// the video), kept between 30 and 70%.
    static func share(forDivider position: CGFloat, _ split: VideoWebcamSettings.Split, in size: CGSize) -> Double {
        let sideBySide = isSideBySide(split, in: size)
        let length = sideBySide ? size.width : size.height
        let gap = (min(size.width, size.height) * CGFloat(split.keptGap)).rounded()
        let available = max(length - gap, 2)
        let at = position * length
        let cameraLength = split.cameraSide == .first ? at - gap / 2 : length - at - gap / 2
        let share = Double(cameraLength / available)
        return min(max(share, VideoWebcamSettings.Split.shareRange.lowerBound), VideoWebcamSettings.Split.shareRange.upperBound)
    }
}
