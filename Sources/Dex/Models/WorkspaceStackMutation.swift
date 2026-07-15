import Foundation

enum WorkspaceStackMutation {
    static func removingWindow(
        _ windowID: String,
        fromWorkspace workspaceKey: String,
        in stacks: [String: ColumnStackState]
    ) -> [String: ColumnStackState] {
        let layoutPrefix = "\(workspaceKey)\u{1F}layout:"
        var updated = stacks
        for key in Array(updated.keys) where key == workspaceKey || key.hasPrefix(layoutPrefix) {
            var state = updated[key, default: ColumnStackState()]
            state.remove(windowID)
            updated[key] = state
        }
        return updated
    }
}
