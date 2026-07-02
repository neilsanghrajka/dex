import AppKit
import SwiftUI

private let boardRunningAppsRowHeight: CGFloat = 88
private let boardCombinedShelfRowHeight: CGFloat = 94

private enum BoardNavigationDirection {
    case left
    case right
    case up
    case down
}

private struct BoardNavigationCandidate {
    let selection: BoardSelection
    let center: CGPoint
}

private func modeSlotNumber(forKeyCode keyCode: UInt16) -> Int? {
    switch keyCode {
    case 18: 1
    case 19: 2
    case 20: 3
    case 21: 4
    case 23: 5
    case 22: 6
    case 26: 7
    case 28: 8
    case 25: 9
    default: nil
    }
}

private enum BoardSelection: Equatable {
    case column(ColumnRole)
    case assigned(ColumnRole, String)
    case unassignedArea
    case unassigned(String)
    case runningAppsArea
    case runningApplication(String)
    case activeModesArea
    case activeMode(UUID)

    var windowID: String? {
        switch self {
        case .column, .unassignedArea, .runningAppsArea, .runningApplication, .activeModesArea, .activeMode:
            nil
        case .assigned(_, let id), .unassigned(let id):
            id
        }
    }

    var runningApplicationID: String? {
        switch self {
        case .runningApplication(let id):
            id
        case .column, .assigned, .unassignedArea, .unassigned, .runningAppsArea, .activeModesArea, .activeMode:
            nil
        }
    }

    var activeModeID: UUID? {
        switch self {
        case .activeMode(let id):
            id
        case .column, .assigned, .unassignedArea, .unassigned, .runningAppsArea, .runningApplication, .activeModesArea:
            nil
        }
    }

    var itemID: String? {
        switch self {
        case .column, .unassignedArea, .runningAppsArea, .activeModesArea:
            nil
        case .assigned(_, let id), .unassigned(let id):
            "window:\(id)"
        case .runningApplication(let id):
            "app:\(id)"
        case .activeMode(let id):
            "mode:\(id)"
        }
    }

    var role: ColumnRole? {
        switch self {
        case .column(let role), .assigned(let role, _):
            role
        case .unassignedArea, .unassigned, .runningAppsArea, .runningApplication, .activeModesArea, .activeMode:
            nil
        }
    }

    func isSelected(itemID: String) -> Bool {
        self.itemID == "window:\(itemID)"
    }

    func isSelected(appID: String) -> Bool {
        self.itemID == "app:\(appID)"
    }

    func isSelected(modeID: UUID) -> Bool {
        self.itemID == "mode:\(modeID)"
    }

    func isSelected(column role: ColumnRole) -> Bool {
        self == .column(role)
    }

    var isOpenWindowsAreaSelected: Bool {
        self == .unassignedArea
    }

    var isRunningAppsAreaSelected: Bool {
        self == .runningAppsArea
    }

    var isActiveModesAreaSelected: Bool {
        self == .activeModesArea
    }

    func isStillValid(with itemIDs: Set<String>) -> Bool {
        guard let itemID else { return true }
        return itemIDs.contains(itemID)
    }
}

