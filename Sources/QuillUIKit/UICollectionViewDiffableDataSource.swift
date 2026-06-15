import Foundation
import CoreGraphics

/// A Linux UIKit reimplementation of `UICollectionViewDiffableDataSource`.
///
/// This is a structural stand-in: it stores the cell/supplementary providers and
/// the most recently applied snapshot so that Signal's call sites compile and
/// retain their state. There is no live UIKit runtime backing this type, so
/// `apply(_:)` simply records the snapshot and invokes the completion handler,
/// and the index/identifier lookups return `nil`.
///
/// `NSDiffableDataSourceSnapshot` is declared elsewhere in this module and is
/// referenced generically here over `SectionIdentifierType` / `ItemIdentifierType`.
@MainActor
open class UICollectionViewDiffableDataSource<
    SectionIdentifierType: Hashable,
    ItemIdentifierType: Hashable
>: NSObject {

    /// Provides a configured cell for a given item identifier and index path.
    public typealias CellProvider = @MainActor (
        UICollectionView,
        IndexPath,
        ItemIdentifierType
    ) -> UICollectionViewCell?

    /// The collection view this data source drives.
    public let collectionView: UICollectionView

    /// The closure that vends cells for items.
    public let cellProvider: CellProvider

    /// Optional closure that vends supplementary views (headers/footers).
    public var supplementaryViewProvider: ((UICollectionView, String, IndexPath) -> UICollectionReusableView?)?

    /// The most recently applied snapshot, if any.
    ///
    /// `NSDiffableDataSourceSnapshot` may not expose a no-argument initializer in
    /// this module, so the snapshot is stored optionally and only materialized
    /// when one is applied. `snapshot()` returns a default-constructed value
    /// when nothing has been applied yet (see the note in the structured output).
    private var currentSnapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>?

    public init(
        collectionView: UICollectionView,
        cellProvider: @escaping CellProvider
    ) {
        self.collectionView = collectionView
        self.cellProvider = cellProvider
        super.init()
    }

    /// Records the supplied snapshot and invokes the completion handler.
    ///
    /// `animatingDifferences` is accepted for source compatibility but has no
    /// effect in this non-rendering reimplementation.
    open func apply(
        _ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>,
        animatingDifferences: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        self.currentSnapshot = snapshot
        completion?()
    }

    /// Returns the most recently applied snapshot, or a default-constructed one
    /// if no snapshot has been applied yet.
    open func snapshot() -> NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> {
        if let currentSnapshot {
            return currentSnapshot
        }
        return NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()
    }

    /// The item identifier for the given index path. Always `nil` in this
    /// non-rendering reimplementation.
    open func itemIdentifier(for indexPath: IndexPath) -> ItemIdentifierType? {
        return nil
    }

    /// The index path for the given item identifier. Always `nil` in this
    /// non-rendering reimplementation.
    open func indexPath(for itemIdentifier: ItemIdentifierType) -> IndexPath? {
        return nil
    }
}
