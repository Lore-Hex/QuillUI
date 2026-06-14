// QuillUIKit · UIStackView
// ========================
// UIStackView shadow for platforms without Apple's UIKit. Upstream UIKit
// code (SignalUI's ActionSheetController, AttachmentApprovalToolbar, …)
// builds its chrome out of stack views: it constructs them, mutates the
// arranged-subview list, and tunes axis/alignment/distribution/spacing.
//
// Honest Linux semantics: a stack view here is a faithful STATE MODEL, not
// a layout engine. There is no compositor on Linux yet, so nothing reads
// axis/alignment/distribution/spacing to position children — the properties
// store exactly what the caller set (a future native layout pass can consume
// them). What IS functional is the arranged-subview bookkeeping, which keeps
// UIKit's documented invariants:
//   - arrangedSubviews is always a subset of subviews: add/insert also
//     addSubview the view.
//   - removeArrangedSubview removes only the arrangement; the view remains
//     a subview until the caller invokes removeFromSuperview (the pattern
//     ActionSheetController.createHeader uses).
//   - A view removed from the view hierarchy by ANY path (e.g. a direct
//     removeFromSuperview) drops out of arrangedSubviews, mirroring UIKit's
//     automatic un-arrangement. Modeled by filtering out entries whose
//     superview is no longer the stack.

import QuillFoundation
import QuillKit

#if !os(iOS)

@MainActor open class UIStackView: UIView {

    // MARK: - Alignment / Distribution

    /// UIStackView.Alignment. Raw values match UIKit's ObjC enum, where
    /// `top` aliases `leading` and `bottom` aliases `trailing` (the
    /// perpendicular attribute named per-axis) — hence static lets, exactly
    /// how the overlapping members import into Swift on iOS.
    public enum Alignment: Int, Sendable {
        case fill = 0
        case leading = 1
        case firstBaseline = 2
        case center = 3
        case trailing = 4
        case lastBaseline = 5

        /// Vertical-axis spelling of `.leading` (same raw value, as in UIKit).
        public static let top: Alignment = .leading
        /// Vertical-axis spelling of `.trailing` (same raw value, as in UIKit).
        public static let bottom: Alignment = .trailing
    }

    /// UIStackView.Distribution. Raw values match UIKit's ObjC enum.
    public enum Distribution: Int, Sendable {
        case fill = 0
        case fillEqually = 1
        case fillProportionally = 2
        case equalSpacing = 3
        case equalCentering = 4
    }

    // MARK: - Spacing sentinels

    /// Sentinel "no custom spacing — use the stack's `spacing`" value.
    /// Apple documents the constant's identity, not its numeric value;
    /// `customSpacing(after:)` returns it when no custom spacing is set.
    public static let spacingUseDefault: CGFloat = .greatestFiniteMagnitude
    /// Sentinel "use the system-defined spacing" value. Stored verbatim like
    /// any other spacing; no layout pass interprets it on Linux yet.
    public static let spacingUseSystem: CGFloat = .greatestFiniteMagnitude - 1

    // MARK: - Configuration (stored faithfully; inert on Linux — see header)

    open var axis: NSLayoutConstraint.Axis = .horizontal
    open var alignment: Alignment = .fill
    open var distribution: Distribution = .fill
    open var spacing: CGFloat = 0
    open var isLayoutMarginsRelativeArrangement: Bool = false

    // MARK: - Init

    public init(arrangedSubviews views: [UIView]) {
        super.init(frame: .zero)
        for view in views {
            addArrangedSubview(view)
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    // Own designated inits suppress inheritance of UIView's
    // required init?(coder:); restate it (an empty arrangement).
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Arranged subviews

    /// Insertion-ordered arrangement. Entries whose view has left the view
    /// hierarchy are lazily purged (UIKit drops a view from arrangedSubviews
    /// the moment removeFromSuperview runs; without a removal hook on UIView
    /// we reproduce that by checking `superview === self` on access).
    private var _arrangedSubviews: [UIView] = []

    /// Custom inter-item spacing, keyed by arranged-subview identity. Keys
    /// never outlive arrangement (purged alongside `_arrangedSubviews`), so
    /// no stale ObjectIdentifier can collide with a later allocation.
    private var customSpacingAfterView: [ObjectIdentifier: CGFloat] = [:]

    open var arrangedSubviews: [UIView] {
        purgeStaleArrangedState()
        return _arrangedSubviews
    }

    open func addArrangedSubview(_ view: UIView) {
        purgeStaleArrangedState()
        _arrangedSubviews.removeAll { $0 === view }
        addSubview(view)
        _arrangedSubviews.append(view)
    }

    open func insertArrangedSubview(_ view: UIView, at stackIndex: Int) {
        purgeStaleArrangedState()
        _arrangedSubviews.removeAll { $0 === view }
        addSubview(view)
        // Out-of-range traps, the shim's analogue of UIKit's
        // NSInternalInconsistencyException for an invalid stack index.
        _arrangedSubviews.insert(view, at: stackIndex)
    }

    /// Removes the view from the arrangement only. Per UIKit's documented
    /// contract the view REMAINS a subview; callers pair this with
    /// `view.removeFromSuperview()` to fully detach.
    open func removeArrangedSubview(_ view: UIView) {
        purgeStaleArrangedState()
        _arrangedSubviews.removeAll { $0 === view }
        customSpacingAfterView.removeValue(forKey: ObjectIdentifier(view))
    }

    // Keeps "arranged ⊆ subviews" sound even when a view re-enters via plain
    // addSubview after leaving the hierarchy: purge BEFORE the add, so the
    // returning view's stale arrangement (if any) is gone and it comes back
    // as an ordinary subview — exactly UIKit's behavior.
    open override func addSubview(_ view: UIView) {
        purgeStaleArrangedState()
        super.addSubview(view)
    }

    // MARK: - Custom spacing

    /// UIKit raises if `arrangedSubview` isn't currently arranged; the shim
    /// just records the value (it's inert either way — see header).
    open func setCustomSpacing(_ spacing: CGFloat, after arrangedSubview: UIView) {
        customSpacingAfterView[ObjectIdentifier(arrangedSubview)] = spacing
    }

    open func customSpacing(after arrangedSubview: UIView) -> CGFloat {
        purgeStaleArrangedState()
        return customSpacingAfterView[ObjectIdentifier(arrangedSubview)] ?? UIStackView.spacingUseDefault
    }

    // MARK: - Private

    private func purgeStaleArrangedState() {
        _arrangedSubviews.removeAll { view in
            guard view.superview !== self else { return false }
            customSpacingAfterView.removeValue(forKey: ObjectIdentifier(view))
            return true
        }
    }
}

#endif // !os(iOS)
