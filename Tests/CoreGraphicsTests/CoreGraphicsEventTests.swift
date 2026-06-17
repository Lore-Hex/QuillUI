import CoreGraphics
import Testing

struct CoreGraphicsEventTests {
    @Test("CGEvent keyboard unicode strings round-trip and truncate")
    func keyboardUnicodeStringsRoundTripAndTruncate() throws {
        let source = try #require(CGEventSource(stateID: .combinedSessionState))
        let event = try #require(CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true))
        #expect(event.source === source)
        #expect(event.virtualKey == 8)
        #expect(event.keyDown)

        let unicode: [UInt16] = [0x0041, 0x03A9, 0x2665]
        unicode.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }

        var actualLength = 0
        var truncated = [UInt16](repeating: 0, count: 2)
        truncated.withUnsafeMutableBufferPointer { buffer in
            event.keyboardGetUnicodeString(
                maxStringLength: buffer.count,
                actualStringLength: &actualLength,
                unicodeString: buffer.baseAddress
            )
        }
        #expect(actualLength == unicode.count)
        #expect(truncated == Array(unicode.prefix(2)))

        event.keyboardSetUnicodeString(stringLength: 0, unicodeString: nil)
        actualLength = -1
        event.keyboardGetUnicodeString(
            maxStringLength: 0,
            actualStringLength: &actualLength,
            unicodeString: nil
        )
        #expect(actualLength == 0)
    }
}
