import AppKit
import XCTest
@testable import Dex

final class CompactBoardGeometryTests: XCTestCase {
    @MainActor
    func testBoardKeyboardCaptureClaimsFirstResponderWithoutClick() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let capture = BoardKeyboardCaptureView(frame: .zero)
        window.contentView = capture
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(capture.claimKeyboardFocus())
        XCTAssertTrue(window.firstResponder === capture)

        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    @MainActor
    func testBoardKeyboardCaptureDispatchesOneArrowCommandPerPhysicalPress() throws {
        let capture = BoardKeyboardCaptureView(frame: .zero)
        var commandCount = 0
        capture.onKeyDown = { _ in
            commandCount += 1
            return true
        }

        let firstDown = try XCTUnwrap(directionalEvent(type: .keyDown, keyCode: 124))
        let duplicateInitialDown = try XCTUnwrap(directionalEvent(type: .keyDown, keyCode: 124))
        let keyUp = try XCTUnwrap(directionalEvent(type: .keyUp, keyCode: 124))
        let secondPressDown = try XCTUnwrap(directionalEvent(type: .keyDown, keyCode: 124))

        capture.keyDown(with: firstDown)
        capture.keyDown(with: duplicateInitialDown)
        XCTAssertEqual(commandCount, 1)

        capture.keyUp(with: keyUp)
        capture.keyDown(with: secondPressDown)
        XCTAssertEqual(commandCount, 2)
    }

    func testDirectionalNavigationDoesNotSkipAdjacentCardInEitherPresentation() {
        let presentationScales: [(origin: CGRect, adjacent: CGRect, farther: CGRect)] = [
            // Full-screen board coordinates.
            (
                CGRect(x: 80, y: 90, width: 200, height: 140),
                CGRect(x: 550, y: 170, width: 200, height: 140),
                CGRect(x: 1_030, y: 90, width: 200, height: 140)
            ),
            // Compact Island board coordinates.
            (
                CGRect(x: 45, y: 45, width: 90, height: 70),
                CGRect(x: 280, y: 85, width: 90, height: 70),
                CGRect(x: 520, y: 45, width: 90, height: 70)
            )
        ]

        for scale in presentationScales {
            XCTAssertEqual(
                BoardNavigationGeometry.targetIndex(
                    from: scale.origin,
                    candidates: [scale.adjacent, scale.farther],
                    direction: .right
                ),
                0
            )
        }
    }

    func testDirectionalNavigationVisitsOpenWindowsBeforeRunningAppsInEitherPresentation() {
        let presentationScales: [(origin: CGRect, openWindows: CGRect, runningApps: CGRect)] = [
            // Full-screen board coordinates.
            (
                CGRect(x: 700, y: 170, width: 200, height: 140),
                CGRect(x: 750, y: 650, width: 200, height: 140),
                CGRect(x: 700, y: 900, width: 200, height: 80)
            ),
            // Compact Island board coordinates.
            (
                CGRect(x: 350, y: 80, width: 100, height: 80),
                CGRect(x: 375, y: 320, width: 100, height: 80),
                CGRect(x: 350, y: 440, width: 100, height: 56)
            )
        ]

        for scale in presentationScales {
            XCTAssertEqual(
                BoardNavigationGeometry.targetIndex(
                    from: scale.origin,
                    candidates: [scale.openWindows, scale.runningApps],
                    direction: .down
                ),
                0
            )
        }
    }

    func testRightPrefersAlignedPaneOverOpenWindowsBelow() {
        let origin = CGRect(x: 500, y: 100, width: 180, height: 130)
        let rightPane = CGRect(x: 900, y: 100, width: 180, height: 130)
        let openWindow = CGRect(x: 690, y: 500, width: 180, height: 130)

        XCTAssertEqual(
            BoardNavigationGeometry.targetIndex(
                from: origin,
                candidates: [openWindow, rightPane],
                direction: .right
            ),
            1
        )
    }

    func testDownPrefersOpenWindowsOverSlightlyLowerSidePane() {
        let origin = CGRect(x: 500, y: 100, width: 180, height: 130)
        let sidePane = CGRect(x: 900, y: 120, width: 180, height: 130)
        let openWindow = CGRect(x: 520, y: 500, width: 180, height: 130)

        XCTAssertEqual(
            BoardNavigationGeometry.targetIndex(
                from: origin,
                candidates: [sidePane, openWindow],
                direction: .down
            ),
            1
        )
    }

