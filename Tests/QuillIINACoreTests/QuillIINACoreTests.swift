import Foundation
import Testing
@testable import QuillIINACore

@Suite("QuillIINACore playlist fixtures")
struct QuillIINACoreTests {

    // MARK: - PlaylistItem identity

    @Test("PlaylistItem assigns a fresh UUID on each init by default")
    func playlistItemUniqueIDs() {
        let a = PlaylistItem(title: "x", subtitle: "y", duration: "1:00")
        let b = PlaylistItem(title: "x", subtitle: "y", duration: "1:00")
        #expect(a.id != b.id)
    }

    @Test("PlaylistItem stores title / subtitle / duration verbatim")
    func playlistItemStoresFields() {
        let item = PlaylistItem(title: "Big Buck Bunny", subtitle: "2008", duration: "9:56")
        #expect(item.title == "Big Buck Bunny")
        #expect(item.subtitle == "2008")
        #expect(item.duration == "9:56")
    }

    // MARK: - Fixture playlist invariants

    @Test("Fixture playlist is non-empty so the sidebar always has rows")
    func fixturePlaylistNonEmpty() {
        #expect(!QuillIINAFixtures.playlist.isEmpty)
    }

    @Test("Fixture playlist items all carry non-empty title + duration")
    func fixturePlaylistItemsHaveTitleAndDuration() {
        for item in QuillIINAFixtures.playlist {
            #expect(!item.title.isEmpty, "playlist item has empty title")
            #expect(!item.duration.isEmpty, "\(item.title) has empty duration")
        }
    }

    @Test("Fixture playlist item ids are unique")
    func fixturePlaylistIDsUnique() {
        let ids = QuillIINAFixtures.playlist.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Fixture durations are in mm:ss form")
    func fixtureDurationsAreClockFormatted() {
        for item in QuillIINAFixtures.playlist {
            // Each fixture duration is "M:SS" or "MM:SS"; assert
            // there's exactly one colon with non-empty halves.
            let parts = item.duration.split(separator: ":")
            #expect(parts.count == 2, "\(item.title) duration \(item.duration) is not mm:ss")
            #expect(parts.allSatisfy { Int($0) != nil }, "\(item.duration) has non-numeric parts")
        }
    }

    @Test("Fixture playlist carries the four Blender shorts named in CP89")
    func fixturePlaylistFourBlenderShorts() {
        let titles = QuillIINAFixtures.playlist.map(\.title)
        #expect(titles.contains("Big Buck Bunny"))
        #expect(titles.contains("Sintel"))
        #expect(titles.contains("Tears of Steel"))
        #expect(titles.contains("Charge"))
    }

    @Test("Initial playlist selection reads the shared backend env key")
    func initialPlaylistSelectionReadsEnvironment() {
        let playlist = QuillIINAFixtures.playlist

        #expect(QuillIINAInitialSelection.selectedPlaylistIndexEnvironmentKey == "QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START")
        #expect(
            QuillIINAInitialSelection.selectedPlaylistID(
                in: playlist,
                environment: ["QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START": "2"]
            ) == playlist[2].id
        )
        #expect(
            QuillIINAInitialSelection.selectedPlaylistID(
                in: playlist,
                environment: ["QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START": "99"]
            ) == playlist.last?.id
        )
    }
}
