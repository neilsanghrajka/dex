import Foundation

struct MacOSSpaceSlot: Equatable {
    let id: String
    let index: Int
    let isCurrent: Bool
}

enum MacOSSpaceReader {
    static func currentMainDisplaySpaceID(defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.spaces")) -> String? {
        guard let configuration = defaults?.dictionary(forKey: "SpacesDisplayConfiguration") else {
            return nil
        }
        return currentMainDisplaySpaceID(from: configuration)
    }

    static func currentMainDisplaySpaceID(from configuration: [String: Any]) -> String? {
        mainDisplaySlots(from: configuration).first(where: \.isCurrent)?.id
    }

    static func mainDisplaySlots(defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.spaces")) -> [MacOSSpaceSlot] {
        guard let configuration = defaults?.dictionary(forKey: "SpacesDisplayConfiguration") else {
            return [MacOSSpaceSlot(id: "space-1", index: 0, isCurrent: true)]
        }
        return mainDisplaySlots(from: configuration)
    }

    static func mainDisplaySlots(from configuration: [String: Any]) -> [MacOSSpaceSlot] {
        guard let managementData = configuration["Management Data"] as? [String: Any],
              let monitors = managementData["Monitors"] as? [[String: Any]],
              let mainMonitor = monitors.first(where: { ($0["Display Identifier"] as? String) == "Main" }),
              let spaces = mainMonitor["Spaces"] as? [[String: Any]],
              !spaces.isEmpty else {
            return [MacOSSpaceSlot(id: "space-1", index: 0, isCurrent: true)]
        }

        let currentID = spaceID(from: mainMonitor["Current Space"] as? [String: Any])
        return spaces.enumerated().map { index, space in
            let id = spaceID(from: space) ?? "space-\(index + 1)"
            return MacOSSpaceSlot(
                id: id,
                index: index,
                isCurrent: currentID == nil ? index == 0 : id == currentID
            )
        }
    }

    private static func spaceID(from raw: [String: Any]?) -> String? {
        guard let raw else { return nil }
        if let uuid = raw["uuid"] as? String, !uuid.isEmpty {
            return uuid
        }
        if let id64 = raw["id64"] {
            return "\(id64)"
        }
        if let managedID = raw["ManagedSpaceID"] {
            return "\(managedID)"
        }
        return nil
    }
}