    func testVerticalNavigationStaysInRoleBeforeEnteringShelves() {
        let origin = CGRect(x: 40, y: 60, width: 180, height: 120)
        let runningApps = CGRect(x: 400, y: 720, width: 700, height: 80)
        let openWindow = CGRect(x: 500, y: 520, width: 180, height: 120)
        let lowerLeftWindow = CGRect(x: 40, y: 250, width: 180, height: 120)
        let candidates = [runningApps, openWindow, lowerLeftWindow]
        let regions: [BoardNavigationRegion] = [.runningApps, .openWindows, .role(.left)]

        XCTAssertEqual(
            BoardNavigationGeometry.semanticTargetIndex(
                from: origin,
                currentRegion: .role(.left),
                candidates: candidates,
                candidateRegions: regions,
                roleFrames: [.left: CGRect(x: 20, y: 20, width: 300, height: 650)],
                direction: .down
            ),
            2
        )
    }

    func testVerticalNavigationVisitsOpenWindowsBeforeRunningAppsRegardlessOfCardAlignment() {
        let origin = CGRect(x: 400, y: 80, width: 180, height: 120)
        let runningApps = CGRect(x: 380, y: 720, width: 700, height: 80)
        let diagonallyPlacedOpenWindow = CGRect(x: 850, y: 500, width: 180, height: 120)

        XCTAssertEqual(
            BoardNavigationGeometry.semanticTargetIndex(
                from: origin,
                currentRegion: .role(.center),
                candidates: [runningApps, diagonallyPlacedOpenWindow],
                candidateRegions: [.runningApps, .openWindows],
                roleFrames: [.center: CGRect(x: 320, y: 20, width: 900, height: 450)],
                direction: .down
            ),
            1
        )
    }

    func testVerticalNavigationUsesGenuinelyStackedRoleBeforeOpenWindows() {
        let origin = CGRect(x: 40, y: 40, width: 180, height: 120)
        let openWindow = CGRect(x: 500, y: 600, width: 180, height: 120)
        let bottomLeft = CGRect(x: 40, y: 300, width: 180, height: 120)
        let roleFrames: [ColumnRole: CGRect] = [
            .topLeft: CGRect(x: 20, y: 20, width: 300, height: 250),
            .bottomLeft: CGRect(x: 20, y: 280, width: 300, height: 250),
            .right: CGRect(x: 330, y: 20, width: 600, height: 510)
        ]

        XCTAssertEqual(
            BoardNavigationGeometry.semanticTargetIndex(
                from: origin,
                currentRegion: .role(.topLeft),
                candidates: [openWindow, bottomLeft],
                candidateRegions: [.openWindows, .role(.bottomLeft)],
                roleFrames: roleFrames,
                direction: .down
            ),
            1
        )
    }

    func testTwoByTwoNavigationFollowsRowsAndColumns() {
        let topLeft = CGRect(x: 0, y: 0, width: 180, height: 120)
        let topRight = CGRect(x: 220, y: 0, width: 180, height: 120)
        let bottomLeft = CGRect(x: 0, y: 160, width: 180, height: 120)
        let bottomRight = CGRect(x: 220, y: 160, width: 180, height: 120)
        let candidates = [topRight, bottomLeft, bottomRight]

        XCTAssertEqual(
            BoardNavigationGeometry.targetIndex(from: topLeft, candidates: candidates, direction: .right),
            0
        )
        XCTAssertEqual(
            BoardNavigationGeometry.targetIndex(from: topLeft, candidates: candidates, direction: .down),
            1
        )
    }

