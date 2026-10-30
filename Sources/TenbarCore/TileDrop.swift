import CoreGraphics

/// Where a dragged tile lands inside a group, computed from the mouse position and the tile frames.
public enum TileDrop {
    /// Returns the app to insert before, or nil to append at the end of the group.
    /// - Parameters:
    ///   - tiles: tile frames in display order, in the same coordinate space as `location`.
    ///   - headerMaxY: drops above this line (on the group header) go to the front.
    public static func target(location: CGPoint, tiles: [(id: String, frame: CGRect)], headerMaxY: CGFloat) -> String? {
        guard !tiles.isEmpty else { return nil }
        if location.y < headerMaxY { return tiles[0].id }
        // Tiles in the row under the mouse; insert before the first one whose center is right of the mouse.
        let row = tiles.indices.filter { tiles[$0].frame.minY <= location.y && location.y < tiles[$0].frame.maxY }
        guard let last = row.last else {
            // Between rows: before the first tile of the next row, else at the end.
            return tiles.first { $0.frame.minY > location.y }?.id
        }
        if let hit = row.first(where: { location.x < tiles[$0].frame.midX }) { return tiles[hit].id }
        return last + 1 < tiles.count ? tiles[last + 1].id : nil
    }
}
