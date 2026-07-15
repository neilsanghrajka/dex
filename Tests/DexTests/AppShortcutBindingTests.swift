import XCTest
@testable import Dex

final class AppShortcutBindingTests: XCTestCase {
    // MARK: - Defaults

    func testDefaultBindingsShipTheStarterFiveApps() {
        let defaults = AppShortcutBinding.defaults
        XCTAssertEqual(defaults.count, BoardAppShortcut.allCases.count)
        XCTAssertEqual(defaults.map(\.displayName), ["Terminal", "Claude", "Dia", "Perplexity", "Codex"])
        XCTAssertEqual(defaults.map(\.key), ["t", "c", "b", "p", "x"])
        XCTAssertEqual(
            defaults.first(where: { $0.displayName == "Codex" })?.newWindowMenuItemTitles,
            ["New Window"]
        )
        XCTAssertEqual(defaults.first(where: { $0.displayName == "Terminal" })?.preferNewWindow, true)
        XCTAssertEqual(defaults.first(where: { $0.displayName == "Dia" })?.preferNewWindow, true)
    }

    func testDefaultBindingSpecMatchesLegacyShortcutSpec() {
        for shortcut in BoardAppShortcut.allCases {
            let binding = shortcut.defaultBinding
            XCTAssertEqual(binding.spec.label, shortcut.spec.label)
            XCTAssertEqual(binding.spec.bundleIdentifiers, shortcut.spec.bundleIdentifiers)
            XCTAssertEqual(binding.spec.forceNew, shortcut.spec.forceNew)
            XCTAssertEqual(binding.spec.newWindowMenuItemTitles, shortcut.spec.newWindowMenuItemTitles)
        }
    }

    // MARK: - Validation

    func testRejectsReservedKeys() {
        let bindings = AppShortcutBinding.defaults
        XCTAssertEqual(
            AppShortcutKeyValidation.validate(pressedCharacter: "f", for: bindings[0].id, in: bindings),
            .reserved("F")
        )
        XCTAssertEqual(
            AppShortcutKeyValidation.validate(pressedCharacter: "q", for: bindings[0].id, in: bindings),
            .reserved("Q")
        )
        XCTAssertEqual(
            AppShortcutKeyValidation.validate(pressedCharacter: "m", for: bindings[0].id, in: bindings),
            .reserved("M")
        )
        XCTAssertEqual(
            AppShortcutKeyValidation.validate(pressedCharacter: "w", for: bindings[0].id, in: bindings),
            .reserved("W")
        )
        XCTAssertEqual(
            AppShortcutKeyValidation.validate(pressedCharacter: "/", for: bindings[0].id, in: bindings),
            .reserved("/")
        )
    }

    func testReportsConflictWithHoldingApp() {
        let bindings = AppShortcutBinding.defaults
        // "c" belongs to Claude; try to give it to Terminal.
        let terminal = bindings.first { $0.displayName == "Terminal" }!
        let claude = bindings.first { $0.displayName == "Claude" }!
        let result = AppShortcutKeyValidation.validate(pressedCharacter: "c", for: terminal.id, in: bindings)
        XCTAssertEqual(result, .conflict(bindingID: claude.id, appName: "Claude", key: "c"))
    }

    func testAcceptsFreeKeyAndIgnoresOwnCurrentKey() {
        let bindings = AppShortcutBinding.defaults
        let terminal = bindings.first { $0.displayName == "Terminal" }!
        XCTAssertEqual(
            AppShortcutKeyValidation.validate(pressedCharacter: "n", for: terminal.id, in: bindings),
            .valid(key: "n")
        )
        // Re-assigning a binding to its own current key is not a conflict.
        XCTAssertEqual(
            AppShortcutKeyValidation.validate(pressedCharacter: "t", for: terminal.id, in: bindings),
            .valid(key: "t")
        )
    }

    func testNonAlphanumericPressIsNotAKey() {
        let bindings = AppShortcutBinding.defaults
        XCTAssertEqual(
            AppShortcutKeyValidation.validate(pressedCharacter: "", for: bindings[0].id, in: bindings),
            .notAKey
        )
        XCTAssertEqual(
            AppShortcutKeyValidation.validate(pressedCharacter: "\u{1b}", for: bindings[0].id, in: bindings),
            .notAKey
        )
    }

    // MARK: - Persistence & migration

    func testPersistenceRoundTrip() {
        let suiteName = "DexTests.appShortcutBindings.roundTrip"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        var bindings = AppShortcutBinding.defaults
        bindings.append(
            AppShortcutBinding(
                displayName: "Notes",
                bundleIdentifiers: ["com.apple.Notes"],
                appNames: ["Notes"],
                key: "n",
                preferNewWindow: false
            )
        )
        store.saveAppShortcutBindings(bindings)

        let loaded = store.loadAppShortcutBindings()
        XCTAssertEqual(loaded, bindings)
        XCTAssertEqual(loaded.last?.displayName, "Notes")
        XCTAssertEqual(loaded.last?.key, "n")
    }

