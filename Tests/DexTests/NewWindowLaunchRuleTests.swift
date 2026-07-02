import XCTest
@testable import Dex

final class NewWindowLaunchRuleTests: XCTestCase {
    func testDefaultsIncludeDiaAndSkipPerplexity() {
        let names = NewWindowLaunchRule.defaults.map(\.displayName)

        XCTAssertEqual(names, ["Terminal", "Claude", "Dia", "Codex"])
        XCTAssertFalse(names.contains("Perplexity"))
    }

    func testMatchesByBundleIdentifier() {
        let rule = NewWindowLaunchRule(
            displayName: "Dia",
            bundleIdentifiers: ["company.thebrowser.dia"],
            appNames: ["Dia"]
        )

        XCTAssertTrue(rule.matches(bundleIdentifiers: ["company.thebrowser.dia"], appNames: ["Browser"]))
        XCTAssertFalse(rule.matches(bundleIdentifiers: ["ai.perplexity.mac"], appNames: ["Perplexity"]))
    }

    func testMatchesByAppNameFallback() {
        let rule = NewWindowLaunchRule(
            displayName: "Notes",
            bundleIdentifiers: [],
            appNames: ["Notes"]
        )

        XCTAssertTrue(rule.matches(bundleIdentifiers: [], appNames: ["Apple Notes"]))
        XCTAssertTrue(rule.matches(bundleIdentifiers: [], appNames: ["Notes"]))
        XCTAssertFalse(rule.matches(bundleIdentifiers: [], appNames: ["Reminders"]))
    }

    func testLaunchSpecMergesCandidateIdentityWithRuleIdentity() {
        let rule = NewWindowLaunchRule(
            displayName: "Claude",
            bundleIdentifiers: ["com.anthropic.claudefordesktop"],
            appNames: ["Claude"],
            newWindowMenuItemTitles: ["New Window"]
        )

        let spec = rule.launchSpec(
            label: "Claude",
            bundleIdentifiers: ["com.anthropic.claude"],
            appNames: ["Claude Desktop"]
        )

        XCTAssertTrue(spec.forceNew)
        XCTAssertEqual(spec.bundleIdentifiers, ["com.anthropic.claude", "com.anthropic.claudefordesktop"])
        XCTAssertEqual(spec.newWindowMenuItemTitles, ["New Window"])
    }
}
