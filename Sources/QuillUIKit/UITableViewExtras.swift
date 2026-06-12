//===----------------------------------------------------------------------===//
//
//  UITableViewExtras.swift
//  QuillUIKit — the UITableView family surface for Linux
//
//  The `UITableView` / `UITableViewCell` class bodies live in QuillUIKit.swift
//  (another owner), so everything here is layered on via extensions plus
//  file-scope side tables for stored state (the UIScrollViewExtras.swift
//  pattern: weak `owner` backref guards every read against ObjectIdentifier
//  address reuse; dead entries are swept on write). Types that did NOT exist
//  anywhere are declared fresh at the bottom of this file:
//  UITableViewHeaderFooterView, UIRefreshControl, NSDiffableDataSourceSnapshot
//  and UITableViewDiffableDataSource, and the UITableViewDataSource /
//  UITableViewDelegate protocols.
//
//  Honest Linux semantics (MODEL not engine, like the rest of the module):
//    - No display pass materializes cells, so the recycle pool is honestly
//      empty: `visibleCells` is `[]`, `cellForRow(at:)` is nil, and the
//      reload/insert/delete batch calls are no-ops — the data source object
//      remains the model of record, exactly as it already is on Apple.
//    - `dequeueReusableCell(withIdentifier:for:)` must return a cell, but a
//      registered AnyClass cannot be instantiated dynamically until the cell
//      initializer becomes `required` in the class body (deferred to the
//      QuillUIKit.swift owner), so it returns a fresh base cell. Registration
//      tables are still recorded faithfully for that future.
//    - Selection (`selectRow` / `deselectRow` / `indexPathForSelectedRow`) is
//      a real model: programmatic selection mutates stored index paths and,
//      per Apple's documented behavior, does NOT notify the delegate.
//
//  Inset layering: `contentInset` (table) and `separatorInset` (table + cell)
//  are UIEdgeInsets-typed on Apple, and UIEdgeInsets lives in the UIKit shim
//  module which DEPENDS on this one. Following the `quillLayoutMargins` /
//  `quillContentInset` precedent, the QuillEdgeInsets-typed backings live
//  here (`quillTableContentInset` & co.) and the UIEdgeInsets accessors are
//  layered in Sources/UIKitShim/UITableViewInsets.swift.
//
//  NOT here on purpose (class-body needs deferred to the QuillUIKit.swift
//  owner, since extension members cannot be `open` or overridden):
//    - `open` on UITableView / UITableViewCell (upstream subclasses both);
//    - UITableViewCell `setSelected(_:animated:)` / `setHighlighted(_:animated:)`
//      / `prepareForReuse()` (upstream overrides them);
//    - `required` (+`open`) on `init(style:reuseIdentifier:)`;
//    - the missing `CellStyle` cases (.value1, .value2, .subtitle) — enum
//      cases cannot be added from an extension;
//    - re-parenting UITableView from UIView to UIScrollView so the whole
//      scroll surface (contentOffset, contentSize, …) applies to tables.
//
//===----------------------------------------------------------------------===//

import QuillFoundation

#if !os(iOS)

// MARK: - UITableView option types

extension UITableView {

    /// The overall table appearance, fixed at init time. Stored
    /// configuration — no compositor consumes it on Linux yet.
    public enum Style: Int, Sendable {
        case plain
        case grouped
        case insetGrouped
    }

    /// The animation applied to row/section batch mutations. Stored intent
    /// only: with no animation backend the batch calls complete instantly.
    public enum RowAnimation: Int, Sendable {
        case fade
        case right
        case left
        case top
        case bottom
        case none
        case middle
        case automatic = 100
    }

    /// Where a row should end up after `scrollToRow` / `selectRow`. With no
    /// layout pass producing row geometry, scrolling requests are no-ops.
    public enum ScrollPosition: Int, Sendable {
        case none
        case top
        case middle
        case bottom
    }

    /// Apple's sentinel (-1) telling the table to size rows/headers itself.
    public static let automaticDimension: CGFloat = -1
}

// MARK: - UITableViewCell option types

extension UITableViewCell {

    /// Highlight treatment for selected cells. Stored configuration.
    public enum SelectionStyle: Int, Sendable {
        case none
        case blue
        case gray
        case `default`
    }

    /// The standard accessory rendered at the cell's trailing edge.
    /// Stored configuration.
    public enum AccessoryType: Int, Sendable {
        case none
        case disclosureIndicator
        case detailDisclosureButton
        case checkmark
        case detailButton
    }

    /// The separator drawing style (a UITableView-level setting that Apple
    /// namespaces under UITableViewCell).
    public enum SeparatorStyle: Int, Sendable {
        case none
        case singleLine
        case singleLineEtched
    }

    /// The editing control shown for a row in editing mode.
    public enum EditingStyle: Int, Sendable {
        case none
        case delete
        case insert
    }
}

// MARK: - UITableViewDataSource

/// The table's content callbacks. The two Apple-required methods are genuine
/// requirements; the optional ones are requirements with Apple's documented
/// fallback as a default implementation below, so conformers keep
/// implementing only what they care about (and their implementations stay
/// reachable through the existential, unlike extension-only members).
public protocol UITableViewDataSource: AnyObject {
    @MainActor func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    @MainActor func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell

    @MainActor func numberOfSections(in tableView: UITableView) -> Int
    @MainActor func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
    @MainActor func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
    @MainActor func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
    @MainActor func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool
    @MainActor func sectionIndexTitles(for tableView: UITableView) -> [String]?
    @MainActor func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int
    @MainActor func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
    @MainActor func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath)
}

