import XCTest
@testable import Dex

final class WindowCloseActionTests: XCTestCase {
    func testMultiWindowAppWithLastWindowAnywhereQuits() {
        XCTAssertEqual(
            WindowCloseAction.decide(
                allowsMultipleWindows: true,
                crossSpaceWindowCount: 1,
                visibleWindowCount: 1
            ),
            .quitApp
        )
    }

    func testMultiWindowAppWithWindowOnAnotherSpaceClosesWindowOnly() {
        // The reported bug: one visible window here, another on a different desktop.
        XCTAssertEqual(
            WindowCloseAction.decide(
                allowsMultipleWindows: true,
                crossSpaceWindowCount: 2,
                visibleWindowCount: 1
            ),
            .closeWindow
        )
    }

    func testMultiWindowAppWithUnknownCountNeverQuits() {
        XCTAssertEqual(
            WindowCloseAction.decide(
                allowsMultipleWindows: true,
                crossSpaceWindowCount: nil,
                visibleWindowCount: 1
            ),
            .closeWindow
        )
    }

    func testSingleWindowAppWithOneVisibleWindowQuits() {
        XCTAssertEqual(
            WindowCloseAction.decide(
                allowsMultipleWindows: false,
                crossSpaceWindowCount: 2,
                visibleWindowCount: 1
            ),
            .quitApp
        )
    }

    func testSingleWindowAppWithSeveralVisibleWindowsClosesWindowOnly() {
        XCTAssertEqual(
            WindowCloseAction.decide(
                allowsMultipleWindows: false,
                crossSpaceWindowCount: nil,
                visibleWindowCount: 3
            ),
            .closeWindow
        )
    }
}
