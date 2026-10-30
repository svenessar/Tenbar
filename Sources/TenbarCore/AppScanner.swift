import Foundation

public struct AppRecord: Identifiable, Hashable, Sendable {
    /// Bundle identifier, or the path when the bundle has none.
    public let id: String
    public let name: String
    public let path: String

    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

public enum AppScanner {
    public static var defaultRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            // Safari and other cryptex apps; their /Applications symlinks are flagged hidden.
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    public static var extraApps: [URL] {
        [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
    }

    /// Finds `.app` bundles below `roots` (not inside other bundles), deduplicated by ID
    /// and sorted by name.
    public static func scan(roots: [URL] = defaultRoots, extras: [URL] = extraApps) -> [AppRecord] {
        let fileManager = FileManager.default
        var seen = Set<String>()
        var records: [AppRecord] = []

        func add(_ url: URL) {
            let id = Bundle(url: url)?.bundleIdentifier ?? url.path
            guard seen.insert(id).inserted else { return }
            let name = (fileManager.displayName(atPath: url.path) as NSString).deletingPathExtension
            records.append(AppRecord(id: id, name: name, path: url.path))
        }

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                add(url)
            }
        }
        for url in extras where fileManager.fileExists(atPath: url.path) {
            add(url)
        }
        return records.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
