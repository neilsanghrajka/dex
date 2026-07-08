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

    func testReflowFillsRolesInOrderAndStacksOverflowInFinalRole() {
        let reflowed = ColumnStackState().reflowing(
            ["a", "b", "c", "d", "e"],
            into: [.left, .topRight, .bottomRight]
        )

        XCTAssertEqual(reflowed.windows(in: .left), ["a"])
        XCTAssertEqual(reflowed.windows(in: .topRight), ["b"])
        XCTAssertEqual(reflowed.windows(in: .bottomRight), ["c", "d", "e"])
        XCTAssertEqual(reflowed.windowsStartingAtActive(in: .bottomRight), ["c", "d", "e"])
        XCTAssertEqual(reflowed.activeWindowID(in: .bottomRight), "c")
    }

    func testReflowingFromPreviousRolesClearsOldRoleAssignments() {
        var state = ColumnStackState()
        state.assign("a", to: .left)
        state.assign("b", to: .center)
        state.assign("c", to: .right)

        let reflowed = state.reflowing(from: [.left, .center, .right], to: [.topLeft, .topRight])

        XCTAssertEqual(reflowed.windows(in: .topLeft), ["a"])
        XCTAssertEqual(reflowed.windows(in: .topRight), ["b", "c"])
        XCTAssertEqual(reflowed.windows(in: .left), [])
        XCTAssertEqual(reflowed.windows(in: .center), [])
        XCTAssertEqual(reflowed.windows(in: .right), [])
    }

    func testFilteringToLayoutRolesDropsWindowsWithoutRememberedTargetRole() {
        var state = ColumnStackState()
        state.assign("left-window", to: .left)
        state.assign("center-window", to: .center)
        state.assign("right-window", to: .right)

        let filtered = state.filtered(to: [.left, .right])

        XCTAssertEqual(filtered.windows(in: .left), ["left-window"])
        XCTAssertEqual(filtered.windows(in: .right), ["right-window"])
        XCTAssertEqual(filtered.windows(in: .center), [])
        XCTAssertFalse(filtered.orderedWindowIDs(preferredRoles: [.left, .right]).contains("center-window"))
    }
}
