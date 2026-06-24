import Foundation

enum BoardPaletteMode: Equatable {
    case shortcuts
    case search

    static func mode(for query: String) -> BoardPaletteMode {
        query.isEmpty ? .shortcuts : .search
    }
}

enum BoardPaletteResult: Identifiable, Equatable {
    case application(InstalledApplication)
    case diaTab(DiaTab, parentAppName: String, parentBundleIdentifier: String)

    var id: String {
        switch self {
        case .application(let application):
            "app:\(application.id)"
        case .diaTab(let tab, _, _):
            "dia:\(tab.id)"
        }
    }

    var title: String {
        switch self {
        case .application(let application):
            application.name
        case .diaTab(let tab, _, _):
            tab.displayTitle
        }
    }

    var subtitle: String {
        switch self {
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

    func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        switch self {
        case .application(let application):
            return application.name.localizedCaseInsensitiveContains(normalized) ||
                (application.bundleIdentifier?.localizedCaseInsensitiveContains(normalized) ?? false)
        case .diaTab(let tab, let parentAppName, _):
            return tab.title.localizedCaseInsensitiveContains(normalized) ||
                tab.url.localizedCaseInsensitiveContains(normalized) ||
                parentAppName.localizedCaseInsensitiveContains(normalized)
        }
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
