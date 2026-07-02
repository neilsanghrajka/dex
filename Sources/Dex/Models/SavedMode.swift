import Foundation

enum ModeLaunchPolicy: String, Codable, Equatable {
    case quitElsewhereAndReopenHere
    case openNewHere
}

struct SavedMode: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var slot: Int
    var windows: [SavedModeWindow]
    var createdAt: Date
    var updatedAt: Date

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
    var windowsByRole: [ColumnRole: [SavedModeWindow]]

    var isEmpty: Bool {
        ColumnRole.allCases.allSatisfy { windowsByRole[$0, default: []].isEmpty }
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