/// Apple's documented defaults for the optional data source methods.
public extension UITableViewDataSource {
    @MainActor func numberOfSections(in tableView: UITableView) -> Int { 1 }
    @MainActor func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    @MainActor func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
    /// "If this method is not implemented, all rows are assumed editable."
    @MainActor func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { true }
    /// Rows are only reorderable when the data source opts in.
    @MainActor func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { false }
    @MainActor func sectionIndexTitles(for tableView: UITableView) -> [String]? { nil }
    @MainActor func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int { index }
    @MainActor func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {}
    @MainActor func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {}
}

// MARK: - UITableViewDelegate

/// The table's display/selection callbacks. Refines UIScrollViewDelegate as
/// on Apple (`scrollViewDidScroll` is defaulted in QuillUIKit.swift, so
/// conformers are not burdened). Every method is a requirement with Apple's
/// documented fallback below; with no display pass, only upstream code that
/// calls these directly ever invokes them.
public protocol UITableViewDelegate: UIScrollViewDelegate {
    @MainActor func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath)
    @MainActor func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath)
    @MainActor func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int)
    @MainActor func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int)
    @MainActor func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int)
    @MainActor func tableView(_ tableView: UITableView, didEndDisplayingFooterView view: UIView, forSection section: Int)

    @MainActor func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
    @MainActor func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    @MainActor func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat
    @MainActor func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat
    @MainActor func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat
    @MainActor func tableView(_ tableView: UITableView, estimatedHeightForFooterInSection section: Int) -> CGFloat

    @MainActor func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
    @MainActor func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView?
    @MainActor func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath)

    @MainActor func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool
    @MainActor func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath)
    @MainActor func tableView(_ tableView: UITableView, didUnhighlightRowAt indexPath: IndexPath)
    @MainActor func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath?
    @MainActor func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath?
    @MainActor func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    @MainActor func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath)

    @MainActor func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle
    @MainActor func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String?
    @MainActor func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool
    @MainActor func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath)
    @MainActor func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?)
    @MainActor func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath
    @MainActor func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int
}

/// Apple's documented fallback behavior for every delegate method (heights
/// fall back to the table's own height properties, exactly as UIKit does
/// when the delegate does not implement the callback).
public extension UITableViewDelegate {
    @MainActor func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {}
    @MainActor func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {}
    @MainActor func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {}
    @MainActor func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {}
    @MainActor func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int) {}
    @MainActor func tableView(_ tableView: UITableView, didEndDisplayingFooterView view: UIView, forSection section: Int) {}

    @MainActor func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { tableView.rowHeight }
    @MainActor func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { tableView.sectionHeaderHeight }
    @MainActor func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { tableView.sectionFooterHeight }
    @MainActor func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat { tableView.estimatedRowHeight }
    @MainActor func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat { tableView.estimatedSectionHeaderHeight }
    @MainActor func tableView(_ tableView: UITableView, estimatedHeightForFooterInSection section: Int) -> CGFloat { tableView.estimatedSectionFooterHeight }

    @MainActor func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? { nil }
    @MainActor func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? { nil }
    @MainActor func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {}

    @MainActor func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool { true }
    @MainActor func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath) {}
    @MainActor func tableView(_ tableView: UITableView, didUnhighlightRowAt indexPath: IndexPath) {}
    @MainActor func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? { indexPath }
    @MainActor func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? { indexPath }
    @MainActor func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}
    @MainActor func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {}

    @MainActor func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .delete }
    /// nil means "use the system's localized Delete title", as on Apple.
    @MainActor func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? { nil }
    @MainActor func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { true }
    @MainActor func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {}
    @MainActor func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {}
    @MainActor func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath { proposedDestinationIndexPath }
    @MainActor func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int { 0 }
}

// MARK: - UITableView per-instance state side table

/// Everything UITableView needs to remember per instance, with Apple's
/// documented defaults.
private struct QuillTableViewState {
    /// Address-reuse guard — see UIScrollViewExtras.swift.
    weak var owner: UITableView?

    var style: UITableView.Style = .plain
    weak var dataSource: (any UITableViewDataSource)?
    weak var delegate: (any UITableViewDelegate)?

    /// Registration tables, recorded faithfully even though dequeue cannot
    /// instantiate a registered cell class yet (see the file header).
    var registeredCellClasses: [String: AnyClass] = [:]
    var registeredHeaderFooterClasses: [String: AnyClass] = [:]

    /// The selection model. Order is selection order, as on Apple.
    var selectedIndexPaths: [IndexPath] = []

    var separatorStyle: UITableViewCell.SeparatorStyle = .singleLine
    /// nil means "use the system default color"; no renderer consults it yet.
    var separatorColor: UIColor?

    var tableHeaderView: UIView?
    var tableFooterView: UIView?
    var backgroundView: UIView?
    var refreshControl: UIRefreshControl?

    // -1 == UITableView.automaticDimension (spelled literally: the static
    // lives on the @MainActor class, out of reach of this nonisolated
    // struct's default-value expressions).
    var sectionHeaderHeight: CGFloat = -1
    var sectionFooterHeight: CGFloat = -1
    var estimatedRowHeight: CGFloat = -1
    var estimatedSectionHeaderHeight: CGFloat = -1
    var estimatedSectionFooterHeight: CGFloat = -1
    var sectionHeaderTopPadding: CGFloat = -1

