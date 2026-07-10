//===----------------------------------------------------------------------===//
//
//  UICollectionViewExtras.swift
//  QuillUIKit — the UICollectionView family surface for Linux
//
//  The UICollectionView / UICollectionViewCell class BODIES live in
//  QuillUIKit.swift (another owner). Everything else in the family is
//  declared fresh here:
//
//    - UICollectionViewLayoutAttributes / UICollectionViewLayoutInvalidationContext
//    - UICollectionViewLayout (open: upstream subclasses override prepare(),
//      layoutAttributesForElements(in:), collectionViewContentSize, …)
//    - UICollectionViewFlowLayout (open: RTLEnabledCollectionViewFlowLayout
//      overrides flipsHorizontallyInOppositeLayoutDirection)
//    - UICollectionReusableView (open: StickerPickerHeaderView subclasses it)
//    - UICollectionViewDataSource / UICollectionViewDelegate /
//      UICollectionViewDelegateFlowLayout protocols, with Apple's optional
//      requirements modeled as defaulted extension members
//    - UICollectionView nested types (ScrollPosition, ScrollDirection,
//      elementKindSectionHeader/Footer, CellRegistration) and the register /
//      dequeue / item-geometry API, as extensions over the existing body
//    - UICollectionViewCell configuration plumbing (ConfigurationUpdateHandler,
//      backgroundView) and the UIBackgroundConfiguration.clear() surface
//
//  Honest Linux semantics (MODEL-not-engine, same rules as UIScrollViewExtras):
//    - There is no virtualized render/event engine, so reloadData() realizes a
//      synchronous snapshot: it consults the data source, creates cells, applies
//      available layout attributes, and records visibleCells / cellForItem(at:).
//      That is enough for static Linux rendering without claiming UIKit's
//      incremental diffing or recycling behavior.
//    - dequeueReusableCell / dequeueReusableSupplementaryView return fresh
//      instances. Constructing an arbitrary registered subclass from its AnyClass
//      metatype would need a `required` initializer, which cannot be imposed on
//      UIView without breaking every upstream `override init(frame:)`; concrete
//      collection views can opt into typed cell construction through
//      QuillUICollectionViewCellFactory.
//    - scrollToItem(at:) resolves the item's frame through the layout object
//      (real geometry if the layout has been prepared) and translates
//      bounds.origin — the same "contentOffset IS bounds.origin" model as
//      UIScrollViewExtras. It writes bounds.origin directly rather than
//      setContentOffset so this file stays compilable both before and after
//      UICollectionView's class body re-parents onto UIScrollView.
//
//  Storage: class bodies owned elsewhere mean extensions cannot add stored
//  properties, so per-instance state lives in file-scope side tables with the
//  weak-`owner` address-reuse guard (the UIScrollViewExtras pattern).
//
//  NOT here on purpose:
//    - `delegate`: UICollectionViewDelegate refines UIScrollViewDelegate, so
//      once UICollectionView inherits UIScrollView, assignments like
//      `collectionView.delegate = self` land on UIScrollView's existing
//      `weak var delegate: UIScrollViewDelegate?` (QuillUIKit.swift) — no
//      shadow property needed.
//    - `collectionViewLayout` storage is here (side table), but the
//      designated `init(frame:collectionViewLayout:)` must live in the class
//      body (subclasses chain `super.init(frame:collectionViewLayout:)`).
//
//===----------------------------------------------------------------------===//

import QuillFoundation

#if !os(iOS)

// MARK: - UICollectionViewLayoutAttributes

/// Per-item layout geometry produced by a UICollectionViewLayout. Faithful
/// value carrier: layouts in SignalUI (NewMembersBarLayout,
/// LinearHorizontalLayout) construct these, set `frame`, and filter on it.
@MainActor open class UICollectionViewLayoutAttributes: NSObject {

    public var frame: CGRect = .zero
    public var alpha: CGFloat = 1
    public var zIndex: Int = 0
    public var isHidden: Bool = false
    public var indexPath: IndexPath

