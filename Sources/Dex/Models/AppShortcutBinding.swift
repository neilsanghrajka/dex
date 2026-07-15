import Foundation

/// A user-editable binding between an installed application and a single board key.
///
/// This is the single source of truth for the configurable app-launch shortcuts.
/// The live list lives on `AppModel.appShortcutBindings`; the board and the palette
/// shortcut-help both read from it so there is exactly one key map in the app.
struct AppShortcutBinding: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var bundleIdentifiers: [String]
    var appNames: [String]
    /// A single lowercase letter or digit. Never a reserved grammar key.
    var key: String
    var preferNewWindow: Bool
    var newWindowMenuItemTitles: [String]

    init(
        id: UUID = UUID(),
        displayName: String,
        bundleIdentifiers: [String],
        appNames: [String],
        key: String,
        preferNewWindow: Bool,
        newWindowMenuItemTitles: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifiers = bundleIdentifiers
        self.appNames = appNames
        self.key = BoardShortcutValidation.clean(key)
        self.preferNewWindow = preferNewWindow
        self.newWindowMenuItemTitles = newWindowMenuItemTitles
    }

    /// Launch descriptor shared with the existing open/launch machinery.
    var spec: BoardAppShortcutSpec {
        BoardAppShortcutSpec(
            label: displayName,
            bundleIdentifiers: bundleIdentifiers,
            appNames: appNames,
            forceNew: preferNewWindow,
            newWindowMenuItemTitles: newWindowMenuItemTitles
        )
    }

    /// Uppercased single-character label for badges/legends.
    var keyLabel: String { key.uppercased() }

    var primaryBundleIdentifier: String? {
        bundleIdentifiers.first { !$0.isEmpty }
    }
}

extension AppShortcutBinding {
    /// The default starter set: the five apps Dex has always shipped.
    static var defaults: [AppShortcutBinding] {
        BoardAppShortcut.allCases.map { $0.defaultBinding }
    }
}

/// Validation for assigning a key to an `AppShortcutBinding`.
///
/// Fixed grammar keys are never configurable. The recorder only ever offers a
/// letter/digit character to this validator; reserved literals (`F`, `M`, `Q`, `W`, `/`) are
/// rejected here with a reason the UI can surface.
enum AppShortcutKeyValidation {
    /// Alphanumeric keys that stay reserved for the board grammar.
    static let reservedKeys: Set<String> = ["f", "m", "q", "w"]

    enum Result: Equatable {
        case valid(key: String)
        /// The keypress produced nothing usable (e.g. a modifier-only press).
        case notAKey
        /// A reserved key was pressed. Associated value is the human label.
        case reserved(String)
        /// The key already belongs to another binding.
        case conflict(bindingID: UUID, appName: String, key: String)
    }

    /// Validate a raw pressed character against the current binding list.
    /// - Parameters:
    ///   - pressedCharacter: `charactersIgnoringModifiers` (or a raw string) from the keypress.
    ///   - bindingID: the binding being edited (excluded from conflict checks); `nil` when adding.
    ///   - bindings: the current live binding list.
    static func validate(
        pressedCharacter raw: String,
        for bindingID: UUID?,
        in bindings: [AppShortcutBinding]
    ) -> Result {
        let lowered = raw.lowercased()
        // "/" opens the palette and is stripped by `clean`, so catch it explicitly.
        if lowered == "/" {
            return .reserved("/")
        }

        let cleaned = BoardShortcutValidation.clean(lowered)
        guard cleaned.count == 1 else {
            return .notAKey
        }
        if reservedKeys.contains(cleaned) {
            return .reserved(cleaned.uppercased())
        }
        if let conflict = bindings.first(where: { $0.id != bindingID && $0.key == cleaned }) {
            return .conflict(bindingID: conflict.id, appName: conflict.displayName, key: cleaned)
        }
        return .valid(key: cleaned)
    }
}