    var allowsSelection = true
    var allowsMultipleSelection = false
    var allowsSelectionDuringEditing = false
    var allowsMultipleSelectionDuringEditing = false
    var isEditing = false
    var cellLayoutMarginsFollowReadableWidth = false

    /// QuillEdgeInsets backings for the UIEdgeInsets accessors layered in
    /// the UIKit shim (Sources/UIKitShim/UITableViewInsets.swift).
    var contentInset = QuillEdgeInsets.zero
    /// Apple's documented default separator inset: {0, 15, 0, 0}.
    var separatorInset = QuillEdgeInsets(top: 0, left: 15, bottom: 0, right: 0)
}

@MainActor private var quillTableViewStates: [ObjectIdentifier: QuillTableViewState] = [:]

// MARK: - UITableView surface

extension UITableView {

    /// The instance's state, validated against address reuse on read and
    /// re-stamped with `owner` on write (UIScrollViewExtras.swift pattern).
    private var quillTableState: QuillTableViewState {
        get {
            if let state = quillTableViewStates[ObjectIdentifier(self)], state.owner === self {
                return state
            }
            return QuillTableViewState(owner: self)
        }
        set {
            if quillTableViewStates[ObjectIdentifier(self)]?.owner !== self {
                quillTableViewStates = quillTableViewStates.filter { $0.value.owner != nil }
            }
            var state = newValue
            state.owner = self
            quillTableViewStates[ObjectIdentifier(self)] = state
        }
    }

    // MARK: Creation & fixed configuration

    /// Apple's designated table initializer. (The class body — another
    /// owner — declares no designated inits of its own, so this convenience
    /// init delegates to the inherited `init(frame:)`.)
    public convenience init(frame: CGRect, style: Style) {
        self.init(frame: frame)
        quillTableState.style = style
    }

    /// The style fixed at init time. Read-only, as on Apple.
    public var style: Style { quillTableState.style }

    // MARK: Data source & delegate

    /// The content provider. Weak, as on Apple.
    public var dataSource: (any UITableViewDataSource)? {
        get { quillTableState.dataSource }
        set { quillTableState.dataSource = newValue }
    }

    // The display/selection delegate is the INHERITED UIScrollView.delegate:
    // UITableViewDelegate refines UIScrollViewDelegate, so upstream's
    // `tableView.delegate = self` lands there by upcast (same approach as
    // UICollectionViewExtras). Apple's covariant ObjC redeclaration can't be
    // spelled in Swift without an override-type clash.

    // MARK: Counts (live questions to the data source, as on Apple)

    /// With no data source there is nothing to count — 0, as on Apple.
    public var numberOfSections: Int {
        guard let dataSource = quillTableState.dataSource else { return 0 }
        return dataSource.numberOfSections(in: self)
    }

    public func numberOfRows(inSection section: Int) -> Int {
        guard let dataSource = quillTableState.dataSource else { return 0 }
        return dataSource.tableView(self, numberOfRowsInSection: section)
    }

    // MARK: Registration & dequeueing

    public func register(_ cellClass: AnyClass?, forCellReuseIdentifier identifier: String) {
        if let cellClass {
            quillTableState.registeredCellClasses[identifier] = cellClass
        } else {
            quillTableState.registeredCellClasses.removeValue(forKey: identifier)
        }
    }

    public func register(_ aClass: AnyClass?, forHeaderFooterViewReuseIdentifier identifier: String) {
        if let aClass {
            quillTableState.registeredHeaderFooterClasses[identifier] = aClass
        } else {
            quillTableState.registeredHeaderFooterClasses.removeValue(forKey: identifier)
        }
    }

    /// MODEL HONESTY: the recycle pool is empty (no cell is ever displayed),
    /// and a registered class cannot be instantiated dynamically until the
    /// cell initializer is `required` (class-body need, see file header) —
    /// so a registered identifier yields a fresh BASE cell and an
    /// unregistered one yields nil, mirroring Apple's nil-for-unregistered
    /// contract.
    public func dequeueReusableCell(withIdentifier identifier: String) -> UITableViewCell? {
        guard quillTableState.registeredCellClasses[identifier] != nil else { return nil }
        return UITableViewCell(style: .default, reuseIdentifier: identifier)
    }

    /// The registration-asserting variant. Returns a fresh base cell (see
    /// above); Apple would trap on an unregistered identifier, but with no
    /// recycle pool a fresh cell is the honest total answer here.
    public func dequeueReusableCell(withIdentifier identifier: String, for indexPath: IndexPath) -> UITableViewCell {
        UITableViewCell(style: .default, reuseIdentifier: identifier)
    }

    /// Base instances only, same instantiation limit as cells (though the
    /// header/footer class declared in this file COULD be instantiated, a
    /// registered upstream subclass cannot, so the base answer is uniform).
    public func dequeueReusableHeaderFooterView(withIdentifier identifier: String) -> UITableViewHeaderFooterView? {
        guard quillTableState.registeredHeaderFooterClasses[identifier] != nil else { return nil }
        return UITableViewHeaderFooterView(reuseIdentifier: identifier)
    }

    // MARK: Reload & batch mutations

    /// MODEL HONESTY: nothing materializes cells on Linux, so reloading is
    /// a pure bookkeeping event. It does clear the selection, as on Apple.
    public func reloadData() {
        quillTableState.selectedIndexPaths = []
    }

