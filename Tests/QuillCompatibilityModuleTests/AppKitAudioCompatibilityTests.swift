import Foundation
import Testing
import AppKit
import QuillKit

@Suite("AppKit audio compatibility", .serialized)
struct AppKitAudioCompatibilityTests {
    @Test("NSSound routes playback state through QuillKit")
    func nsSoundRoutesPlaybackStateThroughQuillKit() throws {
        QuillAudioPlayerService.shared.resetAll()
        QuillCompatibilityDiagnostics.shared.clear()

        let sound = try #require(NSSound(data: Data([1, 2, 3])))
        #expect(sound.play())
        #expect(sound.stop())

        let state = try #require(QuillAudioPlayerService.shared.playerStates.first {
            $0.source == .data(byteCount: 3)
        })
        #expect(state.playCount == 1)
        #expect(state.stopCount == 1)
        #expect(state.isPlaying == false)

        let operations = Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        #expect(operations.contains("audioPlayer.play"))
        #expect(operations.contains("audioPlayer.stop"))
    }
}
