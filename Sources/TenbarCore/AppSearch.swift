import Foundation

/// Start menu search: ranks names by how well they match, ignoring case and diacritics.
public enum AppSearch {
    /// Returns matching elements, best match first; keeps the input order within a rank.
    /// An empty or whitespace-only query returns everything unchanged.
    public static func filter<T>(_ items: [T], query: String, name: (T) -> String, id: (T) -> String = { _ in "" }) -> [T] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return items }
        return items.enumerated()
            .compactMap { index, item in rank(normalize(name(item)), id: normalize(id(item)), needle: needle).map { (item, $0, index) } }
            .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
            .map(\.0)
    }

    /// 0 = name starts with query, 1 = a word starts with it, 2 = name contains it, 3 = identifier contains it.
    static func rank(_ name: String, id: String, needle: String) -> Int? {
        if name.hasPrefix(needle) { return 0 }
        let words = name.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { $0.hasPrefix(needle) }) { return 1 }
        if name.contains(needle) { return 2 }
        if !id.isEmpty, id.contains(needle) { return 3 }
        return nil
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
