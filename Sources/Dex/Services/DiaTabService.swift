import Foundation

final class DiaTabService: @unchecked Sendable {
    private static let bundleIdentifier = "company.thebrowser.dia"

    func tabsByWindowID(for windows: [ManagedWindow]) async -> [String: [DiaTab]] {
        let candidates = windows
            .filter { $0.bundleIdentifier == Self.bundleIdentifier }
            .map { DiaWindowCandidate(id: $0.id, title: $0.title) }

        guard !candidates.isEmpty else { return [:] }

        return await Task.detached(priority: .userInitiated) {
            let snapshots = Self.loadTabSnapshots()
            return DiaTabMapper.map(snapshots: snapshots, to: candidates)
        }.value
    }

    func focus(_ tab: DiaTab) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            Self.focusTab(tabID: tab.tabID)
        }.value
    }

    private static func loadTabSnapshots() -> [DiaTabWindowSnapshot] {
        guard let script = NSAppleScript(source: listTabsScript) else { return [] }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return [] }
        return parseTabSnapshots(result.stringValue ?? "")
    }

    private static func focusTab(tabID: String) -> Bool {
        let literal = appleScriptStringLiteral(tabID)
        let source = """
        tell application id "\(bundleIdentifier)"
            repeat with diaWindow in windows
                repeat with diaTab in tabs of diaWindow
                    if ((id of diaTab) as text) is \(literal) then
                        focus diaTab
                        return "true"
                    end if
                end repeat
            end repeat
        end tell
        return "false"
        """

        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return false }
        return (result.stringValue ?? "") == "true"
    }

    private static func parseTabSnapshots(_ value: String) -> [DiaTabWindowSnapshot] {
        var windowsByID: [String: (title: String, tabs: [DiaRawTab])] = [:]
        var order: [String] = []

        for line in value.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 6 else { continue }

            let windowID = fields[0]
            let windowTitle = fields[1]
            let rawTab = DiaRawTab(
                tabID: fields[2],
                title: fields[3],
                url: fields[4],
                isFocused: fields[5].lowercased() == "true"
            )

            if windowsByID[windowID] == nil {
                order.append(windowID)
                windowsByID[windowID] = (windowTitle, [])
            }
            windowsByID[windowID]?.tabs.append(rawTab)
        }

        return order.compactMap { windowID in
            guard let entry = windowsByID[windowID] else { return nil }
            return DiaTabWindowSnapshot(
                diaWindowID: windowID,
                title: entry.title,
                tabs: entry.tabs
            )
        }
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static let listTabsScript = """
    on replaceText(findText, replacementText, sourceText)
        set oldDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to findText
        set parts to text items of sourceText
        set AppleScript's text item delimiters to replacementText
        set resultText to parts as text
        set AppleScript's text item delimiters to oldDelimiters
        return resultText
    end replaceText

    on sanitize(valueText)
        set fieldDelimiter to ASCII character 9
        set sourceText to valueText as text
        set sourceText to my replaceText(fieldDelimiter, " ", sourceText)
        set sourceText to my replaceText(linefeed, " ", sourceText)
        set sourceText to my replaceText(return, " ", sourceText)
        return sourceText
    end sanitize

    set fieldDelimiter to ASCII character 9
    set outputLines to {}
    tell application id "company.thebrowser.dia"
        repeat with diaWindow in windows
            set diaWindowID to (id of diaWindow) as text
            set diaWindowTitle to (name of diaWindow) as text
            repeat with diaTab in tabs of diaWindow
                set tabID to (id of diaTab) as text
                set tabTitle to (title of diaTab) as text
                set tabURL to (URL of diaTab) as text
                set tabFocused to (isFocused of diaTab) as text
                set end of outputLines to (my sanitize(diaWindowID)) & fieldDelimiter & (my sanitize(diaWindowTitle)) & fieldDelimiter & (my sanitize(tabID)) & fieldDelimiter & (my sanitize(tabTitle)) & fieldDelimiter & (my sanitize(tabURL)) & fieldDelimiter & (my sanitize(tabFocused))
            end repeat
        end repeat
    end tell
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set outputText to outputLines as text
    set AppleScript's text item delimiters to oldDelimiters
    return outputText
    """
}
