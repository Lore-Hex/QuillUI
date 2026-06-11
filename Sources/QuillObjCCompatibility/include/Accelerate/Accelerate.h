#ifndef QUILL_OBJC_ACCELERATE_H
#define QUILL_OBJC_ACCELERATE_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef unsigned long vImagePixelCount;
typedef unsigned long vImage_Flags;
typedef long vImage_Error;
typedef int vImage_Flags32;

typedef struct {
    void *data;
    vImagePixelCount height;
    vImagePixelCount width;
    size_t rowBytes;
} vImage_Buffer;

static const vImage_Flags kvImageEdgeExtend = 1UL << 1;
static const vImage_Flags kvImageDoNotTile = 1UL << 4;
static const vImage_Flags kvImageBackgroundColorFill = 1UL << 5;
static const vImage_Error kvImageNoError = 0;

typedef struct {
    double a;
    double b;
    double c;
    double d;
    double tx;
    double ty;
} vImage_CGAffineTransform;

typedef struct {
    int opaque;
} vImage_ARGBToYpCbCr;

typedef struct {
    int opaque;
} vImage_YpCbCrToARGB;

typedef struct {
    uint8_t Yp_bias;
    uint8_t CbCr_bias;
    uint8_t YpRangeMax;
    uint8_t CbCrRangeMax;
    uint8_t YpMax;
    uint8_t YpMin;
    uint8_t CbCrMax;
    uint8_t CbCrMin;
} vImage_YpCbCrPixelRange;

static const int kvImageARGB8888 = 0;
static const int kvImage420Yp8_Cb8_Cr8 = 1;
static const int kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2 = 0;
static const int kvImage_YpCbCrToARGBMatrix_ITU_R_709_2 = 0;
static const int kvImage_YpCbCrToARGBMatrix_ITU_R_601_4 = 1;

static inline vImage_Error vImageBoxConvolve_ARGB8888(
    const vImage_Buffer *src,
    const vImage_Buffer *dest,
    void *tempBuffer,
    vImagePixelCount srcOffsetToROI_X,
    vImagePixelCount srcOffsetToROI_Y,
    uint32_t kernel_height,
    uint32_t kernel_width,
    const void *backgroundColor,
    vImage_Flags flags
) {
    (void)tempBuffer;
    (void)srcOffsetToROI_X;
    (void)srcOffsetToROI_Y;
    (void)kernel_height;
    (void)kernel_width;
    (void)backgroundColor;
    (void)flags;
    if (src == NULL || dest == NULL || src->data == NULL || dest->data == NULL) {
        return -1;
    }
    vImagePixelCount rows = src->height < dest->height ? src->height : dest->height;
    size_t bytes = src->rowBytes < dest->rowBytes ? src->rowBytes : dest->rowBytes;
    for (vImagePixelCount row = 0; row < rows; row++) {
        const char *srcRow = (const char *)src->data + row * src->rowBytes;
        char *destRow = (char *)dest->data + row * dest->rowBytes;
        memcpy(destRow, srcRow, bytes);
    }
    return kvImageNoError;
}

static inline vImage_Error vImageScale_ARGB8888(
    const vImage_Buffer *src,
    const vImage_Buffer *dest,
    void *tempBuffer,
    vImage_Flags flags
) {
    (void)tempBuffer;
    (void)flags;
    if (src == NULL || dest == NULL || src->data == NULL || dest->data == NULL) {
        return -1;
    }
    vImagePixelCount rows = src->height < dest->height ? src->height : dest->height;
    size_t bytes = src->rowBytes < dest->rowBytes ? src->rowBytes : dest->rowBytes;
    for (vImagePixelCount row = 0; row < rows; row++) {
        const char *srcRow = (const char *)src->data + row * src->rowBytes;
        char *destRow = (char *)dest->data + row * dest->rowBytes;
        memcpy(destRow, srcRow, bytes);
    }
    return kvImageNoError;
}