    func testDirectionalNavigationFollowsEveryGridLayoutAtFullAndCompactScales() throws {
        let sizes = [
            CGSize(width: 1_920, height: 1_000),
            CGSize(width: 760, height: 420)
        ]

        for size in sizes {
            for kind in BoardLayoutKind.allCases {
                let grid = GridLayout(
                    visibleFrame: CGRect(origin: .zero, size: size),
                    gutter: 10,
                    kind: kind
                )

                switch kind {
                case .threeColumn, .wideCenter:
                    try assertNavigation(
                        in: grid,
                        from: .center,
                        direction: .right,
                        reaches: .right
                    )
                case .halves, .leftNarrowCenter, .centerRightNarrow:
                    try assertNavigation(
                        in: grid,
                        from: .left,
                        direction: .right,
                        reaches: .right
                    )
                case .twoByTwo:
                    try assertNavigation(
                        in: grid,
                        from: .topLeft,
                        direction: .right,
                        reaches: .topRight
                    )
                    try assertNavigation(
                        in: grid,
                        from: .topLeft,
                        direction: .down,
                        reaches: .bottomLeft
                    )
                case .leftMainRightStack:
                    try assertNavigation(
                        in: grid,
                        from: .left,
                        direction: .right,
                        reaches: .topRight
                    )
                    try assertNavigation(
                        in: grid,
                        from: .topRight,
                        direction: .down,
                        reaches: .bottomRight
                    )
                case .leftStackRightMain:
                    try assertNavigation(
                        in: grid,
                        from: .topLeft,
                        direction: .right,
                        reaches: .right
                    )
                    try assertNavigation(
                        in: grid,
                        from: .topLeft,
                        direction: .down,
                        reaches: .bottomLeft
                    )
                }
            }
        }
    }

    func testPresentationModeDefaultsToFullScreenAndPersists() {
        let suiteName = "DexTests.boardPresentationMode"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        XCTAssertEqual(store.boardPresentationMode, .fullScreen)

        store.boardPresentationMode = .compactIsland
        XCTAssertEqual(LayoutStore(defaults: defaults).boardPresentationMode, .compactIsland)
    }

    func testExternalDisplayUsesResponsiveTopCenteredFrameAndVirtualSeed() {
        let display = DisplayInfo(
            id: "external",
            frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_055),
            name: "External"
        )

        let geometry = CompactBoardGeometry(display: display)

