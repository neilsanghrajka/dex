import Foundation

enum ColumnRole: String, CaseIterable, Codable, Identifiable {
    case left
    case center
    case right
    case topLeft
    case bottomLeft
    case topRight
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .topLeft: "Top Left"
        case .bottomLeft: "Bottom Left"
        case .topRight: "Top Right"
        case .bottomRight: "Bottom Right"
        }
    }

    var ratio: Double {
        switch self {
        case .left, .right: 0.25
        case .center: 0.50
        case .topLeft, .bottomLeft, .topRight, .bottomRight:
            0.50
        }
    }
}
