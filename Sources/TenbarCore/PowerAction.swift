public enum PowerAction: String, CaseIterable, Identifiable, Sendable {
    case lock, sleep, logOut, restart, shutDown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lock: "Sperren"
        case .sleep: "Energie sparen"
        case .logOut: "Abmelden"
        case .restart: "Neu starten"
        case .shutDown: "Herunterfahren"
        }
    }

    public var symbol: String {
        switch self {
        case .lock: "lock.fill"
        case .sleep: "moon.fill"
        case .logOut: "rectangle.portrait.and.arrow.right"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        }
    }

    public var needsConfirmation: Bool {
        switch self {
        case .logOut, .restart, .shutDown: true
        case .lock, .sleep: false
        }
    }

    /// Session-ending actions: macOS must not reopen the apps afterwards.
    public var endsSession: Bool {
        switch self {
        case .logOut, .restart, .shutDown: true
        case .lock, .sleep: false
        }
    }

    public var appleScript: String {
        switch self {
        case .lock: #"tell application "System Events" to keystroke "q" using {control down, command down}"#
        case .sleep: #"tell application "System Events" to sleep"#
        case .logOut: #"tell application "System Events" to log out"#
        case .restart: #"tell application "System Events" to restart"#
        case .shutDown: #"tell application "System Events" to shut down"#
        }
    }
}
