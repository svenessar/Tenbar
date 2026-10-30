/// Ordered list of pinned app IDs without duplicates.
public struct PinList: Equatable, Sendable {
    public private(set) var ids: [String]

    public init(_ ids: [String] = []) {
        var seen = Set<String>()
        self.ids = ids.filter { seen.insert($0).inserted }
    }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    public mutating func pin(_ id: String) {
        guard !contains(id) else { return }
        ids.append(id)
    }

    public mutating func unpin(_ id: String) {
        ids.removeAll { $0 == id }
    }

    public mutating func toggle(_ id: String) {
        contains(id) ? unpin(id) : pin(id)
    }

    public mutating func move(_ source: String, before target: String) {
        var order = StableOrder(ids)
        order.move(source, before: target)
        ids = order.ids
    }

    /// Picks initial pins: preferred IDs that are installed, otherwise the first few available apps.
    public static func defaults(available: [String], preferred: [String], fallbackCount: Int = 5) -> PinList {
        let installed = Set(available)
        let chosen = preferred.filter { installed.contains($0) }
        return PinList(chosen.isEmpty ? Array(available.prefix(fallbackCount)) : chosen)
    }
}
