import AppKit
import TenbarCore

/// Pin target in the app: the start menu, or the taskbar of one display.
enum PinTarget: Hashable {
    case start
    case taskbar(display: String)
}

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
    /// Template for displays without an own list (the former global taskbar pins).
    @Published private(set) var taskbarPinTemplate: PinList
    @Published private(set) var taskbarPinsByDisplay: [String: PinList] = [:]
    @Published private(set) var startPins: PinList
    @Published var statusMessage = ""
    @Published var combineMode: CombineMode {
        didSet { preferences.combineMode = combineMode }
    }
    @Published var showLabels: Bool {
        didSet { preferences.showLabels = showLabels }
    }
    /// Order of running, unpinned apps (in memory only, like Windows 10).
    @Published private(set) var unpinnedOrder: [String] = []

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
        self.taskbarPinTemplate = preferences.pins(.taskbar) ?? PinList()
        self.startPins = preferences.pins(.start) ?? PinList()
        self.combineMode = preferences.combineMode
        self.showLabels = preferences.showLabels
    }

    func startMenuSize(forDisplay key: String) -> StartMenuSize {
        preferences.startMenuSize(forDisplay: key) ?? .standard
    }

    func setStartMenuSize(_ size: StartMenuSize?, forDisplay key: String) {
        preferences.setStartMenuSize(size, forDisplay: key)
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
                setDefaultPins(defaults, location)
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

    func taskbarPins(display: String) -> PinList {
        if let pins = taskbarPinsByDisplay[display] { return pins }
        return preferences.taskbarPins(forDisplay: display) ?? taskbarPinTemplate
    }

    func pins(_ target: PinTarget) -> PinList {
        switch target {
        case .start: startPins
        case .taskbar(let display): taskbarPins(display: display)
        }
    }

    func isPinned(_ appID: String, to target: PinTarget) -> Bool {
        pins(target).contains(appID)
    }

    func togglePin(_ appID: String, _ target: PinTarget) {
        var updated = pins(target)
        updated.toggle(appID)
        setPins(updated, target)
    }

    private func setPins(_ pins: PinList, _ target: PinTarget) {
        switch target {
        case .start:
            startPins = pins
            preferences.setPins(pins, .start)
        case .taskbar(let display):
            taskbarPinsByDisplay[display] = pins
            preferences.setTaskbarPins(pins, forDisplay: display)
        }
    }

    /// Initial pins after the first app scan (only for lists that were never set).
    private func setDefaultPins(_ pins: PinList, _ location: PinLocation) {
        switch location {
        case .taskbar: taskbarPinTemplate = pins
        case .start: startPins = pins
        }
        preferences.setPins(pins, location)
    }

    /// Applies a drop on a display's taskbar. `target` nil means "after the last item".
    func dropOnTaskbar(_ source: String, before target: String?, display: String, visibleUnpinned: [String]) {
        switch TaskbarDrop.apply(source: source, target: target, pins: taskbarPins(display: display),
                                 visibleUnpinned: visibleUnpinned, unpinnedOrder: unpinnedOrder) {
        case .none: break
        case .pins(let pins): setPins(pins, .taskbar(display: display))
        case .unpinnedOrder(let order): unpinnedOrder = order
        }
    }

    /// Pins `source` to start (if needed) and places it before `target`, or at the end.
    func dropOnStart(_ source: String, before target: String?) {
        guard source != target else { return }
        var pins = startPins
        if let target, pins.contains(target) {
            pins.pin(source)
            pins.move(source, before: target)
        } else {
            pins.unpin(source)
            pins.pin(source)
        }
        if pins != startPins { setPins(pins, .start) }
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
