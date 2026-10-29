import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import LFStudiosCore

/// 1.11.0: split screen side by side or stacked on every output shape, and
/// the ratio menu's 16:10, 21:9 and Custom… (VideoSplitScreen.swift,
/// VideoDemoProject.swift, VideoRatioVersions.swift).
@Suite("Split direction and ratios")
struct VideoSplitDirectionTests {
    typealias RGB = (r: Double, g: Double, b: Double)
    typealias Split = VideoWebcamSettings.Split
    static let magenta: RGB = (0.9, 0.1, 0.8)
    static let white: RGB = (1, 1, 1)

    /// Every output shape: the presets, and Custom… at 2.39:1.
    static let shapes: [(VideoDemoProject.AspectPreset, Double?)] = [
        (.widescreen, nil), (.vertical, nil), (.square, nil), (.portrait, nil), (.classic, nil), (.mac, nil), (.cinema, nil), (.custom, 2.39),
    ]

    private func project(_ preset: VideoDemoProject.AspectPreset, custom: Double? = nil, split: Split) -> VideoDemoProject {
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/direction.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        project.aspectPreset = preset
        project.customAspect = custom
        project.background = .color(VideoRGBA(1, 1, 1))
        project.webcam = VideoRecordingCameraSetup.LayoutChoice.split.applied(to: project.webcam)
        project.webcam.split = split
        return project
    }

    private struct Frame {
        let bytes: [UInt8]
        let size: CGSize
        func color(_ x: CGFloat, _ y: CGFloat) -> RGB { TestVideos.pixel(bytes, width: Int(size.width), x: Int(x), y: Int(y)) }
    }

