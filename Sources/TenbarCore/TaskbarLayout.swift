public enum CombineMode: String, CaseIterable, Identifiable, Sendable {
    /// One icon per app; pinned apps and their windows share one button.
    case always
    /// One labeled button per window; pinned apps without windows stay as icons.
    case never

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .always: "Immer gruppieren"
        case .never: "Nie gruppieren"
        }
    }
}

public struct TaskbarItem<WindowID: Hashable & Sendable>: Identifiable, Equatable, Sendable {
    public let appKey: String
    public let isPinned: Bool
    /// Windows represented by this item, in taskbar order. Empty for a pinned app that isn't running.
    public let windowIDs: [WindowID]
    /// True if the item stands for the whole app (icon button), false for a single window button.
    public let representsApp: Bool

    public var id: String {
        representsApp ? "app:\(appKey)" : "window:\(windowIDs.first.map { "\($0)" } ?? appKey)"
    }
}

public enum TaskbarLayout {
    /// Builds the taskbar items: pinned apps first (in pin order), then unpinned apps
    /// in `unpinnedOrder`, then any remaining apps in the order their first window appeared.
    public static func items<WindowID>(
        pinnedAppKeys: [String],
        windows: [(id: WindowID, appKey: String)],
        mode: CombineMode,
        unpinnedOrder: [String] = []
    ) -> [TaskbarItem<WindowID>] {
        var windowsByApp: [String: [WindowID]] = [:]
        var appOrder: [String] = []
        for window in windows {
            if windowsByApp[window.appKey] == nil { appOrder.append(window.appKey) }
            windowsByApp[window.appKey, default: []].append(window.id)
        }

        let pinned = PinList(pinnedAppKeys).ids
        let pinnedSet = Set(pinned)
        let unpinned = appOrder.filter { !pinnedSet.contains($0) }
        let rank = Dictionary(unpinnedOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sortedUnpinned = unpinned.enumerated().sorted { lhs, rhs in
            let left = rank[lhs.element] ?? Int.max, right = rank[rhs.element] ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
        let orderedApps = pinned + sortedUnpinned

        return orderedApps.flatMap { appKey -> [TaskbarItem<WindowID>] in
            let ids = windowsByApp[appKey] ?? []
            let isPinned = pinnedSet.contains(appKey)
            if mode == .always || ids.isEmpty {
                return [TaskbarItem(appKey: appKey, isPinned: isPinned, windowIDs: ids, representsApp: true)]
            }
            return ids.map { TaskbarItem(appKey: appKey, isPinned: isPinned, windowIDs: [$0], representsApp: false) }
        }
    }
}
