#ifndef QUILL_OBJC_COREFOUNDATION_H
#define QUILL_OBJC_COREFOUNDATION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>

#ifndef __has_attribute
#define __has_attribute(x) 0
#endif

#ifndef CF_BRIDGED_TYPE
#if defined(__OBJC__) && __has_attribute(objc_bridge)
#define CF_BRIDGED_TYPE(T) __attribute__((objc_bridge(T)))
#else
#define CF_BRIDGED_TYPE(T)
#endif
#endif

#if defined(__OBJC__)
@class NSString;
#endif

typedef signed long CFIndex;
typedef signed int SInt32;
typedef double Float64;
typedef bool Boolean;
typedef double CFAbsoluteTime;
typedef uint32_t CFOptionFlags;
typedef uint32_t CFStringEncoding;
typedef const void *CFAllocatorRef;
typedef const void *CFTypeRef;
typedef const struct __CFData *CFDataRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef struct __CFDictionary *CFMutableDictionaryRef;
#if defined(__OBJC__)
typedef const struct CF_BRIDGED_TYPE(NSString) __CFString *CFStringRef;
#else
typedef const struct __CFString *CFStringRef;
#endif
typedef const struct __CFURL *CFURLRef;
typedef const struct __CFArray *CFArrayRef;
typedef const struct __CFNumber *CFNumberRef;

#ifndef CF_INLINE
#define CF_INLINE static inline
#endif

#if defined(__OBJC__)
@class NSMutableString;
@class NSDictionary;
@class NSURL;

typedef NSMutableString *CFMutableStringRef;
typedef NSDictionary *CFDictionary;
typedef NSURL *CFURL;
#else
typedef struct __CFString *CFMutableStringRef;
#endif

#ifndef QUILL_OBJC_UINT8_TYPEDEF
#define QUILL_OBJC_UINT8_TYPEDEF
typedef uint8_t UInt8;
#endif

typedef struct {
    CFIndex location;
    CFIndex length;
} CFRange;

CF_INLINE CFRange CFRangeMake(CFIndex loc, CFIndex len) {
    CFRange range;
    range.location = loc;
    range.length = len;
    return range;
}

static const CFStringEncoding kCFStringEncodingInvalidId = 0xffffffffU;
static const CFStringEncoding kCFStringEncodingMacRoman = 0U;
static const CFStringEncoding kCFStringEncodingUTF16LE = 0x14000100U;
static const CFStringEncoding kCFStringEncodingUTF8 = 0x08000100U;
static const CFAllocatorRef kCFAllocatorDefault = NULL;
static const CFAbsoluteTime kCFAbsoluteTimeIntervalSince1970 = 978307200.0;
static const int kCFNumberSInt64Type = 4;
static const CFStringRef kCFStringTransformStripCombiningMarks = (CFStringRef)"kCFStringTransformStripCombiningMarks";
static const CFStringRef kCFStringTransformToLatin = (CFStringRef)"kCFStringTransformToLatin";
#if defined(__OBJC__)
static NSString * const kCFStreamSSLIsServer = @"kCFStreamSSLIsServer";
static NSString * const kCFStreamSSLPeerName = @"kCFStreamSSLPeerName";
static NSString * const kCFStreamSSLAllowsAnyRoot = @"kCFStreamSSLAllowsAnyRoot";
static NSString * const kCFStreamSSLAllowsExpiredRoots = @"kCFStreamSSLAllowsExpiredRoots";
static NSString * const kCFStreamSSLValidatesCertificateChain = @"kCFStreamSSLValidatesCertificateChain";
static NSString * const kCFStreamSSLAllowsExpiredCertificates = @"kCFStreamSSLAllowsExpiredCertificates";
static NSString * const kCFStreamSSLCertificates = @"kCFStreamSSLCertificates";
static NSString * const kCFStreamSSLLevel = @"kCFStreamSSLLevel";
static NSString * const kCFStreamSocketSecurityLevelSSLv2 = @"kCFStreamSocketSecurityLevelSSLv2";
static NSString * const kCFStreamSocketSecurityLevelSSLv3 = @"kCFStreamSocketSecurityLevelSSLv3";
static NSString * const kCFStreamSocketSecurityLevelTLSv1 = @"kCFStreamSocketSecurityLevelTLSv1";
static NSString * const kCFStreamSocketSecurityLevelNegotiatedSSL = @"kCFStreamSocketSecurityLevelNegotiatedSSL";
#else
static const CFStringRef kCFStreamSSLIsServer = (CFStringRef)"kCFStreamSSLIsServer";
static const CFStringRef kCFStreamSSLPeerName = (CFStringRef)"kCFStreamSSLPeerName";
static const CFStringRef kCFStreamSSLAllowsAnyRoot = (CFStringRef)"kCFStreamSSLAllowsAnyRoot";
static const CFStringRef kCFStreamSSLAllowsExpiredRoots = (CFStringRef)"kCFStreamSSLAllowsExpiredRoots";
static const CFStringRef kCFStreamSSLValidatesCertificateChain = (CFStringRef)"kCFStreamSSLValidatesCertificateChain";
static const CFStringRef kCFStreamSSLAllowsExpiredCertificates = (CFStringRef)"kCFStreamSSLAllowsExpiredCertificates";
static const CFStringRef kCFStreamSSLCertificates = (CFStringRef)"kCFStreamSSLCertificates";
static const CFStringRef kCFStreamSSLLevel = (CFStringRef)"kCFStreamSSLLevel";
static const CFStringRef kCFStreamSocketSecurityLevelSSLv2 = (CFStringRef)"kCFStreamSocketSecurityLevelSSLv2";
static const CFStringRef kCFStreamSocketSecurityLevelSSLv3 = (CFStringRef)"kCFStreamSocketSecurityLevelSSLv3";
static const CFStringRef kCFStreamSocketSecurityLevelTLSv1 = (CFStringRef)"kCFStreamSocketSecurityLevelTLSv1";
static const CFStringRef kCFStreamSocketSecurityLevelNegotiatedSSL = (CFStringRef)"kCFStreamSocketSecurityLevelNegotiatedSSL";
#endif

