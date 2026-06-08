#ifndef QUILL_OBJC_APPKIT_H
#define QUILL_OBJC_APPKIT_H

#include <Foundation/Foundation.h>

typedef struct CGPoint {
    CGFloat x;
    CGFloat y;
} CGPoint;

typedef struct CGSize {
    CGFloat width;
    CGFloat height;
} CGSize;

typedef struct CGRect {
    CGPoint origin;
    CGSize size;
} CGRect;

#if defined(__OBJC__)
@class NSColor;
@class NSImage;
@class NSView;
@class NSWindow;

@interface NSColor : NSObject
@end

@interface NSImage : NSObject
@end

@interface NSView : NSObject
@property (nonatomic, readonly) NSArray<NSView *> *subviews;
@property (nonatomic, readonly) NSString *className;
@end

@interface NSWindow : NSObject
@end
#endif

typedef CGPoint NSPoint;
typedef CGSize NSSize;
typedef CGRect NSRect;

#endif
