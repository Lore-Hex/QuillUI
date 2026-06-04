// QuillAppKitQt — the Auto Layout solve pass (M2 slice 2b, issue #231).
//
// Joins the functional NSLayoutConstraint model (QuillUIKit, slice 2a) to the
// Cassowary solver (QuillAutoLayout / kiwi, M0): translate a view subtree's
// active constraints into the solver, solve, and apply the solved frames to the
// backing QWidgets via applyQtGeometry (slice 1). This is where an unmodified
// AppKit ViewController, built from source, lays out faithfully on Qt — the
// AppKit-faithful path GTK's gtk_box backing can't match.

import AppKit
import QuillUIKit
import QuillAutoLayout
import CQuillAppKitQt

private func mapAttribute(_ a: QuillLayoutAttribute) -> LayoutAttribute? {
    switch a {
    case .left: return .left
    case .right: return .right
    case .top: return .top
    case .bottom: return .bottom
    case .leading: return .leading
    case .trailing: return .trailing
    case .width: return .width
    case .height: return .height
    case .centerX: return .centerX
    case .centerY: return .centerY
    case .firstBaseline: return .firstBaseline
    case .lastBaseline: return .lastBaseline
    case .notAnAttribute: return nil
    }
}

private func mapRelation(_ r: NSLayoutConstraint.QuillRelation) -> LayoutRelation {
    switch r {
    case .equal: return .equal
    case .lessThanOrEqual: return .lessThanOrEqual
    case .greaterThanOrEqual: return .greaterThanOrEqual
    }
}

/// Map an NSLayoutConstraint.Priority (1000 = required) onto a solver strength,
/// so soft constraints (content hugging/compression, .defaultHigh, …) yield to
/// required ones instead of over-constraining the system.
private func mapPriority(_ p: NSLayoutConstraint.Priority) -> LayoutPriority {
    switch p.rawValue {
    case 1000...: return .required
    case 500...: return .strong
    case 100...: return .medium
    default: return .weak
    }
}

extension NSView {
    /// Solve this view's subtree against its active `NSLayoutConstraint`s using
    /// `QuillAutoLayout` (kiwi) and apply the solved frames to the backing
    /// QWidgets. `self` is the layout root: pinned to (0,0) and driven to
    /// (width, height). Coordinates are top-left, matching Qt.
    public func layoutQtSubtree(width: Double, height: Double) {
        // Collect the subtree (self + all descendants).
        var subtree: [NSView] = []
        func collect(_ v: NSView) {
            subtree.append(v)
            v.subviews.forEach(collect)
        }
        collect(self)
        let memberIDs = Set(subtree.map { ObjectIdentifier($0) })

        // One LayoutItem per view.
        let engine = LayoutEngine()
        var items: [ObjectIdentifier: LayoutItem] = [:]
        for v in subtree {
            items[ObjectIdentifier(v)] = engine.makeItem(v.identifier?.rawValue ?? "view")
        }

        // Translate each active constraint that lives entirely within the subtree.
        for c in NSLayoutConstraint.quillActive {
            guard let firstAnchor = c.quillFirstAnchor,
                  let firstView = firstAnchor.quillItem as? NSView,
                  memberIDs.contains(ObjectIdentifier(firstView)),
                  let attr1 = mapAttribute(firstAnchor.quillAttribute),
                  let firstItem = items[ObjectIdentifier(firstView)]
            else { continue }

            var secondItem: LayoutItem?
            var attr2: LayoutAttribute?
            if let secondAnchor = c.quillSecondAnchor {
                guard let secondView = secondAnchor.quillItem as? NSView,
                      memberIDs.contains(ObjectIdentifier(secondView)),
                      let mapped = mapAttribute(secondAnchor.quillAttribute),
                      let item2 = items[ObjectIdentifier(secondView)]
                else { continue }
                secondItem = item2
                attr2 = mapped
            }

            engine.addConstraint(
                firstItem, attr1, mapRelation(c.quillRelation),
                secondItem, attr2,
                multiplier: Double(c.quillMultiplier),
                constant: Double(c.quillConstant),
                priority: mapPriority(c.priority)
            )
        }

        guard let rootItem = items[ObjectIdentifier(self)] else { return }
        engine.solve(root: rootItem, width: width, height: height)

        // Apply solved frames to the shadow + the backing QWidgets.
        for v in subtree {
            guard let item = items[ObjectIdentifier(v)] else { continue }
            let f = item.frame
            v.frame = NSRect(x: CGFloat(f.x), y: CGFloat(f.y),
                             width: CGFloat(f.width), height: CGFloat(f.height))
            v.ensureQtWidget()
            v.applyQtGeometry(x: Int32(f.x.rounded()), y: Int32(f.y.rounded()),
                              width: Int32(f.width.rounded()), height: Int32(f.height.rounded()))
        }
    }
}
