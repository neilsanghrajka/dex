import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class ThumbnailService {
    func attachThumbnails(to windows: [ManagedWindow]) async -> [ManagedWindow] {
        if #available(macOS 14.0, *),
           let captured = try? await attachScreenCaptureKitThumbnails(to: windows) {
            return captured
        }
        return attachLegacyThumbnails(to: windows)
    }

    @available(macOS 14.0, *)
    private func attachScreenCaptureKitThumbnails(to windows: [ManagedWindow]) async throws -> [ManagedWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let shareableWindows = content.windows.filter { window in
            guard let app = window.owningApplication else { return false }
            return windows.contains { $0.pid == app.processID }
        }
        let candidates = shareableWindows.compactMap { window -> WindowMatchCandidate? in
            guard let app = window.owningApplication else { return nil }
            return WindowMatchCandidate(
                windowID: window.windowID,
                ownerPID: app.processID,
                title: window.title ?? "",
                bounds: window.frame
            )
        }

        var result: [ManagedWindow] = []
        var usedWindowIDs = Set<CGWindowID>()
        for window in windows {
            var copy = window
            if let match = WindowMatchResolver.bestMatch(
                forPID: window.pid,
                title: window.title,
                frame: window.frame,
                in: candidates,
                usedWindowIDs: &usedWindowIDs
            ),
                let shareableWindow = shareableWindows.first(where: { $0.windowID == match.windowID }) {
                copy.cgWindowID = shareableWindow.windowID
                copy.thumbnail = try? await capture(window: shareableWindow)
            }
            result.append(copy)
        }
        return result
    }

    private func attachLegacyThumbnails(to windows: [ManagedWindow]) -> [ManagedWindow] {
        let infos = cgWindowInfos()
        var usedWindowIDs = Set<CGWindowID>()
        return windows.map { window in
            var copy = window
            if let match = WindowMatchResolver.bestMatch(
                forPID: window.pid,
                title: window.title,
                frame: window.frame,
                in: infos,
                usedWindowIDs: &usedWindowIDs
            ) {
                copy.cgWindowID = match.windowID
                copy.thumbnail = capture(windowID: match.windowID)
            }
            return copy
        }
    }

    @available(macOS 14.0, *)
    private func capture(window: SCWindow) async throws -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let maxWidth: CGFloat = 1_800
        let scale = min(1, maxWidth / max(window.frame.width, 1))
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return NSImage(cgImage: image, size: .zero)
    }

    private func cgWindowInfos() -> [WindowMatchCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return raw.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 0,
                  bounds.height > 0 else {
                return nil
            }

            return WindowMatchCandidate(
                windowID: CGWindowID(number.uint32Value),
                ownerPID: ownerPID.int32Value,
                title: info[kCGWindowName as String] as? String ?? "",
                bounds: bounds
            )
        }
    }

    private func capture(windowID: CGWindowID) -> NSImage? {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return nil
        }

        return NSImage(cgImage: image, size: .zero)
    }
}
