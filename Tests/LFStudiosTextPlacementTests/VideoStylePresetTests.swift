import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import LFStudiosCore

/// Saved style presets (VideoStylePresets.swift).
@Suite("Style presets", .serialized)
struct VideoStylePresetTests {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-presets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func project() -> VideoDemoProject {
        var project = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/presets.mp4"), duration: 4, sourceSize: CGSize(width: 1280, height: 720))
        project.apply(style: .factory)
        project.aspectPreset = .widescreen
        return project
    }

    /// A look unlike the built-in one in every part a preset carries.
    private func distinctStyle() -> VideoStylePreset {
        var style = VideoStylePreset.factory
        style.aspectPreset = .vertical
        style.background = .color(VideoRGBA(0.9, 0.1, 0.1))
        style.backgroundBlur = 0.3
        style.padding = 0.2
        style.cornerRadius = 0
        style.shadow = 0
        style.outline = false
        style.zoomSpeed = .quick
        style.defaultZoomScale = 2.6
        style.motionBlur = 0
        style.cursor.size = 2.2
        style.webcam.anchor = .topLeft
        style.webcam.size = 0.4
        style.captionStyle.size = .large
        style.captionStyle.position = .top
        style.keystrokeStyle.size = .small
        return style
    }

    // MARK: The library

    @Test func namesStayUnique() {
        var library = VideoStylePresetLibrary()
        let first = library.add(name: "Brand", style: .factory, includesAspectRatio: false)
        let second = library.add(name: "brand", style: .factory, includesAspectRatio: false)
        let third = library.add(name: "  Brand ", style: .factory, includesAspectRatio: false)
        #expect(first.name == "Brand")
        #expect(second.name == "brand 2")
        #expect(third.name == "Brand 3")
        library.rename(third.id, to: "Brand")
        #expect(library.preset(third.id)?.name == "Brand 3", "renaming onto a taken name keeps them apart")
        library.rename(third.id, to: "   ")
        #expect(library.preset(third.id)?.name == "Brand 3", "an empty name is ignored")
        library.rename(third.id, to: "Tutorials")
        #expect(library.preset(third.id)?.name == "Tutorials")
    }

    @Test func updateKeepsTheNameAndTheAspectSetting() {
        var library = VideoStylePresetLibrary()
        let preset = library.add(name: "Brand", style: .factory, includesAspectRatio: true)
        library.update(preset.id, with: distinctStyle())
        let updated = library.preset(preset.id)
        #expect(updated?.style == distinctStyle())
        #expect(updated?.name == "Brand")
        #expect(updated?.includesAspectRatio == true)
    }

    @Test func deletingTheDefaultClearsIt() {
        var library = VideoStylePresetLibrary()
        let a = library.add(name: "A", style: .factory, includesAspectRatio: false)
        let b = library.add(name: "B", style: distinctStyle(), includesAspectRatio: false)
        library.setDefault(b.id)
        #expect(library.defaultPreset?.id == b.id)
        library.setDefault(UUID())
        #expect(library.defaultID == nil, "an unknown preset can't be the default")
        library.setDefault(b.id)
        library.delete(b.id)
        #expect(library.defaultID == nil)
        #expect(library.presets.map(\.id) == [a.id])
    }

    // MARK: Applying

    @Test func applyingLeavesTheAspectRatioUnlessThePresetIncludesIt() {
        var project = project()
        project.cursor.visible = false
        let without = VideoNamedStylePreset(name: "No aspect", style: distinctStyle(), includesAspectRatio: false)
        project.apply(preset: without)
        #expect(project.aspectPreset == .widescreen)
        #expect(project.background == .color(VideoRGBA(0.9, 0.1, 0.1)))
        #expect(project.padding == 0.2)
        #expect(project.webcam.anchor == .topLeft)
        #expect(project.captionStyle.position == .top)
        #expect(project.cursor.size == 2.2)
        #expect(project.cursor.visible == false, "whether the pointer was captured is the recording's")
        #expect(without.matches(project))

        let with = VideoNamedStylePreset(name: "Vertical", style: distinctStyle(), includesAspectRatio: true)
        #expect(!with.matches(project), "its aspect ratio counts")
        project.apply(preset: with)
        #expect(project.aspectPreset == .vertical)
        #expect(with.matches(project))
    }