    public func reloadRows(at indexPaths: [IndexPath], with animation: RowAnimation) {}
    public func insertRows(at indexPaths: [IndexPath], with animation: RowAnimation) {}
    public func deleteRows(at indexPaths: [IndexPath], with animation: RowAnimation) {}
    public func insertSections(_ sections: IndexSet, with animation: RowAnimation) {}
    public func deleteSections(_ sections: IndexSet, with animation: RowAnimation) {}
    public func reloadSections(_ sections: IndexSet, with animation: RowAnimation) {}
    public func moveRow(at indexPath: IndexPath, to newIndexPath: IndexPath) {}
    public func moveSection(_ section: Int, toSection newSection: Int) {}

    public func beginUpdates() {}
    public func endUpdates() {}

    /// Runs the mutation closure and completes synchronously — no animation
    /// backend, same instant-completion rule as the rest of the module.
    public func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        updates?()
        completion?(true)
    }

    // MARK: Cell & geometry lookups (honestly empty — nothing displays)

    public var visibleCells: [UITableViewCell] { [] }
    public var indexPathsForVisibleRows: [IndexPath]? { [] }
    public func cellForRow(at indexPath: IndexPath) -> UITableViewCell? { nil }
    public func indexPath(for cell: UITableViewCell) -> IndexPath? { nil }
    public func indexPathForRow(at point: CGPoint) -> IndexPath? { nil }
    public func indexPathsForRows(in rect: CGRect) -> [IndexPath]? { nil }
    public func headerView(forSection section: Int) -> UITableViewHeaderFooterView? { nil }
    public func footerView(forSection section: Int) -> UITableViewHeaderFooterView? { nil }
    public func rectForRow(at indexPath: IndexPath) -> CGRect { .zero }
    public func rect(forSection section: Int) -> CGRect { .zero }

    // MARK: Scrolling (no row geometry exists to scroll to)

    public func scrollToRow(at indexPath: IndexPath, at scrollPosition: ScrollPosition, animated: Bool) {}
    public func scrollToNearestSelectedRow(at scrollPosition: ScrollPosition, animated: Bool) {}

    // MARK: Selection (a real model; mutations don't notify the delegate,
    // exactly as Apple documents for the programmatic calls)

    /// The first selected row, or nil.
    public var indexPathForSelectedRow: IndexPath? {
        quillTableState.selectedIndexPaths.first
    }

    /// All selected rows, or nil when none — Apple returns nil, not [].
    public var indexPathsForSelectedRows: [IndexPath]? {
        let selected = quillTableState.selectedIndexPaths
        return selected.isEmpty ? nil : selected
    }

    /// Selects a row (replacing the selection unless multiple selection is
    /// on); nil clears the selection. Does not notify the delegate.
    public func selectRow(at indexPath: IndexPath?, animated: Bool, scrollPosition: ScrollPosition) {
        guard let indexPath else {
            quillTableState.selectedIndexPaths = []
            return
        }
        if allowsMultipleSelection {
            if !quillTableState.selectedIndexPaths.contains(indexPath) {
                quillTableState.selectedIndexPaths.append(indexPath)
            }
        } else {
            quillTableState.selectedIndexPaths = [indexPath]
        }
    }

    /// Deselects a row. Does not notify the delegate, as on Apple.
    public func deselectRow(at indexPath: IndexPath, animated: Bool) {
        quillTableState.selectedIndexPaths.removeAll { $0 == indexPath }
    }

    public var allowsSelection: Bool {
        get { quillTableState.allowsSelection }
        set { quillTableState.allowsSelection = newValue }
    }

    public var allowsMultipleSelection: Bool {
        get { quillTableState.allowsMultipleSelection }
        set { quillTableState.allowsMultipleSelection = newValue }
    }

    public var allowsSelectionDuringEditing: Bool {
        get { quillTableState.allowsSelectionDuringEditing }
        set { quillTableState.allowsSelectionDuringEditing = newValue }
    }

    public var allowsMultipleSelectionDuringEditing: Bool {
        get { quillTableState.allowsMultipleSelectionDuringEditing }
        set { quillTableState.allowsMultipleSelectionDuringEditing = newValue }
    }

    // MARK: Editing

    public var isEditing: Bool {
        get { quillTableState.isEditing }
        set { quillTableState.isEditing = newValue }
    }

    /// Instant, like every animated variant in the module.
    public func setEditing(_ editing: Bool, animated: Bool) {
        quillTableState.isEditing = editing
    }

    // MARK: Appearance & chrome (faithfully stored Apple defaults)

    public var separatorStyle: UITableViewCell.SeparatorStyle {
        get { quillTableState.separatorStyle }
        set { quillTableState.separatorStyle = newValue }
    }

    /// nil = system default; no renderer draws separators on Linux.
    public var separatorColor: UIColor? {
        get { quillTableState.separatorColor }
        set { quillTableState.separatorColor = newValue }
    }

    /// Stored accessory views. MODEL HONESTY: no layout pass positions them
    /// (or adds them to the hierarchy) yet, so this is pure storage.
    public var tableHeaderView: UIView? {
        get { quillTableState.tableHeaderView }
        set { quillTableState.tableHeaderView = newValue }
    }

    public var tableFooterView: UIView? {
        get { quillTableState.tableFooterView }
        set { quillTableState.tableFooterView = newValue }
    }

    public var backgroundView: UIView? {
        get { quillTableState.backgroundView }
        set { quillTableState.backgroundView = newValue }
    }

    /// The pull-to-refresh control. On Apple this lives on UIScrollView;
    /// it sits here until UITableView is re-parented (file header). The
    /// control is attached as a subview, as UIKit does.
    public var refreshControl: UIRefreshControl? {
        get { quillTableState.refreshControl }
        set {
            if let old = quillTableState.refreshControl, old.superview === self {
                old.removeFromSuperview()
            }
            quillTableState.refreshControl = newValue
            if let newValue {
                addSubview(newValue)
            }
        }
    }

    // MARK: Heights (rowHeight itself lives in the class body)

    public var sectionHeaderHeight: CGFloat {
        get { quillTableState.sectionHeaderHeight }
        set { quillTableState.sectionHeaderHeight = newValue }
    }

    public var sectionFooterHeight: CGFloat {
        get { quillTableState.sectionFooterHeight }
        set { quillTableState.sectionFooterHeight = newValue }
    }

    public var estimatedRowHeight: CGFloat {
        get { quillTableState.estimatedRowHeight }
        set { quillTableState.estimatedRowHeight = newValue }
    }

    public var estimatedSectionHeaderHeight: CGFloat {
        get { quillTableState.estimatedSectionHeaderHeight }
        set { quillTableState.estimatedSectionHeaderHeight = newValue }
    }

    public var estimatedSectionFooterHeight: CGFloat {
        get { quillTableState.estimatedSectionFooterHeight }
        set { quillTableState.estimatedSectionFooterHeight = newValue }
    }

    /// iOS 15's extra padding above section headers.
    public var sectionHeaderTopPadding: CGFloat {
        get { quillTableState.sectionHeaderTopPadding }
        set { quillTableState.sectionHeaderTopPadding = newValue }
    }

    public var cellLayoutMarginsFollowReadableWidth: Bool {
        get { quillTableState.cellLayoutMarginsFollowReadableWidth }
        set { quillTableState.cellLayoutMarginsFollowReadableWidth = newValue }
    }

    // MARK: Inset backings (UIEdgeInsets accessors live in the UIKit shim)

    /// Backing store for `contentInset` (UIKitShim/UITableViewInsets.swift).
    /// Distinctly named so it cannot collide with UIScrollView's
    /// `quillContentInset` if UITableView is later re-parented.
    public var quillTableContentInset: QuillEdgeInsets {
        get { quillTableState.contentInset }
        set { quillTableState.contentInset = newValue }
    }

    /// Backing store for the table-wide `separatorInset`.
    public var quillTableSeparatorInset: QuillEdgeInsets {
        get { quillTableState.separatorInset }
        set { quillTableState.separatorInset = newValue }
    }
}

