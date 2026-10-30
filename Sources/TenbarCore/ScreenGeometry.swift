import CoreGraphics

public enum ScreenGeometry {
    /// Converts an Accessibility rect (origin top-left of the primary screen, y down)
    /// into Cocoa coordinates (origin bottom-left of the primary screen, y up).
    public static func cocoaRect(fromAccessibility rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Index of the screen that shows the largest part of `rect`.
    /// Falls back to the screen containing the rect's center, then nil.
    public static func bestScreenIndex(for rect: CGRect, screens: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        if let best { return best.index }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return screens.firstIndex { $0.contains(center) }
    }
}
