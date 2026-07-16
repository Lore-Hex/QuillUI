#if os(Linux)
import Foundation
import QuillFoundation
import Testing

@Suite("QuillFoundation URL security-scope clone")
struct URLSecurityScopeTests {
    @Test("security-scoped access is a Linux no-op and bookmarks round-trip")
    func securityScopeAndBookmarkRoundTrip() throws {
        let url = URL(fileURLWithPath: "/tmp/quill-url-security-scope.txt")

        #expect(url.startAccessingSecurityScopedResource())
        url.stopAccessingSecurityScopedResource()

        let bookmark = try url.bookmarkData(options: [.withSecurityScope])
        var isStale = true
        let resolved = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            bookmarkDataIsStale: &isStale
        )

        #expect(isStale == false)
        #expect(resolved.path == url.path)
    }
}
#endif
