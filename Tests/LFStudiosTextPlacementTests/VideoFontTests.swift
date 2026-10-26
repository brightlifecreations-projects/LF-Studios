import AppKit
import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import LFStudiosCore

/// A font no Mac has: a system font file with its family renamed (same
/// length, so the file stays valid), made at test time, never committed.
enum TestFonts {
    static let family = "LFStudiosQa"

    static func makeFontFile(in directory: URL) throws -> URL {
        let original = try Data(contentsOf: URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Chalkduster.ttf"))
        func replacing(_ data: Data, _ a: Data, _ b: Data) -> Data {
            var out = data
            var search = out.startIndex..<out.endIndex
            while let range = out.range(of: a, in: search) {
                out.replaceSubrange(range, with: b)
                search = range.upperBound..<out.endIndex
            }
            return out
        }
        var data = replacing(original, "Chalkduster".data(using: .utf16BigEndian)!, family.data(using: .utf16BigEndian)!)
        data = replacing(data, Data("Chalkduster".utf8), Data(family.utf8))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(family).ttf")
        try data.write(to: url)
        return url
    }

    /// The font, added to LF Studios the way Add Font File… does it, its
    /// original file deleted afterwards.
    static func addToLFStudios() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-font-\(UUID().uuidString)", isDirectory: true)
        let file = try makeFontFile(in: scratch)
        _ = try VideoFonts.addFontFile(file)
        try FileManager.default.removeItem(at: scratch)
    }
}

@Suite("Custom fonts", .serialized)
struct VideoFontTests {
    // MARK: The choice

