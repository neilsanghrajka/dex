import Foundation

enum BoardLayoutKind: String, CaseIterable, Codable, Equatable {
    case threeColumn
    case wideCenter
    case halves
    case twoByTwo
    case leftMainRightStack
    case leftStackRightMain
    case leftNarrowCenter
    case centerRightNarrow

    static let defaultKind: BoardLayoutKind = .threeColumn
    static let shortcutSlots = Array(1...8)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "fourByFour" {
            self = .twoByTwo
        } else if let kind = BoardLayoutKind(rawValue: rawValue) {
            self = kind
        } else {
            self = .defaultKind
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func shortcutKind(for slot: Int) -> BoardLayoutKind? {
        switch slot {
        case 1: .wideCenter
        case 2: .threeColumn
        case 3: .leftNarrowCenter
        case 4: .centerRightNarrow
        case 5: .halves
        case 6: .twoByTwo
        case 7: .leftMainRightStack
        case 8: .leftStackRightMain
        default: nil
        }
    }

    var roles: [ColumnRole] {
        switch self {
        case .threeColumn:
            [.left, .center, .right]
        case .wideCenter:
            [.left, .center, .right]
        case .halves:
            [.left, .right]
        case .twoByTwo:
            [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .leftMainRightStack:
            [.left, .topRight, .bottomRight]
        case .leftStackRightMain:
            [.topLeft, .bottomLeft, .right]
        case .leftNarrowCenter:
            [.left, .right]
        case .centerRightNarrow:
            [.left, .right]
        }
    }

    var displayName: String {
        switch self {
        case .threeColumn: "Three Columns"
        case .wideCenter: "Wide Center"
        case .halves: "Two Halves"
        case .twoByTwo: "2 x 2"
        case .leftMainRightStack: "Left + Right Stack"
        case .leftStackRightMain: "Left Stack + Right"
        case .leftNarrowCenter: "Left Narrow + Right Wide"
        case .centerRightNarrow: "Left Wide + Right Narrow"
        }
    }
}
