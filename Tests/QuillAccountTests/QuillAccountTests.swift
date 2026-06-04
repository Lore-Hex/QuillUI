import Foundation
import Testing
@testable import QuillAccount

/// Smoke tests for the vendored upstream NetNewsWire `Account` module —
/// the first, Foundation-only leaf types of an incremental bring-up
/// (`AccountBehavior`, `UnreadCountProvider`). Upstream Account has no test
/// target of its own, so these are Quill-side guards against import-rewrite
/// regressions as the module grows.
@Suite("QuillAccount — vendored upstream leaf types")
struct QuillAccountTests {

    @Test("AccountBehavior is Equatable, including its associated value")
    func accountBehaviorEquatable() {
        #expect(AccountBehavior.disallowOPMLImports == .disallowOPMLImports)
        #expect(AccountBehavior.disallowMarkAsUnreadAfterPeriod(30) == .disallowMarkAsUnreadAfterPeriod(30))
        #expect(AccountBehavior.disallowMarkAsUnreadAfterPeriod(30) != .disallowMarkAsUnreadAfterPeriod(7))
        #expect(AccountBehavior.disallowFolderManagement != .disallowOPMLImports)
        // AccountBehaviors is just [AccountBehavior].
        let behaviors: AccountBehaviors = [.disallowFolderManagement, .disallowOPMLImports]
        #expect(behaviors.contains(.disallowOPMLImports))
        #expect(!behaviors.contains(.disallowFeedInRootFolder))
    }

    @MainActor
    @Test("UnreadCountProvider.calculateUnreadCount sums children's counts")
    func unreadCountSumsChildren() {
        struct Node: UnreadCountProvider {
            var unreadCount: Int
        }
        let parent = Node(unreadCount: 0)
        let total = parent.calculateUnreadCount([
            Node(unreadCount: 3), Node(unreadCount: 4), Node(unreadCount: 0)
        ])
        #expect(total == 7)
    }

    @Test("Unread-count notification names are the stable upstream raw values")
    func notificationNamesStable() {
        #expect(Notification.Name.UnreadCountDidChange.rawValue == "UnreadCountDidChange")
        #expect(Notification.Name.UnreadCountDidInitialize.rawValue == "UnreadCountDidInitialize")
    }
}
