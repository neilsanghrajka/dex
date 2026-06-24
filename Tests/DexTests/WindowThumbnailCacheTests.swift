import AppKit
import ApplicationServices
import XCTest
@testable import Dex

final class WindowThumbnailCacheTests: XCTestCase {
    func testDuplicateWindowIDsDoNotTrap() {
        let first = makeWindow(id: "duplicate", thumbnail: NSImage(size: NSSize(width: 8, height: 8)))
        let second = makeWindow(id: "duplicate", thumbnail: NSImage(size: NSSize(width: 16, height: 16)))

        let cache = WindowThumbnailCache.make(from: [first, second])

        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache["duplicate"]?.size, NSSize(width: 16, height: 16))
    }

    func testWindowsWithoutThumbnailsAreIgnored() {
        let cache = WindowThumbnailCache.make(from: [
            makeWindow(id: "missing", thumbnail: nil),
            makeWindow(id: "present", thumbnail: NSImage(size: NSSize(width: 8, height: 8)))
        ])

        XCTAssertNil(cache["missing"])
        XCTAssertNotNil(cache["present"])
    }

    private func makeWindow(id: String, thumbnail: NSImage?) -> ManagedWindow {
        ManagedWindow(
            id: id,
            pid: 1,
            appName: "Codex",
            bundleIdentifier: "com.openai.codex",
            title: "Codex",
            frame: .zero,
            axElement: AXUIElementCreateSystemWide(),
            cgWindowID: nil,
            thumbnail: thumbnail
        )
    }
}
