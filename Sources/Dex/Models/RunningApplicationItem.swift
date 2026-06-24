import AppKit
import Foundation

struct RunningApplicationItem: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let url: URL?
    let processIdentifier: pid_t

    init(
        id: String? = nil,
        name: String,
        bundleIdentifier: String?,
        url: URL?,
        processIdentifier: pid_t
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.url = url
        self.processIdentifier = processIdentifier
        self.id = id ?? bundleIdentifier ?? "pid.\(processIdentifier)"
    }
}

enum RunningApplicationFilter {
    static func hiddenApplications(
        candidates: [RunningApplicationItem],
        visibleWindows: [ManagedWindow],
        dexBundleIdentifier: String?
    ) -> [RunningApplicationItem] {
        let visibleBundleIdentifiers = Set(visibleWindows.map(\.bundleIdentifier))
        let visiblePIDs = Set(visibleWindows.map(\.pid))
        var seen = Set<String>()

        return candidates
            .filter { item in
                if let dexBundleIdentifier,
                   item.bundleIdentifier == dexBundleIdentifier {
                    return false
                }

                if let bundleIdentifier = item.bundleIdentifier,
                   visibleBundleIdentifiers.contains(bundleIdentifier) {
                    return false
                }

                if visiblePIDs.contains(item.processIdentifier) {
                    return false
                }

                return seen.insert(item.id).inserted
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
