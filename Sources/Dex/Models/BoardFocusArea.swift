import Foundation

enum BoardFocusArea: CaseIterable {
    case left
    case center
    case right
    case openWindows
    case runningApps
    case activeModes

    init(role: ColumnRole) {
        switch role {
        case .left: self = .left
        case .center: self = .center
        case .right: self = .right
        }
    }

    var role: ColumnRole? {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        case .openWindows, .runningApps, .activeModes: nil
        }
    }
}