#if defined(__OBJC__)
#ifndef CFSTR
#define CFSTR(cStr) ((__bridge CFStringRef)@cStr)
#endif
#else
#ifndef CFSTR
#define CFSTR(cStr) ((CFStringRef)cStr)
#endif
#endif

#ifndef CF_RETURNS_RETAINED
#define CF_RETURNS_RETAINED
#endif

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

static inline CFStringEncoding CFStringConvertIANACharSetNameToEncoding(CFStringRef theString) {
    (void)theString;
    return kCFStringEncodingUTF8;
}

static inline bool CFStringTransform(
    CFMutableStringRef string,
    CFRange *range,
    CFStringRef transform,
    bool reverse
) {
    (void)string;
    (void)range;
    (void)transform;
    (void)reverse;
    return true;
}

static inline const UInt8 *CFDataGetBytePtr(CFDataRef theData) {
    (void)theData;
    return NULL;
}

static inline CFIndex CFArrayGetCount(CFArrayRef theArray) {
    (void)theArray;
    return 0;
}

static inline const void *CFArrayGetValueAtIndex(CFArrayRef theArray, CFIndex idx) {
    (void)theArray;
    (void)idx;
    return NULL;
}

static inline bool CFEqual(const void *cf1, const void *cf2) {
    return cf1 == cf2;
}

#if defined(__OBJC__)
static inline const void *QuillCFDictionaryGetValue(CFDictionaryRef theDict, id key) {
    (void)theDict;
    (void)key;
    return NULL;
}
#ifndef CFDictionaryGetValue
#define CFDictionaryGetValue(theDict, key) QuillCFDictionaryGetValue((theDict), (key))
#endif
#else
static inline const void *CFDictionaryGetValue(CFDictionaryRef theDict, const void *key) {
    (void)theDict;
    (void)key;
    return NULL;
}
#endif

static inline bool CFNumberGetValue(CFNumberRef number, int theType, void *valuePtr) {
    (void)number;
    (void)theType;
    if (valuePtr != NULL) {
        *(int64_t *)valuePtr = 0;
    }
    return false;
}

static inline CFAbsoluteTime CFAbsoluteTimeGetCurrent(void) {
    return (CFAbsoluteTime)time(NULL) - kCFAbsoluteTimeIntervalSince1970;
}

static inline void CFRelease(const void *cf) {
    (void)cf;
}

static inline const void *CFRetain(const void *cf) {
    return cf;
}

#if defined(__OBJC__)
static inline CFTypeRef CFBridgingRetain(id object) {
    return (__bridge CFTypeRef)object;
}

static inline id CFBridgingRelease(CFTypeRef cf) {
    return (__bridge id)cf;
}

static inline CFTypeRef CFAutorelease(CFTypeRef cf) {
    return cf;
}
#endif

#endif
