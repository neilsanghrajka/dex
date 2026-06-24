import XCTest
@testable import Dex

final class DiaTabMapperTests: XCTestCase {
    func testMapsDiaTabsToMatchingManagedWindowTitle() {
        let snapshots = [
            DiaTabWindowSnapshot(
                diaWindowID: "dia-window-1",
                title: "API Keys | Claude Platform",
                tabs: [
                    DiaRawTab(
                        tabID: "tab-1",
                        title: "API Keys | Claude Platform",
                        url: "https://console.anthropic.com/settings/keys",
                        isFocused: true
                    ),
                    DiaRawTab(
                        tabID: "tab-2",
                        title: "WhatsApp",
                        url: "https://web.whatsapp.com/",
                        isFocused: false
                    )
                ]
            )
        ]

        let mapped = DiaTabMapper.map(
            snapshots: snapshots,
            to: [
                DiaWindowCandidate(id: "managed-dia-window", title: "API Keys | Claude Platform")
            ]
        )

        let tabs = mapped["managed-dia-window"]
        XCTAssertEqual(tabs?.count, 2)
        XCTAssertEqual(tabs?.first?.id, "dia-tab:managed-dia-window:tab-1")
        XCTAssertEqual(tabs?.first?.parentWindowID, "managed-dia-window")
        XCTAssertEqual(tabs?.first?.diaWindowID, "dia-window-1")
        XCTAssertEqual(tabs?.first?.displayTitle, "API Keys | Claude Platform")
        XCTAssertEqual(tabs?.first?.isFocused, true)
    }

    func testMapsDiaWindowByFocusedTabTitleWhenWindowTitleDiffers() {
        let snapshots = [
            DiaTabWindowSnapshot(
                diaWindowID: "dia-window-2",
                title: "Dia",
                tabs: [
                    DiaRawTab(
                        tabID: "focused",
                        title: "Neil Sanghrajka",
                        url: "https://x.com/neil",
                        isFocused: true
                    )
                ]
            )
        ]

        let mapped = DiaTabMapper.map(
            snapshots: snapshots,
            to: [
                DiaWindowCandidate(id: "other-dia-window", title: "Cloudflare Dashboard"),
                DiaWindowCandidate(id: "matching-dia-window", title: "Neil Sanghrajka")
            ]
        )

        XCTAssertNil(mapped["other-dia-window"])
        XCTAssertEqual(mapped["matching-dia-window"]?.first?.tabID, "focused")
    }
}
