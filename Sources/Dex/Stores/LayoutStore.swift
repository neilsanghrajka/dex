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
    private let appShortcutBindingsKey = "dex.appShortcutBindings"
    private let newWindowLaunchRulesKey = "dex.newWindowLaunchRules"
    private let savedModesKey = "dex.savedModes"
    private let displayLayoutKindsKey = "dex.displayLayoutKinds"
    private let hasCompletedOnboardingKey = "dex.hasCompletedOnboarding"
    private let showsBoardLegendKey = "dex.showsBoardLegend"
    private let boardLegendSessionsRemainingKey = "dex.boardLegendSessionsRemaining"

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

    /// Set once the user completes OR exits onboarding. Once true, onboarding never
    /// auto-shows again across launches/updates.
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: hasCompletedOnboardingKey) }
        set { defaults.set(newValue, forKey: hasCompletedOnboardingKey) }
    }

    /// Whether the post-tour reinforcement legend is allowed to show. Defaults on.
    var showsBoardLegend: Bool {
        get {
            defaults.object(forKey: showsBoardLegendKey) == nil
                ? true
                : defaults.bool(forKey: showsBoardLegendKey)
        }
        set { defaults.set(newValue, forKey: showsBoardLegendKey) }
    }

    /// Remaining board sessions that should show the reinforcement legend.
    var boardLegendSessionsRemaining: Int {
        get { defaults.integer(forKey: boardLegendSessionsRemainingKey) }
        set { defaults.set(newValue, forKey: boardLegendSessionsRemainingKey) }
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

    func loadDisplayLayoutKinds() -> [String: BoardLayoutKind] {
        guard let data = defaults.data(forKey: displayLayoutKindsKey),
              let raw = try? JSONDecoder().decode([String: BoardLayoutKind].self, from: data) else {
            return [:]
        }
        return raw.filter { key, _ in LayoutWorkspaceID(rawValue: key) != nil }
    }

    func saveDisplayLayoutKinds(_ layoutKinds: [String: BoardLayoutKind]) {
        let nonDefault = layoutKinds.filter { key, kind in
            kind != .defaultKind && LayoutWorkspaceID(rawValue: key) != nil
        }
        guard let data = try? JSONEncoder().encode(nonDefault) else { return }
        defaults.set(data, forKey: displayLayoutKindsKey)
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

    func loadAppShortcutBindings() -> [AppShortcutBinding] {
        if let data = defaults.data(forKey: appShortcutBindingsKey),
           let decoded = try? JSONDecoder().decode([AppShortcutBinding].self, from: data) {
            let migrated = decoded.map { binding in
                var binding = binding
                if BoardShortcutValidation.clean(binding.key) == "m" {
                    binding.key = ""
                }
                return binding
            }
            if migrated != decoded {
                saveAppShortcutBindings(migrated)
            }
            return migrated
        }

        // First run on this build: start from the default set and migrate any legacy
        // per-app key overrides ('dex.boardShortcutMappings', itself migrated from Nile)
        // so existing users keep their custom keys.
        let legacyMappings = loadShortcutMappings()
        return BoardAppShortcut.allCases.map { shortcut in
            var binding = shortcut.defaultBinding
            if let key = legacyMappings[shortcut] {
                let cleaned = BoardShortcutValidation.clean(key)
                if !cleaned.isEmpty {
                    binding.key = cleaned
                }
            }
            return binding
        }
    }

    func saveAppShortcutBindings(_ bindings: [AppShortcutBinding]) {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        defaults.set(data, forKey: appShortcutBindingsKey)
    }

    func loadNewWindowLaunchRules() -> [NewWindowLaunchRule] {
        if let data = defaults.data(forKey: newWindowLaunchRulesKey),
           let decoded = try? JSONDecoder().decode([NewWindowLaunchRule].self, from: data) {
            return decoded
        }

        var seeded = NewWindowLaunchRule.defaults
        if let data = defaults.data(forKey: appShortcutBindingsKey),
           let bindings = try? JSONDecoder().decode([AppShortcutBinding].self, from: data) {
            seeded.append(contentsOf: bindings.filter(\.preferNewWindow).map(NewWindowLaunchRule.from(binding:)))
        }
        return NewWindowLaunchRule.deduplicated(seeded)
    }

    func saveNewWindowLaunchRules(_ rules: [NewWindowLaunchRule]) {
        guard let data = try? JSONEncoder().encode(NewWindowLaunchRule.deduplicated(rules)) else { return }
        defaults.set(data, forKey: newWindowLaunchRulesKey)
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
        migrateLegacyAllDisplaysIfNeeded()
        seedOnboardingCompleteForExistingInstallsIfNeeded()
    }

    private func migrateLegacyAllDisplaysIfNeeded() {
        guard defaults.object(forKey: allDisplaysKey) == nil,
              let raw = legacyObject(forKey: legacyAllDisplaysKey) else {
            return
        }
        defaults.set((raw as? Bool) ?? false, forKey: allDisplaysKey)
    }

    /// Treat a prior install (existing saved data) as already-onboarded so that shipping
    /// the onboarding feature does not force the entire installed base back through the
    /// first-run wizard. Only applies when the flag has never been written.
    private func seedOnboardingCompleteForExistingInstallsIfNeeded() {
        guard defaults.object(forKey: hasCompletedOnboardingKey) == nil else { return }

        let hasPriorData =
            defaults.data(forKey: stacksKey) != nil ||
            defaults.data(forKey: workspaceStacksKey) != nil ||
            defaults.data(forKey: shortcutMappingsKey) != nil ||
            defaults.data(forKey: savedModesKey) != nil ||
            defaults.data(forKey: displayLayoutKindsKey) != nil ||
            defaults.data(forKey: appShortcutBindingsKey) != nil ||
            defaults.data(forKey: newWindowLaunchRulesKey) != nil ||
            defaults.object(forKey: allDisplaysKey) != nil ||
            legacyData(forKey: legacyStacksKey) != nil ||
            legacyData(forKey: legacyWorkspaceStacksKey) != nil ||
            legacyData(forKey: legacyShortcutMappingsKey) != nil

        if hasPriorData {
            defaults.set(true, forKey: hasCompletedOnboardingKey)
        }
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
