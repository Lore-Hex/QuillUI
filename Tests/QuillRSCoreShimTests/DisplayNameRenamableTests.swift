import Foundation
import Testing
@testable import QuillRSCoreShim

/// Captures notification deliveries synchronously. `NotificationCenter.post`
/// runs observers inline on the posting thread, so the test reads these back
/// immediately after posting. `@unchecked Sendable` is sound here because every
/// access happens on the main thread within a single `@MainActor` test.
private final class NotificationSpy: @unchecked Sendable {
    var fireCount = 0
    var lastObject: AnyObject?
}

/// A stand-in for the real Account model types (`Feed`, `Folder`), which both
/// conform to `DisplayNameProvider` and `Renamable` from RSCore. Vendoring those
/// two protocols into the live RSCore clone (QuillRSCoreShim) is a prerequisite
/// for bringing up the model classes that `import RSCore`.
@MainActor private final class SidebarThing: DisplayNameProvider, Renamable {
    private(set) var nameForDisplay: String
    init(_ name: String) { nameForDisplay = name }

    func rename(to newName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        nameForDisplay = newName
        postDisplayNameDidChangeNotification()
        completion(.success(()))
    }
}

@Suite("QuillRSCoreShim — DisplayNameProvider + Renamable (Account-model protocols)")
@MainActor
struct DisplayNameRenamableTests {

    @Test("DisplayNameProvider exposes nameForDisplay")
    func nameForDisplay() {
        let thing = SidebarThing("Cats")
        #expect(thing.nameForDisplay == "Cats")
    }

    @Test("postDisplayNameDidChangeNotification fires .DisplayNameDidChange with the provider as object")
    func displayNameNotification() {
        let spy = NotificationSpy()
        let token = NotificationCenter.default.addObserver(
            forName: .DisplayNameDidChange, object: nil, queue: nil
        ) { note in
            spy.fireCount += 1
            spy.lastObject = note.object as AnyObject?
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let thing = SidebarThing("Cats")
        thing.postDisplayNameDidChangeNotification()

        #expect(spy.fireCount == 1)
        #expect(spy.lastObject === thing)
    }

    @Test("Renamable.rename updates the display name and calls completion with success")
    func renameSucceeds() {
        let thing = SidebarThing("Old Name")
        var result: Result<Void, Error>?
        thing.rename(to: "New Name") { result = $0 }

        #expect(thing.nameForDisplay == "New Name")
        guard case .success = result else {
            Issue.record("expected rename to complete with .success, got \(String(describing: result))")
            return
        }
    }

    @Test("rename also posts a display-name-change notification (model types repaint on rename)")
    func renamePostsNotification() {
        let spy = NotificationSpy()
        let token = NotificationCenter.default.addObserver(
            forName: .DisplayNameDidChange, object: nil, queue: nil
        ) { note in
            spy.fireCount += 1
            spy.lastObject = note.object as AnyObject?
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let thing = SidebarThing("Old Name")
        thing.rename(to: "New Name") { _ in }

        #expect(spy.fireCount == 1)
        #expect(spy.lastObject === thing)
    }
}
