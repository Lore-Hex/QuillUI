import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import RSWeb

/// Pins the source-compatible RSWeb `Downloader` surface used by
/// FeedFinder.find(url:): non-http URLs are ignored without attempting a
/// URLSession request, matching upstream's best-effort callback behavior.
@MainActor
@Suite("RSWeb clone — Downloader")
struct DownloaderTests {

    @Test("non-http URLs complete with no data, response, or error")
    func nonHTTPURLCompletesEmpty() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Downloader.shared.download(URL(string: "file:///tmp/feed.xml")!) { data, response, error in
                #expect(data == nil)
                #expect(response == nil)
                #expect(error == nil)
                continuation.resume()
            }
        }
    }
}
