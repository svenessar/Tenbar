import CoreGraphics
import Foundation

public enum WindowPlacement {
    /// Moves `window` from the `source` area to the `target` area (same coordinate system),
    /// keeping its relative position and shrinking it if it doesn't fit.
    public static func frame(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let size = CGSize(width: min(window.width, target.width), height: min(window.height, target.height))
        func fraction(_ offset: CGFloat, _ free: CGFloat) -> CGFloat {
            free > 0 ? min(max(offset / free, 0), 1) : 0.5
        }
        let fx = fraction(window.minX - source.minX, source.width - window.width)
        let fy = fraction(window.minY - source.minY, source.height - window.height)
        return CGRect(
            x: (target.minX + fx * (target.width - size.width)).rounded(),
            y: (target.minY + fy * (target.height - size.height)).rounded(),
            width: size.width, height: size.height
        )
    }

    /// The area windows may use: the visible frame minus Tenbar's taskbar at the bottom (Cocoa coordinates).
    public static func usableArea(screen: CGRect, visible: CGRect, barHeight: CGFloat) -> CGRect {
        let minY = max(visible.minY, screen.minY + barHeight)
        return CGRect(x: visible.minX, y: minY, width: visible.width, height: max(visible.maxY - minY, 0))
    }
}

/// Remembers "this app was opened from display X" and decides which new windows to move there.
public struct PlacementRequests<WindowID: Hashable, Display: Hashable> {
    struct Request {
        var appKey: String
        var display: Display
        var knownWindows: Set<WindowID>
        var deadline: Date
    }

    private var requests: [Request] = []
    /// Waiting time for the first window (apps may launch slowly).
    public var timeout: TimeInterval = 20
    /// After the first window, further new windows (e.g. restored ones) are moved for this long.
    public var followUp: TimeInterval = 1.5

    public init() {}

    public var isEmpty: Bool { requests.isEmpty }

    /// `knownWindows`: the app's windows that existed before opening; they are never moved.
    public mutating func expect(appKey: String, on display: Display, knownWindows: Set<WindowID>, now: Date = Date()) {
        requests.removeAll { $0.appKey == appKey }
        requests.append(Request(appKey: appKey, display: display, knownWindows: knownWindows,
                                deadline: now.addingTimeInterval(timeout)))
    }

    /// Returns new windows with the display they should move to. Windows already on that display are
    /// accepted without a move.
    public mutating func place(
        windows: [(id: WindowID, appKey: String, display: Display?)], now: Date = Date()
    ) -> [(id: WindowID, display: Display)] {
        requests.removeAll { $0.deadline < now }
        var moves: [(id: WindowID, display: Display)] = []
        for index in requests.indices {
            let request = requests[index]
            let fresh = windows.filter { $0.appKey == request.appKey && !request.knownWindows.contains($0.id) }
            guard !fresh.isEmpty else { continue }
            for window in fresh where window.display != request.display {
                moves.append((window.id, request.display))
            }
            requests[index].knownWindows.formUnion(fresh.map(\.id))
            requests[index].deadline = min(request.deadline, now.addingTimeInterval(followUp))
        }
        return moves
    }
}
