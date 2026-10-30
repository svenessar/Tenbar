import AppKit
@preconcurrency import ApplicationServices
import TenbarCore

struct TaskWindow: Identifiable, Equatable {
    let id: UUID
    let pid: pid_t
    let title: String
    let appName: String
    let bundleID: String?
    let isMinimized: Bool
    /// Display that shows most of the window; nil if unknown.
    let displayID: CGDirectDisplayID?
    let element: AXUIElement

    /// Groups windows by app; matches pinned IDs, which are bundle identifiers.
    var appKey: String { bundleID ?? "pid-\(pid)" }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.isMinimized == rhs.isMinimized
            && lhs.displayID == rhs.displayID && lhs.appName == rhs.appName
    }
}

/// Tracks the windows of all regular apps. Updates are driven by AXObserver and
/// NSWorkspace notifications; a slow safety timer catches anything missed.
@MainActor
final class WindowTracker: ObservableObject {
    @Published private(set) var windows: [TaskWindow] = []
    @Published private(set) var focusedWindowID: UUID?
    @Published private(set) var activePID: pid_t?
    @Published private(set) var hasPermission = AXIsProcessTrusted()

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var windowIDs: [AXElementKey: UUID] = [:]
    private var order = StableOrder<UUID>()
    private var appObservers: [pid_t: AXObserver] = [:]
    private var observedWindows: Set<AXElementKey> = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var safetyTimer: Timer?
    private var refreshPending = false
    private var iconCache: [pid_t: NSImage] = [:]
    private var placements = PlacementRequests<UUID, CGDirectDisplayID>()
    private var placementTimer: Timer?
    private var frontRequests: [String: (display: CGDirectDisplayID, deadline: Date)] = [:]

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                MainActor.assumeIsolated {
                    self?.handleWorkspace(name, pid: pid)
                }
            }
            workspaceTokens.append(token)
        }
        activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func icon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        iconCache[pid] = icon
        return icon
    }

    // MARK: Updates

    private func handleWorkspace(_ name: Notification.Name, pid: pid_t?) {
        if name == NSWorkspace.didActivateApplicationNotification, let pid, pid != ownPID {
            activePID = pid
        }
        if name == NSWorkspace.didTerminateApplicationNotification, let pid {
            removeObserver(for: pid)
            iconCache[pid] = nil
        }
        scheduleRefresh()
    }

    /// Coalesces bursts of notifications (e.g. while dragging a window) into one refresh.
    func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self else { return }
            self.refreshPending = false
            self.refresh()
        }
    }

    func refresh() {
        hasPermission = AXIsProcessTrusted()
        guard hasPermission else {
            for pid in Array(appObservers.keys) { removeObserver(for: pid) }
            windows = []
            focusedWindowID = nil
            return
        }

        let screens = NSScreen.screens
        let screenFrames = screens.map(\.frame)
        let primaryHeight = screens.first?.frame.height ?? 0
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID
        }

        let livePIDs = Set(apps.map(\.processIdentifier))
        for pid in Array(appObservers.keys) where !livePIDs.contains(pid) { removeObserver(for: pid) }

        var found: [UUID: TaskWindow] = [:]
        var discovered: [UUID] = []
        var seenKeys = Set<AXElementKey>()
        var focused: UUID?

        for app in apps {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            let observer = observer(for: pid, appElement: appElement)
            let focusedElement = pid == activePID ? AX.element(appElement, kAXFocusedWindowAttribute) : nil

            for element in AX.elements(appElement, kAXWindowsAttribute) where AX.isTaskWindow(element) {
                let key = AXElementKey(element: element)
                guard seenKeys.insert(key).inserted else { continue }
                let id = windowIDs[key] ?? UUID()
                windowIDs[key] = id
                if let observer { observeWindow(element, key: key, observer: observer) }

                let displayID = AX.frame(element).flatMap { axRect -> CGDirectDisplayID? in
                    let rect = ScreenGeometry.cocoaRect(fromAccessibility: axRect, primaryScreenHeight: primaryHeight)
                    return ScreenGeometry.bestScreenIndex(for: rect, screens: screenFrames).map { screens[$0].displayID }
                }
                let rawTitle = AX.string(element, kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let appName = app.localizedName ?? "App"
                found[id] = TaskWindow(
                    id: id, pid: pid, title: rawTitle.isEmpty ? appName : rawTitle, appName: appName,
                    bundleID: app.bundleIdentifier, isMinimized: AX.bool(element, kAXMinimizedAttribute) ?? false,
                    displayID: displayID, element: element
                )
                discovered.append(id)
                if let focusedElement, CFEqual(focusedElement, element) { focused = id }
            }
        }

        windowIDs = windowIDs.filter { seenKeys.contains($0.key) }
        observedWindows.formIntersection(seenKeys)
        let newWindows = order.update(with: discovered).compactMap { found[$0] }
        if newWindows != windows { windows = newWindows }
        if focused != focusedWindowID { focusedWindowID = focused }
        placeNewWindows()
    }

    // MARK: Placement

    /// After opening `appKey` from a taskbar or start menu on `displayID`, its windows go to that display:
    /// the window that comes to front (also an existing one, e.g. from another Space) and new ones.
    func expectNewWindow(appKey: String, on displayID: CGDirectDisplayID) {
        let existing = windows.filter { $0.appKey == appKey }
        placements.expect(appKey: appKey, on: displayID, knownWindows: Set(existing.map(\.id)))
        frontRequests[appKey] = (displayID, Date().addingTimeInterval(6))
        uiLog.notice("place expect app=\(appKey, privacy: .public) display=\(displayID) existing=\(existing.count)")
        // Poll quickly while waiting, so the window doesn't visibly jump late.
        if placementTimer == nil {
            placementTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    private func placeNewWindows() {
        moveFrontWindows()
        if !placements.isEmpty {
            let moves = placements.place(windows: windows.map { ($0.id, $0.appKey, $0.displayID) })
            for move in moves {
                guard let window = windows.first(where: { $0.id == move.id }) else { continue }
                moveWindow(window.element, appKey: window.appKey, to: move.display)
            }
            if !moves.isEmpty { scheduleRefresh() }
        }
        if placements.isEmpty && frontRequests.isEmpty {
            placementTimer?.invalidate()
            placementTimer = nil
        }
    }

    /// Moves the opened app's front window once the app is frontmost and the window is reachable.
    private func moveFrontWindows() {
        let now = Date()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for (appKey, request) in frontRequests {
            if request.deadline < now { frontRequests[appKey] = nil; continue }
            guard let pid = Self.pid(forAppKey: appKey), pid == frontPID else { continue }
            let appElement = AXUIElementCreateApplication(pid)
            guard let window = AX.element(appElement, kAXFocusedWindowAttribute) ?? AX.element(appElement, kAXMainWindowAttribute),
                  AX.isTaskWindow(window), AX.bool(window, kAXMinimizedAttribute) != true else { continue }
            frontRequests[appKey] = nil
            if displayID(of: window) != request.display {
                moveWindow(window, appKey: appKey, to: request.display)
                scheduleRefresh()
            }
        }
    }

    private static func pid(forAppKey appKey: String) -> pid_t? {
        if appKey.hasPrefix("pid-") { return pid_t(appKey.dropFirst(4)) }
        return NSRunningApplication.runningApplications(withBundleIdentifier: appKey).first?.processIdentifier
    }

    private func displayID(of window: AXUIElement) -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height, let axFrame = AX.frame(window) else { return nil }
        let frame = ScreenGeometry.cocoaRect(fromAccessibility: axFrame, primaryScreenHeight: primaryHeight)
        return ScreenGeometry.bestScreenIndex(for: frame, screens: screens.map(\.frame)).map { screens[$0].displayID }
    }

    private func moveWindow(_ window: AXUIElement, appKey: String, to displayID: CGDirectDisplayID) {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height,
              let target = NSScreen.with(displayID: displayID),
              let axFrame = AX.frame(window) else { return }
        let frame = ScreenGeometry.cocoaRect(fromAccessibility: axFrame, primaryScreenHeight: primaryHeight)
        let source = ScreenGeometry.bestScreenIndex(for: frame, screens: screens.map(\.frame)).map { screens[$0] } ?? target
        guard source.displayID != displayID else { return }
        func area(_ screen: NSScreen) -> CGRect {
            WindowPlacement.usableArea(screen: screen.frame, visible: screen.visibleFrame, barHeight: Theme.barHeight)
        }
        let placed = WindowPlacement.frame(frame, from: area(source), to: area(target))
        // The conversion is its own inverse (flip around the primary screen's height).
        let axPlaced = ScreenGeometry.cocoaRect(fromAccessibility: placed, primaryScreenHeight: primaryHeight)
        let ok = AX.setFrame(window, axPlaced)
        uiLog.notice("place move \(appKey, privacy: .public) to display=\(displayID) ok=\(ok)")
    }

    // MARK: AXObserver

    private func observer(for pid: pid_t, appElement: AXUIElement) -> AXObserver? {
        if let existing = appObservers[pid] { return existing }
        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let observer = created else { return nil }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                     kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
            AXObserverAddNotification(observer, appElement, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        appObservers[pid] = observer
        return observer
    }

    private func observeWindow(_ element: AXUIElement, key: AXElementKey, observer: AXObserver) {
        guard observedWindows.insert(key).inserted else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                     kAXWindowMovedNotification] {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
    }

    private func removeObserver(for pid: pid_t) {
        guard let observer = appObservers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        let stale = windowIDs.keys.filter { key in
            var windowPID: pid_t = 0
            return AXUIElementGetPid(key.element, &windowPID) == .success ? windowPID == pid : true
        }
        for key in stale {
            windowIDs[key] = nil
            observedWindows.remove(key)
        }
    }

    // MARK: Actions

    func isFrontmost(_ window: TaskWindow) -> Bool {
        window.id == focusedWindowID && window.pid == activePID && !window.isMinimized
    }

    func activate(_ window: TaskWindow) {
        if window.isMinimized { AX.set(window.element, kAXMinimizedAttribute, false) }
        NSRunningApplication(processIdentifier: window.pid)?.activate()
        AX.set(window.element, kAXMainAttribute, true)
        AX.perform(window.element, kAXRaiseAction)
        scheduleRefresh()
    }

    func minimize(_ window: TaskWindow) {
        AX.set(window.element, kAXMinimizedAttribute, true)
        scheduleRefresh()
    }

    /// Windows-like behavior: clicking the active window minimizes it, otherwise brings it to front.
    func toggle(_ window: TaskWindow) {
        isFrontmost(window) ? minimize(window) : activate(window)
    }

    func close(_ window: TaskWindow) {
        if let button = AX.element(window.element, kAXCloseButtonAttribute) {
            AX.perform(button, kAXPressAction)
        }
        scheduleRefresh()
    }

    func quitApp(of window: TaskWindow) {
        NSRunningApplication(processIdentifier: window.pid)?.terminate()
    }

    func closeAll(_ windows: [TaskWindow]) {
        for window in windows { close(window) }
    }
}

private let axCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { tracker.scheduleRefresh() }
}
