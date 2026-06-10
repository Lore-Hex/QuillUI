#ifndef QUILL_OBJC_COREVIDEO_H
#define QUILL_OBJC_COREVIDEO_H

#include <CoreFoundation/CoreFoundation.h>
#include <OpenGL/gl.h>
#include <stdint.h>
#include <stddef.h>

typedef int32_t CVReturn;
typedef uint64_t CVOptionFlags;
typedef uint32_t OSType;
typedef struct __CVBuffer *CVBufferRef;
typedef CVBufferRef CVImageBufferRef;
typedef CVImageBufferRef CVPixelBufferRef;
typedef CVPixelBufferRef CVPixelBuffer;
typedef struct __CVPixelBufferPool *CVPixelBufferPoolRef;
typedef struct __CVDisplayLink *CVDisplayLinkRef;
typedef void *CVOpenGLTextureCacheRef;
typedef void *CVOpenGLTextureRef;
typedef uint32_t FourCharCode;

typedef struct {
    uint32_t version;
    int32_t videoTimeScale;
    int64_t videoTime;
    uint64_t hostTime;
    double rateScalar;
    int64_t videoRefreshPeriod;
    uint64_t smpteTime;
    uint64_t flags;
    uint64_t reserved;
} CVTimeStamp;

enum {
    kCVReturnSuccess = 0,
    kCVReturnError = -6660,
    kCVReturnWouldExceedAllocationThreshold = -6689,
};

enum {
    kCVPixelFormatType_32ARGB = 0x00000020,
    kCVPixelFormatType_32BGRA = 0x42475241,
};

enum {
    kCVPixelBufferLock_ReadOnly = 1,
};

#if defined(__OBJC__)
static NSString * const kCVPixelBufferIOSurfacePropertiesKey = @"IOSurfaceProperties";
static NSString * const kCVPixelBufferPixelFormatTypeKey = @"PixelFormatType";
static NSString * const kCVPixelBufferWidthKey = @"Width";
static NSString * const kCVPixelBufferHeightKey = @"Height";
static NSString * const kCVPixelBufferCGImageCompatibilityKey = @"CGImageCompatibility";
static NSString * const kCVPixelBufferCGBitmapContextCompatibilityKey = @"CGBitmapContextCompatibility";
static NSString * const kCVPixelFormatOpenGLCompatibility = @"OpenGLCompatibility";
static NSString * const kCVPixelBufferPoolMinimumBufferCountKey = @"MinimumBufferCount";
static NSString * const kCVPixelBufferPoolAllocationThresholdKey = @"AllocationThreshold";
#else
static const CFStringRef kCVPixelBufferIOSurfacePropertiesKey = (CFStringRef)"IOSurfaceProperties";
static const CFStringRef kCVPixelBufferPixelFormatTypeKey = (CFStringRef)"PixelFormatType";
static const CFStringRef kCVPixelBufferWidthKey = (CFStringRef)"Width";
static const CFStringRef kCVPixelBufferHeightKey = (CFStringRef)"Height";
static const CFStringRef kCVPixelBufferCGImageCompatibilityKey = (CFStringRef)"CGImageCompatibility";
static const CFStringRef kCVPixelBufferCGBitmapContextCompatibilityKey = (CFStringRef)"CGBitmapContextCompatibility";
static const CFStringRef kCVPixelFormatOpenGLCompatibility = (CFStringRef)"OpenGLCompatibility";
static const CFStringRef kCVPixelBufferPoolMinimumBufferCountKey = (CFStringRef)"MinimumBufferCount";
static const CFStringRef kCVPixelBufferPoolAllocationThresholdKey = (CFStringRef)"AllocationThreshold";
#endif

static inline CVReturn CVPixelBufferLockBaseAddress(CVPixelBufferRef pixelBuffer, CVOptionFlags lockFlags) {
    (void)pixelBuffer;
    (void)lockFlags;
    return kCVReturnSuccess;
}

static inline CVReturn CVPixelBufferUnlockBaseAddress(CVPixelBufferRef pixelBuffer, CVOptionFlags unlockFlags) {
    (void)pixelBuffer;
    (void)unlockFlags;
    return kCVReturnSuccess;
}

static inline void *CVPixelBufferGetBaseAddress(CVPixelBufferRef pixelBuffer) {
    (void)pixelBuffer;
    return NULL;
}