    /// The supplementary-view kind, or nil for a cell. Apple exposes this
    /// read-only; the factory initializers below are the only writers.
    public let representedElementKind: String?

    /// Apple semantics: center/size are views over `frame`.
    public var center: CGPoint {
        get { CGPoint(x: frame.midX, y: frame.midY) }
        set { frame.origin = CGPoint(x: newValue.x - frame.width / 2, y: newValue.y - frame.height / 2) }
    }

    public var size: CGSize {
        get { frame.size }
        set { frame.size = newValue }
    }

    public convenience init(forCellWith indexPath: IndexPath) {
        self.init(indexPath: indexPath, elementKind: nil)
    }

    public convenience init(forSupplementaryViewOfKind elementKind: String, with indexPath: IndexPath) {
        self.init(indexPath: indexPath, elementKind: elementKind)
    }

    public required init(indexPath: IndexPath, elementKind: String?) {
        self.indexPath = indexPath
        self.representedElementKind = elementKind
        super.init()
    }

    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = type(of: self).init(indexPath: indexPath, elementKind: representedElementKind)
        copy.frame = frame
        copy.alpha = alpha
        copy.zIndex = zIndex
        copy.isHidden = isHidden
        return copy
    }
}

// MARK: - UICollectionViewLayoutInvalidationContext

/// Carrier object for invalidateLayout(with:). Upstream only passes it
/// through to super, so the flags are honest constants matching Apple's
/// full-invalidation default.
@MainActor open class UICollectionViewLayoutInvalidationContext: NSObject {
    public override init() { super.init() }
    open var invalidateEverything: Bool { true }
    open var invalidateDataSourceCounts: Bool { true }
    open var contentOffsetAdjustment: CGPoint = .zero
}

// MARK: - UICollectionViewLayout

/// Abstract layout base. Every member that SignalUI overrides
/// (NewMembersBarLayout, LinearHorizontalLayout) is declared in the class
/// body as `open` — extension members cannot be overridden.
@MainActor open class UICollectionViewLayout: NSObject {

    /// The collection view using this layout. Set by
    /// UICollectionView.collectionViewLayout's setter (same module).
    public internal(set) weak var collectionView: UICollectionView?

    public override init() { super.init() }

    /// Schedule the collection view to realize a fresh cell snapshot after
    /// subclass invalidation finishes. UIKit performs this on the next layout
    /// pass; Linux has no run-loop layout engine, so the shim coalesces the
    /// equivalent work onto the next main-actor turn.
    open func invalidateLayout() {
        collectionView?.quillScheduleReloadAfterLayoutInvalidation()
    }

    open func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        _ = context
        collectionView?.quillScheduleReloadAfterLayoutInvalidation()
    }

    open func prepare() {}

    open var collectionViewContentSize: CGSize { .zero }

    open func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        _ = rect
        return nil
    }

    open func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        _ = indexPath
        return nil
    }

    open func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        _ = newBounds
        return false
    }

    open func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        _ = velocity
        return proposedContentOffset
    }

    open func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        proposedContentOffset
    }

    /// RTL mirroring opt-in. UIKit default false; RTLEnabledCollectionViewFlowLayout
    /// and LinearHorizontalLayout override to true.
    open var flipsHorizontallyInOppositeLayoutDirection: Bool { false }
}

// MARK: - UICollectionViewFlowLayout

/// Line-oriented layout. Stored configuration with Apple's documented
/// defaults; no measurement pass consumes them on Linux yet, but
/// StickerPackCollectionView reads `itemSize` back to decide invalidation,
/// so the storage is load-bearing state, not write-only.
@MainActor open class UICollectionViewFlowLayout: UICollectionViewLayout {
    public var scrollDirection: UICollectionView.ScrollDirection = .vertical
    /// Apple's default item size (50×50).
    public var itemSize: CGSize = CGSize(width: 50, height: 50)
    /// Apple's default inter-line spacing (10).
    public var minimumLineSpacing: CGFloat = 10
    /// Apple's default intra-line spacing (10).
    public var minimumInteritemSpacing: CGFloat = 10
    public var estimatedItemSize: CGSize = .zero
}

