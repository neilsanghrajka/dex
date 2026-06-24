import XCTest
@testable import Dex

final class ColumnStackStateTests: XCTestCase {
    func testAssignMovesWindowBetweenColumns() {
        var state = ColumnStackState()

        state.assign("a", to: .left)
        state.assign("a", to: .center)

        XCTAssertTrue(state.windows(in: .left).isEmpty)
        XCTAssertEqual(state.windows(in: .center), ["a"])
    }

    func testCycleWrapsForwardAndBackward() {
        var state = ColumnStackState()
        state.assign("a", to: .center)
        state.assign("b", to: .center)
        state.assign("c", to: .center)

        XCTAssertEqual(state.cycle(.center, direction: .forward), "a")
        XCTAssertEqual(state.cycle(.center, direction: .backward), "c")
    }

    func testPruneKeepsActiveIndexInBounds() {
        var state = ColumnStackState()
        state.assign("a", to: .right)
        state.assign("b", to: .right)

        state.prune(keeping: ["a"])

        XCTAssertEqual(state.windows(in: .right), ["a"])
        XCTAssertEqual(state.activeWindowID(in: .right), "a")
    }

    func testPromoteMovesWindowToFrontWithinSameColumn() {
        var state = ColumnStackState()
        state.assign("a", to: .left)
        state.assign("b", to: .left)
        state.assign("c", to: .left)

        state.promote("b", in: .left)

        XCTAssertEqual(state.windows(in: .left), ["b", "a", "c"])
        XCTAssertTrue(state.windows(in: .center).isEmpty)
        XCTAssertEqual(state.activeWindowID(in: .left), "b")
    }

    func testWindowsStartingAtActiveRotatesDisplayOrderWithoutMutatingStack() {
        var state = ColumnStackState()
        state.assign("a", to: .center)
        state.assign("b", to: .center)
        state.assign("c", to: .center)

        XCTAssertEqual(state.windowsStartingAtActive(in: .center), ["c", "a", "b"])
        XCTAssertEqual(state.windows(in: .center), ["a", "b", "c"])

        _ = state.cycle(.center, direction: .forward)

        XCTAssertEqual(state.windowsStartingAtActive(in: .center), ["a", "b", "c"])
        XCTAssertEqual(state.windows(in: .center), ["a", "b", "c"])
    }
}