struct ArrangeBoardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let display: DisplayInfo
    @State private var hoveredRole: ColumnRole?
    @State private var draggedWindowID: String?
    @State private var selection: BoardSelection?
    @State private var activeColumnRole: ColumnRole = .center
    @State private var paletteQuery = ""
    @State private var paletteApplications: [InstalledApplication] = []
    @State private var paletteSelectionIndex = 0
    @State private var isPaletteLoading = false
    @State private var isPaletteVisible = false
    @State private var cleanupCandidates: [CleanupCandidate] = []
    @State private var selectedCleanupIDs: Set<String> = []
    @State private var cleanupSelectionIndex = 0
    @State private var isCleanupVisible = false
    @State private var isSaveModeVisible = false
    @State private var saveModeName = ""
    @State private var saveModeSelectionIndex = 0

    var body: some View {
        GeometryReader { geometry in
            let visibleLocalRect = display.localRect(for: display.visibleFrame)
            let boardGutter = display.grid.gutter
            let metrics = layoutMetrics(for: visibleLocalRect)
            let bottomShelfHeight = metrics.bottomShelfHeight
            let activeModes = model.activeModes(on: display)
            let bottomRowHeight = activeModes.isEmpty ? boardRunningAppsRowHeight : boardCombinedShelfRowHeight
            let openWindowsHeight = max(0, bottomShelfHeight - boardGutter - bottomRowHeight)
            let centerStackHeight = metrics.centerStackHeight
            let unassignedWindows = model.unassignedWindows(on: display)
            let runningApps = model.runningApplicationsWithoutVisibleWindows(on: display)
            let ownsBoardInput = model.isDisplayActive(display)
            let bottomSplit = bottomShelfSplit(
                totalWidth: display.localRect(for: display.grid.rect(for: .center)).width,
                gutter: boardGutter,
                hasActiveModes: !activeModes.isEmpty
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.black.opacity(model.isDisplayActive(display) ? 0.42 : 0.22))
                    .ignoresSafeArea()

                VisualEffectBlur()
                    .opacity(0.86)
                    .ignoresSafeArea()

                HStack(alignment: .top, spacing: boardGutter) {
                    ForEach(ColumnRole.allCases) { role in
                        let localRect = display.localRect(for: display.grid.rect(for: role))

                        if role == .center {
                            VStack(alignment: .leading, spacing: boardGutter) {
                                ColumnDropZone(
                                    display: display,
                                    role: role,
                                    size: CGSize(width: localRect.width, height: centerStackHeight),
                                    selection: selection,
                                    isDropTarget: hoveredRole == role,
                                    isDragging: draggedWindowID != nil,
                                    onColumnClicked: {
                                        activeColumnRole = role
                                        selection = .column(role)
                                    },
                                    onCardDragChanged: { windowID, screenPoint in
                                        updateDragHover(windowID: windowID, screenPoint: screenPoint)
                                    },
                                    onCardDragEnded: { windowID, screenPoint in
                                        draggedWindowID = nil
                                        hoveredRole = nil
                                        let targetRole = display.grid.nearestRole(to: screenPoint)
                                        activeColumnRole = targetRole
                                        selection = .assigned(targetRole, windowID)
                                        model.assign(windowID: windowID, at: screenPoint)
                                    },
                                    onCardClicked: { windowID in
                                        activeColumnRole = role
                                        selection = .assigned(role, windowID)
                                        model.selectBoardWindow(windowID: windowID)
                                    },
                                    onCardDoubleClicked: { windowID in
                                        model.activateBoardWindow(windowID: windowID)
                                    }
                                )
                                .environmentObject(model)

                                UnassignedWindowStrip(
                                    windows: unassignedWindows,
                                    size: CGSize(width: localRect.width, height: openWindowsHeight),
                                    selection: selection,
                                    isAreaSelected: selection?.isOpenWindowsAreaSelected == true,
                                    onCardDragChanged: { windowID, screenPoint in
                                        updateDragHover(windowID: windowID, screenPoint: screenPoint)
                                    },
                                    onCardDragEnded: { windowID, screenPoint in
                                        draggedWindowID = nil
                                        hoveredRole = nil
                                        let targetRole = display.grid.nearestRole(to: screenPoint)
                                        activeColumnRole = targetRole
                                        selection = .assigned(targetRole, windowID)
                                        model.assign(windowID: windowID, at: screenPoint)
                                    },
                                    onCardClicked: { windowID in
                                        selection = .unassigned(windowID)
                                        model.selectBoardWindow(windowID: windowID)
                                    },
                                    onCardDoubleClicked: { windowID in
                                        model.activateBoardWindow(windowID: windowID)
                                    }
                                )

                                HStack(spacing: boardGutter) {
                                    RunningAppSwitcherStrip(
                                        apps: runningApps,
                                        size: CGSize(width: bottomSplit.runningWidth, height: bottomRowHeight),
                                        selection: selection,
                                        isAreaSelected: selection?.isRunningAppsAreaSelected == true,
                                        onAreaClicked: {
                                            selection = .runningAppsArea
                                        },
                                        onAppClicked: { item in
                                            selection = .runningApplication(item.id)
                                            model.selectRunningApplication(item)
                                        },
                                        onAppDoubleClicked: { item in
                                            selection = .runningApplication(item.id)
                                            Task {
                                                await model.openRunningApplication(item, in: activeRole(), displayID: display.id)
                                            }
                                        }
                                    )

                                    if !activeModes.isEmpty {
                                        ActiveModeStrip(
                                            modes: activeModes,
                                            size: CGSize(width: bottomSplit.activeModesWidth, height: bottomRowHeight),
                                            selection: selection,
                                            isAreaSelected: selection?.isActiveModesAreaSelected == true,
                                            onAreaClicked: {
                                                selection = .activeModesArea
                                            },
                                            onModeClicked: { instance in
                                                selection = .activeMode(instance.id)
                                            },
                                            onModeDoubleClicked: { instance in
                                                selection = .activeMode(instance.id)
                                                Task { await model.raiseModeInstance(id: instance.id) }
                                            }
                                        )
                                    }
                                }
                            }
                            .frame(width: localRect.width, height: metrics.columnsHeight, alignment: .top)
                        } else {
                            ColumnDropZone(
                                display: display,
                                role: role,
                                size: CGSize(width: localRect.width, height: metrics.columnsHeight),
                                selection: selection,
                                isDropTarget: hoveredRole == role,
                                isDragging: draggedWindowID != nil,
                                onColumnClicked: {
                                    activeColumnRole = role
                                    selection = .column(role)
                                },
                                onCardDragChanged: { windowID, screenPoint in
                                    updateDragHover(windowID: windowID, screenPoint: screenPoint)
                                },
                                onCardDragEnded: { windowID, screenPoint in
                                    draggedWindowID = nil
                                    hoveredRole = nil
                                    let targetRole = display.grid.nearestRole(to: screenPoint)
                                    activeColumnRole = targetRole
                                    selection = .assigned(targetRole, windowID)
                                    model.assign(windowID: windowID, at: screenPoint)
                                },
                                onCardClicked: { windowID in
                                    activeColumnRole = role
                                    selection = .assigned(role, windowID)
                                    model.selectBoardWindow(windowID: windowID)
                                },
                                onCardDoubleClicked: { windowID in
                                    model.activateBoardWindow(windowID: windowID)
                                }
                            )
                            .environmentObject(model)
                        }
                    }
                }
                .frame(width: visibleLocalRect.width, height: metrics.columnsHeight, alignment: .topLeading)
                .offset(
                    x: visibleLocalRect.minX,
                    y: visibleLocalRect.minY + metrics.headerHeight + boardGutter
                )
                .zIndex(1)

                if let hudText = model.hudText {
                    HUDView(text: hudText)
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(30)
                }

            }
            .contentShape(Rectangle())
            .overlay {
                if ownsBoardInput && !isPaletteVisible && !isCleanupVisible && !isSaveModeVisible {
                    BoardKeyboardCapture { event in
                        handleKeyDown(event)
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                }
            }
            .overlay {
                if ownsBoardInput && isPaletteVisible {
                    BoardPaletteOverlay(
                        query: $paletteQuery,
                        results: filteredPaletteResults,
                        shortcuts: model.savedModes.map { ($0.name, $0.shortcutLabel) } +
                            model.appShortcutBindings
                                .filter { !$0.key.isEmpty }
                                .map { ($0.displayName, $0.keyLabel) },
                        isLoading: isPaletteLoading,
                        selectedIndex: $paletteSelectionIndex,
                        onMove: movePaletteSelection,
                        onSubmit: openSelectedPaletteResult,
                        onCancel: closePalette
                    )
                    .zIndex(40)
                }
            }
            .overlay {
                if ownsBoardInput && isCleanupVisible {
                    CleanupOverlay(
                        candidates: cleanupCandidates,
                        selectedIDs: $selectedCleanupIDs,
                        selectedIndex: $cleanupSelectionIndex,
                        onClean: runCleanup,
                        onCancel: closeCleanup
                    )
                    .zIndex(40)
                }
            }
            .overlay {
                if ownsBoardInput && isSaveModeVisible {
                    SaveModeOverlay(
                        name: $saveModeName,
                        modes: model.savedModes,
                        preview: model.modeCapturePreview(displayID: display.id),
                        selectedModeIndex: $saveModeSelectionIndex,
                        onMoveSelection: moveSaveModeSelection,
                        onSaveNew: saveModeAsNew,
                        onReplace: replaceSelectedMode,
                        onCancel: closeSaveMode
                    )
                    .zIndex(45)
                }
            }
            .overlay {
                if case .confirming(let mode, let policy, _) = model.modeLaunchConfirmation {
                    ModeLaunchConfirmationOverlay(
                        mode: mode,
                        policy: policy,
                        onPolicyChange: model.setLaunchConfirmationPolicy,
                        onLaunch: {
                            Task { await model.launchConfirmedMode() }
                        },
                        onCancel: model.cancelModeLaunchConfirmation
                    )
                    .zIndex(44)
                }
            }
            .overlay(alignment: .bottom) {
                if ownsBoardInput, let step = model.tourStep {
                    TourCoachCard(
                        step: step,
                        exampleBinding: model.tourExampleBinding,
                        legendShortcuts: legendShortcuts,
                        onSkip: { model.exitTour() },
                        onDone: { model.completeTour() }
                    )
                    .padding(.bottom, 42)
                    .zIndex(46)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                if ownsBoardInput, model.tourStep == nil, model.isBoardLegendVisibleThisSession {
                    BoardLegendBar(onDismiss: { model.dismissBoardLegend() })
                        .padding(.bottom, 18)
                        .zIndex(29)
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onExitCommand {
                if isPaletteVisible {
                    closePalette()
                    return
                }
                if isCleanupVisible {
                    closeCleanup()
                    return
                }
                if isSaveModeVisible {
                    closeSaveMode()
                    return
                }
                if case .confirming = model.modeLaunchConfirmation {
                    model.cancelModeLaunchConfirmation()
                    return
                }
                if model.tourStep != nil {
                    model.exitTour()
                    return
                }
                model.closeArrangeBoard()
            }
            .onAppear {
                applyPendingBoardFocusOrEnsureSelection()
            }
            .onChange(of: selectionItemIDs) {
                ensureSelection()
            }
            .animation(draggedWindowID == nil ? .spring(response: 0.24, dampingFraction: 0.86) : nil, value: hoveredRole)
        }
    }

    private var selectionItemIDs: [String] {
        ColumnRole.allCases.flatMap { windows(for: $0).map { "window:\($0.id)" } }
            + model.unassignedWindows(on: display).map { "window:\($0.id)" }
            + runningApps.map { "app:\($0.id)" }
            + activeModes.map { "mode:\($0.id)" }
    }

    private var runningApps: [RunningApplicationItem] {
        model.runningApplicationsWithoutVisibleWindows(on: display)
    }

    private var activeModes: [ActiveModeInstance] {
        model.activeModes(on: display)
    }

    private var filteredPaletteResults: [BoardPaletteResult] {
        BoardPaletteSearch.filtered(paletteResults, query: paletteQuery)
    }

    /// Live app-launch bindings as (label, key) pairs for the tour step-4 mini legend.
    private var legendShortcuts: [(String, String)] {
        model.appShortcutBindings
            .filter { !$0.key.isEmpty }
            .map { ($0.displayName, $0.keyLabel) }
    }

    private var paletteResults: [BoardPaletteResult] {
        (model.savedModes.isEmpty ? [] : [.manageModes]) +
            model.savedModes.map(BoardPaletteResult.savedMode) +
            diaTabPaletteResults() +
            paletteApplications.map(BoardPaletteResult.application)
    }

    private func windows(for role: ColumnRole) -> [ManagedWindow] {
        model.boardWindows(for: role, on: display)
    }

    private func diaTabPaletteResults() -> [BoardPaletteResult] {
        var seenWindowIDs: Set<String> = []
        let displayWindows = ColumnRole.allCases.flatMap { windows(for: $0) } +
            model.unassignedWindows(on: display)

        return displayWindows.flatMap { window -> [BoardPaletteResult] in
            guard seenWindowIDs.insert(window.id).inserted else { return [] }
            return model.diaTabs(for: window).map { tab in
                .diaTab(
                    tab,
                    parentAppName: window.appName,
                    parentBundleIdentifier: window.bundleIdentifier
                )
            }
        }
    }

    private func updateDragHover(windowID: String, screenPoint: CGPoint) {
        if draggedWindowID != windowID {
            draggedWindowID = windowID
        }

        let role = display.grid.nearestRole(to: screenPoint)
        if hoveredRole != role {
            hoveredRole = role
        }
    }

    private func layoutMetrics(for visibleLocalRect: CGRect) -> (
        headerHeight: CGFloat,
        columnsHeight: CGFloat,
        bottomShelfHeight: CGFloat,
        centerStackHeight: CGFloat
    ) {
        let headerHeight: CGFloat = 0
        let boardGutter = display.grid.gutter
        let columnsHeight = max(260, visibleLocalRect.height - headerHeight - boardGutter)
        let bottomShelfHeight = floor(columnsHeight * 0.35)
        let centerStackHeight = max(160, columnsHeight - boardGutter - bottomShelfHeight)
        return (headerHeight, columnsHeight, bottomShelfHeight, centerStackHeight)
    }

    private func bottomShelfSplit(
        totalWidth: CGFloat,
        gutter: CGFloat,
        hasActiveModes: Bool
    ) -> (runningWidth: CGFloat, activeModesWidth: CGFloat) {
        guard hasActiveModes else {
            return (max(0, totalWidth), 0)
        }

        var activeWidth = min(340, max(230, totalWidth * 0.36))
        let preferredRunningWidth: CGFloat = 380
        activeWidth = min(activeWidth, max(190, totalWidth - preferredRunningWidth - gutter))
        if totalWidth < 560 {
            activeWidth = max(170, totalWidth * 0.36)
        }
        activeWidth = min(activeWidth, max(0, totalWidth - gutter))
        return (max(0, totalWidth - activeWidth - gutter), max(0, activeWidth))
    }

    private func bottomShelfRects(
        for visibleLocalRect: CGRect
    ) -> (openWindows: CGRect, runningApps: CGRect, activeModes: CGRect?) {
        let boardGutter = display.grid.gutter
        let metrics = layoutMetrics(for: visibleLocalRect)
        let centerRect = display.localRect(for: display.grid.rect(for: .center))
        let hasActiveModes = !activeModes.isEmpty
        let bottomRowHeight = hasActiveModes ? boardCombinedShelfRowHeight : boardRunningAppsRowHeight
        let openWindowsHeight = max(0, metrics.bottomShelfHeight - boardGutter - bottomRowHeight)
        let openWindowsRect = CGRect(
            x: centerRect.minX,
            y: visibleLocalRect.minY + metrics.headerHeight + boardGutter + metrics.centerStackHeight + boardGutter,
            width: centerRect.width,
            height: openWindowsHeight
        )
        let split = bottomShelfSplit(
            totalWidth: centerRect.width,
            gutter: boardGutter,
            hasActiveModes: hasActiveModes
        )
        let runningAppsRect = CGRect(
            x: centerRect.minX,
            y: openWindowsRect.maxY + boardGutter,
            width: split.runningWidth,
            height: bottomRowHeight
        )
        let activeModesRect = hasActiveModes ? CGRect(
            x: runningAppsRect.maxX + boardGutter,
            y: runningAppsRect.minY,
            width: split.activeModesWidth,
            height: bottomRowHeight
        ) : nil
        return (openWindowsRect, runningAppsRect, activeModesRect)
    }

    private func applyPendingBoardFocusOrEnsureSelection() {
        guard let request = model.consumePendingBoardFocusRequest() else {
            ensureSelection()
            return
        }

        switch request {
        case .assigned(let role, let windowID):
            activeColumnRole = role
            selection = .assigned(role, windowID)
        }
    }

    private func ensureSelection() {
        let ids = Set(selectionItemIDs)
        if let selection, selection.isStillValid(with: ids) {
            return
        }

        if let center = windows(for: .center).first {
            activeColumnRole = .center
            selection = .assigned(.center, center.id)
            return
        }

        for role in ColumnRole.allCases {
            if let window = windows(for: role).first {
                activeColumnRole = role
                selection = .assigned(role, window.id)
                return
            }
        }

        if let unassigned = model.unassignedWindows(on: display).first {
            selection = .unassigned(unassigned.id)
            return
        }

        if let runningApp = runningApps.first {
            selection = .runningApplication(runningApp.id)
            return
        }

        if let activeMode = activeModes.first {
            selection = .activeMode(activeMode.id)
            return
        }

        selection = .column(.center)
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if handleModeConfirmationKeyDown(event) {
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.option) {
            let optionKey = event.charactersIgnoringModifiers?.lowercased()

            if event.keyCode == 48 {
                switchFocusArea(reverse: flags.contains(.shift))
                return true
            }

            if optionKey == "s" {
                showSaveMode()
                return true
            }

            if let slot = modeSlot(for: event) {
                Task { await model.handleModeHotkey(slot: slot) }
                return true
            }

            if flags.contains(.shift), isArrowKey(event.keyCode) {
                return true
            }

            if handleOptionArrow(event) {
                return true
            }

            if optionKey == "x" {
                showCleanup()
                return true
            }
        }

        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }

        switch event.keyCode {
        case 123:
            moveSelection(.left)
            return true
        case 124:
            moveSelection(.right)
            return true
        case 125:
            moveSelection(.down)
            return true
        case 126:
            moveSelection(.up)
            return true
        case 36, 76:
            if model.tourStep == .jump {
                // Teach Return without tearing the board down mid-tour.
                model.advanceTour(from: .jump)
                return true
            }
            // During any other tour step, Return must not activate a window (which would
            // close the board and abandon the tour). Swallow it so the tour stays live.
            if model.tourStep != nil {
                return true
            }
            activateSelectedWindow()
            return true
        default:
            break
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else {
            return false
        }
        guard !flags.contains(.option),
              !flags.contains(.command),
              !flags.contains(.control) else {
            return false
        }

        switch key {
        case "/":
            showPalette()
            return true
        case "q":
            // Q closes/quits the selected item. Suppress it during the tour so a stray
            // press can't destroy the user's windows while they're being taught; the
            // closing card teaches Q only as information.
            if model.tourStep != nil {
                return true
            }
            closeSelectedItem()
            return true
        default:
            return handleAppShortcut(event)
        }
    }

    private func handleOptionArrow(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123:
            if handleWindowEdgeMove(direction: .left) {
                return true
            }
            moveSelectedItem(to: previousRole(from: activeRole()))
            return true
        case 124:
            if handleWindowEdgeMove(direction: .right) {
                return true
            }
            moveSelectedItem(to: nextRole(from: activeRole()))
            return true
        case 126:
            moveSelectedItem(to: .center)
            return true
        case 125:
            if let windowID = selection?.windowID {
                selection = .unassigned(windowID)
                model.moveBoardWindowToUnassigned(windowID: windowID)
                return true
            }
            return false
        default:
            return false
        }
    }

    private func handleAppShortcut(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased().filter { $0.isLetter || $0.isNumber } ?? ""
        guard !key.isEmpty else { return false }

        guard let binding = model.appShortcutBinding(forKey: key) else {
            return false
        }

        openShortcut(binding)
        model.advanceTour(from: .shortcut)
        return true
    }

    private func switchFocusArea(reverse: Bool = false) {
        ensureSelection()
        let areas = BoardFocusArea.allCases
        let current = currentFocusArea()
        let currentIndex = areas.firstIndex(of: current) ?? 1
        let nextIndex = reverse
            ? (currentIndex - 1 + areas.count) % areas.count
            : (currentIndex + 1) % areas.count
        selectFocusArea(areas[nextIndex])
    }

    private func currentFocusArea() -> BoardFocusArea {
        guard let selection else { return .center }
        switch selection {
        case .column(let role), .assigned(let role, _):
            return BoardFocusArea(role: role)
        case .unassignedArea, .unassigned:
            return .openWindows
        case .runningAppsArea, .runningApplication:
            return .runningApps
        case .activeModesArea, .activeMode:
            return .activeModes
        }
    }

    private func selectFocusArea(_ area: BoardFocusArea) {
        if let role = area.role {
            activeColumnRole = role
            selectFirstWindowOrColumn(in: role)
            return
        }

        if area == .runningApps {
            if let first = runningApps.first {
                selection = .runningApplication(first.id)
            } else {
                selection = .runningAppsArea
            }
            return
        }

        if area == .activeModes {
            if let first = activeModes.first {
                selection = .activeMode(first.id)
            } else {
                selection = .activeModesArea
            }
            return
        }

        if let first = model.unassignedWindows(on: display).first {
            selection = .unassigned(first.id)
        } else {
            selection = .unassignedArea
        }
    }

    private func moveSelection(_ direction: BoardNavigationDirection) {
        ensureSelection()
        let previousSelection = selection
        guard let target = visualNavigationTarget(direction) else { return }
        if let role = target.selection.role {
            activeColumnRole = role
        }
        selection = target.selection
        applySelectionSideEffects()
        if target.selection != previousSelection {
            model.advanceTour(from: .navigate)
        }
    }

    private func visualNavigationTarget(_ direction: BoardNavigationDirection) -> BoardNavigationCandidate? {
        let candidates = visualNavigationCandidates()
        guard !candidates.isEmpty else { return nil }

        guard let origin = navigationOrigin(in: candidates) else {
            return candidates.first
        }

        return candidates
            .filter { candidate in
                candidate.selection != selection && isCandidate(candidate.center, in: direction, from: origin)
            }
            .min { lhs, rhs in
                visualNavigationScore(lhs.center, direction: direction, from: origin) <
                    visualNavigationScore(rhs.center, direction: direction, from: origin)
            }
    }

    private func visualGridColumnCount(for role: ColumnRole) -> Int {
        let localRect = display.localRect(for: display.grid.rect(for: role))
        let availableWidth = max(180, localRect.width - 36)
        let minimumWidth: CGFloat = availableWidth < 640 ? min(availableWidth, 340) : 360
        return max(1, Int((availableWidth + 22) / (minimumWidth + 22)))
    }

    private func visualNavigationCandidates() -> [BoardNavigationCandidate] {
        let visibleLocalRect = display.localRect(for: display.visibleFrame)
        let boardGutter = display.grid.gutter
        let metrics = layoutMetrics(for: visibleLocalRect)
        let shelfRects = bottomShelfRects(for: visibleLocalRect)
        let columnsTopY = visibleLocalRect.minY + metrics.headerHeight + boardGutter

        var candidates: [BoardNavigationCandidate] = []
        for role in ColumnRole.allCases {
            let roleRect = display.localRect(for: display.grid.rect(for: role))
            let zoneHeight = role == .center ? metrics.centerStackHeight : metrics.columnsHeight
            let zoneRect = CGRect(
                x: roleRect.minX,
                y: columnsTopY,
                width: roleRect.width,
                height: zoneHeight
            )
            candidates.append(contentsOf: navigationCandidatesForAssignedWindows(role: role, zoneRect: zoneRect))
        }

        candidates.append(contentsOf: navigationCandidatesForUnassignedWindows(zoneRect: shelfRects.openWindows))
        candidates.append(contentsOf: navigationCandidatesForRunningApps(zoneRect: shelfRects.runningApps))
        if let activeModesRect = shelfRects.activeModes {
            candidates.append(contentsOf: navigationCandidatesForActiveModes(zoneRect: activeModesRect))
        }
        return candidates
    }

    private func navigationCandidatesForAssignedWindows(role: ColumnRole, zoneRect: CGRect) -> [BoardNavigationCandidate] {
        let windows = windows(for: role)
        guard !windows.isEmpty else { return [] }

        let metrics = assignedGridMetrics(for: zoneRect.width)
        return windows.enumerated().map { index, window in
            BoardNavigationCandidate(
                selection: .assigned(role, window.id),
                center: cardCenter(
                    index: index,
                    columns: metrics.columns,
                    cardWidth: metrics.cardWidth,
                    cardHeight: metrics.cardHeight,
                    origin: CGPoint(x: zoneRect.minX + 18, y: zoneRect.minY + 60),
                    spacing: CGSize(width: 22, height: 18)
                )
            )
        }
    }

    private func navigationCandidatesForUnassignedWindows(zoneRect: CGRect) -> [BoardNavigationCandidate] {
        let windows = model.unassignedWindows(on: display)
        guard !windows.isEmpty else { return [] }

        let availableCardHeight = max(120, zoneRect.height - 96)
        let cardWidth = min(380, max(220, availableCardHeight * 1.6))
        let cardHeight = cardWidth * 10.0 / 16.0 + 46
        let spacing: CGFloat = 22
        let viewportWidth = max(0, zoneRect.width - 36)
        let contentWidth = CGFloat(windows.count) * cardWidth + CGFloat(max(windows.count - 1, 0)) * spacing
        let centeringInset = max(0, (viewportWidth - contentWidth) / 2)
        let origin = CGPoint(x: zoneRect.minX + 18 + centeringInset, y: zoneRect.minY + 60)

        return windows.enumerated().map { index, window in
            BoardNavigationCandidate(
                selection: .unassigned(window.id),
                center: CGPoint(
                    x: origin.x + CGFloat(index) * (cardWidth + spacing) + cardWidth / 2,
                    y: origin.y + cardHeight / 2
                )
            )
        }
    }

    private func navigationCandidatesForRunningApps(zoneRect: CGRect) -> [BoardNavigationCandidate] {
        let apps = runningApps
        guard !apps.isEmpty else { return [] }

        let cardWidth: CGFloat = 82
        let spacing: CGFloat = 12
        let viewportWidth = max(0, zoneRect.width - 36)
        let contentWidth = CGFloat(apps.count) * cardWidth + CGFloat(max(apps.count - 1, 0)) * spacing
        let centeringInset = max(0, (viewportWidth - contentWidth) / 2)
        let origin = CGPoint(x: zoneRect.minX + 18 + centeringInset, y: zoneRect.minY + 34)

        return apps.enumerated().map { index, item in
            BoardNavigationCandidate(
                selection: .runningApplication(item.id),
                center: CGPoint(
                    x: origin.x + CGFloat(index) * (cardWidth + spacing) + cardWidth / 2,
                    y: origin.y + 28
                )
            )
        }
    }

    private func navigationCandidatesForActiveModes(zoneRect: CGRect) -> [BoardNavigationCandidate] {
        let modes = activeModes
        guard !modes.isEmpty else { return [] }

        let cardWidth: CGFloat = 150
        let spacing: CGFloat = 12
        let viewportWidth = max(0, zoneRect.width - 36)
        let contentWidth = CGFloat(modes.count) * cardWidth + CGFloat(max(modes.count - 1, 0)) * spacing
        let centeringInset = max(0, (viewportWidth - contentWidth) / 2)
        let origin = CGPoint(x: zoneRect.minX + 18 + centeringInset, y: zoneRect.minY + 20)

        return modes.enumerated().map { index, item in
            BoardNavigationCandidate(
                selection: .activeMode(item.id),
                center: CGPoint(
                    x: origin.x + CGFloat(index) * (cardWidth + spacing) + cardWidth / 2,
                    y: origin.y + 30
                )
            )
        }
    }

    private func assignedGridMetrics(for zoneWidth: CGFloat) -> (columns: Int, cardWidth: CGFloat, cardHeight: CGFloat) {
        let availableWidth = max(180, zoneWidth - 36)
        let minimumWidth: CGFloat = availableWidth < 640 ? min(availableWidth, 340) : 360
        let columns = max(1, Int((availableWidth + 22) / (minimumWidth + 22)))
        let rawCardWidth = (availableWidth - CGFloat(columns - 1) * 22) / CGFloat(columns)
        let cardWidth = min(460, max(minimumWidth, rawCardWidth))
        let cardHeight = cardWidth * 10.0 / 16.0 + 46
        return (columns, cardWidth, cardHeight)
    }

    private func cardCenter(
        index: Int,
        columns: Int,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        origin: CGPoint,
        spacing: CGSize
    ) -> CGPoint {
        let column = index % columns
        let row = index / columns
        return CGPoint(
            x: origin.x + CGFloat(column) * (cardWidth + spacing.width) + cardWidth / 2,
            y: origin.y + CGFloat(row) * (cardHeight + spacing.height) + cardHeight / 2
        )
    }

    private func navigationOrigin(in candidates: [BoardNavigationCandidate]) -> CGPoint? {
        guard let selection else { return nil }
        if let selected = candidates.first(where: { $0.selection == selection }) {
            return selected.center
        }

        switch selection {
        case .column(let role):
            let rect = display.localRect(for: display.grid.rect(for: role))
            let visibleLocalRect = display.localRect(for: display.visibleFrame)
            let metrics = layoutMetrics(for: visibleLocalRect)
            return CGPoint(
                x: rect.midX,
                y: visibleLocalRect.minY + metrics.headerHeight + display.grid.gutter + metrics.columnsHeight / 2
            )
        case .unassignedArea:
            let visibleLocalRect = display.localRect(for: display.visibleFrame)
            let shelfRects = bottomShelfRects(for: visibleLocalRect)
            return CGPoint(
                x: shelfRects.openWindows.midX,
                y: shelfRects.openWindows.midY
            )
        case .runningAppsArea:
            let visibleLocalRect = display.localRect(for: display.visibleFrame)
            let shelfRects = bottomShelfRects(for: visibleLocalRect)
            return CGPoint(
                x: shelfRects.runningApps.midX,
                y: shelfRects.runningApps.midY
            )
        case .activeModesArea:
            let visibleLocalRect = display.localRect(for: display.visibleFrame)
            let shelfRects = bottomShelfRects(for: visibleLocalRect)
            guard let activeModesRect = shelfRects.activeModes else {
                return CGPoint(x: shelfRects.runningApps.midX, y: shelfRects.runningApps.midY)
            }
            return CGPoint(x: activeModesRect.midX, y: activeModesRect.midY)
        case .assigned, .unassigned, .runningApplication, .activeMode:
            return nil
        }
    }

    private func isCandidate(_ point: CGPoint, in direction: BoardNavigationDirection, from origin: CGPoint) -> Bool {
        let threshold: CGFloat = 8
        switch direction {
        case .left:
            return point.x < origin.x - threshold
        case .right:
            return point.x > origin.x + threshold
        case .up:
            return point.y < origin.y - threshold
        case .down:
            return point.y > origin.y + threshold
        }
    }

    private func visualNavigationScore(
        _ point: CGPoint,
        direction: BoardNavigationDirection,
        from origin: CGPoint
    ) -> CGFloat {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let primary: CGFloat
        let secondary: CGFloat

        switch direction {
        case .left, .right:
            primary = abs(dx)
            secondary = abs(dy)
        case .up, .down:
            primary = abs(dy)
            secondary = abs(dx)
        }

        return primary + secondary * 2.4
    }

    private func selectFirstWindowOrColumn(in role: ColumnRole) {
        activeColumnRole = role
        if let first = windows(for: role).first {
            selection = .assigned(role, first.id)
        } else {
            selection = .column(role)
        }
    }

    private func applySelectionSideEffects() {
    }

    private func isArrowKey(_ keyCode: UInt16) -> Bool {
        keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126
    }

    private func activateSelectedWindow() {
        activateSelectedItem()
    }

    private func activateSelectedItem() {
        if let windowID = selection?.windowID {
            model.activateBoardWindow(windowID: windowID)
            return
        }

        if let modeID = selection?.activeModeID {
            Task { await model.raiseModeInstance(id: modeID) }
            return
        }

        guard let appID = selection?.runningApplicationID,
              let item = runningApps.first(where: { $0.id == appID }) else {
            return
        }

        Task {
            await model.openRunningApplication(item, in: activeRole(), displayID: display.id)
        }
    }

    private func closeSelectedItem() {
        if let windowID = selection?.windowID {
            selection = selectionAfterRemoving(windowID)
            model.closeBoardWindow(windowID: windowID)
            return
        }

        if let modeID = selection?.activeModeID {
            selection = selectionAfterRemovingActiveMode(modeID)
            Task { await model.closeModeInstance(id: modeID) }
            return
        }

        guard let appID = selection?.runningApplicationID,
              let item = runningApps.first(where: { $0.id == appID }) else {
            return
        }

        selection = selectionAfterRemovingRunningApp(appID)
        model.quitRunningApplication(item)
    }

    private func selectionAfterRemoving(_ windowID: String) -> BoardSelection? {
        guard let selection else { return nil }

        switch selection {
        case .assigned(let role, _):
            let windows = windows(for: role)
            let remaining = windows.filter { $0.id != windowID }
            guard !remaining.isEmpty else { return .column(role) }
            let currentIndex = windows.firstIndex(where: { $0.id == windowID }) ?? 0
            let nextIndex = min(currentIndex, remaining.count - 1)
            return .assigned(role, remaining[nextIndex].id)
        case .unassigned:
            let windows = model.unassignedWindows(on: display)
            let remaining = windows.filter { $0.id != windowID }
            guard !remaining.isEmpty else { return .unassignedArea }
            let currentIndex = windows.firstIndex(where: { $0.id == windowID }) ?? 0
            let nextIndex = min(currentIndex, remaining.count - 1)
            return .unassigned(remaining[nextIndex].id)
        case .column, .unassignedArea, .runningAppsArea, .runningApplication, .activeModesArea, .activeMode:
            return selection
        }
    }

    private func selectionAfterRemovingRunningApp(_ appID: String) -> BoardSelection? {
        let apps = runningApps
        let remaining = apps.filter { $0.id != appID }
        guard !remaining.isEmpty else { return .runningAppsArea }
        let currentIndex = apps.firstIndex(where: { $0.id == appID }) ?? 0
        let nextIndex = min(currentIndex, remaining.count - 1)
        return .runningApplication(remaining[nextIndex].id)
    }

    private func selectionAfterRemovingActiveMode(_ modeID: UUID) -> BoardSelection? {
        let modes = activeModes
        let remaining = modes.filter { $0.id != modeID }
        guard !remaining.isEmpty else { return .activeModesArea }
        let currentIndex = modes.firstIndex(where: { $0.id == modeID }) ?? 0
        let nextIndex = min(currentIndex, remaining.count - 1)
        return .activeMode(remaining[nextIndex].id)
    }

    private func showPalette() {
        paletteApplications = []
        paletteQuery = ""
        paletteSelectionIndex = 0
        isPaletteLoading = true
        isPaletteVisible = true
        Task {
            async let applications = model.loadInstalledApplications()
            await model.refreshDiaTabsForPalette()
            let loadedApplications = await applications
            guard isPaletteVisible else { return }
            paletteApplications = loadedApplications
            paletteSelectionIndex = 0
            isPaletteLoading = false
        }
    }

    private func closePalette() {
        isPaletteVisible = false
        isPaletteLoading = false
        paletteQuery = ""
        paletteSelectionIndex = 0
    }

    private func movePaletteSelection(_ direction: Int) {
        let results = filteredPaletteResults
        guard !results.isEmpty else {
            paletteSelectionIndex = 0
            return
        }

        paletteSelectionIndex = min(
            max(paletteSelectionIndex + direction, 0),
            results.count - 1
        )
    }

    private func openSelectedPaletteResult() {
        let results = filteredPaletteResults
        guard !results.isEmpty else { return }
        let index = min(paletteSelectionIndex, results.count - 1)

        switch results[index] {
        case .manageModes:
            closePalette()
            openWindow(id: "main")
            model.openModeManagement()
        case .savedMode(let mode):
            closePalette()
            Task {
                await model.launchModeFromPalette(mode)
            }
        case .application(let application):
            let role = activeRole()
            activeColumnRole = role
            selection = .column(role)
            closePalette()
            Task {
                await model.openApplication(application, in: role, displayID: display.id)
            }
        case .diaTab(let tab, _, _):
            closePalette()
            model.activateBoardDiaTab(tabID: tab.id)
        }
    }

    private func showCleanup() {
        cleanupCandidates = model.cleanupCandidates(on: display)
        selectedCleanupIDs = Set(cleanupCandidates.map(\.id))
        cleanupSelectionIndex = 0
        isCleanupVisible = true
    }

    private func closeCleanup() {
        isCleanupVisible = false
        cleanupCandidates = []
        selectedCleanupIDs = []
        cleanupSelectionIndex = 0
    }

    private func runCleanup() {
        let selected = cleanupCandidates.filter { selectedCleanupIDs.contains($0.id) }
        closeCleanup()
        guard !selected.isEmpty else { return }
        model.closeCleanupCandidates(selected)
    }

    private func showSaveMode() {
        saveModeName = ""
        saveModeSelectionIndex = -1
        isSaveModeVisible = true
    }

    private func closeSaveMode() {
        isSaveModeVisible = false
        saveModeName = ""
        saveModeSelectionIndex = 0
    }

    private func saveModeAsNew() {
        if model.saveMode(name: saveModeName, replacing: nil, displayID: display.id) != nil {
            closeSaveMode()
        }
    }

    private func replaceSelectedMode() {
        guard model.savedModes.indices.contains(saveModeSelectionIndex) else {
            saveModeAsNew()
            return
        }
        let mode = model.savedModes[saveModeSelectionIndex]
        if model.saveMode(name: saveModeName.isEmpty ? mode.name : saveModeName, replacing: mode.id, displayID: display.id) != nil {
            closeSaveMode()
        }
    }

    private func moveSaveModeSelection(_ direction: Int) {
        let upperBound = model.savedModes.count - 1
        saveModeSelectionIndex = min(max(saveModeSelectionIndex + direction, -1), upperBound)
    }

    private func modeSlot(for event: NSEvent) -> Int? {
        modeSlotNumber(forKeyCode: event.keyCode)
    }

    private func handleModeConfirmationKeyDown(_ event: NSEvent) -> Bool {
        guard case .confirming(let mode, _, _) = model.modeLaunchConfirmation else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.option),
           modeSlot(for: event) == mode.slot {
            Task { await model.launchConfirmedMode() }
            return true
        }

        switch event.keyCode {
        case 53:
            model.cancelModeLaunchConfirmation()
            return true
        case 36, 76:
            Task { await model.launchConfirmedMode() }
            return true
        case 123, 126:
            model.setLaunchConfirmationPolicy(.quitElsewhereAndReopenHere)
            return true
        case 124, 125:
            model.setLaunchConfirmationPolicy(.openNewHere)
            return true
        default:
            return false
        }
    }

    private func moveSelectedWindow(_ windowID: String, to role: ColumnRole) {
        let previousRole = selection?.role
        activeColumnRole = role
        selection = .assigned(role, windowID)
        model.moveBoardWindow(windowID: windowID, to: role, displayID: display.id)
        if previousRole != role {
            model.advanceTour(from: .moveColumn)
        }
    }

    private func handleWindowEdgeMove(direction: DisplaySwitchDirection) -> Bool {
        let edgeRole: ColumnRole = direction == .left ? .left : .right
        guard activeRole() == edgeRole,
              let windowID = selection?.windowID else {
            return false
        }

        guard let target = model.moveBoardWindowAcrossDisplayEdge(
            windowID: windowID,
            from: display.id,
            direction: direction
        ) else {
            return true
        }

        activeColumnRole = target.role
        selection = .assigned(target.role, windowID)
        return true
    }

    private func moveSelectedItem(to role: ColumnRole) {
        activeColumnRole = role
        if let windowID = selection?.windowID {
            moveSelectedWindow(windowID, to: role)
            return
        }

        // During the tour's move-column step the selection may not be a window (e.g. a
        // running-app card carried in from the previous step). Re-select an actual window
        // so Option+arrow performs the taught move instead of launching an app; if the
        // board has no movable window, advance so the step doesn't wedge.
        if model.tourStep == .moveColumn {
            if let fallbackWindowID = firstMovableWindowID() {
                activeColumnRole = role
                selection = .assigned(role, fallbackWindowID)
                model.moveBoardWindow(windowID: fallbackWindowID, to: role, displayID: display.id)
            }
            model.advanceTour(from: .moveColumn)
            return
        }

        guard let appID = selection?.runningApplicationID,
              let item = runningApps.first(where: { $0.id == appID }) else {
            selection = .column(role)
            return
        }

        selection = .runningApplication(item.id)
        Task {
            await model.openRunningApplication(item, in: role, displayID: display.id)
        }
    }

    /// The first assignable/movable window on the board, preferring assigned columns and
    /// falling back to the unassigned shelf. Used to recover the tour's move-column step
    /// when the selection isn't a window.
    private func firstMovableWindowID() -> String? {
        for role in ColumnRole.allCases {
            if let window = windows(for: role).first {
                return window.id
            }
        }
        return model.unassignedWindows(on: display).first?.id
    }

    private func openShortcut(_ binding: AppShortcutBinding) {
        let role = activeRole()
        activeColumnRole = role
        selection = .column(role)
        Task {
            await model.openAppShortcut(binding, in: role, displayID: display.id)
        }
    }

    private func activeRole() -> ColumnRole {
        selection?.role ?? activeColumnRole
    }

    private func nextRole(from role: ColumnRole) -> ColumnRole {
        switch role {
        case .left: .center
        case .center: .right
        case .right: .right
        }
    }

    private func previousRole(from role: ColumnRole) -> ColumnRole {
        switch role {
        case .left: .left
        case .center: .left
        case .right: .center
        }
    }

}