static inline vImage_Error vImageAffineWarpCG_ARGB8888(
    const vImage_Buffer *src,
    const vImage_Buffer *dest,
    const void *tempBuffer,
    const vImage_CGAffineTransform *transform,
    const uint8_t *backColor,
    vImage_Flags flags
) {
    (void)tempBuffer;
    (void)transform;
    (void)backColor;
    return vImageScale_ARGB8888(src, dest, NULL, flags);
}

static inline vImage_Error vImagePermuteChannels_ARGB8888(
    const vImage_Buffer *src,
    const vImage_Buffer *dest,
    const uint8_t permuteMap[4],
    vImage_Flags flags
) {
    (void)permuteMap;
    return vImageScale_ARGB8888(src, dest, NULL, flags);
}

static inline vImage_Error vImagePremultiplyData_ARGB8888(
    const vImage_Buffer *src,
    const vImage_Buffer *dest,
    vImage_Flags flags
) {
    return vImageScale_ARGB8888(src, dest, NULL, flags);
}

static inline vImage_Error vImageUnpremultiplyData_ARGB8888(
    const vImage_Buffer *src,
    const vImage_Buffer *dest,
    vImage_Flags flags
) {
    return vImageScale_ARGB8888(src, dest, NULL, flags);
}

static inline vImage_Error vImageConvert_ARGBToYpCbCr_GenerateConversion(
    int matrix,
    const vImage_YpCbCrPixelRange *pixelRange,
    vImage_ARGBToYpCbCr *outInfo,
    int sourceFormat,
    int destinationFormat,
    vImage_Flags flags
) {
    (void)matrix;
    (void)pixelRange;
    (void)outInfo;
    (void)sourceFormat;
    (void)destinationFormat;
    (void)flags;
    return kvImageNoError;
}

static inline vImage_Error vImageConvert_YpCbCrToARGB_GenerateConversion(
    int matrix,
    const vImage_YpCbCrPixelRange *pixelRange,
    vImage_YpCbCrToARGB *outInfo,
    int sourceFormat,
    int destinationFormat,
    vImage_Flags flags
) {
    (void)matrix;
    (void)pixelRange;
    (void)outInfo;
    (void)sourceFormat;
    (void)destinationFormat;
    (void)flags;
    return kvImageNoError;
}

static inline vImage_Error vImageConvert_ARGB8888To420Yp8_CbCr8(
    const vImage_Buffer *src,
    const vImage_Buffer *destYp,
    const vImage_Buffer *destCbCr,
    const vImage_ARGBToYpCbCr *info,
    const uint8_t *permuteMap,
    vImage_Flags flags
) {
    (void)src;
    (void)info;
    (void)permuteMap;
    (void)flags;
    if (destYp != NULL && destYp->data != NULL) {
        memset(destYp->data, 0, destYp->rowBytes * destYp->height);
    }
    if (destCbCr != NULL && destCbCr->data != NULL) {
        memset(destCbCr->data, 128, destCbCr->rowBytes * destCbCr->height);
    }
    return kvImageNoError;
}

static inline vImage_Error vImageConvert_420Yp8_CbCr8ToARGB8888(
    const vImage_Buffer *srcYp,
    const vImage_Buffer *srcCbCr,
    ...
) {
    (void)srcYp;
    (void)srcCbCr;
    return kvImageNoError;
}

static inline vImage_Error vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(
    const vImage_Buffer *srcYp,
    const vImage_Buffer *srcCb,
    const vImage_Buffer *srcCr,
    const vImage_Buffer *dest,
    const vImage_YpCbCrToARGB *info,
    const uint8_t *permuteMap,
    uint8_t alpha,
    vImage_Flags flags
) {
    (void)srcYp;
    (void)srcCb;
    (void)srcCr;
    (void)info;
    (void)permuteMap;
    (void)alpha;
    (void)flags;
    if (dest != NULL && dest->data != NULL) {
        memset(dest->data, 0, dest->rowBytes * dest->height);
    }
    return kvImageNoError;
}

#endif
