import Testing
@testable import QuillFoundation

@Suite("QuillFoundation initial selection")
struct QuillInitialSelectionTests {
    struct Row: Identifiable {
        let id: String
    }

    @Test("Index reads ordered keys and ignores missing or invalid values")
    func indexReadsOrderedKeys() {
        #expect(QuillInitialSelection.index(environmentKeys: ["missing"], environment: [:]) == nil)
        #expect(
            QuillInitialSelection.index(
                environmentKeys: ["bad", "row"],
                environment: ["bad": "not-an-index", "row": " 2 "]
            ) == 2
        )
        #expect(QuillInitialSelection.index(environmentKeys: ["row"], environment: ["row": ""]) == nil)
    }

    @Test("Selected ID clamps requested indexes to available rows")
    func selectedIDClamps() {
        let rows = [
            Row(id: "first"),
            Row(id: "middle"),
            Row(id: "last")
        ]

        #expect(
            QuillInitialSelection.selectedID(in: rows, environmentKeys: ["row"], environment: ["row": "1"])
            == "middle"
        )
        #expect(
            QuillInitialSelection.selectedID(in: rows, environmentKeys: ["row"], environment: ["row": "-5"])
            == "first"
        )
        #expect(
            QuillInitialSelection.selectedID(in: rows, environmentKeys: ["row"], environment: ["row": "99"])
            == "last"
        )
        #expect(
            QuillInitialSelection.selectedID(in: [Row](), environmentKeys: ["row"], environment: ["row": "0"])
            == nil
        )
    }
}
