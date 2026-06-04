import Foundation
import Testing
@testable import QuillRSCoreShim

/// Pins the vendored RSCore `Array` helpers: `subscript(safe:)` (bounds-checked
/// access) and `chunked(into:)` (split into fixed-size sub-arrays).
@Suite("QuillRSCoreShim — Array+RSCore")
struct ArrayRSCoreTests {

    @Test("subscript(safe:) returns the element in range and nil out of range")
    func safeSubscript() {
        let xs = [10, 20, 30]
        #expect(xs[safe: 0] == 10)
        #expect(xs[safe: 2] == 30)
        #expect(xs[safe: 3] == nil)
        #expect(xs[safe: -1] == nil)
        #expect([Int]()[safe: 0] == nil)
    }

    @Test("chunked(into:) splits into fixed-size sub-arrays, last may be short")
    func chunked() {
        #expect([1, 2, 3, 4, 5].chunked(into: 2) == [[1, 2], [3, 4], [5]])
        #expect([1, 2, 3, 4].chunked(into: 2) == [[1, 2], [3, 4]])
    }

    @Test("chunked(into:) handles empty and over-sized chunks")
    func chunkedEdges() {
        #expect([Int]().chunked(into: 3) == [])
        #expect([1, 2].chunked(into: 5) == [[1, 2]])
    }
}