private struct ColumnDropZone: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayInfo
    let role: ColumnRole
    let size: CGSize
    let selection: BoardSelection?
    let isDropTarget: Bool
    let isDragging: Bool
    let onColumnClicked: () -> Void
    let onCardDragChanged: (String, CGPoint) -> Void
    let onCardDragEnded: (String, CGPoint) -> Void
    let onCardClicked: (String) -> Void
    let onCardDoubleClicked: (String) -> Void

    var body: some View {
        let windows = model.boardWindows(for: role, on: display)
        let isColumnSelected = selection?.isSelected(column: role) == true

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(isDropTarget || isColumnSelected ? 0.18 : 0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            .white.opacity(isDropTarget || isColumnSelected ? 0.82 : 0.34),
                            style: StrokeStyle(lineWidth: isDropTarget || isColumnSelected ? 3 : 1.5, dash: [8, 7])
                        )
                }
                .allowsHitTesting(false)
                .zIndex(0)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(role.title, systemImage: iconName)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text("\(windows.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.16), in: Capsule())
                        .foregroundStyle(.white)
                }

                if windows.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.dashed")
                            .font(.system(size: 22, weight: .semibold))
                        Text("Drop here")
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: gridColumns(for: size.width), spacing: 18) {
                            ForEach(windows) { window in
                                WindowThumbnailCard(
                                    window: window,
                                    role: role,
                                    isSelected: selection?.isSelected(itemID: window.id) == true,
                                    onDragChanged: onCardDragChanged,
                                    onDragEnded: { draggedWindowID, screenPoint in
                                        onCardDragEnded(draggedWindowID, screenPoint)
                                    },
                                    onClicked: onCardClicked,
                                    onDoubleClicked: onCardDoubleClicked
                                )
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(18)
            .zIndex(2)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            onColumnClicked()
        }
        .animation(nil, value: windows.map(\.id))
        .animation(isDragging ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: isDropTarget)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isColumnSelected)
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let availableWidth = max(180, width - 36)
        let minimumWidth: CGFloat = availableWidth < 640 ? min(availableWidth, 340) : 360
        return [
            GridItem(.adaptive(minimum: minimumWidth, maximum: 460), spacing: 22, alignment: .top)
        ]
    }

    private var iconName: String {
        switch role {
        case .left: "sidebar.left"
        case .center: "rectangle"
        case .right: "sidebar.right"
        }
    }
}