// MARK: - UITableViewCell per-instance state side table

/// Per-cell stored state with Apple's documented defaults. (`textLabel` /
/// `detailTextLabel` / `imageView` live in the class body — another owner.)
private struct QuillTableCellState {
    weak var owner: UITableViewCell?

    /// Lazily created by the `contentView` accessor.
    var contentView: UIView?

    var selectionStyle: UITableViewCell.SelectionStyle = .default
    var accessoryType: UITableViewCell.AccessoryType = .none
    var editingAccessoryType: UITableViewCell.AccessoryType = .none
    var accessoryView: UIView?
    var backgroundView: UIView?
    var selectedBackgroundView: UIView?
    var multipleSelectionBackgroundView: UIView?
    var isSelected = false
    var isHighlighted = false

    /// QuillEdgeInsets backing for the shim-layered `separatorInset`;
    /// Apple's default cell separator inset is {0, 15, 0, 0}.
    var separatorInset = QuillEdgeInsets(top: 0, left: 15, bottom: 0, right: 0)
}

@MainActor private var quillTableCellStates: [ObjectIdentifier: QuillTableCellState] = [:]

// MARK: - UITableViewCell surface

extension UITableViewCell {

    private var quillCellState: QuillTableCellState {
        get {
            if let state = quillTableCellStates[ObjectIdentifier(self)], state.owner === self {
                return state
            }
            return QuillTableCellState(owner: self)
        }
        set {
            if quillTableCellStates[ObjectIdentifier(self)]?.owner !== self {
                quillTableCellStates = quillTableCellStates.filter { $0.value.owner != nil }
            }
            var state = newValue
            state.owner = self
            quillTableCellStates[ObjectIdentifier(self)] = state
        }
    }

    /// The container for cell content. Created lazily and attached as a
    /// subview on first access — a real hierarchy mutation, so constraints
    /// and geometry against it behave (Apple creates it eagerly in init,
    /// which lives in the class body, another owner).
    public var contentView: UIView {
        if let existing = quillCellState.contentView {
            return existing
        }
        let view = UIView()
        addSubview(view)
        quillCellState.contentView = view
        return view
    }

    /// Highlight treatment when selected. Apple's default: `.default`.
    public var selectionStyle: SelectionStyle {
        get { quillCellState.selectionStyle }
        set { quillCellState.selectionStyle = newValue }
    }

    /// The trailing accessory. Apple's default: `.none`.
    public var accessoryType: AccessoryType {
        get { quillCellState.accessoryType }
        set { quillCellState.accessoryType = newValue }
    }

    /// The trailing accessory while editing. Apple's default: `.none`.
    public var editingAccessoryType: AccessoryType {
        get { quillCellState.editingAccessoryType }
        set { quillCellState.editingAccessoryType = newValue }
    }

