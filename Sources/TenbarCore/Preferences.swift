import Foundation

/// Typed access to persisted settings.
public struct Preferences {
    private enum Key {
        static let pinnedAppIDs = "PinnedAppIDs"
        static let pinsInitialized = "PinsInitialized"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var pins: PinList? {
        get {
            guard defaults.bool(forKey: Key.pinsInitialized) else { return nil }
            return PinList(defaults.stringArray(forKey: Key.pinnedAppIDs) ?? [])
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.ids, forKey: Key.pinnedAppIDs)
                defaults.set(true, forKey: Key.pinsInitialized)
            } else {
                defaults.removeObject(forKey: Key.pinnedAppIDs)
                defaults.removeObject(forKey: Key.pinsInitialized)
            }
        }
    }
}