// MARK: - UICollectionReusableView

/// Base class for supplementary views (section headers/footers).
@MainActor open class UICollectionReusableView: UIView {

    public override init(frame: CGRect) { super.init(frame: frame) }

    /// UIView.init() is designated, so a parameterless convenience must be
    /// an override; subclasses that override init(frame:) (StickerPicker's
    /// header view) inherit it, keeping `HeaderView()` call sites working.
    public convenience init() { self.init(frame: .zero) }

    // Own designated init suppresses inheritance of UIView's
    // required init?(coder:); restate it.
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    open func prepareForReuse() {}
}

/// Escape hatch for app-specific collection views whose registered cell
/// subclasses cannot be constructed from an erased metatype. QuillUIKit asks the
/// concrete collection view first, then falls back to a base UICollectionViewCell.
@MainActor public protocol QuillUICollectionViewCellFactory: AnyObject {
    func quillCollectionView(
        _ collectionView: UICollectionView,
        makeCellWithReuseIdentifier identifier: String,
        for indexPath: IndexPath
    ) -> UICollectionViewCell?
}

// MARK: - Data source / delegate protocols

/// Apple's optional requirements are modeled as protocol requirements with
/// defaulted extension implementations — the UIScrollViewDelegate pattern.
@MainActor public protocol UICollectionViewDataSource: AnyObject {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell

    // Optional on Apple:
    func numberOfSections(in collectionView: UICollectionView) -> Int
    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView
}

public extension UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        UICollectionReusableView(frame: .zero)
    }
}

/// Refines UIScrollViewDelegate exactly as on Apple — that refinement is what
/// lets `collectionView.delegate = self` land on UIScrollView's inherited
/// `delegate` property without a shadow declaration here.
@MainActor public protocol UICollectionViewDelegate: UIScrollViewDelegate {
    // All optional on Apple:
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath)
    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath)
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath)
}

public extension UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {}
    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool { true }
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {}
    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {}
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {}
}

@MainActor public protocol UICollectionViewDelegateFlowLayout: UICollectionViewDelegate {
    // All optional on Apple:
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat
}

