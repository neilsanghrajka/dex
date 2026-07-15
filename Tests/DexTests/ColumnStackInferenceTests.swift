import ApplicationServices
import CoreGraphics
import XCTest
@testable import Dex

final class ColumnStackInferenceTests: XCTestCase {
    func testExplicitlyEmptyWorkspaceDoesNotReinferUnassignedWindows() {
        let window = makeWindow(id: "expanded", frame: CGRect(x: 0, y: 0, width: 1200, height: 700))
        let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)

        let repaired = ColumnStackInference.repairedState(
            existing: ColumnStackState(),
            windows: [window],
            visibleFrame: visibleFrame,
            grid: GridLayout(visibleFrame: visibleFrame),
            allowsInitialInference: false
        )

        XCTAssertTrue(repaired.windowIDsByColumn.values.allSatisfy(\.isEmpty))
    }

    func testInfersColumnsFromWindowPositionsWhenNoLiveAssignmentsExist() {
        let grid = GridLayout(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), gutter: 10)
        let left = makeWindow(id: "left", frame: CGRect(x: 20, y: 100, width: 180, height: 500))
        let center = makeWindow(id: "center", frame: CGRect(x: 360, y: 100, width: 300, height: 500))
        let right = makeWindow(id: "right", frame: CGRect(x: 820, y: 100, width: 160, height: 500))

        let repaired = ColumnStackInference.repairedState(
            existing: ColumnStackState(),
            windows: [left, center, right],
            visibleFrame: grid.visibleFrame,
            grid: grid
        )

        XCTAssertEqual(repaired.windows(in: .left), ["left"])
        XCTAssertEqual(repaired.windows(in: .center), ["center"])
        XCTAssertEqual(repaired.windows(in: .right), ["right"])
    }

    func testStaleAssignmentsAreReplacedWithPositionBasedAssignments() {
        let grid = GridLayout(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), gutter: 10)
        var stale = ColumnStackState()
        stale.assign("old-window-id", to: .center)
        let current = makeWindow(id: "current", frame: CGRect(x: 820, y: 100, width: 160, height: 500))

        let repaired = ColumnStackInference.repairedState(
            existing: stale,
            windows: [current],
            visibleFrame: grid.visibleFrame,
            grid: grid
        )

        XCTAssertEqual(repaired.windows(in: .left), [])
        XCTAssertEqual(repaired.windows(in: .center), [])
        XCTAssertEqual(repaired.windows(in: .right), ["current"])
    }

    func testExistingLiveAssignmentsAreNotOverwrittenByUnassignedWindows() {
        let grid = GridLayout(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), gutter: 10)
        var existing = ColumnStackState()
        existing.assign("center", to: .center)
        let left = makeWindow(id: "left", frame: CGRect(x: 20, y: 100, width: 180, height: 500))
        let center = makeWindow(id: "center", frame: CGRect(x: 360, y: 100, width: 300, height: 500))

        let repaired = ColumnStackInference.repairedState(
            existing: existing,
            windows: [left, center],
            visibleFrame: grid.visibleFrame,
            grid: grid
        )

        XCTAssertEqual(repaired.windows(in: .left), [])
        XCTAssertEqual(repaired.windows(in: .center), ["center"])
        XCTAssertEqual(repaired.windows(in: .right), [])
    }

    func testWindowsOutsideVisibleFrameAreIgnoredDuringInference() {
        let grid = GridLayout(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), gutter: 10)
        let outside = makeWindow(id: "outside", frame: CGRect(x: 1400, y: 100, width: 200, height: 500))

        let repaired = ColumnStackInference.repairedState(
            existing: ColumnStackState(),
            windows: [outside],
            visibleFrame: grid.visibleFrame,
            grid: grid
        )

        XCTAssertEqual(repaired.windows(in: .left), [])
        XCTAssertEqual(repaired.windows(in: .center), [])
        XCTAssertEqual(repaired.windows(in: .right), [])
    }

    func testEmptyRefreshDoesNotOverwriteExistingAssignments() {
        let grid = GridLayout(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), gutter: 10)
        var existing = ColumnStackState()
        existing.assign("center", to: .center)

        let repaired = ColumnStackInference.repairedState(
            existing: existing,
            windows: [],
            visibleFrame: grid.visibleFrame,
            grid: grid
        )

        XCTAssertEqual(repaired, existing)
    }

    func testPartialRefreshDoesNotOverwriteExistingAssignments() {
        let grid = GridLayout(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), gutter: 10)
        var existing = ColumnStackState()
        existing.assign("left", to: .left)
        existing.assign("center", to: .center)
        let left = makeWindow(id: "left", frame: CGRect(x: 20, y: 100, width: 180, height: 500))

        let repaired = ColumnStackInference.repairedState(
            existing: existing,
            windows: [left],
            visibleFrame: grid.visibleFrame,
            grid: grid
        )

        XCTAssertEqual(repaired, existing)
    }

    func testOneToOneFingerprintRemapPreservesAssignment() {
        let grid = GridLayout(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), gutter: 10)
        var existing = ColumnStackState()
        existing.assign("old-id", to: .center)
        let oldWindow = makeWindow(
            id: "old-id",
            appName: "Codex",
            bundleIdentifier: "com.openai.codex",
            title: "Project",
            frame: CGRect(x: 360, y: 100, width: 300, height: 500)
        )
        let refreshedWindow = makeWindow(
            id: "new-id",
            appName: "Codex",
            bundleIdentifier: "com.openai.codex",
            title: "Project",
            frame: CGRect(x: 360, y: 100, width: 300, height: 500)
        )

        let repaired = ColumnStackInference.repairedState(
            existing: existing,
            windows: [refreshedWindow],
            previousWindows: [oldWindow],
            visibleFrame: grid.visibleFrame,
            grid: grid
        )

        XCTAssertEqual(repaired.windows(in: .center), ["new-id"])
    }

    private func makeWindow(
        id: String,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        title: String? = nil,
        frame: CGRect
    ) -> ManagedWindow {
        ManagedWindow(
            id: id,
            pid: 1,
            appName: appName ?? id,
            bundleIdentifier: bundleIdentifier ?? "test.\(id)",
            title: title ?? id,
            frame: frame,
            axElement: AXUIElementCreateSystemWide(),
            cgWindowID: nil,
            thumbnail: nil
        )
    }
}
