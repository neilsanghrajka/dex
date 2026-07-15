import XCTest
@testable import Dex

final class BoardWindowTransformTests: XCTestCase {
    private let normalFrame = CGRect(x: 320, y: 180, width: 900, height: 700)
    private let visibleFrame = CGRect(x: 0, y: 24, width: 1920, height: 1056)

    func testFSecondPressRestoresExactNormalFrame() {
        let first = BoardWindowTransformLogic.transition(
            currentState: nil,
            requestedTransform: .maximized,
            currentFrame: normalFrame,
            visibleFrame: visibleFrame
        )
        guard case .apply(let maximized, let state) = first else {
            return XCTFail("Expected maximize application")
        }
        XCTAssertEqual(maximized, visibleFrame)

        XCTAssertEqual(
            BoardWindowTransformLogic.transition(
                currentState: state,
                requestedTransform: .maximized,
                currentFrame: maximized,
                visibleFrame: visibleFrame
            ),
            .restore(frame: normalFrame)
        )
    }

    func testFImmediatelyAfterWRestoresNarrowLRightFrame() {
        let narrowLRightFrame = GridLayout(
            visibleFrame: visibleFrame,
            kind: .leftNarrowCenter
        ).rect(for: .right)
        let first = BoardWindowTransformLogic.transition(
            currentState: nil,
            requestedTransform: .maximized,
            currentFrame: narrowLRightFrame,
            visibleFrame: visibleFrame
        )
        guard case .apply(let maximized, let state) = first else {
            return XCTFail("Expected maximize application")
        }

        XCTAssertEqual(
            BoardWindowTransformLogic.transition(
                currentState: state,
                requestedTransform: .maximized,
                currentFrame: maximized,
                visibleFrame: visibleFrame
            ),
            .restore(frame: narrowLRightFrame)
        )
    }

}
