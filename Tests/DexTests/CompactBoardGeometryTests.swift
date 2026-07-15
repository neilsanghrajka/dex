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

    func testDirectionalNavigationPrefersAdjacentCardOverFarAlignedCard() {
        let origin = CGPoint(x: 0, y: 0)
        let adjacentCard = CGPoint(x: 220, y: 90)
        let fartherAlignedCard = CGPoint(x: 400, y: 0)

        XCTAssertLessThan(
            BoardNavigationGeometry.score(point: adjacentCard, from: origin, axis: .horizontal),
            BoardNavigationGeometry.score(point: fartherAlignedCard, from: origin, axis: .horizontal)
        )
    }

    func testDirectionalNavigationPrefersOpenWindowsRowOverRunningAppsRow() {
        let origin = CGPoint(x: 0, y: 0)
        let openWindow = CGPoint(x: 200, y: 100)
        let runningApp = CGPoint(x: 0, y: 240)

        XCTAssertLessThan(
            BoardNavigationGeometry.score(point: openWindow, from: origin, axis: .vertical),
            BoardNavigationGeometry.score(point: runningApp, from: origin, axis: .vertical)
        )
    }

    func testDirectionalNavigationDoesNotSkipAdjacentCardInEitherPresentation() {
        let presentationScales: [(origin: CGPoint, adjacent: CGPoint, farther: CGPoint)] = [
            // Full-screen board coordinates.
            (CGPoint(x: 180, y: 160), CGPoint(x: 650, y: 240), CGPoint(x: 1_130, y: 160)),
            // Compact Island board coordinates.
            (CGPoint(x: 90, y: 80), CGPoint(x: 325, y: 120), CGPoint(x: 565, y: 80))
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
        let presentationScales: [(origin: CGPoint, openWindows: CGPoint, runningApps: CGPoint)] = [
            // Full-screen board coordinates.
            (CGPoint(x: 800, y: 240), CGPoint(x: 850, y: 720), CGPoint(x: 800, y: 940)),
            // Compact Island board coordinates.
            (CGPoint(x: 400, y: 120), CGPoint(x: 425, y: 360), CGPoint(x: 400, y: 470))
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