public extension UICollectionViewDelegateFlowLayout {
    /// Defaults mirror Apple: fall back to the flow layout's configuration.
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        (collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize ?? CGSize(width: 50, height: 50)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        .zero
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumLineSpacing ?? 10
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat {
        (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumInteritemSpacing ?? 10
    }
}

// MARK: - UICollectionView per-instance state side table

private struct QuillCollectionViewState {
    /// Address-reuse guard: an entry is only valid while the view that wrote
    /// it is alive AND is the view reading it (UIScrollViewExtras rationale).
    weak var owner: UICollectionView?

    weak var dataSource: (any UICollectionViewDataSource)?
    var layout: UICollectionViewLayout?
    var backgroundView: UIView?
    var allowsMultipleSelection = false
    var isPrefetchingEnabled = true

    /// Registration tables: reuse identifier → registered class. Recorded
    /// faithfully even though dequeue cannot construct arbitrary subclasses
    /// (see file header).
    var cellClasses: [String: AnyClass] = [:]
    /// element kind → (reuse identifier → registered class)
    var supplementaryClasses: [String: [String: AnyClass]] = [:]
    var realizedCells: [IndexPath: UICollectionViewCell] = [:]
    var realizedIndexPaths: [IndexPath] = []
    var selectedIndexPaths: Set<IndexPath> = []
    var isPerformingBatchUpdates = false
    var isReloadingData = false
    var needsReloadAfterBatchUpdates = false
    var hasScheduledReloadAfterLayoutInvalidation = false
}

@MainActor private var quillCollectionViewStates: [ObjectIdentifier: QuillCollectionViewState] = [:]

// MARK: - UICollectionView API surface

extension UICollectionView {

    /// The instance's state, validated against address reuse on read and
    /// re-stamped with `owner` on write; dead entries are swept on first
    /// write from a new instance (UIScrollViewExtras pattern).
    private var quillCollectionState: QuillCollectionViewState {
        get {
            if let state = quillCollectionViewStates[ObjectIdentifier(self)], state.owner === self {
                return state
            }
            return QuillCollectionViewState(owner: self)
        }
        set {
            if quillCollectionViewStates[ObjectIdentifier(self)]?.owner !== self {
                quillCollectionViewStates = quillCollectionViewStates.filter { $0.value.owner != nil }
            }
            var state = newValue
            state.owner = self
            quillCollectionViewStates[ObjectIdentifier(self)] = state
        }
    }

    // MARK: Nested types

    /// Section-supplementary element kinds. Raw values match Apple's
    /// (UICollectionElementKindSection… are the ObjC constants' values).
    public static let elementKindSectionHeader = "UICollectionElementKindSectionHeader"
    public static let elementKindSectionFooter = "UICollectionElementKindSectionFooter"

    public enum ScrollDirection: Int, Sendable {
        case vertical
        case horizontal
    }

    public struct ScrollPosition: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let top = ScrollPosition(rawValue: 1 << 0)
        public static let centeredVertically = ScrollPosition(rawValue: 1 << 1)
        public static let bottom = ScrollPosition(rawValue: 1 << 2)
        public static let left = ScrollPosition(rawValue: 1 << 3)
        public static let centeredHorizontally = ScrollPosition(rawValue: 1 << 4)
        public static let right = ScrollPosition(rawValue: 1 << 5)
    }

    /// Modern cell-registration API: captures the configuration closure;
    /// dequeueConfiguredReusableCell(using:for:item:) replays it.
    public struct CellRegistration<Cell, Item> where Cell: UICollectionViewCell {
        public typealias Handler = @MainActor (_ cell: Cell, _ indexPath: IndexPath, _ item: Item) -> Void

        public let handler: Handler

        public init(handler: @escaping Handler) {
            self.handler = handler
        }
    }

    // MARK: Data source / layout / chrome

    /// Weak, exactly as on Apple — the reference is held `weak` inside the
    /// side-table entry (computed properties cannot carry `weak` directly).
    /// (`delegate` is NOT declared here — see the file header; it lands on
    /// UIScrollView's inherited property.)
    public var dataSource: (any UICollectionViewDataSource)? {
        get { quillCollectionState.dataSource }
        set { quillCollectionState.dataSource = newValue }
    }

    /// The layout object. The designated `init(frame:collectionViewLayout:)`
    /// in the class body assigns through this setter, which performs the
    /// layout→view back-attachment Apple does (layout.collectionView).
    public var collectionViewLayout: UICollectionViewLayout {
        get {
            if let layout = quillCollectionState.layout { return layout }
            // Apple's parameterless UICollectionView path defaults to a flow
            // layout; reaching this before the designated init has run is
            // only possible from the class body itself.
            let layout = UICollectionViewFlowLayout()
            quillCollectionState.layout = layout
            layout.collectionView = self
            return layout
        }
        set {
            quillCollectionState.layout = newValue
            newValue.collectionView = self
        }
    }

    /// Stored faithfully; no compositor composites it behind cells yet.
    public var backgroundView: UIView? {
        get { quillCollectionState.backgroundView }
        set { quillCollectionState.backgroundView = newValue }
    }

    public var allowsMultipleSelection: Bool {
        get { quillCollectionState.allowsMultipleSelection }
        set { quillCollectionState.allowsMultipleSelection = newValue }
    }

    public var isPrefetchingEnabled: Bool {
        get { quillCollectionState.isPrefetchingEnabled }
        set { quillCollectionState.isPrefetchingEnabled = newValue }
    }

    // MARK: Counts (live dataSource queries, as on Apple post-reload)

    public var numberOfSections: Int {
        guard let dataSource else { return 0 }
        return dataSource.numberOfSections(in: self)
    }

    public func numberOfItems(inSection section: Int) -> Int {
        guard let dataSource else { return 0 }
        return dataSource.collectionView(self, numberOfItemsInSection: section)
    }

    // MARK: Registration / dequeue

    public func register(_ cellClass: AnyClass?, forCellWithReuseIdentifier identifier: String) {
        quillCollectionState.cellClasses[identifier] = cellClass
    }

    public func register(
        _ viewClass: AnyClass?,
        forSupplementaryViewOfKind elementKind: String,
        withReuseIdentifier identifier: String
    ) {
        quillCollectionState.supplementaryClasses[elementKind, default: [:]][identifier] = viewClass
    }

    /// Returns a fresh base-class cell (see the file header for why the
    /// registered subclass cannot always be constructed from its metatype).
    /// Concrete collection-view subclasses can opt into construction through
    /// QuillUICollectionViewCellFactory.
    public func dequeueReusableCell(withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UICollectionViewCell {
        if let factory = self as? QuillUICollectionViewCellFactory,
           let cell = factory.quillCollectionView(self, makeCellWithReuseIdentifier: identifier, for: indexPath) {
            return cell
        }
        _ = (identifier, indexPath)
        return UICollectionViewCell(frame: .zero)
    }

    public func dequeueReusableSupplementaryView(
        ofKind elementKind: String,
        withReuseIdentifier identifier: String,
        for indexPath: IndexPath
    ) -> UICollectionReusableView {
        _ = (elementKind, identifier, indexPath)
        return UICollectionReusableView(frame: .zero)
    }

    public func dequeueConfiguredReusableCell<Cell, Item>(
        using registration: CellRegistration<Cell, Item>,
        for indexPath: IndexPath,
        item: Item?
    ) -> Cell where Cell: UICollectionViewCell {
        // SignalUI only registers Cell == UICollectionViewCell, so the base
        // instance IS the requested type; a genuine subclass would trap here,
        // honestly surfacing the missing-required-init limitation.
        let cell = UICollectionViewCell(frame: .zero) as! Cell
        if let item {
            registration.handler(cell, indexPath, item)
        }
        return cell
    }

    // MARK: Content updates

    /// Item-level reload. Linux realizes a synchronous snapshot, so any
    /// item mutation invalidates that snapshot. During batch updates we defer
    /// the refresh until the update block finishes, matching UIKit's "final
    /// data source state" contract closely enough for Signal's loader.
    public func reloadItems(at indexPaths: [IndexPath]) {
        quillApplyContentMutation(indexPaths)
    }

    public func insertItems(at indexPaths: [IndexPath]) {
        quillApplyContentMutation(indexPaths)
    }

    public func deleteItems(at indexPaths: [IndexPath]) {
        quillApplyContentMutation(indexPaths)
    }

    public func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        quillApplyContentMutation([indexPath, newIndexPath])
    }

    public func selectItem(at indexPath: IndexPath?, animated: Bool, scrollPosition: ScrollPosition) {
        _ = (animated, scrollPosition)
        var state = quillCollectionState
        guard let indexPath else {
            state.selectedIndexPaths.removeAll()
            quillCollectionState = state
            return
        }
        if !allowsMultipleSelection {
            state.selectedIndexPaths.removeAll()
        }
        state.selectedIndexPaths.insert(indexPath)
        quillCollectionState = state
    }

    func quillDeselectItem(at indexPath: IndexPath) {
        var state = quillCollectionState
        state.selectedIndexPaths.remove(indexPath)
        quillCollectionState = state
    }

    func quillPerformBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)?) {
        var state = quillCollectionState
        state.isPerformingBatchUpdates = true
        state.needsReloadAfterBatchUpdates = false
        quillCollectionState = state

        updates?()

        state = quillCollectionState
        let shouldReload = state.needsReloadAfterBatchUpdates
        state.isPerformingBatchUpdates = false
        state.needsReloadAfterBatchUpdates = false
        quillCollectionState = state

        if shouldReload {
            quillReloadDataAndNotify()
        }
        completion?(true)
    }

    private func quillApplyContentMutation(_ indexPaths: [IndexPath]) {
        _ = indexPaths
        var state = quillCollectionState
        if state.isPerformingBatchUpdates {
            state.needsReloadAfterBatchUpdates = true
            quillCollectionState = state
        } else {
            quillReloadDataAndNotify()
        }
    }

    // MARK: Realized-cell snapshot

    func quillReloadDataAndNotify() {
        var state = quillCollectionState
        guard !state.isReloadingData else { return }
        state.isReloadingData = true
        quillCollectionState = state
        defer {
            var state = quillCollectionState
            let shouldReloadAgain = state.needsReloadAfterBatchUpdates
            state.isReloadingData = false
            state.needsReloadAfterBatchUpdates = false
            quillCollectionState = state
            if shouldReloadAgain {
                quillScheduleReloadAfterLayoutInvalidation()
            }
        }

        QuillUIKitMutationNotifications.withoutNotifications {
            quillReloadData()
        }
        quillNotifySubviewMutation()
    }

    func quillScheduleReloadAfterLayoutInvalidation() {
        var state = quillCollectionState
        guard state.dataSource != nil else { return }

        if state.isReloadingData || state.isPerformingBatchUpdates {
            state.needsReloadAfterBatchUpdates = true
            quillCollectionState = state
            return
        }

        guard !state.hasScheduledReloadAfterLayoutInvalidation else { return }
        state.hasScheduledReloadAfterLayoutInvalidation = true
        quillCollectionState = state

        Task { @MainActor [weak self] in
            guard let self else { return }
            var state = self.quillCollectionState
            guard state.hasScheduledReloadAfterLayoutInvalidation else { return }
            state.hasScheduledReloadAfterLayoutInvalidation = false
            self.quillCollectionState = state
            self.quillReloadDataAndNotify()
        }
    }

    func quillReloadData() {
        var state = quillCollectionState
        let oldCells = Array(state.realizedCells.values)
        state.realizedCells.removeAll()
        state.realizedIndexPaths.removeAll()
        quillCollectionState = state

        for cell in oldCells where cell.superview === self {
            cell.removeFromSuperview()
        }

        collectionViewLayout.prepare()

        guard let dataSource else {
            contentSize = collectionViewLayout.collectionViewContentSize
            return
        }

        var realizedCells: [IndexPath: UICollectionViewCell] = [:]
        var realizedIndexPaths: [IndexPath] = []
        var fallbackY: CGFloat = 0
        var contentUnion = CGRect.null
        let prefetchedAttributes = quillPrefetchedLayoutAttributesByIndexPath()

        let sectionCount = max(0, dataSource.numberOfSections(in: self))
        for section in 0..<sectionCount {
            let itemCount = max(0, dataSource.collectionView(self, numberOfItemsInSection: section))
            for item in 0..<itemCount {
                let indexPath = IndexPath(item: item, section: section)
                let cell = dataSource.collectionView(self, cellForItemAt: indexPath)

                if let attributes = prefetchedAttributes[indexPath] {
                    cell.apply(attributes)
                } else if prefetchedAttributes.isEmpty, let attributes = collectionViewLayout.layoutAttributesForItem(at: indexPath) {
                    cell.apply(attributes)
                } else if cell.frame.size == .zero {
                    let fallbackSize = quillFallbackItemSize()
                    cell.frame = CGRect(x: 0, y: fallbackY, width: fallbackSize.width, height: fallbackSize.height)
                    fallbackY += fallbackSize.height
                }
                cell.layoutIfNeeded()

                addSubview(cell)
                (delegate as? UICollectionViewDelegate)?.collectionView(self, willDisplay: cell, forItemAt: indexPath)
                realizedCells[indexPath] = cell
                realizedIndexPaths.append(indexPath)
                contentUnion = contentUnion.union(cell.frame)
            }
        }

        state = quillCollectionState
        state.realizedCells = realizedCells
        state.realizedIndexPaths = realizedIndexPaths
        quillCollectionState = state

        let layoutContentSize = collectionViewLayout.collectionViewContentSize
        if layoutContentSize.width > 0 || layoutContentSize.height > 0 {
            contentSize = layoutContentSize
        } else if !contentUnion.isNull {
            contentSize = CGSize(width: max(contentUnion.maxX, bounds.width), height: max(contentUnion.maxY, bounds.height))
        } else {
            contentSize = .zero
        }
    }

    private func quillPrefetchedLayoutAttributesByIndexPath() -> [IndexPath: UICollectionViewLayoutAttributes] {
        let layoutContentSize = collectionViewLayout.collectionViewContentSize
        let scanRect = CGRect(
            x: min(bounds.minX, contentOffset.x) - 10_000,
            y: min(bounds.minY, contentOffset.y) - 1_000_000,
            width: max(bounds.width, layoutContentSize.width, 1) + 20_000,
            height: max(bounds.height, layoutContentSize.height, 1) + 2_000_000
        )
        let attributes = collectionViewLayout.layoutAttributesForElements(in: scanRect) ?? []
        var result: [IndexPath: UICollectionViewLayoutAttributes] = [:]
        for attributes in attributes {
            result[attributes.indexPath] = attributes
        }
        return result
    }

    func quillCellForItem(at indexPath: IndexPath) -> UICollectionViewCell? {
        quillCollectionState.realizedCells[indexPath]
    }

    var quillVisibleCells: [UICollectionViewCell] {
        let state = quillCollectionState
        let visibleBounds = bounds
        return state.realizedIndexPaths.compactMap { indexPath in
            guard let cell = state.realizedCells[indexPath],
                  cell.frame.intersects(visibleBounds) || visibleBounds.isEmpty else {
                return nil
            }
            return cell
        }
    }

    var quillSelectedIndexPaths: [IndexPath]? {
        let selected = quillCollectionState.selectedIndexPaths
        return selected.isEmpty ? nil : selected.sorted { lhs, rhs in
            for offset in 0..<max(lhs.count, rhs.count) {
                let lhsValue = offset < lhs.count ? lhs[offset] : -1
                let rhsValue = offset < rhs.count ? rhs[offset] : -1
                if lhsValue != rhsValue {
                    return lhsValue < rhsValue
                }
            }
            return false
        }
    }

    private func quillFallbackItemSize() -> CGSize {
        if let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout,
           flowLayout.itemSize.width > 0,
           flowLayout.itemSize.height > 0 {
            return flowLayout.itemSize
        }
        let width = bounds.width > 0 ? bounds.width : max(frame.width, 44)
        return CGSize(width: width, height: 44)
    }

    // MARK: Item geometry (resolved through the layout object)

    /// Index paths of items whose frames intersect the visible bounds —
    /// real geometry whenever the layout has been prepared.
    public var indexPathsForVisibleItems: [IndexPath] {
        if let attributes = collectionViewLayout.layoutAttributesForElements(in: bounds),
           !attributes.isEmpty {
            return attributes.map { $0.indexPath }
        }

        let state = quillCollectionState
        let visibleBounds = bounds
        return state.realizedIndexPaths.compactMap { indexPath in
            guard let cell = state.realizedCells[indexPath],
                  cell.frame.intersects(visibleBounds) || visibleBounds.isEmpty else {
                return nil
            }
            return indexPath
        }
    }

    /// The item whose frame contains `point` (in content coordinates).
    public func indexPathForItem(at point: CGPoint) -> IndexPath? {
        let everywhere = CGRect(
            x: -CGFloat.greatestFiniteMagnitude / 2,
            y: -CGFloat.greatestFiniteMagnitude / 2,
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if let indexPath = collectionViewLayout.layoutAttributesForElements(in: everywhere)?
            .first(where: { $0.frame.contains(point) })?
            .indexPath {
            return indexPath
        }

        let state = quillCollectionState
        return state.realizedIndexPaths.first { indexPath in
            state.realizedCells[indexPath]?.frame.contains(point) == true
        }
    }

    /// Translates bounds.origin to bring the item's layout frame to the
    /// requested position ("contentOffset IS bounds.origin", see header).
    /// Animation completes instantly — no animation backend.
    public func scrollToItem(at indexPath: IndexPath, at scrollPosition: ScrollPosition, animated: Bool) {
        _ = animated
        let itemFrame: CGRect
        if let attributes = collectionViewLayout.layoutAttributesForItem(at: indexPath) {
            itemFrame = attributes.frame
        } else if let cell = quillCollectionState.realizedCells[indexPath] {
            itemFrame = cell.frame
        } else {
            return
        }
        var origin = bounds.origin

        if scrollPosition.contains(.centeredHorizontally) {
            origin.x = itemFrame.midX - bounds.width / 2
        } else if scrollPosition.contains(.left) {
            origin.x = itemFrame.minX
        } else if scrollPosition.contains(.right) {
            origin.x = itemFrame.maxX - bounds.width
        }

        if scrollPosition.contains(.centeredVertically) {
            origin.y = itemFrame.midY - bounds.height / 2
        } else if scrollPosition.contains(.top) {
            origin.y = itemFrame.minY
        } else if scrollPosition.contains(.bottom) {
            origin.y = itemFrame.maxY - bounds.height
        }

        bounds.origin = origin
    }
}

