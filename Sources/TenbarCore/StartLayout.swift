import Foundation

/// A named group of pinned start tiles (the name may be empty, like Windows 10).
public struct StartGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var apps: [String]

    public init(id: String = UUID().uuidString, name: String = "", apps: [String] = []) {
        self.id = id
        self.name = name
        self.apps = apps
    }
}

/// Pinned start tiles organized in groups. Each app appears at most once; empty groups are removed.
public struct StartLayout: Codable, Equatable, Sendable {
    /// Drag payload prefix that distinguishes a group from an app ID.
    public static let groupPayloadPrefix = "group:"

    public private(set) var groups: [StartGroup]

    public init(groups: [StartGroup] = []) {
        self.groups = []
        for group in groups {
            let apps = group.apps.filter { !contains($0) }
            if !apps.isEmpty { self.groups.append(StartGroup(id: group.id, name: group.name, apps: PinList(apps).ids)) }
        }
    }

    /// Migration from the flat start pin list.
    public init(pins: PinList, groupID: String = UUID().uuidString) {
        self.init(groups: [StartGroup(id: groupID, apps: pins.ids)])
    }

    public var allApps: [String] { groups.flatMap(\.apps) }

    public func contains(_ app: String) -> Bool {
        groups.contains { $0.apps.contains(app) }
    }

    public func groupID(of app: String) -> String? {
        groups.first { $0.apps.contains(app) }?.id
    }

    /// Pins at the end of the last group (or a new group if there is none). No-op if already pinned.
    public mutating func pin(_ app: String, newGroupID: String = UUID().uuidString) {
        guard !contains(app) else { return }
        if groups.isEmpty {
            groups.append(StartGroup(id: newGroupID, apps: [app]))
        } else {
            groups[groups.count - 1].apps.append(app)
        }
    }

    public mutating func unpin(_ app: String) {
        for index in groups.indices { groups[index].apps.removeAll { $0 == app } }
        removeEmptyGroups()
    }

    /// Moves (or pins) `app` into a group, before `target` or at the end of that group.
    public mutating func move(_ app: String, toGroup groupID: String, before target: String? = nil) {
        guard app != target, groups.contains(where: { $0.id == groupID }) else { return }
        for index in groups.indices { groups[index].apps.removeAll { $0 == app } }
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if let target, let position = groups[index].apps.firstIndex(of: target) {
            groups[index].apps.insert(app, at: position)
        } else {
            groups[index].apps.append(app)
        }
        removeEmptyGroups()
    }

    /// Moves (or pins) `app` into a new group at the end.
    public mutating func moveToNewGroup(_ app: String, groupID: String = UUID().uuidString) {
        for index in groups.indices { groups[index].apps.removeAll { $0 == app } }
        removeEmptyGroups()
        groups.append(StartGroup(id: groupID, apps: [app]))
    }

    public mutating func rename(_ groupID: String, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Moves a whole group before another group, or to the end.
    public mutating func moveGroup(_ groupID: String, before target: String?) {
        guard groupID != target, let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let group = groups.remove(at: index)
        if let target, let position = groups.firstIndex(where: { $0.id == target }) {
            groups.insert(group, at: position)
        } else {
            groups.append(group)
        }
    }

    /// Unpins all apps of a group.
    public mutating func removeGroup(_ groupID: String) {
        groups.removeAll { $0.id == groupID }
    }

    private mutating func removeEmptyGroups() {
        groups.removeAll { $0.apps.isEmpty }
    }
}
