import XCTest
@testable import Dex

final class MaximizedWindowGeometryTests: XCTestCase {
    func testUsesEntireVisibleDisplayWithoutEnteringMacOSFullScreen() {
        let visibleFrame = CGRect(x: 0, y: 24, width: 1728, height: 1080)

        XCTAssertEqual(
            MaximizedWindowGeometry.frame(visibleFrame: visibleFrame),
            visibleFrame
        )
    }

    func testPreservesNegativeOriginExternalDisplayGeometry() {
        let visibleFrame = CGRect(x: -1920, y: -120, width: 1920, height: 1080)

        XCTAssertEqual(
            MaximizedWindowGeometry.frame(visibleFrame: visibleFrame),
            visibleFrame
        )
    }

    func testRoundsScaledDisplayGeometryToWholePoints() {
        XCTAssertEqual(
            MaximizedWindowGeometry.frame(
                visibleFrame: CGRect(x: 100.4, y: 50.4, width: 1439.2, height: 899.2)
            ),
            CGRect(x: 100, y: 50, width: 1440, height: 900)
        )
    }
}