private struct UnassignedWindowStrip: View {
    let windows: [ManagedWindow]
    let size: CGSize
    let selection: BoardSelection?
    let isAreaSelected: Bool
    let onCardDragChanged: (String, CGPoint) -> Void
    let onCardDragEnded: (String, CGPoint) -> Void
    let onCardClicked: (String) -> Void
    let onCardDoubleClicked: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(isAreaSelected ? 0.16 : 0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            .white.opacity(isAreaSelected ? 0.78 : 0.24),
                            style: StrokeStyle(lineWidth: isAreaSelected ? 2.5 : 1.5, dash: [8, 7])
                        )
                }
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Open Windows", systemImage: "rectangle.stack")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text("\(windows.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.16), in: Capsule())
                        .foregroundStyle(.white)
                }

                if windows.isEmpty {
                    Spacer()
                    Text("No unassigned windows")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    let availableCardHeight = max(120, size.height - 96)
                    let cardWidth = min(380, max(220, availableCardHeight * 1.6))
                    let cardSpacing: CGFloat = 22
                    let horizontalPadding: CGFloat = 18
                    let scrollViewportWidth = max(0, size.width - horizontalPadding * 2)
                    let contentWidth = CGFloat(windows.count) * cardWidth +
                        CGFloat(max(windows.count - 1, 0)) * cardSpacing
                    let centeringInset = max(0, (scrollViewportWidth - contentWidth) / 2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: cardSpacing) {
                            ForEach(windows) { window in
                                WindowThumbnailCard(
                                    window: window,
                                    role: .center,
                                    isSelected: selection?.isSelected(itemID: window.id) == true,
                                    onDragChanged: onCardDragChanged,
                                    onDragEnded: onCardDragEnded,
                                    onClicked: onCardClicked,
                                    onDoubleClicked: onCardDoubleClicked
                                )
                                .frame(width: cardWidth)
                            }
                        }
                        .padding(.horizontal, centeringInset)
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(18)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isAreaSelected)
    }
}