    func testStoredMShortcutIsClearedAndPersisted() throws {
        let suiteName = "DexTests.appShortcutBindings.reservedMMigration"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        let bindings = [
            AppShortcutBinding(
                displayName: "Mail",
                bundleIdentifiers: ["com.apple.mail"],
                appNames: ["Mail"],
                key: "m",
                preferNewWindow: false
            ),
            AppShortcutBinding(
                displayName: "Terminal",
                bundleIdentifiers: ["com.apple.Terminal"],
                appNames: ["Terminal"],
                key: "t",
                preferNewWindow: true
            )
        ]
        store.saveAppShortcutBindings(bindings)

        let loaded = store.loadAppShortcutBindings()
        XCTAssertEqual(loaded.map(\.key), ["", "t"])

        let persistedData = try XCTUnwrap(defaults.data(forKey: "dex.appShortcutBindings"))
        let persisted = try JSONDecoder().decode([AppShortcutBinding].self, from: persistedData)
        XCTAssertEqual(persisted.map(\.key), ["", "t"])
    }

    func testStoredFShortcutIsClearedAndPersisted() throws {
        let suiteName = "DexTests.appShortcutBindings.reservedFMigration"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        let bindings = [
            AppShortcutBinding(
                displayName: "Finder",
                bundleIdentifiers: ["com.apple.finder"],
                appNames: ["Finder"],
                key: "f",
                preferNewWindow: false
            )
        ]
        store.saveAppShortcutBindings(bindings)

        let loaded = store.loadAppShortcutBindings()
        XCTAssertEqual(loaded.map(\.key), [""])

        let persistedData = try XCTUnwrap(defaults.data(forKey: "dex.appShortcutBindings"))
        let persisted = try JSONDecoder().decode([AppShortcutBinding].self, from: persistedData)
        XCTAssertEqual(persisted.map(\.key), [""])
    }

    func testMigratesLegacyMappingsOntoDefaultBindings() throws {
        let suiteName = "DexTests.appShortcutBindings.migration"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        // Legacy per-app override: Terminal was rebound to "z".
        var mappings = Dictionary(uniqueKeysWithValues: BoardAppShortcut.allCases.map { ($0, $0.defaultKeySequence) })
        mappings[.terminal] = "z"
        store.saveShortcutMappings(mappings)

        // No new bindings key yet -> load should migrate the override onto the defaults.
        let migrated = store.loadAppShortcutBindings()
        XCTAssertEqual(migrated.first(where: { $0.displayName == "Terminal" })?.key, "z")
        XCTAssertEqual(migrated.first(where: { $0.displayName == "Claude" })?.key, "c")
        XCTAssertEqual(migrated.count, BoardAppShortcut.allCases.count)
    }

    func testLegacyMMappingFallsBackToDefaultBinding() {
        let suiteName = "DexTests.appShortcutBindings.reservedMLegacyMigration"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        var mappings = Dictionary(uniqueKeysWithValues: BoardAppShortcut.allCases.map { ($0, $0.defaultKeySequence) })
        mappings[.terminal] = "m"
        store.saveShortcutMappings(mappings)

        let migrated = store.loadAppShortcutBindings()
        XCTAssertEqual(migrated.first(where: { $0.displayName == "Terminal" })?.key, "t")
    }

    func testStoredBindingsTakePrecedenceOverLegacyMigration() {
        let suiteName = "DexTests.appShortcutBindings.precedence"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        // A legacy override exists...
        var mappings = Dictionary(uniqueKeysWithValues: BoardAppShortcut.allCases.map { ($0, $0.defaultKeySequence) })
        mappings[.terminal] = "z"
        store.saveShortcutMappings(mappings)

        // ...but the user has already saved a new bindings list; that must win.
        let custom = [
            AppShortcutBinding(
                displayName: "Terminal",
                bundleIdentifiers: ["com.apple.Terminal"],
                appNames: ["Terminal"],
                key: "1",
                preferNewWindow: true
            )
        ]
        store.saveAppShortcutBindings(custom)

        XCTAssertEqual(store.loadAppShortcutBindings(), custom)
    }

    func testNewWindowLaunchRulesSeedDefaultsWithDia() {
        let suiteName = "DexTests.newWindowRules.defaults"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        let rules = store.loadNewWindowLaunchRules()

        XCTAssertEqual(rules.map(\.displayName), ["Terminal", "Claude", "Dia", "Codex"])
    }

    func testNewWindowLaunchRulesPersistEmptyList() {
        let suiteName = "DexTests.newWindowRules.empty"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        store.saveNewWindowLaunchRules([])

        XCTAssertEqual(store.loadNewWindowLaunchRules(), [])
    }

    func testNewWindowLaunchRulesPersistenceRoundTrip() {
        let suiteName = "DexTests.newWindowRules.roundTrip"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        let custom = [
            NewWindowLaunchRule(
                displayName: "Notes",
                bundleIdentifiers: ["com.apple.Notes"],
                appNames: ["Notes"]
            )
        ]
        store.saveNewWindowLaunchRules(custom)

        XCTAssertEqual(store.loadNewWindowLaunchRules(), custom)
    }

    func testNewWindowLaunchRulesMigrateSavedShortcutPreferencesAndDia() {
        let suiteName = "DexTests.newWindowRules.migration"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        store.saveAppShortcutBindings([
            AppShortcutBinding(
                id: BoardAppShortcut.dia.defaultBindingID,
                displayName: "Dia",
                bundleIdentifiers: ["company.thebrowser.dia"],
                appNames: ["Dia"],
                key: "b",
                preferNewWindow: false
            ),
            AppShortcutBinding(
                displayName: "Notes",
                bundleIdentifiers: ["com.apple.Notes"],
                appNames: ["Notes"],
                key: "n",
                preferNewWindow: true
            )
        ])

        let rules = store.loadNewWindowLaunchRules()

        XCTAssertTrue(rules.contains { $0.displayName == "Dia" })
        XCTAssertTrue(rules.contains { $0.displayName == "Notes" })
    }
}
