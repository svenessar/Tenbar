import AppKit
import SwiftUI
import TenbarCore

/// Borderless panel for the start menu. It can become key (for Escape) without activating Tenbar,
/// so the previously active app keeps focus.
final class StartMenuPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
}

/// Shows one start menu at a time, sitting directly on top of the taskbar of the chosen display.
/// The bottom-left corner stays fixed, resizing grows the menu up and to the right.
@MainActor
final class StartMenuController: ObservableObject {
    @Published private(set) var openDisplayID: CGDirectDisplayID?
    @Published private(set) var size = StartMenuSize.standard
    /// "All apps" column visible on the open display (stored per display).
    @Published private(set) var showsAllApps = true
    @Published var searchText = ""
    /// Incremented on every open, so the view can focus the search field.
    @Published private(set) var openCount = 0

    private let catalog: AppCatalog
    private let panel = StartMenuPanel()
    private var hasContent = false
    private var monitors: [Any] = []
    private var spaceObserver: NSObjectProtocol?
    private var lastAutoClose: (display: CGDirectDisplayID, time: Date)?

    init(catalog: AppCatalog) {
        self.catalog = catalog
    }

    var displayKey: String? { openDisplayID.map(stableDisplayKey) }

    func toggle(on displayID: CGDirectDisplayID) {
        uiLog.notice("start toggle display=\(displayID) open=\(String(describing: self.openDisplayID), privacy: .public)")
        if openDisplayID == displayID {
            close()
            return
        }
        // The click on the start button already closed the menu via the mouse monitor; don't reopen it.
        if let last = lastAutoClose, last.display == displayID, Date().timeIntervalSince(last.time) < 0.3 {
            lastAutoClose = nil
            return
        }
        open(on: displayID)
    }

    func open(on displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.with(displayID: displayID) else { return }
        close()
        openDisplayID = displayID
        showsAllApps = catalog.startShowsAllApps(forDisplay: stableDisplayKey(displayID))
        size = clamp(catalog.startMenuSize(forDisplay: stableDisplayKey(displayID)), on: screen)
        catalog.rescan()

        // NSPanel always has a default (empty) content view, so track the hosting view explicitly.
        if !hasContent {
            let host = NSHostingView(rootView: StartMenuView().environmentObject(catalog).environmentObject(self))
            host.sizingOptions = []
            panel.contentView = host
            hasContent = true
        }
        searchText = ""
        applyFrame()
        panel.makeKeyAndOrderFront(nil)
        openCount += 1
        uiLog.notice("start open frame=\(String(describing: self.panel.frame), privacy: .public) content=\(String(describing: type(of: self.panel.contentView!)), privacy: .public) visible=\(self.panel.isVisible)")
        installMonitors()
    }

    func close(auto: Bool = false) {
        guard let displayID = openDisplayID else { return }
        uiLog.notice("start close auto=\(auto)")
        if auto { lastAutoClose = (displayID, Date()) }
        removeMonitors()
        TooltipController.shared.hide()
        panel.orderOut(nil)
        openDisplayID = nil
    }

    // MARK: Size

    func resize(to newSize: StartMenuSize) {
        guard let screen = openScreen else { return }
        size = clamp(newSize, on: screen)
        applyFrame()
    }

    func resetSize(forDisplay displayID: CGDirectDisplayID) {
        catalog.setStartMenuSize(nil, forDisplay: stableDisplayKey(displayID))
        if openDisplayID == displayID { resize(to: .standard) }
    }

    func setShowsAllApps(_ shows: Bool, forDisplay displayID: CGDirectDisplayID) {
        catalog.setStartShowsAllApps(shows, forDisplay: stableDisplayKey(displayID))
        guard openDisplayID == displayID, let screen = openScreen else { return }
        showsAllApps = shows
        if !shows { searchText = "" }
        size = clamp(size, on: screen)
        applyFrame()
    }

    func toggleAllApps() {
        guard let displayID = openDisplayID else { return }
        setShowsAllApps(!showsAllApps, forDisplay: displayID)
    }

    func saveSize() {
        guard let key = displayKey else { return }
        catalog.setStartMenuSize(size, forDisplay: key)
    }

    /// Room above the taskbar on the open display.
    func limits(on screen: NSScreen) -> (width: Double, height: Double) {
        (screen.frame.width - 8, screen.visibleFrame.maxY - (screen.frame.minY + Theme.barHeight) - 8)
    }

    private var openScreen: NSScreen? { openDisplayID.flatMap(NSScreen.with(displayID:)) }

    private func clamp(_ size: StartMenuSize, on screen: NSScreen) -> StartMenuSize {
        let limits = limits(on: screen)
        return size.clamped(maxTotalWidth: limits.width, maxHeight: limits.height, showsAllApps: showsAllApps)
    }

    private func applyFrame() {
        guard let screen = openScreen else { return }
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY + Theme.barHeight,
                           width: size.width(showsAllApps: showsAllApps), height: size.height)
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: Closing

    private func installMonitors() {
        // Clicks in other apps.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close(auto: true) }
        }) { monitors.append(global) }
        // Clicks in Tenbar's own windows (taskbar) outside the menu, plus Escape.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            let isEscape = event.type == .keyDown && event.keyCode == 53
            let inTaskbar = event.type != .keyDown && event.window is TaskbarPanel
            guard isEscape || inTaskbar else { return event }
            MainActor.assumeIsolated {
                guard let self else { return }
                // Escape first clears the search, a second Escape closes the menu.
                if isEscape, !self.searchText.isEmpty { self.searchText = "" } else { self.close(auto: inTaskbar) }
            }
            return isEscape ? nil : event
        }) { monitors.append(local) }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
    }
}