private struct RunningAppSwitcherStrip: View {
    let apps: [RunningApplicationItem]
    let size: CGSize
    let selection: BoardSelection?
    let isAreaSelected: Bool
    let onAreaClicked: () -> Void
    let onAppClicked: (RunningApplicationItem) -> Void
    let onAppDoubleClicked: (RunningApplicationItem) -> Void

    var body: some View {
        let labelWidth = min(130, max(96, size.width * 0.24))

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(isAreaSelected ? 0.15 : 0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            .white.opacity(isAreaSelected ? 0.72 : 0.18),
                            style: StrokeStyle(lineWidth: isAreaSelected ? 2.5 : 1.2, dash: [8, 7])
                        )
                }
                .allowsHitTesting(false)

            HStack(spacing: 14) {
                Label("Running Apps", systemImage: "app.dashed")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: labelWidth, alignment: .leading)

                if apps.isEmpty {
                    Text("No hidden running apps")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.56))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    let cardWidth: CGFloat = 82
                    let spacing: CGFloat = 12
                    let viewportWidth = max(0, size.width - labelWidth - 44)
                    let contentWidth = CGFloat(apps.count) * cardWidth +
                        CGFloat(max(apps.count - 1, 0)) * spacing
                    let centeringInset = max(0, (viewportWidth - contentWidth) / 2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: spacing) {
                            ForEach(apps) { item in
                                RunningAppIconCard(
                                    item: item,
                                    isSelected: selection?.isSelected(appID: item.id) == true,
                                    onClicked: onAppClicked,
                                    onDoubleClicked: onAppDoubleClicked
                                )
                                .frame(width: cardWidth)
                            }
                        }
                        .padding(.horizontal, centeringInset)
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onAreaClicked)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isAreaSelected)
    }
}

