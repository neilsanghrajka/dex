import Foundation

struct DiaTab: Identifiable, Equatable, Sendable {
    let id: String
    let parentWindowID: String
    let diaWindowID: String
    let tabID: String
    let title: String
    let url: String
    let isFocused: Bool

    var displayTitle: String {
        title.isEmpty ? "Untitled Dia Tab" : title
    }

    var subtitle: String {
        guard !url.isEmpty else { return "Dia" }
        return url
    }
}

struct DiaWindowCandidate: Equatable, Sendable {
    let id: String
    let title: String
}

struct DiaTabWindowSnapshot: Equatable, Sendable {
    let diaWindowID: String
    let title: String
    let tabs: [DiaRawTab]
}

struct DiaRawTab: Equatable, Sendable {
    let tabID: String
    let title: String
    let url: String
    let isFocused: Bool
}

enum DiaTabMapper {
    static func map(
        snapshots: [DiaTabWindowSnapshot],
        to candidates: [DiaWindowCandidate]
    ) -> [String: [DiaTab]] {
        guard !snapshots.isEmpty, !candidates.isEmpty else { return [:] }

        var remaining = candidates
        var result: [String: [DiaTab]] = [:]

        for snapshot in snapshots {
            guard let index = bestCandidateIndex(for: snapshot, in: remaining) else { continue }
            let candidate = remaining.remove(at: index)
            result[candidate.id] = snapshot.tabs.map { rawTab in
                DiaTab(
                    id: "dia-tab:\(candidate.id):\(rawTab.tabID)",
                    parentWindowID: candidate.id,
                    diaWindowID: snapshot.diaWindowID,
                    tabID: rawTab.tabID,
                    title: rawTab.title,
                    url: rawTab.url,
                    isFocused: rawTab.isFocused
                )
            }
        }

        return result
    }

    private static func bestCandidateIndex(
        for snapshot: DiaTabWindowSnapshot,
        in candidates: [DiaWindowCandidate]
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return 0 }

        let snapshotTitle = normalized(snapshot.title)
        if let exact = candidates.firstIndex(where: { normalized($0.title) == snapshotTitle }) {
            return exact
        }

        let focusedTitle = normalized(snapshot.tabs.first(where: \.isFocused)?.title ?? "")
        if !focusedTitle.isEmpty,
           let exactFocused = candidates.firstIndex(where: { normalized($0.title) == focusedTitle }) {
            return exactFocused
        }

        if let contained = candidates.firstIndex(where: { candidate in
            let title = normalized(candidate.title)
            return !title.isEmpty &&
                (!snapshotTitle.isEmpty && (title.contains(snapshotTitle) || snapshotTitle.contains(title)) ||
                 !focusedTitle.isEmpty && (title.contains(focusedTitle) || focusedTitle.contains(title)))
        }) {
            return contained
        }

        return 0
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
