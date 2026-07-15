import ApplicationServices
import XCTest
@testable import Dex

final class RunningApplicationFilterTests: XCTestCase {
    func testFiltersAppsWithVisibleWindowsOnDisplay() {
        let visibleCodex = makeWindow(
            id: "codex-window",
            pid: 101,
            appName: "Codex",
            bundleIdentifier: "com.openai.codex"
        )
        let candidates = [
            RunningApplicationItem(name: "Codex", bundleIdentifier: "com.openai.codex", url: nil, processIdentifier: 101),
            RunningApplicationItem(name: "Claude", bundleIdentifier: "com.anthropic.claude", url: nil, processIdentifier: 202)
        ]

        let hidden = RunningApplicationFilter.hiddenApplications(
            candidates: candidates,
            visibleWindows: [visibleCodex],
            dexBundleIdentifier: "com.neilsanghrajka.Dex"
        )

        XCTAssertEqual(hidden.map(\.name), ["Claude"])
    }

    func testAppAppearsWhenItsLastVisibleWindowIsMinimized() {
        let candidates = [
            RunningApplicationItem(
                name: "Codex",
                bundleIdentifier: "com.openai.codex",
                url: nil,
                processIdentifier: 101
            )
        ]

        let hidden = RunningApplicationFilter.hiddenApplications(
            candidates: candidates,
            visibleWindows: [],
            dexBundleIdentifier: "com.neilsanghrajka.Dex"
        )

        XCTAssertEqual(hidden.map(\.name), ["Codex"])
    }

    func testAppStaysOutOfShelfWhenAnotherWindowRemainsVisible() {
        let remainingCodexWindow = makeWindow(
            id: "remaining-codex-window",
            pid: 101,
            appName: "Codex",
            bundleIdentifier: "com.openai.codex"
        )
        let candidates = [
            RunningApplicationItem(
                name: "Codex",
                bundleIdentifier: "com.openai.codex",
                url: nil,
                processIdentifier: 101
            )
        ]

        let hidden = RunningApplicationFilter.hiddenApplications(
            candidates: candidates,
            visibleWindows: [remainingCodexWindow],
            dexBundleIdentifier: "com.neilsanghrajka.Dex"
        )

        XCTAssertTrue(hidden.isEmpty)
    }

    func testFiltersDexAndDeduplicatesByStableID() {
        let candidates = [
            RunningApplicationItem(name: "Dex", bundleIdentifier: "com.neilsanghrajka.Dex", url: nil, processIdentifier: 1),
            RunningApplicationItem(name: "Dia", bundleIdentifier: "company.thebrowser.dia", url: nil, processIdentifier: 2),
            RunningApplicationItem(name: "Dia", bundleIdentifier: "company.thebrowser.dia", url: nil, processIdentifier: 3)
        ]

        let hidden = RunningApplicationFilter.hiddenApplications(
            candidates: candidates,
            visibleWindows: [],
            dexBundleIdentifier: "com.neilsanghrajka.Dex"
        )

        XCTAssertEqual(hidden.count, 1)
        XCTAssertEqual(hidden.first?.bundleIdentifier, "company.thebrowser.dia")
    }

    private func makeWindow(
        id: String,
        pid: pid_t,
        appName: String,
        bundleIdentifier: String
    ) -> ManagedWindow {
        ManagedWindow(
            id: id,
            pid: pid,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: appName,
            frame: .zero,
            axElement: AXUIElementCreateSystemWide(),
            cgWindowID: nil,
            thumbnail: nil
        )
    }
}

final class BoardFocusAreaTests: XCTestCase {
    func testFocusAreaOrderStartsWithColumns() {
        XCTAssertEqual(
            BoardFocusArea.allCases(for: [.left, .center, .right], includesActiveModes: true),
            [.role(.left), .role(.center), .role(.right), .openWindows, .runningApps, .activeModes]
        )
    }

    func testFocusAreaOrderUsesCustomLayoutRoles() {
        XCTAssertEqual(
            BoardFocusArea.allCases(for: [.left, .topRight, .bottomRight], includesActiveModes: false),
            [.role(.left), .role(.topRight), .role(.bottomRight), .openWindows, .runningApps]
        )
    }
}
