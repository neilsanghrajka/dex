import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var windows: [ManagedWindow] = []
    @Published var stacksByDisplay: [String: ColumnStackState] = [:]
    @Published private var stacksByWorkspace: [String: ColumnStackState] = [:]
    @Published var layoutKindsByWorkspace: [String: BoardLayoutKind] = [:]
    @Published var arrangeAllDisplays: Bool {
        didSet {
            store.arrangeAllDisplays = arrangeAllDisplays
        }
    }
    @Published var boardPresentationMode: BoardPresentationMode {
        didSet {
            store.boardPresentationMode = boardPresentationMode
        }
    }
    /// Live, user-editable list of app-launch shortcuts. Single source of truth for
    /// the board key handler, the palette shortcut-help, and (later) the onboarding tour.
    @Published var appShortcutBindings: [AppShortcutBinding] {
        didSet {
            store.saveAppShortcutBindings(appShortcutBindings)
        }
    }
    /// Apps in this list should get a fresh window when Dex opens them from the
    /// board, palette, or running-app shelf.
    @Published var newWindowLaunchRules: [NewWindowLaunchRule] {
        didSet {
            store.saveNewWindowLaunchRules(newWindowLaunchRules)
        }
    }
    @Published var hoveredSnapRole: ColumnRole?
    @Published var hudText: String?
    @Published var permissionRefreshID = UUID()
    @Published private(set) var savedModes: [SavedMode]
    @Published private(set) var activeModeInstances: [ActiveModeInstance] = []
    @Published var modeLaunchConfirmation: ModeLaunchConfirmation = .idle
    @Published private(set) var diaTabsByWindowID: [String: [DiaTab]] = [:]
    @Published private(set) var diaTabPreviewCache: [String: NSImage] = [:]
    @Published private(set) var isArrangeBoardVisible = false
    @Published var activeBoardDisplayID: String?
    @Published var activeBoardDesktopID: String?

    // MARK: Onboarding
    /// Drives whether `ContentView` shows the first-run wizard (Acts 1 & 2).
    @Published var isOnboardingWizardActive: Bool
    /// Registered by a live SwiftUI view (Settings / main window) so onboarding replay can
    /// recreate the main "Dex" window via `openWindow(id:)`. Re-fronting `NSApp.windows`
    /// alone cannot bring back a `WindowGroup` window the user has closed.
    var openMainWindowAction: (() -> Void)?
    /// The current wizard stage while `isOnboardingWizardActive` is true.
    @Published var onboardingPhase: OnboardingPhase = .welcome
    /// The active in-board tour step, or `nil` when no tour is running (Act 3).
    @Published private(set) var tourStep: OnboardingTourStep?
    /// Whether the reinforcement legend is showing along the board's bottom edge.
    @Published private(set) var isBoardLegendVisibleThisSession = false
    /// Settings toggle: allow the post-tour reinforcement legend at all.
    @Published var showsBoardLegend: Bool {
        didSet {
            store.showsBoardLegend = showsBoardLegend
        }
    }
    /// How many board sessions after tour completion keep showing the legend.
    private static let boardLegendSessionCount = 5

    let permissions = PermissionService()
    private let accessibility = AccessibilityWindowService()
    private let thumbnails = ThumbnailService()
    private let diaTabs = DiaTabService()
    private let applicationCatalog = ApplicationCatalogService()
    private let eventMonitor = EventMonitor()
    private let overlayController = OverlayWindowController()
    private let store = LayoutStore()
    private var hudTask: Task<Void, Never>?
    private var permissionRefreshTask: Task<Void, Never>?
    private var thumbnailRefreshTask: Task<Void, Never>?
    private var boardSpacePollTask: Task<Void, Never>?
    private var pendingBoardSpaceRefreshTask: Task<Void, Never>?
    private var activeSpaceObserver: NSObjectProtocol?
    private var lastObservedMainSpaceID: String?
    private var pendingBoardFocusRequest: BoardFocusRequest?
    /// Retains exact AX handles for windows minimized from the board so the Running Apps
    /// shelf restores them before applying an app's "open a new window" rule.
    private var minimizedBoardWindows: [String: ManagedWindow] = [:]
    /// Session-local reversible F/W transforms. Restoring returns the exact prior
    /// position and size while the window remains in Open Windows.
    private var windowTransformStates: [String: BoardWindowTransformState] = [:]

    init() {
        self.arrangeAllDisplays = store.arrangeAllDisplays
        self.boardPresentationMode = store.boardPresentationMode
        self.stacksByDisplay = store.loadStacks()
        self.stacksByWorkspace = store.loadWorkspaceStacks()
        self.layoutKindsByWorkspace = store.loadDisplayLayoutKinds()
        self.appShortcutBindings = store.loadAppShortcutBindings()
        self.newWindowLaunchRules = store.loadNewWindowLaunchRules()
        self.savedModes = store.loadSavedModes()
        self.showsBoardLegend = store.showsBoardLegend
        self.isOnboardingWizardActive = !store.hasCompletedOnboarding
    }

    func start() {
        applicationCatalog.prewarm()
        eventMonitor.onDoubleOption = { [weak self] in
            Task { @MainActor in await self?.toggleArrangeBoard() }
        }
        eventMonitor.onCycle = { [weak self] direction, trigger in
            Task { @MainActor in await self?.cycleStack(direction, trigger: trigger) }
        }
        eventMonitor.onModeHotkey = { [weak self] slot in
            guard let self else { return false }
            Task { @MainActor in await self.handleModeHotkey(slot: slot) }
            return true
        }
        eventMonitor.shouldHandleCycle = { [weak self] in
            guard let self else { return true }
            return !self.isArrangeBoardVisible
        }
        eventMonitor.shouldHandleModeHotkeys = { [weak self] in
            guard let self else { return true }
            return !self.isArrangeBoardVisible
        }
        eventMonitor.onEscape = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.isArrangeBoardVisible == true else { return }
                if self.tourStep != nil {
                    self.exitTour()
                    return
                }
                self.closeArrangeBoard()
            }
        }
        eventMonitor.onControlDragChanged = { [weak self] point in
            self?.updateControlDrag(at: point)
        }
        eventMonitor.onControlDragEnded = { [weak self] point in
            Task { @MainActor in await self?.finishControlDrag(at: point) }
        }
        eventMonitor.start()
        startPermissionRefreshLoop()
        startActiveSpaceObserver()
    }

    func stop() {
        permissionRefreshTask?.cancel()
        stopArrangeBoardSpaceRefreshLoop()
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
            self.activeSpaceObserver = nil
        }
        eventMonitor.stop()
        overlayController.closeAll()
        activeBoardDisplayID = nil
        activeBoardDesktopID = nil
        isArrangeBoardVisible = false
    }

    func refreshPermissions() {
        permissionRefreshID = UUID()
        if permissions.isInputMonitoringTrusted {
            eventMonitor.start()
        }
        advanceOnboardingIfRequiredPermissionsGranted()
    }

    func requestAccessibility() {
        permissions.requestAccessibility()
        refreshPermissions()
        showHUD("Grant Accessibility in Settings")
    }

    func requestInputMonitoring() {
        permissions.requestInputMonitoring()
        refreshPermissions()
        showHUD("Grant Input Monitoring in Settings")
    }

    func requestScreenRecording() {
        permissions.requestScreenRecording()
        refreshPermissions()
        showHUD("Grant Screen Recording in Settings")
    }

    private func startPermissionRefreshLoop() {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.refreshPermissions()
                }
            }
        }
    }

    func showArrangeBoard() async {
        guard permissions.isAccessibilityTrusted else {
            showHUD("Grant Accessibility first")
            return
        }
        let displays = boardDisplays()
        await refreshWindowsUntilStableForLayoutRead()
        let repairedDisplayIDs = repairStacksFromWindowPositionsIfNeeded(for: displays)
        if !repairedDisplayIDs.isEmpty {
            arrangeAssignedWindows(displayIDs: repairedDisplayIDs, raiseActiveWindows: false)
            await refreshWindows(includeThumbnails: false, pruneMissingWindows: false)
        }
        overlayController.showArrangeBoard(
            model: self,
            displays: displays,
            presentationMode: boardPresentationMode
        )
        isArrangeBoardVisible = true
        startArrangeBoardSpaceRefreshLoop()
        beginInBoardTourIfSummoning()
        updateBoardLegendVisibilityForNewSession()

        Task { @MainActor in
            await refreshWindows(includeThumbnails: true)
            await refreshDiaTabs()
        }
    }

    func closeArrangeBoard() {
        // Closing the board (e.g. a second double-Option) must not leave the tour
        // half-running: clear the step so it does not re-appear on reopen, and treat
        // the interruption as completing onboarding so the wizard never re-runs.
        if tourStep != nil {
            finishOnboarding()
            tourStep = nil
        }
        overlayController.closeArrangeBoard()
        stopArrangeBoardSpaceRefreshLoop()
        activeBoardDisplayID = nil
        activeBoardDesktopID = nil
        isArrangeBoardVisible = false
        isBoardLegendVisibleThisSession = false
    }

    func toggleArrangeBoard() async {
        if isArrangeBoardVisible {
            closeArrangeBoard()
            showHUD("Dex board hidden")
        } else {
            await showArrangeBoard()
        }
    }

    func arrangeNow() async {
        await refreshWindows(includeThumbnails: false)
        _ = repairStacksFromWindowPositionsIfNeeded(for: targetDisplays())
        arrangeAssignedWindows()
        showHUD("Arranged \(arrangeAllDisplays ? "all displays" : "active display")")
    }

    func layoutKind(for displayID: String, spaceID: String? = nil) -> BoardLayoutKind {
        layoutKindsByWorkspace[workspaceKey(for: displayID, spaceID: spaceID), default: .defaultKind]
    }

    func grid(for display: DisplayInfo) -> GridLayout {
        GridLayout(visibleFrame: display.visibleFrame, kind: layoutKind(for: display.id))
    }

    func layoutRoles(for display: DisplayInfo) -> [ColumnRole] {
        grid(for: display).roles
    }

    @discardableResult
    func applyLayoutShortcut(_ slot: Int, displayID: String) -> ColumnRole? {
        guard let kind = BoardLayoutKind.shortcutKind(for: slot),
              let display = display(withID: displayID) else {
            return nil
        }

        let activeWorkspaceKey = workspaceKey(for: displayID)
        let previousGrid = grid(for: display)
        layoutKindsByWorkspace[activeWorkspaceKey] = kind
        store.saveDisplayLayoutKinds(layoutKindsByWorkspace)

        let nextGrid = GridLayout(visibleFrame: display.visibleFrame, kind: kind)
        let didReflowStack = reflowCurrentWorkspaceStack(
            for: displayID,
            workspaceKey: activeWorkspaceKey,
            previousGrid: previousGrid,
            nextGrid: nextGrid
        )
        saveWorkspaceStacks()

        if didReflowStack || previousGrid.kind != nextGrid.kind {
            arrangeAssignedWindows(displayIDs: Set([displayID]), raiseActiveWindows: !isArrangeBoardVisible)
        }

        showHUD(kind.displayName)
        refocusArrangeBoardIfNeeded()
        refreshThumbnailsAfterWindowGeometryChange()
        return nextGrid.roles.first
    }

    func modeCapturePreview(displayID: String) -> ModeCapturePreview {
        ModeCapturePreview(
            layoutKind: layoutKind(for: displayID),
            windowsByRole: capturedModeWindows(displayID: displayID)
        )
    }

    @discardableResult
    func saveMode(name rawName: String, replacing existingID: UUID?, displayID: String) -> SavedMode? {
        let cleanedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleanedName.isEmpty ? "Group \(savedModes.count + 1)" : cleanedName
        let captured = capturedModeWindows(displayID: displayID)
        let modeLayoutKind = layoutKind(for: displayID)
        let windows = modeLayoutKind.roles.flatMap { role in
            captured[role, default: []]
        }

        guard !windows.isEmpty else {
            showHUD("Assign windows before saving a group")
            return nil
        }

        let now = Date()
        var modes = savedModes
        let slot: Int
        let id: UUID
        let createdAt: Date

        if let existingID,
           let index = modes.firstIndex(where: { $0.id == existingID }) {
            slot = modes[index].slot
            id = existingID
            createdAt = modes[index].createdAt
            modes.remove(at: index)
        } else {
            slot = ModeSlotAssignment.firstAvailableSlot(in: modes)
            id = UUID()
            createdAt = now
        }

        let mode = SavedMode(
            id: id,
            name: name,
            slot: slot,
            layoutKind: modeLayoutKind,
            windows: windows,
            createdAt: createdAt,
            updatedAt: now
        )
        modes.append(mode)
        savedModes = modes.sorted { lhs, rhs in lhs.slot < rhs.slot }
        store.saveSavedModes(savedModes)
        activateModeFromCurrentArrangement(mode, displayID: displayID)
        showHUD("\(mode.name) saved as \(mode.shortcutLabel)")
        refocusArrangeBoardIfNeeded()
        return mode
    }

    func renameMode(id: UUID, to rawName: String) {
        let cleanedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            showHUD("Group name cannot be empty")
            return
        }
        guard let index = savedModes.firstIndex(where: { $0.id == id }) else {
            showHUD("Group not found")
            return
        }

        savedModes[index].name = cleanedName
        savedModes[index].updatedAt = Date()
        savedModes = savedModes.sorted { lhs, rhs in lhs.slot < rhs.slot }
        store.saveSavedModes(savedModes)

        activeModeInstances = activeModeInstances.map { instance in
            guard instance.modeID == id else { return instance }
            var updated = instance
            updated.modeName = cleanedName
            return updated
        }
        showHUD("Renamed group")
    }

    func deleteMode(id: UUID) {
        guard let mode = savedModes.first(where: { $0.id == id }) else {
            showHUD("Group not found")
            return
        }
        savedModes.removeAll { $0.id == id }
        store.saveSavedModes(savedModes)
        activeModeInstances.removeAll { $0.modeID == id }
        modeLaunchConfirmation = .idle
        showHUD("Deleted \(mode.name)")
    }

    func openModeManagement() {
        closeArrangeBoard()
        NSApp.activate(ignoringOtherApps: true)
        showHUD("Manage groups in Dex")
    }

    func mode(forSlot slot: Int) -> SavedMode? {
        savedModes.first { $0.slot == slot }
    }

    func handleModeHotkey(slot: Int) async {
        guard let mode = mode(forSlot: slot) else {
            showHUD("No group saved for Option+\(slot)")
            return
        }
        await confirmOrLaunchMode(mode, policy: selectedLaunchPolicy())
    }

    func prepareModeLaunch(slot: Int) {
        guard let mode = mode(forSlot: slot) else {
            showHUD("No group saved for Option+\(slot)")
            return
        }
        modeLaunchConfirmation = .confirming(
            mode: mode,
            policy: .quitElsewhereAndReopenHere,
            armedAt: Date()
        )
    }

    func setLaunchConfirmationPolicy(_ policy: ModeLaunchPolicy) {
        guard case .confirming(let mode, _, let armedAt) = modeLaunchConfirmation else { return }
        modeLaunchConfirmation = .confirming(mode: mode, policy: policy, armedAt: armedAt)
    }

    func cancelModeLaunchConfirmation() {
        modeLaunchConfirmation = .idle
    }

    func launchConfirmedMode() async {
        guard case .confirming(let mode, let policy, _) = modeLaunchConfirmation else { return }
        modeLaunchConfirmation = .idle
        await launchMode(mode, policy: policy)
    }

    func launchModeFromPalette(_ mode: SavedMode) async {
        modeLaunchConfirmation = .idle
        await launchMode(mode, policy: .quitElsewhereAndReopenHere)
    }

    func activeModes(on display: DisplayInfo) -> [ActiveModeInstance] {
        let spaceID = activeLayoutSpaceID()
        return activeModeInstances
            .filter { $0.displayID == display.id && $0.spaceID == spaceID && !$0.windowBindings.isEmpty }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func raiseModeInstance(id: UUID) async {
        await refreshWindows(includeThumbnails: false)
        guard let instance = activeModeInstances.first(where: { $0.id == id }) else {
            showHUD("Group is no longer active")
            return
        }
        let liveWindows = instance.windowBindings.compactMap { binding in
            windows.first { $0.id == binding.windowID }
        }
        guard !liveWindows.isEmpty else {
            removeActiveModeInstance(id: id)
            showHUD("Group windows are gone")
            return
        }

        for window in liveWindows {
            if let binding = instance.windowBindings.first(where: { $0.windowID == window.id }),
               let display = display(withID: instance.displayID) {
                accessibility.moveResize(window, to: grid(for: display).rect(for: binding.role))
            }
        }
        let roleOrder: [ColumnRole]
        if let display = display(withID: instance.displayID) {
            let layoutRoles = grid(for: display).roles
            roleOrder = layoutRoles + ColumnRole.allCases.filter { !layoutRoles.contains($0) }
        } else {
            roleOrder = ColumnRole.allCases
        }

        for role in roleOrder {
            liveWindows
                .filter { window in
                    instance.windowBindings.first(where: { $0.windowID == window.id })?.role == role
                }
                .forEach(accessibility.raise)
        }
        showHUD("Raised \(instance.modeName)")
    }

    func closeModeInstance(id: UUID) async {
        await refreshWindows(includeThumbnails: false)
        guard let instance = activeModeInstances.first(where: { $0.id == id }) else { return }
        let bindingIDs = Set(instance.windowBindings.map(\.windowID))
        let liveWindows = windows.filter { bindingIDs.contains($0.id) }
        let windowsByPID = Dictionary(grouping: liveWindows, by: \.pid)
        var terminatedPIDs = Set<pid_t>()

        for (pid, modeWindows) in windowsByPID {
            let nonModeWindows = windows.filter { $0.pid == pid && !bindingIDs.contains($0.id) }
            if nonModeWindows.isEmpty,
               let app = NSRunningApplication(processIdentifier: pid) {
                app.terminate()
                terminatedPIDs.insert(pid)
                modeWindows.forEach { removeWindowFromAllStacks($0.id) }
            } else {
                for window in modeWindows {
                    accessibility.closeWindowOnly(window)
                    removeWindowFromAllStacks(window.id)
                }
            }
        }

        removeActiveModeInstance(id: id)
        saveAllStackStores()
        showHUD(terminatedPIDs.isEmpty ? "Closed \(instance.modeName)" : "Quit \(instance.modeName)")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await refreshWindows(includeThumbnails: true)
            refocusArrangeBoardIfNeeded()
        }
    }

    @discardableResult
    func assign(windowID: String, to role: ColumnRole, displayID: String) -> Bool {
        windowTransformStates.removeValue(forKey: windowID)
        removeWindowFromActiveWorkspaceStacks(windowID)
        var state = stackState(for: displayID)
        state.assign(windowID, to: role)
        if !isArrangeBoardVisible {
            state.prune(keeping: Set(windows(on: displayID).map(\.id)))
        }
        setStackState(state, for: displayID)
        let didMove = arrangeAssignedWindows(displayIDs: Set([displayID]), raiseActiveWindows: !isArrangeBoardVisible)
        refocusArrangeBoardIfNeeded()
        refreshThumbnailsAfterWindowGeometryChange()
        return didMove
    }

    func assign(windowID: String, at screenPoint: CGPoint) {
        guard let display = targetDisplays().first(where: { $0.frame.contains(screenPoint) }) else {
            return
        }
        assign(windowID: windowID, to: grid(for: display).nearestRole(to: screenPoint), displayID: display.id)
    }

    func selectBoardWindow(windowID: String) {
        guard let window = windows.first(where: { $0.id == windowID }) else {
            showHUD("Window not found")
            return
        }
        showHUD("Selected \(window.displayTitle)")
    }

    func selectBoardDiaTab(tabID: String) {
        guard let tab = diaTab(withID: tabID) else {
            showHUD("Dia tab not found")
            return
        }
        showHUD("Selected \(tab.displayTitle)")
    }

    func activateBoardWindow(windowID: String) {
        guard let window = windows.first(where: { $0.id == windowID }) else {
            showHUD("Window not found")
            return
        }
        promoteWindowInExistingStack(windowID)
        closeArrangeBoard()
        accessibility.raise(window)
    }

    func activateBoardDiaTab(tabID: String) {
        guard let tab = diaTab(withID: tabID),
              let window = windows.first(where: { $0.id == tab.parentWindowID }) else {
            showHUD("Dia tab not found")
            return
        }

        promoteWindowInExistingStack(tab.parentWindowID)
        closeArrangeBoard()
        Task { @MainActor in
            let focused = await diaTabs.focus(tab)
            accessibility.raise(window)
            if focused {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await refreshWindows(includeThumbnails: true)
                await refreshDiaTabs()
            } else {
                showHUD("Could not focus Dia tab")
            }
        }
    }

    func closeBoardWindow(windowID: String) {
        guard let window = windows.first(where: { $0.id == windowID }) else {
            showHUD("Window not found")
            return
        }
        let action = WindowCloseAction.decide(
            allowsMultipleWindows: newWindowLaunchRules.contains { $0.matches(window) },
            crossSpaceWindowCount: accessibility.appWindowCount(pid: window.pid),
            visibleWindowCount: windows.filter { $0.pid == window.pid }.count
        )
        if action == .quitApp,
           let app = NSRunningApplication(processIdentifier: window.pid) {
            app.terminate()
            showHUD("Quit \(window.appName)")
        } else {
            accessibility.closeWindowOnly(window)
            showHUD("Closed \(window.displayTitle)")
        }
        removeWindowFromAllStacks(windowID)
        saveAllStackStores()
        refocusArrangeBoardIfNeeded()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await refreshWindows(includeThumbnails: true)
            refocusArrangeBoardIfNeeded()
        }
    }

    @discardableResult
    func minimizeBoardWindow(windowID: String) -> Bool {
        guard let window = windows.first(where: { $0.id == windowID }) else {
            showHUD("Window not found")
            return false
        }
        guard accessibility.minimize(window) else {
            showHUD("Could not minimize \(window.displayTitle)")
            refocusArrangeBoardIfNeeded()
            return false
        }

        minimizedBoardWindows[window.id] = window
        showHUD("Minimized \(window.displayTitle)")
        refocusArrangeBoardIfNeeded()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await refreshWindows(includeThumbnails: true)
            refocusArrangeBoardIfNeeded()
        }
        return true
    }

    func showMinimizeWindowSelectionHint() {
        showHUD("Select a window to minimize")
        refocusArrangeBoardIfNeeded()
    }

    @discardableResult
    func toggleBoardWindowTransform(
        windowID: String,
        displayID: String,
        transform: BoardWindowTransform
    ) -> Bool {
        guard let window = windows.first(where: { $0.id == windowID }) else {
            showHUD("Window not found")
            return false
        }
        guard let display = allDisplays().first(where: { $0.id == displayID }) else {
            showHUD("Display not found")
            refocusArrangeBoardIfNeeded()
            return false
        }
        let transition = BoardWindowTransformLogic.transition(
            currentState: windowTransformStates[windowID],
            requestedTransform: transform,
            currentFrame: assignedBoardFrame(windowID: windowID, on: display) ?? window.frame,
            visibleFrame: display.visibleFrame
        )
        let targetFrame: CGRect
        switch transition {
        case .apply(let frame, _), .restore(let frame):
            targetFrame = frame
        }
        guard accessibility.moveResize(window, to: targetFrame) else {
            showHUD("Could not resize \(window.displayTitle)")
            refocusArrangeBoardIfNeeded()
            return false
        }

        switch transition {
        case .apply(_, let nextState):
            windowTransformStates[windowID] = nextState
            removeWindowFromActiveWorkspaceStacks(windowID)
            saveWorkspaceStacks()
            showHUD("\(transform.actionName) \(window.displayTitle)")
        case .restore:
            windowTransformStates.removeValue(forKey: windowID)
            showHUD("Restored \(window.displayTitle)")
        }
        refocusArrangeBoardIfNeeded()
        refreshThumbnailsAfterWindowGeometryChange()
        return true
    }

    func showResizeWindowSelectionHint() {
        showHUD("Select a window to resize")
        refocusArrangeBoardIfNeeded()
    }

    @discardableResult
    func makeBoardWindowWide(windowID: String, displayID: String) -> Bool {
        guard let window = windows.first(where: { $0.id == windowID }) else {
            showHUD("Window not found")
            return false
        }
        guard let display = display(withID: displayID) else {
            showHUD("Display not found")
            refocusArrangeBoardIfNeeded()
            return false
        }

        let activeWorkspaceKey = workspaceKey(for: displayID)
        let previousGrid = grid(for: display)
        let previousLayoutKinds = layoutKindsByWorkspace
        let previousWorkspaceStacks = stacksByWorkspace
        let nextGrid = GridLayout(
            visibleFrame: display.visibleFrame,
            kind: WideBoardPlacement.layoutKind
        )

        layoutKindsByWorkspace[activeWorkspaceKey] = WideBoardPlacement.layoutKind
        _ = reflowCurrentWorkspaceStack(
            for: displayID,
            workspaceKey: activeWorkspaceKey,
            previousGrid: previousGrid,
            nextGrid: nextGrid
        )

        let nextState = WideBoardPlacement.placing(
            windowID: windowID,
            in: stackState(for: displayID)
        )
        setStackState(nextState, for: displayID, save: false)
        stacksByWorkspace[
            layoutMemoryKey(
                workspaceKey: activeWorkspaceKey,
                kind: WideBoardPlacement.layoutKind
            )
        ] = nextState
        let arranged = arrangeAssignedWindows(
            displayIDs: Set([displayID]),
            raiseActiveWindows: !isArrangeBoardVisible
        )
        guard arranged else {
            layoutKindsByWorkspace = previousLayoutKinds
            stacksByWorkspace = previousWorkspaceStacks
            saveWorkspaceStacks()
            _ = arrangeAssignedWindows(
                displayIDs: Set([displayID]),
                raiseActiveWindows: !isArrangeBoardVisible
            )
            showHUD("Could not make \(window.displayTitle) wide")
            refocusArrangeBoardIfNeeded()
            return false
        }

        windowTransformStates.removeValue(forKey: windowID)
        store.saveDisplayLayoutKinds(layoutKindsByWorkspace)
        saveWorkspaceStacks()
        showHUD("Narrow L: \(window.displayTitle) wide")
        refocusArrangeBoardIfNeeded()
        refreshThumbnailsAfterWindowGeometryChange()
        return true
    }

    func showWideWindowSelectionHint() {
        showHUD("Select a window to make wide")
        refocusArrangeBoardIfNeeded()
    }

    func cleanupCandidates(on display: DisplayInfo) -> [CleanupCandidate] {
        windows(on: display).compactMap { window in
            let haystack = "\(window.appName) \(window.bundleIdentifier) \(window.title)".lowercased()
            let isDiaSocial = window.bundleIdentifier == "company.thebrowser.dia" &&
                (haystack.contains("twitter") ||
                 haystack.contains("x.com") ||
                 haystack.contains("instagram"))
            let isWhatsApp = haystack.contains("whatsapp")
            let isSuperhuman = haystack.contains("superhuman")
            guard isDiaSocial || isWhatsApp || isSuperhuman else { return nil }

            let label: String
            if isDiaSocial {
                label = window.title.isEmpty ? "Dia social tab" : window.title
            } else if isWhatsApp {
                label = "WhatsApp"
            } else {
                label = "Superhuman"
            }

            return CleanupCandidate(
                id: window.id,
                title: label,
                detail: window.appName,
                windowID: window.id
            )
        }
    }

    func closeCleanupCandidates(_ candidates: [CleanupCandidate]) {
        let ids = Set(candidates.map(\.windowID))
        for window in windows where ids.contains(window.id) {
            let haystack = "\(window.appName) \(window.bundleIdentifier) \(window.title)".lowercased()
            if haystack.contains("whatsapp") || haystack.contains("superhuman") {
                NSRunningApplication(processIdentifier: window.pid)?.terminate()
            } else {
                accessibility.closeWindowOnly(window)
            }
            removeWindowFromAllStacks(window.id)
        }
        saveAllStackStores()
        showHUD("Closed \(candidates.count) distracting windows")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await refreshWindows(includeThumbnails: true)
        }
    }

    func moveBoardWindow(windowID: String, to role: ColumnRole, displayID: String) {
        assign(windowID: windowID, to: role, displayID: displayID)
        showHUD("Moved to \(role.title)")
    }

    func moveBoardWindowToUnassigned(windowID: String) {
        removeWindowFromActiveWorkspaceStacks(windowID)
        saveWorkspaceStacks()
        showHUD("Moved to unassigned")
        refocusArrangeBoardIfNeeded()
    }

    func openAppShortcut(_ binding: AppShortcutBinding, in role: ColumnRole, displayID: String) async {
        await openLaunchTarget(launchSpec(for: binding), launchURL: nil, in: role, displayID: displayID)
    }

    func installedApplications() -> [InstalledApplication] {
        applicationCatalog.installedApplications()
    }

    func loadInstalledApplications() async -> [InstalledApplication] {
        await Task.detached(priority: .userInitiated) { [applicationCatalog] in
            applicationCatalog.installedApplications()
        }.value
    }

    /// Installed applications plus currently-running regular apps, deduplicated and
    /// sorted by name. Used by the Settings "Add App…" picker for new bindings.
    func availableApplicationsForBinding() async -> [InstalledApplication] {
        let installed = await loadInstalledApplications()
        let running: [InstalledApplication] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  let url = app.bundleURL,
                  let name = app.localizedName,
                  !name.isEmpty else {
                return nil
            }
            return InstalledApplication(
                id: url.path,
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                url: url
            )
        }

        let dexBundleID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var combined: [InstalledApplication] = []
        for app in running + installed {
            if let dexBundleID, app.bundleIdentifier == dexBundleID { continue }
            guard seen.insert(app.id).inserted else { continue }
            combined.append(app)
        }
        return combined.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func openApplication(_ application: InstalledApplication, in role: ColumnRole, displayID: String) async {
        await openLaunchTarget(launchSpec(for: application), launchURL: application.url, in: role, displayID: displayID)
    }

    private func openLaunchTarget(
        _ spec: BoardAppShortcutSpec,
        launchURL: URL?,
        in role: ColumnRole,
        displayID: String
    ) async {
        await refreshWindows(includeThumbnails: false)
        let existingMatchingWindows = windows.filter { spec.matches($0) }
        let launchSnapshot = BoardWindowLaunchSnapshot(windows: existingMatchingWindows)

        if !spec.forceNew, let existing = existingMatchingWindows.first {
            assign(windowID: existing.id, to: role, displayID: displayID)
            accessibility.raise(existing)
            showHUD("Moved \(spec.label) to \(role.title)")
            refocusArrangeBoardIfNeeded()
            return
        }

        if let launched = await openNewWindowUsingAppCommandIfAvailable(spec, excluding: launchSnapshot) {
            assign(windowID: launched.id, to: role, displayID: displayID)
            accessibility.raise(launched)
            showHUD("Opened \(spec.label) in \(role.title)")
            refocusArrangeBoardIfNeeded()
            return
        }

        guard launch(spec, url: launchURL) else {
            showHUD("Could not open \(spec.label)")
            refocusArrangeBoardIfNeeded()
            return
        }

        if let launched = await waitForLaunchedWindow(matching: spec, excluding: launchSnapshot) {
            assign(windowID: launched.id, to: role, displayID: displayID)
            accessibility.raise(launched)
            showHUD("Opened \(spec.label) in \(role.title)")
        } else {
            showHUD(spec.forceNew ? "Could not open new \(spec.label) window" : "Opened \(spec.label)")
        }
        refocusArrangeBoardIfNeeded()
    }

    func runningApplicationsWithoutVisibleWindows(on display: DisplayInfo) -> [RunningApplicationItem] {
        let displayWindows = windows(on: display)
        let candidates = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApplicationItem? in
            guard app.activationPolicy == .regular,
                  app.processIdentifier > 0,
                  let name = app.localizedName,
                  !name.isEmpty else {
                return nil
            }

            return RunningApplicationItem(
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                url: app.bundleURL,
                processIdentifier: app.processIdentifier
            )
        }

        return RunningApplicationFilter.hiddenApplications(
            candidates: candidates,
            visibleWindows: displayWindows,
            dexBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    func selectRunningApplication(_ item: RunningApplicationItem) {
        showHUD("Selected \(item.name)")
    }

    func openRunningApplication(
        _ item: RunningApplicationItem,
        in role: ColumnRole,
        displayID: String
    ) async {
        if let minimizedWindow = minimizedBoardWindows.values.first(where: { windowMatches($0, item: item) }) {
            minimizedBoardWindows[minimizedWindow.id] = nil
            if accessibility.restore(minimizedWindow) {
                try? await Task.sleep(nanoseconds: 350_000_000)
                await refreshWindows(includeThumbnails: true)
                if let restored = firstWindow(matching: item) {
                    assign(windowID: restored.id, to: role, displayID: displayID)
                    accessibility.raise(restored)
                    showHUD("Restored \(item.name) in \(role.title)")
                } else {
                    showHUD("Restored \(item.name)")
                }
                refocusArrangeBoardIfNeeded()
                return
            }
        }

        if newWindowLaunchRule(matching: item) != nil {
            await openLaunchTarget(launchSpec(for: item), launchURL: item.url, in: role, displayID: displayID)
            return
        }

        await refreshWindows(includeThumbnails: false)
        if let existing = firstWindow(matching: item) {
            assign(windowID: existing.id, to: role, displayID: displayID)
            accessibility.raise(existing)
            showHUD("Moved \(item.name) to \(role.title)")
            refocusArrangeBoardIfNeeded()
            return
        }

        if let running = NSRunningApplication(processIdentifier: item.processIdentifier) {
            running.activate(options: [.activateAllWindows])
            try? await Task.sleep(nanoseconds: 450_000_000)
            await refreshWindows(includeThumbnails: true)
            if let revealed = firstWindow(matching: item) {
                assign(windowID: revealed.id, to: role, displayID: displayID)
                accessibility.raise(revealed)
                showHUD("Opened \(item.name) in \(role.title)")
                refocusArrangeBoardIfNeeded()
                return
            }
        }

        if let url = item.url {
            NSWorkspace.shared.open(url)
        } else if let bundleIdentifier = item.bundleIdentifier {
            _ = launchWithOpen(arguments: ["-b", bundleIdentifier])
        } else {
            showHUD("Could not open \(item.name)")
            refocusArrangeBoardIfNeeded()
            return
        }

        try? await Task.sleep(nanoseconds: 900_000_000)
        await refreshWindows(includeThumbnails: true)
        if let launched = firstWindow(matching: item) {
            assign(windowID: launched.id, to: role, displayID: displayID)
            accessibility.raise(launched)
            showHUD("Opened \(item.name) in \(role.title)")
            refocusArrangeBoardIfNeeded()
        } else {
            showHUD("Opened \(item.name)")
            refocusArrangeBoardIfNeeded()
        }
    }

    func quitRunningApplication(_ item: RunningApplicationItem) {
        guard let app = NSRunningApplication(processIdentifier: item.processIdentifier) else {
            showHUD("\(item.name) is not running")
            return
        }

        app.terminate()
        showHUD("Quit \(item.name)")
        refocusArrangeBoardIfNeeded()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await refreshWindows(includeThumbnails: true)
            refocusArrangeBoardIfNeeded()
        }
    }

    // MARK: - App-launch shortcut bindings

    /// The default starter set, exposed so onboarding/settings can offer a reset.
    var defaultAppShortcutBindings: [AppShortcutBinding] {
        AppShortcutBinding.defaults
    }

    var defaultNewWindowLaunchRules: [NewWindowLaunchRule] {
        NewWindowLaunchRule.defaults
    }

    @discardableResult
    func addNewWindowLaunchRule(for application: InstalledApplication) -> NewWindowLaunchRule? {
        if newWindowLaunchRule(matching: application) != nil {
            showHUD("\(application.name) already opens new windows")
            return nil
        }

        let rule = NewWindowLaunchRule.from(application: application)
        newWindowLaunchRules = NewWindowLaunchRule.deduplicated(newWindowLaunchRules + [rule])
        showHUD("\(rule.displayName) will open new windows")
        return rule
    }

    func removeNewWindowLaunchRule(id: String) {
        guard let index = newWindowLaunchRules.firstIndex(where: { $0.id == id }) else { return }
        let removed = newWindowLaunchRules.remove(at: index)
        showHUD("\(removed.displayName) will reuse existing windows")
    }

    func resetNewWindowLaunchRulesToDefaults() {
        newWindowLaunchRules = defaultNewWindowLaunchRules
        showHUD("Restored new-window app defaults")
    }

    func appShortcutBinding(withID id: UUID) -> AppShortcutBinding? {
        appShortcutBindings.first { $0.id == id }
    }

    /// The binding whose key matches a pressed board key, if any.
    func appShortcutBinding(forKey key: String) -> AppShortcutBinding? {
        let cleaned = BoardShortcutValidation.clean(key)
        guard !cleaned.isEmpty else { return nil }
        return appShortcutBindings.first { $0.key == cleaned }
    }

    /// Add a binding for an installed application, auto-assigning the first free key.
    /// Returns the created binding, or `nil` if it is already bound or no key is free.
    @discardableResult
    func addAppShortcutBinding(for application: InstalledApplication) -> AppShortcutBinding? {
        if let existing = appShortcutBindings.first(where: { binding in
            if let bundleID = application.bundleIdentifier {
                return binding.bundleIdentifiers.contains(bundleID)
            }
            return binding.appNames.contains { $0.caseInsensitiveCompare(application.name) == .orderedSame }
        }) {
            showHUD("\(existing.displayName) is already bound to \(existing.keyLabel)")
            return nil
        }

        guard let key = firstAvailableShortcutKey() else {
            showHUD("No free keys left. Change or remove one first.")
            return nil
        }

        let binding = AppShortcutBinding(
            displayName: application.name,
            bundleIdentifiers: application.bundleIdentifier.map { [$0] } ?? [],
            appNames: [application.name],
            key: key,
            preferNewWindow: false
        )
        appShortcutBindings.append(binding)
        showHUD("Bound \(binding.displayName) to \(binding.keyLabel)")
        return binding
    }

    func removeAppShortcutBinding(id: UUID) {
        guard let index = appShortcutBindings.firstIndex(where: { $0.id == id }) else { return }
        let removed = appShortcutBindings.remove(at: index)
        showHUD("Removed \(removed.displayName)")
    }

    /// Assign a key to a binding after validating it. Returns the validation result so
    /// the UI can surface the reason inline (reserved key, conflict, etc.).
    @discardableResult
    func setAppShortcutKey(_ pressedCharacter: String, for id: UUID) -> AppShortcutKeyValidation.Result {
        let result = AppShortcutKeyValidation.validate(
            pressedCharacter: pressedCharacter,
            for: id,
            in: appShortcutBindings
        )
        if case .valid(let key) = result,
           let index = appShortcutBindings.firstIndex(where: { $0.id == id }) {
            appShortcutBindings[index].key = key
        }
        return result
    }

    /// Assign `key` to `id`, first clearing it from whichever binding currently holds it.
    /// Used by the "replace" affordance when a conflict is reported.
    func replaceAppShortcutKey(_ pressedCharacter: String, for id: UUID) {
        let cleaned = BoardShortcutValidation.clean(pressedCharacter.lowercased())
        guard cleaned.count == 1,
              !AppShortcutKeyValidation.reservedKeys.contains(cleaned),
              cleaned != "/",
              let targetIndex = appShortcutBindings.firstIndex(where: { $0.id == id }) else {
            return
        }

        var updated = appShortcutBindings
        for index in updated.indices where updated[index].id != id && updated[index].key == cleaned {
            updated[index].key = ""
        }
        updated[targetIndex].key = cleaned
        appShortcutBindings = updated
    }

    func setPreferNewWindow(_ preferNewWindow: Bool, for id: UUID) {
        guard let index = appShortcutBindings.firstIndex(where: { $0.id == id }) else { return }
        appShortcutBindings[index].preferNewWindow = preferNewWindow
    }

    func resetAppShortcutBindingsToDefaults() {
        appShortcutBindings = AppShortcutBinding.defaults
        showHUD("Restored default shortcuts")
    }

    private func launchSpec(for binding: AppShortcutBinding) -> BoardAppShortcutSpec {
        let rule = newWindowLaunchRule(
            matchingBundleIdentifiers: binding.bundleIdentifiers,
            appNames: binding.appNames
        )
        if let rule {
            return rule.launchSpec(
                label: binding.displayName,
                bundleIdentifiers: binding.bundleIdentifiers,
                appNames: binding.appNames
            )
        }
        return BoardAppShortcutSpec(
            label: binding.displayName,
            bundleIdentifiers: binding.bundleIdentifiers,
            appNames: binding.appNames,
            forceNew: false,
            newWindowMenuItemTitles: binding.newWindowMenuItemTitles
        )
    }

    private func launchSpec(for application: InstalledApplication) -> BoardAppShortcutSpec {
        let bundleIdentifiers = application.bundleIdentifier.map { [$0] } ?? []
        let rule = newWindowLaunchRule(matching: application)
        if let rule {
            return rule.launchSpec(
                label: application.name,
                bundleIdentifiers: bundleIdentifiers,
                appNames: [application.name]
            )
        }
        return BoardAppShortcutSpec(
            label: application.name,
            bundleIdentifiers: bundleIdentifiers,
            appNames: [application.name],
            forceNew: false,
            newWindowMenuItemTitles: []
        )
    }

    private func launchSpec(for item: RunningApplicationItem) -> BoardAppShortcutSpec {
        let bundleIdentifiers = item.bundleIdentifier.map { [$0] } ?? []
        if let rule = newWindowLaunchRule(matching: item) {
            return rule.launchSpec(
                label: item.name,
                bundleIdentifiers: bundleIdentifiers,
                appNames: [item.name]
            )
        }
        return BoardAppShortcutSpec(
            label: item.name,
            bundleIdentifiers: bundleIdentifiers,
            appNames: [item.name],
            forceNew: false,
            newWindowMenuItemTitles: []
        )
    }

    private func newWindowLaunchRule(matching application: InstalledApplication) -> NewWindowLaunchRule? {
        newWindowLaunchRules.first { $0.matches(application) }
    }

    private func newWindowLaunchRule(matching item: RunningApplicationItem) -> NewWindowLaunchRule? {
        newWindowLaunchRules.first { $0.matches(item) }
    }

    private func newWindowLaunchRule(
        matchingBundleIdentifiers bundleIdentifiers: [String],
        appNames: [String]
    ) -> NewWindowLaunchRule? {
        newWindowLaunchRules.first {
            $0.matches(bundleIdentifiers: bundleIdentifiers, appNames: appNames)
        }
    }

    private func firstAvailableShortcutKey() -> String? {
        let taken = Set(appShortcutBindings.map(\.key))
        let candidates = (Array("abcdefghijklmnoprstuvwxyz") + Array("0123456789")).map { String($0) }
        return candidates.first { candidate in
            !taken.contains(candidate) && !AppShortcutKeyValidation.reservedKeys.contains(candidate)
        }
    }

    // MARK: - Onboarding

    /// The example binding used by tour step 4 ("Press <key> to open <app>"): the first
    /// LIVE binding that still has a key assigned. Returns `nil` when the user has cleared
    /// every key, so the tour can skip the un-completable shortcut step rather than show a
    /// default key that isn't actually mapped.
    var tourExampleBinding: AppShortcutBinding? {
        appShortcutBindings.first { !$0.key.isEmpty }
    }

    /// Advance the wizard from the welcome screen to the permission checklist.
    func beginOnboardingPermissions() {
        onboardingPhase = .permissions
        advanceOnboardingIfRequiredPermissionsGranted()
    }

    /// Auto-advance the wizard to the summon gate once both required permissions
    /// (Accessibility + Input Monitoring) are granted. Screen Recording is optional.
    private func advanceOnboardingIfRequiredPermissionsGranted() {
        guard isOnboardingWizardActive, onboardingPhase == .permissions else { return }
        guard permissions.isAccessibilityTrusted, permissions.isInputMonitoringTrusted else { return }
        onboardingPhase = .summon
    }

    /// Start the full onboarding flow again from the welcome screen (Settings → General).
    /// Already-granted permission rows simply render as granted.
    func replayOnboarding() {
        if isArrangeBoardVisible {
            closeArrangeBoard()
        }
        tourStep = nil
        onboardingPhase = .welcome
        isOnboardingWizardActive = true
        showMainWindow()
    }

    /// Jump straight into the in-board guided tour ("Replay Board Tour" in the Dex window).
    func replayTour() async {
        isOnboardingWizardActive = false
        tourStep = .navigate
        if !isArrangeBoardVisible {
            await showArrangeBoard()
        }
        // Accessibility may be missing: showArrangeBoard leaves the board hidden.
        if !isArrangeBoardVisible {
            tourStep = nil
        }
    }

    /// If the board was just opened while waiting on the summon gate, hide the wizard
    /// window and drop the user straight into the in-board tour.
    private func beginInBoardTourIfSummoning() {
        guard isArrangeBoardVisible, isOnboardingWizardActive, onboardingPhase == .summon else { return }
        // Persist onboarding completion the moment the user reaches the in-board tour.
        // If they quit before finishing/skipping the tour, the wizard must not re-run
        // the whole flow (Welcome/Permissions) on the next launch.
        finishOnboarding()
        tourStep = .navigate
        hideMainWindow()
    }

    /// Advance the tour when the user performs the action for `step`. No-op if the tour
    /// is on a different step (so repeated/late detections are ignored).
    func advanceTour(from step: OnboardingTourStep) {
        guard tourStep == step else { return }
        guard let next = step.next else {
            completeTour()
            return
        }
        tourStep = next
        // The shortcut step can only be completed by pressing a live, key-bound app.
        // If the user has cleared every shortcut key, skip it rather than stranding them
        // on a step whose instructed key isn't actually mapped.
        if next == .shortcut, tourExampleBinding == nil {
            advanceTour(from: .shortcut)
        }
    }

    /// The user pressed Done on the closing card, or finished the last step.
    func completeTour() {
        tourStep = nil
        finishOnboarding()
        boardLegendSessionsRemaining = Self.boardLegendSessionCount
        updateBoardLegendVisibilityForNewSession()
    }

    /// The user pressed Esc (or a skip link) during the tour.
    func exitTour() {
        guard tourStep != nil else { return }
        tourStep = nil
        finishOnboarding()
        showHUD("Replay the tour anytime from the Dex window")
    }

    func dismissBoardLegend() {
        isBoardLegendVisibleThisSession = false
    }

    /// Persist the onboarding-complete flag. Called on completing or exiting either the
    /// wizard or the tour.
    private func finishOnboarding() {
        isOnboardingWizardActive = false
        if !store.hasCompletedOnboarding {
            store.hasCompletedOnboarding = true
        }
    }

    private var boardLegendSessionsRemaining: Int {
        get { store.boardLegendSessionsRemaining }
        set { store.boardLegendSessionsRemaining = newValue }
    }

    /// Decide whether the reinforcement legend shows for a freshly opened board session.
    private func updateBoardLegendVisibilityForNewSession() {
        guard isArrangeBoardVisible, tourStep == nil, !isOnboardingWizardActive else {
            isBoardLegendVisibleThisSession = false
            return
        }
        guard showsBoardLegend, boardLegendSessionsRemaining > 0 else {
            isBoardLegendVisibleThisSession = false
            return
        }
        isBoardLegendVisibleThisSession = true
        boardLegendSessionsRemaining -= 1
    }

    private func hideMainWindow() {
        for window in NSApp.windows where window.isVisible && window.title == "Dex" {
            window.orderOut(nil)
        }
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Recreate the WindowGroup window if it was closed; this also re-fronts an existing
        // one. Fall back to fronting any live "Dex" window if no action was registered.
        if let openMainWindowAction {
            openMainWindowAction()
        } else {
            for window in NSApp.windows where window.title == "Dex" {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func cycleStack(_ direction: CycleDirection, trigger: CycleTrigger) async {
        await refreshWindows(includeThumbnails: false)
        guard let target = cycleTarget(trigger: trigger) else { return }
        let display = target.display
        let role = target.role
        var state = stackState(for: display.id)
        guard let nextID = state.cycle(role, direction: direction),
              let window = windows.first(where: { $0.id == nextID }) else {
            showHUD("No \(role.title.lowercased()) stack")
            return
        }
        setStackState(state, for: display.id)
        accessibility.moveResize(window, to: grid(for: display).rect(for: role))
        accessibility.raise(window)
        showHUD("\(role.title): \(window.displayTitle)")
    }

    func stackWindows(for role: ColumnRole, displayID: String) -> [ManagedWindow] {
        let ids = stackState(for: displayID).windows(in: role)
        return ids.compactMap { id in windows.first { $0.id == id } }
    }

    func boardWindows(for role: ColumnRole, on display: DisplayInfo) -> [ManagedWindow] {
        let physicalWindows = windows(on: display)
        let state = stackState(for: display.id)
        var seen = Set<String>()

        let ids = state.windowsStartingAtActive(in: role)
        return ids.compactMap { id in
            guard let window = physicalWindows.first(where: { $0.id == id }),
                  seen.insert(id).inserted else {
                return nil
            }
            return window
        }
    }

    func unassignedWindows(on display: DisplayInfo) -> [ManagedWindow] {
        let state = stackState(for: display.id)
        let assigned = Set([
            state
        ].flatMap { state in
            ColumnRole.allCases.flatMap { state.windows(in: $0) }
        })
        return windows(on: display)
            .filter { !assigned.contains($0.id) }
    }

    func diaTabs(for window: ManagedWindow) -> [DiaTab] {
        diaTabsByWindowID[window.id, default: []]
    }

    func diaTabPreview(for tab: DiaTab) -> NSImage? {
        diaTabPreviewCache[tab.id]
    }

    func refreshDiaTabsForPalette() async {
        await refreshDiaTabs()
    }

    func isDisplayActive(_ display: DisplayInfo) -> Bool {
        if let activeBoardDisplayID, isArrangeBoardVisible {
            return display.id == activeBoardDisplayID
        }
        guard !arrangeAllDisplays else { return true }
        return display.id == activeDisplay()?.id
    }

    func displaySwitcherTargets() -> [DisplaySwitcherTarget] {
        let displays = DisplaySwitcher.sortedDisplays(allDisplays())
        let activeDisplayID = activeBoardDisplayID ?? activeDisplay()?.id ?? displays.first?.id
        var targetIndex = 0
        return displays.flatMap { display -> [DisplaySwitcherTarget] in
            let spaceSlots = displays.count == 1 ? MacOSSpaceReader.mainDisplaySlots() : [MacOSSpaceSlot(id: "display-\(display.id)", index: 0, isCurrent: true)]

            return spaceSlots.map { slot in
                defer { targetIndex += 1 }
                let targetID = "\(display.id):\(slot.id)"
                let layoutSpaceID = displays.count == 1 ? slot.id : activeLayoutSpaceID()
                let state = stackState(for: display.id, spaceID: layoutSpaceID)
                let kind = layoutKind(for: display.id, spaceID: layoutSpaceID)
                let roles = GridLayout(visibleFrame: display.visibleFrame, kind: kind).roles
                let assignedCounts = Dictionary(uniqueKeysWithValues: roles.map { role in
                    (role, state.windows(in: role).count)
                })
                let assignedIDs = Set(ColumnRole.allCases.flatMap { state.windows(in: $0) })
                let unassignedCount = windows(on: display).filter { !assignedIDs.contains($0.id) }.count
                return DisplaySwitcherTarget(
                    id: targetID,
                    displayID: display.id,
                    displayName: display.name,
                    spaceID: slot.id,
                    index: targetIndex,
                    spaceIndex: slot.index,
                    frame: display.frame,
                    isActive: display.id == activeDisplayID && slot.isCurrent,
                    assignedCounts: assignedCounts,
                    unassignedCount: unassignedCount
                )
            }
        }
    }

    @discardableResult
    func moveBoardWindowAcrossDisplayEdge(
        windowID: String,
        from displayID: String,
        direction: DisplaySwitchDirection
    ) -> (displayID: String, role: ColumnRole)? {
        guard let target = DisplaySwitcher.edgeMoveTarget(
            currentDisplayID: displayID,
            direction: direction,
            displays: allDisplays()
        ) else {
            if allDisplays().count == 1, MacOSSpaceReader.mainDisplaySlots().count > 1 {
                showHUD("Window moves between Spaces need Mission Control")
            } else {
                showHUD("No display in that direction")
            }
            return nil
        }
        let targetRole = display(withID: target.displayID)
            .map { grid(for: $0).edgeRole(for: direction == .left ? .right : .left) } ?? target.role

        activeBoardDesktopID = nil
        pendingBoardFocusRequest = .assigned(targetRole, windowID)
        let previousWorkspaceStacks = stacksByWorkspace
        let previousDisplayStacks = stacksByDisplay
        let didMove = assign(windowID: windowID, to: targetRole, displayID: target.displayID)
        guard didMove else {
            stacksByWorkspace = previousWorkspaceStacks
            stacksByDisplay = previousDisplayStacks
            saveAllStackStores()
            pendingBoardFocusRequest = nil
            activeBoardDisplayID = displayID
            showHUD("macOS did not move that window")
            return nil
        }

        activeBoardDisplayID = target.displayID
        if let display = display(withID: target.displayID), isArrangeBoardVisible {
            overlayController.showArrangeBoard(
                model: self,
                displays: [display],
                presentationMode: boardPresentationMode
            )
            refocusArrangeBoardIfNeeded()
        }
        return (target.displayID, targetRole)
    }

    func consumePendingBoardFocusRequest() -> BoardFocusRequest? {
        let request = pendingBoardFocusRequest
        pendingBoardFocusRequest = nil
        return request
    }

    private func stackState(for displayID: String, spaceID: String? = nil) -> ColumnStackState {
        WorkspaceStackResolver.state(
            displayID: displayID,
            spaceID: spaceID ?? activeLayoutSpaceID(),
            workspaceStacks: stacksByWorkspace,
            legacyStacks: stacksByDisplay
        )
    }

    private func setStackState(
        _ state: ColumnStackState,
        for displayID: String,
        spaceID: String? = nil,
        save: Bool = true
    ) {
        let key = workspaceKey(for: displayID, spaceID: spaceID)
        stacksByWorkspace[key] = state
        if save {
            store.saveWorkspaceStacks(stacksByWorkspace)
        }
    }

    private func workspaceKey(for displayID: String, spaceID: String? = nil) -> String {
        LayoutWorkspaceID(displayID: displayID, spaceID: spaceID ?? activeLayoutSpaceID()).rawValue
    }

    private func layoutMemoryKey(workspaceKey: String, kind: BoardLayoutKind) -> String {
        "\(workspaceKey)\u{1F}layout:\(kind.rawValue)"
    }

    private func activeLayoutSpaceID() -> String {
        MacOSSpaceReader.currentMainDisplaySpaceID() ?? LayoutWorkspaceID.visibleSpaceID
    }

    private func saveWorkspaceStacks() {
        store.saveWorkspaceStacks(stacksByWorkspace)
    }

    private func saveAllStackStores() {
        store.saveWorkspaceStacks(stacksByWorkspace)
        store.saveStacks(stacksByDisplay)
    }

    @discardableResult
    private func reflowCurrentWorkspaceStack(
        for displayID: String,
        workspaceKey: String,
        previousGrid: GridLayout,
        nextGrid: GridLayout
    ) -> Bool {
        var state = stackState(for: displayID)
        let previousState = state
        let visibleWindowIDs = Set(windows(on: displayID).map(\.id))
        let shouldFilterToVisibleWindows = !visibleWindowIDs.isEmpty || !isArrangeBoardVisible
        if !isArrangeBoardVisible {
            state.prune(keeping: visibleWindowIDs)
        }
        stacksByWorkspace[layoutMemoryKey(workspaceKey: workspaceKey, kind: previousGrid.kind)] = state

        var rememberedState = stacksByWorkspace[
            layoutMemoryKey(workspaceKey: workspaceKey, kind: nextGrid.kind),
            default: ColumnStackState()
        ]
        if shouldFilterToVisibleWindows {
            rememberedState.prune(keeping: visibleWindowIDs)
        }

        var nextState = rememberedState.filtered(to: nextGrid.roles)
        var assignedIDs = Set(nextState.orderedWindowIDs(preferredRoles: nextGrid.roles))
        let orderedIDs = state.orderedWindowIDs(preferredRoles: previousGrid.roles)
        for windowID in orderedIDs {
            guard (!shouldFilterToVisibleWindows || visibleWindowIDs.contains(windowID)),
                  !assignedIDs.contains(windowID),
                  let previousRole = state.column(containing: windowID) else {
                continue
            }

            let point = windows.first(where: { $0.id == windowID })?.frame.center ??
                previousGrid.rect(for: previousRole).center
            guard let role = nextGrid.nearestHorizontallyCompatibleRole(
                to: point,
                from: previousRole,
                in: previousGrid
            ) else {
                continue
            }
            nextState.assign(windowID, to: role)
            assignedIDs.insert(windowID)
        }

        stacksByWorkspace[workspaceKey] = nextState
        stacksByWorkspace[layoutMemoryKey(workspaceKey: workspaceKey, kind: nextGrid.kind)] = nextState
        return nextState != previousState
    }

    private func refreshWindows(includeThumbnails: Bool, pruneMissingWindows: Bool = true) async {
        let raw = accessibility.visibleWindows(excluding: Bundle.main.bundleIdentifier)
        if includeThumbnails {
            windows = await thumbnails.attachThumbnails(to: raw)
            cacheFocusedDiaTabPreviews()
        } else {
            let existingThumbnails = WindowThumbnailCache.make(from: windows)
            windows = raw.map { window in
                var preserved = window
                preserved.thumbnail = existingThumbnails[window.id]
                return preserved
            }
        }

        if pruneMissingWindows {
            pruneStacksForVisibleWindowsIfSafe()
        }
    }

    private func refreshDiaTabs() async {
        let tabs = await diaTabs.tabsByWindowID(for: windows)
        diaTabsByWindowID = tabs
        cacheFocusedDiaTabPreviews()
    }

    private func startActiveSpaceObserver() {
        guard activeSpaceObserver == nil else { return }
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleArrangeBoardSpaceRefresh()
            }
        }
    }

    private func startArrangeBoardSpaceRefreshLoop() {
        lastObservedMainSpaceID = MacOSSpaceReader.currentMainDisplaySpaceID()
        boardSpacePollTask?.cancel()
        boardSpacePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                await self?.refreshArrangeBoardIfCurrentSpaceChanged()
            }
        }
    }

    private func stopArrangeBoardSpaceRefreshLoop() {
        boardSpacePollTask?.cancel()
        boardSpacePollTask = nil
        pendingBoardSpaceRefreshTask?.cancel()
        pendingBoardSpaceRefreshTask = nil
        lastObservedMainSpaceID = nil
    }

    private func scheduleArrangeBoardSpaceRefresh() {
        guard isArrangeBoardVisible else { return }
        pendingBoardSpaceRefreshTask?.cancel()
        pendingBoardSpaceRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.refreshArrangeBoardIfCurrentSpaceChanged(force: true)
        }
    }

    private func refreshArrangeBoardIfCurrentSpaceChanged(force: Bool = false) async {
        guard isArrangeBoardVisible else { return }
        let currentSpaceID = MacOSSpaceReader.currentMainDisplaySpaceID()
        guard force || currentSpaceID != lastObservedMainSpaceID else { return }
        lastObservedMainSpaceID = currentSpaceID

        if let activeTarget = displaySwitcherTargets().first(where: \.isActive) {
            activeBoardDisplayID = activeTarget.displayID
            activeBoardDesktopID = activeTarget.id
        }
        let previousWindows = windows
        await refreshWindowsUntilStableForLayoutRead()
        _ = repairStacksFromWindowPositionsIfNeeded(
            for: boardDisplays(),
            previousWindows: previousWindows
        )
        await refreshDiaTabs()
        await refreshWindows(includeThumbnails: true)
        await refreshDiaTabs()
        refocusArrangeBoardIfNeeded()
    }

    private func refreshWindowsUntilStableForLayoutRead() async {
        // Space changes can briefly produce partial AX snapshots; probe reads must not erase saved layout memory.
        var previousIDs: Set<String>?
        for _ in 0..<4 {
            await refreshWindows(includeThumbnails: false, pruneMissingWindows: false)
            let ids = Set(windows.map(\.id))
            if !ids.isEmpty, ids == previousIDs {
                return
            }
            previousIDs = ids
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    private func cacheFocusedDiaTabPreviews() {
        var cache = diaTabPreviewCache
        for window in windows where window.bundleIdentifier == "company.thebrowser.dia" {
            guard let thumbnail = window.thumbnail,
                  let focusedTab = diaTabsByWindowID[window.id, default: []].first(where: \.isFocused) else {
                continue
            }
            cache[focusedTab.id] = thumbnail
        }
        diaTabPreviewCache = cache
    }

    private func diaTab(withID tabID: String) -> DiaTab? {
        diaTabsByWindowID.values.flatMap { $0 }.first { $0.id == tabID }
    }

    private func firstWindow(matching item: RunningApplicationItem) -> ManagedWindow? {
        windows.first { windowMatches($0, item: item) }
    }

    private func windowMatches(_ window: ManagedWindow, item: RunningApplicationItem) -> Bool {
        if let bundleIdentifier = item.bundleIdentifier,
           window.bundleIdentifier == bundleIdentifier {
            return true
        }

        if window.pid == item.processIdentifier {
            return true
        }

        return window.appName.localizedCaseInsensitiveContains(item.name)
    }

    private func capturedModeWindows(displayID: String) -> [ColumnRole: [SavedModeWindow]] {
        guard let display = display(withID: displayID) else { return [:] }
        let grid = grid(for: display)
        var captured: [ColumnRole: [SavedModeWindow]] = [:]
        for role in grid.roles {
            let liveWindows = boardWindows(for: role, on: display)
            captured[role] = liveWindows.enumerated().map { index, window in
                SavedModeWindow(
                    id: UUID(),
                    role: role,
                    order: index,
                    bundleIdentifier: window.bundleIdentifier,
                    appName: window.appName,
                    titleHint: window.title
                )
            }
        }
        return captured
    }

    private func activateModeFromCurrentArrangement(_ mode: SavedMode, displayID: String) {
        guard let display = display(withID: displayID) else { return }
        let bindings = grid(for: display).roles.flatMap { role in
            boardWindows(for: role, on: display).map { window in
                ActiveModeWindowBinding(
                    windowID: window.id,
                    role: role,
                    appName: window.appName,
                    bundleIdentifier: window.bundleIdentifier
                )
            }
        }
        guard !bindings.isEmpty else { return }

        let instance = ActiveModeInstance(
            id: UUID(),
            modeID: mode.id,
            modeName: mode.name,
            slot: mode.slot,
            displayID: displayID,
            spaceID: activeLayoutSpaceID(),
            windowBindings: bindings,
            startedAt: Date()
        )
        activeModeInstances.removeAll { existing in
            existing.modeID == mode.id &&
                existing.displayID == displayID &&
                existing.spaceID == instance.spaceID
        }
        activeModeInstances.append(instance)
    }

    private func selectedLaunchPolicy() -> ModeLaunchPolicy {
        if case .confirming(_, let policy, _) = modeLaunchConfirmation {
            return policy
        }
        return .quitElsewhereAndReopenHere
    }

    private func confirmOrLaunchMode(_ mode: SavedMode, policy: ModeLaunchPolicy) async {
        if case .confirming(let armedMode, let armedPolicy, let armedAt) = modeLaunchConfirmation,
           armedMode.id == mode.id,
           Date().timeIntervalSince(armedAt) <= 4 {
            modeLaunchConfirmation = .idle
            await launchMode(mode, policy: armedPolicy)
            return
        }

        modeLaunchConfirmation = .confirming(mode: mode, policy: policy, armedAt: Date())
        showHUD("Press \(mode.shortcutLabel) again to launch \(mode.name)")
    }

    private func launchMode(_ mode: SavedMode, policy: ModeLaunchPolicy) async {
        guard permissions.isAccessibilityTrusted else {
            showHUD("Grant Accessibility first")
            return
        }
        guard let display = activeDisplay() ?? allDisplays().first else {
            showHUD("No display available")
            return
        }

        await refreshWindows(includeThumbnails: false)
        layoutKindsByWorkspace[workspaceKey(for: display.id)] = mode.layoutKind
        store.saveDisplayLayoutKinds(layoutKindsByWorkspace)
        var usedWindowIDs = Set<String>()
        var bindings: [ActiveModeWindowBinding] = []

        for target in mode.windows.sorted(by: { lhs, rhs in
            if lhs.role == rhs.role {
                return lhs.order < rhs.order
            }
            let roles = mode.layoutKind.roles
            let lhsIndex = roles.firstIndex(of: lhs.role) ?? 0
            let rhsIndex = roles.firstIndex(of: rhs.role) ?? 0
            return lhsIndex < rhsIndex
        }) {
            if policy == .quitElsewhereAndReopenHere,
               firstModeWindow(matching: target, excluding: usedWindowIDs) == nil {
                terminateRunningApplication(matching: target)
                try? await Task.sleep(nanoseconds: 180_000_000)
                await refreshWindows(includeThumbnails: false)
            }

            let window: ManagedWindow?
            if policy == .openNewHere {
                window = await openModeWindow(target, forceNew: true)
            } else if let existing = firstModeWindow(matching: target, excluding: usedWindowIDs) {
                window = existing
            } else {
                window = await openModeWindow(target, forceNew: false)
            }

            guard let window else { continue }
            usedWindowIDs.insert(window.id)
            assign(windowID: window.id, to: target.role, displayID: display.id)
            bindings.append(
                ActiveModeWindowBinding(
                    windowID: window.id,
                    role: target.role,
                    appName: window.appName,
                    bundleIdentifier: window.bundleIdentifier
                )
            )
        }

        guard !bindings.isEmpty else {
            showHUD("Could not launch \(mode.name)")
            return
        }

        arrangeAssignedWindows(displayIDs: Set([display.id]), raiseActiveWindows: true)
        let instance = ActiveModeInstance(
            id: UUID(),
            modeID: mode.id,
            modeName: mode.name,
            slot: mode.slot,
            displayID: display.id,
            spaceID: activeLayoutSpaceID(),
            windowBindings: bindings,
            startedAt: Date()
        )
        activeModeInstances.removeAll { existing in
            existing.modeID == mode.id &&
                existing.displayID == instance.displayID &&
                existing.spaceID == instance.spaceID
        }
        activeModeInstances.append(instance)
        showHUD("\(mode.name) active")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await refreshWindows(includeThumbnails: true)
            await refreshDiaTabs()
            refocusArrangeBoardIfNeeded()
        }
    }

    private func firstModeWindow(matching target: SavedModeWindow, excluding usedWindowIDs: Set<String>) -> ManagedWindow? {
        windows.first { window in
            !usedWindowIDs.contains(window.id) && modeWindow(window, matches: target)
        }
    }

    private func modeWindow(_ window: ManagedWindow, matches target: SavedModeWindow) -> Bool {
        if window.bundleIdentifier == target.bundleIdentifier {
            return true
        }
        if window.appName.localizedCaseInsensitiveContains(target.appName) {
            return true
        }
        guard !target.titleHint.isEmpty else { return false }
        return window.title.localizedCaseInsensitiveContains(target.titleHint)
    }

    private func openModeWindow(_ target: SavedModeWindow, forceNew: Bool) async -> ManagedWindow? {
        let snapshot = BoardWindowLaunchSnapshot(windows: windows.filter { modeWindow($0, matches: target) })
        if !target.bundleIdentifier.isEmpty {
            _ = launchWithOpen(arguments: forceNew ? ["-n", "-b", target.bundleIdentifier] : ["-b", target.bundleIdentifier])
        } else {
            _ = launchWithOpen(arguments: forceNew ? ["-n", "-a", target.appName] : ["-a", target.appName])
        }
        return await waitForModeWindow(matching: target, excluding: snapshot)
    }

    private func waitForModeWindow(
        matching target: SavedModeWindow,
        excluding snapshot: BoardWindowLaunchSnapshot
    ) async -> ManagedWindow? {
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            await refreshWindows(includeThumbnails: true)
            if let launched = windows.first(where: { modeWindow($0, matches: target) && !snapshot.contains($0) }) {
                return launched
            }
            if let existing = windows.first(where: { modeWindow($0, matches: target) }) {
                return existing
            }
        }
        return nil
    }

    private func terminateRunningApplication(matching target: SavedModeWindow) {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if app.bundleIdentifier == target.bundleIdentifier ||
                (app.localizedName?.localizedCaseInsensitiveContains(target.appName) == true) {
                app.terminate()
            }
        }
    }

    private func removeActiveModeInstance(id: UUID) {
        activeModeInstances.removeAll { $0.id == id }
    }

    private func waitForLaunchedWindow(
        matching spec: BoardAppShortcutSpec,
        excluding snapshot: BoardWindowLaunchSnapshot
    ) async -> ManagedWindow? {
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            await refreshWindows(includeThumbnails: true)
            if let launched = spec.firstNewWindow(in: windows, excluding: snapshot) {
                return launched
            }
        }
        return nil
    }

    private func openNewWindowUsingAppCommandIfAvailable(
        _ spec: BoardAppShortcutSpec,
        excluding snapshot: BoardWindowLaunchSnapshot
    ) async -> ManagedWindow? {
        guard spec.forceNew else {
            return nil
        }

        if !spec.newWindowMenuItemTitles.isEmpty,
           accessibility.pressNewWindowMenuItem(
            bundleIdentifiers: spec.bundleIdentifiers,
            appNames: spec.appNames,
            itemTitles: spec.newWindowMenuItemTitles
        ), let launched = await waitForLaunchedWindow(matching: spec, excluding: snapshot) {
            return launched
        }

        if accessibility.postNewWindowKeyboardShortcut(
            bundleIdentifiers: spec.bundleIdentifiers,
            appNames: spec.appNames
        ), let launched = await waitForLaunchedWindow(matching: spec, excluding: snapshot) {
            return launched
        }

        return nil
    }

    private func refreshThumbnailsAfterWindowGeometryChange() {
        guard isArrangeBoardVisible else { return }
        thumbnailRefreshTask?.cancel()
        thumbnailRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshWindows(includeThumbnails: true)
            self?.refocusArrangeBoardIfNeeded()
        }
    }

    private func pruneStacksForVisibleWindowsIfSafe() {
        // Keep board assignments stable while the board is open; AX refreshes can briefly miss moved windows.
        guard !isArrangeBoardVisible else { return }

        for display in allDisplays() {
            var state = stackState(for: display.id)
            state.prune(keeping: Set(windows(on: display).map(\.id)))
            setStackState(state, for: display.id, save: false)
        }
        saveWorkspaceStacks()
    }

    private func repairStacksFromWindowPositionsIfNeeded(
        for displays: [DisplayInfo],
        previousWindows: [ManagedWindow] = []
    ) -> Set<String> {
        var repairedDisplayIDs = Set<String>()
        for display in displays {
            let existing = stackState(for: display.id)
            let repaired = ColumnStackInference.repairedState(
                existing: existing,
                windows: windows(on: display),
                previousWindows: previousWindows.filter { displayID(for: $0) == display.id },
                visibleFrame: display.visibleFrame,
                grid: grid(for: display),
                allowsInitialInference: stacksByWorkspace[workspaceKey(for: display.id)] == nil &&
                    stacksByDisplay[display.id] == nil
            )
            guard repaired != existing else {
                continue
            }
            setStackState(repaired, for: display.id, save: false)
            repairedDisplayIDs.insert(display.id)
        }
        if !repairedDisplayIDs.isEmpty {
            saveWorkspaceStacks()
        }
        return repairedDisplayIDs
    }

    @discardableResult
    private func arrangeAssignedWindows(displayIDs: Set<String>? = nil, raiseActiveWindows: Bool = true) -> Bool {
        let displays = displayIDs == nil
            ? targetDisplays()
            : allDisplays().filter { displayIDs?.contains($0.id) == true }
        var allMovesSucceeded = true
        for display in displays {
            if let displayIDs, !displayIDs.contains(display.id) {
                continue
            }
            var state = stackState(for: display.id)
            if !isArrangeBoardVisible {
                state.prune(keeping: Set(windows(on: display).map(\.id)))
                setStackState(state, for: display.id, save: false)
            }

            let grid = grid(for: display)
            for role in grid.roles {
                let rect = grid.rect(for: role)
                let stack = state.windows(in: role)
                for windowID in stack {
                    guard let window = windows.first(where: { $0.id == windowID }) else { continue }
                    if !accessibility.moveResize(window, to: rect) {
                        allMovesSucceeded = false
                    }
                }
                if raiseActiveWindows,
                   let activeID = state.activeWindowID(in: role),
                   let active = windows.first(where: { $0.id == activeID }) {
                    accessibility.raise(active)
                }
            }
        }
        saveWorkspaceStacks()
        return allMovesSucceeded
    }

    private func refocusArrangeBoardIfNeeded() {
        guard isArrangeBoardVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overlayController.refocusArrangeBoard(
                preferredDisplayID: self.activeBoardDisplayID
            )
        }
    }

    private func updateControlDrag(at point: CGPoint) {
        guard let display = display(containing: point) else { return }
        overlayController.showSnapOverlay(model: self, displays: [display])
        hoveredSnapRole = grid(for: display).nearestRole(to: point)
    }

    private func finishControlDrag(at point: CGPoint) async {
        overlayController.closeSnapOverlay()
        hoveredSnapRole = nil
        await refreshWindows(includeThumbnails: false)
        guard let display = display(containing: point),
              let frontmost = windows.first(where: { $0.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier }) else {
            return
        }
        let role = grid(for: display).nearestRole(to: point)
        assign(windowID: frontmost.id, to: role, displayID: display.id)
        showHUD("Snapped to \(role.title)")
    }

    private func targetDisplays() -> [DisplayInfo] {
        let displays = allDisplays()
        guard !arrangeAllDisplays else { return displays }
        if let active = activeDisplay() {
            return [active]
        }
        return displays.prefix(1).map { $0 }
    }

    private func boardDisplays() -> [DisplayInfo] {
        let displays = allDisplays()
        if let activeBoardDisplayID,
           let display = displays.first(where: { $0.id == activeBoardDisplayID }) {
            return [display]
        }
        if let active = activeDisplay() {
            activeBoardDisplayID = active.id
            return [active]
        }
        if let first = displays.first {
            activeBoardDisplayID = first.id
            return [first]
        }
        return []
    }

    private func allDisplays() -> [DisplayInfo] {
        NSScreen.screens.map(DisplayInfo.init(screen:))
    }

    private func activeDisplay() -> DisplayInfo? {
        let pointer = NSEvent.mouseLocation
        if let pointerDisplay = display(containing: pointer) {
            return pointerDisplay
        }

        if let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let window = windows.first(where: { $0.pid == frontmostPID }) {
            return display(containing: CGPoint(x: window.frame.midX, y: window.frame.midY))
        }

        return NSScreen.main.map(DisplayInfo.init(screen:))
    }

    private func display(withID id: String) -> DisplayInfo? {
        allDisplays().first { $0.id == id }
    }

    private func display(containing point: CGPoint) -> DisplayInfo? {
        allDisplays()
            .first { $0.frame.contains(point) }
    }

    private func windows(on display: DisplayInfo) -> [ManagedWindow] {
        windows.filter { displayID(for: $0) == display.id }
    }

    private func windows(on displayID: String) -> [ManagedWindow] {
        guard let display = display(withID: displayID) else { return windows }
        return windows(on: display)
    }

    private func assignedBoardFrame(windowID: String, on display: DisplayInfo) -> CGRect? {
        let grid = grid(for: display)
        guard let role = stackState(for: display.id).column(containing: windowID),
              grid.roles.contains(role) else {
            return nil
        }
        return grid.rect(for: role)
    }

    private func displayID(for window: ManagedWindow) -> String? {
        allDisplays()
            .compactMap { display -> (DisplayInfo, CGFloat)? in
                let intersection = display.frame.intersection(window.frame)
                guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
                    return nil
                }
                return (display, intersection.width * intersection.height)
            }
            .max { $0.1 < $1.1 }?
            .0
            .id
    }

    private func removeWindowFromAllStacks(_ windowID: String) {
        windowTransformStates.removeValue(forKey: windowID)
        for key in Array(stacksByWorkspace.keys) {
            var state = stacksByWorkspace[key, default: ColumnStackState()]
            state.remove(windowID)
            stacksByWorkspace[key] = state
        }
        for displayID in Array(stacksByDisplay.keys) {
            var state = stacksByDisplay[displayID, default: ColumnStackState()]
            state.remove(windowID)
            stacksByDisplay[displayID] = state
        }
    }

    private func removeWindowFromActiveWorkspaceStacks(_ windowID: String) {
        for display in allDisplays() {
            let activeWorkspaceKey = workspaceKey(for: display.id)
            if stacksByWorkspace[activeWorkspaceKey] == nil {
                stacksByWorkspace[activeWorkspaceKey] = stackState(for: display.id)
            }
            stacksByWorkspace = WorkspaceStackMutation.removingWindow(
                windowID,
                fromWorkspace: activeWorkspaceKey,
                in: stacksByWorkspace
            )
        }
    }

    private func promoteWindowInExistingStack(_ windowID: String) {
        for display in allDisplays() {
            var state = stackState(for: display.id)
            if let role = state.column(containing: windowID) {
                state.promote(windowID, in: role)
                setStackState(state, for: display.id)
                return
            }
        }

        for key in Array(stacksByWorkspace.keys) {
            var state = stacksByWorkspace[key, default: ColumnStackState()]
            if let role = state.column(containing: windowID) {
                state.promote(windowID, in: role)
                stacksByWorkspace[key] = state
                saveWorkspaceStacks()
                return
            }
        }
    }

    private func launch(_ spec: BoardAppShortcutSpec, url: URL? = nil) -> Bool {
        if spec.forceNew {
            for bundleID in spec.bundleIdentifiers {
                if launchWithOpen(arguments: ["-n", "-b", bundleID]) {
                    return true
                }
            }

            if let url, launchWithOpen(arguments: ["-n", url.path]) {
                return true
            }

            for name in spec.appNames {
                if launchWithOpen(arguments: ["-na", name]) {
                    return true
                }
            }

            return false
        }

        if let url {
            NSWorkspace.shared.open(url)
            return true
        }

        for bundleID in spec.bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open(url)
                return true
            }
        }

        for name in spec.appNames {
            if launchWithOpen(arguments: ["-a", name]) {
                return true
            }
        }

        return false
    }

    private func launchWithOpen(arguments: [String]) -> Bool {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = arguments
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private func cycleTarget(trigger: CycleTrigger) -> (display: DisplayInfo, role: ColumnRole)? {
        let pointer = NSEvent.mouseLocation
        if let display = display(containing: pointer) {
            return (display, grid(for: display).nearestRole(to: pointer))
        }

        if trigger == .keyboard,
           let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let window = windows.first(where: { $0.pid == frontmostPID }),
           let display = display(containing: window.frame.center) {
            let state = stackState(for: display.id)
            let grid = grid(for: display)
            let roles = grid.roles + ColumnRole.allCases.filter { !grid.roles.contains($0) }
            if let assignedRole = roles.first(where: { state.windows(in: $0).contains(window.id) }) {
                return (display, assignedRole)
            }
            return (display, grid.nearestRole(to: window.frame.center))
        }

        if let display = activeDisplay() {
            let grid = grid(for: display)
            return (display, grid.roles.first ?? .center)
        }

        return nil
    }

    private func showHUD(_ text: String) {
        hudTask?.cancel()
        hudText = text
        hudTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            await MainActor.run {
                self?.hudText = nil
            }
        }
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
