import Foundation

enum WideBoardPlacement {
    static let layoutKind: BoardLayoutKind = .leftNarrowCenter
    static let role: ColumnRole = .right

    static func placing(windowID: String, in state: ColumnStackState) -> ColumnStackState {
        var updated = state
        updated.assign(windowID, to: role)
        updated.promote(windowID, in: role)
        return updated
    }
}
