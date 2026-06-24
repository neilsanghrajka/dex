import AppKit
import ApplicationServices
import Foundation

struct ManagedWindow: Identifiable {
    let id: String
    let pid: pid_t
    let appName: String
    let bundleIdentifier: String
    let title: String
    let frame: CGRect
    let axElement: AXUIElement
    var cgWindowID: CGWindowID?
    var thumbnail: NSImage?

    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    var subtitle: String {
        title.isEmpty ? bundleIdentifier : appName
    }
}
