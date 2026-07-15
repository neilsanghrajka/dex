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

    func testWUsesNarrowLRightWideFrameAndSecondPressRestores() {
        let first = BoardWindowTransformLogic.transition(
            currentState: nil,
            requestedTransform: .wide,
            currentFrame: normalFrame,
            visibleFrame: visibleFrame
        )
        guard case .apply(let wideFrame, let state) = first else {
            return XCTFail("Expected wide application")
        }
        XCTAssertEqual(
            wideFrame,
            GridLayout(visibleFrame: visibleFrame, kind: .leftNarrowCenter).rect(for: .right)
        )

        XCTAssertEqual(
            BoardWindowTransformLogic.transition(
                currentState: state,
                requestedTransform: .wide,
                currentFrame: wideFrame,
                visibleFrame: visibleFrame
            ),
            .restore(frame: normalFrame)
        )
    }

    func testSwitchingBetweenFAndWKeepsOriginalNormalFrame() {
        guard case .apply(_, let maximizedState) = BoardWindowTransformLogic.transition(
            currentState: nil,
            requestedTransform: .maximized,
            currentFrame: normalFrame,
            visibleFrame: visibleFrame
        ) else {
            return XCTFail("Expected maximize application")
        }
        guard case .apply(let wideFrame, let wideState) = BoardWindowTransformLogic.transition(
            currentState: maximizedState,
            requestedTransform: .wide,
            currentFrame: visibleFrame,
            visibleFrame: visibleFrame
        ) else {
            return XCTFail("Expected wide application")
        }

        XCTAssertEqual(wideState.normalFrame, normalFrame)
        XCTAssertEqual(
            BoardWindowTransformLogic.transition(
                currentState: wideState,
                requestedTransform: .wide,
                currentFrame: wideFrame,
                visibleFrame: visibleFrame
            ),
            .restore(frame: normalFrame)
        )
    }

    func testWideFrameSupportsNegativeOriginExternalDisplay() {
        let external = CGRect(x: -2560, y: -200, width: 2560, height: 1440)
        XCTAssertEqual(
            BoardWindowTransform.wide.targetFrame(visibleFrame: external),
            GridLayout(visibleFrame: external, kind: .leftNarrowCenter).rect(for: .right)
        )
    }
}
