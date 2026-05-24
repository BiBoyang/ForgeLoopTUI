import XCTest
@testable import ForgeLoopTUI

final class TerminalSizeTests: XCTestCase {
    func testGetTerminalSizeReturnsValidDimensionsWhenPresent() throws {
        guard let size = getTerminalSize() else {
            try XCTSkipIf(true, "No TTY available — terminal size cannot be queried in this environment")
            return
        }
        XCTAssertGreaterThan(size.rows, 0)
        XCTAssertGreaterThan(size.columns, 0)
    }
}
