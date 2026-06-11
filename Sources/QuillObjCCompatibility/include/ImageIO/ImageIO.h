#ifndef QUILL_OBJC_IMAGEIO_H
#define QUILL_OBJC_IMAGEIO_H

#include <AppKit/AppKit.h>

#include <stddef.h>
#include <stdint.h>

typedef const void *CGImageSourceRef;
typedef int32_t CGImageSourceStatus;

static const CGImageSourceStatus kCGImageStatusComplete = 0;

#if defined(__OBJC__)
static NSString * const kCGImageSourceTypeIdentifierHint = @"kCGImageSourceTypeIdentifierHint";
static NSString * const kCGImagePropertyGIFDictionary = @"{GIF}";
static NSString * const kCGImagePropertyGIFUnclampedDelayTime = @"UnclampedDelayTime";
static NSString * const kCGImagePropertyGIFDelayTime = @"DelayTime";
static NSString * const kUTTypeGIF = @"com.compuserve.gif";
#else
static const CFStringRef kCGImageSourceTypeIdentifierHint = CFSTR("kCGImageSourceTypeIdentifierHint");
static const CFStringRef kCGImagePropertyGIFDictionary = CFSTR("{GIF}");
static const CFStringRef kCGImagePropertyGIFUnclampedDelayTime = CFSTR("UnclampedDelayTime");
static const CFStringRef kCGImagePropertyGIFDelayTime = CFSTR("DelayTime");
static const CFStringRef kUTTypeGIF = CFSTR("com.compuserve.gif");
#endif

static inline CGImageSourceRef CGImageSourceCreateWithData(CFDataRef data, CFDictionaryRef options) {
    (void)options;
    return (CGImageSourceRef)data;
}

static inline CGImageSourceStatus CGImageSourceGetStatus(CGImageSourceRef source) {
    (void)source;
    return kCGImageStatusComplete;
}

static inline size_t CGImageSourceGetCount(CGImageSourceRef source) {
    (void)source;
    return 0;
}

static inline CGImageRef CGImageSourceCreateImageAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options) {
    (void)source;
    (void)index;
    (void)options;
    return NULL;
}

static inline CFDictionaryRef CGImageSourceCopyPropertiesAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options) {
    (void)source;
    (void)index;
    (void)options;
    return NULL;
}

#endif
