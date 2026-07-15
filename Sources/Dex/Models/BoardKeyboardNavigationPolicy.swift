import Foundation

enum BoardKeyboardNavigationPolicy {
    private static let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]

    static func isDirectionalKey(_ keyCode: UInt16) -> Bool {
        arrowKeyCodes.contains(keyCode)
    }

    /// Board navigation and window moves are semantic, one-step commands. AppKit can
    /// emit repeated key-down events while an arrow is held, which would otherwise
    /// skip cards or move a window across more than one role per press.
    static func shouldProcess(keyCode: UInt16, isRepeat: Bool) -> Bool {
        guard isDirectionalKey(keyCode) else { return true }
        return !isRepeat
    }
}

struct BoardDirectionalKeyPressGate {
    private var pressedKeyCodes: Set<UInt16> = []

    mutating func shouldProcessKeyDown(keyCode: UInt16, isRepeat: Bool) -> Bool {
        guard BoardKeyboardNavigationPolicy.shouldProcess(keyCode: keyCode, isRepeat: isRepeat) else {
            return false
        }
        guard BoardKeyboardNavigationPolicy.isDirectionalKey(keyCode) else { return true }
        return pressedKeyCodes.insert(keyCode).inserted
    }

    mutating func processKeyUp(keyCode: UInt16) {
        pressedKeyCodes.remove(keyCode)
    }

    mutating func reset() {
        pressedKeyCodes.removeAll()
    }
}