    /// A custom accessory view (wins over `accessoryType` on Apple). Pure
    /// storage — no layout pass places it yet.
    public var accessoryView: UIView? {
        get { quillCellState.accessoryView }
        set { quillCellState.accessoryView = newValue }
    }

    /// Stored background views; nothing composites them on Linux yet.
    public var backgroundView: UIView? {
        get { quillCellState.backgroundView }
        set { quillCellState.backgroundView = newValue }
    }

    public var selectedBackgroundView: UIView? {
        get { quillCellState.selectedBackgroundView }
        set { quillCellState.selectedBackgroundView = newValue }
    }

    public var multipleSelectionBackgroundView: UIView? {
        get { quillCellState.multipleSelectionBackgroundView }
        set { quillCellState.multipleSelectionBackgroundView = newValue }
    }

    /// Selection flags. NOTE: `setSelected(_:animated:)` /
    /// `setHighlighted(_:animated:)` are deliberately NOT shimmed here —
    /// upstream overrides them, so they must be `open` in the class body
    /// (deferred to the QuillUIKit.swift owner; see the file header).
    public var isSelected: Bool {
        get { quillCellState.isSelected }
        set { quillCellState.isSelected = newValue }
    }

    public var isHighlighted: Bool {
        get { quillCellState.isHighlighted }
        set { quillCellState.isHighlighted = newValue }
    }

    /// Backing store for the shim-layered per-cell `separatorInset`
    /// (UIKitShim/UITableViewInsets.swift).
    public var quillCellSeparatorInset: QuillEdgeInsets {
        get { quillCellState.separatorInset }
        set { quillCellState.separatorInset = newValue }
    }
}

// MARK: - UITableViewHeaderFooterView

/// The reusable section header/footer. Declared fresh here (it existed
/// nowhere in the shim), so unlike the cell it CAN be open and own its
/// overridable members directly.
@MainActor open class UITableViewHeaderFooterView: UIView {

    /// The reuse identifier passed at init, read-only as on Apple.
    public private(set) var reuseIdentifier: String?

    /// The content container, attached as a subview at init, as on Apple.
    public let contentView = UIView()

    /// Settable optional labels — the same honest simplification as the
    /// cell's `textLabel` in the class body (Apple lazily creates these).
    public var textLabel: UILabel?
    public var detailTextLabel: UILabel?

    /// Stored background view; nothing composites it on Linux yet.
    public var backgroundView: UIView?

    public init(reuseIdentifier: String?) {
        self.reuseIdentifier = reuseIdentifier
        super.init()
        addSubview(contentView)
    }

    public override init() {
        super.init()
        addSubview(contentView)
    }

    /// Called when a view is about to be recycled. With no recycle pool on
    /// Linux nothing calls it, but subclasses override it, so it must exist
    /// (and be open) here.
    open func prepareForReuse() {}
}

// MARK: - UIRefreshControl

/// Pull-to-refresh. On Apple the control attaches to a UIScrollView and
/// fires `.valueChanged` on pull; with no event backend the state machine
/// only moves when upstream calls begin/end programmatically. Target-action
/// registration comes from UIControl (UITextInput.swift's side table).
@MainActor open class UIRefreshControl: UIControl {

    /// Whether a refresh is in progress. Read-only, as on Apple.
    public private(set) var isRefreshing = false

    /// The styled title under the spinner. Stored configuration.
    public var attributedTitle: NSAttributedString?

    /// Programmatic start: flips state only — Apple also avoids sending
    /// `.valueChanged` for the programmatic call.
    open func beginRefreshing() {
        isRefreshing = true
    }

    open func endRefreshing() {
        isRefreshing = false
    }
}

// MARK: - UITableViewController

/// A view controller that manages a table view. Declared fresh here (it
/// existed nowhere in the shim), so like UITableViewHeaderFooterView it CAN
/// be open and own its overridable members directly. Apple's wiring is kept:
/// the table is created at init with the requested style, `self` becomes its
/// data source and delegate, and `loadView()` installs the table as the
/// controller's view.
///
/// The data-source methods subclasses override (TablePreviewViewController
/// overrides the row count and cell vendor) are declared in the CLASS BODY,
/// not satisfied via the protocol-extension defaults — extension members
/// cannot be overridden, so they must be `open` funcs here.
@MainActor open class UITableViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    /// The managed table. Force-unwrapped optional, as on Apple.
    open var tableView: UITableView!

    /// Apple's default is true (selection clears on appearance via the
    /// transition coordinator). Stored faithfully; with no transitions on
    /// Linux nothing consumes it yet.
    open var clearsSelectionOnViewWillAppear: Bool = true

    /// Designated, as on Apple. (`super.init()` is NSObject's initializer,
    /// inherited by UIViewController, which declares none of its own; if the
    /// class body there ever gains Apple's `init(nibName:bundle:)`, this call
    /// becomes `super.init(nibName: nil, bundle: nil)`.)
    public init(style: UITableView.Style) {
        super.init()
        let tableView = UITableView(frame: .zero, style: style)
        tableView.dataSource = self
        tableView.delegate = self
        self.tableView = tableView
    }

    /// The controller's view IS the table view, as on Apple.
    open override func loadView() {
        view = tableView
    }

    // MARK: UITableViewDataSource (class-body so subclasses can override)

    /// Apple's base implementation reports a single section.
    open func numberOfSections(in tableView: UITableView) -> Int { 1 }

    /// Apple's base implementation reports no rows.
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }

    /// Abstract on Apple (the base raises if a row is ever requested without
    /// an override). With no display pass on Linux nothing should call it;
    /// a fresh base cell keeps the model honest without trapping.
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        UITableViewCell(style: .default, reuseIdentifier: nil)
    }
}

