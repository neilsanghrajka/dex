import CoreGraphics

enum BoardNavigationAxis {
    case horizontal
    case vertical
}

enum BoardNavigationGeometry {
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
}
