import XCTest
@testable import Dex

final class BoardPaletteSearchTests: XCTestCase {
    func testEmptyQueryShowsShortcutHelpAndNoSearchResults() {
        let results: [BoardPaletteResult] = [
            .application(sampleApplication(name: "Claude", bundleIdentifier: "com.anthropic.claudefordesktop"))
        ]

        XCTAssertTrue(BoardPaletteSearch.isShowingShortcutHelp(query: ""))
        XCTAssertEqual(BoardPaletteSearch.filtered(results, query: ""), [])
    }

    func testFiltersInstalledApplicationsByNameAndBundle() {
        let claude = BoardPaletteResult.application(
            sampleApplication(name: "Claude", bundleIdentifier: "com.anthropic.claudefordesktop")
        )
        let dia = BoardPaletteResult.application(
            sampleApplication(name: "Dia", bundleIdentifier: "company.thebrowser.dia")
        )

        XCTAssertEqual(BoardPaletteSearch.filtered([claude, dia], query: "anthropic"), [claude])
        XCTAssertEqual(BoardPaletteSearch.filtered([claude, dia], query: "dia"), [dia])
    }

    func testFiltersDiaTabsByTitleAndURL() {
        let apiTab = BoardPaletteResult.diaTab(
            sampleDiaTab(title: "API Keys | Claude Platform", url: "https://console.anthropic.com/settings/keys"),
            parentAppName: "Dia",
            parentBundleIdentifier: "company.thebrowser.dia"
        )
        let jobsTab = BoardPaletteResult.diaTab(
            sampleDiaTab(title: "Levels.fyi Salaries", url: "https://levels.fyi/jobs"),
            parentAppName: "Dia",
            parentBundleIdentifier: "company.thebrowser.dia"
        )

        XCTAssertEqual(BoardPaletteSearch.filtered([apiTab, jobsTab], query: "keys"), [apiTab])
        XCTAssertEqual(BoardPaletteSearch.filtered([apiTab, jobsTab], query: "levels.fyi"), [jobsTab])
    }

    func testDiaTabResultKeepsDistinctIdentityFromApplicationResult() {
        let tab = BoardPaletteResult.diaTab(
            sampleDiaTab(title: "Dia", url: "https://example.com"),
            parentAppName: "Dia",
            parentBundleIdentifier: "company.thebrowser.dia"
        )
        let application = BoardPaletteResult.application(
            sampleApplication(name: "Dia", bundleIdentifier: "company.thebrowser.dia")
        )

        XCTAssertTrue(tab.isDiaTab)
        XCTAssertFalse(application.isDiaTab)
        XCTAssertNotEqual(tab.id, application.id)
    }

    func testSavedModeMatchesByModeNamePhrase() {
        let mode = sampleMode(name: "Meeting", slot: 1)
        let result = BoardPaletteResult.savedMode(mode)

        XCTAssertEqual(BoardPaletteSearch.filtered([result], query: "m"), [result])
        XCTAssertEqual(BoardPaletteSearch.filtered([result], query: "meeting mode"), [result])
    }

    func testSavedModeExposesShortcutAccessory() {
        let mode = sampleMode(name: "Catchup", slot: 2)
        let result = BoardPaletteResult.savedMode(mode)

        XCTAssertEqual(result.title, "Catchup")
        XCTAssertEqual(result.rightAccessory, "Option+2")
        XCTAssertTrue(result.isSavedMode)
        XCTAssertFalse(result.isDiaTab)
    }

    private func sampleApplication(
        name: String,
        bundleIdentifier: String?
    ) -> InstalledApplication {
        InstalledApplication(
            id: bundleIdentifier ?? name,
            name: name,
            bundleIdentifier: bundleIdentifier,
            url: URL(fileURLWithPath: "/Applications/\(name).app")
        )
    }

    private func sampleDiaTab(title: String, url: String) -> DiaTab {
        DiaTab(
            id: "dia-tab:window-1:\(title)",
            parentWindowID: "window-1",
            diaWindowID: "dia-window-1",
            tabID: title,
            title: title,
            url: url,
            isFocused: false
        )
    }

    private func sampleMode(name: String, slot: Int) -> SavedMode {
        SavedMode(
            id: UUID(),
            name: name,
            slot: slot,
            windows: [
                SavedModeWindow(
                    id: UUID(),
                    role: .center,
                    order: 0,
                    bundleIdentifier: "com.example.App",
                    appName: "Example",
                    titleHint: "Example"
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
