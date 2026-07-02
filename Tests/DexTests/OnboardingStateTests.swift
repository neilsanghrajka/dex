import XCTest
@testable import Dex

final class OnboardingStateTests: XCTestCase {
    func testTourStepAdvancesInOrderThenFinishes() {
        XCTAssertEqual(OnboardingTourStep.navigate.next, .jump)
        XCTAssertEqual(OnboardingTourStep.jump.next, .moveColumn)
        XCTAssertEqual(OnboardingTourStep.moveColumn.next, .shortcut)
        XCTAssertEqual(OnboardingTourStep.shortcut.next, .closing)
        XCTAssertNil(OnboardingTourStep.closing.next, "The closing card is the last step")
    }

    func testTourStepCoversEveryCase() {
        XCTAssertEqual(OnboardingTourStep.allCases.count, 5)
    }

    func testOnboardingFlagDefaultsUnsetAndPersists() {
        let suiteName = "DexTests.onboardingFlag"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        XCTAssertFalse(store.hasCompletedOnboarding, "First run should not have completed onboarding")

        store.hasCompletedOnboarding = true
        XCTAssertTrue(LayoutStore(defaults: defaults).hasCompletedOnboarding, "Flag must survive a reload")
    }

    func testBoardLegendSettingsDefaultsAndPersistence() {
        let suiteName = "DexTests.boardLegend"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LayoutStore(defaults: defaults)

        XCTAssertTrue(store.showsBoardLegend, "Legend is enabled by default")
        XCTAssertEqual(store.boardLegendSessionsRemaining, 0, "No reinforcement sessions before the tour completes")

        store.showsBoardLegend = false
        store.boardLegendSessionsRemaining = 5

        let reloaded = LayoutStore(defaults: defaults)
        XCTAssertFalse(reloaded.showsBoardLegend)
        XCTAssertEqual(reloaded.boardLegendSessionsRemaining, 5)
    }
}
