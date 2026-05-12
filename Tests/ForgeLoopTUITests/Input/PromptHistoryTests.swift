import XCTest
@testable import ForgeLoopTUI

final class PromptHistoryTests: XCTestCase {
    // MARK: - commit

    func testCommitStoresEntry() {
        var history = PromptHistory()
        history.commit("hello")
        XCTAssertEqual(history.prev(), "hello")
    }

    func testCommitMultipleStoresInLIFOOrder() {
        var history = PromptHistory()
        history.commit("first")
        history.commit("second")
        // Most recent first (LIFO)
        XCTAssertEqual(history.prev(), "second")
        XCTAssertEqual(history.prev(), "first")
        XCTAssertNil(history.prev())
    }

    func testCommitEmptyStringIgnored() {
        var history = PromptHistory()
        history.commit("")
        XCTAssertNil(history.prev())
    }

    func testCommitResetsIndexToCurrent() {
        var history = PromptHistory()
        history.commit("a")
        history.commit("b")
        _ = history.prev()  // index = 0, looking at "b"
        XCTAssertFalse(history.isAtCurrent)
        history.commit("c")  // should reset index
        XCTAssertTrue(history.isAtCurrent)
    }

    // MARK: - prev

    func testPrevReturnsNilWhenEmpty() {
        var history = PromptHistory()
        XCTAssertNil(history.prev())
    }

    func testPrevReturnsMostRecentFirst() {
        var history = PromptHistory()
        history.commit("a")
        history.commit("b")
        history.commit("c")
        XCTAssertEqual(history.prev(), "c")
        XCTAssertEqual(history.prev(), "b")
        XCTAssertEqual(history.prev(), "a")
    }

    func testPrevReturnsNilAtOldest() {
        var history = PromptHistory()
        history.commit("a")
        _ = history.prev()  // "a"
        XCTAssertNil(history.prev())  // at boundary
    }

    // MARK: - next

    func testNextReturnsNilWhenAtCurrent() {
        var history = PromptHistory()
        history.commit("a")
        // at current position (index = -1)
        XCTAssertNil(history.next())
    }

    func testNextReturnsNewerEntry() {
        var history = PromptHistory()
        history.commit("a")
        history.commit("b")
        _ = history.prev()  // "b" (index 0)
        _ = history.prev()  // "a" (index 1)
        XCTAssertEqual(history.next(), "b")  // index 0
    }

    func testNextReturnsNilWhenBackToCurrent() {
        var history = PromptHistory()
        history.commit("a")
        _ = history.prev()  // "a" (index 0)
        XCTAssertNil(history.next())  // back to current (-1)
        XCTAssertTrue(history.isAtCurrent)
    }

    // MARK: - reset

    func testResetSetsIndexToCurrent() {
        var history = PromptHistory()
        history.commit("a")
        history.commit("b")
        _ = history.prev()  // "b"
        XCTAssertFalse(history.isAtCurrent)
        history.reset()
        XCTAssertTrue(history.isAtCurrent)
        XCTAssertNil(history.next())  // at current, next returns nil
    }

    func testResetPreservesEntries() {
        var history = PromptHistory()
        history.commit("a")
        history.commit("b")
        _ = history.prev()  // "b"
        _ = history.prev()  // "a"
        history.reset()
        // Entries preserved; can re-navigate
        XCTAssertEqual(history.prev(), "b")
        XCTAssertEqual(history.prev(), "a")
    }

    // MARK: - isAtCurrent

    func testIsAtCurrentInitiallyTrue() {
        let history = PromptHistory()
        XCTAssertTrue(history.isAtCurrent)
    }

    func testIsAtCurrentAfterCommit() {
        var history = PromptHistory()
        history.commit("a")
        XCTAssertTrue(history.isAtCurrent)
    }

    func testIsAtCurrentFalseAfterPrev() {
        var history = PromptHistory()
        history.commit("a")
        _ = history.prev()
        XCTAssertFalse(history.isAtCurrent)
    }

    // MARK: - Integration scenarios

    func testFullNavigationCycle() {
        var history = PromptHistory()
        history.commit("a")
        history.commit("b")
        history.commit("c")

        // Navigate back
        XCTAssertEqual(history.prev(), "c")
        XCTAssertEqual(history.prev(), "b")
        XCTAssertEqual(history.prev(), "a")
        XCTAssertNil(history.prev())  // at oldest

        // Navigate forward
        XCTAssertEqual(history.next(), "b")
        XCTAssertEqual(history.next(), "c")
        XCTAssertNil(history.next())  // back to current
        XCTAssertTrue(history.isAtCurrent)
    }

    func testDuplicateCommitsArePreserved() {
        var history = PromptHistory()
        history.commit("dup")
        history.commit("dup")
        XCTAssertEqual(history.prev(), "dup")
        XCTAssertEqual(history.prev(), "dup")
        XCTAssertNil(history.prev())
    }

    func testPrevThenCommitThenPrev() {
        var history = PromptHistory()
        history.commit("old")
        _ = history.prev()  // "old"
        history.commit("new")
        // After commit, index reset; new entry is most recent
        XCTAssertEqual(history.prev(), "new")
        XCTAssertEqual(history.prev(), "old")
    }
}
