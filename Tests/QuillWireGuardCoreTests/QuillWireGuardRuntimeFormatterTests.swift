import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard runtime formatter")
struct QuillWireGuardRuntimeFormatterTests {

    @Test("transfer text uses binary units (exact bytes < 1 KiB, 2 decimals above)")
    func transferText() {
        #expect(QuillWireGuardRuntimeFormatter.transferText(0) == "0 B")
        #expect(QuillWireGuardRuntimeFormatter.transferText(512) == "512 B")
        #expect(QuillWireGuardRuntimeFormatter.transferText(1023) == "1023 B")
        #expect(QuillWireGuardRuntimeFormatter.transferText(1024) == "1.00 KiB")
        #expect(QuillWireGuardRuntimeFormatter.transferText(1536) == "1.50 KiB")
        #expect(QuillWireGuardRuntimeFormatter.transferText(1_048_576) == "1.00 MiB")
        #expect(QuillWireGuardRuntimeFormatter.transferText(1_572_864) == "1.50 MiB")
        #expect(QuillWireGuardRuntimeFormatter.transferText(1_073_741_824) == "1.00 GiB")
    }

    @Test("handshake text is relative; Never for nil, Just now for recent")
    func handshakeText() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let f = QuillWireGuardRuntimeFormatter.handshakeText
        #expect(f(nil, now) == "Never")
        #expect(f(now, now) == "Just now")
        #expect(f(now.addingTimeInterval(-2), now) == "Just now")
        #expect(f(now.addingTimeInterval(-30), now) == "30 seconds ago")
        #expect(f(now.addingTimeInterval(-60), now) == "1 minute ago")
        #expect(f(now.addingTimeInterval(-120), now) == "2 minutes ago")
        #expect(f(now.addingTimeInterval(-3600), now) == "1 hour ago")
        #expect(f(now.addingTimeInterval(-7200), now) == "2 hours ago")
        #expect(f(now.addingTimeInterval(-90_000), now) == "1 day ago")
    }
}
