import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class OverlayWindowController {
    private var arrangeWindows: [NSWindow] = []
    private var snapWindows: [NSWindow] = []
    private var screenParametersObserver: NSObjectProtocol?
    private var menuBarVisibilityBeforeCompactBoard: Bool?
    private var pendingCompactDismissals = 0

    func showArrangeBoard(
        model: AppModel,
        displays: [DisplayInfo],
        presentationMode: BoardPresentationMode
    ) {
        closeArrangeBoard()
        NSApp.activate(ignoringOtherApps: true)

        if presentationMode == .compactIsland, !displays.isEmpty {
            hideMenuBarForCompactBoard()
        }

        for display in displays {
            if presentationMode == .compactIsland {
                let panel = makeCompactPanel(model: model, display: display)
                arrangeWindows.append(panel)
                presentCompactPanel(panel, model: model, display: display)
                continue
            }

            let window = makeOverlayWindow(
                display: display,
                level: .floating,
                ignoresMouseEvents: false,
                rootView: ArrangeBoardView(display: display, presentation: .fullScreen)
                    .environmentObject(model)
            )
            arrangeWindows.append(window)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        if presentationMode == .compactIsland, !displays.isEmpty {
            startScreenParametersObserver(model: model)
        } else {
            restoreMenuBarIfCompactBoardIsClosed()
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
        stopScreenParametersObserver()
        let windows = arrangeWindows
        arrangeWindows.removeAll()
        let compactPanelCount = windows.lazy.filter { $0 is CompactBoardPanel }.count
        pendingCompactDismissals += compactPanelCount

        for window in windows {
            if let panel = window as? CompactBoardPanel {
                dismissCompactPanel(panel) { [weak self] in
                    guard let self else { return }
                    self.pendingCompactDismissals = max(0, self.pendingCompactDismissals - 1)
                    self.restoreMenuBarIfCompactBoardIsClosed()
                }
            } else {
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        restoreMenuBarIfCompactBoardIsClosed()
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
        stopScreenParametersObserver()
        for window in arrangeWindows {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        arrangeWindows.removeAll()
        pendingCompactDismissals = 0
        forceRestoreMenuBar()
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

    private func makeCompactPanel(model: AppModel, display: DisplayInfo) -> CompactBoardPanel {
        let geometry = CompactBoardGeometry(display: display)
        let panel = CompactBoardPanel(
            contentRect: geometry.collapsedFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.displayID = display.id
        panel.geometry = geometry
        panel.setFrame(geometry.collapsedFrame, display: false)
        // The shell must meet the physical top edge and cover the menu-bar seam so
        // it reads as an expansion of the notch instead of a detached popover.
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = compactBackdropView()
        panel.alphaValue = 1
        panel.onResignKey = { [weak self, weak model] in
            guard let self, let model, model.isArrangeBoardVisible else { return }
            guard !self.arrangeWindows.contains(where: { $0.isKeyWindow }) else { return }
            model.closeArrangeBoard()
        }
        return panel
    }

    private func compactHostingView(
        model: AppModel,
        display: DisplayInfo,
        geometry: CompactBoardGeometry
    ) -> NSView {
        let hostingView = NSHostingView(
            rootView: ArrangeBoardView(
                display: display,
                presentation: .compactIsland(geometry)
            )
            .environmentObject(model)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        return hostingView
    }

    private func compactBackdropView() -> NSView {
        let hostingView = NSHostingView(
            rootView: Rectangle()
                .fill(.black)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 26,
                        bottomTrailingRadius: 26,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        return hostingView
    }

    private func presentCompactPanel(
        _ panel: CompactBoardPanel,
        model: AppModel,
        display: DisplayInfo
    ) {
        panel.isDismissing = false
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let revealBoard = { [weak panel, weak model] in
            guard let panel, let model, panel.isVisible, !panel.isDismissing else { return }
            panel.isOpening = false
            let board = self.compactHostingView(model: model, display: display, geometry: panel.geometry)
            board.alphaValue = 0
            panel.contentView = board
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0.10 : 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                board.animator().alphaValue = 1
            }
        }

        if reduceMotion {
            panel.setFrame(panel.geometry.expandedFrame, display: true)
            revealBoard()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.30, 1.0)
            panel.animator().setFrame(panel.geometry.expandedFrame, display: true)
        } completionHandler: {
            revealBoard()
        }
    }

    private func dismissCompactPanel(
        _ panel: CompactBoardPanel,
        completion: @escaping () -> Void
    ) {
        guard !panel.isDismissing else {
            completion()
            return
        }
        panel.isOpening = false
        panel.isDismissing = true
        panel.suppressesResignDismissal = true
        let finish = {
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
            completion()
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let contractShell = {
            panel.contentView = self.compactBackdropView()
            panel.contentView?.alphaValue = 1

            if reduceMotion {
                panel.setFrame(panel.geometry.collapsedFrame, display: false)
                finish()
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0.0, 0.90, 0.45)
                panel.animator().setFrame(panel.geometry.collapsedFrame, display: true)
            } completionHandler: {
                finish()
            }
        }

        guard let board = panel.contentView else {
            contractShell()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.08 : 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            board.animator().alphaValue = 0
        } completionHandler: {
            contractShell()
        }
    }

    private func startScreenParametersObserver(model: AppModel) {
        stopScreenParametersObserver()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak model] _ in
            Task { @MainActor in
                guard let self, let model else { return }
                self.refreshCompactPanels(model: model)
            }
        }
    }

    private func stopScreenParametersObserver() {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
    }

    private func hideMenuBarForCompactBoard() {
        if menuBarVisibilityBeforeCompactBoard == nil {
            menuBarVisibilityBeforeCompactBoard = NSMenu.menuBarVisible()
        }
        NSMenu.setMenuBarVisible(false)
    }

    private func restoreMenuBarIfCompactBoardIsClosed() {
        guard pendingCompactDismissals == 0,
              !arrangeWindows.contains(where: { $0 is CompactBoardPanel }),
              let wasVisible = menuBarVisibilityBeforeCompactBoard else {
            return
        }
        NSMenu.setMenuBarVisible(wasVisible)
        menuBarVisibilityBeforeCompactBoard = nil
    }

    private func forceRestoreMenuBar() {
        guard let wasVisible = menuBarVisibilityBeforeCompactBoard else { return }
        NSMenu.setMenuBarVisible(wasVisible)
        menuBarVisibilityBeforeCompactBoard = nil
    }

    private func refreshCompactPanels(model: AppModel) {
        let displays = NSScreen.screens.map(DisplayInfo.init(screen:))
        let panels = arrangeWindows.compactMap { $0 as? CompactBoardPanel }
        guard !panels.isEmpty else { return }

        for panel in panels {
            guard !panel.isDismissing else { continue }
            guard let display = displays.first(where: { $0.id == panel.displayID }) else {
                model.closeArrangeBoard()
                return
            }
            let geometry = CompactBoardGeometry(display: display)
            panel.geometry = geometry
            guard !panel.isOpening else { continue }
            panel.setFrame(geometry.expandedFrame, display: true)
            panel.contentView = compactHostingView(model: model, display: display, geometry: geometry)
        }
        panels.last?.makeKeyAndOrderFront(nil)
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

private final class CompactBoardPanel: NSPanel {
    var displayID = ""
    var geometry: CompactBoardGeometry!
    var onResignKey: (() -> Void)?
    var suppressesResignDismissal = false
    var isOpening = true
    var isDismissing = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // NSWindow normally pushes borderless windows down to the screen's visible
    // frame, leaving the menu-bar-height gap seen beneath the notch. Compact
    // Island intentionally owns that top band, so preserve the physical-screen
    // frame calculated by CompactBoardGeometry.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func resignKey() {
        super.resignKey()
        guard !suppressesResignDismissal else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onResignKey?()
        }
    }
}
