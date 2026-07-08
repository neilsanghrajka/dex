import Foundation

struct ColumnStackState: Codable, Equatable {
    var windowIDsByColumn: [ColumnRole: [String]] = [:]
    var activeIndexByColumn: [ColumnRole: Int] = [:]

    func windows(in column: ColumnRole) -> [String] {
        windowIDsByColumn[column, default: []]
    }

    func activeWindowID(in column: ColumnRole) -> String? {
        let ids = windows(in: column)
        guard !ids.isEmpty else { return nil }
        let index = min(max(activeIndexByColumn[column, default: 0], 0), ids.count - 1)
        return ids[index]
    }

    func windowsStartingAtActive(in column: ColumnRole) -> [String] {
        let ids = windows(in: column)
        guard ids.count > 1 else { return ids }
        let index = min(max(activeIndexByColumn[column, default: 0], 0), ids.count - 1)
        guard index > 0 else { return ids }
        return Array(ids[index...]) + Array(ids[..<index])
    }

    mutating func assign(_ windowID: String, to column: ColumnRole) {
        for key in ColumnRole.allCases {
            windowIDsByColumn[key, default: []].removeAll { $0 == windowID }
        }
        windowIDsByColumn[column, default: []].append(windowID)
        activeIndexByColumn[column] = max(0, windows(in: column).count - 1)
    }

    func column(containing windowID: String) -> ColumnRole? {
        ColumnRole.allCases.first { windows(in: $0).contains(windowID) }
    }

    mutating func promote(_ windowID: String, in column: ColumnRole) {
        var ids = windows(in: column)
        guard let index = ids.firstIndex(of: windowID) else { return }
        ids.remove(at: index)
        ids.insert(windowID, at: 0)
        windowIDsByColumn[column] = ids
        activeIndexByColumn[column] = 0
    }

    mutating func remove(_ windowID: String) {
        for column in ColumnRole.allCases {
            windowIDsByColumn[column, default: []].removeAll { $0 == windowID }
            let count = windows(in: column).count
            activeIndexByColumn[column] = count == 0 ? 0 : min(activeIndexByColumn[column, default: 0], count - 1)
        }
    }

    mutating func cycle(_ column: ColumnRole, direction: CycleDirection) -> String? {
        let ids = windows(in: column)
        guard !ids.isEmpty else { return nil }
        let current = activeIndexByColumn[column, default: 0]
        let next: Int
        switch direction {
        case .forward:
            next = (current + 1) % ids.count
        case .backward:
            next = (current - 1 + ids.count) % ids.count
        }
        activeIndexByColumn[column] = next
        return ids[next]
    }

    mutating func prune(keeping validIDs: Set<String>) {
        for column in ColumnRole.allCases {
            let pruned = windows(in: column).filter { validIDs.contains($0) }
            windowIDsByColumn[column] = pruned
            if pruned.isEmpty {
                activeIndexByColumn[column] = 0
            } else {
                activeIndexByColumn[column] = min(activeIndexByColumn[column, default: 0], pruned.count - 1)
            }
        }
    }

    func orderedWindowIDs(preferredRoles: [ColumnRole]) -> [String] {
        var seen = Set<String>()
        let orderedRoles = preferredRoles + ColumnRole.allCases.filter { !preferredRoles.contains($0) }
        return orderedRoles.flatMap { role in
            windowsStartingAtActive(in: role).filter { seen.insert($0).inserted }
        }
    }

    func filtered(to roles: [ColumnRole]) -> ColumnStackState {
        var next = ColumnStackState()
        var seen = Set<String>()
        for role in roles {
            let ids = windowsStartingAtActive(in: role).filter { seen.insert($0).inserted }
            next.windowIDsByColumn[role] = ids
            next.activeIndexByColumn[role] = 0
        }
        return next
    }

    func reflowing(from previousRoles: [ColumnRole], to nextRoles: [ColumnRole]) -> ColumnStackState {
        reflowing(orderedWindowIDs(preferredRoles: previousRoles), into: nextRoles)
    }

    func reflowing(_ windowIDs: [String], into roles: [ColumnRole]) -> ColumnStackState {
        guard let overflowRole = roles.last else { return ColumnStackState() }
        var next = ColumnStackState()
        var idsByRole: [ColumnRole: [String]] = [:]
        for (index, windowID) in windowIDs.enumerated() {
            let role = index < roles.count ? roles[index] : overflowRole
            idsByRole[role, default: []].append(windowID)
        }
        for role in roles {
            let ids = idsByRole[role, default: []]
            next.windowIDsByColumn[role] = ids
            next.activeIndexByColumn[role] = 0
        }
        return next
    }
}
