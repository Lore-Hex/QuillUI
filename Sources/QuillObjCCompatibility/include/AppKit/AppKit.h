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
@class NSWorkspace;

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
@end

@interface NSImage : NSObject
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

typedef CGPoint NSPoint;
typedef CGSize NSSize;
typedef CGRect NSRect;

#endif
