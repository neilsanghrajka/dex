import CoreGraphics
import Foundation

enum DisplaySwitchDirection: Equatable {
    case left
    case right
}

struct DisplaySwitcherTarget: Identifiable, Equatable {
    let id: String
    let displayID: String
    let displayName: String
    let spaceID: String
    let index: Int
    let spaceIndex: Int
    let frame: CGRect
    let isActive: Bool
    let assignedCounts: [ColumnRole: Int]
    let unassignedCount: Int

    func count(for role: ColumnRole) -> Int {
        assignedCounts[role, default: 0]
    }
}

enum DisplaySwitcher {
    static func sortedDisplays(_ displays: [DisplayInfo]) -> [DisplayInfo] {
        displays.sorted { lhs, rhs in
            if lhs.frame.minX == rhs.frame.minX {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.frame.minX < rhs.frame.minX
        }
    }

    static func switchedDisplayID(
        currentID: String?,
        direction: DisplaySwitchDirection,
        displays: [DisplayInfo]
    ) -> String? {
        let sorted = sortedDisplays(displays)
        guard !sorted.isEmpty else { return nil }
        let currentIndex = currentID.flatMap { id in
            sorted.firstIndex { $0.id == id }
        } ?? 0

        switch direction {
        case .left:
            return sorted[max(0, currentIndex - 1)].id
        case .right:
            return sorted[min(sorted.count - 1, currentIndex + 1)].id
        }
    }

    static func edgeMoveTarget(
        currentDisplayID: String,
        direction: DisplaySwitchDirection,
        displays: [DisplayInfo]
    ) -> (displayID: String, role: ColumnRole)? {
        guard let targetID = adjacentDisplayID(
            currentDisplayID: currentDisplayID,
            direction: direction,
            displays: displays
        ) else {
            return nil
        }

        switch direction {
        case .left:
            return (targetID, .right)
        case .right:
            return (targetID, .left)
        }
    }

    static func adjacentDisplayID(
        currentDisplayID: String,
        direction: DisplaySwitchDirection,
        displays: [DisplayInfo]
    ) -> String? {
        guard let current = displays.first(where: { $0.id == currentDisplayID }) else {
            return nil
        }

        return displays
            .filter { display in
                guard display.id != current.id else { return false }
                switch direction {
                case .left:
                    return display.frame.midX < current.frame.midX
                case .right:
                    return display.frame.midX > current.frame.midX
                }
            }
            .min { lhs, rhs in
                displayAdjacencyScore(lhs.frame, from: current.frame, direction: direction) <
                    displayAdjacencyScore(rhs.frame, from: current.frame, direction: direction)
            }?
            .id
    }

    private static func displayAdjacencyScore(
        _ candidate: CGRect,
        from current: CGRect,
        direction: DisplaySwitchDirection
    ) -> CGFloat {
        let horizontalDistance: CGFloat
        switch direction {
        case .left:
            horizontalDistance = max(0, current.minX - candidate.maxX)
        case .right:
            horizontalDistance = max(0, candidate.minX - current.maxX)
        }

        let verticalGap: CGFloat
        if candidate.maxY < current.minY {
            verticalGap = current.minY - candidate.maxY
        } else if candidate.minY > current.maxY {
            verticalGap = candidate.minY - current.maxY
        } else {
            verticalGap = 0
        }

        let centerDistance = abs(candidate.midY - current.midY)
        return horizontalDistance + verticalGap * 10_000 + centerDistance * 0.01
    }
}
