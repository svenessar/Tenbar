import AppKit
import SwiftUI

/// Borderless panel that never activates Tenbar when clicked, so the
/// previously active app keeps focus (needed for click-to-minimize).
final class TaskbarPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Keeps one taskbar panel per connected screen.
@MainActor
final class TaskbarController {
    private let tracker: WindowTracker
    private let catalog: AppCatalog
    private let menus: AppMenus
    private let startMenu: StartMenuController
    private var panels: [CGDirectDisplayID: TaskbarPanel] = [:]
    private var token: NSObjectProtocol?

    init(tracker: WindowTracker, catalog: AppCatalog, menus: AppMenus) {
        self.tracker = tracker
        self.catalog = catalog
        self.menus = menus
        self.startMenu = StartMenuController(catalog: catalog)
    }

    func start() {
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startMenu.close()
                self?.syncPanels()
                self?.tracker.scheduleRefresh()
            }
        }
        syncPanels()
    }

    private func syncPanels() {
        let screens = NSScreen.screens
        let primaryID = screens.first?.displayID
        let liveIDs = Set(screens.map(\.displayID))
        for id in panels.keys where !liveIDs.contains(id) {
            panels.removeValue(forKey: id)?.close()
        }
        for screen in screens {
            let id = screen.displayID
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: Theme.barHeight)
            if let panel = panels[id] {
                panel.setFrame(frame, display: true)
                continue
            }
            let panel = TaskbarPanel(frame: frame)
            let root = TaskbarView(displayID: id, isPrimary: id == primaryID)
                .environmentObject(tracker)
                .environmentObject(catalog)
                .environmentObject(startMenu)
                .environmentObject(menus)
            panel.contentView = FirstMouseHostingView(rootView: root)
            panel.orderFrontRegardless()
            panels[id] = panel
        }
    }
}
