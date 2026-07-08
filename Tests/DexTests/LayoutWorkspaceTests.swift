import XCTest
@testable import Dex

final class LayoutWorkspaceTests: XCTestCase {
    func testWorkspaceIDsSeparateSpacesForSameDisplay() {
        let spaceA = LayoutWorkspaceID(displayID: "display-1", spaceID: "space-a")
        let spaceB = LayoutWorkspaceID(displayID: "display-1", spaceID: "space-b")

        XCTAssertNotEqual(spaceA.rawValue, spaceB.rawValue)
        XCTAssertEqual(LayoutWorkspaceID(rawValue: spaceA.rawValue), spaceA)
    }

    func testWorkspaceResolverFallsBackToLegacyDisplayStack() {
        var legacy = ColumnStackState()
        legacy.assign("legacy-window", to: .center)

        let resolved = WorkspaceStackResolver.state(
            displayID: "display-1",
            spaceID: "space-a",
            workspaceStacks: [:],
            legacyStacks: ["display-1": legacy]
        )

        XCTAssertEqual(resolved.windows(in: .center), ["legacy-window"])
    }

    func testWorkspaceResolverPrefersWorkspaceStackOverLegacyStack() {
        var legacy = ColumnStackState()
        legacy.assign("legacy-window", to: .center)
        var workspace = ColumnStackState()
        workspace.assign("workspace-window", to: .right)
        let key = LayoutWorkspaceID(displayID: "display-1", spaceID: "space-a").rawValue

        let resolved = WorkspaceStackResolver.state(
            displayID: "display-1",
            spaceID: "space-a",
            workspaceStacks: [key: workspace],
            legacyStacks: ["display-1": legacy]
        )

        XCTAssertEqual(resolved.windows(in: .right), ["workspace-window"])
        XCTAssertEqual(resolved.windows(in: .center), [])
    }

    func testLayoutStorePersistsWorkspaceStacksSeparatelyFromLegacyStacks() {
        let suiteName = "DexTests.workspaceStacks"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        var legacy = ColumnStackState()
        legacy.assign("legacy", to: .left)
        var workspace = ColumnStackState()
        workspace.assign("workspace", to: .right)
        let key = LayoutWorkspaceID(displayID: "display-1", spaceID: "space-a").rawValue

        store.saveStacks(["display-1": legacy])
        store.saveWorkspaceStacks([key: workspace])

        XCTAssertEqual(store.loadStacks()["display-1"]?.windows(in: .left), ["legacy"])
        XCTAssertEqual(store.loadWorkspaceStacks()[key]?.windows(in: .right), ["workspace"])
    }

    func testLayoutStorePersistsNonDefaultLayoutKindPerWorkspace() {
        let suiteName = "DexTests.displayLayoutKinds"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)
        let workspaceKey = LayoutWorkspaceID(displayID: "display-1", spaceID: "space-a").rawValue

        store.saveDisplayLayoutKinds([
            workspaceKey: .twoByTwo,
            "display-2": .halves,
            LayoutWorkspaceID(displayID: "display-3", spaceID: "space-b").rawValue: .defaultKind
        ])

        let loaded = store.loadDisplayLayoutKinds()
        XCTAssertEqual(loaded[workspaceKey], .twoByTwo)
        XCTAssertNil(loaded["display-2"])
        XCTAssertNil(loaded[LayoutWorkspaceID(displayID: "display-3", spaceID: "space-b").rawValue])
    }

    func testLayoutStoreMigratesLegacyDexSettings() throws {
        let suiteName = "DexTests.legacyMigration.current"
        let legacySuiteName = "DexTests.legacyMigration.legacy"
        let defaults = UserDefaults(suiteName: suiteName)!
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)

        var legacyStack = ColumnStackState()
        legacyStack.assign("legacy-window", to: .left)
        let workspaceKey = LayoutWorkspaceID(displayID: "display-1", spaceID: "space-a").rawValue
        var legacyWorkspaceStack = ColumnStackState()
        legacyWorkspaceStack.assign("legacy-workspace-window", to: .right)

        legacyDefaults.set(
            try JSONEncoder().encode(["display-1": legacyStack]),
            forKey: "nile.columnStacks"
        )
        legacyDefaults.set(
            try JSONEncoder().encode([workspaceKey: legacyWorkspaceStack]),
            forKey: "nile.columnStacksByWorkspace"
        )
        legacyDefaults.set(true, forKey: "nile.arrangeAllDisplays")
        legacyDefaults.set(
            try JSONEncoder().encode([BoardAppShortcut.terminal.rawValue: "z"]),
            forKey: "nile.boardShortcutMappings"
        )

        let store = LayoutStore(defaults: defaults, legacyDefaults: legacyDefaults)

        XCTAssertEqual(store.loadStacks()["display-1"]?.windows(in: .left), ["legacy-window"])
        XCTAssertEqual(store.loadWorkspaceStacks()[workspaceKey]?.windows(in: .right), ["legacy-workspace-window"])
        XCTAssertTrue(store.arrangeAllDisplays)
        XCTAssertEqual(store.loadShortcutMappings()[.terminal], "z")
        XCTAssertNotNil(defaults.data(forKey: "dex.columnStacks"))
        XCTAssertNotNil(defaults.data(forKey: "dex.columnStacksByWorkspace"))
        XCTAssertNotNil(defaults.data(forKey: "dex.boardShortcutMappings"))
    }

    func testLayoutStorePersistsSavedModesBySlot() {
        let suiteName = "DexTests.savedModes"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        let later = sampleMode(name: "Catchup", slot: 2)
        let earlier = sampleMode(name: "Meeting", slot: 1)

        store.saveSavedModes([later, earlier])

        XCTAssertEqual(store.loadSavedModes().map(\.name), ["Meeting", "Catchup"])
        XCTAssertEqual(store.loadSavedModes().first?.windows.first?.role, .center)
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
            createdAt: Date(timeIntervalSince1970: Double(slot)),
            updatedAt: Date(timeIntervalSince1970: Double(slot))
        )
    }
}
