import SwiftUI
import Testing
@testable import QuillUI

#if os(Linux)
@Suite("ForEach binding compatibility")
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
}

private struct EditableRow: Identifiable, Equatable {
    let id: UUID
    var name: String
}
#endif
