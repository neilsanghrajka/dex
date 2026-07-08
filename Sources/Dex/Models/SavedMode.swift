import Foundation

enum ModeLaunchPolicy: String, Codable, Equatable {
    case quitElsewhereAndReopenHere
    case openNewHere
}

struct SavedMode: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var slot: Int
    var layoutKind: BoardLayoutKind
    var windows: [SavedModeWindow]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        name: String,
        slot: Int,
        layoutKind: BoardLayoutKind = .defaultKind,
        windows: [SavedModeWindow],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.slot = slot
        self.layoutKind = layoutKind
        self.windows = windows
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slot
        case layoutKind
        case windows
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slot = try container.decode(Int.self, forKey: .slot)
        layoutKind = try container.decodeIfPresent(BoardLayoutKind.self, forKey: .layoutKind) ?? .defaultKind
        windows = try container.decode([SavedModeWindow].self, forKey: .windows)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var shortcutLabel: String {
        "Option+\(slot)"
    }
}

struct SavedModeWindow: Codable, Identifiable, Equatable {
    var id: UUID
    var role: ColumnRole
    var order: Int
    var bundleIdentifier: String
    var appName: String
    var titleHint: String

    var displayTitle: String {
        titleHint.isEmpty ? appName : titleHint
    }
}

struct ActiveModeInstance: Identifiable, Equatable {
    var id: UUID
    var modeID: UUID
    var modeName: String
    var slot: Int
    var displayID: String
    var spaceID: String
    var windowBindings: [ActiveModeWindowBinding]
    var startedAt: Date

    var shortcutLabel: String {
        "Option+\(slot)"
    }
}

struct ActiveModeWindowBinding: Identifiable, Equatable {
    var id: String { windowID }
    var windowID: String
    var role: ColumnRole
    var appName: String
    var bundleIdentifier: String
}

struct ModeCapturePreview: Equatable {
    var layoutKind: BoardLayoutKind = .defaultKind
    var windowsByRole: [ColumnRole: [SavedModeWindow]]

    var isEmpty: Bool {
        layoutKind.roles.allSatisfy { windowsByRole[$0, default: []].isEmpty }
    }
}

enum ModeLaunchConfirmation: Equatable {
    case idle
    case confirming(mode: SavedMode, policy: ModeLaunchPolicy, armedAt: Date)
}

enum ModeSlotAssignment {
    static func firstAvailableSlot(in modes: [SavedMode], maximum: Int = 9) -> Int {
        let used = Set(modes.map(\.slot))
        for slot in 1...maximum where !used.contains(slot) {
            return slot
        }
        return min(maximum, (modes.map(\.slot).max() ?? 0) + 1)
    }
}
