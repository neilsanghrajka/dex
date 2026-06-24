import AppKit
import SwiftUI

final class OverlayWindowController {
    private var arrangeWindows: [NSWindow] = []
    private var snapWindows: [NSWindow] = []

    func showArrangeBoard(model: AppModel, displays: [DisplayInfo]) {
        closeArrangeBoard()
        NSApp.activate(ignoringOtherApps: true)

        for display in displays {
            let window = makeOverlayWindow(
                display: display,
                level: .floating,
                ignoresMouseEvents: false,
                rootView: ArrangeBoardView(display: display)
                    .environmentObject(model)
            )
            arrangeWindows.append(window)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func showSnapOverlay(model: AppModel, displays: [DisplayInfo]) {
        guard snapWindows.isEmpty else { return }

        for display in displays {
            let window = makeOverlayWindow(
                display: display,
                level: .screenSaver,
                ignoresMouseEvents: true,
                rootView: SnapOverlayView(display: display)
                    .environmentObject(model)
            )
            snapWindows.append(window)
        }
    }

    func closeArrangeBoard() {
        close(windows: &arrangeWindows)
    }

    func refocusArrangeBoard() {
        guard !arrangeWindows.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        for window in arrangeWindows {
            window.orderFrontRegardless()
        }
        arrangeWindows.last?.makeKeyAndOrderFront(nil)
    }

    func closeSnapOverlay() {
        close(windows: &snapWindows)
    }

    func closeAll() {
        closeArrangeBoard()
        closeSnapOverlay()
    }

    private func makeOverlayWindow<Content: View>(
        display: DisplayInfo,
        level: NSWindow.Level,
        ignoresMouseEvents: Bool,
        rootView: Content
    ) -> NSWindow {
        let window = OverlayWindow(
            contentRect: display.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.setFrame(display.frame, display: true)
        window.level = level
        window.ignoresMouseEvents = ignoresMouseEvents
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return window
    }

    private func close(windows: inout [NSWindow]) {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
