import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tracker = WindowTracker()
    private let catalog = AppCatalog()
    private let menus = AppMenus()
    private lazy var taskbars = TaskbarController(tracker: tracker, catalog: catalog, menus: menus)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        catalog.onOpen = { [tracker] appKey, display in tracker.expectNewWindow(appKey: appKey, on: display) }
        catalog.rescan()
        tracker.start()
        taskbars.start()
    }
}
