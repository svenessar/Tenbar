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
}