// MARK: - NSDiffableDataSourceSnapshot

/// The diffable data source's value-type model. Unlike the display-side
/// stubs above this is PURE model, so it is implemented for real: ordered
/// sections, ordered items per section, and the reload/reconfigure marks.
public struct NSDiffableDataSourceSnapshot<SectionIdentifierType: Hashable, ItemIdentifierType: Hashable> {

    /// Section order, and items per section (parallel storage; sections are
    /// unique by Hashable identity, as Apple requires).
    private var sectionOrder: [SectionIdentifierType] = []
    private var itemsBySection: [SectionIdentifierType: [ItemIdentifierType]] = [:]

    /// Identifiers marked for reload/reconfigure since the last apply —
    /// faithfully recorded even though no view consumes them yet.
    public private(set) var reloadedItemIdentifiers: [ItemIdentifierType] = []
    public private(set) var reconfiguredItemIdentifiers: [ItemIdentifierType] = []
    public private(set) var reloadedSectionIdentifiers: [SectionIdentifierType] = []

    public init() {}

    // MARK: Queries

    public var numberOfSections: Int { sectionOrder.count }

    public var numberOfItems: Int {
        sectionOrder.reduce(0) { $0 + (itemsBySection[$1]?.count ?? 0) }
    }

    public var sectionIdentifiers: [SectionIdentifierType] { sectionOrder }

    public var itemIdentifiers: [ItemIdentifierType] {
        sectionOrder.flatMap { itemsBySection[$0] ?? [] }
    }

    public func numberOfItems(inSection identifier: SectionIdentifierType) -> Int {
        itemsBySection[identifier]?.count ?? 0
    }

    public func itemIdentifiers(inSection identifier: SectionIdentifierType) -> [ItemIdentifierType] {
        itemsBySection[identifier] ?? []
    }

    public func sectionIdentifier(containingItem identifier: ItemIdentifierType) -> SectionIdentifierType? {
        sectionOrder.first { itemsBySection[$0]?.contains(identifier) == true }
    }

    /// The item's absolute position across all sections, as on Apple.
    public func indexOfItem(_ identifier: ItemIdentifierType) -> Int? {
        var offset = 0
        for section in sectionOrder {
            let items = itemsBySection[section] ?? []
            if let index = items.firstIndex(of: identifier) {
                return offset + index
            }
            offset += items.count
        }
        return nil
    }

    public func indexOfSection(_ identifier: SectionIdentifierType) -> Int? {
        sectionOrder.firstIndex(of: identifier)
    }

    // MARK: Section mutations

    public mutating func appendSections(_ identifiers: [SectionIdentifierType]) {
        for identifier in identifiers where !sectionOrder.contains(identifier) {
            sectionOrder.append(identifier)
            itemsBySection[identifier] = []
        }
    }

    public mutating func insertSections(_ identifiers: [SectionIdentifierType], beforeSection toIdentifier: SectionIdentifierType) {
        insertSections(identifiers, at: sectionOrder.firstIndex(of: toIdentifier))
    }

    public mutating func insertSections(_ identifiers: [SectionIdentifierType], afterSection toIdentifier: SectionIdentifierType) {
        insertSections(identifiers, at: sectionOrder.firstIndex(of: toIdentifier).map { $0 + 1 })
    }

    /// Apple traps when the anchor section is missing; the shim's quiet
    /// equivalent is to drop the insertion.
    private mutating func insertSections(_ identifiers: [SectionIdentifierType], at index: Int?) {
        guard var index else { return }
        for identifier in identifiers where !sectionOrder.contains(identifier) {
            sectionOrder.insert(identifier, at: index)
            itemsBySection[identifier] = []
            index += 1
        }
    }

    public mutating func deleteSections(_ identifiers: [SectionIdentifierType]) {
        for identifier in identifiers {
            sectionOrder.removeAll { $0 == identifier }
            itemsBySection.removeValue(forKey: identifier)
        }
    }

    // MARK: Item mutations

    /// nil section = the last section, as on Apple (which traps when there
    /// are no sections; the shim quietly drops the append instead).
    public mutating func appendItems(_ identifiers: [ItemIdentifierType], toSection sectionIdentifier: SectionIdentifierType? = nil) {
        guard let section = sectionIdentifier ?? sectionOrder.last else { return }
        guard sectionOrder.contains(section) else { return }
        itemsBySection[section, default: []].append(contentsOf: identifiers)
    }

    public mutating func insertItems(_ identifiers: [ItemIdentifierType], beforeItem beforeIdentifier: ItemIdentifierType) {
        insertItems(identifiers, nextTo: beforeIdentifier, offset: 0)
    }

    public mutating func insertItems(_ identifiers: [ItemIdentifierType], afterItem afterIdentifier: ItemIdentifierType) {
        insertItems(identifiers, nextTo: afterIdentifier, offset: 1)
    }