private struct RunningAppIconCard: View {
    let item: RunningApplicationItem
    let isSelected: Bool
    let onClicked: (RunningApplicationItem) -> Void
    let onDoubleClicked: (RunningApplicationItem) -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 5) {
            icon
                .frame(width: 38, height: 38)
                .padding(7)
                .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isHovered || isSelected ? 0.28 : 0.12), radius: isHovered || isSelected ? 12 : 5, y: 4)

            Text(item.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 4)
        .background(.white.opacity(isSelected ? 0.16 : (isHovered ? 0.08 : 0)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(isSelected ? 0.88 : (isHovered ? 0.28 : 0)), lineWidth: isSelected ? 2 : 1)
        }
        .scaleEffect(isHovered ? 1.04 : 1)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            onDoubleClicked(item)
        }
        .onTapGesture {
            onClicked(item)
        }
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isHovered)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isSelected)
        .help("Open \(item.name) in the selected Dex column")
    }

    @ViewBuilder
    private var icon: some View {
        if let bundleIdentifier = item.bundleIdentifier,
           let icon = AppIconCache.icon(for: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else if let url = item.url {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.black.opacity(0.72))
        }
    }
}

private struct ActiveModeStrip: View {
    let modes: [ActiveModeInstance]
    let size: CGSize
    let selection: BoardSelection?
    let isAreaSelected: Bool
    let onAreaClicked: () -> Void
    let onModeClicked: (ActiveModeInstance) -> Void
    let onModeDoubleClicked: (ActiveModeInstance) -> Void

    var body: some View {
        let labelWidth = min(118, max(90, size.width * 0.38))
        let chipWidth = min(142, max(112, size.width - labelWidth - 48))

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(isAreaSelected ? 0.15 : 0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            .white.opacity(isAreaSelected ? 0.72 : 0.18),
                            style: StrokeStyle(lineWidth: isAreaSelected ? 2.5 : 1.2, dash: [8, 7])
                        )
                }
                .allowsHitTesting(false)

            HStack(spacing: 14) {
                Label("Active Modes", systemImage: "square.grid.3x1.below.line.grid.1x2")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: labelWidth, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(modes) { mode in
                            ActiveModeChip(
                                mode: mode,
                                isSelected: selection?.isSelected(modeID: mode.id) == true,
                                onClicked: onModeClicked,
                                onDoubleClicked: onModeDoubleClicked
                            )
                            .frame(width: chipWidth)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onAreaClicked)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isAreaSelected)
    }
}

private struct ActiveModeChip: View {
    let mode: ActiveModeInstance
    let isSelected: Bool
    let onClicked: (ActiveModeInstance) -> Void
    let onDoubleClicked: (ActiveModeInstance) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -6) {
                ForEach(Array(mode.windowBindings.prefix(4).enumerated()), id: \.offset) { _, binding in
                    modeIcon(for: binding)
                        .frame(width: 22, height: 22)
                        .padding(4)
                        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                        }
                }
            }
            .frame(height: 30, alignment: .leading)

            Text(mode.modeName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.white.opacity(isSelected ? 0.16 : (isHovered ? 0.08 : 0.035)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(isSelected ? 0.88 : (isHovered ? 0.26 : 0.12)), lineWidth: isSelected ? 2 : 1)
        }
        .scaleEffect(isHovered ? 1.03 : 1)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            onDoubleClicked(mode)
        }
        .onTapGesture {
            onClicked(mode)
        }
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isHovered)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isSelected)
        .help("Return raises \(mode.modeName). Q closes its tracked windows.")
    }

    @ViewBuilder
    private func modeIcon(for binding: ActiveModeWindowBinding) -> some View {
        if let icon = AppIconCache.icon(for: binding.bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black.opacity(0.72))
        }
    }
}

private struct WindowThumbnailCard: View {
    let window: ManagedWindow
    let role: ColumnRole
    let isSelected: Bool
    let onDragChanged: (String, CGPoint) -> Void
    let onDragEnded: (String, CGPoint) -> Void
    let onClicked: (String) -> Void
    let onDoubleClicked: (String) -> Void
    @State private var isDragging = false
    @State private var isPressed = false
    @State private var isHovered = false
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .topLeading) {
                previewImage
                    .zIndex(0)

                appIconBadge
                    .padding(12)
                    .zIndex(2)

                dragHint
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .zIndex(3)

            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .overlay {
                NativeCardInteractionSurface(
                    windowID: window.id,
                    onPressChanged: { isPressed = $0 },
                    onHoverChanged: { isHovered = $0 },
                    onClick: { onClicked($0) },
                    onDoubleClick: { onDoubleClicked($0) },
                    onDragChanged: { translation, screenPoint in
                        isDragging = true
                        dragTranslation = translation
                        onDragChanged(window.id, screenPoint)
                    },
                    onDragEnded: { windowID, screenPoint in
                        isDragging = false
                        dragTranslation = .zero
                        onDragEnded(windowID, screenPoint)
                    }
                )
                .zIndex(10)
            }

            VStack(spacing: 2) {
                Text(window.displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(window.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .offset(dragTranslation)
        .scaleEffect(isDragging ? 1.02 : (isPressed ? 0.985 : (isHovered ? 1.015 : 1)))
        .shadow(
            color: .black.opacity(isDragging ? 0.30 : (isHovered ? 0.18 : 0)),
            radius: isDragging ? 18 : (isHovered ? 12 : 0),
            y: isDragging ? 8 : (isHovered ? 5 : 0)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    .white.opacity(isSelected ? 0.95 : (isHovered ? 0.34 : 0)),
                    lineWidth: isSelected ? 3 : (isHovered ? 1.5 : 0)
                )
        }
        .onHover { isHovered = $0 }
        .zIndex(isDragging ? 100 : 1)
        .animation(.spring(response: 0.18, dampingFraction: 0.82), value: isPressed)
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isHovered)
        .animation(isDragging ? nil : .spring(response: 0.22, dampingFraction: 0.82), value: dragTranslation)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isDragging)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isSelected)
        .help("Drag to another Dex column")
        .accessibilityLabel("\(window.displayTitle), \(role.title)")
    }

    @ViewBuilder
    private var previewImage: some View {
        ZStack {
            if let thumbnail = window.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .shadow(color: .black.opacity(0.34), radius: 18, y: 10)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 46, weight: .semibold))
                    Text("No preview")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
            }
        }
    }

    private var dragHint: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(8)
            .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var appIconBadge: some View {
        appIcon
            .frame(width: 38, height: 38)
            .padding(7)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
    }

    private var appIcon: some View {
        Group {
            if let icon = AppIconCache.icon(for: window.bundleIdentifier) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.72))
            }
        }
    }
}

