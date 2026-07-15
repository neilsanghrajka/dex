import XCTest
@testable import Dex

final class WorkspaceStackMutationTests: XCTestCase {
    func testRemovingWindowClearsCurrentAndRememberedLayoutsOnlyForActiveWorkspace() {
        let workspace = "display-a\u{1F}space-1"
        let otherWorkspace = "display-a\u{1F}space-2"
        var current = ColumnStackState()
        current.assign("target", to: .center)
        current.assign("keep", to: .left)
        var rememberedLayout = ColumnStackState()
        rememberedLayout.assign("target", to: .right)
        var otherSpace = ColumnStackState()
        otherSpace.assign("target", to: .left)

        let updated = WorkspaceStackMutation.removingWindow(
            "target",
            fromWorkspace: workspace,
            in: [
                workspace: current,
                "\(workspace)\u{1F}layout:wideCenter": rememberedLayout,
                otherWorkspace: otherSpace
            ]
        )

        XCTAssertNil(updated[workspace]?.column(containing: "target"))
        XCTAssertEqual(updated[workspace]?.column(containing: "keep"), .left)
        XCTAssertNil(updated["\(workspace)\u{1F}layout:wideCenter"]?.column(containing: "target"))
        XCTAssertEqual(updated[otherWorkspace]?.column(containing: "target"), .left)
    }
}
