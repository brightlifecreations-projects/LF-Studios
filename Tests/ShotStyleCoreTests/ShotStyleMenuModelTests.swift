import XCTest
@testable import ShotStyleCore

final class ShotStyleMenuModelTests: XCTestCase {
    func testActionDescriptorKeepsStableDisplayMetadata() {
        let action = ShotStyleMenuAction(
            id: "quick.delete",
            title: "Delete",
            subtitle: "Remove this capture",
            symbolName: "trash",
            shortcut: "⌘⌫",
            isEnabled: false,
            role: .destructive
        )

        XCTAssertEqual(action.id, "quick.delete")
        XCTAssertEqual(action.title, "Delete")
        XCTAssertEqual(action.subtitle, "Remove this capture")
        XCTAssertEqual(action.symbolName, "trash")
        XCTAssertEqual(action.shortcut, "⌘⌫")
        XCTAssertFalse(action.isEnabled)
        XCTAssertEqual(action.role, .destructive)
    }

    func testSectionGroupsActionsWithoutChangingDescriptors() {
        let copy = ShotStyleMenuAction(id: "capture.copy", title: "Copy", symbolName: "doc.on.doc")
        let edit = ShotStyleMenuAction(id: "capture.edit", title: "Edit", symbolName: "pencil", role: .primary)
        let section = ShotStyleMenuSection(id: "capture", title: "Capture", actions: [copy, edit])

        XCTAssertEqual(section.id, "capture")
        XCTAssertEqual(section.title, "Capture")
        XCTAssertEqual(section.actions.map(\.id), ["capture.copy", "capture.edit"])
        XCTAssertEqual(section.actions.last?.role, .primary)
    }
}
