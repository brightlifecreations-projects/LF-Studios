import AppKit
import XCTest
@testable import LFStudiosCore

/// Keyboard Shortcuts ▸ Customize (1.15.0): LF Studios' keys unchanged by
/// default, the Final Cut Pro and Premiere Pro presets, changing a key,
/// conflicts and reset.
@MainActor
final class VideoKeymapTests: XCTestCase {
    func testTheStandardKeysAreUnchanged() {
        let keymap = VideoKeymap()
        for command in VideoKeymap.editable {
            XCTAssertEqual(keymap.binding(for: command)?.display ?? "", command.standardKeys, "\(command)")
        }
        XCTAssertEqual(keymap.command(key: "b", modifiers: .command), .split)
        XCTAssertEqual(keymap.command(key: "b", modifiers: [.command, .shift]), .splitAllTracks)
        XCTAssertEqual(keymap.command(key: "t", modifiers: .option), .addText)
        XCTAssertEqual(keymap.command(key: "†", modifiers: .option), .addText, "⌥ characters too")
        XCTAssertEqual(keymap.command(key: "t", modifiers: [.option, .shift]), .addTextClip)
        XCTAssertEqual(keymap.command(key: "ˇ", modifiers: [.option, .shift]), .addTextClip)
        XCTAssertEqual(keymap.command(key: "`", modifiers: []), .toggleLinkage)
        XCTAssertEqual(keymap.command(key: "~", modifiers: .shift), .toggleLinkage)
        XCTAssertEqual(keymap.command(key: "[", modifiers: .option), .previousKeyframe)
        XCTAssertNil(keymap.command(key: "j", modifiers: []), "playback keys aren't commands")
        XCTAssertTrue(keymap.clashes.isEmpty)
    }

    func testPresets() {
        for preset in VideoKeymapPreset.allCases {
            var keymap = VideoKeymap()
            keymap.preset = preset
            XCTAssertTrue(keymap.clashes.isEmpty, "\(preset): \(keymap.clashes)")
            for (command, binding) in keymap.bindings {
                XCTAssertTrue(VideoKeymap.editable.contains(command), "\(preset) only changes LF Studios' commands")
                XCTAssertFalse(keymap.conflicts(binding, for: command).contains(where: \.blocks), "\(preset) \(command) on a key the editor keeps")
            }
        }
        var fcp = VideoKeymap()
        fcp.preset = .finalCut
        XCTAssertEqual(fcp.command(key: "m", modifiers: []), .addMarker)
        XCTAssertEqual(fcp.command(key: "[", modifiers: .option), .deleteLeft)
        XCTAssertEqual(fcp.command(key: "k", modifiers: .option), .addKeyframe)
        XCTAssertEqual(fcp.command(key: "b", modifiers: .command), .split)
        var premiere = VideoKeymap()
        premiere.preset = .premiere
        XCTAssertEqual(premiere.command(key: "v", modifiers: []), .selectTool)
        XCTAssertEqual(premiere.command(key: "c", modifiers: []), .splitTool)
        XCTAssertEqual(premiere.command(key: "e", modifiers: .shift), .toggleEnabled)
        XCTAssertEqual(premiere.command(key: "s", modifiers: []), .toggleSnapping)
    }

    func testChangingAKeyAndConflicts() {
        var keymap = VideoKeymap()
        let commandB = VideoKeyBinding(key: "b", modifiers: .command)
        // ⌘B on Mark in: Split loses it.
        XCTAssertEqual(keymap.conflicts(commandB, for: .markIn), [.command(.split)])
        keymap.set(.markIn, to: commandB)
        XCTAssertEqual(keymap.command(key: "b", modifiers: .command), .markIn)
        XCTAssertNil(keymap.binding(for: .split))
        XCTAssertTrue(keymap.clashes.isEmpty)
        // Split back to its own key: Mark in gives it up.
        keymap.reset(.split)
        XCTAssertEqual(keymap.binding(for: .split), commandB)
        XCTAssertNil(keymap.binding(for: .markIn))
        // Setting the preset's own key stores nothing.
        keymap.set(.markIn, to: VideoKeyBinding(key: "i"))
        XCTAssertNil(keymap.custom[VideoEditCommand.markIn.rawValue])
        // Keys the editor keeps, and ones it gives up.
        XCTAssertTrue(keymap.conflicts(VideoKeyBinding(key: " "), for: .markIn).contains(where: \.blocks))
        XCTAssertTrue(keymap.conflicts(VideoKeyBinding(key: "z", modifiers: .command), for: .markIn).contains(where: \.blocks))
        XCTAssertEqual(keymap.conflicts(VideoKeyBinding(key: "j"), for: .markIn), [.takesOver(L("Play backwards"))])
        // Written and read back.
        XCTAssertEqual(VideoKeyBinding("⌥⇧T")?.display, "⌥⇧T")
        XCTAssertEqual(VideoKeyBinding("⇧⌘B"), VideoKeyBinding(key: "B", modifiers: [.shift, .command]))
        XCTAssertNil(VideoKeyBinding("⌘"))
    }
}

/// The keymap kept in the shared settings, and picking a key in the editor
/// (SERIAL: UserDefaults.standard).
@MainActor
final class VideoKeymapSettingsTests: XCTestCase {
    func testKeptAndRecorded() throws {
        let saved = Settings.videoKeymap
        defer {
            Settings.videoKeymap = saved
            VideoKeymap.current = saved.flatMap { try? JSONDecoder().decode(VideoKeymap.self, from: $0) } ?? VideoKeymap()
        }
        VideoKeymap.current = VideoKeymap()
        XCTAssertNil(Settings.videoKeymap, "LF Studios' own keys store nothing")
        let model = VideoEditorModel(videoURL: URL(fileURLWithPath: "/tmp/none.mp4"))
        model.recordingShortcut = .freezeFrame
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option], timestamp: 0, windowNumber: 0, context: nil,
                                                   characters: "ƒ", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3))
        XCTAssertTrue(model.handleKey(event), "the editor hands the key to the recorder")
        XCTAssertNil(model.recordingShortcut)
        XCTAssertEqual(VideoKeymap.current.binding(for: .freezeFrame)?.display, "⌥F")
        XCTAssertEqual(VideoEditCommand.freezeFrame.keys, "⌥F", "menus and the Guide show it")
        XCTAssertNotNil(Settings.videoKeymap)
        // Space can't be taken: still recording, nothing changed.
        model.recordingShortcut = .freezeFrame
        let space = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                   characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        model.recordShortcut(space)
        XCTAssertEqual(model.recordingShortcut, .freezeFrame)
        XCTAssertEqual(VideoKeymap.current.binding(for: .freezeFrame)?.display, "⌥F")
        // The new key runs the command.
        model.recordingShortcut = nil
        XCTAssertEqual(VideoEditCommand.command(key: "f", modifiers: .option), .freezeFrame)
    }
}
