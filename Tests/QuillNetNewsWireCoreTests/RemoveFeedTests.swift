import Foundation
import Testing
@testable import QuillNetNewsWireCore

/// Pins the "Delete Feed" / unsubscribe action (NetNewsWire parity): removing a
/// subscribed feed, the selection fix-up when the removed feed was selected, and
/// the no-op for an unknown id.
@Suite("QuillNetNewsWireCore — removeFeed (unsubscribe)")
@MainActor
struct RemoveFeedTests {

    private func model() -> RSSReaderModel {
        RSSReaderModel(subscribedFeeds: [
            Feed(title: "A", url: "https://a.example.com/feed"),
            Feed(title: "B", url: "https://b.example.com/feed"),
        ])
    }

    @Test("removes a subscribed feed")
    func removesFeed() {
        let m = model()
        #expect(m.removeFeed(id: "https://b.example.com/feed"))
        #expect(!m.subscribedFeeds.contains { $0.id == "https://b.example.com/feed" })
        #expect(m.subscribedFeeds.count == 1)
    }

    @Test("an unknown id is a no-op")
    func unknownIDNoOp() {
        let m = model()
        #expect(!m.removeFeed(id: "https://nope.example.com/feed"))
        #expect(m.subscribedFeeds.count == 2)
    }

    @Test("removing the selected feed moves selection to the first remaining feed")
    func selectionFollowsRemoval() {
        let m = model()
        // Default selection is the first feed (A).
        #expect(m.selectedFeedID == "https://a.example.com/feed")
        #expect(m.removeFeed(id: "https://a.example.com/feed"))
        #expect(m.selectedFeedID == "https://b.example.com/feed")
    }

    @Test("removing the last feed clears the selection")
    func removingLastClearsSelection() {
        let m = model()
        _ = m.removeFeed(id: "https://a.example.com/feed")
        _ = m.removeFeed(id: "https://b.example.com/feed")
        #expect(m.subscribedFeeds.isEmpty)
        #expect(m.selectedFeedID == nil)
    }
}
