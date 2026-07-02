import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var windows: [ManagedWindow] = []
    @Published var stacksByDisplay: [String: ColumnStackState] = [:]
    @Published private var stacksByWorkspace: [String: ColumnStackState] = [:]
    @Published var arrangeAllDisplays: Bool {
        didSet {
            store.arrangeAllDisplays = arrangeAllDisplays
        }
    }
    @Published var boardShortcutMappings: [BoardAppShortcut: String] {
        didSet {
            store.saveShortcutMappings(boardShortcutMappings)
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

    init() {
        self.arrangeAllDisplays = store.arrangeAllDisplays
        self.stacksByDisplay = store.loadStacks()
        self.stacksByWorkspace = store.loadWorkspaceStacks()
        self.boardShortcutMappings = store.loadShortcutMappings()
        self.savedModes = store.loadSavedModes()
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
        overlayController.showArrangeBoard(model: self, displays: displays)
        isArrangeBoardVisible = true
        startArrangeBoardSpaceRefreshLoop()

        Task { @MainActor in
            await refreshWindows(includeThumbnails: true)
            await refreshDiaTabs()
        }
    }

    func closeArrangeBoard() {
        overlayController.closeArrangeBoard()
        stopArrangeBoardSpaceRefreshLoop()
        activeBoardDisplayID = nil
        activeBoardDesktopID = nil
        isArrangeBoardVisible = false
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

    func modeCapturePreview(displayID: String) -> ModeCapturePreview {
        ModeCapturePreview(windowsByRole: capturedModeWindows(displayID: displayID))
    }

    @discardableResult
    func saveMode(name rawName: String, replacing existingID: UUID?, displayID: String) -> SavedMode? {
        let cleanedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleanedName.isEmpty ? "Mode \(savedModes.count + 1)" : cleanedName
        let captured = capturedModeWindows(displayID: displayID)
        let windows = ColumnRole.allCases.flatMap { role in
            captured[role, default: []]
        }

        guard !windows.isEmpty else {
            showHUD("Assign windows before saving a mode")
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
            windows: windows,
            createdAt: createdAt,
            updatedAt: now
        )
        modes.append(mode)
        savedModes = modes.sorted { lhs, rhs in lhs.slot < rhs.slot }
        store.saveSavedModes(savedModes)
        showHUD("\(mode.name) saved as \(mode.shortcutLabel)")
        refocusArrangeBoardIfNeeded()
        return mode
    }

    func mode(forSlot slot: Int) -> SavedMode? {
        savedModes.first { $0.slot == slot }
    }

    func handleModeHotkey(slot: Int) async {
        guard let mode = mode(forSlot: slot) else {
            showHUD("No mode saved for Option+\(slot)")
            return
        }
        await confirmOrLaunchMode(mode, policy: selectedLaunchPolicy())
    }

    func prepareModeLaunch(slot: Int) {
        guard let mode = mode(forSlot: slot) else {
            showHUD("No mode saved for Option+\(slot)")
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
            showHUD("Mode is no longer active")
            return
        }
        let liveWindows = instance.windowBindings.compactMap { binding in
            windows.first { $0.id == binding.windowID }
        }
        guard !liveWindows.isEmpty else {
            removeActiveModeInstance(id: id)
            showHUD("Mode windows are gone")
            return
        }

        for window in liveWindows {
            if let binding = instance.windowBindings.first(where: { $0.windowID == window.id }),
               let display = display(withID: instance.displayID) {
                accessibility.moveResize(window, to: display.grid.rect(for: binding.role))
            }
        }
        for role in [ColumnRole.left, .right, .center] {
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

        for window in liveWindows {
            accessibility.closeWindowOnly(window)
            removeWindowFromAllStacks(window.id)
        }

        removeActiveModeInstance(id: id)
        saveAllStackStores()
        showHUD("Closed \(instance.modeName)")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await refreshWindows(includeThumbnails: true)
            refocusArrangeBoardIfNeeded()
        }
    }

    @discardableResult
    func assign(windowID: String, to role: ColumnRole, displayID: String) -> Bool {
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
        assign(windowID: windowID, to: display.grid.nearestRole(to: screenPoint), displayID: display.id)
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
        let visibleAppWindowCount = windows.filter { $0.pid == window.pid }.count
        if visibleAppWindowCount <= 1,
           let app = NSRunningApplication(processIdentifier: window.pid) {
            app.terminate()
            showHUD("Quit \(window.appName)")
        } else {
            accessibility.close(window)
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
                accessibility.close(window)
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

    func openShortcut(_ shortcut: BoardAppShortcut, in role: ColumnRole, displayID: String) async {
        let spec = shortcut.spec
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

        guard launch(spec) else {
            showHUD("Could not open \(spec.label)")
            return
        }

        let launched = await waitForLaunchedWindow(matching: spec, excluding: launchSnapshot)
        if let launched {
            assign(windowID: launched.id, to: role, displayID: displayID)
            accessibility.raise(launched)
            showHUD("Opened \(spec.label) in \(role.title)")
            refocusArrangeBoardIfNeeded()
        } else {
            if let launched = await openNewWindowUsingAppCommandIfAvailable(spec, excluding: launchSnapshot) {
                assign(windowID: launched.id, to: role, displayID: displayID)
                accessibility.raise(launched)
                showHUD("Opened \(spec.label) in \(role.title)")
                refocusArrangeBoardIfNeeded()
            } else {
                showHUD(spec.forceNew ? "Could not open new \(spec.label) window" : "Opened \(spec.label)")
                refocusArrangeBoardIfNeeded()
            }
        }
    }

    func installedApplications() -> [InstalledApplication] {
        applicationCatalog.installedApplications()
    }

    func loadInstalledApplications() async -> [InstalledApplication] {
        await Task.detached(priority: .userInitiated) { [applicationCatalog] in
            applicationCatalog.installedApplications()
        }.value
    }

    func openApplication(_ application: InstalledApplication, in role: ColumnRole, displayID: String) async {
        await refreshWindows(includeThumbnails: false)
        if let existing = windows.first(where: { window in
            if let bundleIdentifier = application.bundleIdentifier,
               window.bundleIdentifier == bundleIdentifier {
                return true
            }
            return window.appName.localizedCaseInsensitiveContains(application.name)
        }) {
            assign(windowID: existing.id, to: role, displayID: displayID)
            accessibility.raise(existing)
            showHUD("Moved \(application.name) to \(role.title)")
            refocusArrangeBoardIfNeeded()
            return
        }

        NSWorkspace.shared.open(application.url)
        try? await Task.sleep(nanoseconds: 900_000_000)
        await refreshWindows(includeThumbnails: true)
        if let launched = windows.first(where: { window in
            if let bundleIdentifier = application.bundleIdentifier,
               window.bundleIdentifier == bundleIdentifier {
                return true
            }
            return window.appName.localizedCaseInsensitiveContains(application.name)
        }) {
            assign(windowID: launched.id, to: role, displayID: displayID)
            accessibility.raise(launched)
            showHUD("Opened \(application.name) in \(role.title)")
            refocusArrangeBoardIfNeeded()
        } else {
            showHUD("Opened \(application.name)")
            refocusArrangeBoardIfNeeded()
        }
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

    func shortcut(for shortcut: BoardAppShortcut) -> String {
        boardShortcutMappings[shortcut] ?? shortcut.defaultKeySequence
    }

    func setShortcut(_ shortcut: BoardAppShortcut, sequence: String) {
        let cleaned = BoardShortcutValidation.clean(sequence)
        let resolved = cleaned.isEmpty ? shortcut.defaultKeySequence : cleaned
        var candidate = boardShortcutMappings
        candidate[shortcut] = resolved

        guard BoardShortcutValidation.isValid(resolved, for: shortcut, in: candidate) else {
            showHUD("Shortcut \(resolved.uppercased()) conflicts")
            return
        }

        boardShortcutMappings = candidate
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
        accessibility.moveResize(window, to: display.grid.rect(for: role))
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
                let layoutSpaceID = displays.count == 1 ? slot.id : LayoutWorkspaceID.visibleSpaceID
                let state = stackState(for: display.id, spaceID: layoutSpaceID)
                let assignedCounts = Dictionary(uniqueKeysWithValues: ColumnRole.allCases.map { role in
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

        activeBoardDesktopID = nil
        pendingBoardFocusRequest = .assigned(target.role, windowID)
        let previousWorkspaceStacks = stacksByWorkspace
        let previousDisplayStacks = stacksByDisplay
        let didMove = assign(windowID: windowID, to: target.role, displayID: target.displayID)
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
            overlayController.showArrangeBoard(model: self, displays: [display])
            refocusArrangeBoardIfNeeded()
        }
        return target
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

    private func activeLayoutSpaceID() -> String {
        if allDisplays().count == 1 {
            return MacOSSpaceReader.currentMainDisplaySpaceID() ?? LayoutWorkspaceID.visibleSpaceID
        }
        return LayoutWorkspaceID.visibleSpaceID
    }

    private func saveWorkspaceStacks() {
        store.saveWorkspaceStacks(stacksByWorkspace)
    }

    private func saveAllStackStores() {
        store.saveWorkspaceStacks(stacksByWorkspace)
        store.saveStacks(stacksByDisplay)
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
        var captured: [ColumnRole: [SavedModeWindow]] = [:]
        for role in ColumnRole.allCases {
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
        var usedWindowIDs = Set<String>()
        var bindings: [ActiveModeWindowBinding] = []

        for target in mode.windows.sorted(by: { lhs, rhs in
            if lhs.role == rhs.role {
                return lhs.order < rhs.order
            }
            let lhsIndex = ColumnRole.allCases.firstIndex(of: lhs.role) ?? 0
            let rhsIndex = ColumnRole.allCases.firstIndex(of: rhs.role) ?? 0
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
        guard spec.forceNew, !spec.newWindowMenuItemTitles.isEmpty else {
            return nil
        }

        if accessibility.pressNewWindowMenuItem(
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
                grid: display.grid
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

            for role in ColumnRole.allCases {
                let rect = display.grid.rect(for: role)
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
            self?.overlayController.refocusArrangeBoard()
        }
    }

    private func updateControlDrag(at point: CGPoint) {
        guard let display = display(containing: point) else { return }
        overlayController.showSnapOverlay(model: self, displays: [display])
        hoveredSnapRole = display.grid.nearestRole(to: point)
    }

    private func finishControlDrag(at point: CGPoint) async {
        overlayController.closeSnapOverlay()
        hoveredSnapRole = nil
        await refreshWindows(includeThumbnails: false)
        guard let display = display(containing: point),
              let frontmost = windows.first(where: { $0.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier }) else {
            return
        }
        let role = display.grid.nearestRole(to: point)
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
            var state = stackState(for: display.id)
            state.remove(windowID)
            setStackState(state, for: display.id, save: false)
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

    private func launch(_ spec: BoardAppShortcutSpec) -> Bool {
        if spec.forceNew {
            for bundleID in spec.bundleIdentifiers {
                if launchWithOpen(arguments: ["-n", "-b", bundleID]) {
                    return true
                }
            }

            for name in spec.appNames {
                if launchWithOpen(arguments: ["-na", name]) {
                    return true
                }
            }

            return false
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
            return (display, display.grid.nearestRole(to: pointer))
        }

        if trigger == .keyboard,
           let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let window = windows.first(where: { $0.pid == frontmostPID }),
           let display = display(containing: window.frame.center) {
            let state = stackState(for: display.id)
            if let assignedRole = ColumnRole.allCases.first(where: { state.windows(in: $0).contains(window.id) }) {
                return (display, assignedRole)
            }
            return (display, display.grid.nearestRole(to: window.frame.center))
        }

        if let display = activeDisplay() {
            return (display, .center)
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
