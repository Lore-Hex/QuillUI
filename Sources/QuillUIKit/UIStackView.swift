// QuillUIKit · UIStackView
// ========================
// UIStackView shadow for platforms without Apple's UIKit. Upstream UIKit
// code (SignalUI's ActionSheetController, AttachmentApprovalToolbar, …)
// builds its chrome out of stack views: it constructs them, mutates the
// arranged-subview list, and tunes axis/alignment/distribution/spacing.
//
// Honest Linux semantics: a stack view here is a modest layout engine plus a
// faithful state model. It lays out visible arranged subviews for the common
// axis/alignment/distribution/spacing cases Signal uses, while still storing
// the full surface for future native layout backends. The arranged-subview
// bookkeeping keeps UIKit's documented invariants:
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

    open override func layoutSubviews() {
        super.layoutSubviews()
        let views = arrangedSubviews.filter { !$0.isHidden }
        guard !views.isEmpty else { return }

        let margins = isLayoutMarginsRelativeArrangement ? quillLayoutMargins : .zero
        let layoutBounds = CGRect(
            x: margins.left,
            y: margins.top,
            width: max(0, bounds.width - margins.left - margins.right),
            height: max(0, bounds.height - margins.top - margins.bottom)
        )

        switch axis {
        case .vertical:
            layoutVerticalSubviews(views, in: layoutBounds)
        case .horizontal:
            layoutHorizontalSubviews(views, in: layoutBounds)
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let views = arrangedSubviews.filter { !$0.isHidden }
        guard !views.isEmpty else { return .zero }

        func isConstrained(_ value: CGFloat) -> Bool {
            value.isFinite && value > 0 && value < CGFloat.greatestFiniteMagnitude / 4
        }

        let margins = isLayoutMarginsRelativeArrangement ? quillLayoutMargins : .zero
        let proposedWidth = isConstrained(size.width)
            ? max(0, size.width - margins.left - margins.right)
            : CGFloat.greatestFiniteMagnitude
        let proposedHeight = isConstrained(size.height)
            ? max(0, size.height - margins.top - margins.bottom)
            : CGFloat.greatestFiniteMagnitude

        let totalSpacing = spacing * CGFloat(max(0, views.count - 1))
        switch axis {
        case .vertical:
            var width: CGFloat = 0
            var height: CGFloat = totalSpacing
            for view in views {
                let measured = view.quillEstimatedFittingSize(
                    proposed: CGSize(width: proposedWidth, height: CGFloat.greatestFiniteMagnitude)
                )
                width = max(width, measured.width)
                height += measured.height
            }
            if isConstrained(size.width), alignment == .fill {
                width = proposedWidth
            }
            return CGSize(width: width + margins.left + margins.right, height: height + margins.top + margins.bottom)
        case .horizontal:
            var width: CGFloat = totalSpacing
            var height: CGFloat = 0
            for view in views {
                let measured = view.quillEstimatedFittingSize(
                    proposed: CGSize(width: CGFloat.greatestFiniteMagnitude, height: proposedHeight)
                )
                width += measured.width
                height = max(height, measured.height)
            }
            if isConstrained(size.height), alignment == .fill {
                height = proposedHeight
            }
            return CGSize(width: width + margins.left + margins.right, height: height + margins.top + margins.bottom)
        }
    }

    // MARK: - Private

    private func layoutVerticalSubviews(_ views: [UIView], in rect: CGRect) {
        let totalSpacing = spacing * CGFloat(max(0, views.count - 1))
        let equalHeight = distribution == .fillEqually
            ? max(0, (rect.height - totalSpacing) / CGFloat(views.count))
            : nil
        var y = rect.minY

        for view in views {
            let measured = view.quillEstimatedFittingSize(proposed: CGSize(
                width: rect.width,
                height: CGFloat.greatestFiniteMagnitude
            ))
            let height = equalHeight ?? measured.height
            let width = alignment == .fill ? rect.width : min(max(measured.width, view.bounds.width), rect.width)
            let x = alignedOrigin(
                availableMin: rect.minX,
                availableSize: rect.width,
                itemSize: width,
                alignment: alignment
            )
            view.frame = CGRect(x: x, y: y, width: width, height: height)
            y += height + spacingAfter(view)
        }
    }

    private func layoutHorizontalSubviews(_ views: [UIView], in rect: CGRect) {
        let totalSpacing = spacing * CGFloat(max(0, views.count - 1))
        let equalWidth = distribution == .fillEqually
            ? max(0, (rect.width - totalSpacing) / CGFloat(views.count))
            : nil
        var x = rect.minX

        for view in views {
            let measured = view.quillEstimatedFittingSize(proposed: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: rect.height
            ))
            let width = equalWidth ?? measured.width
            let height = alignment == .fill ? rect.height : min(max(measured.height, view.bounds.height), rect.height)
            let y = alignedOrigin(
                availableMin: rect.minY,
                availableSize: rect.height,
                itemSize: height,
                alignment: alignment
            )
            view.frame = CGRect(x: x, y: y, width: width, height: height)
            x += width + spacingAfter(view)
        }
    }

    private func spacingAfter(_ view: UIView) -> CGFloat {
        let custom = customSpacingAfterView[ObjectIdentifier(view)]
        guard let custom, custom != UIStackView.spacingUseDefault else {
            return spacing
        }
        if custom == UIStackView.spacingUseSystem {
            return spacing
        }
        return custom
    }

    private func alignedOrigin(
        availableMin: CGFloat,
        availableSize: CGFloat,
        itemSize: CGFloat,
        alignment: Alignment
    ) -> CGFloat {
        switch alignment {
        case .fill, .leading, .firstBaseline:
            return availableMin
        case .center:
            return availableMin + (availableSize - itemSize) / 2
        case .trailing, .lastBaseline:
            return availableMin + availableSize - itemSize
        }
    }

    private func purgeStaleArrangedState() {
        _arrangedSubviews.removeAll { view in
            guard view.superview !== self else { return false }
            customSpacingAfterView.removeValue(forKey: ObjectIdentifier(view))
            return true
        }
    }
}

#endif // !os(iOS)
