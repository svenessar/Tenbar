/// Keeps a stable order of IDs across updates: existing IDs keep their
/// position, new IDs are appended, vanished IDs are dropped.
public struct StableOrder<ID: Hashable>: Sendable where ID: Sendable {
    public private(set) var ids: [ID] = []

    public init(_ ids: [ID] = []) {
        self.ids = ids
    }

    @discardableResult
    public mutating func update(with current: [ID]) -> [ID] {
        let present = Set(current)
        var result = ids.filter { present.contains($0) }
        var known = Set(result)
        for id in current where known.insert(id).inserted {
            result.append(id)
        }
        ids = result
        return result
    }

    /// Moves `source` directly before `target`. No-op if either is unknown.
    public mutating func move(_ source: ID, before target: ID) {
        guard source != target,
              let sourceIndex = ids.firstIndex(of: source),
              ids.contains(target) else { return }
        ids.remove(at: sourceIndex)
        let targetIndex = ids.firstIndex(of: target)!
        ids.insert(source, at: targetIndex)
    }
}
