import Foundation

enum BoardFocusArea: Equatable {
    case role(ColumnRole)
    case openWindows
    case runningApps
    case activeModes

    static let left = BoardFocusArea.role(.left)
    static let center = BoardFocusArea.role(.center)
    static let right = BoardFocusArea.role(.right)

    static var allCases: [BoardFocusArea] {
        allCases(for: BoardLayoutKind.defaultKind.roles, includesActiveModes: true)
    }

    var role: ColumnRole? {
        switch self {
        case .role(let role): role
        case .openWindows, .runningApps, .activeModes: nil
        }
    }

    static func allCases(for roles: [ColumnRole], includesActiveModes: Bool) -> [BoardFocusArea] {
        roles.map(BoardFocusArea.role) +
            [.openWindows, .runningApps] +
            (includesActiveModes ? [.activeModes] : [])
    }
}