    private mutating func insertItems(_ identifiers: [ItemIdentifierType], nextTo anchor: ItemIdentifierType, offset: Int) {
        guard let section = sectionIdentifier(containingItem: anchor),
              let anchorIndex = itemsBySection[section]?.firstIndex(of: anchor) else { return }
        itemsBySection[section]?.insert(contentsOf: identifiers, at: anchorIndex + offset)
    }

    public mutating func deleteItems(_ identifiers: [ItemIdentifierType]) {
        for section in sectionOrder {
            itemsBySection[section]?.removeAll { identifiers.contains($0) }
        }
    }

    public mutating func deleteAllItems() {
        for section in sectionOrder {
            itemsBySection[section] = []
        }
    }

    // MARK: Reload marks

    public mutating func reloadItems(_ identifiers: [ItemIdentifierType]) {
        reloadedItemIdentifiers.append(contentsOf: identifiers)
    }

    public mutating func reconfigureItems(_ identifiers: [ItemIdentifierType]) {
        reconfiguredItemIdentifiers.append(contentsOf: identifiers)
    }

    public mutating func reloadSections(_ identifiers: [SectionIdentifierType]) {
        reloadedSectionIdentifiers.append(contentsOf: identifiers)
    }
}

// MARK: - UITableViewDiffableDataSource

/// The snapshot-driven data source. The snapshot bookkeeping is real; the
/// display side bottoms out in `reloadData()`, which is honest bookkeeping
/// on Linux (see above). Data source methods are `open` because upstream
/// subclasses (e.g. SignalUI's OWSTableViewDiffableDataSource) override
/// them — they can be, since this class is declared in this file.
@MainActor
open class UITableViewDiffableDataSource<SectionIdentifierType: Hashable, ItemIdentifierType: Hashable>: NSObject, UITableViewDataSource {

    public typealias CellProvider = (_ tableView: UITableView, _ indexPath: IndexPath, _ itemIdentifier: ItemIdentifierType) -> UITableViewCell?

    private let cellProvider: CellProvider
    private weak var tableView: UITableView?
    private var currentSnapshot = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()

    /// The animation used when applying snapshot differences. Stored
    /// intent — applies are instant on Linux.
    public var defaultRowAnimation: UITableView.RowAnimation = .automatic

    /// Installs itself as the table's data source, as on Apple (the table's
    /// reference is weak, so the caller keeps owning the data source).
    public init(tableView: UITableView, cellProvider: @escaping CellProvider) {
        self.cellProvider = cellProvider
        self.tableView = tableView
        super.init()
        tableView.dataSource = self
    }

    // MARK: Snapshots

    /// A copy of the current snapshot (value semantics make this Apple's
    /// "safe to mutate and re-apply" contract for free).
    open func snapshot() -> NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> {
        currentSnapshot
    }

    /// Replaces the model and reloads. Instant completion — there is no
    /// diff animation to wait for.
    open func apply(
        _ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>,
        animatingDifferences: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        currentSnapshot = snapshot
        tableView?.reloadData()
        completion?()
    }

    /// iOS 15's non-diffing apply: identical here, where every apply is
    /// already a straight reload.
    open func applySnapshotUsingReloadData(
        _ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>,
        completion: (() -> Void)? = nil
    ) {
        currentSnapshot = snapshot
        tableView?.reloadData()
        completion?()
    }

    // MARK: Identifier <-> index path mapping
    //
    // NOTE: `IndexPath.row` / `.section` are placeholder zeros in
    // QuillUIKit.swift (another owner) — these methods are written against
    // the real accessors so they become correct the moment those are.

    open func itemIdentifier(for indexPath: IndexPath) -> ItemIdentifierType? {
        let sections = currentSnapshot.sectionIdentifiers
        guard indexPath.section >= 0, indexPath.section < sections.count else { return nil }
        let items = currentSnapshot.itemIdentifiers(inSection: sections[indexPath.section])
        guard indexPath.row >= 0, indexPath.row < items.count else { return nil }
        return items[indexPath.row]
    }

    open func indexPath(for itemIdentifier: ItemIdentifierType) -> IndexPath? {
        for (sectionIndex, section) in currentSnapshot.sectionIdentifiers.enumerated() {
            if let rowIndex = currentSnapshot.itemIdentifiers(inSection: section).firstIndex(of: itemIdentifier) {
                // Built with the Foundation initializer because the
                // UIKit-flavored IndexPath(row:section:) is not shimmed yet.
                return IndexPath(indexes: [sectionIndex, rowIndex])
            }
        }
        return nil
    }

    /// iOS 15 convenience: the section identifier at an index.
    open func sectionIdentifier(for index: Int) -> SectionIdentifierType? {
        let sections = currentSnapshot.sectionIdentifiers
        guard index >= 0, index < sections.count else { return nil }
        return sections[index]
    }

    // MARK: UITableViewDataSource

    open func numberOfSections(in tableView: UITableView) -> Int {
        currentSnapshot.numberOfSections
    }

    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sections = currentSnapshot.sectionIdentifiers
        guard section >= 0, section < sections.count else { return 0 }
        return currentSnapshot.numberOfItems(inSection: sections[section])
    }

    /// Falls back to a fresh base cell when the provider declines — Apple
    /// traps there, but a total answer keeps the un-displayed model honest.
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = itemIdentifier(for: indexPath),
              let cell = cellProvider(tableView, indexPath, item) else {
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }
        return cell
    }

    open func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    open func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
    /// Apple's diffable default: rows are not editable unless a subclass
    /// says so.
    open func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { false }
    open func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { false }
    open func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {}
}

#endif // !os(iOS)
