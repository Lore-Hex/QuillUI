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

typedef CGPoint NSPoint;
typedef CGSize NSSize;
typedef CGRect NSRect;

static inline CGPoint CGPointMake(CGFloat x, CGFloat y) {
    CGPoint point = { x, y };
    return point;
}

static inline CGSize CGSizeMake(CGFloat width, CGFloat height) {
    CGSize size = { width, height };
    return size;
}

static const CGSize CGSizeZero = { 0, 0 };

static inline BOOL CGSizeEqualToSize(CGSize lhs, CGSize rhs) {
    return lhs.width == rhs.width && lhs.height == rhs.height;
}

static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    CGRect rect = { CGPointMake(x, y), CGSizeMake(width, height) };
    return rect;
}

typedef void *CGContextRef;
typedef const void *CGColorRef;
typedef int CGLineCap;
typedef int CGLineJoin;

static const CGLineCap kCGLineCapButt = 0;
static const CGLineCap kCGLineCapRound = 1;
static const CGLineCap kCGLineCapSquare = 2;
static const CGLineJoin kCGLineJoinMiter = 0;
static const CGLineJoin kCGLineJoinRound = 1;
static const CGLineJoin kCGLineJoinBevel = 2;

static inline void CGContextTranslateCTM(CGContextRef context, CGFloat tx, CGFloat ty) { (void)context; (void)tx; (void)ty; }
static inline void CGContextScaleCTM(CGContextRef context, CGFloat sx, CGFloat sy) { (void)context; (void)sx; (void)sy; }
static inline void CGContextClearRect(CGContextRef context, CGRect rect) { (void)context; (void)rect; }
static inline void CGContextFillRect(CGContextRef context, CGRect rect) { (void)context; (void)rect; }
static inline void CGContextSetFillColorWithColor(CGContextRef context, CGColorRef color) { (void)context; (void)color; }
static inline void CGContextSetStrokeColorWithColor(CGContextRef context, CGColorRef color) { (void)context; (void)color; }
static inline void CGContextBeginPath(CGContextRef context) { (void)context; }
static inline void CGContextMoveToPoint(CGContextRef context, CGFloat x, CGFloat y) { (void)context; (void)x; (void)y; }
static inline void CGContextAddCurveToPoint(CGContextRef context, CGFloat cp1x, CGFloat cp1y, CGFloat cp2x, CGFloat cp2y, CGFloat x, CGFloat y) {
    (void)context; (void)cp1x; (void)cp1y; (void)cp2x; (void)cp2y; (void)x; (void)y;
}
static inline void CGContextAddLineToPoint(CGContextRef context, CGFloat x, CGFloat y) { (void)context; (void)x; (void)y; }
static inline void CGContextClosePath(CGContextRef context) { (void)context; }
static inline void CGContextEOFillPath(CGContextRef context) { (void)context; }
static inline void CGContextFillPath(CGContextRef context) { (void)context; }
static inline void CGContextStrokePath(CGContextRef context) { (void)context; }
static inline void CGContextSetMiterLimit(CGContextRef context, CGFloat limit) { (void)context; (void)limit; }
static inline void CGContextSetLineWidth(CGContextRef context, CGFloat width) { (void)context; (void)width; }
static inline void CGContextSetLineCap(CGContextRef context, CGLineCap cap) { (void)context; (void)cap; }
static inline void CGContextSetLineJoin(CGContextRef context, CGLineJoin join) { (void)context; (void)join; }

#if defined(__OBJC__)
@class NSColor;
@class NSImage;
@class NSBitmapImageRep;
@class NSView;
@class NSWindow;
@class NSWorkspace;
@class NSGraphicsContext;

typedef NSString *NSColorSpaceName;
static NSColorSpaceName const NSCalibratedRGBColorSpace = @"NSCalibratedRGBColorSpace";

typedef NSUInteger NSEventModifierFlags;

static const NSEventModifierFlags NSEventModifierFlagCapsLock = 1UL << 16;
static const NSEventModifierFlags NSEventModifierFlagShift = 1UL << 17;
static const NSEventModifierFlags NSEventModifierFlagControl = 1UL << 18;
static const NSEventModifierFlags NSEventModifierFlagOption = 1UL << 19;
static const NSEventModifierFlags NSEventModifierFlagCommand = 1UL << 20;
static const NSEventModifierFlags NSAlphaShiftKeyMask = 1UL << 16;
static const NSEventModifierFlags NSShiftKeyMask = 1UL << 17;
static const NSEventModifierFlags NSControlKeyMask = 1UL << 18;
static const NSEventModifierFlags NSAlternateKeyMask = 1UL << 19;
static const NSEventModifierFlags NSCommandKeyMask = 1UL << 20;

@interface NSColor : NSObject
+ (instancetype)clearColor;
+ (instancetype)blackColor;
+ (instancetype)whiteColor;
- (NSColor *)colorWithAlphaComponent:(CGFloat)alpha;
@property (nonatomic, readonly) CGColorRef CGColor;
@end

@interface NSImage : NSObject
- (instancetype)initWithSize:(NSSize)size;
- (void)addRepresentation:(NSBitmapImageRep *)imageRep;
- (void)lockFocus;
- (void)unlockFocus;
@end

@interface NSBitmapImageRep : NSObject
- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes
                              pixelsWide:(NSInteger)width
                              pixelsHigh:(NSInteger)height
                           bitsPerSample:(NSInteger)bps
                         samplesPerPixel:(NSInteger)spp
                                hasAlpha:(BOOL)alpha
                                isPlanar:(BOOL)isPlanar
                          colorSpaceName:(NSColorSpaceName)colorSpaceName
                             bytesPerRow:(NSInteger)rowBytes
                            bitsPerPixel:(NSInteger)pixelBits;
@end

@interface NSGraphicsContext : NSObject
+ (instancetype)currentContext;
- (CGContextRef)graphicsPort;
@end

@interface NSView : NSObject
@property (nonatomic, readonly) NSArray<NSView *> *subviews;
@property (nonatomic, readonly) NSString *className;
@end

@interface NSWindow : NSObject
@end

@interface NSWorkspace : NSObject
+ (instancetype)sharedWorkspace;
- (BOOL)openURL:(NSURL *)url;
@end
#endif

#endif
