import Foundation
import Testing
@testable import QuillAccount

/// Tests for the vendored upstream NetNewsWire sync identifier types
/// (`ContainerIdentifier`, `SidebarItemIdentifier`) — rung 2 of the Account
/// bring-up. Both are Foundation-only and round-trip through `userInfo`
/// dictionaries (used for state restoration / sync); `ContainerIdentifier`
/// is also `Codable`.
@Suite("QuillAccount — sync identifiers")
struct AccountIdentifierTests {

    @Test("ContainerIdentifier round-trips through userInfo for every case")
    func containerIdentifierUserInfoRoundTrip() {
        let cases: [ContainerIdentifier] = [
            .smartFeedController,
            .account("acc1"),
            .folder("acc1", "News"),
        ]
        for identifier in cases {
            #expect(ContainerIdentifier(userInfo: identifier.userInfo) == identifier)
        }
    }

    @Test("ContainerIdentifier is Codable round-trip")
    func containerIdentifierCodable() throws {
        for identifier in [ContainerIdentifier.smartFeedController, .account("a"), .folder("a", "F")] {
            let data = try JSONEncoder().encode(identifier)
            let decoded = try JSONDecoder().decode(ContainerIdentifier.self, from: data)
            #expect(decoded == identifier)
        }
    }

    @Test("ContainerIdentifier(userInfo:) rejects malformed dictionaries")
    func containerIdentifierRejectsMalformed() {
        #expect(ContainerIdentifier(userInfo: [:]) == nil)
        #expect(ContainerIdentifier(userInfo: ["type": "account"]) == nil)       // missing accountID
        #expect(ContainerIdentifier(userInfo: ["type": "bogus"]) == nil)
    }

    @Test("SidebarItemIdentifier round-trips through userInfo and has a description")
    func sidebarItemIdentifierUserInfo() {
        let cases: [SidebarItemIdentifier] = [
            .smartFeed("today"),
            .feed("acc1", "feed1"),
            .folder("acc1", "News"),
        ]
        for identifier in cases {
            #expect(SidebarItemIdentifier(userInfo: identifier.userInfo) == identifier)
            #expect(!identifier.description.isEmpty)
        }
        #expect(SidebarItemIdentifier(userInfo: [:]) == nil)
    }

    @Test("Identifier cases are distinct (Equatable/Hashable)")
    func identifiersDistinct() {
        #expect(ContainerIdentifier.account("a") != .account("b"))
        #expect(ContainerIdentifier.folder("a", "F") != .folder("a", "G"))
        #expect(SidebarItemIdentifier.feed("a", "1") != .feed("a", "2"))
        #expect(Set([SidebarItemIdentifier.smartFeed("x"), .smartFeed("x"), .smartFeed("y")]).count == 2)
    }
}
