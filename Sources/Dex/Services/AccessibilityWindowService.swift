import AppKit
import ApplicationServices
import Foundation

final class AccessibilityWindowService {
    func visibleWindows(excluding excludedBundleID: String?) -> [ManagedWindow] {
        let cgInfos = cgWindowInfos()
        return NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                app.processIdentifier > 0 &&
                app.bundleIdentifier != excludedBundleID
            }
            .flatMap { windows(for: $0, cgInfos: cgInfos) }
    }

    @discardableResult
    func moveResize(_ window: ManagedWindow, to rect: CGRect) -> Bool {
        var origin = rect.origin
        var size = rect.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }
        let firstSizeError = AXUIElementSetAttributeValue(window.axElement, kAXSizeAttribute as CFString, sizeValue)
        let positionError = AXUIElementSetAttributeValue(window.axElement, kAXPositionAttribute as CFString, positionValue)
        let secondSizeError = AXUIElementSetAttributeValue(window.axElement, kAXSizeAttribute as CFString, sizeValue)
        return firstSizeError == .success && positionError == .success && secondSizeError == .success
    }

    func raise(_ window: ManagedWindow) {
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
    }

    func closeWindowOnly(_ window: ManagedWindow) {
        if let closeButton = copyAttribute(window.axElement, kAXCloseButtonAttribute) as! AXUIElement? {
            AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        }
    }

    /// Counts the app's standard windows across all spaces. AX enumeration is not
    /// limited to the current space, unlike the CG on-screen list used for the board,
    /// so windows parked on other desktops are included. Minimized windows count too —
    /// quitting the app would destroy them. Returns nil when the AX read fails.
    func appWindowCount(pid: pid_t) -> Int? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let rawWindows = copyAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else {
            return nil
        }
        return rawWindows.filter { element in
            guard copyAttribute(element, kAXRoleAttribute) as? String == kAXWindowRole as String else {
                return false
            }
            return copyAttribute(element, kAXSubroleAttribute) as? String != kAXSystemDialogSubrole as String
        }.count
    }

    func pressNewWindowMenuItem(
        bundleIdentifiers: [String],
        appNames: [String],
        itemTitles: [String]
    ) -> Bool {
        guard !itemTitles.isEmpty else { return false }

        for app in matchingRunningApplications(bundleIdentifiers: bundleIdentifiers, appNames: appNames) {
            app.activate(options: [.activateIgnoringOtherApps])
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let menuBar = copyAttribute(appElement, kAXMenuBarAttribute) as! AXUIElement? else {
                continue
            }

            guard let fileMenuItem = child(of: menuBar, matchingTitle: "File") else {
                continue
            }

            AXUIElementPerformAction(fileMenuItem, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 0.05)

            guard let fileMenu = firstMenuDescendant(of: fileMenuItem),
                  let newWindowItem = descendant(of: fileMenu, matchingAnyTitle: itemTitles),
                  isEnabled(newWindowItem),
                  AXUIElementPerformAction(newWindowItem, kAXPressAction as CFString) == .success else {
                continue
            }
            return true
        }

        return false
    }

    func postNewWindowKeyboardShortcut(
        bundleIdentifiers: [String],
        appNames: [String]
    ) -> Bool {
        guard let app = matchingRunningApplications(
            bundleIdentifiers: bundleIdentifiers,
            appNames: appNames
        ).first else {
            return false
        }

        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.18)

        let source = CGEventSource(stateID: .hidSystemState)
        let nKeyCode = CGKeyCode(45)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: nKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: nKeyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func windows(for app: NSRunningApplication, cgInfos: [WindowMatchCandidate]) -> [ManagedWindow] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let rawWindows = copyAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else {
            return []
        }
        var usedCGWindowIDs = Set<CGWindowID>()

        return rawWindows.compactMap { element in
            guard isNormalWindow(element),
                  let frame = frame(of: element),
                  frame.width >= 120,
                  frame.height >= 80 else {
                return nil
            }

            let title = copyAttribute(element, kAXTitleAttribute) as? String ?? ""
            let bundleID = app.bundleIdentifier ?? "pid.\(app.processIdentifier)"
            let appName = app.localizedName ?? bundleID
            let cgWindow = WindowMatchResolver.bestMatch(
                forPID: app.processIdentifier,
                title: title,
                frame: frame,
                in: cgInfos,
                usedWindowIDs: &usedCGWindowIDs
            )
            guard let cgWindow else {
                return nil
            }
            let id = "\(app.processIdentifier):\(cgWindow.windowID)"

            return ManagedWindow(
                id: id,
                pid: app.processIdentifier,
                appName: appName,
                bundleIdentifier: bundleID,
                title: title,
                frame: frame,
                axElement: element,
                cgWindowID: cgWindow.windowID,
                thumbnail: nil
            )
        }
    }

    private func isNormalWindow(_ element: AXUIElement) -> Bool {
        let role = copyAttribute(element, kAXRoleAttribute) as? String
        guard role == kAXWindowRole as String else { return false }

        if let minimized = copyAttribute(element, kAXMinimizedAttribute) as? Bool, minimized {
            return false
        }

        let subrole = copyAttribute(element, kAXSubroleAttribute) as? String
        if subrole == kAXSystemDialogSubrole as String {
            return false
        }

        return true
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute) as! AXValue?,
              let sizeValue = copyAttribute(element, kAXSizeAttribute) as! AXValue? else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &point)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: point, size: size).integral
    }

    private func matchingRunningApplications(
        bundleIdentifiers: [String],
        appNames: [String]
    ) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            if let bundleIdentifier = app.bundleIdentifier,
               bundleIdentifiers.contains(bundleIdentifier) {
                return true
            }
            guard let localizedName = app.localizedName else { return false }
            return appNames.contains { localizedName.localizedCaseInsensitiveContains($0) }
        }
    }

    private func child(of element: AXUIElement, matchingTitle title: String) -> AXUIElement? {
        children(of: element).first { child in
            (copyAttribute(child, kAXTitleAttribute) as? String) == title
        }
    }

    private func descendant(of element: AXUIElement, matchingAnyTitle titles: [String]) -> AXUIElement? {
        for child in children(of: element) {
            if let title = copyAttribute(child, kAXTitleAttribute) as? String,
               titles.contains(title) {
                return child
            }

            if let match = descendant(of: child, matchingAnyTitle: titles) {
                return match
            }
        }

        return nil
    }

    private func firstMenuDescendant(of element: AXUIElement) -> AXUIElement? {
        for child in children(of: element) {
            let role = copyAttribute(child, kAXRoleAttribute) as? String
            if role == kAXMenuRole as String {
                return child
            }

            if let menu = firstMenuDescendant(of: child) {
                return menu
            }
        }

        return nil
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func isEnabled(_ element: AXUIElement) -> Bool {
        (copyAttribute(element, kAXEnabledAttribute) as? Bool) ?? true
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> Any? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
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
}
