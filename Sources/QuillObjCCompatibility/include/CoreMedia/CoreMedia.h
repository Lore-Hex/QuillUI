#ifndef QUILL_OBJC_COREMEDIA_H
#define QUILL_OBJC_COREMEDIA_H

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreVideo/CoreVideo.h>
#include <stdint.h>
#include <stddef.h>

typedef int32_t OSStatus;
typedef int64_t CMTimeValue;
typedef int32_t CMTimeScale;
typedef uint32_t CMTimeFlags;
typedef int64_t CMTimeEpoch;
typedef int64_t CMItemCount;
typedef uint32_t CMVideoCodecType;

typedef const struct opaqueCMBlockBuffer *CMBlockBufferRef;
typedef const struct opaqueCMFormatDescription *CMFormatDescriptionRef;
typedef CMFormatDescriptionRef CMVideoFormatDescriptionRef;
typedef const struct opaqueCMSampleBuffer *CMSampleBufferRef;

typedef struct {
    CMTimeValue value;
    CMTimeScale timescale;
    CMTimeFlags flags;
    CMTimeEpoch epoch;
} CMTime;

typedef struct {
    int32_t width;
    int32_t height;
} CMVideoDimensions;

typedef struct {
    CMTime duration;
    CMTime presentationTimeStamp;
    CMTime decodeTimeStamp;
} CMSampleTimingInfo;

enum {
    kCMTimeFlags_Valid = 1UL << 0,
    kCMTimeFlags_HasBeenRounded = 1UL << 1,
    kCMTimeFlags_PositiveInfinity = 1UL << 2,
    kCMTimeFlags_NegativeInfinity = 1UL << 3,
    kCMTimeFlags_Indefinite = 1UL << 4,
    kCMTimeFlags_ImpliedValueFlagsMask = kCMTimeFlags_PositiveInfinity | kCMTimeFlags_NegativeInfinity | kCMTimeFlags_Indefinite,
};

#define QUILL_CM_FOURCC(a, b, c, d) ((CMVideoCodecType)((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d)))

enum {
    kCMVideoCodecType_H263 = QUILL_CM_FOURCC('h', '2', '6', '3'),
    kCMVideoCodecType_H264 = QUILL_CM_FOURCC('a', 'v', 'c', '1'),
    kCMVideoCodecType_MPEG1Video = QUILL_CM_FOURCC('m', 'p', '1', 'v'),
    kCMVideoCodecType_MPEG2Video = QUILL_CM_FOURCC('m', 'p', '2', 'v'),
    kCMVideoCodecType_MPEG4Video = QUILL_CM_FOURCC('m', 'p', '4', 'v'),
};

static const CMTime kCMTimeZero = {0, 1, kCMTimeFlags_Valid, 0};
static const CMTime kCMTimeInvalid = {0, 0, 0, 0};
static const CMTime kCMTimeIndefinite = {0, 0, kCMTimeFlags_Indefinite, 0};

static inline CMTime CMTimeMake(int64_t value, int32_t timescale) {
    CMTime time = { value, timescale, kCMTimeFlags_Valid, 0 };
    return time;
}

static inline CMTime CMTimeMakeWithSeconds(double seconds, int32_t preferredTimescale) {
    return CMTimeMake((int64_t)(seconds * (double)preferredTimescale), preferredTimescale);
}

static inline double CMTimeGetSeconds(CMTime time) {
    if (time.timescale == 0) {
        return 0.0;
    }
    return (double)time.value / (double)time.timescale;
}

static inline CMTime CMTimeAdd(CMTime lhs, CMTime rhs) {
    int32_t scale = lhs.timescale != 0 ? lhs.timescale : (rhs.timescale != 0 ? rhs.timescale : 1);
    double seconds = CMTimeGetSeconds(lhs) + CMTimeGetSeconds(rhs);
    return CMTimeMakeWithSeconds(seconds, scale);
}

static inline CMTime CMTimeSubtract(CMTime lhs, CMTime rhs) {
    int32_t scale = lhs.timescale != 0 ? lhs.timescale : (rhs.timescale != 0 ? rhs.timescale : 1);
    double seconds = CMTimeGetSeconds(lhs) - CMTimeGetSeconds(rhs);
    return CMTimeMakeWithSeconds(seconds, scale);
}

