import Testing
@testable import QuillAutoLayout

/// M0 spike (issue #231): prove the vendored kiwi Cassowary solver, driven through the
/// CKiwi C ABI by NSLayoutConstraint-shaped Swift, produces exact AppKit-style frames
/// on Linux. If this holds, the rest of the AppKit→Qt layer is mechanical mapping.
@Suite("QuillAutoLayout / Cassowary spike")
struct QuillAutoLayoutTests {

    private func approx(_ a: Double, _ b: Double, _ tol: Double = 0.0001) -> Bool {
        abs(a - b) <= tol
    }

    @Test("KeyValueRow: a fully-constrained AppKit layout solves to exact frames")
    func keyValueRow() {
        // Mirrors wireguard-apple's KeyValueRow: a fixed-width name label and a value
        // field that stretches between it and the trailing edge, both vertically centered.
        let engine = LayoutEngine()
        let root = engine.makeItem("root")
        let name = engine.makeItem("name")
        let value = engine.makeItem("value")

        LayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            name.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            name.widthAnchor.constraint(equalToConstant: 80),
            name.heightAnchor.constraint(equalToConstant: 17),

            value.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 8),
            value.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            value.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            value.heightAnchor.constraint(equalToConstant: 22),
        ])

        engine.solve(root: root, width: 300, height: 44)

        let r = root.frame, n = name.frame, v = value.frame
        // container
        #expect(approx(r.x, 0) && approx(r.y, 0) && approx(r.width, 300) && approx(r.height, 44))
        // name: x=16, w=80 (→ right=96); centerY=22, h=17 → y=13.5
        #expect(approx(n.x, 16) && approx(n.width, 80) && approx(n.height, 17) && approx(n.y, 13.5))
        // value: x=name.right+8=104; right=root.right-16=284 → w=180; centerY=22, h=22 → y=11
        #expect(approx(v.x, 104) && approx(v.width, 180) && approx(v.height, 22) && approx(v.y, 11))
    }

    @Test("Inequality + soft priority: a width prefers 500 but is capped at 120")
    func inequalityAndSoftPriority() {
        // The Cassowary value-add over fixed layouts: required inequalities win over
        // soft equalities. Proves <= relations and priority ordering both work.
        let engine = LayoutEngine()
        let root = engine.makeItem("root")
        let box = engine.makeItem("box")

        LayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            box.topAnchor.constraint(equalTo: root.topAnchor),
            box.heightAnchor.constraint(equalToConstant: 10),
            box.widthAnchor.constraint(lessThanOrEqualToConstant: 120),          // required
            box.widthAnchor.constraint(equalToConstant: 500).priority(.weak),    // soft wish
        ])

        engine.solve(root: root, width: 200, height: 50)
        #expect(approx(box.frame.width, 120))
    }

    @Test("Multiplier: a child sized to half its container")
    func multiplier() {
        let engine = LayoutEngine()
        let root = engine.makeItem("root")
        let half = engine.makeItem("half")

        LayoutConstraint.activate([
            half.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            half.topAnchor.constraint(equalTo: root.topAnchor),
            half.heightAnchor.constraint(equalToConstant: 10),
            half.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.5),
        ])

        engine.solve(root: root, width: 240, height: 50)
        #expect(approx(half.frame.width, 120))
    }
}