private struct NativeCardInteractionSurface: NSViewRepresentable {
    let windowID: String
    let onPressChanged: (Bool) -> Void
    let onHoverChanged: (Bool) -> Void
    let onClick: (String) -> Void
    let onDoubleClick: (String) -> Void
    let onDragChanged: (CGSize, CGPoint) -> Void
    let onDragEnded: (String, CGPoint) -> Void

    func makeNSView(context: Context) -> NativeCardInteractionSurfaceView {
        let view = NativeCardInteractionSurfaceView()
        view.windowID = windowID
        view.onPressChanged = onPressChanged
        view.onHoverChanged = onHoverChanged
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: NativeCardInteractionSurfaceView, context: Context) {
        nsView.windowID = windowID
        nsView.onPressChanged = onPressChanged
        nsView.onHoverChanged = onHoverChanged
        nsView.onClick = onClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }
}

private final class NativeCardInteractionSurfaceView: NSView {
    var windowID = ""
    var onPressChanged: ((Bool) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onClick: ((String) -> Void)?
    var onDoubleClick: ((String) -> Void)?
    var onDragChanged: ((CGSize, CGPoint) -> Void)?
    var onDragEnded: ((String, CGPoint) -> Void)?

    private var mouseDownPointInWindow: NSPoint?
    private var trackingAreaRef: NSTrackingArea?
    private var isDragging = false
    private let dragThreshold: CGFloat = 6

    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onHoverChanged?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onHoverChanged?(false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPointInWindow = event.locationInWindow
        isDragging = false
        DispatchQueue.main.async { [weak self] in
            self?.onPressChanged?(true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !windowID.isEmpty,
              let mouseDownPointInWindow else {
            return
        }

        let currentPoint = event.locationInWindow
        let translation = CGSize(
            width: currentPoint.x - mouseDownPointInWindow.x,
            height: mouseDownPointInWindow.y - currentPoint.y
        )

        if !isDragging {
            guard hypot(translation.width, translation.height) >= dragThreshold else {
                return
            }
            isDragging = true
            DispatchQueue.main.async { [weak self] in
                self?.onPressChanged?(false)
            }
        }

        NSCursor.closedHand.set()
        let screenPoint = screenPoint(for: event)
        onDragChanged?(translation, screenPoint)
    }

    override func mouseUp(with event: NSEvent) {
        let shouldDragEnd = isDragging
        let clickedWindowID = windowID
        let screenPoint = screenPoint(for: event)
        mouseDownPointInWindow = nil
        isDragging = false
        NSCursor.openHand.set()

        DispatchQueue.main.async { [weak self] in
            self?.onPressChanged?(false)
            guard !clickedWindowID.isEmpty else { return }
            if shouldDragEnd {
                self?.onDragEnded?(clickedWindowID, screenPoint)
            } else if event.clickCount >= 2 {
                self?.onDoubleClick?(clickedWindowID)
            } else {
                self?.onClick?(clickedWindowID)
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if let scrollView = enclosingScrollView {
            scrollView.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        guard let window = event.window else {
            let point = NSEvent.mouseLocation
            return CGPoint(x: point.x, y: point.y)
        }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        return CGPoint(x: point.x, y: point.y)
    }
}

private struct BoardKeyboardCapture: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> BoardKeyboardCaptureView {
        let view = BoardKeyboardCaptureView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: BoardKeyboardCaptureView, context: Context) {
        nsView.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class BoardKeyboardCaptureView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

private struct ModeNameTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onMove: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel, onMove: onMove)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        field.font = .systemFont(ofSize: 22, weight: .semibold)
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        let isEditing = nsView.window?.firstResponder === nsView.currentEditor()
        if !isEditing && nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        context.coordinator.onMove = onMove
        DispatchQueue.main.async {
            if nsView.window?.firstResponder !== nsView.currentEditor() {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onCancel: () -> Void
        var onMove: (Int) -> Void
        var didRequestFocus = false

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            onCancel: @escaping () -> Void,
            onMove: @escaping (Int) -> Void
        ) {
            self.text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
            self.onMove = onMove
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                text.wrappedValue = control.stringValue
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMove(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                onMove(-1)
                return true
            case #selector(NSResponder.insertTab(_:)):
                onMove(1)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                onMove(-1)
                return true
            default:
                return false
            }
        }
    }
}

private struct SaveModeOverlay: View {
    @Binding var name: String
    let modes: [SavedMode]
    let preview: ModeCapturePreview
    @Binding var selectedModeIndex: Int
    let onMoveSelection: (Int) -> Void
    let onSaveNew: () -> Void
    let onReplace: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save Mode")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Capture the assigned windows on this desktop.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.72))
                }

                ModeNameTextField(
                    text: $name,
                    placeholder: "Mode name",
                    onSubmit: {
                        selectedModeIndex >= 0 ? onReplace() : onSaveNew()
                    },
                    onCancel: onCancel,
                    onMove: onMoveSelection
                )
                    .frame(height: 32)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.20), lineWidth: 1)
                    }

                captureSummary

                VStack(alignment: .leading, spacing: 8) {
                    SaveModeChoiceRow(
                        title: "Save as new mode",
                        detail: "Return",
                        windows: capturedWindows,
                        isSelected: selectedModeIndex < 0,
                        action: {
                            selectedModeIndex = -1
                            onSaveNew()
                        }
                    )
                    ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                        SaveModeChoiceRow(
                            title: "Replace \(mode.name)",
                            detail: mode.shortcutLabel,
                            windows: mode.windows,
                            isSelected: selectedModeIndex == index,
                            action: {
                                selectedModeIndex = index
                                onReplace()
                            }
                        )
                    }
                }
            }
            .frame(width: 560)
            .padding(22)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 38, y: 18)
            .onExitCommand(perform: onCancel)
            .onSubmit {
                selectedModeIndex >= 0 ? onReplace() : onSaveNew()
            }
            .onMoveCommand { direction in
                switch direction {
                case .down:
                    onMoveSelection(1)
                case .up:
                    onMoveSelection(-1)
                default:
                    break
                }
            }
        }
    }

    private var captureSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Current arrangement")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(capturedWindows.count) windows")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                ForEach(ColumnRole.allCases) { role in
                    ModeCaptureRoleGroup(
                        role: role,
                        windows: preview.windowsByRole[role, default: []]
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var capturedWindows: [SavedModeWindow] {
        ColumnRole.allCases.flatMap { preview.windowsByRole[$0, default: []] }
    }

}

private struct ModeCaptureRoleGroup: View {
    let role: ColumnRole
    let windows: [SavedModeWindow]

    var body: some View {
        HStack(spacing: -5) {
            Text(String(role.title.prefix(1)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            if windows.isEmpty {
                Image(systemName: "minus")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 18, height: 18)
            } else {
                ForEach(Array(windows.prefix(3).enumerated()), id: \.element.id) { _, window in
                    AppBundleIcon(bundleIdentifier: window.bundleIdentifier, fallbackSystemName: "app.dashed")
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                        }
                }
            }
        }
        .help("\(role.title): \(windows.count) windows")
    }
}

private struct AppBundleIcon: View {
    let bundleIdentifier: String
    let fallbackSystemName: String

    var body: some View {
        if let icon = AppIconCache.icon(for: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: fallbackSystemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black.opacity(0.72))
        }
    }
}

private struct SaveModeChoiceRow: View {
    let title: String
    let detail: String
    let windows: [SavedModeWindow]
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SaveModeIconCluster(windows: windows)
                    .frame(width: 84, height: 30, alignment: .leading)

                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Text(detail)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.10), in: Capsule())

                if isSelected {
                    Image(systemName: "return")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(isSelected ? 0.16 : 0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.72 : 0.12), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SaveModeIconCluster: View {
    let windows: [SavedModeWindow]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(windows.prefix(4).enumerated()), id: \.element.id) { _, window in
                AppBundleIcon(bundleIdentifier: window.bundleIdentifier, fallbackSystemName: "app.dashed")
                    .frame(width: 18, height: 18)
                    .padding(3)
                    .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                    }
            }
            if windows.isEmpty {
                Image(systemName: "app.dashed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(width: 24, height: 24)
            }
        }
    }
}

private struct ModeLaunchConfirmationOverlay: View {
    let mode: SavedMode
    let policy: ModeLaunchPolicy
    let onPolicyChange: (ModeLaunchPolicy) -> Void
    let onLaunch: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Press \(mode.shortcutLabel) again to launch")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    Text(mode.shortcutLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.74))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.12), in: Capsule())
                }

                HStack(spacing: -6) {
                    ForEach(Array(mode.windows.prefix(6).enumerated()), id: \.offset) { _, window in
                        modeIcon(bundleIdentifier: window.bundleIdentifier)
                            .frame(width: 28, height: 28)
                            .padding(5)
                            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    LaunchPolicyRow(
                        title: "Quit elsewhere and reopen here",
                        isSelected: policy == .quitElsewhereAndReopenHere
                    )
                    LaunchPolicyRow(
                        title: "Open new here",
                        isSelected: policy == .openNewHere
                    )
                }
            }
            .frame(width: 470)
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 38, y: 18)
            .overlay {
                BoardKeyboardCapture { event in
                    handleKeyDown(event)
                }
                .frame(width: 1, height: 1)
                .opacity(0.001)
            }
        }
    }

    @ViewBuilder
    private func modeIcon(bundleIdentifier: String) -> some View {
        if let icon = AppIconCache.icon(for: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black.opacity(0.72))
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.option),
           modeSlotNumber(forKeyCode: event.keyCode) == mode.slot {
            onLaunch()
            return true
        }

        switch event.keyCode {
        case 53:
            onCancel()
            return true
        case 36, 76:
            onLaunch()
            return true
        case 123, 126:
            onPolicyChange(.quitElsewhereAndReopenHere)
            return true
        case 124, 125:
            onPolicyChange(.openNewHere)
            return true
        default:
            return false
        }
    }
}

