/// Zoom factor for text and icons in the start menu, set per display (e.g. larger on high-resolution screens).
public enum StartMenuScale {
    public static let range: ClosedRange<Double> = 0.8...1.8
    public static let standard: Double = 1
    public static let step: Double = 0.05

    public static func clamped(_ scale: Double) -> Double {
        guard scale.isFinite else { return standard }
        return min(max(scale, range.lowerBound), range.upperBound)
    }
}
