//
// SignalServiceKit NSFileCoordinator shim for QuillOS (Track B).
//
// GRDBDatabaseStorageAdapter.buildPool coordinates the database-file open through
// NSFileCoordinator (so multiple processes sharing the DB don't corrupt it).
// swift-corelibs Foundation has no NSFileCoordinator (verified via 1-file swiftc).
// QuillOS runs the DB single-process, so coordination is INERT: the shim simply
// invokes the accessor with the same URL (the DatabasePool open happens directly).
// HONEST STATUS: no cross-process file coordination on Linux.
//
// Same-module port (linked via quill-signal-link-ports) -> visible to SSK without
// an import. On Apple the real SignalServiceKit + Foundation are used, so this
// file is Linux-only (the port dir is only added to the Linux SSK target).
//
import Foundation

public class NSFileCoordinator {
    public struct WritingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        // Raw values match Apple's <Foundation/NSFileCoordinator.h>.
        public static let forDeleting = WritingOptions(rawValue: 1 << 0)
        public static let forMoving = WritingOptions(rawValue: 1 << 1)
        public static let forMerging = WritingOptions(rawValue: 1 << 4)
        public static let forReplacing = WritingOptions(rawValue: 1 << 5)
        public static let contentIndependentMetadataOnly = WritingOptions(rawValue: 1 << 4)
    }

    public struct ReadingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let withoutChanges = ReadingOptions(rawValue: 1 << 0)
        public static let resolvesSymbolicLink = ReadingOptions(rawValue: 1 << 1)
        public static let immediatelyAvailableMetadataOnly = ReadingOptions(rawValue: 1 << 2)
    }

    public init(filePresenter: Any? = nil) {}

    /// Inert: no real coordination on Linux. Runs the accessor with the same URL.
    public func coordinate(
        writingItemAt url: URL,
        options: WritingOptions = [],
        error outError: UnsafeMutablePointer<NSError?>? = nil,
        byAccessor accessor: (URL) -> Void
    ) {
        accessor(url)
    }

    /// Inert: see writing variant.
    public func coordinate(
        readingItemAt url: URL,
        options: ReadingOptions = [],
        error outError: UnsafeMutablePointer<NSError?>? = nil,
        byAccessor accessor: (URL) -> Void
    ) {
        accessor(url)
    }
}
