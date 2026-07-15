import Foundation

enum BoardKeyboardNavigationPolicy {
    private static let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]

    /// Board navigation and window moves are semantic, one-step commands. AppKit can
    /// emit repeated key-down events while an arrow is held, which would otherwise
    /// skip cards or move a window across more than one role per press.
    static func shouldProcess(keyCode: UInt16, isRepeat: Bool) -> Bool {
        !isRepeat || !arrowKeyCodes.contains(keyCode)
    }
}