        XCTAssertEqual(geometry.expandedFrame.width, 1_382, accuracy: 1)
        XCTAssertEqual(geometry.expandedFrame.height, 734, accuracy: 1)
        XCTAssertEqual(
            geometry.expandedFrame.width * geometry.expandedFrame.height /
                (display.frame.width * display.frame.height),
            0.49,
            accuracy: 0.01
        )
        XCTAssertEqual(geometry.expandedFrame.midX, display.frame.midX, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.maxY, display.frame.maxY, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.size, CompactBoardGeometry.virtualSeedSize)
        XCTAssertEqual(geometry.collapsedFrame.midX, display.frame.midX, accuracy: 0.5)
    }

    func testGeometrySupportsNegativeDisplayOrigins() {
        let display = DisplayInfo(
            id: "left-display",
            frame: CGRect(x: -2_560, y: 240, width: 2_560, height: 1_440),
            visibleFrame: CGRect(x: -2_560, y: 240, width: 2_560, height: 1_416),
            name: "Left External"
        )

        let geometry = CompactBoardGeometry(display: display)

        XCTAssertEqual(geometry.expandedFrame.width, CompactBoardGeometry.maximumWidth)
        XCTAssertEqual(geometry.expandedFrame.midX, display.frame.midX, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.maxY, display.frame.maxY, accuracy: 0.5)
        XCTAssertTrue(display.frame.contains(geometry.expandedFrame))

        let topLeft = CGPoint(x: geometry.expandedFrame.minX, y: geometry.expandedFrame.maxY)
        XCTAssertEqual(geometry.localPoint(fromScreenPoint: topLeft), .zero)
    }

    func testNotchedDisplayUsesPublicAuxiliaryAreaGapAsSeed() {
        let frame = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let display = DisplayInfo(
            id: "notched",
            frame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 944),
            name: "Built-in",
            topSafeAreaInset: 38,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 650, height: 38),
            auxiliaryTopRightArea: CGRect(x: 862, y: 944, width: 650, height: 38)
        )

        let geometry = CompactBoardGeometry(display: display)

        XCTAssertEqual(geometry.collapsedFrame.minX, 650, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.width, 212, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.height, 38, accuracy: 0.5)
        XCTAssertEqual(geometry.contentTopInset, 38, accuracy: 0.5)
    }

    func testSmallDisplayClampsToAvailableBounds() {
        let display = DisplayInfo(
            id: "small",
            frame: CGRect(x: 0, y: 0, width: 700, height: 440),
            visibleFrame: CGRect(x: 0, y: 0, width: 700, height: 416),
            name: "Small"
        )

        let geometry = CompactBoardGeometry(display: display)

        XCTAssertLessThanOrEqual(geometry.expandedFrame.width, display.frame.width - 32)
        XCTAssertLessThanOrEqual(geometry.expandedFrame.height, display.frame.height - 32)
        XCTAssertTrue(display.frame.contains(geometry.expandedFrame))
    }

    private func directionalEvent(type: NSEvent.EventType, keyCode: UInt16) -> NSEvent? {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "\u{F703}",
            charactersIgnoringModifiers: "\u{F703}",
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private func assertNavigation(
        in grid: GridLayout,
        from originRole: ColumnRole,
        direction: BoardNavigationDirection,
        reaches expectedRole: ColumnRole,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let candidateRoles = grid.roles.filter { $0 != originRole }
        let candidateFrames = candidateRoles.map { navigationCardFrame(for: $0, in: grid) }
        let targetIndex = try XCTUnwrap(
            BoardNavigationGeometry.targetIndex(
                from: navigationCardFrame(for: originRole, in: grid),
                candidates: candidateFrames,
                direction: direction
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(candidateRoles[targetIndex], expectedRole, file: file, line: line)
    }

    private func navigationCardFrame(for role: ColumnRole, in grid: GridLayout) -> CGRect {
        let roleRect = grid.rect(for: role)
        let localRoleRect = CGRect(
            x: roleRect.minX - grid.visibleFrame.minX,
            y: grid.visibleFrame.maxY - roleRect.maxY,
            width: roleRect.width,
            height: roleRect.height
        )
        let horizontalInset = min(20, localRoleRect.width * 0.08)
        let verticalInset = min(20, localRoleRect.height * 0.08)
        return CGRect(
            x: localRoleRect.minX + horizontalInset,
            y: localRoleRect.minY + verticalInset,
            width: min(180, max(20, localRoleRect.width - horizontalInset * 2)),
            height: min(120, max(20, localRoleRect.height - verticalInset * 2))
        )
    }

    func testEveryLayoutRoleFitsCompactViewportAndResolvesFromItsCenter() {
        let viewport = CGRect(x: 8, y: 46, width: 742, height: 358)

        for kind in BoardLayoutKind.allCases {
            let grid = GridLayout(visibleFrame: viewport, gutter: 8, kind: kind)
            let roleRects = Dictionary(uniqueKeysWithValues: grid.roles.map { ($0, grid.rect(for: $0)) })

            for role in grid.roles {
                guard let rect = roleRects[role] else {
                    return XCTFail("Missing compact rect for \(kind) / \(role)")
                }
                XCTAssertTrue(
                    viewport.contains(rect),
                    "Compact rect escaped viewport for \(kind) / \(role): \(rect)"
                )
                XCTAssertEqual(
                    BoardDropTargetResolver.role(
                        at: CGPoint(x: rect.midX, y: rect.midY),
                        roleRects: roleRects,
                        roleOrder: grid.roles
                    ),
                    role
                )
            }
        }
    }

    func testDropTargetUsesCompactLocalPointOnNegativeOriginDisplay() {
        let display = DisplayInfo(
            id: "negative",
            frame: CGRect(x: -1_920, y: 120, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: -1_920, y: 120, width: 1_920, height: 1_056),
            name: "Negative"
        )
        let geometry = CompactBoardGeometry(display: display)
        let localRects: [ColumnRole: CGRect] = [
            .left: CGRect(x: 8, y: 40, width: 190, height: 300),
            .center: CGRect(x: 206, y: 40, width: 380, height: 300),
            .right: CGRect(x: 594, y: 40, width: 190, height: 300)
        ]
        let screenPoint = CGPoint(
            x: geometry.expandedFrame.minX + localRects[.right]!.midX,
            y: geometry.expandedFrame.maxY - localRects[.right]!.midY
        )
        let localPoint = geometry.localPoint(fromScreenPoint: screenPoint)

        XCTAssertEqual(
            BoardDropTargetResolver.role(
                at: localPoint,
                roleRects: localRects,
                roleOrder: [.left, .center, .right]
            ),
            .right
        )
    }
}
