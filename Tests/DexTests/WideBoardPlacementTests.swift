import XCTest
@testable import Dex

final class WideBoardPlacementTests: XCTestCase {
    func testUsesLayoutThreeAndRightRole() {
        XCTAssertEqual(WideBoardPlacement.layoutKind, .leftNarrowCenter)
        XCTAssertEqual(BoardLayoutKind.shortcutKind(for: 3), WideBoardPlacement.layoutKind)
        XCTAssertEqual(WideBoardPlacement.role, .right)
    }

    func testSelectedWindowBecomesActiveInWideRightStack() {
        var state = ColumnStackState()
        state.assign("left", to: .left)
        state.assign("existing-right", to: .right)

        let updated = WideBoardPlacement.placing(windowID: "selected", in: state)

        XCTAssertEqual(updated.column(containing: "selected"), .right)
        XCTAssertEqual(updated.activeWindowID(in: .right), "selected")
        XCTAssertEqual(updated.windows(in: .right).first, "selected")
        XCTAssertEqual(updated.windowsStartingAtActive(in: .right).first, "selected")
    }

    func testRepeatedWIsIdempotentAndCanPromoteAnotherWindow() {
        var state = ColumnStackState()
        state.assign("a", to: .right)
        state.assign("b", to: .right)

        let repeated = WideBoardPlacement.placing(
            windowID: "b",
            in: WideBoardPlacement.placing(windowID: "b", in: state)
        )
        XCTAssertEqual(repeated.windows(in: .right).filter { $0 == "b" }.count, 1)
        XCTAssertEqual(repeated.activeWindowID(in: .right), "b")

        let promoted = WideBoardPlacement.placing(windowID: "a", in: repeated)
        XCTAssertEqual(promoted.activeWindowID(in: .right), "a")
        XCTAssertEqual(promoted.windowsStartingAtActive(in: .right).first, "a")
    }
}
