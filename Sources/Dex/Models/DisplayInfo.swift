import AppKit
import Foundation

struct DisplayInfo: Identifiable, Hashable {
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect
    let name: String
    let topSafeAreaInset: CGFloat
    let auxiliaryTopLeftArea: CGRect
    let auxiliaryTopRightArea: CGRect

    init(
        id: String,
        frame: CGRect,
        visibleFrame: CGRect,
        name: String,
        topSafeAreaInset: CGFloat = 0,
        auxiliaryTopLeftArea: CGRect = .zero,
        auxiliaryTopRightArea: CGRect = .zero
    ) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.name = name
        self.topSafeAreaInset = topSafeAreaInset
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }

    init(screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.id = number?.stringValue ?? "\(screen.frame.origin.x)-\(screen.frame.origin.y)-\(screen.frame.width)-\(screen.frame.height)"
        self.frame = screen.frame
        self.visibleFrame = screen.visibleFrame
        self.name = screen.localizedName
        self.topSafeAreaInset = screen.safeAreaInsets.top
        self.auxiliaryTopLeftArea = screen.auxiliaryTopLeftArea ?? .zero
        self.auxiliaryTopRightArea = screen.auxiliaryTopRightArea ?? .zero
    }

    var notchGap: CGRect? {
        guard topSafeAreaInset > 0,
              !auxiliaryTopLeftArea.isEmpty,
              !auxiliaryTopRightArea.isEmpty else {
            return nil
        }
        let minX = auxiliaryTopLeftArea.maxX
        let maxX = auxiliaryTopRightArea.minX
        guard maxX > minX else { return nil }
        return CGRect(
            x: minX,
            y: frame.maxY - topSafeAreaInset,
            width: maxX - minX,
            height: topSafeAreaInset
        )
    }

    var grid: GridLayout {
        GridLayout(visibleFrame: visibleFrame)
    }

    func localRect(for rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - frame.minX,
            y: frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    func globalPoint(fromLocal point: CGPoint) -> CGPoint {
        CGPoint(
            x: frame.minX + point.x,
            y: frame.maxY - point.y
        )
    }
}
