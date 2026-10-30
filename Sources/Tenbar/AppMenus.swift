import AppKit
@preconcurrency import ApplicationServices
import TenbarCore

/// Reads the "new …" commands from other apps' menu bars and triggers them,
/// e.g. "Neues Finder-Fenster" (⌘N) for the taskbar's "Neu" submenu.
@MainActor
final class AppMenus: ObservableObject {
    @Published private(set) var commands: [pid_t: [MenuCommand]] = [:]
    private var lastRead: [pid_t: Date] = [:]

    /// Re-reads an app's File menu, at most every two seconds per app.
    func refresh(pid: pid_t) {
        if let last = lastRead[pid], Date().timeIntervalSince(last) < 2 { return }
        lastRead[pid] = Date()
        Task.detached(priority: .userInitiated) {
            let commands = Self.readCommands(pid: pid)
            await MainActor.run {
                if self.commands[pid] != commands {
                    uiLog.notice("menu commands pid=\(pid) \(commands.map(\.title).joined(separator: " | "), privacy: .public)")
                    self.commands[pid] = commands
                }
            }
        }
    }

    func perform(_ command: MenuCommand, pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate()
        // Give the app a moment to come to front, so the new window opens on top.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let pressed = Self.press(path: command.path, pid: pid)
            uiLog.notice("menu press \(command.path.joined(separator: " > "), privacy: .public) ok=\(pressed)")
        }
    }

    // MARK: Accessibility

    private nonisolated static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        return app
    }

    /// Menu bar items: 0 is the Apple menu, 1 the app menu, 2 the File menu.
    private nonisolated static func readCommands(pid: pid_t) -> [MenuCommand] {
        guard let menuBar = AX.element(application(pid), kAXMenuBarAttribute) else {
            uiLog.notice("menu read pid=\(pid) no menu bar trusted=\(AXIsProcessTrusted())")
            return []
        }
        let barItems = AX.elements(menuBar, kAXChildrenAttribute)
        guard barItems.count > 2, let title = AX.string(barItems[2], kAXTitleAttribute) else { return [] }
        let fileItems = items(of: barItems[2], depth: 2)
        return NewCommands.select(menuTitle: title, items: fileItems)
    }

    private nonisolated static func items(of parent: AXUIElement, depth: Int) -> [MenuItemInfo] {
        guard depth > 0, let menu = AX.elements(parent, kAXChildrenAttribute).first else { return [] }
        return AX.elements(menu, kAXChildrenAttribute).map { item in
            MenuItemInfo(
                title: AX.string(item, kAXTitleAttribute) ?? "",
                key: AX.string(item, kAXMenuItemCmdCharAttribute),
                modifiers: (AX.attribute(item, kAXMenuItemCmdModifiersAttribute) as? Int) ?? 0,
                enabled: AX.bool(item, kAXEnabledAttribute) ?? false,
                children: items(of: item, depth: depth - 1)
            )
        }
    }

    /// Finds the item again by its titles (menus may have been rebuilt) and presses it.
    private static func press(path: [String], pid: pid_t) -> Bool {
        guard let menuBar = AX.element(application(pid), kAXMenuBarAttribute), let first = path.first,
              var current = AX.elements(menuBar, kAXChildrenAttribute).first(where: { AX.string($0, kAXTitleAttribute) == first })
        else { return false }
        for title in path.dropFirst() {
            guard let menu = AX.elements(current, kAXChildrenAttribute).first,
                  let next = AX.elements(menu, kAXChildrenAttribute).first(where: {
                      AX.string($0, kAXTitleAttribute)?.trimmingCharacters(in: .whitespaces) == title
                  })
            else { return false }
            current = next
        }
        return AX.perform(current, kAXPressAction)
    }
}
