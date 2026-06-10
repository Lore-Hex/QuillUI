#ifndef QUILL_OBJC_COREGRAPHICS_H
#define QUILL_OBJC_COREGRAPHICS_H

#include <AppKit/AppKit.h>

static inline CGFloat CGRectGetMinX(CGRect rect) {
    return rect.origin.x;
}

static inline CGFloat CGRectGetMinY(CGRect rect) {
    return rect.origin.y;
}

static inline CGFloat CGRectGetMaxX(CGRect rect) {
    return rect.origin.x + rect.size.width;
}

static inline CGFloat CGRectGetMaxY(CGRect rect) {
    return rect.origin.y + rect.size.height;
}

static inline CGFloat CGRectGetWidth(CGRect rect) {
    return rect.size.width;
}

static inline CGFloat CGRectGetHeight(CGRect rect) {
    return rect.size.height;
}

#endif
