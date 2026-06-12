import Testing
@testable import SwiftOpenUI

@Suite("ForEach binding collection")
struct ForEachBindingCollectionTests {

    private struct Completion: Identifiable, Equatable {
        let id: Int
        var text: String
    }

    @Test("edit actions option set exposes SwiftUI-shaped cases")
    func editActionsCases() {
        #expect(EditActions.move.rawValue != EditActions.delete.rawValue)
        #expect(EditActions.all.contains(.move))
        #expect(EditActions.all.contains(.delete))
    }

    @Test("binding collection with editActions renders and writes element bindings")
    func bindingCollectionEditActionsRenderAndWriteThrough() {
        var completions = [
            Completion(id: 1, text: "alpha"),
            Completion(id: 2, text: "beta"),
        ]
        let completionsBinding = Binding<[Completion]>(
            get: { completions },
            set: { completions = $0 }
        )
        @Binding(projectedValue: completionsBinding) var boundCompletions: [Completion]
        var capturedBindings: [Binding<Completion>] = []

        func row(_ binding: Binding<Completion>, _ completion: Completion) -> Text {
            capturedBindings.append(binding)
            return Text(completion.text)
        }

        let forEach = ForEach($boundCompletions, editActions: .move) { $completion in
            row($completion, completion)
        }

        #expect(forEach.children.count == 2)
        #expect(capturedBindings.map { $0.wrappedValue.text } == ["alpha", "beta"])

        var edited = capturedBindings[1].wrappedValue
        edited.text = "gamma"
        capturedBindings[1].wrappedValue = edited

        #expect(completions == [
            Completion(id: 1, text: "alpha"),
            Completion(id: 2, text: "gamma"),
        ])
    }
}
