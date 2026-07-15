import CoreGraphics

enum BoardDropTargetResolver {
    static func role(
        at point: CGPoint,
        roleRects: [ColumnRole: CGRect],
        roleOrder: [ColumnRole]
    ) -> ColumnRole? {
        if let containingRole = roleOrder.first(where: { roleRects[$0]?.contains(point) == true }) {
            return containingRole
        }
        return roleOrder
            .compactMap { role -> (ColumnRole, CGRect)? in
                guard let rect = roleRects[role] else { return nil }
                return (role, rect)
            }
            .min { lhs, rhs in
                distance(from: point, to: lhs.1) < distance(from: point, to: rhs.1)
            }?.0
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
