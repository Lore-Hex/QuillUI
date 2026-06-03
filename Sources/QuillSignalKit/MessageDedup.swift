//
// QuillSignalKit — message de-duplication by Signal timestamp.
//
// A message can reach the UI from three sources that overlap: the optimistic
// echo of a just-sent message, the `receive` push stream, and a `list-messages`
// reload of the stored thread. Signal stamps every message with a unique
// millisecond timestamp, so a per-thread set of seen timestamps lets us drop
// the duplicates. Pure + generic so it is unit-tested directly.
//
import Foundation

public enum MessageDedup {
    /// Return only the `incoming` items whose timestamp has not been seen yet
    /// for this thread, in their original order, inserting each kept timestamp
    /// into `seen`. Items with a `nil` timestamp can't be keyed, so they are
    /// always kept (and never recorded).
    public static func unseen<M>(
        _ incoming: [M],
        seen: inout Set<UInt64>,
        timestamp: (M) -> UInt64?
    ) -> [M] {
        var kept: [M] = []
        kept.reserveCapacity(incoming.count)
        for item in incoming {
            guard let ts = timestamp(item) else {
                kept.append(item) // no key -> can't dedup; keep it
                continue
            }
            if seen.contains(ts) { continue }
            seen.insert(ts)
            kept.append(item)
        }
        return kept
    }
}
