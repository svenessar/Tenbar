import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tracker = WindowTracker()
    private let catalog = AppCatalog()
    private lazy var taskbars = TaskbarController(tracker: tracker, catalog: catalog)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        catalog.rescan()
        tracker.start()
        taskbars.start()
    }
}
