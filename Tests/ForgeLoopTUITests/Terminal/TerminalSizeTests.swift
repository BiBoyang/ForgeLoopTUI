import XCTest
@testable import ForgeLoopTUI

final class TerminalSizeTests: XCTestCase {
    func testGetTerminalSizeReturnsValidDimensionsWhenPresent() {
        guard let size = getTerminalSize() else {
            return
        }
        XCTAssertGreaterThan(size.rows, 0)
        XCTAssertGreaterThan(size.columns, 0)
    }
}