// MARK: - UICollectionViewCell configuration surface

/// Snapshot of a cell's interaction state handed to
/// configurationUpdateHandler. Minimal faithful model of Apple's struct.
public struct UICellConfigurationState: Sendable {
    public var isSelected: Bool = false
    public var isHighlighted: Bool = false
    public var isFocused: Bool = false
    public init() {}
}

private struct QuillCollectionCellState {
    weak var owner: UICollectionViewCell?
    var configurationUpdateHandler: UICollectionViewCell.ConfigurationUpdateHandler?
    var backgroundView: UIView?
    var selectedBackgroundView: UIView?
}

@MainActor private var quillCollectionCellStates: [ObjectIdentifier: QuillCollectionCellState] = [:]

extension UICollectionViewCell {

    public typealias ConfigurationUpdateHandler = @MainActor (UICollectionViewCell, UICellConfigurationState) -> Void

    private var quillCellState: QuillCollectionCellState {
        get {
            if let state = quillCollectionCellStates[ObjectIdentifier(self)], state.owner === self {
                return state
            }
            return QuillCollectionCellState(owner: self)
        }
        set {
            if quillCollectionCellStates[ObjectIdentifier(self)]?.owner !== self {
                quillCollectionCellStates = quillCollectionCellStates.filter { $0.value.owner != nil }
            }
            var state = newValue
            state.owner = self
            quillCollectionCellStates[ObjectIdentifier(self)] = state
        }
    }

