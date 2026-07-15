import Foundation

enum BoardAppShortcut: String, CaseIterable, Codable, Identifiable {
    case terminal
    case claude
    case dia
    case perplexity
    case codex

    var id: String { rawValue }

    var spec: BoardAppShortcutSpec {
        switch self {
        case .terminal:
            BoardAppShortcutSpec(
                label: "Terminal",
                bundleIdentifiers: ["com.apple.Terminal"],
                appNames: ["Terminal"],
                forceNew: true,
                newWindowMenuItemTitles: []
            )
        case .claude:
            BoardAppShortcutSpec(
                label: "Claude",
                bundleIdentifiers: ["com.anthropic.claudefordesktop", "com.anthropic.claude"],
                appNames: ["Claude"],
                forceNew: true,
                newWindowMenuItemTitles: ["New Window"]
            )
        case .dia:
            BoardAppShortcutSpec(
                label: "Dia",
                bundleIdentifiers: ["company.thebrowser.dia"],
                appNames: ["Dia"],
                forceNew: true,
                newWindowMenuItemTitles: ["New Window"]
            )
        case .perplexity:
            BoardAppShortcutSpec(
                label: "Perplexity",
                bundleIdentifiers: ["ai.perplexity.mac", "com.perplexity.ai"],
                appNames: ["Perplexity"],
                forceNew: false,
                newWindowMenuItemTitles: []
            )
        case .codex:
            BoardAppShortcutSpec(
                label: "Codex",
                bundleIdentifiers: ["com.openai.codex"],
                appNames: ["Codex"],
                forceNew: true,
                newWindowMenuItemTitles: ["New Window"]
            )
        }
    }

    var defaultKeySequence: String {
        switch self {
        case .terminal: "t"
        case .claude: "c"
        case .dia: "b"
        case .perplexity: "p"
        case .codex: "x"
        }
    }

    /// Stable identifier used for the matching default `AppShortcutBinding`.
    /// Kept fixed so legacy key overrides can be migrated onto the right starter app.
    var defaultBindingID: UUID {
        switch self {
        case .terminal: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        case .claude: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        case .dia: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        case .perplexity: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        case .codex: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        }
    }

    /// The default user-editable binding shipped for this starter app.
    var defaultBinding: AppShortcutBinding {
        let spec = spec
        return AppShortcutBinding(
            id: defaultBindingID,
            displayName: spec.label,
            bundleIdentifiers: spec.bundleIdentifiers,
            appNames: spec.appNames,
            key: defaultKeySequence,
            preferNewWindow: spec.forceNew,
            newWindowMenuItemTitles: spec.newWindowMenuItemTitles
        )
    }
}

enum BoardShortcutValidation {
    static let reservedSequences: Set<String> = ["f", "m", "q", "w"]

    static func clean(_ sequence: String) -> String {
        sequence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    static func isValid(
        _ sequence: String,
        for shortcut: BoardAppShortcut,
        in mappings: [BoardAppShortcut: String]
    ) -> Bool {
        let cleaned = clean(sequence)
        guard cleaned.count == 1, !reservedSequences.contains(cleaned) else {
            return false
        }

        for other in BoardAppShortcut.allCases where other != shortcut {
            let otherSequence = clean(mappings[other] ?? other.defaultKeySequence)
            guard !otherSequence.isEmpty else { continue }
            if cleaned == otherSequence {
                return false
            }
        }

        return true
    }
}

struct BoardAppShortcutSpec {
    let label: String
    let bundleIdentifiers: [String]
    let appNames: [String]
    let forceNew: Bool
    let newWindowMenuItemTitles: [String]

    func matches(_ window: ManagedWindow) -> Bool {
        if bundleIdentifiers.contains(window.bundleIdentifier) {
            return true
        }
        return appNames.contains { appName in
            window.appName.localizedCaseInsensitiveContains(appName)
        }
    }

    func firstNewWindow(in windows: [ManagedWindow], excluding existingIDs: Set<String>) -> ManagedWindow? {
        firstNewWindow(in: windows, excluding: BoardWindowLaunchSnapshot(ids: existingIDs))
    }

    func firstNewWindow(in windows: [ManagedWindow], excluding snapshot: BoardWindowLaunchSnapshot) -> ManagedWindow? {
        windows.first { window in
            matches(window) && !snapshot.contains(window)
        }
    }
}

struct BoardWindowLaunchSnapshot {
    let ids: Set<String>
    let fingerprints: Set<String>

    init(ids: Set<String> = [], windows: [ManagedWindow] = []) {
        self.ids = ids.union(windows.map(\.id))
        self.fingerprints = Set(windows.map(Self.fingerprint(for:)))
    }

    func contains(_ window: ManagedWindow) -> Bool {
        ids.contains(window.id) || fingerprints.contains(Self.fingerprint(for: window))
    }

    static func fingerprint(for window: ManagedWindow) -> String {
        WindowFingerprint.make(for: window)
    }
}
