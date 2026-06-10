#ifndef QUILL_OBJC_ACCELERATE_H
#define QUILL_OBJC_ACCELERATE_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef unsigned long vImagePixelCount;
typedef unsigned long vImage_Flags;
typedef long vImage_Error;

typedef struct {
    void *data;
    vImagePixelCount height;
    vImagePixelCount width;
    size_t rowBytes;
} vImage_Buffer;

static const vImage_Flags kvImageEdgeExtend = 1UL << 1;
static const vImage_Error kvImageNoError = 0;

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

#endif
