import AppKit
import TenbarCore

struct InstalledApp: Identifiable, Hashable {
    let record: AppRecord
    var id: String { record.id }
    var name: String { record.name }
    var url: URL { URL(fileURLWithPath: record.path) }
}

/// Installed apps for the start menu plus the user's pinned apps.
@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var taskbarPins: PinList
    @Published private(set) var startPins: PinList
    @Published var statusMessage = ""
    @Published var combineMode: CombineMode {
        didSet { preferences.combineMode = combineMode }
    }

    private let preferences: Preferences
    private var isScanning = false
    private var iconCache: [String: NSImage] = [:]

    static func preferredPins(_ location: PinLocation) -> [String] {
        switch location {
        case .taskbar:
            ["com.apple.finder", "com.apple.Safari", "com.apple.mail"]
        case .start:
            ["com.apple.mail", "com.apple.iCal", "com.apple.Notes", "com.apple.Photos",
             "com.apple.Music", "com.apple.AppStore", "com.apple.systempreferences"]
        }
    }

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        self.taskbarPins = preferences.pins(.taskbar) ?? PinList()
        self.startPins = preferences.pins(.start) ?? PinList()
        self.combineMode = preferences.combineMode
    }

    func app(id: String) -> InstalledApp? {
        apps.first { $0.id == id }
    }

    var startPinnedApps: [InstalledApp] {
        let byID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return startPins.ids.compactMap { byID[$0] }
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let records = await Task.detached(priority: .utility) { AppScanner.scan() }.value
            apps = records.map(InstalledApp.init(record:))
            for location in PinLocation.allCases where preferences.pins(location) == nil {
                let defaults = PinList.defaults(available: records.map(\.id), preferred: Self.preferredPins(location))
                setPins(defaults, location)
            }
            isScanning = false
        }
    }

    func icon(for app: InstalledApp) -> NSImage {
        if let cached = iconCache[app.id] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: app.record.path)
        iconCache[app.id] = icon
        return icon
    }

    func pins(_ location: PinLocation) -> PinList {
        switch location {
        case .taskbar: taskbarPins
        case .start: startPins
        }
    }

    func isPinned(_ appID: String, to location: PinLocation) -> Bool {
        pins(location).contains(appID)
    }

    func togglePin(_ appID: String, _ location: PinLocation) {
        var updated = pins(location)
        updated.toggle(appID)
        setPins(updated, location)
    }

    private func setPins(_ pins: PinList, _ location: PinLocation) {
        switch location {
        case .taskbar: taskbarPins = pins
        case .start: startPins = pins
        }
        preferences.setPins(pins, location)
    }

    func launch(_ app: InstalledApp) {
        open(app.url, name: app.name)
    }

    /// Launches by catalog ID or bundle identifier. For running apps this
    /// activates them (or opens a new instance window, depending on the app).
    func launch(appKey: String, fallbackName: String) {
        if let app = app(id: appKey) {
            launch(app)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appKey) {
            open(url, name: fallbackName)
        }
    }

    private func open(_ url: URL, name: String) {
        statusMessage = ""
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            let message = "„\(name)“ konnte nicht geöffnet werden: \(error.localizedDescription)"
            Task { @MainActor in self?.statusMessage = message }
        }
    }
}
