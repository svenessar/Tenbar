import Foundation

/// A menu item as read from another app's menu bar.
public struct MenuItemInfo: Equatable, Sendable {
    public var title: String
    /// Key equivalent, e.g. "N"; nil when the item has none.
    public var key: String?
    /// Accessibility modifier mask: 1 shift, 2 option, 4 control, 8 no command key.
    public var modifiers: Int
    public var enabled: Bool
    public var children: [MenuItemInfo]

    public init(title: String, key: String? = nil, modifiers: Int = 0, enabled: Bool = true, children: [MenuItemInfo] = []) {
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.enabled = enabled
        self.children = children
    }
}

/// A command offered in the taskbar's "Neu" submenu. `path` holds the menu titles
/// from the menu bar item down to this item, so it can be found again when pressed.
public struct MenuCommand: Hashable, Identifiable, Sendable {
    public var path: [String]
    public var shortcut: String?
    public var children: [MenuCommand]

    public var id: [String] { path }
    public var title: String { path.last ?? "" }

    public init(path: [String], shortcut: String? = nil, children: [MenuCommand] = []) {
        self.path = path
        self.shortcut = shortcut
        self.children = children
    }
}

public enum NewCommands {
    static let prefixes = ["neu", "new", "nouve", "nuev", "nuov"]
    static let maxChildren = 15

    /// Picks the "new window/tab/document" commands of an app's File menu.
    /// The ⌘N command comes first; submenus such as Terminal's "Neues Fenster" keep their items.
    public static func select(menuTitle: String, items: [MenuItemInfo]) -> [MenuCommand] {
        let picked = items.compactMap { command(for: $0, parent: [menuTitle]) }
        let primary = picked.filter { $0.shortcut == "⌘N" }
        return primary + picked.filter { $0.shortcut != "⌘N" }
    }

    static func command(for item: MenuItemInfo, parent: [String]) -> MenuCommand? {
        let title = item.title.trimmingCharacters(in: .whitespaces)
        guard item.enabled, !title.isEmpty else { return nil }
        let shortcut = shortcutText(key: item.key, modifiers: item.modifiers)
        let isNew = isNewTitle(title) || shortcut == "⌘N"
        guard isNew else { return nil }
        let path = parent + [title]
        if item.children.isEmpty {
            return MenuCommand(path: path, shortcut: shortcut)
        }
        let children = item.children
            .filter { $0.enabled && $0.children.isEmpty && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(maxChildren)
            .map { MenuCommand(path: path + [$0.title.trimmingCharacters(in: .whitespaces)],
                               shortcut: shortcutText(key: $0.key, modifiers: $0.modifiers)) }
        return children.isEmpty ? nil : MenuCommand(path: path, children: Array(children))
    }

    static func isNewTitle(_ title: String) -> Bool {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return prefixes.contains { folded.hasPrefix($0) }
    }

    /// "⇧⌘N"-style text in macOS menu order (⌃⌥⇧⌘).
    public static func shortcutText(key: String?, modifiers: Int) -> String? {
        guard let key, !key.isEmpty, key.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else { return nil }
        var text = ""
        if modifiers & 4 != 0 { text += "⌃" }
        if modifiers & 2 != 0 { text += "⌥" }
        if modifiers & 1 != 0 { text += "⇧" }
        if modifiers & 8 == 0 { text += "⌘" }
        return text + key.uppercased()
    }
}