static inline int32_t CMTimeCompare(CMTime lhs, CMTime rhs) {
    double lhsSeconds = CMTimeGetSeconds(lhs);
    double rhsSeconds = CMTimeGetSeconds(rhs);
    if (lhsSeconds < rhsSeconds) {
        return -1;
    }
    if (lhsSeconds > rhsSeconds) {
        return 1;
    }
    return 0;
}

static inline CMVideoDimensions CMVideoFormatDescriptionGetDimensions(CMVideoFormatDescriptionRef videoDesc) {
    (void)videoDesc;
    CMVideoDimensions dimensions = {0, 0};
    return dimensions;
}

static inline OSStatus CMVideoFormatDescriptionCreateForImageBuffer(
    CFAllocatorRef allocator,
    CVImageBufferRef imageBuffer,
    CMVideoFormatDescriptionRef *formatDescriptionOut
) {
    (void)allocator;
    (void)imageBuffer;
    if (formatDescriptionOut != NULL) {
        *formatDescriptionOut = NULL;
    }
    return 0;
}

static inline CMFormatDescriptionRef CMSampleBufferGetFormatDescription(CMSampleBufferRef sbuf) {
    (void)sbuf;
    return NULL;
}

static inline CMBlockBufferRef CMSampleBufferGetDataBuffer(CMSampleBufferRef sbuf) {
    (void)sbuf;
    return NULL;
}

static inline size_t CMSampleBufferGetTotalSampleSize(CMSampleBufferRef sbuf) {
    (void)sbuf;
    return 0;
}

static inline CMTime CMSampleBufferGetPresentationTimeStamp(CMSampleBufferRef sbuf) {
    (void)sbuf;
    return kCMTimeInvalid;
}

static inline CMTime CMSampleBufferGetDecodeTimeStamp(CMSampleBufferRef sbuf) {
    (void)sbuf;
    return kCMTimeInvalid;
}

static inline CMTime CMSampleBufferGetDuration(CMSampleBufferRef sbuf) {
    (void)sbuf;
    return kCMTimeInvalid;
}

static inline OSStatus CMSampleBufferCreateForImageBuffer(
    CFAllocatorRef allocator,
    CVImageBufferRef imageBuffer,
    Boolean dataReady,
    const void *makeDataReadyCallback,
    void *refcon,
    CMVideoFormatDescriptionRef formatDescription,
    const CMSampleTimingInfo *sampleTiming,
    CMSampleBufferRef *sampleBufferOut
) {
    (void)allocator;
    (void)imageBuffer;
    (void)dataReady;
    (void)makeDataReadyCallback;
    (void)refcon;
    (void)formatDescription;
    (void)sampleTiming;
    if (sampleBufferOut != NULL) {
        *sampleBufferOut = NULL;
    }
    return 0;
}

static inline OSStatus CMSampleBufferGetSampleTimingInfoArray(
    CMSampleBufferRef sbuf,
    CMItemCount numSampleTimingEntries,
    CMSampleTimingInfo *timingArrayOut,
    CMItemCount *timingArrayEntriesNeededOut
) {
    (void)sbuf;
    if (timingArrayEntriesNeededOut != NULL) {
        *timingArrayEntriesNeededOut = 0;
    }
    if (numSampleTimingEntries > 0 && timingArrayOut != NULL) {
        timingArrayOut[0].duration = kCMTimeInvalid;
        timingArrayOut[0].presentationTimeStamp = kCMTimeInvalid;
        timingArrayOut[0].decodeTimeStamp = kCMTimeInvalid;
    }
    return 0;
}

static inline OSStatus CMSampleBufferCreateCopyWithNewTiming(
    CFAllocatorRef allocator,
    CMSampleBufferRef originalSBuf,
    CMItemCount numSampleTimingEntries,
    const CMSampleTimingInfo *sampleTimingArray,
    CMSampleBufferRef *sampleBufferOut
) {
    (void)allocator;
    (void)numSampleTimingEntries;
    (void)sampleTimingArray;
    if (sampleBufferOut != NULL) {
        *sampleBufferOut = originalSBuf;
    }
    return 0;
}

#endif
