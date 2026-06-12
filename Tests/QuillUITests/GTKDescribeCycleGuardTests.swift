import Testing

#if os(Linux)
@testable import BackendGTK4
import SwiftUI

@Suite("GTK describe cycle guard")
@MainActor
struct GTKDescribeCycleGuardTests {
    @Test("cyclic AnyView body records diagnostic chain")
    func cyclicAnyViewBodyRecordsDiagnosticChain() {
        let previousHandler = gtkDescribeDepthLimitExceededHandler
        var capturedNames: [String] = []

        gtkDescribeDepthLimitExceededHandler = { names in
            capturedNames = names
        }
        defer { gtkDescribeDepthLimitExceededHandler = previousHandler }

        _ = gtkDescribeView(Cyclic())

        #expect(capturedNames.count == 8)
        #expect(
            capturedNames.contains { $0.contains("Cyclic") },
            "Expected cycle chain to include Cyclic, got \(capturedNames.joined(separator: " -> "))"
        )
    }
}

private struct Cyclic: View {
    var body: some View {
        AnyView(Cyclic())
    }
}
#endif
