#ifndef QUILL_OBJC_COREFOUNDATION_H
#define QUILL_OBJC_COREFOUNDATION_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

typedef signed long CFIndex;
typedef uint32_t CFOptionFlags;
typedef uint32_t CFStringEncoding;
typedef const void *CFAllocatorRef;
typedef const struct __CFData *CFDataRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef const struct __CFString *CFStringRef;
typedef const struct __CFURL *CFURLRef;

#if defined(__OBJC__)
@class NSDictionary;
@class NSURL;

typedef NSDictionary *CFDictionary;
typedef NSURL *CFURL;
#endif

#ifndef QUILL_OBJC_UINT8_TYPEDEF
#define QUILL_OBJC_UINT8_TYPEDEF
typedef uint8_t UInt8;
#endif

typedef struct {
    CFIndex location;
    CFIndex length;
} CFRange;

static inline CFRange CFRangeMake(CFIndex location, CFIndex length) {
    CFRange range = { location, length };
    return range;
}

static const CFStringEncoding kCFStringEncodingUTF16LE = 0x14000100U;

#ifndef FALSE
#define FALSE false
#endif

#ifndef TRUE
#define TRUE true
#endif

CFIndex CFStringGetLength(CFStringRef theString);
CFIndex CFStringGetBytes(
    CFStringRef theString,
    CFRange range,
    CFStringEncoding encoding,
    UInt8 lossByte,
    bool isExternalRepresentation,
    UInt8 *buffer,
    CFIndex maxBufLen,
    CFIndex *usedBufLen
);
CFStringRef CFStringCreateWithBytes(
    CFAllocatorRef alloc,
    const UInt8 *bytes,
    CFIndex numBytes,
    CFStringEncoding encoding,
    bool isExternalRepresentation
);

static inline const UInt8 *CFDataGetBytePtr(CFDataRef theData) {
    (void)theData;
    return NULL;
}

static inline void CFRelease(const void *cf) {
    (void)cf;
}

#endif
