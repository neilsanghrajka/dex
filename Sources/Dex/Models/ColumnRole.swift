import Foundation

enum ColumnRole: String, CaseIterable, Codable, Identifiable {
    case left
    case center
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        }
    }

    var ratio: Double {
        switch self {
        case .left, .right: 0.25
        case .center: 0.50
        }
    }
}
