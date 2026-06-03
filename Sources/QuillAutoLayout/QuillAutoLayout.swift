// QuillAutoLayout — a Cassowary-backed Auto Layout core for the AppKit→Qt layer.
//
// M0 spike (issue #231): prove that real NSLayoutConstraint-style layout solves to
// exact frames on Linux via the vendored kiwi solver (CKiwi). The anchor/constraint
// surface deliberately mirrors AppKit's (NSLayoutAnchor.constraint(equalTo:constant:),
// NSLayoutDimension.constraint(equalToConstant:), priorities, inequalities) so the
// real `AppKit` shadow module (M1) can adopt these types directly.

import CKiwi

/// A solved rectangle (top-left origin, like AppKit's non-flipped frame math here
/// is irrelevant — we only assert relative geometry). Double-based to stay free of
/// any CoreGraphics dependency in the spike.
public struct LayoutRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum LayoutPriority: Sendable {
    case required, strong, medium, weak
    var raw: Int32 {
        switch self {
        case .required: return Int32(QL_REQUIRED)
        case .strong:   return Int32(QL_STRONG)
        case .medium:   return Int32(QL_MEDIUM)
        case .weak:     return Int32(QL_WEAK)
        }
    }
}

public enum LayoutRelation: Sendable {
    case equal, lessThanOrEqual, greaterThanOrEqual
    var op: Int32 {
        switch self {
        case .equal:              return Int32(QL_OP_EQ)
        case .lessThanOrEqual:    return Int32(QL_OP_LE)
        case .greaterThanOrEqual: return Int32(QL_OP_GE)
        }
    }
}

public enum LayoutAttribute: Sendable {
    case left, top, width, height, right, bottom, centerX, centerY
    // AppKit-shaped aliases for bridges (e.g. QuillAppKitQt mapping
    // NSLayoutConstraint). LTR: leading == left, trailing == right. Baselines
    // approximate to top/bottom until real text metrics land.
    case leading, trailing, firstBaseline, lastBaseline
}

/// Thin Swift wrapper over the CKiwi C ABI.
final class KiwiSolver {
    private let handle: OpaquePointer

    init() { handle = ql_solver_new() }
    deinit { ql_solver_free(handle) }

    func newVariable(_ name: String) -> Int32 { ql_solver_add_var(handle, name) }

    @discardableResult
    func addConstraint(_ ids: [Int32], _ coeffs: [Double], constant: Double,
                       op: Int32, strength: Int32) -> Bool {
        precondition(ids.count == coeffs.count)
        return ids.withUnsafeBufferPointer { idBuf in
            coeffs.withUnsafeBufferPointer { coBuf in
                ql_solver_add_constraint(handle, idBuf.baseAddress, coBuf.baseAddress,
                                         Int32(ids.count), constant, op, strength) == 0
            }
        }
    }

    @discardableResult
    func addEditVariable(_ id: Int32, strength: Int32) -> Bool {
        ql_solver_add_edit_var(handle, id, strength) == 0
    }

    @discardableResult
    func suggest(_ id: Int32, _ value: Double) -> Bool {
        ql_solver_suggest(handle, id, value) == 0
    }

    func update() { ql_solver_update(handle) }
    func value(_ id: Int32) -> Double { ql_solver_value(handle, id) }
}

/// A layout participant (stands in for an NSView). Owns one solver variable per
/// attribute and registers the required internal relations that keep them consistent
/// (right = left + width, centerX = left + width/2, width >= 0, …).
public final class LayoutItem {
    public let name: String
    unowned let engine: LayoutEngine
    let left, top, width, height, right, bottom, centerX, centerY: Int32

    init(name: String, engine: LayoutEngine) {
        self.name = name
        self.engine = engine
        let s = engine.solver
        left = s.newVariable("\(name).left")
        top = s.newVariable("\(name).top")
        width = s.newVariable("\(name).width")
        height = s.newVariable("\(name).height")
        right = s.newVariable("\(name).right")
        bottom = s.newVariable("\(name).bottom")
        centerX = s.newVariable("\(name).centerX")
        centerY = s.newVariable("\(name).centerY")

        let R = Int32(QL_REQUIRED), EQ = Int32(QL_OP_EQ), GE = Int32(QL_OP_GE)
        // right = left + width  →  right - left - width = 0
        s.addConstraint([right, left, width], [1, -1, -1], constant: 0, op: EQ, strength: R)
        // bottom = top + height
        s.addConstraint([bottom, top, height], [1, -1, -1], constant: 0, op: EQ, strength: R)
        // centerX = left + 0.5*width
        s.addConstraint([centerX, left, width], [1, -1, -0.5], constant: 0, op: EQ, strength: R)
        // centerY = top + 0.5*height
        s.addConstraint([centerY, top, height], [1, -1, -0.5], constant: 0, op: EQ, strength: R)
        // sizes are non-negative
        s.addConstraint([width], [1], constant: 0, op: GE, strength: R)
        s.addConstraint([height], [1], constant: 0, op: GE, strength: R)
    }

