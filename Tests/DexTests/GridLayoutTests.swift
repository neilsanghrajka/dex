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

    func testRoleHitTesting() {
        let layout = GridLayout(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 500), gutter: 10)

        XCTAssertEqual(layout.role(containing: CGPoint(x: 50, y: 100)), .left)
        XCTAssertEqual(layout.role(containing: CGPoint(x: 500, y: 100)), .center)
        XCTAssertEqual(layout.role(containing: CGPoint(x: 950, y: 100)), .right)
    }
}
