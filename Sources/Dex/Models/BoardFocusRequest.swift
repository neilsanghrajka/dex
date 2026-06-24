import Foundation

enum BoardFocusRequest: Equatable {
    case assigned(ColumnRole, String)
}
