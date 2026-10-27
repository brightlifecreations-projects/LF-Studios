import AppKit
import XCTest
@testable import LFStudiosCore

/// 1.2.0, "manual only": new recordings open plain, every effect is a
/// switch, Auto-zoom turns its options on and off, Apply my style is one
/// undo step, after-capture actions are off — and older work is untouched.
@MainActor
final class ManualOnlyTests: XCTestCase {
    private var suiteName: String!
    private var directory: URL!

    override func setUp() async throws {
        VideoTestStorage.isolate()
        suiteName = "LFStudiosCoreTests.ManualOnly.\(UUID().uuidString)"
        Settings.defaults = UserDefaults(suiteName: suiteName)!
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-manual-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VideoStylePresetStore.shared.change { $0 = VideoStylePresetLibrary() }
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        Settings.defaults = .standard
        VideoStylePresetStore.shared.change { $0 = VideoStylePresetLibrary() }
        try? FileManager.default.removeItem(at: directory)
    }

    /// A recording with a pointer path and clicks, opened in the editor.
    private func model(draft: VideoDemoProject? = nil, seconds: Double = 6) async throws -> VideoEditorModel {
        let url = directory.appendingPathComponent("rec-\(Int(seconds)).mp4")
        if !FileManager.default.fileExists(atPath: url.path) {
            try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 1440, height: 900), seconds: seconds, fps: 30)
        }
        let (samples, clicks) = VideoTestSupport.scriptedPointer(duration: seconds)
        let metadata = VideoDemoRecordingMetadata(videoURLPath: url.path, createdAt: Date(), duration: seconds, sourceWidth: 1440, sourceHeight: 900, fps: 30, nativeCursorVisible: false, cursorSamples: samples, clickEvents: clicks, pointPixelScale: 2, renderCursor: true)
        VideoDemoSidecarStore.save(metadata, for: url)
        if let draft { VideoDemoDraftStore.save(draft, for: url) } else { VideoDemoDraftStore.delete(for: url) }
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        XCTAssertTrue(model.isReady)
        return model
    }

    // MARK: New recordings open plain

    func testANewRecordingOpensAsAPlainVideo() async throws {
        let model = try await model()
        let project = model.project
        XCTAssertTrue(project.zoomRegions.isEmpty, "no zooms by themselves, though there are clicks")
        XCTAssertFalse(project.clickEvents.isEmpty)
        XCTAssertFalse(project.autoZoom)
        XCTAssertEqual(project.aspectPreset, .source, "the recording's own frame")
        XCTAssertTrue(project.usesRawSourceFrame, "no background")
        XCTAssertEqual(project.cornerRadius, 0)
        XCTAssertEqual(project.shadow, 0)
        XCTAssertFalse(project.outline)
        XCTAssertEqual(project.motionBlur, 0)
        XCTAssertEqual(project.cursor.size, 1, "the pointer at its real size")
        XCTAssertEqual(project.cursor.smoothing, .off)
        XCTAssertEqual(project.cursor.clickEffect, VideoCursorSettings.ClickEffect.none)
        XCTAssertFalse(project.cursor.hideWhenIdle)
        XCTAssertFalse(project.cursor.motionBlur)
        XCTAssertFalse(project.cursor.tidyEnding)
        XCTAssertTrue(project.cursor.visible, "the pointer still shows")
        XCTAssertFalse(project.webcam.mirror)
        XCTAssertFalse(project.webcam.shrinkWhenZoomed)
        XCTAssertFalse(project.captionStyle.highlightWords)
        XCTAssertFalse(project.keystrokeStyle.visible, "keys hidden until switched on")
        XCTAssertFalse(project.audio.normalizeLoudness, "the loudness is left alone unless asked")
        XCTAssertTrue(project.captions.isEmpty)
    }

    func testStartOverGoesBackToThePlainVideo() async throws {
        let model = try await model()
        model.setAutoZoom(true)
        model.setStyle { $0.toggleBackground() }
        model.resetToOriginal()
        XCTAssertTrue(model.project.zoomRegions.isEmpty)
        XCTAssertFalse(model.project.autoZoom)
        XCTAssertTrue(model.project.usesRawSourceFrame)
    }

    func testTheDefaultPresetIsNeverAppliedByItself() {
        VideoStylePresetStore.shared.change { library in
            var look = VideoStylePreset.factory
            look.padding = 0.2
            let preset = library.add(name: "Old default", style: look, includesAspectRatio: false)
            library.setMyStyle(preset.id)
        }
        let made = VideoDemoProject.make(sourceURL: directory.appendingPathComponent("x.mp4"), duration: 3)
        XCTAssertNotEqual(made.padding, 0.2, "make() no longer applies it")
        let fresh = VideoDemoProject.fresh(sourceURL: directory.appendingPathComponent("x.mp4"), duration: 3)
        XCTAssertEqual(fresh.padding, 0)
    }

    // MARK: Older work stays as it was

    func testAProjectSavedBeforeThisUpdateKeepsItsLookAndItsZoomOptions() throws {
        // A 1.1 project: the factory look, auto zooms, no autoZoom key.
        var old = VideoDemoProject.make(sourceURL: URL(fileURLWithPath: "/tmp/old.mp4"), duration: 6, sourceSize: CGSize(width: 1440, height: 900))
        old.zoomRegions = [VideoZoomRegion(start: 1, end: 3, scale: 2, isAuto: true)]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "autoZoom")
        let decoded = try JSONDecoder().decode(VideoDemoProject.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.autoZoom, "older projects count as on: nothing greys out or changes")
        XCTAssertEqual(decoded, old)
        XCTAssertEqual(decoded.padding, 0.085)
        XCTAssertEqual(decoded.cursor.size, 1.6)
        XCTAssertEqual(decoded.motionBlur, 0.5)
        XCTAssertTrue(decoded.webcam.mirror)
        // A project with only the oldest keys (no cursor, camera, captions
        // settings): it falls back on the old built-in values, as before.
        let minimal = try JSONDecoder().decode(VideoDemoProject.self, from: Data(#"{"version": 2, "id": "\#(UUID().uuidString)", "sourcePath": "/tmp/a.mp4", "createdAt": 0, "sourceWidth": 1280, "sourceHeight": 720, "trimStart": 0, "trimEnd": 3}"#.utf8))
        XCTAssertEqual(minimal.cursor.size, VideoCursorSettings().size)
        XCTAssertTrue(minimal.webcam.mirror)
        XCTAssertTrue(minimal.captionStyle.highlightWords)
        XCTAssertTrue(minimal.autoZoom)
    }

    func testADraftOpensExactlyAsItWasSaved() async throws {
        var draft = VideoDemoProject.make(sourceURL: directory.appendingPathComponent("rec-6.mp4"), duration: 6, sourceSize: CGSize(width: 1440, height: 900))
        draft.padding = 0.12
        draft.cursor.size = 2.2
        draft.zoomRegions = [VideoZoomRegion(start: 1, end: 2.5, scale: 2.5, isAuto: true)]
        let model = try await model(draft: draft)
        XCTAssertTrue(model.restoredDraft)
        XCTAssertEqual(model.project.padding, 0.12)
        XCTAssertEqual(model.project.cursor.size, 2.2)
        XCTAssertEqual(model.project.zoomRegions.count, 1)
        XCTAssertTrue(model.project.autoZoom)
    }

    // MARK: Auto-zoom on clicks

    func testAutoZoomTurnsItsOptionsOnAndOffInOneUndoStep() async throws {
        // 12 s: clicks at 1.4, 3.2, 4.3, 6.0, and 9.6 s; a zoom by hand in the
        // quiet stretch between 6 and 9.6 s doesn't overlap the click zooms.
        let model = try await model(seconds: 12)
        model.addZoom(at: 7.2, length: 0.8)
        let manual = model.project.zoomRegions.filter { !$0.isAuto }
        XCTAssertEqual(manual.count, 1, "a zoom by hand works with Auto-zoom off")

        model.setAutoZoom(true)
        XCTAssertTrue(model.project.autoZoom)
        XCTAssertTrue(model.project.zoomRegions.contains { $0.isAuto }, "zooms from the clicks")
        XCTAssertEqual(model.project.motionBlur, VideoDemoProject.autoZoomMotionBlur)
        XCTAssertTrue(model.project.webcam.shrinkWhenZoomed)
        XCTAssertEqual(model.undoLabel, "Auto-Zoom On")
        XCTAssertTrue(model.project.zoomRegions.contains { $0.id == manual[0].id }, "the hand-made zoom stays")

        // Each option can still be switched off on its own.
        model.setStyle { $0.motionBlur = 0 }
        XCTAssertTrue(model.project.autoZoom)
        model.undo()

        model.undo()
        XCTAssertFalse(model.project.autoZoom, "one ⌘Z undoes it")
        XCTAssertEqual(model.project.zoomRegions.map(\.id), manual.map(\.id))
        XCTAssertEqual(model.project.motionBlur, 0)

        model.redo()
        model.setAutoZoom(false)
        XCTAssertFalse(model.project.autoZoom)
        XCTAssertEqual(model.project.zoomRegions.map(\.id), manual.map(\.id), "only its own zooms go")
        XCTAssertEqual(model.project.motionBlur, 0)
        XCTAssertFalse(model.project.webcam.shrinkWhenZoomed)
        XCTAssertEqual(model.undoLabel, "Auto-Zoom Off")
        XCTAssertEqual(VideoEditDescription.undoTitle("Auto-Zoom On"), L("Undo Auto-Zoom On"))
    }

    // MARK: Apply my style

    func testApplyMyStyleIsOneUndoStep() async throws {
        let model = try await model()
        let before = model.project
        model.applyMyStyle()
        XCTAssertEqual(model.project, before, "no My Style yet: nothing changes")
        XCTAssertNotNil(model.notice, "it says how to choose one")

        var look = VideoStylePreset.factory
        look.padding = 0.15
        look.cornerRadius = 24
        look.cursor.size = 2
        look.autoZoom = true
        VideoStylePresetStore.shared.change { library in
            let preset = library.add(name: "Brand", style: look, includesAspectRatio: true)
            library.setMyStyle(preset.id)
        }
        XCTAssertEqual(model.myStyle?.name, "Brand")
        model.applyMyStyle()
        XCTAssertEqual(model.project.padding, 0.15)
        XCTAssertEqual(model.project.cornerRadius, 24)
        XCTAssertEqual(model.project.cursor.size, 2)
        XCTAssertTrue(model.project.autoZoom, "My Style can turn Auto-zoom on")
        XCTAssertTrue(model.project.zoomRegions.contains { $0.isAuto })
        XCTAssertEqual(model.undoLabel, "Apply My Style")
        model.undo()
        XCTAssertEqual(model.project, before, "one ⌘Z: the plain video again")
    }

    func testAnOldDefaultPresetIsMyStyleNowWithoutBeingApplied() throws {
        // 1.1 kept "default for new recordings" as defaultID.
        let json = #"{"presets":[{"id":"\#(UUID().uuidString)","name":"My Look","style":{"padding":0.2},"includesAspectRatio":false}],"defaultID":null}"#
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let id = ((data["presets"] as? [[String: Any]])?.first?["id"] as? String) ?? ""
        data["defaultID"] = id
        let library = try JSONDecoder().decode(VideoStylePresetLibrary.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertEqual(library.myStyle?.name, "My Look")
        XCTAssertNil(library.myStyle?.style.autoZoom, "an older preset leaves Auto-zoom as it is")
    }

    func testApplyMyStyleHasItsShortcutInTheListAndTheCommands() {
        XCTAssertTrue(VideoShortcutsSheet.groups.flatMap(\.1).contains { $0.0 == "⇧⌘Y" && $0.1 == L("Apply my style") })
    }

    // MARK: After capture

    func testAfterCaptureActionsAreOffUntilTurnedOn() {
        XCTAssertFalse(Settings.afterCaptureCopyToClipboard)
        XCTAssertFalse(Settings.afterCaptureShowOverlay)
        XCTAssertFalse(Settings.openVideoEditorAfterRecording)
        XCTAssertFalse(Settings.afterCaptureSaveAutomatically)
        // A choice someone made is kept, on or off.
        Settings.defaults.set(true, forKey: "afterCaptureShowOverlay")
        Settings.defaults.set(true, forKey: "afterCaptureCopyToClipboard")
        Settings.defaults.set(true, forKey: "openVideoEditorAfterRecording")
        XCTAssertTrue(Settings.afterCaptureShowOverlay)
        XCTAssertTrue(Settings.afterCaptureCopyToClipboard)
        XCTAssertTrue(Settings.openVideoEditorAfterRecording)
        Settings.defaults.set(false, forKey: "afterCaptureShowOverlay")
        XCTAssertFalse(Settings.afterCaptureShowOverlay)
        XCTAssertNil(Settings.defaults.object(forKey: "autoZoomNewRecordings"), "that setting is gone")
    }

    func testTheNoticesGoByThemselves() {
        XCTAssertNotEqual(CaptureEngine.savedToHistoryMessage, "")
        XCTAssertLessThanOrEqual(CaptureEngine.savedToHistorySeconds, 4)
        XCTAssertLessThanOrEqual(VideoDemoPostRecordingPanel.autoCloseSeconds, 8, "never left in the way, whatever the preview's timeout")
        Settings.overlayTimeout = -1
        XCTAssertEqual(VideoDemoPostRecordingPanel.autoCloseSeconds, 6)
    }
}
