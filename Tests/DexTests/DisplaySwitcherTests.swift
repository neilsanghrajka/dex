import CoreGraphics
import XCTest
@testable import Dex

final class DisplaySwitcherTests: XCTestCase {
    func testDisplayOrderingIsLeftToRight() {
        let displays = [
            makeDisplay(id: "right", x: 1440, y: 0),
            makeDisplay(id: "left", x: 0, y: 0),
            makeDisplay(id: "upper-left", x: 0, y: 900)
        ]

        XCTAssertEqual(DisplaySwitcher.sortedDisplays(displays).map(\.id), ["left", "upper-left", "right"])
    }

    func testSwitchingDisplaysClampsAtEdges() {
        let displays = [
            makeDisplay(id: "one", x: 0),
            makeDisplay(id: "two", x: 1440),
            makeDisplay(id: "three", x: 2880)
        ]

        XCTAssertEqual(DisplaySwitcher.switchedDisplayID(currentID: "one", direction: .left, displays: displays), "one")
        XCTAssertEqual(DisplaySwitcher.switchedDisplayID(currentID: "one", direction: .right, displays: displays), "two")
        XCTAssertEqual(DisplaySwitcher.switchedDisplayID(currentID: "three", direction: .right, displays: displays), "three")
        XCTAssertEqual(DisplaySwitcher.switchedDisplayID(currentID: "missing", direction: .right, displays: displays), "two")
    }

    func testEdgeMoveMapsRightEdgeToNextDisplayLeftColumn() {
        let displays = [
            makeDisplay(id: "one", x: 0),
            makeDisplay(id: "two", x: 1440)
        ]

        let target = DisplaySwitcher.edgeMoveTarget(currentDisplayID: "one", direction: .right, displays: displays)

        XCTAssertEqual(target?.displayID, "two")
        XCTAssertEqual(target?.role, .left)
    }

    func testEdgeMoveChoosesGeometricRightNeighbor() {
        let displays = [
            makeDisplay(id: "current", x: 0, y: 0),
            makeDisplay(id: "above", x: 0, y: 1000),
            makeDisplay(id: "right", x: 1440, y: 0)
        ]

        let target = DisplaySwitcher.edgeMoveTarget(currentDisplayID: "current", direction: .right, displays: displays)

        XCTAssertEqual(target?.displayID, "right")
        XCTAssertEqual(target?.role, .left)
    }

    func testEdgeMoveIgnoresVerticalDisplaysWhenHorizontalNeighborExists() {
        let displays = [
            makeDisplay(id: "left", x: 0, y: 0),
            makeDisplay(id: "stacked", x: 0, y: 900),
            makeDisplay(id: "current", x: 1440, y: 0)
        ]

        let target = DisplaySwitcher.edgeMoveTarget(currentDisplayID: "current", direction: .left, displays: displays)

        XCTAssertEqual(target?.displayID, "left")
        XCTAssertEqual(target?.role, .right)
    }

    func testEdgeMoveMapsLeftEdgeToPreviousDisplayRightColumn() {
        let displays = [
            makeDisplay(id: "one", x: 0),
            makeDisplay(id: "two", x: 1440)
        ]

        let target = DisplaySwitcher.edgeMoveTarget(currentDisplayID: "two", direction: .left, displays: displays)

        XCTAssertEqual(target?.displayID, "one")
        XCTAssertEqual(target?.role, .right)
    }

    func testSingleDisplayEdgeMoveDoesNotSwitch() {
        let displays = [makeDisplay(id: "only", x: 0)]

        XCTAssertNil(DisplaySwitcher.edgeMoveTarget(currentDisplayID: "only", direction: .left, displays: displays))
        XCTAssertNil(DisplaySwitcher.edgeMoveTarget(currentDisplayID: "only", direction: .right, displays: displays))
    }

    func testMacOSSpaceReaderFindsMainDisplaySpaces() {
        let configuration: [String: Any] = [
            "Management Data": [
                "Monitors": [
                    [
                        "Display Identifier": "Main",
                        "Current Space": ["uuid": "space-a"],
                        "Spaces": [
                            ["uuid": "space-a"],
                            ["uuid": "space-b"]
                        ]
                    ]
                ]
            ]
        ]

        let slots = MacOSSpaceReader.mainDisplaySlots(from: configuration)

        XCTAssertEqual(slots.map(\.id), ["space-a", "space-b"])
        XCTAssertEqual(slots.map(\.index), [0, 1])
        XCTAssertEqual(slots.map(\.isCurrent), [true, false])
        XCTAssertEqual(MacOSSpaceReader.currentMainDisplaySpaceID(from: configuration), "space-a")
    }

    private func makeDisplay(id: String, x: CGFloat, y: CGFloat = 0) -> DisplayInfo {
        let frame = CGRect(x: x, y: y, width: 1440, height: 900)
        return DisplayInfo(id: id, frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 24), name: id)
    }
}
