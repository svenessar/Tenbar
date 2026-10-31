import Foundation

/// Where an app is pinned. Like Windows 10, taskbar and start menu keep separate lists.
public enum PinLocation: String, CaseIterable, Sendable {
    case taskbar, start
}

/// Typed access to persisted settings.
public struct Preferences {
    private enum Key {
        static let combineMode = "CombineMode"
        static let showLabels = "ShowLabels"
        static let startMenuSizes = "StartMenuSizes"
        static let startAllAppsHiddenDisplays = "StartAllAppsHiddenDisplays"
        static let taskbarPinsByDisplay = "TaskbarPinsByDisplay"
        static let startLayout = "StartLayout"
        static let startLayoutsByDisplay = "StartLayoutsByDisplay"
        static let startLayoutPerDisplay = "StartLayoutPerDisplay"

        static func pinnedAppIDs(_ location: PinLocation) -> String {
            switch location {
            case .taskbar: "PinnedAppIDs"
            case .start: "StartPinnedAppIDs"
            }
        }

        static func pinsInitialized(_ location: PinLocation) -> String {
            switch location {
            case .taskbar: "PinsInitialized"
            case .start: "StartPinsInitialized"
            }
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// nil means the list was never initialized (distinct from an empty list the user cleared).
    public func pins(_ location: PinLocation) -> PinList? {
        guard defaults.bool(forKey: Key.pinsInitialized(location)) else { return nil }
        return PinList(defaults.stringArray(forKey: Key.pinnedAppIDs(location)) ?? [])
    }

    public func setPins(_ pins: PinList?, _ location: PinLocation) {
        if let pins {
            defaults.set(pins.ids, forKey: Key.pinnedAppIDs(location))
            defaults.set(true, forKey: Key.pinsInitialized(location))
        } else {
            defaults.removeObject(forKey: Key.pinnedAppIDs(location))
            defaults.removeObject(forKey: Key.pinsInitialized(location))
        }
    }

    public var combineMode: CombineMode {
        get { defaults.string(forKey: Key.combineMode).flatMap(CombineMode.init(rawValue:)) ?? .always }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.combineMode) }
    }

    /// Show names next to icons of running apps. Defaults to true.
    public var showLabels: Bool {
        get { defaults.object(forKey: Key.showLabels) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.showLabels) }
    }

    /// Grouped start tiles. nil means never saved (migrate from `pins(.start)`).
    public var startLayout: StartLayout? {
        get { defaults.data(forKey: Key.startLayout).flatMap { try? JSONDecoder().decode(StartLayout.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.startLayout) }
    }

    /// Each display has its own start tiles (true, default) or all share `startLayout`.
    public var startLayoutPerDisplay: Bool {
        get { defaults.object(forKey: Key.startLayoutPerDisplay) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.startLayoutPerDisplay) }
    }

    /// Start tiles of one display. nil means the display has no own layout yet and uses `startLayout`.
    public func startLayout(forDisplay key: String) -> StartLayout? {
        guard let data = (defaults.dictionary(forKey: Key.startLayoutsByDisplay) as? [String: Data])?[key] else { return nil }
        return try? JSONDecoder().decode(StartLayout.self, from: data)
    }

    public func setStartLayout(_ layout: StartLayout?, forDisplay key: String) {
        var all = defaults.dictionary(forKey: Key.startLayoutsByDisplay) as? [String: Data] ?? [:]
        all[key] = layout.flatMap { try? JSONEncoder().encode($0) }
        defaults.set(all, forKey: Key.startLayoutsByDisplay)
    }

    /// Taskbar pins of one display. nil means the display has no own list yet and uses `pins(.taskbar)`.
    public func taskbarPins(forDisplay key: String) -> PinList? {
        (defaults.dictionary(forKey: Key.taskbarPinsByDisplay) as? [String: [String]])?[key].map(PinList.init)
    }

    public func setTaskbarPins(_ pins: PinList?, forDisplay key: String) {
        var all = defaults.dictionary(forKey: Key.taskbarPinsByDisplay) as? [String: [String]] ?? [:]
        all[key] = pins?.ids
        defaults.set(all, forKey: Key.taskbarPinsByDisplay)
    }

    /// Start menu size per display (keyed by a stable display identifier). nil means default size.
    public func startMenuSize(forDisplay key: String) -> StartMenuSize? {
        guard let data = (defaults.dictionary(forKey: Key.startMenuSizes) as? [String: Data])?[key] else { return nil }
        return try? JSONDecoder().decode(StartMenuSize.self, from: data)
    }

    public func setStartMenuSize(_ size: StartMenuSize?, forDisplay key: String) {
        var all = defaults.dictionary(forKey: Key.startMenuSizes) as? [String: Data] ?? [:]
        all[key] = size.flatMap { try? JSONEncoder().encode($0) }
        defaults.set(all, forKey: Key.startMenuSizes)
    }

    /// Whether the start menu on one display shows the "All apps" column. Defaults to true.
    public func startShowsAllApps(forDisplay key: String) -> Bool {
        !(defaults.stringArray(forKey: Key.startAllAppsHiddenDisplays) ?? []).contains(key)
    }

    public func setStartShowsAllApps(_ shows: Bool, forDisplay key: String) {
        var hidden = Set(defaults.stringArray(forKey: Key.startAllAppsHiddenDisplays) ?? [])
        if shows { hidden.remove(key) } else { hidden.insert(key) }
        defaults.set(hidden.sorted(), forKey: Key.startAllAppsHiddenDisplays)
    }
}
