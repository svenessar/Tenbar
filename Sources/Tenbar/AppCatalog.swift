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
    @Published private(set) var pins: PinList
    @Published var statusMessage = ""
    @Published var combineMode: CombineMode {
        didSet { preferences.combineMode = combineMode }
    }

    private let preferences: Preferences
    private var isScanning = false
    private var iconCache: [String: NSImage] = [:]

    static let preferredPins = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.iCal", "com.apple.Notes"]

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        self.pins = preferences.pins ?? PinList()
        self.combineMode = preferences.combineMode
    }

    func app(id: String) -> InstalledApp? {
        apps.first { $0.id == id }
    }

    var pinnedApps: [InstalledApp] {
        let byID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pins.ids.compactMap { byID[$0] }
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let records = await Task.detached(priority: .utility) { AppScanner.scan() }.value
            apps = records.map(InstalledApp.init(record:))
            if preferences.pins == nil {
                pins = PinList.defaults(available: records.map(\.id), preferred: Self.preferredPins)
                preferences.pins = pins
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

    func isPinned(_ app: InstalledApp) -> Bool { pins.contains(app.id) }

    func togglePin(_ app: InstalledApp) { updatePins { $0.toggle(app.id) } }

    func pin(appID: String) { updatePins { $0.pin(appID) } }

    func unpin(appID: String) { updatePins { $0.unpin(appID) } }

    private func updatePins(_ change: (inout PinList) -> Void) {
        var updated = pins
        change(&updated)
        pins = updated
        preferences.pins = updated
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