    /// Rendered at half the canvas size.
    private func render(_ project: VideoDemoProject, transparent: Bool = false) throws -> Frame {
        let canvas = project.canvasSize()
        let size = CGSize(width: (canvas.width / 2).rounded(), height: (canvas.height / 2).rounded())
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 4, recording: nil, hasWebcam: true)
        var options = VideoFrameRenderer.Options(frameRate: 30)
        options.webcamFrame = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.8)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        options.transparentBackground = transparent
        let image = VideoFrameRenderer().render(source: TestVideos.quadrantImage(size: project.sourceSize), timelineTime: 2, plan: plan, outputSize: size, options: options)
        let cgImage = try #require(CIContext().createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
        return Frame(bytes: TestVideos.rgba(cgImage), size: size)
    }

    private func isCamera(_ c: RGB) -> Bool { TestVideos.close(c, Self.magenta, within: 0.12) }
    private func isScreen(_ c: RGB) -> Bool { TestVideos.quadrantColors.contains { TestVideos.close(c, $0, within: 0.12) } }

    // MARK: Both directions on every shape

    @Test(arguments: [Split.Direction.sideBySide, .stacked])
    func everyShapeSplitsTheChosenWay(direction: Split.Direction) throws {
        for (preset, custom) in Self.shapes {
            for side in Split.Side.allCases {
                let split = Split(cameraSide: side, direction: direction)
                let frame = try render(project(preset, custom: custom, split: split))
                let size = frame.size
                let parts = VideoSplitLayout.parts(split, in: size)
                if direction == .sideBySide {
                    #expect(parts.screen.height == size.height && parts.camera.height == size.height, "\(preset) side by side: full height")
                } else {
                    #expect(parts.screen.width == size.width && parts.camera.width == size.width, "\(preset) stacked: full width")
                }
                // Inside each part, a third of the way in from its corners (top-left origin for pixels).
                func inside(_ rect: CGRect) -> [(CGFloat, CGFloat)] {
                    [(rect.minX + rect.width * 0.2, size.height - rect.maxY + rect.height * 0.2), (rect.maxX - rect.width * 0.2, size.height - rect.minY - rect.height * 0.2)]
                }
                for (x, y) in inside(parts.camera) {
                    #expect(isCamera(frame.color(x, y)), "\(preset) \(direction) \(side): camera at \(x), \(y)")
                }
                for (x, y) in inside(parts.screen) {
                    #expect(isScreen(frame.color(x, y)), "\(preset) \(direction) \(side): screen at \(x), \(y)")
                }
            }
        }
    }

    @Test func notChosenFollowsTheShapeAsIn110() {
        for (preset, custom) in Self.shapes {
            let project = project(preset, custom: custom, split: Split())
            let canvas = project.canvasSize()
            #expect(VideoSplitLayout.isSideBySide(Split(), in: canvas) == (canvas.width > canvas.height * 1.0001), "\(preset)")
        }
    }

    @Test func dividerAndGapWorkBothWays() throws {
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920), CGSize(width: 1080, height: 1080)] {
            for direction in Split.Direction.allCases {
                for share in [0.3, 0.55, 0.7] {
                    let split = Split(cameraSide: .first, cameraShare: share, gap: 0.03, direction: direction)
                    let parts = VideoSplitLayout.parts(split, in: size)
                    let gap = (min(size.width, size.height) * 0.03).rounded()
                    if direction == .sideBySide {
                        #expect(abs(parts.screen.minX - parts.camera.maxX - gap) < 0.001, "the gap, side by side")
                    } else {
                        #expect(abs(parts.camera.minY - parts.screen.maxY - gap) < 0.001, "the gap, stacked (camera on top)")
                    }
                    let position = VideoSplitLayout.dividerPosition(split, in: size)
                    #expect(abs(VideoSplitLayout.share(forDivider: position, split, in: size) - share) < 0.002, "\(size) \(direction) \(share)")
                }
            }
        }
        // The gap's background, stacked on a landscape video.
        let frame = try render(project(.widescreen, split: Split(gap: 0.05, direction: .stacked)))
        let parts = VideoSplitLayout.parts(Split(gap: 0.05, direction: .stacked), in: frame.size)
        let middle = frame.size.height - (parts.screen.minY + parts.camera.maxY) / 2
        #expect(TestVideos.close(frame.color(frame.size.width * 0.3, middle), Self.white, within: 0.1))
    }

    // MARK: Adapt, older projects, handoff

    @Test func adaptKeepsAChosenDirection() {
        var chosen = project(.widescreen, split: Split(direction: .sideBySide))
        chosen.aspectPreset = .vertical
        _ = chosen.adaptToCurrentRatio(hasCursor: false)
        #expect(VideoSplitLayout.isSideBySide(chosen.webcam.effectiveSplit, in: chosen.canvasSize()), "kept side by side on 9:16")

        var automatic = project(.widescreen, split: Split())
        automatic.aspectPreset = .vertical
        _ = automatic.adaptToCurrentRatio(hasCursor: false)
        #expect(!VideoSplitLayout.isSideBySide(automatic.webcam.effectiveSplit, in: automatic.canvasSize()), "not chosen: follows the shape")
    }

    @Test func projectsFrom110HaveNoDirection() throws {
        let json = #"{"cameraSide": "first", "cameraShare": 0.4, "gap": 0}"#
        let split = try JSONDecoder().decode(Split.self, from: Data(json.utf8))
        #expect(split.direction == nil)
        #expect(!(String(data: try JSONEncoder().encode(Split()), encoding: .utf8) ?? "").contains("direction"), "nothing new written")
        var chosen = Split(direction: .stacked)
        chosen = try JSONDecoder().decode(Split.self, from: JSONEncoder().encode(chosen))
        #expect(chosen.direction == .stacked)
    }

    @Test func aStackedHandoffSaysTopAndBottom() throws {
        var project = project(.widescreen, split: Split(direction: .stacked))
        project.aspectPreset = .source
        project.splitVideoAspect = 16.0 / 9
        // Recorded as the stacked screen part: 1920 × 540.
        let split = try #require(VideoHandoffSplit.make(project: project, recordingSize: CGSize(width: 1920, height: 540)))
        #expect(split.video == CGSize(width: 1920, height: 1080))
        #expect(!split.sideBySide)
        #expect(split.screen == CGRect(x: 0, y: 0, width: 1920, height: 540))
        #expect(split.readme.joined().contains("the screen on the top, the camera on the bottom"))
    }

    // MARK: 16:10, 21:9, Custom…

    @Test func theNewRatiosHaveTheirShape() {
        let source = CGSize(width: 1280, height: 720)
        for (preset, ratio) in [(VideoDemoProject.AspectPreset.mac, 16.0 / 10), (.cinema, 21.0 / 9)] {
            let canvas = preset.canvasSize(sourceSize: source)
            #expect(abs(canvas.width / canvas.height - ratio) < 0.005, "\(preset)")
            #expect(canvas.height == 1080)
        }
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/ratio.mp4"), duration: 4, sourceSize: source)
        project.aspectPreset = .custom
        project.customAspect = 2.39
        #expect(abs(project.canvasSize().width / project.canvasSize().height - 2.39) < 0.005)
        #expect(project.aspectTitle == "2.39:1")
        #expect(VideoEditorModel.ratioFileTag(.custom, in: project) == "2.39x1")
        #expect(VideoEditorModel.ratioFileTag(.cinema) == "21x9")
        project.customAspect = 0.5
        #expect(project.aspectTitle == "1:2")
        project.customAspect = nil
        #expect(project.canvasSize() == VideoDemoProject.AspectPreset.source.canvasSize(sourceSize: source), "no shape yet: the recording's")
        project.customAspect = 50
        #expect(project.canvasSize().width / project.canvasSize().height <= 8.01, "kept to 8:1")
    }

    @Test func customTakesWhatTheFrameBarTakes() {
        #expect(VideoEditorModel.customAspect(from: "3:2") == 1.5)
        #expect(abs((VideoEditorModel.customAspect(from: "2.39:1") ?? 0) - 2.39) < 0.0001)
        #expect(VideoEditorModel.customAspect(from: "5 x 4") == 1.25)
        #expect(VideoEditorModel.customAspect(from: "wide") == nil)
        #expect(VideoEditorModel.customAspect(from: "20:1") == nil, "too narrow")
    }

    @Test func theNewRatiosAdaptAndExportLikeTheOthers() {
        var project = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/ratio.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        project.aspectPreset = .widescreen
        project.webcam.placement = nil
        for preset in [VideoDemoProject.AspectPreset.mac, .cinema] {
            project.switchRatio(to: preset)
            _ = project.adaptToCurrentRatio(hasCursor: false)
            #expect(project.isAdaptedRatio, "\(preset) has its own version")
        }
        project.customAspect = 2.39
        project.switchRatio(to: .custom)
        _ = project.adaptToCurrentRatio(hasCursor: false)
        let ratios = project.ratiosToExport
        #expect(ratios.contains(.mac) && ratios.contains(.cinema) && ratios.contains(.custom) && ratios.contains(.widescreen))
        let cinema = project.version(for: .cinema)
        #expect(cinema.aspectPreset == .cinema && abs(cinema.canvasSize().width / cinema.canvasSize().height - 21.0 / 9) < 0.005)
        let custom = project.version(for: .custom)
        #expect(abs(custom.canvasSize().width / custom.canvasSize().height - 2.39) < 0.005)
        // Saved and opened again.
        let back = try? JSONDecoder().decode(VideoDemoProject.self, from: JSONEncoder().encode(project))
        #expect(back?.aspectPreset == .custom && back?.customAspect == 2.39)
    }

    @Test func presetsWithTheirAspectRatioCarryCustomsShape() throws {
        var source = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/ratio.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        source.aspectPreset = .custom
        source.customAspect = 1.85
        let saved = try JSONDecoder().decode(VideoStylePreset.self, from: JSONEncoder().encode(source.style))
        #expect(saved.aspectPreset == .custom && saved.customAspect == 1.85)

        var target = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/other.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        target.aspectPreset = .widescreen
        target.apply(preset: VideoNamedStylePreset(name: "Wide", style: saved, includesAspectRatio: true))
        #expect(target.aspectPreset == .custom && target.customAspect == 1.85)
        var kept = VideoDemoProject.fresh(sourceURL: URL(fileURLWithPath: "/tmp/other.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        kept.aspectPreset = .mac
        kept.apply(preset: VideoNamedStylePreset(name: "Wide", style: saved, includesAspectRatio: false))
        #expect(kept.aspectPreset == .mac && kept.customAspect == nil, "without its ratio, the project's stays")
        // A preset saved before 1.11.0 still reads.
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(VideoStylePreset.factory)) as? [String: Any])
        object.removeValue(forKey: "customAspect")
        #expect((try JSONDecoder().decode(VideoStylePreset.self, from: JSONSerialization.data(withJSONObject: object))).customAspect == nil)
    }
}
