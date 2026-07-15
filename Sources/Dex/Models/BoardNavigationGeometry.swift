import CoreGraphics

enum BoardNavigationAxis {
    case horizontal
    case vertical
}

enum BoardNavigationDirection {
    case left
    case right
    case up
    case down
}

enum BoardNavigationGeometry {
    static func targetIndex(
        from origin: CGPoint,
        candidates: [CGPoint],
        direction: BoardNavigationDirection
    ) -> Int? {
        candidates.indices
            .filter { isCandidate(candidates[$0], in: direction, from: origin) }
            .min { lhs, rhs in
                score(
                    point: candidates[lhs],
                    from: origin,
                    axis: direction.axis
                ) < score(
                    point: candidates[rhs],
                    from: origin,
                    axis: direction.axis
                )
            }
    }

    static func score(
        point: CGPoint,
        from origin: CGPoint,
        axis: BoardNavigationAxis
    ) -> CGFloat {
        let dx = abs(point.x - origin.x)
        let dy = abs(point.y - origin.y)
        let primary = axis == .horizontal ? dx : dy
        let secondary = axis == .horizontal ? dy : dx

        // Favor the next visual row or column while retaining a light alignment
        // preference inside that row or column.
        return primary + secondary * 0.35
    }

    private static func isCandidate(
        _ point: CGPoint,
        in direction: BoardNavigationDirection,
        from origin: CGPoint
    ) -> Bool {
        let threshold: CGFloat = 8
        switch direction {
        case .left:
            return point.x < origin.x - threshold
        case .right:
            return point.x > origin.x + threshold
        case .up:
            return point.y < origin.y - threshold
        case .down:
            return point.y > origin.y + threshold
        }
    }
}

private extension BoardNavigationDirection {
    var axis: BoardNavigationAxis {
        switch self {
        case .left, .right:
            .horizontal
        case .up, .down:
            .vertical
        }
    }
}
