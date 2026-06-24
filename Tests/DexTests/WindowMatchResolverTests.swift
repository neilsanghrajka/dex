import CoreGraphics
import XCTest
@testable import Dex

final class WindowMatchResolverTests: XCTestCase {
    func testDuplicateTitlesAreMatchedOneToOneByNearestFrame() {
        let pid: pid_t = 42
        let candidates = [
            WindowMatchCandidate(
                windowID: 100,
                ownerPID: pid,
                title: "Codex",
                bounds: CGRect(x: 0, y: 0, width: 400, height: 600)
            ),
            WindowMatchCandidate(
                windowID: 200,
                ownerPID: pid,
                title: "Codex",
                bounds: CGRect(x: 500, y: 0, width: 400, height: 600)
            )
        ]
        var used = Set<CGWindowID>()

        let first = WindowMatchResolver.bestMatch(
            forPID: pid,
            title: "Codex",
            frame: CGRect(x: 10, y: 0, width: 400, height: 600),
            in: candidates,
            usedWindowIDs: &used
        )
        let second = WindowMatchResolver.bestMatch(
            forPID: pid,
            title: "Codex",
            frame: CGRect(x: 510, y: 0, width: 400, height: 600),
            in: candidates,
            usedWindowIDs: &used
        )

        XCTAssertEqual(first?.windowID, 100)
        XCTAssertEqual(second?.windowID, 200)
        XCTAssertEqual(used, [100, 200])
    }

    func testUsedWindowIDsAreNotReturnedAgain() {
        let pid: pid_t = 42
        let candidates = [
            WindowMatchCandidate(
                windowID: 100,
                ownerPID: pid,
                title: "Codex",
                bounds: CGRect(x: 0, y: 0, width: 400, height: 600)
            )
        ]
        var used: Set<CGWindowID> = [100]

        let match = WindowMatchResolver.bestMatch(
            forPID: pid,
            title: "Codex",
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            in: candidates,
            usedWindowIDs: &used
        )

        XCTAssertNil(match)
    }
}
