import CoreGraphics

struct CompactBoardGeometry: Equatable {
    // Roughly half of the display area (0.72 x 0.68 = 0.49) while retaining
    // the wide, top-attached island silhouette.
    static let widthRatio: CGFloat = 0.72
    static let heightRatio: CGFloat = 0.68
    static let minimumWidth: CGFloat = 900
    static let maximumWidth: CGFloat = 1_800
    static let minimumHeight: CGFloat = 560
    static let maximumHeight: CGFloat = 1_000
    static let screenMargin: CGFloat = 16
    static let virtualSeedSize = CGSize(width: 160, height: 8)

    let expandedFrame: CGRect
    let collapsedFrame: CGRect
    let contentTopInset: CGFloat

    init(display: DisplayInfo) {
        let frame = display.frame
        let availableWidth = max(1, frame.width - Self.screenMargin * 2)
        let availableHeight = max(1, frame.height - Self.screenMargin * 2)
        let targetWidth = min(
            Self.maximumWidth,
            max(Self.minimumWidth, frame.width * Self.widthRatio)
        )
        let targetHeight = min(
            Self.maximumHeight,
            max(Self.minimumHeight, frame.height * Self.heightRatio)
        )
        let width = min(availableWidth, targetWidth).rounded()
        let height = min(availableHeight, targetHeight).rounded()

        expandedFrame = CGRect(
            x: (frame.midX - width / 2).rounded(),
            y: (frame.maxY - height).rounded(),
            width: width,
            height: height
        )

        let topObscuredHeight = max(0, frame.maxY - display.visibleFrame.maxY)
        contentTopInset = max(28, topObscuredHeight, display.topSafeAreaInset)

        let notchGap = display.notchGap
        let seedWidth = min(
            width,
            notchGap.map { max(Self.virtualSeedSize.width, $0.width) } ?? Self.virtualSeedSize.width
        )
        let seedHeight = min(
            height,
            max(Self.virtualSeedSize.height, display.topSafeAreaInset)
        )
        let seedMidX = notchGap?.midX ?? frame.midX
        collapsedFrame = CGRect(
            x: (seedMidX - seedWidth / 2).rounded(),
            y: (frame.maxY - seedHeight).rounded(),
            width: seedWidth.rounded(),
            height: seedHeight.rounded()
        )
    }

    func localPoint(fromScreenPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - expandedFrame.minX,
            y: expandedFrame.maxY - point.y
        )
    }
}

enum BoardPresentationStyle: Equatable {
    case fullScreen
    case compactIsland(CompactBoardGeometry)

    var isCompact: Bool {
        if case .compactIsland = self { return true }
        return false
    }

    var compactGeometry: CompactBoardGeometry? {
        guard case .compactIsland(let geometry) = self else { return nil }
        return geometry
    }
}
