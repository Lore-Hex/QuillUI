import Foundation
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `MimeType` constants and the `String` MIME-category
/// helpers (image/audio/video, with `x-` prefix and case-insensitive matching).
@Suite("RSWeb clone — MimeType")
struct MimeTypeTests {

    @Test("MimeType exposes the expected constants")
    func constants() {
        #expect(MimeType.png == "image/png")
        #expect(MimeType.jpeg == "image/jpeg")
        #expect(MimeType.gif == "image/gif")
        #expect(MimeType.formURLEncoded == "application/x-www-form-urlencoded")
    }

    @Test("isMimeTypeImage matches image types, x- prefixes, and is case-insensitive")
    func image() {
        #expect("image/png".isMimeTypeImage())
        #expect("x-image/foo".isMimeTypeImage())
        #expect("IMAGE/PNG".isMimeTypeImage())
        #expect(!"text/html".isMimeTypeImage())
    }

    @Test("audio and video categories")
    func audioVideo() {
        #expect("audio/mpeg".isMimeTypeAudio())
        #expect(!"video/mp4".isMimeTypeAudio())
        #expect("video/mp4".isMimeTypeVideo())
        #expect(!"audio/mpeg".isMimeTypeVideo())
    }

    @Test("time-based media is audio or video, not image")
    func timeBasedMedia() {
        #expect("audio/mpeg".isMimeTypeTimeBasedMedia())
        #expect("video/mp4".isMimeTypeTimeBasedMedia())
        #expect(!"image/png".isMimeTypeTimeBasedMedia())
    }
}
