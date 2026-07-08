import CoreGraphics
import Foundation

struct GridLayout: Equatable {
    var visibleFrame: CGRect
    var gutter: CGFloat
    var kind: BoardLayoutKind

    init(
        visibleFrame: CGRect,
        gutter: CGFloat = 10,
        kind: BoardLayoutKind = .defaultKind
    ) {
        self.visibleFrame = visibleFrame.integral
        self.gutter = gutter
        self.kind = kind
    }

    var roles: [ColumnRole] {
        kind.roles
    }

    func rect(for role: ColumnRole) -> CGRect {
        switch kind {
        case .threeColumn:
            return threeColumnRect(for: role)
        case .wideCenter:
            return wideCenterRect(for: role)
        case .halves:
            return halvesRect(for: role)
        case .twoByTwo:
            return twoByTwoRect(for: role)
        case .leftMainRightStack:
            return leftMainRightStackRect(for: role)
        case .leftStackRightMain:
            return leftStackRightMainRect(for: role)
        case .leftNarrowCenter:
            return asymmetricTwoColumnRect(for: role, narrowOnLeft: true)
        case .centerRightNarrow:
            return asymmetricTwoColumnRect(for: role, narrowOnLeft: false)
        }
    }

    func role(containing point: CGPoint) -> ColumnRole? {
        roles.first { rect(for: $0).contains(point) }
    }

    func nearestRole(to point: CGPoint) -> ColumnRole {
        role(containing: point) ?? roles.min { lhs, rhs in
            distance(from: point, to: rect(for: lhs)) < distance(from: point, to: rect(for: rhs))
        } ?? .center
    }

    func nearestHorizontallyCompatibleRole(
        to point: CGPoint,
        from previousRole: ColumnRole,
        in previousGrid: GridLayout
    ) -> ColumnRole? {
        guard previousGrid.roles.contains(previousRole) else { return nil }
        let candidate = nearestRole(to: point)
        let previousRect = previousGrid.rect(for: previousRole)
        let candidateRect = rect(for: candidate)
        return hasCompatibleVerticalBand(previousRect, candidateRect) ? candidate : nil
    }

    func nextRole(after role: ColumnRole) -> ColumnRole {
        adjacentRole(from: role, direction: .right)
    }

    func previousRole(before role: ColumnRole) -> ColumnRole {
        adjacentRole(from: role, direction: .left)
    }

    func edgeRole(for direction: DisplaySwitchDirection) -> ColumnRole {
        edgeRoles(for: direction).first ?? .center
    }

    func isEdgeRole(_ role: ColumnRole, direction: DisplaySwitchDirection) -> Bool {
        edgeRoles(for: direction).contains(role)
    }

    private func edgeRoles(for direction: DisplaySwitchDirection) -> [ColumnRole] {
        guard !roles.isEmpty else { return [] }
        switch direction {
        case .left:
            let edgeValue = roles.map { rect(for: $0).minX }.min() ?? visibleFrame.minX
            return roles
                .filter { abs(rect(for: $0).minX - edgeValue) < 0.5 }
                .sorted(by: isVisuallyBefore)
        case .right:
            let edgeValue = roles.map { rect(for: $0).maxX }.max() ?? visibleFrame.maxX
            return roles
                .filter { abs(rect(for: $0).maxX - edgeValue) < 0.5 }
                .sorted(by: isVisuallyBefore)
        }
    }

    private func adjacentRole(from role: ColumnRole, direction: DisplaySwitchDirection) -> ColumnRole {
        guard roles.contains(role) else {
            return roles.first ?? .center
        }
        let sourceRect = rect(for: role)
        let sourceIndex = roles.firstIndex(of: role) ?? 0
        let candidates = roles.filter { candidate in
            guard candidate != role else { return false }
            let candidateRect = rect(for: candidate)
            switch direction {
            case .left:
                return candidateRect.midX < sourceRect.midX
            case .right:
                return candidateRect.midX > sourceRect.midX
            }
        }

        return candidates.min { lhs, rhs in
            let lhsScore = directionalScore(from: sourceRect, sourceIndex: sourceIndex, to: lhs, direction: direction)
            let rhsScore = directionalScore(from: sourceRect, sourceIndex: sourceIndex, to: rhs, direction: direction)
            return lhsScore < rhsScore
        } ?? role
    }

