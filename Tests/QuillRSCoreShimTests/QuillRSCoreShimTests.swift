import Foundation
import Testing
@testable import QuillRSCoreShim

/// Pins the QuillRSCoreShim's `String.md5String` byte-for-byte
/// against the RFC 1321 test suite. Any drift here will silently
/// shift article IDs computed by the vendored upstream parsers
/// — round-trip stability matters more than the algorithm
/// itself.
@Suite("QuillRSCoreShim.String.md5String — RFC 1321 vectors")
struct QuillRSCoreShimTests {

    @Test("RFC 1321: MD5(\"\") == d41d8cd98f00b204e9800998ecf8427e")
    func md5EmptyString() {
        #expect("".md5String == "d41d8cd98f00b204e9800998ecf8427e")
    }

    @Test("RFC 1321: MD5(\"a\") == 0cc175b9c0f1b6a831c399e269772661")
    func md5SingleChar() {
        #expect("a".md5String == "0cc175b9c0f1b6a831c399e269772661")
    }

    @Test("RFC 1321: MD5(\"abc\") == 900150983cd24fb0d6963f7d28e17f72")
    func md5ABC() {
        #expect("abc".md5String == "900150983cd24fb0d6963f7d28e17f72")
    }

    @Test("RFC 1321: MD5(\"message digest\") == f96b697d7cb7938d525a2f31aaf161d0")
    func md5MessageDigest() {
        #expect("message digest".md5String == "f96b697d7cb7938d525a2f31aaf161d0")
    }

    @Test("RFC 1321: MD5(a-z) == c3fcd3d76192e4007dfb496cca67e13b")
    func md5Alphabet() {
        #expect("abcdefghijklmnopqrstuvwxyz".md5String == "c3fcd3d76192e4007dfb496cca67e13b")
    }

    @Test("RFC 1321: MD5(A-Za-z0-9) == d174ab98d277d9f5a5611c2c9f419d9f")
    func md5Alphanumeric() {
        #expect(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".md5String
                == "d174ab98d277d9f5a5611c2c9f419d9f"
        )
    }

    @Test("RFC 1321: MD5(8x\"1234567890\") == 57edf4a22be3c955ac49da2e2107b67a")
    func md5LongMessage() {
        let payload = String(repeating: "1234567890", count: 8)
        #expect(payload.md5String == "57edf4a22be3c955ac49da2e2107b67a")
    }

    @Test("md5String is deterministic across repeat calls")
    func md5Deterministic() {
        let s = "Daring Fireball — https://daringfireball.net/2025/03/test_article"
        let h1 = s.md5String
        let h2 = s.md5String
        #expect(h1 == h2)
        #expect(h1.count == 32)
    }

    @Test("md5String handles Unicode (UTF-8 byte sequence, not Apple-specific normalization)")
    func md5Unicode() {
        // "é" is 0xC3 0xA9 in UTF-8 → MD5 of those two bytes.
        // Verified against `printf 'é' | md5sum`.
        #expect("é".md5String == "66ddcd97cfdeabb2f6fb8a999b4bc76f")
    }

    @Test("Notification.Name.lowMemory matches upstream RSCore string literal")
    func lowMemoryNotificationNameRoundTrip() {
        // Upstream RSCore.AppNotifications declares the same
        // name with the same raw string; matching the literal
        // means observers registered on either side route the
        // same notification.
        #expect(Notification.Name.lowMemory.rawValue == "LowMemoryNotification")
    }

    @Test("collapsingWhitespace trims ASCII whitespace and preserves non-ASCII text")
    func collapsingWhitespace() {
        #expect("".collapsingWhitespace == "")
        #expect("   hello   ".collapsingWhitespace == "hello")
        #expect("one \n\t two\r\nthree".collapsingWhitespace == "one two three")
        let accented = "Caf\u{00e9}   r\u{00e9}sum\u{00e9}"
        #expect(accented.collapsingWhitespace == "Caf\u{00e9} r\u{00e9}sum\u{00e9}")

        let nonBreakingSpace = "\u{00a0}"
        #expect("a\(nonBreakingSpace)b".collapsingWhitespace == "a\(nonBreakingSpace)b")
    }

    @Test("NSAttributedString simpleHTML exposes visible text")
    func simpleHTMLAttributedString() {
        let attributed = NSAttributedString(simpleHTML: "<b>Hello</b> &amp; <q>world</q>")
        #expect(attributed.string.contains("Hello & "))
        #expect(attributed.string.contains("world"))
    }

    @Test("postOnMainThread asynchronously delivers a notification")
    func postOnMainThreadDeliversNotification() async {
        let name = Notification.Name("QuillRSCoreShimTests.postOnMainThread.\(UUID().uuidString)")
        var observer: NSObjectProtocol?

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notification in
                #expect(notification.name == name)
                continuation.resume()
            }

            NotificationCenter.default.postOnMainThread(name: name, object: nil)
        }

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @Test("Platform.isRunningUnitTests returns true under XCTest")
    func platformIsRunningUnitTestsUnderXCTest() {
        // The Quill test runner injects XCTestConfigurationFilePath
        // (XCTest) or SWIFT_TESTING_ENABLED (swift-testing). At
        // least one is set whenever this assertion executes.
        let env = ProcessInfo.processInfo.environment
        let testRunnerSignalSet =
            env["XCTestConfigurationFilePath"] != nil ||
            env["SWIFT_TESTING_ENABLED"] != nil
        if testRunnerSignalSet {
            #expect(Platform.isRunningUnitTests)
        } else {
            // If neither env var is set in this test runner, the
            // shim returns false (Articles' AuthorCache would then
            // proceed with the lowMemory registration — which is
            // its production behavior).
            #expect(!Platform.isRunningUnitTests)
        }
    }
}
