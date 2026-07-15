import CoreGraphics
import Foundation

enum ColumnStackInference {
    static func repairedState(
        existing: ColumnStackState,
        windows: [ManagedWindow],
        previousWindows: [ManagedWindow] = [],
        visibleFrame: CGRect,
        grid: GridLayout,
        allowsInitialInference: Bool = true
    ) -> ColumnStackState {
        guard !windows.isEmpty else { return existing }

        let assignedIDs = Set(ColumnRole.allCases.flatMap { existing.windows(in: $0) })
        guard !assignedIDs.isEmpty else {
            return allowsInitialInference
                ? inferredState(windows: windows, visibleFrame: visibleFrame, grid: grid)
                : existing
        }

        var repaired = remappingStableFingerprints(
            in: existing,
            previousWindows: previousWindows,
            currentWindows: windows
        )
        let visibleWindowIDs = Set(windows.map(\.id))
        let repairedAssignedIDsBeforePrune = Set(ColumnRole.allCases.flatMap { repaired.windows(in: $0) })
        let unresolvedIDsBeforePrune = repairedAssignedIDsBeforePrune.subtracting(visibleWindowIDs)
        if !unresolvedIDsBeforePrune.isEmpty, windows.count < assignedIDs.count {
            return existing
        }

        repaired.prune(keeping: visibleWindowIDs)

        let hasLiveAssignments = ColumnRole.allCases.contains { role in
            !repaired.windows(in: role).isEmpty
        }
        let repairedAssignedIDs = Set(ColumnRole.allCases.flatMap { repaired.windows(in: $0) })
        let unresolvedIDs = repairedAssignedIDs.subtracting(visibleWindowIDs)
        if hasLiveAssignments, unresolvedIDs.isEmpty {
            return repaired
        }

        if windows.count < assignedIDs.count {
            return existing
        }

        return inferredState(windows: windows, visibleFrame: visibleFrame, grid: grid)
    }

    private static func inferredState(
        windows: [ManagedWindow],
        visibleFrame: CGRect,
        grid: GridLayout
    ) -> ColumnStackState {
        var inferred = ColumnStackState()
        for window in windows where visibleFrame.intersects(window.frame) {
            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            inferred.assign(window.id, to: grid.nearestRole(to: center))
        }
        return inferred
    }

    private static func remappingStableFingerprints(
        in existing: ColumnStackState,
        previousWindows: [ManagedWindow],
        currentWindows: [ManagedWindow]
    ) -> ColumnStackState {
        let assignedIDs = Set(ColumnRole.allCases.flatMap { existing.windows(in: $0) })
        guard !previousWindows.isEmpty, !currentWindows.isEmpty else { return existing }

        let previousByID = Dictionary(uniqueKeysWithValues: previousWindows.map { ($0.id, $0) })
        let currentByFingerprint = uniqueWindowsByFingerprint(currentWindows)
        let previousAssignedByFingerprint = uniqueWindowsByFingerprint(
            previousWindows.filter { assignedIDs.contains($0.id) }
        )

        var remapped = existing
        var usedCurrentIDs = Set(existing.windowIDsByColumn.values.flatMap { $0 })
        for oldID in assignedIDs {
            guard !currentWindows.contains(where: { $0.id == oldID }),
                  let previous = previousByID[oldID],
                  previousAssignedByFingerprint[WindowFingerprint.make(for: previous)]?.id == oldID,
                  let current = currentByFingerprint[WindowFingerprint.make(for: previous)],
                  !usedCurrentIDs.contains(current.id) else {
                continue
            }

            for role in ColumnRole.allCases {
                var ids = remapped.windows(in: role)
                guard let index = ids.firstIndex(of: oldID) else { continue }
                ids[index] = current.id
                remapped.windowIDsByColumn[role] = ids
                usedCurrentIDs.insert(current.id)
                break
            }
        }
        return remapped
    }

    private static func uniqueWindowsByFingerprint(_ windows: [ManagedWindow]) -> [String: ManagedWindow] {
        let grouped = Dictionary(grouping: windows, by: WindowFingerprint.make(for:))
        return grouped.compactMapValues { matches in
            matches.count == 1 ? matches[0] : nil
        }
    }
}
