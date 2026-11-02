import AppKit
import SwiftUI
import TenbarCore

/// Borderless panel that never activates Tenbar when clicked, so the
/// previously active app keeps focus (needed for click-to-minimize).
final class TaskbarPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        // No .fullScreenAuxiliary: the bar stays out of full-screen Spaces.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
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
    private var workspaceTokens: [NSObjectProtocol] = []
    private var fullScreenTimer: Timer?
    private var fullScreenDisplays: Set<CGDirectDisplayID> = []

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
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFullScreen() }
            })
        }
        // Windows can enter full screen without any notification (e.g. remote desktop clients).
        fullScreenTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullScreen() }
        }
        syncPanels()
    }

    /// Hides the bar on screens where the topmost window covers the whole screen.
    private func updateFullScreen() {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let windows: [CGRect] = info.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return bounds
        }
        // CGWindow bounds use top-left coordinates like Accessibility; the conversion is its own inverse.
        let screenRects = screens.map { ScreenGeometry.cocoaRect(fromAccessibility: $0.frame, primaryScreenHeight: primaryHeight) }
        let covered = Set(ScreenGeometry.fullScreenIndices(screens: screenRects, windows: windows).map { screens[$0].displayID })
        guard covered != fullScreenDisplays else { return }
        fullScreenDisplays = covered
        applyVisibility()
    }

    private func applyVisibility() {
        for (id, panel) in panels {
            if fullScreenDisplays.contains(id) {
                if panel.isVisible {
                    if startMenu.openDisplayID == id { startMenu.close() }
                    panel.orderOut(nil)
                }
            } else if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
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
        updateFullScreen()
        applyVisibility()
    }
}
