import SwiftUI
import Testing
@testable import QuillUI

#if os(Linux)
// `@MainActor`: ForEach.children invokes the MainActor-isolated content
// closure, so accessing it off-main trips the Swift-6 isolation runtime
// check (dispatch_assert_queue → SIGTRAP). Swift Testing runs @Test cases
// on a background pool by default; pin the suite to the main actor so the
// children getter evaluates where its isolation expects.
@Suite("ForEach binding compatibility")
@MainActor
struct ForEachBindingCompatibilityTests {
    @Test("Binding collection editActions initializer renders current rows")
    func bindingCollectionEditActionsRendersRows() {
        var rows = [
            EditableRow(id: UUID(), name: "First"),
            EditableRow(id: UUID(), name: "Second")
        ]
        let binding = Binding<[EditableRow]>(
            get: { rows },
            set: { rows = $0 }
        )

        let list = ForEach(binding, editActions: .move) { $row in
            Text(row.name)
        }

        #expect(list.data.map(\.name) == ["First", "Second"])
        #expect(list.children.count == 2)
    }

    @Test("Binding collection editActions initializer writes back by identity")
    func bindingCollectionEditActionsWritesBackByIdentity() {
        let firstID = UUID()
        var rows = [
            EditableRow(id: firstID, name: "First"),
            EditableRow(id: UUID(), name: "Second")
        ]
        let binding = Binding<[EditableRow]>(
            get: { rows },
            set: { rows = $0 }
        )
        var captured: Binding<EditableRow>?

        let list = ForEach(binding, editActions: [.move, .delete]) { $row in
            if row.id == firstID {
                captured = $row
            }
            return Text(row.name)
        }

        _ = list.children
        captured?.wrappedValue.name = "Updated"

        #expect(rows.map(\.name) == ["Updated", "Second"])
    }

    @Test("Binding collection explicit id initializer renders and writes current rows")
    func bindingCollectionExplicitIDRendersAndWritesRows() {
        var rows = [
            PlainRow(name: "First", detail: "One"),
            PlainRow(name: "Second", detail: "Two")
        ]
        let binding = Binding<[PlainRow]>(
            get: { rows },
            set: { rows = $0 }
        )
        var captured: Binding<PlainRow>?

        let list = ForEach(binding, id: \.name) { $row in
            if row.name == "First" {
                captured = $row
            }
            return Text(row.detail)
        }

        #expect(list.data.map { $0.wrappedValue.name } == ["First", "Second"])
        #expect(list.children.count == 2)

        captured?.wrappedValue.detail = "Updated"

        #expect(rows.map(\.detail) == ["Updated", "Two"])
    }
}

private struct EditableRow: Identifiable, Equatable {
    let id: UUID
    var name: String
}

private struct PlainRow: Equatable {
    var name: String
    var detail: String
}
#endif
