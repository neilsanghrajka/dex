import CoreGraphics
import XCTest
@testable import Dex

final class GridLayoutTests: XCTestCase {
    func testThreeColumnRatioUsesVisibleFrameAndGutters() {
        let layout = GridLayout(visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000), gutter: 10)

        let left = layout.rect(for: .left)
        let center = layout.rect(for: .center)
        let right = layout.rect(for: .right)

        XCTAssertEqual(left.width, 475)
        XCTAssertEqual(center.width, 950)
        XCTAssertEqual(right.width, 475)
        XCTAssertEqual(center.minX, left.maxX + 10)
        XCTAssertEqual(right.minX, center.maxX + 10)
        XCTAssertEqual(left.height, 1000)
    }

    func testWideCenterKeepsThreeColumnsWithNarrowerSides() {
        let layout = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000),
            gutter: 10,
            kind: .wideCenter
        )

        let left = layout.rect(for: .left)
        let center = layout.rect(for: .center)
        let right = layout.rect(for: .right)

        XCTAssertEqual(left.width, 342)
        XCTAssertEqual(center.width, 1216)
        XCTAssertEqual(right.width, 342)
        XCTAssertEqual(center.minX, left.maxX + 10)
        XCTAssertEqual(right.minX, center.maxX + 10)
    }

    func testPairLayoutsUseFullWidthTwoColumnLayouts() {
        let leftNarrowRightWide = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000),
            gutter: 10,
            kind: .leftNarrowCenter
        )

        XCTAssertEqual(leftNarrowRightWide.roles, [.left, .right])
        XCTAssertEqual(leftNarrowRightWide.rect(for: .left).width, 475)
        XCTAssertEqual(leftNarrowRightWide.rect(for: .right).width, 1435)
        XCTAssertEqual(leftNarrowRightWide.rect(for: .right).minX, leftNarrowRightWide.rect(for: .left).maxX + 10)
        XCTAssertEqual(leftNarrowRightWide.rect(for: .right).maxX, 1920)

        let leftWideRightNarrow = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000),
            gutter: 10,
            kind: .centerRightNarrow
        )

        XCTAssertEqual(leftWideRightNarrow.roles, [.left, .right])
        XCTAssertEqual(leftWideRightNarrow.rect(for: .left).width, 1435)
        XCTAssertEqual(leftWideRightNarrow.rect(for: .right).width, 475)
        XCTAssertEqual(leftWideRightNarrow.rect(for: .right).minX, leftWideRightNarrow.rect(for: .left).maxX + 10)
        XCTAssertEqual(leftWideRightNarrow.rect(for: .right).maxX, 1920)
    }

    func testLayoutSwitchFallbackAllowsHorizontalOnlyMovement() {
        let previous = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000),
            gutter: 10,
            kind: .threeColumn
        )
        let next = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000),
            gutter: 10,
            kind: .halves
        )

        XCTAssertEqual(
            next.nearestHorizontallyCompatibleRole(
                to: point(in: previous.rect(for: .center)),
                from: .center,
                in: previous
            ),
            .left
        )
        XCTAssertEqual(
            next.nearestHorizontallyCompatibleRole(
                to: point(in: previous.rect(for: .right)),
                from: .right,
                in: previous
            ),
            .right
        )
    }

    func testLayoutSwitchFallbackRejectsTopBottomMovement() {
        let fullHeight = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .threeColumn
        )
        let stacked = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .leftMainRightStack
        )
        let twoByTwo = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .twoByTwo
        )

        XCTAssertNil(
            stacked.nearestHorizontallyCompatibleRole(
                to: point(in: fullHeight.rect(for: .right)),
                from: .right,
                in: fullHeight
            )
        )
        XCTAssertNil(
            fullHeight.nearestHorizontallyCompatibleRole(
                to: point(in: twoByTwo.rect(for: .topLeft)),
                from: .topLeft,
                in: twoByTwo
            )
        )
        XCTAssertEqual(
            stacked.nearestHorizontallyCompatibleRole(
                to: point(in: twoByTwo.rect(for: .topRight)),
                from: .topRight,
                in: twoByTwo
            ),
            .topRight
        )
    }

    func testRoleHitTesting() {
        let layout = GridLayout(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 500), gutter: 10)

        XCTAssertEqual(layout.role(containing: CGPoint(x: 50, y: 100)), .left)
        XCTAssertEqual(layout.role(containing: CGPoint(x: 500, y: 100)), .center)
        XCTAssertEqual(layout.role(containing: CGPoint(x: 950, y: 100)), .right)
    }

    func testTwoByTwoGeometryUsesScreenQuadrants() {
        let layout = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .twoByTwo
        )

        XCTAssertEqual(layout.roles, [.topLeft, .topRight, .bottomLeft, .bottomRight])
        XCTAssertEqual(layout.rect(for: .topLeft), CGRect(x: 0, y: 405, width: 495, height: 395))
        XCTAssertEqual(layout.rect(for: .topRight), CGRect(x: 505, y: 405, width: 495, height: 395))
        XCTAssertEqual(layout.rect(for: .bottomLeft), CGRect(x: 0, y: 0, width: 495, height: 395))
        XCTAssertEqual(layout.rect(for: .bottomRight), CGRect(x: 505, y: 0, width: 495, height: 395))
        XCTAssertEqual(layout.nearestRole(to: CGPoint(x: 20, y: 790)), .topLeft)
    }

    func testStackedHalfLayoutsNameTopAndBottomByScreenPosition() {
        let leftFocus = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .leftMainRightStack
        )

        XCTAssertEqual(leftFocus.rect(for: .left), CGRect(x: 0, y: 0, width: 495, height: 800))
        XCTAssertEqual(leftFocus.rect(for: .topRight), CGRect(x: 505, y: 405, width: 495, height: 395))
        XCTAssertEqual(leftFocus.rect(for: .bottomRight), CGRect(x: 505, y: 0, width: 495, height: 395))

        let rightFocus = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .leftStackRightMain
        )

        XCTAssertEqual(rightFocus.rect(for: .topLeft), CGRect(x: 0, y: 405, width: 495, height: 395))
        XCTAssertEqual(rightFocus.rect(for: .bottomLeft), CGRect(x: 0, y: 0, width: 495, height: 395))
        XCTAssertEqual(rightFocus.rect(for: .right), CGRect(x: 505, y: 0, width: 495, height: 800))
    }

    func testPlainNumberShortcutsMapToCustomLayouts() {
        XCTAssertEqual(BoardLayoutKind.shortcutKind(for: 1), .wideCenter)
        XCTAssertEqual(BoardLayoutKind.shortcutKind(for: 2), .threeColumn)
        XCTAssertEqual(BoardLayoutKind.shortcutKind(for: 3), .leftNarrowCenter)
        XCTAssertEqual(BoardLayoutKind.shortcutKind(for: 4), .centerRightNarrow)
        XCTAssertEqual(BoardLayoutKind.shortcutKind(for: 5), .halves)
        XCTAssertEqual(BoardLayoutKind.shortcutKind(for: 6), .twoByTwo)
        XCTAssertEqual(BoardLayoutKind.shortcutKind(for: 7), .leftMainRightStack)
        XCTAssertEqual(BoardLayoutKind.shortcutKind(for: 8), .leftStackRightMain)
        XCTAssertNil(BoardLayoutKind.shortcutKind(for: 0))
        XCTAssertNil(BoardLayoutKind.shortcutKind(for: 9))
        XCTAssertEqual(BoardLayoutKind.shortcutSlots, Array(1...8))
    }

    func testHorizontalRoleMovesFollowVisualRows() {
        let layout = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .twoByTwo
        )

        XCTAssertEqual(layout.nextRole(after: .topLeft), .topRight)
        XCTAssertEqual(layout.previousRole(before: .topRight), .topLeft)
        XCTAssertEqual(layout.nextRole(after: .topRight), .topRight)
        XCTAssertEqual(layout.previousRole(before: .bottomLeft), .bottomLeft)
        XCTAssertEqual(layout.nextRole(after: .bottomLeft), .bottomRight)
        XCTAssertEqual(layout.previousRole(before: .bottomRight), .bottomLeft)
    }

    func testThreeColumnHorizontalMovesAdvanceExactlyOneRole() {
        let layout = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000),
            gutter: 10,
            kind: .threeColumn
        )

        XCTAssertEqual(layout.nextRole(after: .left), .center)
        XCTAssertEqual(layout.nextRole(after: .center), .right)
        XCTAssertEqual(layout.previousRole(before: .right), .center)
        XCTAssertEqual(layout.previousRole(before: .center), .left)
    }

    func testBoardNavigationProcessesOnlyInitialDirectionalKeyDown() {
        XCTAssertTrue(BoardKeyboardNavigationPolicy.shouldProcess(keyCode: 124, isRepeat: false))
        XCTAssertFalse(BoardKeyboardNavigationPolicy.shouldProcess(keyCode: 124, isRepeat: true))
        XCTAssertFalse(BoardKeyboardNavigationPolicy.shouldProcess(keyCode: 125, isRepeat: true))
        XCTAssertTrue(BoardKeyboardNavigationPolicy.shouldProcess(keyCode: 36, isRepeat: true))
    }

    func testDirectionalKeyPressGateProcessesOneCommandPerPhysicalPress() {
        var gate = BoardDirectionalKeyPressGate()

        XCTAssertTrue(gate.shouldProcessKeyDown(keyCode: 124, isRepeat: false))
        XCTAssertFalse(gate.shouldProcessKeyDown(keyCode: 124, isRepeat: false))
        XCTAssertFalse(gate.shouldProcessKeyDown(keyCode: 124, isRepeat: true))

        XCTAssertTrue(gate.shouldProcessKeyDown(keyCode: 125, isRepeat: false))
        gate.processKeyUp(keyCode: 124)
        XCTAssertTrue(gate.shouldProcessKeyDown(keyCode: 124, isRepeat: false))

        gate.reset()
        XCTAssertTrue(gate.shouldProcessKeyDown(keyCode: 124, isRepeat: false))
        XCTAssertTrue(gate.shouldProcessKeyDown(keyCode: 36, isRepeat: true))
    }

    func testStackedHorizontalRoleMovesDoNotMoveVertically() {
        let leftMain = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .leftMainRightStack
        )

        XCTAssertEqual(leftMain.nextRole(after: .left), .topRight)
        XCTAssertEqual(leftMain.nextRole(after: .topRight), .topRight)
        XCTAssertEqual(leftMain.previousRole(before: .topRight), .left)
        XCTAssertEqual(leftMain.previousRole(before: .bottomRight), .left)

        let rightMain = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .leftStackRightMain
        )

        XCTAssertEqual(rightMain.previousRole(before: .right), .topLeft)
        XCTAssertEqual(rightMain.previousRole(before: .topLeft), .topLeft)
        XCTAssertEqual(rightMain.nextRole(after: .topLeft), .right)
        XCTAssertEqual(rightMain.nextRole(after: .bottomLeft), .right)
    }

    func testEveryVisualEdgeRoleIsRecognized() {
        let grid = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .twoByTwo
        )

        XCTAssertTrue(grid.isEdgeRole(.topRight, direction: .right))
        XCTAssertTrue(grid.isEdgeRole(.bottomRight, direction: .right))
        XCTAssertFalse(grid.isEdgeRole(.topLeft, direction: .right))
        XCTAssertTrue(grid.isEdgeRole(.topLeft, direction: .left))
        XCTAssertTrue(grid.isEdgeRole(.bottomLeft, direction: .left))
        XCTAssertFalse(grid.isEdgeRole(.bottomRight, direction: .left))

        let stack = GridLayout(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            gutter: 10,
            kind: .leftMainRightStack
        )

        XCTAssertTrue(stack.isEdgeRole(.topRight, direction: .right))
        XCTAssertTrue(stack.isEdgeRole(.bottomRight, direction: .right))
        XCTAssertFalse(stack.isEdgeRole(.left, direction: .right))
    }

    private func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }
}