    private func directionalScore(
        from sourceRect: CGRect,
        sourceIndex: Int,
        to candidate: ColumnRole,
        direction: DisplaySwitchDirection
    ) -> (CGFloat, CGFloat, Int) {
        let candidateRect = rect(for: candidate)
        let horizontalDistance: CGFloat
        switch direction {
        case .left:
            horizontalDistance = max(0, sourceRect.minX - candidateRect.maxX)
        case .right:
            horizontalDistance = max(0, candidateRect.minX - sourceRect.maxX)
        }
        let verticalDistance = abs(candidateRect.midY - sourceRect.midY)
        let candidateIndex = roles.firstIndex(of: candidate) ?? sourceIndex
        return (horizontalDistance, verticalDistance, candidateIndex)
    }

    private func isVisuallyBefore(_ lhs: ColumnRole, _ rhs: ColumnRole) -> Bool {
        let lhsRect = rect(for: lhs)
        let rhsRect = rect(for: rhs)
        if abs(lhsRect.midY - rhsRect.midY) > 0.5 {
            return lhsRect.midY > rhsRect.midY
        }
        if abs(lhsRect.midX - rhsRect.midX) > 0.5 {
            return lhsRect.midX < rhsRect.midX
        }
        return (roles.firstIndex(of: lhs) ?? 0) < (roles.firstIndex(of: rhs) ?? 0)
    }

    private func threeColumnRect(for role: ColumnRole) -> CGRect {
        let availableWidth = max(0, visibleFrame.width - (gutter * 2))
        let leftWidth = floor(availableWidth * ColumnRole.left.ratio)
        let centerWidth = floor(availableWidth * ColumnRole.center.ratio)
        let rightWidth = max(0, availableWidth - leftWidth - centerWidth)
        return threeColumnRect(for: role, leftWidth: leftWidth, centerWidth: centerWidth, rightWidth: rightWidth)
    }

    private func wideCenterRect(for role: ColumnRole) -> CGRect {
        let availableWidth = max(0, visibleFrame.width - (gutter * 2))
        let sideWidth = floor(availableWidth * 0.18)
        let centerWidth = max(0, availableWidth - sideWidth * 2)
        return threeColumnRect(for: role, leftWidth: sideWidth, centerWidth: centerWidth, rightWidth: sideWidth)
    }

