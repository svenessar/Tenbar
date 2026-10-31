import Foundation

/// Size of the start menu on one display. The two columns have independent widths, the height is shared.
public struct StartMenuSize: Codable, Equatable, Sendable {
    public static let railWidth: Double = 48
    public static let allAppsRange: ClosedRange<Double> = 180...480
    public static let minPinnedWidth: Double = 180
    public static let minHeight: Double = 300
    public static let standard = StartMenuSize(allAppsWidth: 240, pinnedWidth: 260, height: 480)

    public var allAppsWidth: Double
    public var pinnedWidth: Double
    public var height: Double

    public init(allAppsWidth: Double, pinnedWidth: Double, height: Double) {
        self.allAppsWidth = allAppsWidth
        self.pinnedWidth = pinnedWidth
        self.height = height
    }

    public var totalWidth: Double { width(showsAllApps: true) }

    /// The "All apps" column can be hidden per display, then only rail and pinned tiles are shown.
    public func width(showsAllApps: Bool) -> Double {
        Self.railWidth + (showsAllApps ? allAppsWidth : 0) + pinnedWidth
    }

    /// Dragging the top-right corner: width changes go to the pinned column (like Windows 10), height is shared.
    public func resized(width dx: Double, height dy: Double, maxTotalWidth: Double, maxHeight: Double) -> StartMenuSize {
        var size = self
        size.pinnedWidth += dx
        size.height += dy
        return size.clamped(maxTotalWidth: maxTotalWidth, maxHeight: maxHeight)
    }

    /// Dragging the divider between the columns: moves width from one column to the other, total stays the same.
    public func splitMoved(by dx: Double) -> StartMenuSize {
        let maxAllApps = min(Self.allAppsRange.upperBound, allAppsWidth + pinnedWidth - Self.minPinnedWidth)
        let newAllApps = min(max(allAppsWidth + dx, Self.allAppsRange.lowerBound), max(maxAllApps, Self.allAppsRange.lowerBound))
        var size = self
        size.pinnedWidth -= newAllApps - allAppsWidth
        size.allAppsWidth = newAllApps
        return size
    }

    /// Keeps the menu usable and on screen (e.g. after moving a setting to a smaller display).
    public func clamped(maxTotalWidth: Double, maxHeight: Double, showsAllApps: Bool = true) -> StartMenuSize {
        var size = self
        size.allAppsWidth = min(max(size.allAppsWidth, Self.allAppsRange.lowerBound), Self.allAppsRange.upperBound)
        let maxPinned = max(Self.minPinnedWidth, maxTotalWidth - Self.railWidth - (showsAllApps ? size.allAppsWidth : 0))
        size.pinnedWidth = min(max(size.pinnedWidth, Self.minPinnedWidth), maxPinned)
        size.height = min(max(size.height, Self.minHeight), max(Self.minHeight, maxHeight))
        return size
    }
}
