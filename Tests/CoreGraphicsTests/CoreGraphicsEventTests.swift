import CoreGraphics
import Testing

struct CoreGraphicsEventTests {
    @Test("CGEvent type and mouse button enums use Apple raw values")
    func eventTypeAndMouseButtonEnumsUseAppleRawValues() {
        #expect(CGEventType.null.rawValue == 0)
        #expect(CGEventType.leftMouseDown.rawValue == 1)
        #expect(CGEventType.leftMouseUp.rawValue == 2)
        #expect(CGEventType.rightMouseDown.rawValue == 3)
        #expect(CGEventType.rightMouseUp.rawValue == 4)
        #expect(CGEventType.mouseMoved.rawValue == 5)
        #expect(CGEventType.leftMouseDragged.rawValue == 6)
        #expect(CGEventType.rightMouseDragged.rawValue == 7)
        #expect(CGEventType.keyDown.rawValue == 10)
        #expect(CGEventType.keyUp.rawValue == 11)
        #expect(CGEventType.flagsChanged.rawValue == 12)
        #expect(CGEventType.scrollWheel.rawValue == 22)
        #expect(CGEventType.tabletPointer.rawValue == 23)
        #expect(CGEventType.tabletProximity.rawValue == 24)
        #expect(CGEventType.otherMouseDown.rawValue == 25)
        #expect(CGEventType.otherMouseUp.rawValue == 26)
        #expect(CGEventType.otherMouseDragged.rawValue == 27)
        #expect(CGEventType.tapDisabledByTimeout.rawValue == 0xFFFF_FFFE)
        #expect(CGEventType.tapDisabledByUserInput.rawValue == 0xFFFF_FFFF)

        #expect(CGMouseButton.left.rawValue == 0)
        #expect(CGMouseButton.right.rawValue == 1)
        #expect(CGMouseButton.center.rawValue == 2)
    }

    @Test("CGEvent fields use Apple raw values")
    func eventFieldsUseAppleRawValues() {
        #expect(CGEventField.mouseEventNumber.rawValue == 0)
        #expect(CGEventField.mouseEventClickState.rawValue == 1)
        #expect(CGEventField.mouseEventPressure.rawValue == 2)
        #expect(CGEventField.mouseEventButtonNumber.rawValue == 3)
        #expect(CGEventField.mouseEventDeltaX.rawValue == 4)
        #expect(CGEventField.mouseEventDeltaY.rawValue == 5)
        #expect(CGEventField.keyboardEventAutorepeat.rawValue == 8)
        #expect(CGEventField.keyboardEventKeycode.rawValue == 9)
        #expect(CGEventField.keyboardEventKeyboardType.rawValue == 10)
        #expect(CGEventField.scrollWheelEventDeltaAxis1.rawValue == 11)
        #expect(CGEventField.scrollWheelEventDeltaAxis2.rawValue == 12)
        #expect(CGEventField.scrollWheelEventDeltaAxis3.rawValue == 13)
        #expect(CGEventField.scrollWheelEventFixedPtDeltaAxis1.rawValue == 93)
        #expect(CGEventField.scrollWheelEventFixedPtDeltaAxis2.rawValue == 94)
        #expect(CGEventField.scrollWheelEventFixedPtDeltaAxis3.rawValue == 95)
        #expect(CGEventField.scrollWheelEventPointDeltaAxis1.rawValue == 96)
        #expect(CGEventField.scrollWheelEventPointDeltaAxis2.rawValue == 97)
        #expect(CGEventField.scrollWheelEventPointDeltaAxis3.rawValue == 98)
    }

    @Test("CGEvent source state and tap enums use Apple raw values")
    func eventSourceStateAndTapEnumsUseAppleRawValues() {
        #expect(CGEventSourceStateID.privateState.rawValue == -1)
        #expect(CGEventSourceStateID.combinedSessionState.rawValue == 0)
        #expect(CGEventSourceStateID.hidSystemState.rawValue == 1)

        #expect(CGEventTapLocation.cghidEventTap.rawValue == 0)
        #expect(CGEventTapLocation.cgSessionEventTap.rawValue == 1)
        #expect(CGEventTapLocation.cgAnnotatedSessionEventTap.rawValue == 2)
    }

    @Test("CGEventFlags use Apple event and modifier raw masks")
    func eventFlagsUseAppleEventAndModifierRawMasks() {
        #expect(CGEventFlags.maskNonCoalesced.rawValue == 1 << 8)
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
        #expect(event.type == .keyDown)
        #expect(event.location == .zero)
        #expect(event.getIntegerValueField(.keyboardEventKeycode) == 8)

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

    @Test("CGEvent mouse initializer preserves source type location and fields")
    func mouseInitializerPreservesSourceTypeLocationAndFields() throws {
        let source = try #require(CGEventSource(stateID: .hidSystemState))
        let event = try #require(CGEvent(
            mouseEventSource: source,
            mouseType: .rightMouseDragged,
            mouseCursorPosition: CGPoint(x: 12.5, y: -3.25),
            mouseButton: .right
        ))

        #expect(event.source === source)
        #expect(event.type == .rightMouseDragged)
        #expect(event.location == CGPoint(x: 12.5, y: -3.25))
        #expect(event.getIntegerValueField(.mouseEventButtonNumber) == 1)
        #expect(event.getIntegerValueField(.mouseEventDeltaX) == 0)

        event.setIntegerValueField(.mouseEventDeltaX, value: -7)
        event.setIntegerValueField(.mouseEventClickState, value: 2)
        #expect(event.getIntegerValueField(.mouseEventDeltaX) == -7)
        #expect(event.getIntegerValueField(.mouseEventClickState) == 2)
    }
}