    // MARK: Saving and loading

    @Test func theLibrarySurvivesSavingAndLoading() throws {
        let root = try temporaryRoot()
        var library = VideoStylePresetLibrary()
        let a = library.add(name: "Brand", style: distinctStyle(), includesAspectRatio: true)
        library.add(name: "Plain", style: .factory, includesAspectRatio: false)
        library.setDefault(a.id)
        #expect(VideoStylePresetStore.save(library, root: root))
        let loaded = VideoStylePresetStore.load(root: root, defaults: UserDefaults(suiteName: "presets-\(UUID())")!)
        #expect(loaded == library)
        #expect(loaded.defaultPreset?.name == "Brand")
    }

    @Test func theOldSavedLookBecomesTheFirstPresetAndStaysTheDefault() throws {
        let root = try temporaryRoot()
        let defaults = try #require(UserDefaults(suiteName: "presets-legacy-\(UUID())"))
        defaults.set(try JSONEncoder().encode(distinctStyle()), forKey: VideoStylePresetStore.legacyDefaultsKey)
        let library = VideoStylePresetStore.load(root: root, defaults: defaults)
        #expect(library.presets.count == 1)
        let mine = try #require(library.defaultPreset)
        #expect(mine.style == distinctStyle())
        #expect(mine.includesAspectRatio, "it set the aspect ratio before, so it still does")
        // Once the library is on disk, the old look is never read again.
        var edited = library
        edited.delete(mine.id)
        #expect(VideoStylePresetStore.save(edited, root: root))
        #expect(VideoStylePresetStore.load(root: root, defaults: defaults).presets.isEmpty)
    }

    @Test func noOldLookMeansNoPresets() throws {
        let library = VideoStylePresetStore.load(root: try temporaryRoot(), defaults: UserDefaults(suiteName: "presets-none-\(UUID())")!)
        #expect(library.presets.isEmpty)
        #expect(library.defaultID == nil)
    }

    @Test func aDamagedLibraryFileDoesntCrash() throws {
        let root = try temporaryRoot()
        let url = VideoStylePresetStore.fileURL(root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        #expect(VideoStylePresetStore.load(root: root, defaults: UserDefaults(suiteName: "presets-bad-\(UUID())")!).presets.isEmpty)
    }

    @Test func presetsSavedBeforeANewSettingStillLoad() throws {
        // A preset from this version, with fields removed the way an older
        // version (or a hand-edited file) would leave them.
        let preset = VideoNamedStylePreset(name: "Old", style: distinctStyle(), includesAspectRatio: true)
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as? [String: Any])
        object.removeValue(forKey: "includesAspectRatio")
        var style = try #require(object["style"] as? [String: Any])
        for key in ["captionStyle", "keystrokeStyle", "webcam", "motionBlur"] { style.removeValue(forKey: key) }
        object["style"] = style
        let old = try JSONDecoder().decode(VideoNamedStylePreset.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.name == "Old")
        #expect(old.includesAspectRatio == false)
        #expect(old.style.background == distinctStyle().background)
        #expect(old.style.captionStyle == VideoStylePreset.factory.captionStyle)
        #expect(old.style.motionBlur == VideoStylePreset.factory.motionBlur)
    }

    // MARK: Sharing

    @Test func exportedPresetsCarryTheirBackgroundPictures() throws {
        let root = try temporaryRoot()
        let picture = root.appendingPathComponent("brand.png")
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus(); NSColor.systemTeal.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill(); image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: picture)

        var style = distinctStyle()
        style.background = .image(picture.path)
        let presets = [VideoNamedStylePreset(name: "Picture", style: style), VideoNamedStylePreset(name: "Plain", style: .factory, includesAspectRatio: true)]
        let data = try VideoStylePresetFile.make(presets).encoded()
        #expect(!String(decoding: data, as: UTF8.self).contains(picture.path), "no path from this Mac in the shared file")

        // Someone else's Mac: the picture is gone from where it was.
        try FileManager.default.removeItem(at: picture)
        let file = try VideoStylePresetFile.read(data)
        let unpacked = file.unpacked(imagesDirectory: root.appendingPathComponent("Imported", isDirectory: true))
        guard case .image(let newPath) = unpacked[0].style.background else {
            Issue.record("the picture background didn't come back")
            return
        }
        #expect(FileManager.default.contents(atPath: newPath) == png)
        #expect(unpacked[1].includesAspectRatio)

