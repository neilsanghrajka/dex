import Foundation

final class ApplicationCatalogService: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let cacheLock = NSLock()
    private var cachedApplications: [InstalledApplication]?

    func installedApplications() -> [InstalledApplication] {
        if let cached = cachedResult() {
            return cached
        }

        let apps = scanInstalledApplications()
        cacheLock.lock()
        cachedApplications = apps
        cacheLock.unlock()
        return apps
    }

    func prewarm() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.installedApplications()
        }
    }

    private func cachedResult() -> [InstalledApplication]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedApplications
    }

    private func scanInstalledApplications() -> [InstalledApplication] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var seen = Set<String>()
        var apps: [InstalledApplication] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            apps.append(contentsOf: applications(in: root, seen: &seen))
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func applications(in root: URL, seen: inout Set<String>) -> [InstalledApplication] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var apps: [InstalledApplication] = []
        for case let url as URL in enumerator where url.pathExtension == "app" {
            guard seen.insert(url.path).inserted else { continue }
            let bundle = Bundle(url: url)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            apps.append(
                InstalledApplication(
                    id: url.path,
                    name: name,
                    bundleIdentifier: bundle?.bundleIdentifier,
                    url: url
                )
            )
        }
        return apps
    }
}
