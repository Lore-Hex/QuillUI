#ifndef QUILL_OBJC_CORETEXT_H
#define QUILL_OBJC_CORETEXT_H

#include <Foundation/Foundation.h>

typedef const struct __CTLine *CTLineRef;
typedef CTLineRef CTLine;

#if defined(__OBJC__)
static inline CTLineRef CTLineCreateWithAttributedString(id attributedString) {
    (void)attributedString;
    return (CTLineRef)1;
}
#endif

static inline CFIndex CTLineGetGlyphCount(CTLineRef line) {
    return line == NULL ? 0 : 1;
}

#endif
