import Foundation

enum WindowFingerprint {
    static func make(for window: ManagedWindow) -> String {
        let frame = window.frame.integral
        return [
            String(window.pid),
            window.bundleIdentifier,
            window.appName,
            window.title,
            String(Int(frame.minX)),
            String(Int(frame.minY)),
            String(Int(frame.width)),
            String(Int(frame.height))
        ].joined(separator: "|")
    }
}
