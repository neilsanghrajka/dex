import AppKit
import Foundation

enum WindowThumbnailCache {
    static func make(from windows: [ManagedWindow]) -> [String: NSImage] {
        var cache: [String: NSImage] = [:]
        for window in windows {
            guard let thumbnail = window.thumbnail else { continue }
            cache[window.id] = thumbnail
        }
        return cache
    }
}
