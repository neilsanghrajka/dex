import Foundation

struct NewWindowLaunchRule: Codable, Identifiable, Equatable, Hashable {
    var displayName: String
    var bundleIdentifiers: [String]
    var appNames: [String]
    var newWindowMenuItemTitles: [String]

    init(
        displayName: String,
        bundleIdentifiers: [String],
        appNames: [String],
        newWindowMenuItemTitles: [String] = ["New Window"]
    ) {
        self.displayName = displayName
        self.bundleIdentifiers = bundleIdentifiers.filter { !$0.isEmpty }
        self.appNames = appNames.filter { !$0.isEmpty }
        self.newWindowMenuItemTitles = newWindowMenuItemTitles.filter { !$0.isEmpty }
    }

    var id: String {
        if let bundleIdentifier = bundleIdentifiers.first {
            return "bundle:\(bundleIdentifier)"
        }
        return "name:\(displayName.lowercased())"
    }

    var primaryBundleIdentifier: String? {
        bundleIdentifiers.first
    }

    func matches(bundleIdentifiers candidateBundleIdentifiers: [String], appNames candidateAppNames: [String]) -> Bool {
        if !Set(bundleIdentifiers).isDisjoint(with: candidateBundleIdentifiers) {
            return true
        }

        return candidateAppNames.contains { candidateName in
            appNames.contains { appName in
                candidateName.localizedCaseInsensitiveContains(appName) ||
                    appName.localizedCaseInsensitiveContains(candidateName)
            }
        }
    }

    func matches(_ application: InstalledApplication) -> Bool {
        let bundleIdentifiers = application.bundleIdentifier.map { [$0] } ?? []
        return matches(bundleIdentifiers: bundleIdentifiers, appNames: [application.name])
    }

    func matches(_ item: RunningApplicationItem) -> Bool {
        let bundleIdentifiers = item.bundleIdentifier.map { [$0] } ?? []
        return matches(bundleIdentifiers: bundleIdentifiers, appNames: [item.name])
    }

    func matches(_ window: ManagedWindow) -> Bool {
        matches(bundleIdentifiers: [window.bundleIdentifier], appNames: [window.appName])
    }

    func launchSpec(
        label: String,
        bundleIdentifiers candidateBundleIdentifiers: [String],
        appNames candidateAppNames: [String]
    ) -> BoardAppShortcutSpec {
        BoardAppShortcutSpec(
            label: label,
            bundleIdentifiers: Self.unique(candidateBundleIdentifiers + bundleIdentifiers),
            appNames: Self.unique(candidateAppNames + appNames),
            forceNew: true,
            newWindowMenuItemTitles: newWindowMenuItemTitles
        )
    }

    static var defaults: [NewWindowLaunchRule] {
        [
            from(shortcut: .terminal),
            from(shortcut: .claude),
            from(shortcut: .dia),
            from(shortcut: .codex)
        ]
    }

    static func from(shortcut: BoardAppShortcut) -> NewWindowLaunchRule {
        let spec = shortcut.spec
        return NewWindowLaunchRule(
            displayName: spec.label,
            bundleIdentifiers: spec.bundleIdentifiers,
            appNames: spec.appNames,
            newWindowMenuItemTitles: spec.newWindowMenuItemTitles.isEmpty ? ["New Window"] : spec.newWindowMenuItemTitles
        )
    }

    static func from(binding: AppShortcutBinding) -> NewWindowLaunchRule {
        NewWindowLaunchRule(
            displayName: binding.displayName,
            bundleIdentifiers: binding.bundleIdentifiers,
            appNames: binding.appNames,
            newWindowMenuItemTitles: binding.newWindowMenuItemTitles.isEmpty ? ["New Window"] : binding.newWindowMenuItemTitles
        )
    }

    static func from(application: InstalledApplication) -> NewWindowLaunchRule {
        NewWindowLaunchRule(
            displayName: application.name,
            bundleIdentifiers: application.bundleIdentifier.map { [$0] } ?? [],
            appNames: [application.name]
        )
    }

    static func deduplicated(_ rules: [NewWindowLaunchRule]) -> [NewWindowLaunchRule] {
        var seen = Set<String>()
        var result: [NewWindowLaunchRule] = []
        for rule in rules where seen.insert(rule.id).inserted {
            result.append(rule)
        }
        return result
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            !value.isEmpty && seen.insert(value).inserted
        }
    }
}
