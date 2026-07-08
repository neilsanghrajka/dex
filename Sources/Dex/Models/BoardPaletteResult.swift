import Foundation

enum BoardPaletteMode: Equatable {
    case shortcuts
    case search

    static func mode(for query: String) -> BoardPaletteMode {
        query.isEmpty ? .shortcuts : .search
    }
}

enum BoardPaletteResult: Identifiable, Equatable {
    case layout(BoardLayoutKind, slot: Int)
    case manageModes
    case savedMode(SavedMode)
    case application(InstalledApplication)
    case diaTab(DiaTab, parentAppName: String, parentBundleIdentifier: String)

    var id: String {
        switch self {
        case .layout(_, let slot):
            "layout:\(slot)"
        case .manageModes:
            "action:manage-modes"
        case .savedMode(let mode):
            "mode:\(mode.id)"
        case .application(let application):
            "app:\(application.id)"
        case .diaTab(let tab, _, _):
            "dia:\(tab.id)"
        }
    }

    var title: String {
        switch self {
        case .layout(let kind, let slot):
            "\(slot) \(kind.displayName)"
        case .manageModes:
            "Manage Groups"
        case .savedMode(let mode):
            mode.name
        case .application(let application):
            application.name
        case .diaTab(let tab, _, _):
            tab.displayTitle
        }
    }

    var subtitle: String {
        switch self {
        case .layout:
            "Layout preset for this monitor and Space"
        case .manageModes:
            "Rename or delete saved groups"
        case .savedMode(let mode):
            "\(mode.windows.count) windows"
        case .application(let application):
            application.bundleIdentifier ?? application.url.path
        case .diaTab(let tab, _, _):
            tab.subtitle
        }
    }

    var isDiaTab: Bool {
        if case .diaTab = self { return true }
        return false
    }

    var isLayoutShortcut: Bool {
        if case .layout = self { return true }
        return false
    }

    var isModeManagementAction: Bool {
        if case .manageModes = self { return true }
        return false
    }

    var isSavedMode: Bool {
        if case .savedMode = self { return true }
        return false
    }

    var rightAccessory: String? {
        switch self {
        case .layout(_, let slot):
            "\(slot)"
        case .manageModes:
            nil
        case .savedMode(let mode):
            mode.shortcutLabel
        case .application, .diaTab:
            nil
        }
    }

    func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        switch self {
        case .layout(let kind, let slot):
            return tokenizedMatch(
                query: normalized,
                corpus: "\(slot) layout layouts grid preset presets monitor space columns windows \(kind.displayName) shortcut \(slot)"
            )
        case .manageModes:
            return tokenizedMatch(
                query: normalized,
                corpus: "group groups manage groups settings saved group rename group delete group edit group mode modes manage modes saved mode rename mode delete mode edit mode"
            )
        case .savedMode(let mode):
            return tokenizedMatch(
                query: normalized,
                corpus: "\(mode.name) group saved group mode saved mode \(mode.shortcutLabel) option \(mode.slot)"
            )
        case .application(let application):
            return application.name.localizedCaseInsensitiveContains(normalized) ||
                (application.bundleIdentifier?.localizedCaseInsensitiveContains(normalized) ?? false)
        case .diaTab(let tab, let parentAppName, _):
            return tab.title.localizedCaseInsensitiveContains(normalized) ||
                tab.url.localizedCaseInsensitiveContains(normalized) ||
                parentAppName.localizedCaseInsensitiveContains(normalized)
        }
    }

    private func tokenizedMatch(query: String, corpus: String) -> Bool {
        let normalizedCorpus = corpus.lowercased()
        return query
            .lowercased()
            .split(separator: " ")
            .allSatisfy { normalizedCorpus.contains($0) }
    }
}

enum BoardPaletteSearch {
    static func isShowingShortcutHelp(query: String) -> Bool {
        BoardPaletteMode.mode(for: query) == .shortcuts
    }

    static func filtered(
        _ results: [BoardPaletteResult],
        query: String,
        limit: Int = 24
    ) -> [BoardPaletteResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        return Array(results.filter { $0.matches(normalized) }.prefix(limit))
    }
}