    @Test func aChoiceSurvivesSavingAndOldStylesHaveNone() throws {
        var style = VideoCaptionStyle()
        style.font = VideoFontChoice(family: "Georgia", weight: .black, outline: true, shadow: true)
        let loaded = try JSONDecoder().decode(VideoCaptionStyle.self, from: JSONEncoder().encode(style))
        #expect(loaded.font == style.font)

        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as? [String: Any])
        object.removeValue(forKey: "font")
        let old = try JSONDecoder().decode(VideoCaptionStyle.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.font == nil)
        #expect(try JSONDecoder().decode(VideoFontChoice.self, from: Data(#"{"family": ""}"#.utf8)).family == nil, "an empty family is the built-in font")
        #expect(try JSONDecoder().decode(VideoKeystrokeStyle.self, from: Data("{}".utf8)).font == nil)
        #expect(try JSONDecoder().decode(VideoTitleCards.self, from: Data("{}".utf8)).font == nil)
    }

    @Test func presetsCarryTheFonts() throws {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/fonts.mp4"), duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        project.captionStyle.font = VideoFontChoice(family: "Georgia")
        project.keystrokeStyle.font = VideoFontChoice(family: "Courier New", weight: .bold)
        project.cards.font = VideoFontChoice(family: "Georgia", weight: .black)
        let style = try JSONDecoder().decode(VideoStylePreset.self, from: JSONEncoder().encode(project.style))
        var other = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/other.mp4"), duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        other.apply(preset: VideoNamedStylePreset(name: "Fonts", style: style))
        #expect(other.captionStyle.font?.family == "Georgia")
        #expect(other.keystrokeStyle.font?.weight == .bold)
        #expect(other.cards.font?.weight == .black)
    }

    @Test func weightsPickTheClosestMember() {
        let regular = VideoFonts.font(VideoFontChoice(family: "Avenir Next", weight: .regular), size: 20, defaultWeight: .regular)
        let bold = VideoFonts.font(VideoFontChoice(family: "Avenir Next", weight: .bold), size: 20, defaultWeight: .regular)
        let black = VideoFonts.font(VideoFontChoice(family: "Avenir Next", weight: .black), size: 20, defaultWeight: .regular)
        #expect(regular.familyName == "Avenir Next" && bold.familyName == "Avenir Next")
        func weight(_ font: NSFont) -> Int { NSFontManager.shared.weight(of: font) }
        #expect(weight(regular) < weight(bold) && weight(bold) <= weight(black), "\(regular.fontName) < \(bold.fontName) ≤ \(black.fontName)")
        #expect(!(NSFontManager.shared.traits(of: bold).contains(.italicFontMask)), "upright first")
        // No weight picked: the text's own (a caption look's semibold).
        let auto = VideoFonts.font(VideoFontChoice(family: "Avenir Next"), size: 20, defaultWeight: .heavy)
        #expect(weight(auto) >= weight(bold))
    }

    @Test func aMissingFamilyFallsBackToTheBuiltInFont() {
        let choice = VideoFontChoice(family: "No Such Font 9183", weight: .bold)
        #expect(choice.isMissing)
        let font = VideoFonts.font(choice, size: 30, defaultWeight: .semibold)
        #expect(font == NSFont.systemFont(ofSize: 30, weight: .bold))
        #expect(!VideoFontChoice(family: "Georgia").isMissing)
        #expect(!VideoFontChoice().isMissing)
        #expect(VideoFonts.font(nil, size: 30, defaultWeight: .semibold) == NSFont.systemFont(ofSize: 30, weight: .semibold))
    }

    @Test func cacheKeysTellChoicesApart() {
        let keys = [VideoFontChoice(), VideoFontChoice(family: "Georgia"), VideoFontChoice(family: "Georgia", weight: .bold),
                    VideoFontChoice(family: "Georgia", outline: true), VideoFontChoice(family: "Georgia", shadow: true)].map(\.cacheKey)
        #expect(Set(keys).count == keys.count)
    }

    @Test func anAddedFontIsCopiedAndKeepsWorkingWithoutItsFile() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-font-add-\(UUID().uuidString)", isDirectory: true)
        let file = try TestFonts.makeFontFile(in: scratch)
        let families = try VideoFonts.addFontFile(file)
        #expect(families == [TestFonts.family])
        // Adding the same file again doesn't make another copy.
        let copies = VideoFonts.addedFontFiles().filter { $0.lastPathComponent.hasPrefix(TestFonts.family) }.count
        _ = try VideoFonts.addFontFile(file)
        #expect(VideoFonts.addedFontFiles().filter { $0.lastPathComponent.hasPrefix(TestFonts.family) }.count == copies)
        try FileManager.default.removeItem(at: scratch)

        #expect(VideoFonts.isAvailable(TestFonts.family), "the copy in LF Studios' fonts serves it")
        #expect(VideoFonts.installedFamilies.contains(TestFonts.family))
        #expect(VideoFonts.addedFontFiles(forFamily: TestFonts.family).allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(VideoFonts.font(VideoFontChoice(family: TestFonts.family), size: 24, defaultWeight: .regular).familyName == TestFonts.family)

        let notAFont = scratch.deletingLastPathComponent().appendingPathComponent("not-a-font-\(UUID().uuidString).ttf")
        try Data("hello".utf8).write(to: notAFont)
        #expect(throws: VideoFonts.AddError.notAFont) { try VideoFonts.addFontFile(notAFont) }
        try? FileManager.default.removeItem(at: notAFont)
    }

    @MainActor
    @Test func theEditorNamesMissingFonts() {
        let model = VideoEditorModel(videoURL: URL(fileURLWithPath: "/tmp/fonts-missing.mp4"))
        model.setStyle {
            $0.captionStyle.font = VideoFontChoice(family: "No Such Font 9183")
            $0.cards.font = VideoFontChoice(family: "Georgia")
            $0.overlayEffects = [VideoDemoOverlayEffect(kind: .text, time: 0)]
            $0.overlayEffects[0].font = VideoFontChoice(family: "Another Missing Font")
        }
        #expect(model.missingFontFamilies == ["Another Missing Font", "No Such Font 9183"])
    }

    // MARK: The renderer (the preview and every export)

    private func captionFrame(_ font: VideoFontChoice?) throws -> (image: CGImage, box: CGRect) {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/fonts.mp4"), duration: 3, sourceSize: CGSize(width: 1280, height: 720))
        project.aspectPreset = .widescreen
        project.captions = [VideoCaptionLine(start: 0.2, end: 2.8, text: "Fonts matter in every frame")]
        project.captionStyle.highlightWords = false
        project.captionStyle.font = font
        let size = CGSize(width: 960, height: 540)
        let plan = VideoDemoExporter.makePlan(project: project, sourceDuration: 3, recording: nil)
        var options = VideoFrameRenderer.Options(frameRate: 30)
        options.recordsTextLayout = true
        let renderer = VideoFrameRenderer()
        let screen = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.25)).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
        let image = renderer.render(source: screen, timelineTime: 1.5, plan: plan, outputSize: size, options: options)
        let cg = try #require(CIContext().createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
        return (cg, try #require(renderer.textLayout.caption).rect(in: size))
    }

    @Test func aFontChangesTheCaptionAndAMissingOneDrawsLikeTheBuiltIn() throws {
        let builtIn = try captionFrame(nil)
        let courier = try captionFrame(VideoFontChoice(family: "Courier New", weight: .bold))
        #expect(abs(courier.box.width - builtIn.box.width) > 8, "monospace letters set wider: \(courier.box.width) vs \(builtIn.box.width)")
        let missing = try captionFrame(VideoFontChoice(family: "No Such Font 9183"))
        #expect(missing.box == builtIn.box)
        #expect(TestVideos.rgba(missing.image) == TestVideos.rgba(builtIn.image), "the fallback is the built-in font, pixel for pixel")
    }

    @Test func outlineAndShadowChangeTheLetters() throws {
        let plain = TestVideos.rgba(try captionFrame(VideoFontChoice(family: "Georgia")).image)
        let outlined = TestVideos.rgba(try captionFrame(VideoFontChoice(family: "Georgia", outline: true)).image)
        let shadowed = TestVideos.rgba(try captionFrame(VideoFontChoice(family: "Georgia", shadow: true)).image)
        #expect(plain != outlined)
        #expect(plain != shadowed)
    }
}