        var library = VideoStylePresetLibrary()
        let existing = library.add(name: "Picture", style: .factory, includesAspectRatio: false)
        let added = library.adding(unpacked)
        #expect(added.map(\.name) == ["Picture 2", "Plain"])
        #expect(!added.contains { $0.id == existing.id || presets.map(\.id).contains($0.id) }, "imported presets get new ids")
    }

    @Test func otherFilesAreRefused() {
        #expect(throws: VideoStylePresetFile.ReadError.notAPresetFile) {
            try VideoStylePresetFile.read(Data(#"{"kind": "something-else", "presets": []}"#.utf8))
        }
        #expect(throws: VideoStylePresetFile.ReadError.notAPresetFile) {
            try VideoStylePresetFile.read(Data("not json".utf8))
        }
    }

    @Test func aFileFromANewerVersionStillImports() throws {
        let json = """
        {"kind": "lfstudios-style-presets", "version": 7, "somethingNew": true, "images": {},
         "presets": [{"id": "\(UUID().uuidString)", "name": "Future", "includesAspectRatio": false, "aFutureField": 3,
                      "style": {"padding": 0.15, "background": {"color": {"_0": {"r": 0, "g": 0, "b": 1, "a": 1}}}}}]}
        """
        let file = try VideoStylePresetFile.read(Data(json.utf8))
        #expect(file.presets.count == 1)
        #expect(file.presets[0].name == "Future")
        #expect(file.presets[0].style.padding == 0.15)
    }

    // MARK: New recordings and undo (the app's own storage root)

    /// Runs `body` with LF Studios' storage in a fresh folder.
    private func withStorage(_ body: (URL) async throws -> Void) async throws {
        let previous = VideoStorageLocation.overrideRoot
        let root = try temporaryRoot()
        VideoStorageLocation.overrideRoot = root
        defer { VideoStorageLocation.overrideRoot = previous }
        try await body(root)
    }

    @Test func newRecordingsStartFromTheDefaultPreset() async throws {
        try await withStorage { root in
            var library = VideoStylePresetLibrary()
            let noAspect = library.add(name: "Red", style: distinctStyle(), includesAspectRatio: false)
            library.setDefault(noAspect.id)
            #expect(VideoStylePresetStore.save(library, root: root))
            let fresh = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/new.mp4"))
            #expect(fresh.background == .color(VideoRGBA(0.9, 0.1, 0.1)))
            #expect(fresh.aspectPreset == VideoStylePreset.factory.aspectPreset, "this preset leaves the aspect ratio alone")

            library.update(noAspect.id, with: distinctStyle())
            library.presets[0].includesAspectRatio = true
            #expect(VideoStylePresetStore.save(library, root: root))
            #expect(VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/new.mp4")).aspectPreset == .vertical)

            // "Use This Look for New Recordings" updates the default preset.
            var look = distinctStyle()
            look.padding = 0.05
            VideoStylePreset.saveAsDefault(look)
            #expect(VideoStylePreset.savedDefault?.padding == 0.05)
            #expect(VideoStylePresetStore.load(root: root).presets.count == 1)
            VideoStylePreset.saveAsDefault(nil)
            #expect(VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/new.mp4")).background == VideoStylePreset.factory.background)
        }
    }

    @MainActor
    @Test func applyingAPresetIsOneUndoStep() async throws {
        try await withStorage { _ in
            let store = VideoStylePresetStore.shared
            store.reloadIfNeeded()
            let preset = store.change { $0.add(name: "Red", style: distinctStyle(), includesAspectRatio: false) }
            let model = VideoEditorModel(videoURL: URL(fileURLWithPath: "/tmp/presets-undo.mp4"))
            model.setStyle { $0.apply(style: .factory) }
            let before = model.project
            model.applyPreset(preset.id)
            #expect(model.project.background == .color(VideoRGBA(0.9, 0.1, 0.1)))
            #expect(model.matchingPreset?.id == preset.id)
            #expect(model.undoLabel == "Apply Preset")
            model.undo()
            #expect(model.project == before)
            model.redo()
            #expect(model.project.background == .color(VideoRGBA(0.9, 0.1, 0.1)))
        }
    }
}
