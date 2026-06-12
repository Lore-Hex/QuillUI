#ifndef QUILL_OBJC_CARBON_H
#define QUILL_OBJC_CARBON_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdint.h>

typedef int32_t OSStatus;

#ifndef QUILL_OBJC_UINT16_TYPEDEF
#define QUILL_OBJC_UINT16_TYPEDEF
typedef uint16_t UInt16;
#endif

#ifndef QUILL_OBJC_UINT32_TYPEDEF
#define QUILL_OBJC_UINT32_TYPEDEF
typedef uint32_t UInt32;
#endif

typedef uint16_t UniChar;
typedef uint32_t UniCharCount;
typedef uint32_t OptionBits;
typedef struct UCKeyboardLayout UCKeyboardLayout;
typedef const void *TISInputSourceRef;

#ifndef QUILL_OBJC_NOERR_DEFINED
#define QUILL_OBJC_NOERR_DEFINED
#ifndef QUILL_OBJC_NOERR_DEFINED
#define QUILL_OBJC_NOERR_DEFINED
#ifndef noErr
#define noErr ((OSStatus)0)
#endif
#endif
#endif

static const UInt32 cmdKey = 1U << 8;
static const UInt32 shiftKey = 1U << 9;
static const UInt32 alphaLock = 1U << 10;
static const UInt32 optionKey = 1U << 11;
static const UInt32 controlKey = 1U << 12;

static const UInt32 kUCKeyActionDown = 0;
static const CFStringRef kAXTrustedCheckOptionPrompt = (CFStringRef)"AXTrustedCheckOptionPrompt";
static const CFStringRef kTISPropertyUnicodeKeyLayoutData = (CFStringRef)"UnicodeKeyLayoutData";
static const CFStringRef kTISPropertyInputSourceLanguages = (CFStringRef)"InputSourceLanguages";

enum {
    kVK_A = 0,
    kVK_S = 1,
    kVK_D = 2,
    kVK_F = 3,
    kVK_H = 4,
    kVK_G = 5,
    kVK_Z = 6,
    kVK_X = 7,
    kVK_C = 8,
    kVK_V = 9,
    kVK_B = 11,
    kVK_Q = 12,
    kVK_W = 13,
    kVK_E = 14,
    kVK_R = 15,
    kVK_Y = 16,
    kVK_T = 17,
    kVK_1 = 18,
    kVK_2 = 19,
    kVK_3 = 20,
    kVK_4 = 21,
    kVK_6 = 22,
    kVK_5 = 23,
    kVK_Equal = 24,
    kVK_9 = 25,
    kVK_7 = 26,
    kVK_Minus = 27,
    kVK_8 = 28,
    kVK_0 = 29,
    kVK_RightBracket = 30,
    kVK_O = 31,
    kVK_U = 32,
    kVK_LeftBracket = 33,
    kVK_I = 34,
    kVK_P = 35,
    kVK_Return = 36,
    kVK_L = 37,
    kVK_J = 38,
    kVK_Quote = 39,
    kVK_K = 40,
    kVK_Semicolon = 41,
    kVK_Backslash = 42,
    kVK_Comma = 43,
    kVK_Slash = 44,
    kVK_N = 45,
    kVK_M = 46,
    kVK_Period = 47,
    kVK_Tab = 48,
    kVK_Space = 49,
    kVK_Grave = 50,
    kVK_Delete = 51,
    kVK_Escape = 53,
    kVK_Command = 55,
    kVK_Shift = 56,
    kVK_CapsLock = 57,
    kVK_Option = 58,
    kVK_Control = 59,
    kVK_RightShift = 60,
    kVK_RightOption = 61,
    kVK_RightControl = 62,
    kVK_Function = 63,
    kVK_F17 = 64,
    kVK_VolumeUp = 72,
    kVK_VolumeDown = 73,
    kVK_Mute = 74,
    kVK_F18 = 79,
    kVK_F19 = 80,
    kVK_F20 = 90,
    kVK_F5 = 96,
    kVK_F6 = 97,
    kVK_F7 = 98,
    kVK_F3 = 99,
    kVK_F8 = 100,
    kVK_F9 = 101,
    kVK_F11 = 103,
    kVK_F13 = 105,
    kVK_F16 = 106,
    kVK_F14 = 107,
    kVK_F10 = 109,
    kVK_F12 = 111,
    kVK_F15 = 113,
    kVK_Home = 115,
    kVK_PageUp = 116,
    kVK_ForwardDelete = 117,
    kVK_F4 = 118,
    kVK_End = 119,
    kVK_F2 = 120,
    kVK_PageDown = 121,
    kVK_F1 = 122,
    kVK_LeftArrow = 123,
    kVK_RightArrow = 124,
    kVK_DownArrow = 125,
    kVK_UpArrow = 126
};

static inline TISInputSourceRef TISCopyCurrentASCIICapableKeyboardLayoutInputSource(void) {
    return NULL;
}

static inline TISInputSourceRef TISCopyCurrentKeyboardInputSource(void) {
    return NULL;
}

static inline CFArrayRef TISCreateInputSourceList(CFDictionaryRef properties, bool includeAllInstalled) {
    (void)properties;
    (void)includeAllInstalled;
    return NULL;
}

static inline const void *TISGetInputSourceProperty(TISInputSourceRef inputSource, CFStringRef propertyKey) {
    (void)inputSource;
    (void)propertyKey;
    return NULL;
}

static inline UInt32 LMGetKbdType(void) {
    return 0;
}

static inline OSStatus UCKeyTranslate(
    const UCKeyboardLayout *keyLayoutPtr,
    UInt16 virtualKeyCode,
    UInt16 keyAction,
    UInt32 modifierKeyState,
    UInt32 keyboardType,
    OptionBits keyTranslateOptions,
    UInt32 *deadKeyState,
    UniCharCount maxStringLength,
    UniCharCount *actualStringLength,
    UniChar unicodeString[]
) {
    (void)keyLayoutPtr;
    (void)virtualKeyCode;
    (void)keyAction;
    (void)modifierKeyState;
    (void)keyboardType;
    (void)keyTranslateOptions;
    (void)deadKeyState;
    (void)maxStringLength;
    (void)unicodeString;
    if (actualStringLength != NULL) {
        *actualStringLength = 0;
    }
    return noErr;
}

static inline bool AXIsProcessTrustedWithOptions(CFDictionaryRef options) {
    (void)options;
    return false;
}

#endif
