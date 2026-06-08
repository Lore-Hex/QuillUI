#ifndef QUILL_OBJC_COREFOUNDATION_H
#define QUILL_OBJC_COREFOUNDATION_H

#include <stdbool.h>
#include <stdint.h>

typedef signed long CFIndex;
typedef uint32_t CFStringEncoding;
typedef const void *CFAllocatorRef;
typedef const struct __CFString *CFStringRef;

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

#endif
