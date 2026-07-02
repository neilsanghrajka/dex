import Foundation

final class LayoutStore {
    private static let legacyBundleIdentifier = "com.neilsanghrajka.Nile"

    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults?
    private let stacksKey = "dex.columnStacks"
    private let legacyStacksKey = "nile.columnStacks"
    private let workspaceStacksKey = "dex.columnStacksByWorkspace"
    private let legacyWorkspaceStacksKey = "nile.columnStacksByWorkspace"
    private let allDisplaysKey = "dex.arrangeAllDisplays"
    private let legacyAllDisplaysKey = "nile.arrangeAllDisplays"
    private let shortcutMappingsKey = "dex.boardShortcutMappings"
    private let legacyShortcutMappingsKey = "nile.boardShortcutMappings"
    private let savedModesKey = "dex.savedModes"

    init(defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let legacyDefaults {
            self.legacyDefaults = legacyDefaults
        } else if defaults === UserDefaults.standard {
            self.legacyDefaults = UserDefaults(suiteName: Self.legacyBundleIdentifier)
        } else {
            self.legacyDefaults = nil
        }
        migrateLegacyValuesIfNeeded()
    }

    var arrangeAllDisplays: Bool {
        get { defaults.bool(forKey: allDisplaysKey) }
        set { defaults.set(newValue, forKey: allDisplaysKey) }
    }

    func loadStacks() -> [String: ColumnStackState] {
        guard let data = defaults.data(forKey: stacksKey) else { return [:] }
        return (try? JSONDecoder().decode([String: ColumnStackState].self, from: data)) ?? [:]
    }

    func saveStacks(_ stacks: [String: ColumnStackState]) {
        guard let data = try? JSONEncoder().encode(stacks) else { return }
        defaults.set(data, forKey: stacksKey)
    }

    func loadWorkspaceStacks() -> [String: ColumnStackState] {
        guard let data = defaults.data(forKey: workspaceStacksKey) else { return [:] }
        return (try? JSONDecoder().decode([String: ColumnStackState].self, from: data)) ?? [:]
    }

    func saveWorkspaceStacks(_ stacks: [String: ColumnStackState]) {
        guard let data = try? JSONEncoder().encode(stacks) else { return }
        defaults.set(data, forKey: workspaceStacksKey)
    }

    func loadShortcutMappings() -> [BoardAppShortcut: String] {
        let defaults = Dictionary(uniqueKeysWithValues: BoardAppShortcut.allCases.map { ($0, $0.defaultKeySequence) })
        guard let data = self.defaults.data(forKey: shortcutMappingsKey),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return defaults
        }

        var result = defaults
        let oldCodexDefault = "d"
        let codexMappingWasOldDefault =
            BoardShortcutValidation.clean(raw[BoardAppShortcut.codex.rawValue] ?? "") == oldCodexDefault

        for shortcut in BoardAppShortcut.allCases {
            if shortcut == .codex, codexMappingWasOldDefault {
                continue
            }

            if let value = raw[shortcut.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !value.isEmpty {
                let cleaned = BoardShortcutValidation.clean(value)
                var candidate = result
                candidate[shortcut] = cleaned
                if BoardShortcutValidation.isValid(cleaned, for: shortcut, in: candidate) {
                    result = candidate
                }
            }
        }
        return result
    }

    func saveShortcutMappings(_ mappings: [BoardAppShortcut: String]) {
        let raw = Dictionary(uniqueKeysWithValues: mappings.map { shortcut, sequence in
            (shortcut.rawValue, sequence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        defaults.set(data, forKey: shortcutMappingsKey)
    }

    func loadSavedModes() -> [SavedMode] {
        guard let data = defaults.data(forKey: savedModesKey),
              let modes = try? JSONDecoder().decode([SavedMode].self, from: data) else {
            return []
        }

        return modes.sorted { lhs, rhs in
            if lhs.slot == rhs.slot {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.slot < rhs.slot
        }
    }

    func saveSavedModes(_ modes: [SavedMode]) {
        let sorted = modes.sorted { lhs, rhs in
            if lhs.slot == rhs.slot {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.slot < rhs.slot
        }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: savedModesKey)
    }

    private func migrateLegacyValuesIfNeeded() {
        migrateLegacyData(from: legacyStacksKey, to: stacksKey)
        migrateLegacyData(from: legacyWorkspaceStacksKey, to: workspaceStacksKey)
        migrateLegacyData(from: legacyShortcutMappingsKey, to: shortcutMappingsKey)

        guard defaults.object(forKey: allDisplaysKey) == nil,
              let raw = legacyObject(forKey: legacyAllDisplaysKey) else {
            return
        }
        defaults.set((raw as? Bool) ?? false, forKey: allDisplaysKey)
    }

    private func migrateLegacyData(from legacyKey: String, to newKey: String) {
        guard defaults.data(forKey: newKey) == nil,
              let data = legacyData(forKey: legacyKey) else {
            return
        }
        defaults.set(data, forKey: newKey)
    }

    private func legacyData(forKey key: String) -> Data? {
        defaults.data(forKey: key) ?? legacyDefaults?.data(forKey: key)
    }

    private func legacyObject(forKey key: String) -> Any? {
        defaults.object(forKey: key) ?? legacyDefaults?.object(forKey: key)
    }
}