static inline size_t CVPixelBufferGetBytesPerRow(CVPixelBufferRef pixelBuffer) {
    (void)pixelBuffer;
    return 0;
}

static inline size_t CVPixelBufferGetWidth(CVPixelBufferRef pixelBuffer) {
    (void)pixelBuffer;
    return 0;
}

static inline size_t CVPixelBufferGetHeight(CVPixelBufferRef pixelBuffer) {
    (void)pixelBuffer;
    return 0;
}

static inline CVReturn CVPixelBufferPoolCreatePixelBuffer(CFAllocatorRef allocator, CVPixelBufferPoolRef pixelBufferPool, CVPixelBufferRef *pixelBufferOut) {
    (void)allocator;
    (void)pixelBufferPool;
    if (pixelBufferOut != NULL) {
        *pixelBufferOut = NULL;
    }
    return kCVReturnError;
}

static inline CVReturn CVPixelBufferCreate(
    CFAllocatorRef allocator,
    size_t width,
    size_t height,
    OSType pixelFormatType,
    CFDictionaryRef pixelBufferAttributes,
    CVPixelBufferRef *pixelBufferOut
) {
    (void)allocator;
    (void)width;
    (void)height;
    (void)pixelFormatType;
    (void)pixelBufferAttributes;
    if (pixelBufferOut != NULL) {
        *pixelBufferOut = NULL;
    }
    return kCVReturnError;
}

static inline CVReturn CVPixelBufferPoolCreate(
    CFAllocatorRef allocator,
    CFDictionaryRef poolAttributes,
    CFDictionaryRef pixelBufferAttributes,
    CVPixelBufferPoolRef *poolOut
) {
    (void)allocator;
    (void)poolAttributes;
    (void)pixelBufferAttributes;
    if (poolOut != NULL) {
        *poolOut = (CVPixelBufferPoolRef)1;
    }
    return kCVReturnSuccess;
}

static inline CVReturn CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
    CFAllocatorRef allocator,
    CVPixelBufferPoolRef pixelBufferPool,
    CFDictionaryRef auxiliaryAttributes,
    CVPixelBufferRef *pixelBufferOut
) {
    (void)allocator;
    (void)pixelBufferPool;
    (void)auxiliaryAttributes;
    if (pixelBufferOut != NULL) {
        *pixelBufferOut = NULL;
    }
    return kCVReturnWouldExceedAllocationThreshold;
}

static inline void CVBufferRelease(CVBufferRef buffer) {
    (void)buffer;
}

static inline CVReturn CVOpenGLTextureCacheCreate(
    CFAllocatorRef allocator,
    CFDictionaryRef cacheAttributes,
    CGLContextObj cglContext,
    CGLPixelFormatObj cglPixelFormat,
    CFDictionaryRef textureAttributes,
    CVOpenGLTextureCacheRef *cacheOut
) {
    (void)allocator;
    (void)cacheAttributes;
    (void)cglContext;
    (void)cglPixelFormat;
    (void)textureAttributes;
    if (cacheOut != NULL) {
        *cacheOut = (CVOpenGLTextureCacheRef)1;
    }
    return kCVReturnSuccess;
}

static inline CVReturn CVOpenGLTextureCacheCreateTextureFromImage(
    CFAllocatorRef allocator,
    CVOpenGLTextureCacheRef textureCache,
    CVImageBufferRef sourceImage,
    CFDictionaryRef attributes,
    CVOpenGLTextureRef *textureOut
) {
    (void)allocator;
    (void)textureCache;
    (void)sourceImage;
    (void)attributes;
    if (textureOut != NULL) {
        *textureOut = (CVOpenGLTextureRef)1;
    }
    return kCVReturnSuccess;
}

static inline void CVOpenGLTextureCacheFlush(CVOpenGLTextureCacheRef textureCache, CVOptionFlags options) {
    (void)textureCache;
    (void)options;
}

static inline GLenum CVOpenGLTextureGetTarget(CVOpenGLTextureRef image) {
    (void)image;
    return GL_TEXTURE_2D;
}

static inline GLuint CVOpenGLTextureGetName(CVOpenGLTextureRef image) {
    (void)image;
    return 0;
}

#endif