    /// Stored faithfully; with no interaction engine there is no state
    /// change to fire it for, so it is never invoked spontaneously.
    public var configurationUpdateHandler: ConfigurationUpdateHandler? {
        get { quillCellState.configurationUpdateHandler }
        set { quillCellState.configurationUpdateHandler = newValue }
    }

    /// The cell's background chrome view. Stored only (no compositor).
    public var backgroundView: UIView? {
        get { quillCellState.backgroundView }
        set { quillCellState.backgroundView = newValue }
    }

    public var selectedBackgroundView: UIView? {
        get { quillCellState.selectedBackgroundView }
        set { quillCellState.selectedBackgroundView = newValue }
    }
}

// UIBackgroundConfiguration's member surface (clear()/backgroundColor/
// cornerRadius/stroke*) lives in UIButtonExtras.swift — a superset added
// by the button cluster; the copy that sat here was a same-module
// redeclaration.

// MARK: - IndexPath item accessors

// QuillUIKit.swift's IndexPath extension owns `row` / `section`; only the
// UICollectionView-flavored members are added here. The inits store real
// [section, item] indexes (UIKit's outer/inner ordering) — the same shape the
// SignalServiceKit port's internal init(row:section:) writes.
public extension IndexPath {
    /// The item component ([section, item] ordering), 0 when absent.
    var item: Int {
        get { count >= 2 ? self[1] : 0 }
        set { self = IndexPath(item: newValue, section: section) }
    }

    init(item: Int, section: Int) {
        self.init(indexes: [section, item])
    }

    init(row: Int, section: Int) {
        self.init(indexes: [section, row])
    }
}

#endif // !os(iOS)
