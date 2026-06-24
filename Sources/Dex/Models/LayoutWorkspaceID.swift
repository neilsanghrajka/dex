import Foundation

struct LayoutWorkspaceID: Hashable, Codable, RawRepresentable {
    static let visibleSpaceID = "visible"

    let displayID: String
    let spaceID: String

    init(displayID: String, spaceID: String?) {
        self.displayID = displayID
        self.spaceID = spaceID?.isEmpty == false ? spaceID! : Self.visibleSpaceID
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "\u{1F}", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        self.displayID = String(parts[0])
        self.spaceID = String(parts[1])
    }

    var rawValue: String {
        "\(displayID)\u{1F}\(spaceID)"
    }
}

enum WorkspaceStackResolver {
    static func state(
        displayID: String,
        spaceID: String?,
        workspaceStacks: [String: ColumnStackState],
        legacyStacks: [String: ColumnStackState]
    ) -> ColumnStackState {
        let key = LayoutWorkspaceID(displayID: displayID, spaceID: spaceID).rawValue
        return workspaceStacks[key] ?? legacyStacks[displayID] ?? ColumnStackState()
    }
}
