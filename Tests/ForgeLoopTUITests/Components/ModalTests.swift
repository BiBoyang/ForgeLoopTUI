import XCTest
@testable import ForgeLoopTUI

final class ModalTests: XCTestCase {
    func testModalRendererBuildsTitleBodyFooterSections() {
        let renderer = ModalRenderer(styleMode: .plain)
        let lines = renderer.render(
            title: "Select a model",
            body: ["○ gpt-4.1", "● gpt-4o"],
            footer: "(↑↓ to select, Enter to confirm, Esc to cancel)"
        )

        XCTAssertEqual(
            lines,
            [
                "Select a model",
                "",
                "○ gpt-4.1",
                "● gpt-4o",
                "",
                "(↑↓ to select, Enter to confirm, Esc to cancel)",
            ]
        )
    }

    func testListPickerNavigationAndConfirm() {
        var state = ListPickerState(
            title: "Select a model",
            items: [
                .init(id: "gpt-4.1", title: "gpt-4.1"),
                .init(id: "gpt-4o", title: "gpt-4o"),
                .init(id: "o3-mini", title: "o3-mini"),
            ],
            selectedIndex: 1
        )

        XCTAssertEqual(state.selectedItem?.id, "gpt-4o")

        _ = state.handle(.moveDown)
        XCTAssertEqual(state.selectedItem?.id, "o3-mini")

        _ = state.handle(.moveDown)
        XCTAssertEqual(state.selectedItem?.id, "o3-mini")

        _ = state.handle(.moveUp)
        if case .confirmed(let item) = state.handle(.confirm) {
            XCTAssertEqual(item.id, "gpt-4o")
        } else {
            XCTFail("Expected confirmed selection")
        }
    }

    func testListPickerCancelAndEmptyState() {
        var empty = ListPickerState(title: "Nothing here", items: [])

        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.selectedItem, nil)
        XCTAssertEqual(empty.handle(.confirm), .none)
        XCTAssertEqual(empty.handle(.cancel), .cancelled)
    }

    func testListPickerRendererHighlightsSelectionAndSubtitles() {
        let state = ListPickerState(
            title: "Select a model",
            subtitle: "provider: openai",
            items: [
                .init(id: "gpt-4.1", title: "gpt-4.1", subtitle: "stable"),
                .init(id: "gpt-4o", title: "gpt-4o", subtitle: "fast"),
            ],
            selectedIndex: 1
        )
        let renderer = ListPickerRenderer(styleMode: .plain)
        let lines = renderer.render(state: state)

        XCTAssertEqual(lines[0], "Select a model")
        XCTAssertTrue(lines.contains("provider: openai"))
        XCTAssertTrue(lines.contains("○ gpt-4.1"))
        XCTAssertTrue(lines.contains("● gpt-4o"))
        XCTAssertTrue(lines.contains("  stable"))
        XCTAssertTrue(lines.contains("  fast"))
        XCTAssertEqual(lines.last, "(↑↓ to select, Enter to confirm, Esc to cancel)")
    }
}