private struct LaunchPolicyRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.caption.weight(.bold))
            Text(title)
                .font(.callout.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.white.opacity(isSelected ? 0.92 : 0.62))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(isSelected ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BoardPaletteOverlay: View {
    @Binding var query: String
    let results: [BoardPaletteResult]
    let shortcuts: [(String, String)]
    let isLoading: Bool
    @Binding var selectedIndex: Int
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 0) {
                searchHeader

                Divider()
                    .overlay(.white.opacity(0.18))

                if BoardPaletteSearch.isShowingShortcutHelp(query: query) {
                    shortcutHelpContent
                        .padding(22)
                } else {
                    searchResultsContent
                }
            }
            .frame(width: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 38, y: 18)
            .onChange(of: query) {
                selectedIndex = 0
            }
            .onChange(of: results.map(\.id)) {
                selectedIndex = min(selectedIndex, max(results.count - 1, 0))
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            PaletteSearchTextField(
                text: $query,
                onSubmit: submitIfSearchIsVisible,
                onCancel: onCancel,
                onMove: onMove
            )
            .frame(height: 24)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var shortcutHelpContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ShortcutHelpRow(keys: "Arrows", label: "Move selection")
                ShortcutHelpRow(keys: "Enter", label: "Open selected item")
                ShortcutHelpRow(keys: "Double-click", label: "Open and promote")
                ShortcutHelpRow(keys: "Q", label: "Close or quit selected")
                ShortcutHelpRow(keys: "Option + Tab", label: "Switch area")
                ShortcutHelpRow(keys: "Option + Arrows", label: "Move/open into column")
                ShortcutHelpRow(keys: "/", label: "Search apps and Dia tabs")
                ShortcutHelpRow(keys: "Option + X", label: "Cleanup checklist")
            }

            Divider()
                .overlay(.white.opacity(0.18))

            VStack(alignment: .leading, spacing: 8) {
                Text("App Shortcuts")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.88))
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, shortcut in
                    ShortcutHelpRow(keys: shortcut.1, label: shortcut.0)
                }
            }
        }
    }

    private var searchResultsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                Text(isLoading ? "Loading apps and Dia tabs..." : "No matches")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            BoardPaletteResultRow(
                                result: result,
                                isSelected: index == selectedIndex
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIndex = index
                                onSubmit()
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 360)
            }
        }
    }

    private func submitIfSearchIsVisible() {
        guard !BoardPaletteSearch.isShowingShortcutHelp(query: query) else { return }
        onSubmit()
    }
}

private struct PaletteSearchTextField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onMove: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel, onMove: onMove)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.placeholderString = ""
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        field.font = .systemFont(ofSize: 18, weight: .medium)
        field.delegate = context.coordinator
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        DispatchQueue.main.async {
            context.coordinator.didRequestFocus = true
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        let isEditing = nsView.window?.firstResponder === nsView.currentEditor()
        if !isEditing && nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        context.coordinator.onMove = onMove
        guard !context.coordinator.didRequestFocus else { return }
        DispatchQueue.main.async {
            context.coordinator.didRequestFocus = true
            if nsView.window?.firstResponder !== nsView.currentEditor() {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onCancel: () -> Void
        var onMove: (Int) -> Void
        var didRequestFocus = false

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            onCancel: @escaping () -> Void,
            onMove: @escaping (Int) -> Void
        ) {
            self.text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
            self.onMove = onMove
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if field.stringValue.hasPrefix("/") {
                let cleaned = String(field.stringValue.drop { $0 == "/" })
                field.stringValue = cleaned
                text.wrappedValue = cleaned
                return
            }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                text.wrappedValue = control.stringValue
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMove(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                onMove(-1)
                return true
            default:
                return false
            }
        }
    }
}

private struct BoardPaletteResultRow: View {
    let result: BoardPaletteResult
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            if let accessory = result.rightAccessory {
                Text(accessory)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.10), in: Capsule())
            }

            if result.isSavedMode {
                Text("Mode")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.10), in: Capsule())
            }

            if result.isModeManagementAction {
                Text("Settings")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.10), in: Capsule())
            }

            if result.isDiaTab {
                Text("Dia tab")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.10), in: Capsule())
            }

            if isSelected {
                Image(systemName: "return")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(isSelected ? 0.18 : (isHovered ? 0.10 : 0.04)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(isHovered ? 1.01 : 1)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.20, dampingFraction: 0.80), value: isHovered)
    }

    @ViewBuilder
    private var icon: some View {
        switch result {
        case .manageModes:
            Image(systemName: "gearshape")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        case .savedMode:
            Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        case .application(let application):
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
                .scaledToFit()
        case .diaTab(_, _, let parentBundleIdentifier):
            if let icon = AppIconCache.icon(for: parentBundleIdentifier) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

private struct CleanupOverlay: View {
    let candidates: [CleanupCandidate]
    @Binding var selectedIDs: Set<String>
    @Binding var selectedIndex: Int
    let onClean: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick Cleanup")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Space toggles, Enter closes selected items, Escape cancels.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    Spacer()
                }

                if candidates.isEmpty {
                    Text("No Twitter, Instagram, WhatsApp, or Superhuman windows found on this display.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                            CleanupCandidateRow(
                                candidate: candidate,
                                number: index + 1,
                                isSelected: index == selectedIndex,
                                isChecked: selectedIDs.contains(candidate.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIndex = index
                                toggle(candidate)
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Clean") {
                        onClean()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedIDs.isEmpty)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(22)
            .frame(width: 520)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 38, y: 18)
            .overlay {
                BoardKeyboardCapture { event in
                    handleKeyDown(event)
                }
                .frame(width: 1, height: 1)
                .opacity(0.001)
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            onCancel()
            return true
        case 36, 76:
            onClean()
            return true
        case 125:
            moveSelection(1)
            return true
        case 126:
            moveSelection(-1)
            return true
        case 49:
            toggleSelected()
            return true
        default:
            break
        }

        if let key = event.charactersIgnoringModifiers,
           let number = Int(key),
           candidates.indices.contains(number - 1) {
            let index = number - 1
            selectedIndex = index
            toggle(candidates[index])
            return true
        }

        return false
    }

    private func moveSelection(_ delta: Int) {
        guard !candidates.isEmpty else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), candidates.count - 1)
    }

    private func toggleSelected() {
        guard candidates.indices.contains(selectedIndex) else { return }
        toggle(candidates[selectedIndex])
    }

    private func toggle(_ candidate: CleanupCandidate) {
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else {
            selectedIDs.insert(candidate.id)
        }
    }
}

private struct CleanupCandidateRow: View {
    let candidate: CleanupCandidate
    let number: Int
    let isSelected: Bool
    let isChecked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 18)

            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isChecked ? .green : .white.opacity(0.54))

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(candidate.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(isSelected ? 0.18 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ShortcutHelpRow: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(label)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
    }
}

private struct HUDView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.72), in: Capsule())
    }
}

/// Bottom-center coach card for the in-board guided tour (Act 3). Non-blocking: the
/// board keeps keyboard ownership so each step advances when the user acts.
private struct TourCoachCard: View {
    let step: OnboardingTourStep
    let exampleBinding: AppShortcutBinding?
    let legendShortcuts: [(String, String)]
    let onSkip: () -> Void
    let onDone: () -> Void

    private var stepNumber: Int { step.rawValue + 1 }
    private var stepCount: Int { OnboardingTourStep.allCases.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Step \(stepNumber) of \(stepCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if step != .closing {
                    Button("Skip", action: onSkip)
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if step == .shortcut, !legendShortcuts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(legendShortcuts.enumerated()), id: \.offset) { _, shortcut in
                        ShortcutHelpRow(keys: shortcut.1, label: shortcut.0)
                    }
                }
                Text("Make these your own — any app, any key — in the Dex window.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if step == .closing {
                HStack {
                    Spacer()
                    Button(action: onDone) {
                        Text("Done")
                            .font(.headline)
                            .frame(minWidth: 90)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 2)
            }
        }
        .padding(22)
        .frame(width: 460, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 38, y: 18)
    }

    private var title: String {
        switch step {
        case .navigate:
            return "Use ← → ↑ ↓ to move between columns and shelves"
        case .jump:
            return "Press Return to jump to the selected window"
        case .moveColumn:
            return "Hold ⌥ Option and press ← or → to move this window to another column"
        case .shortcut:
            if let binding = exampleBinding, !binding.key.isEmpty {
                return "Press \(binding.keyLabel) to open \(binding.displayName) in this column"
            }
            return "Press an app key to open it in this column"
        case .closing:
            return "You're all set"
        }
    }

    private var detail: String? {
        switch step {
        case .navigate:
            return "The highlight follows your arrows across the three columns and the shelves below."
        case .jump:
            return nil
        case .moveColumn:
            return nil
        case .shortcut:
            return "Each key opens (or moves) its app straight into the focused column."
        case .closing:
            return "/ opens the palette · ⌥S saves this layout as a Mode · ⌥1–9 recalls Modes · Q closes things · Esc leaves"
        }
    }
}

/// One-line dismissible key legend shown along the board's bottom edge for the first
/// few sessions after the tour completes.
private struct BoardLegendBar: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            legendItem("/", "Palette")
            legendItem("⌥S", "Save Mode")
            legendItem("⌥1–9", "Modes")
            legendItem("Q", "Close")
            legendItem("Esc", "Leave")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
    }

    private func legendItem(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}
