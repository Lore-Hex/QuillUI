import Foundation

/// Shared startup row-selection policy for fixture-backed app shells and
/// backend smoke tests.
///
/// Apps pass their ordered environment keys and item collection. The first
/// parseable key wins, negative indexes clamp to the first row, and oversized
/// indexes clamp to the last row.
public enum QuillInitialSelection {
    public static func index(
        environmentKeys: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int? {
        for key in environmentKeys {
            guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawValue.isEmpty,
                  let index = Int(rawValue)
            else { continue }
            return index
        }
        return nil
    }

    public static func selectedID<Item: Identifiable>(
        in items: [Item],
        environmentKeys: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Item.ID? {
        guard !items.isEmpty,
              let requestedIndex = index(environmentKeys: environmentKeys, environment: environment)
        else { return nil }

        let clampedIndex = min(max(requestedIndex, 0), items.count - 1)
        return items[clampedIndex].id
    }
}
