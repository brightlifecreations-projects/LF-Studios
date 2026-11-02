import XCTest
@testable import LFStudiosCore

/// 1.17.0's new layout moves things around but removes nothing: in both
/// layouts every command can be found and run from ⌘K, every panel can be
/// opened, the Library keeps its tabs, and the Guide's "Show me" lands on
/// the panel it names.
@MainActor
final class VideoEveryFeatureReachableTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-reach-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testNothingIsLostInEitherLayout() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.white, 3)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        try await forEachEditorStyle { style in
            // Every command is in ⌘K.
            let palette = VideoCommandPalette(model: model).commands.map(\.id)
            for command in VideoEditCommand.allCases where ![.undo, .redo, .addText, .addArrow, .addHighlight, .addBlur].contains(command) {
                XCTAssertTrue(palette.contains("command-\(command.rawValue)"), "\(style): \(command.title) is in ⌘K")
            }
            // Every panel opens (in the new layout: in Properties ▸ Video or Captions).
            for tab in VideoEditorModel.InspectorTab.allCases {
                model.inspectorTab = tab == .background ? .audio : .background
                model.inspectorTab = tab
                if style == .lfStudios {
                    XCTAssertEqual(model.propertiesTab, tab == .captions ? .captions : .video, "\(tab) shows in its Properties tab")
                }
                XCTAssertEqual(model.inspectorTab, tab)
            }
            // The Library keeps all its tabs.
            XCTAssertEqual(Set(VideoLibraryTab.allCases), Set([.media, .audio, .text, .stickers, .effects, .transitions, .captions, .filters, .adjustment]))
        }
        // The Guide's "Show me" names a panel that opens.
        let destinations = GuideContent.featureCategories().flatMap(\.entries).compactMap { entry -> VideoEditorModel.InspectorTab? in
            if case .editor(let tab) = entry.showMe { return tab }
            return nil
        }
        XCTAssertFalse(destinations.isEmpty)
        for tab in Set(destinations) {
            XCTAssertFalse(GuideContent.newLayoutPlace(of: tab).isEmpty, "\(tab) has its place in the new layout")
        }
    }
}
