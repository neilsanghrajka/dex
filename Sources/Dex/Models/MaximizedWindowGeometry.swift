import CoreGraphics
import Foundation

enum MaximizedWindowGeometry {
    static func frame(visibleFrame: CGRect) -> CGRect {
        visibleFrame.integral
    }
}
