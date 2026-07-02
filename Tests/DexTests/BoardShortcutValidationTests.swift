import ApplicationServices
import XCTest
@testable import Dex

final class BoardShortcutValidationTests: XCTestCase {
    func testForceNewShortcutPolicy() {
        XCTAssertTrue(BoardAppShortcut.terminal.spec.forceNew)
        XCTAssertTrue(BoardAppShortcut.claude.spec.forceNew)
        XCTAssertTrue(BoardAppShortcut.dia.spec.forceNew)
        XCTAssertTrue(BoardAppShortcut.codex.spec.forceNew)
        XCTAssertFalse(BoardAppShortcut.perplexity.spec.forceNew)
    }

    func testElectronForceNewShortcutsUseNewWindowMenuFallback() {
        XCTAssertEqual(BoardAppShortcut.codex.spec.newWindowMenuItemTitles, ["New Window"])
        XCTAssertEqual(BoardAppShortcut.claude.spec.newWindowMenuItemTitles, ["New Window"])
        XCTAssertEqual(BoardAppShortcut.dia.spec.newWindowMenuItemTitles, ["New Window"])
        XCTAssertEqual(BoardAppShortcut.terminal.spec.newWindowMenuItemTitles, [])
    }

    func testFirstNewWindowPrefersNewMatchingWindow() {
        let spec = BoardAppShortcut.codex.spec
        let oldCodex = makeWindow(id: "old", appName: "Codex", bundleIdentifier: "com.openai.codex")
        let unrelated = makeWindow(id: "other", appName: "Dia", bundleIdentifier: "company.thebrowser.dia")
        let newCodex = makeWindow(id: "new", appName: "Codex", bundleIdentifier: "com.openai.codex")

        XCTAssertEqual(
            spec.firstNewWindow(in: [oldCodex, unrelated, newCodex], excluding: ["old"])?.id,
            "new"
        )
    }

    func testFirstNewWindowIgnoresOldWindowWhenRefreshedWithDifferentID() {
        let spec = BoardAppShortcut.codex.spec
        let oldCodex = makeWindow(
            id: "old",
            appName: "Codex",
            bundleIdentifier: "com.openai.codex",
            frame: CGRect(x: 10, y: 20, width: 300, height: 400)
        )
        let sameOldCodexAfterRefresh = makeWindow(
            id: "old-different-cg-id",
            appName: "Codex",
            bundleIdentifier: "com.openai.codex",
            frame: CGRect(x: 10, y: 20, width: 300, height: 400)
        )
        let newCodex = makeWindow(
            id: "new",
            appName: "Codex",
            bundleIdentifier: "com.openai.codex",
            frame: CGRect(x: 40, y: 80, width: 900, height: 700)
        )
        let snapshot = BoardWindowLaunchSnapshot(windows: [oldCodex])

        XCTAssertEqual(
            spec.firstNewWindow(in: [sameOldCodexAfterRefresh, newCodex], excluding: snapshot)?.id,
            "new"
        )
    }

    func testCleansShortcutInput() {
        XCTAssertEqual(BoardShortcutValidation.clean(" C + D "), "cd")
        XCTAssertEqual(BoardShortcutValidation.clean("/"), "")
    }

    func testRejectsReservedBoardKeys() {
        XCTAssertFalse(BoardShortcutValidation.isValid("q", for: .terminal, in: defaultMappings(updating: .terminal, to: "q")))
        XCTAssertTrue(BoardShortcutValidation.isValid("x", for: .codex, in: defaultMappings(updating: .codex, to: "x")))
    }

    func testRejectsMultiKeyAndDuplicateShortcuts() {
        XCTAssertFalse(BoardShortcutValidation.isValid("cc", for: .terminal, in: defaultMappings(updating: .terminal, to: "cc")))
        XCTAssertFalse(BoardShortcutValidation.isValid("c", for: .terminal, in: defaultMappings(updating: .terminal, to: "c")))
        XCTAssertFalse(BoardShortcutValidation.isValid("cd", for: .codex, in: defaultMappings(updating: .codex, to: "cd")))
    }

    func testAcceptsDistinctShortcuts() {
        XCTAssertTrue(BoardShortcutValidation.isValid("n", for: .terminal, in: defaultMappings(updating: .terminal, to: "n")))
        XCTAssertTrue(BoardShortcutValidation.isValid("z", for: .terminal, in: defaultMappings(updating: .terminal, to: "z")))
    }

    func testDefaultCodexShortcutIsX() {
        XCTAssertEqual(BoardAppShortcut.codex.defaultKeySequence, "x")
    }

    func testOldDefaultCodexMappingMigratesFromDToX() {
        let defaults = UserDefaults(suiteName: "DexTests.shortcutMigration.oldDefault")!
        defaults.removePersistentDomain(forName: "DexTests.shortcutMigration.oldDefault")
        let store = LayoutStore(defaults: defaults)

        var mappings = defaultMappings(updating: .codex, to: "d")
        mappings[.codex] = "d"
        store.saveShortcutMappings(mappings)

        XCTAssertEqual(store.loadShortcutMappings()[.codex], "x")
    }

    func testCustomCodexMappingIsPreserved() {
        let defaults = UserDefaults(suiteName: "DexTests.shortcutMigration.custom")!
        defaults.removePersistentDomain(forName: "DexTests.shortcutMigration.custom")
        let store = LayoutStore(defaults: defaults)

        var mappings = defaultMappings(updating: .codex, to: "z")
        mappings[.codex] = "z"
        store.saveShortcutMappings(mappings)

        XCTAssertEqual(store.loadShortcutMappings()[.codex], "z")
    }

    private func defaultMappings(updating shortcut: BoardAppShortcut, to value: String) -> [BoardAppShortcut: String] {
        var mappings = Dictionary(uniqueKeysWithValues: BoardAppShortcut.allCases.map { ($0, $0.defaultKeySequence) })
        mappings[shortcut] = value
        return mappings
    }

    private func makeWindow(
        id: String,
        appName: String,
        bundleIdentifier: String,
        frame: CGRect = .zero
    ) -> ManagedWindow {
        ManagedWindow(
            id: id,
            pid: 1,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: appName,
            frame: frame,
            axElement: AXUIElementCreateSystemWide(),
            cgWindowID: nil,
            thumbnail: nil
        )
    }
}
