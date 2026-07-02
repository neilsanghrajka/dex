import Foundation

enum BoardPaletteMode: Equatable {
    case shortcuts
    case search

    static func mode(for query: String) -> BoardPaletteMode {
        query.isEmpty ? .shortcuts : .search
    }
}

enum BoardPaletteResult: Identifiable, Equatable {
    case manageModes
    case savedMode(SavedMode)
    case application(InstalledApplication)
    case diaTab(DiaTab, parentAppName: String, parentBundleIdentifier: String)

    var id: String {
        switch self {
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
        case .manageModes:
            "Manage Modes"
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
        case .manageModes:
            "Rename or delete saved modes"
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
        case .manageModes:
            return tokenizedMatch(
                query: normalized,
                corpus: "mode modes manage modes settings saved mode rename mode delete mode edit mode"
            )
        case .savedMode(let mode):
            return tokenizedMatch(
                query: normalized,
                corpus: "\(mode.name) mode saved mode \(mode.shortcutLabel) option \(mode.slot)"
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
