import CoreGraphics
import Testing

struct CoreGraphicsEventTests {
    @Test("CGEventFlags use Apple modifier raw masks")
    func eventFlagsUseAppleModifierRawMasks() {
        #expect(CGEventFlags.maskAlphaShift.rawValue == 1 << 16)
        #expect(CGEventFlags.maskShift.rawValue == 1 << 17)
        #expect(CGEventFlags.maskControl.rawValue == 1 << 18)
        #expect(CGEventFlags.maskAlternate.rawValue == 1 << 19)
        #expect(CGEventFlags.maskCommand.rawValue == 1 << 20)
        #expect(CGEventFlags.maskNumericPad.rawValue == 1 << 21)
        #expect(CGEventFlags.maskHelp.rawValue == 1 << 22)
        #expect(CGEventFlags.maskSecondaryFn.rawValue == 1 << 23)

        let shortcut: CGEventFlags = [.maskCommand, .maskShift]
        #expect(shortcut.contains(.maskCommand))
        #expect(shortcut.contains(.maskShift))
        #expect(!shortcut.contains(.maskAlternate))
        #expect(shortcut.rawValue == (1 << 20) | (1 << 17))
    }

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