    private func threeColumnRect(
        for role: ColumnRole,
        leftWidth: CGFloat,
        centerWidth: CGFloat,
        rightWidth: CGFloat
    ) -> CGRect {
        switch role {
        case .left:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: leftWidth,
                height: visibleFrame.height
            ).integral
        case .center:
            return CGRect(
                x: visibleFrame.minX + leftWidth + gutter,
                y: visibleFrame.minY,
                width: centerWidth,
                height: visibleFrame.height
            ).integral
        case .right:
            return CGRect(
                x: visibleFrame.maxX - rightWidth,
                y: visibleFrame.minY,
                width: rightWidth,
                height: visibleFrame.height
            ).integral
        case .topLeft, .bottomLeft, .topRight, .bottomRight:
            return CGRect(
                x: visibleFrame.minX + leftWidth + gutter,
                y: visibleFrame.minY,
                width: centerWidth,
                height: visibleFrame.height
            ).integral
        }
    }

    private func halvesRect(for role: ColumnRole) -> CGRect {
        let halfWidth = floor(max(0, visibleFrame.width - gutter) / 2)
        switch role {
        case .left:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height).integral
        case .right:
            return CGRect(
                x: visibleFrame.minX + halfWidth + gutter,
                y: visibleFrame.minY,
                width: max(0, visibleFrame.maxX - (visibleFrame.minX + halfWidth + gutter)),
                height: visibleFrame.height
            ).integral
        case .center, .topLeft, .bottomLeft, .topRight, .bottomRight:
            return visibleFrame.integral
        }
    }

    private func asymmetricTwoColumnRect(for role: ColumnRole, narrowOnLeft: Bool) -> CGRect {
        let defaultThreeColumnWidth = max(0, visibleFrame.width - (gutter * 2))
        let narrowWidth = floor(defaultThreeColumnWidth * ColumnRole.left.ratio)
        let wideWidth = max(0, visibleFrame.width - narrowWidth - gutter)
        let leftWidth = narrowOnLeft ? narrowWidth : wideWidth
        let rightWidth = narrowOnLeft ? wideWidth : narrowWidth
        let rightX = visibleFrame.minX + leftWidth + gutter

        switch role {
        case .left:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: leftWidth,
                height: visibleFrame.height
            ).integral
        case .right:
            return CGRect(
                x: rightX,
                y: visibleFrame.minY,
                width: rightWidth,
                height: visibleFrame.height
            ).integral
        case .center, .topLeft, .bottomLeft, .topRight, .bottomRight:
            return CGRect(
                x: narrowOnLeft ? rightX : visibleFrame.minX,
                y: visibleFrame.minY,
                width: wideWidth,
                height: visibleFrame.height
            ).integral
        }
    }

    private func twoByTwoRect(for role: ColumnRole) -> CGRect {
        let halfWidth = floor(max(0, visibleFrame.width - gutter) / 2)
        let rightX = visibleFrame.minX + halfWidth + gutter
        let rightWidth = max(0, visibleFrame.maxX - rightX)
        let halfHeight = floor(max(0, visibleFrame.height - gutter) / 2)
        let bottomHeight = max(0, visibleFrame.height - halfHeight - gutter)

        switch role {
        case .topLeft:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.maxY - halfHeight,
                width: halfWidth,
                height: halfHeight
            ).integral
        case .topRight:
            return CGRect(
                x: rightX,
                y: visibleFrame.maxY - halfHeight,
                width: rightWidth,
                height: halfHeight
            ).integral
        case .bottomLeft:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: halfWidth,
                height: bottomHeight
            ).integral
        case .bottomRight:
            return CGRect(
                x: rightX,
                y: visibleFrame.minY,
                width: rightWidth,
                height: bottomHeight
            ).integral
        case .left, .center, .right:
            return visibleFrame.integral
        }
    }

    private func leftMainRightStackRect(for role: ColumnRole) -> CGRect {
        let halfWidth = floor(max(0, visibleFrame.width - gutter) / 2)
        let rightX = visibleFrame.minX + halfWidth + gutter
        let rightWidth = max(0, visibleFrame.maxX - rightX)
        let halfHeight = floor(max(0, visibleFrame.height - gutter) / 2)

        switch role {
        case .left:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height).integral
        case .topRight:
            return CGRect(
                x: rightX,
                y: visibleFrame.maxY - halfHeight,
                width: rightWidth,
                height: halfHeight
            ).integral
        case .bottomRight:
            return CGRect(
                x: rightX,
                y: visibleFrame.minY,
                width: rightWidth,
                height: max(0, visibleFrame.height - halfHeight - gutter)
            ).integral
        case .center, .right, .topLeft, .bottomLeft:
            return visibleFrame.integral
        }
    }

    private func leftStackRightMainRect(for role: ColumnRole) -> CGRect {
        let halfWidth = floor(max(0, visibleFrame.width - gutter) / 2)
        let rightX = visibleFrame.minX + halfWidth + gutter
        let rightWidth = max(0, visibleFrame.maxX - rightX)
        let halfHeight = floor(max(0, visibleFrame.height - gutter) / 2)

        switch role {
        case .topLeft:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.maxY - halfHeight,
                width: halfWidth,
                height: halfHeight
            ).integral
        case .bottomLeft:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: halfWidth,
                height: max(0, visibleFrame.height - halfHeight - gutter)
            ).integral
        case .right:
            return CGRect(x: rightX, y: visibleFrame.minY, width: rightWidth, height: visibleFrame.height).integral
        case .left, .center, .topRight, .bottomRight:
            return visibleFrame.integral
        }
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private func hasCompatibleVerticalBand(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance = max(12, max(lhs.height, rhs.height) * 0.04)
        return abs(lhs.midY - rhs.midY) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
}
