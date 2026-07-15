import CoreGraphics
import Foundation

enum BoardWindowTransform: Equatable {
    case maximized

    func targetFrame(visibleFrame: CGRect) -> CGRect {
        MaximizedWindowGeometry.frame(visibleFrame: visibleFrame)
    }

    var actionName: String {
        "Maximized"
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