    func variable(_ a: LayoutAttribute) -> Int32 {
        switch a {
        case .left: return left
        case .top: return top
        case .width: return width
        case .height: return height
        case .right: return right
        case .bottom: return bottom
        case .centerX: return centerX
        case .centerY: return centerY
        case .leading: return left
        case .trailing: return right
        case .firstBaseline: return top
        case .lastBaseline: return bottom
        }
    }

    /// The solved frame. Valid only after `LayoutEngine.solve(...)`.
    public var frame: LayoutRect {
        LayoutRect(x: engine.solver.value(left),
                   y: engine.solver.value(top),
                   width: engine.solver.value(width),
                   height: engine.solver.value(height))
    }

    // AppKit-shaped anchors.
    public var leadingAnchor: LayoutXAxisAnchor { LayoutXAxisAnchor(self, .left) }
    public var trailingAnchor: LayoutXAxisAnchor { LayoutXAxisAnchor(self, .right) }
    public var leftAnchor: LayoutXAxisAnchor { LayoutXAxisAnchor(self, .left) }
    public var rightAnchor: LayoutXAxisAnchor { LayoutXAxisAnchor(self, .right) }
    public var centerXAnchor: LayoutXAxisAnchor { LayoutXAxisAnchor(self, .centerX) }
    public var topAnchor: LayoutYAxisAnchor { LayoutYAxisAnchor(self, .top) }
    public var bottomAnchor: LayoutYAxisAnchor { LayoutYAxisAnchor(self, .bottom) }
    public var centerYAnchor: LayoutYAxisAnchor { LayoutYAxisAnchor(self, .centerY) }
    public var widthAnchor: LayoutDimension { LayoutDimension(self, .width) }
    public var heightAnchor: LayoutDimension { LayoutDimension(self, .height) }
}

/// Base anchor (mirrors NSLayoutAnchor). Concrete axis subtypes keep x/y from being
/// mistakenly related, exactly like AppKit.
public class LayoutAnchor {
    let item: LayoutItem
    let attribute: LayoutAttribute
    init(_ item: LayoutItem, _ attribute: LayoutAttribute) {
        self.item = item
        self.attribute = attribute
    }

    fileprivate func make(_ relation: LayoutRelation, _ other: LayoutAnchor?,
                          multiplier: Double, constant: Double) -> LayoutConstraint {
        LayoutConstraint(first: self, relation: relation, second: other,
                         multiplier: multiplier, constant: constant)
    }
}

public final class LayoutXAxisAnchor: LayoutAnchor {
    public func constraint(equalTo other: LayoutXAxisAnchor, constant: Double = 0) -> LayoutConstraint {
        make(.equal, other, multiplier: 1, constant: constant)
    }
    public func constraint(greaterThanOrEqualTo other: LayoutXAxisAnchor, constant: Double = 0) -> LayoutConstraint {
        make(.greaterThanOrEqual, other, multiplier: 1, constant: constant)
    }
    public func constraint(lessThanOrEqualTo other: LayoutXAxisAnchor, constant: Double = 0) -> LayoutConstraint {
        make(.lessThanOrEqual, other, multiplier: 1, constant: constant)
    }
}

public final class LayoutYAxisAnchor: LayoutAnchor {
    public func constraint(equalTo other: LayoutYAxisAnchor, constant: Double = 0) -> LayoutConstraint {
        make(.equal, other, multiplier: 1, constant: constant)
    }
    public func constraint(greaterThanOrEqualTo other: LayoutYAxisAnchor, constant: Double = 0) -> LayoutConstraint {
        make(.greaterThanOrEqual, other, multiplier: 1, constant: constant)
    }
    public func constraint(lessThanOrEqualTo other: LayoutYAxisAnchor, constant: Double = 0) -> LayoutConstraint {
        make(.lessThanOrEqual, other, multiplier: 1, constant: constant)
    }
}

