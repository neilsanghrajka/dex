import Foundation

/// Decides what Q on a board window card does: close just that window, or quit the app.
enum WindowCloseAction: Equatable {
    case closeWindow
    case quitApp

    /// - Parameters:
    ///   - allowsMultipleWindows: whether the app is in the user's "Open New Windows"
    ///     rules (browsers, terminals, …).
    ///   - crossSpaceWindowCount: the app's window count across all spaces, nil when
    ///     it could not be determined.
    ///   - visibleWindowCount: the app's window count on the current space.
    ///
    /// Multi-window apps only quit when this is their last window anywhere; when the
    /// cross-space count is unknown we close just the window — closing too little is
    /// recoverable, quitting the app is not. Other apps keep the visible-count rule.
    static func decide(
        allowsMultipleWindows: Bool,
        crossSpaceWindowCount: Int?,
        visibleWindowCount: Int
    ) -> WindowCloseAction {
        if allowsMultipleWindows {
            guard let crossSpaceWindowCount else { return .closeWindow }
            return crossSpaceWindowCount <= 1 ? .quitApp : .closeWindow
        }
        return visibleWindowCount <= 1 ? .quitApp : .closeWindow
    }
}
