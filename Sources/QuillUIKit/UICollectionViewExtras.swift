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
//    - There is no render/event engine, so nothing ever *drives* the data
//      source: numberOfSections / numberOfItems(inSection:) consult the
//      dataSource faithfully on demand, but cellForItemAt is only executed
//      if upstream code calls it directly.
//    - dequeueReusableCell / dequeueReusableSupplementaryView return fresh
//      base-class instances. Constructing the *registered subclass* from its
//      AnyClass metatype would need a `required` initializer, which cannot
//      be imposed on UIView without breaking every upstream
//      `override init(frame:)` (see QuillAppKit's QuillReusableView note —
//      the same trade-off, resolved the same way). Upstream dequeue paths
//      are only reachable from a layout/render pass that does not exist on
//      Linux yet, so the dishonesty is dormant; the registration tables are
//      still recorded faithfully for a future engine.
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

    private init(indexPath: IndexPath, elementKind: String?) {
        self.indexPath = indexPath
        self.representedElementKind = elementKind
        super.init()
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

    /// Invalidation is bookkeeping-only on Linux (no layout pass to
    /// re-schedule); subclasses clear their caches around the super call.
    open func invalidateLayout() {}
    open func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) { _ = context }

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
}

// MARK: - UICollectionReusableView

/// Base class for supplementary views (section headers/footers).
@MainActor open class UICollectionReusableView: UIView {

    public override init(frame: CGRect) { super.init(frame: frame) }

    /// UIView.init() is designated, so a parameterless convenience must be
    /// an override; subclasses that override init(frame:) (StickerPicker's
    /// header view) inherit it, keeping `HeaderView()` call sites working.
    public convenience init() { self.init(frame: .zero) }

    open func prepareForReuse() {}
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

    /// Registration tables: reuse identifier → registered class. Recorded
    /// faithfully even though dequeue cannot construct arbitrary subclasses
    /// (see file header).
    var cellClasses: [String: AnyClass] = [:]
    /// element kind → (reuse identifier → registered class)
    var supplementaryClasses: [String: [String: AnyClass]] = [:]
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
    /// registered subclass cannot be constructed from its metatype). Only
    /// reachable when upstream drives its own data-source methods.
    public func dequeueReusableCell(withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UICollectionViewCell {
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

    /// Item-level reload. With counts answered live off the dataSource and
    /// no render pass caching cells, there is no stale state to refresh.
    public func reloadItems(at indexPaths: [IndexPath]) {
        _ = indexPaths
    }

    // MARK: Item geometry (resolved through the layout object)

    /// Index paths of items whose frames intersect the visible bounds —
    /// real geometry whenever the layout has been prepared.
    public var indexPathsForVisibleItems: [IndexPath] {
        collectionViewLayout.layoutAttributesForElements(in: bounds)?.map { $0.indexPath } ?? []
    }

    /// The item whose frame contains `point` (in content coordinates).
    public func indexPathForItem(at point: CGPoint) -> IndexPath? {
        let everywhere = CGRect(
            x: -CGFloat.greatestFiniteMagnitude / 2,
            y: -CGFloat.greatestFiniteMagnitude / 2,
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        return collectionViewLayout.layoutAttributesForElements(in: everywhere)?
            .first { $0.frame.contains(point) }?
            .indexPath
    }

    /// Translates bounds.origin to bring the item's layout frame to the
    /// requested position ("contentOffset IS bounds.origin", see header).
    /// Animation completes instantly — no animation backend.
    public func scrollToItem(at indexPath: IndexPath, at scrollPosition: ScrollPosition, animated: Bool) {
        _ = animated
        guard let attributes = collectionViewLayout.layoutAttributesForItem(at: indexPath) else { return }
        let itemFrame = attributes.frame
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
        count >= 2 ? self[1] : 0
    }

    init(item: Int, section: Int) {
        self.init(indexes: [section, item])
    }

    init(row: Int, section: Int) {
        self.init(indexes: [section, row])
    }
}

#endif // !os(iOS)