public final class LayoutDimension: LayoutAnchor {
    public func constraint(equalToConstant c: Double) -> LayoutConstraint {
        make(.equal, nil, multiplier: 0, constant: c)
    }
    public func constraint(lessThanOrEqualToConstant c: Double) -> LayoutConstraint {
        make(.lessThanOrEqual, nil, multiplier: 0, constant: c)
    }
    public func constraint(greaterThanOrEqualToConstant c: Double) -> LayoutConstraint {
        make(.greaterThanOrEqual, nil, multiplier: 0, constant: c)
    }
    public func constraint(equalTo other: LayoutDimension, multiplier m: Double, constant c: Double = 0) -> LayoutConstraint {
        make(.equal, other, multiplier: m, constant: c)
    }
}

/// Mirrors NSLayoutConstraint:  attr1  <relation>  multiplier * attr2 + constant.
public final class LayoutConstraint {
    let first: LayoutAnchor
    let relation: LayoutRelation
    let second: LayoutAnchor?
    let multiplier: Double
    let constant: Double
    public private(set) var priority: LayoutPriority = .required

    init(first: LayoutAnchor, relation: LayoutRelation, second: LayoutAnchor?,
         multiplier: Double, constant: Double) {
        self.first = first
        self.relation = relation
        self.second = second
        self.multiplier = multiplier
        self.constant = constant
    }

    /// Chainable, like setting `.priority` on an NSLayoutConstraint.
    @discardableResult
    public func priority(_ p: LayoutPriority) -> LayoutConstraint {
        priority = p
        return self
    }

    func activate() {
        // attr1 - multiplier*attr2 - constant  <relation>  0
        var ids: [Int32] = [first.item.variable(first.attribute)]
        var coeffs: [Double] = [1]
        if let second {
            ids.append(second.item.variable(second.attribute))
            coeffs.append(-multiplier)
        }
        first.item.engine.solver.addConstraint(ids, coeffs, constant: -constant,
                                                op: relation.op, strength: priority.raw)
    }

    public static func activate(_ constraints: [LayoutConstraint]) {
        constraints.forEach { $0.activate() }
    }
}

/// Owns the solver and produces layout items. One engine == one layout pass scope.
public final class LayoutEngine {
    let solver = KiwiSolver()
    private var rootPinned = false

    public init() {}

    public func makeItem(_ name: String) -> LayoutItem {
        LayoutItem(name: name, engine: self)
    }

    /// Pin `root` to (0,0), drive its size to (width,height), and solve. Call once.
    public func solve(root: LayoutItem, width: Double, height: Double) {
        if !rootPinned {
            let R = Int32(QL_REQUIRED), EQ = Int32(QL_OP_EQ)
            solver.addConstraint([root.left], [1], constant: 0, op: EQ, strength: R)
            solver.addConstraint([root.top], [1], constant: 0, op: EQ, strength: R)
            solver.addEditVariable(root.width, strength: Int32(QL_STRONG))
            solver.addEditVariable(root.height, strength: Int32(QL_STRONG))
            rootPinned = true
        }
        solver.suggest(root.width, width)
        solver.suggest(root.height, height)
        solver.update()
    }

    /// Generic constraint add for bridges that translate an external constraint
    /// model (e.g. NSLayoutConstraint → QuillAppKitQt):
    ///   item1.attribute1  (relation)  multiplier · item2.attribute2 + constant
    /// Pass `item2`/`attribute2` == nil for a constant dimension
    /// (item1.attribute1 (relation) constant).
    public func addConstraint(
        _ item1: LayoutItem, _ attribute1: LayoutAttribute,
        _ relation: LayoutRelation,
        _ item2: LayoutItem?, _ attribute2: LayoutAttribute?,
        multiplier: Double = 1, constant: Double = 0,
        priority: LayoutPriority = .required
    ) {
        var ids: [Int32] = [item1.variable(attribute1)]
        var coeffs: [Double] = [1]
        if let item2, let attribute2 {
            ids.append(item2.variable(attribute2))
            coeffs.append(-multiplier)
        }
        solver.addConstraint(ids, coeffs, constant: -constant, op: relation.op, strength: priority.raw)
    }
}
