import CoreGraphics

enum BoardNavigationDirection {
    case left
    case right
    case up
    case down
}

enum BoardNavigationGeometry {
    private static let directionThreshold: CGFloat = 8
    private static let alignmentTolerance: CGFloat = 12

    static func targetIndex(
        from origin: CGRect,
        candidates: [CGRect],
        direction: BoardNavigationDirection
    ) -> Int? {
        candidates.indices
            .filter { isCandidate(candidates[$0], in: direction, from: origin) }
            .min { lhs, rhs in
                isPreferred(
                    candidates[lhs],
                    index: lhs,
                    over: candidates[rhs],
                    index: rhs,
                    from: origin,
                    direction: direction
                )
            }
    }

    private static func isCandidate(
        _ candidate: CGRect,
        in direction: BoardNavigationDirection,
        from origin: CGRect
    ) -> Bool {
        switch direction {
        case .left:
            candidate.midX < origin.midX - directionThreshold
        case .right:
            candidate.midX > origin.midX + directionThreshold
        case .up:
            candidate.midY < origin.midY - directionThreshold
        case .down:
            candidate.midY > origin.midY + directionThreshold
        }
    }

    private static func isPreferred(
        _ lhs: CGRect,
        index lhsIndex: Int,
        over rhs: CGRect,
        index rhsIndex: Int,
        from origin: CGRect,
        direction: BoardNavigationDirection
    ) -> Bool {
        let lhsRank = rank(of: lhs, from: origin, direction: direction)
        let rhsRank = rank(of: rhs, from: origin, direction: direction)

        if lhsRank.tier != rhsRank.tier {
            return lhsRank.tier < rhsRank.tier
        }
        if !approximatelyEqual(lhsRank.first, rhsRank.first) {
            return lhsRank.first < rhsRank.first
        }
        if !approximatelyEqual(lhsRank.second, rhsRank.second) {
            return lhsRank.second < rhsRank.second
        }
        if !approximatelyEqual(lhsRank.third, rhsRank.third) {
            return lhsRank.third < rhsRank.third
        }
        return lhsIndex < rhsIndex
    }

    private static func rank(
        of candidate: CGRect,
        from origin: CGRect,
        direction: BoardNavigationDirection
    ) -> (tier: Int, first: CGFloat, second: CGFloat, third: CGFloat) {
        let crossGap = perpendicularGap(between: origin, and: candidate, direction: direction)
        let forwardGap = directionalEdgeGap(from: origin, to: candidate, direction: direction)
        let centerDistance = hypot(candidate.midX - origin.midX, candidate.midY - origin.midY)

        if crossGap == 0 {
            return (0, forwardGap, centerDistance, 0)
        }
        if crossGap <= alignmentTolerance {
            return (1, forwardGap, crossGap, centerDistance)
        }

        let forwardCenterDistance = max(
            direction.isHorizontal
                ? abs(candidate.midX - origin.midX)
                : abs(candidate.midY - origin.midY),
            1
        )
        let angularDeviation = crossGap / forwardCenterDistance
        return (2, angularDeviation, centerDistance, forwardGap)
    }

    private static func directionalEdgeGap(
        from origin: CGRect,
        to candidate: CGRect,
        direction: BoardNavigationDirection
    ) -> CGFloat {
        switch direction {
        case .left:
            max(0, origin.minX - candidate.maxX)
        case .right:
            max(0, candidate.minX - origin.maxX)
        case .up:
            max(0, origin.minY - candidate.maxY)
        case .down:
            max(0, candidate.minY - origin.maxY)
        }
    }

    private static func perpendicularGap(
        between origin: CGRect,
        and candidate: CGRect,
        direction: BoardNavigationDirection
    ) -> CGFloat {
        direction.isHorizontal
            ? intervalGap(origin.minY...origin.maxY, candidate.minY...candidate.maxY)
            : intervalGap(origin.minX...origin.maxX, candidate.minX...candidate.maxX)
    }

    private static func intervalGap(
        _ lhs: ClosedRange<CGFloat>,
        _ rhs: ClosedRange<CGFloat>
    ) -> CGFloat {
        if lhs.overlaps(rhs) {
            return 0
        }
        return rhs.lowerBound > lhs.upperBound
            ? rhs.lowerBound - lhs.upperBound
            : lhs.lowerBound - rhs.upperBound
    }

    private static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }
}

private extension BoardNavigationDirection {
    var isHorizontal: Bool {
        switch self {
        case .left, .right:
            true
        case .up, .down:
            false
        }
    }
}
