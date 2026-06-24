import CoreGraphics

extension CGRect {
    func intersectionArea(with other: CGRect) -> CGFloat {
        let intersection = intersection(other)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}
