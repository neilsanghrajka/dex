import CoreGraphics
import Foundation

struct GridLayout: Equatable {
    var visibleFrame: CGRect
    var gutter: CGFloat

    init(visibleFrame: CGRect, gutter: CGFloat = 10) {
        self.visibleFrame = visibleFrame.integral
        self.gutter = gutter
    }

    func rect(for role: ColumnRole) -> CGRect {
        let availableWidth = max(0, visibleFrame.width - (gutter * 2))
        let leftWidth = floor(availableWidth * ColumnRole.left.ratio)
        let centerWidth = floor(availableWidth * ColumnRole.center.ratio)
        let rightWidth = max(0, availableWidth - leftWidth - centerWidth)

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
        }
    }

    func role(containing point: CGPoint) -> ColumnRole? {
        ColumnRole.allCases.first { rect(for: $0).contains(point) }
    }

    func nearestRole(to point: CGPoint) -> ColumnRole {
        role(containing: point) ?? ColumnRole.allCases.min { lhs, rhs in
            distance(from: point, to: rect(for: lhs)) < distance(from: point, to: rect(for: rhs))
        } ?? .center
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
