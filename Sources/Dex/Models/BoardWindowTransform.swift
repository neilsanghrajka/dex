import CoreGraphics
import Foundation

enum BoardWindowTransform: Equatable {
    case maximized
    case wide

    func targetFrame(visibleFrame: CGRect) -> CGRect {
        switch self {
        case .maximized:
            MaximizedWindowGeometry.frame(visibleFrame: visibleFrame)
        case .wide:
            GridLayout(
                visibleFrame: visibleFrame,
                kind: .leftNarrowCenter
            ).rect(for: .right)
        }
    }

    var actionName: String {
        switch self {
        case .maximized: "Maximized"
        case .wide: "Made wide"
        }
    }
}

struct BoardWindowTransformState: Equatable {
    let normalFrame: CGRect
    let activeTransform: BoardWindowTransform
}

enum BoardWindowTransformTransition: Equatable {
    case apply(frame: CGRect, nextState: BoardWindowTransformState)
    case restore(frame: CGRect)
}

enum BoardWindowTransformLogic {
    static func transition(
        currentState: BoardWindowTransformState?,
        requestedTransform: BoardWindowTransform,
        currentFrame: CGRect,
        visibleFrame: CGRect
    ) -> BoardWindowTransformTransition {
        if let currentState, currentState.activeTransform == requestedTransform {
            return .restore(frame: currentState.normalFrame)
        }

        let normalFrame = currentState?.normalFrame ?? currentFrame.integral
        return .apply(
            frame: requestedTransform.targetFrame(visibleFrame: visibleFrame),
            nextState: BoardWindowTransformState(
                normalFrame: normalFrame,
                activeTransform: requestedTransform
            )
        )
    }
}
