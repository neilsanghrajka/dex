import AppKit
import Foundation

struct DisplayInfo: Identifiable, Hashable {
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect
    let name: String

    init(id: String, frame: CGRect, visibleFrame: CGRect, name: String) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.name = name
    }

    init(screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.id = number?.stringValue ?? "\(screen.frame.origin.x)-\(screen.frame.origin.y)-\(screen.frame.width)-\(screen.frame.height)"
        self.frame = screen.frame
        self.visibleFrame = screen.visibleFrame
        self.name = screen.localizedName
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
