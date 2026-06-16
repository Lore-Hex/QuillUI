//
// Foundation `Progress.performAsCurrent(withPendingUnitCount:using:)` for Linux.
//
// swift-corelibs Foundation ships `Progress` (NSProgress) but not the
// `performAsCurrent` convenience that SSK's DatabaseRecovery uses to scope a
// child-progress to a pending unit count. The progress-tree bookkeeping is
// cosmetic (drives a progress bar); on Linux we just run the work and return its
// result so the recovery logic is unaffected.
//
import Foundation

public extension Progress {
    @discardableResult
    func performAsCurrent<ReturnType>(
        withPendingUnitCount unitCount: Int64,
        using work: () throws -> ReturnType
    ) rethrows -> ReturnType {
        // Progress-tree attribution is a no-op on Linux; the work still runs.
        return try work()
    }
}
