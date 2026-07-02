import Foundation

/// The stage of the first-run wizard shown inside the main window (Acts 1 & 2).
/// Act 3 (the guided in-board tour) is tracked separately by `OnboardingTourStep`.
enum OnboardingPhase: Equatable {
    /// Welcome screen with a three-column visual and a "Get started" button.
    case welcome
    /// Permission checklist (Accessibility, Input Monitoring, Screen Recording).
    case permissions
    /// The summon gate: "Press ⌥ Option twice" waiting on the real gesture.
    case summon
}

/// A single step of the guided tour that runs inside the real Arrange Board.
/// Each step advances only once the user actually performs its action.
enum OnboardingTourStep: Int, CaseIterable, Equatable {
    /// Move the selection with the arrow keys.
    case navigate
    /// Press Return to jump to the selected window.
    case jump
    /// Hold Option and press ← / → to move a window across columns.
    case moveColumn
    /// Press a mapped app-shortcut key to open an app in the column.
    case shortcut
    /// Closing summary card with a Done button.
    case closing

    /// The next step, or `nil` when the tour is finished after `closing`.
    var next: OnboardingTourStep? {
        OnboardingTourStep(rawValue: rawValue + 1)
    }
}
