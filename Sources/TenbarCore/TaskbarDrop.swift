/// Rules for dropping an app (by app key) onto the taskbar, Windows 10 style:
/// pinned apps reorder among pins, running unpinned apps reorder among themselves,
/// and apps dragged in from elsewhere (e.g. the start menu) get pinned.
public enum TaskbarDrop {
    public enum Result: Equatable, Sendable {
        case none
        case pins(PinList)
        case unpinnedOrder([String])
    }

    /// - Parameters:
    ///   - source: app key being dragged.
    ///   - target: app key it was dropped on; nil means "after the last item".
    ///   - visibleUnpinned: unpinned app keys currently shown, in display order.
    ///   - unpinnedOrder: the stored order (may contain apps not shown on this display).
    public static func apply(
        source: String,
        target: String?,
        pins: PinList,
        visibleUnpinned: [String],
        unpinnedOrder: [String]
    ) -> Result {
        guard source != target else { return .none }
        let targetIsPinned = target.map(pins.contains) ?? false

        if pins.contains(source) {
            var updated = pins
            if let target, targetIsPinned {
                updated.move(source, before: target)
            } else {
                updated.unpin(source)
                updated.pin(source)
            }
            return updated == pins ? .none : .pins(updated)
        }

        if visibleUnpinned.contains(source) {
            guard target == nil || visibleUnpinned.contains(target!) else { return .none }
            var order = visibleUnpinned.filter { $0 != source }
            if let target, let index = order.firstIndex(of: target) {
                order.insert(source, at: index)
            } else {
                order.append(source)
            }
            let hidden = unpinnedOrder.filter { !visibleUnpinned.contains($0) }
            let result = order + hidden
            return result == unpinnedOrder ? .none : .unpinnedOrder(result)
        }

        var updated = pins
        updated.pin(source)
        if let target, targetIsPinned { updated.move(source, before: target) }
        return .pins(updated)
    }
}
