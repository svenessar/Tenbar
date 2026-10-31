import AppKit
import TenbarCore

/// Pin target in the app: the start menu, or the taskbar of one display.
enum PinTarget: Hashable {
    case start(display: String)
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
    /// Shared start tiles; also the template for displays without an own layout.
    @Published private(set) var startLayout: StartLayout
    @Published private(set) var startLayoutsByDisplay: [String: StartLayout] = [:]
    @Published private(set) var startLayoutPerDisplay: Bool
    @Published var statusMessage = ""
    /// Called with the app key and display when an app is opened from a display, so its new window can go there.
    var onOpen: ((String, CGDirectDisplayID) -> Void)?
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
        self.startLayoutPerDisplay = preferences.startLayoutPerDisplay
        if let layout = preferences.startLayout {
            self.startLayout = layout
        } else if let pins = preferences.pins(.start) {
            // One-time migration from the flat start pin list.
            let migrated = StartLayout(pins: pins)
            self.startLayout = migrated
            preferences.startLayout = migrated
        } else {
            self.startLayout = StartLayout()
        }
        self.combineMode = preferences.combineMode
        self.showLabels = preferences.showLabels
    }

    func startMenuSize(forDisplay key: String) -> StartMenuSize {
        preferences.startMenuSize(forDisplay: key) ?? .standard
    }

    func setStartMenuSize(_ size: StartMenuSize?, forDisplay key: String) {
        preferences.setStartMenuSize(size, forDisplay: key)
    }

    func startShowsAllApps(forDisplay key: String) -> Bool {
        preferences.startShowsAllApps(forDisplay: key)
    }

    func setStartShowsAllApps(_ shows: Bool, forDisplay key: String) {
        preferences.setStartShowsAllApps(shows, forDisplay: key)
    }

    func app(id: String) -> InstalledApp? {
        apps.first { $0.id == id }
    }

    /// Installed apps of a start group (pins of uninstalled apps are hidden).
    func apps(in group: StartGroup) -> [InstalledApp] {
        let byID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return group.apps.compactMap { byID[$0] }
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let records = await Task.detached(priority: .utility) { AppScanner.scan() }.value
            apps = records.map(InstalledApp.init(record:))
            if preferences.pins(.taskbar) == nil {
                let defaults = PinList.defaults(available: records.map(\.id), preferred: Self.preferredPins(.taskbar))
                taskbarPinTemplate = defaults
                preferences.setPins(defaults, .taskbar)
            }
            if preferences.startLayout == nil {
                let defaults = PinList.defaults(available: records.map(\.id), preferred: Self.preferredPins(.start))
                updateSharedStart { $0 = StartLayout(pins: defaults) }
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
        case .start(let display): PinList(startLayout(display: display).allApps)
        case .taskbar(let display): taskbarPins(display: display)
        }
    }

    func isPinned(_ appID: String, to target: PinTarget) -> Bool {
        pins(target).contains(appID)
    }

    func togglePin(_ appID: String, _ target: PinTarget) {
        switch target {
        case .start(let display):
            updateStart(display: display) { $0.contains(appID) ? $0.unpin(appID) : $0.pin(appID) }
        case .taskbar(let display):
            var updated = taskbarPins(display: display)
            updated.toggle(appID)
            setTaskbarPins(updated, display: display)
        }
    }

    private func setTaskbarPins(_ pins: PinList, display: String) {
        taskbarPinsByDisplay[display] = pins
        preferences.setTaskbarPins(pins, forDisplay: display)
    }

    /// Applies a drop on a display's taskbar. `target` nil means "after the last item".
    func dropOnTaskbar(_ source: String, before target: String?, display: String, visibleUnpinned: [String]) {
        guard !source.hasPrefix(StartLayout.groupPayloadPrefix) else { return }
        switch TaskbarDrop.apply(source: source, target: target, pins: taskbarPins(display: display),
                                 visibleUnpinned: visibleUnpinned, unpinnedOrder: unpinnedOrder) {
        case .none: break
        case .pins(let pins): setTaskbarPins(pins, display: display)
        case .unpinnedOrder(let order): unpinnedOrder = order
        }
    }

    // MARK: Start groups

    /// Handles a drop in the start tiles. `source` is an app ID or a group payload.
    /// `group` nil means "below all groups": apps get a new group, groups move to the end.
    func dropOnStart(_ source: String, display: String, group: String?, before target: String? = nil) {
        uiLog.notice("start drop source=\(source, privacy: .public) group=\(group ?? "nil", privacy: .public) before=\(target ?? "nil", privacy: .public)")
        if source.hasPrefix(StartLayout.groupPayloadPrefix) {
            let groupID = String(source.dropFirst(StartLayout.groupPayloadPrefix.count))
            updateStart(display: display) { $0.moveGroup(groupID, before: group) }
        } else if let group {
            updateStart(display: display) { $0.move(source, toGroup: group, before: target) }
        } else {
            updateStart(display: display) { $0.moveToNewGroup(source) }
        }
    }

    func renameStartGroup(_ groupID: String, to name: String, display: String) {
        updateStart(display: display) { $0.rename(groupID, to: name) }
    }

    func removeStartGroup(_ groupID: String, display: String) {
        updateStart(display: display) { $0.removeGroup(groupID) }
    }

    /// Switching to "same everywhere" adopts the tiles of `display` for all displays.
    /// Own layouts stay stored, so switching back restores them.
    func setStartLayoutPerDisplay(_ perDisplay: Bool, from display: String) {
        guard perDisplay != startLayoutPerDisplay else { return }
        if !perDisplay {
            let current = startLayout(display: display)
            updateSharedStart { $0 = current }
        }
        startLayoutPerDisplay = perDisplay
        preferences.startLayoutPerDisplay = perDisplay
    }

    /// The start tiles shown on a display (its own layout, or the shared one).
    func startLayout(display: String) -> StartLayout {
        guard startLayoutPerDisplay else { return startLayout }
        if let layout = startLayoutsByDisplay[display] { return layout }
        return preferences.startLayout(forDisplay: display) ?? startLayout
    }

    /// The first change on a display copies the shared layout, so other displays stay untouched.
    private func updateStart(display: String, _ change: (inout StartLayout) -> Void) {
        guard startLayoutPerDisplay else { return updateSharedStart(change) }
        var layout = startLayout(display: display)
        change(&layout)
        startLayoutsByDisplay[display] = layout
        preferences.setStartLayout(layout, forDisplay: display)
    }

    private func updateSharedStart(_ change: (inout StartLayout) -> Void) {
        var layout = startLayout
        change(&layout)
        guard layout != startLayout || preferences.startLayout == nil else { return }
        startLayout = layout
        preferences.startLayout = layout
    }

    func launch(_ app: InstalledApp, on display: CGDirectDisplayID? = nil) {
        if let display { onOpen?(app.id, display) }
        open(app.url, name: app.name)
    }

    /// Launches by catalog ID or bundle identifier. For running apps this
    /// activates them (or opens a new instance window, depending on the app).
    func launch(appKey: String, fallbackName: String, on display: CGDirectDisplayID? = nil) {
        if let app = app(id: appKey) {
            launch(app, on: display)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appKey) {
            if let display { onOpen?(appKey, display) }
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
